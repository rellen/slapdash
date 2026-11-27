# NixOS VM test for services.slapdash: the service starts against a local
# PostgreSQL, runs its migrations, generates its secrets on first boot and
# serves the home page, and root can be onboarded with slapdash-eval.
{ self }:
{
  name = "slapdash";

  nodes.machine =
    { pkgs, ... }:
    {
      imports = [ self.nixosModules.slapdash ];

      virtualisation.memorySize = 2048;
      environment.systemPackages = [ pkgs.curl ];

      # Test-only master key. Real deployments keep it out of the Nix store,
      # for example with sops-nix or agenix.
      environment.etc."slapdash/master-key".text = "dGVzdC1tYXN0ZXIta2V5LTAxMjM0NTY3ODlhYmNkZWY=";

      services.postgresql.package = pkgs.postgresql_17;

      services.slapdash = {
        enable = true;
        masterKeyFile = "/etc/slapdash/master-key";
      };
    };

  testScript = ''
    machine.wait_for_unit("slapdash.service")
    machine.wait_for_open_port(4000)
    machine.succeed("curl --fail --silent http://localhost:4000/ | grep -i '<html'")
    machine.succeed(
      "sudo -u postgres psql -d slapdash -tAc 'SELECT count(*) FROM schema_migrations' | grep -qv '^0$'"
    )

    # First boot generated and stored the secrets.
    machine.succeed(
      "sudo -u postgres psql -d slapdash -tAc 'SELECT count(*) FROM instance_boot_secrets' | grep -q '^1$'"
    )

    # Oban has its tables, and the webhook endpoint answers without a session.
    machine.succeed(
      "sudo -u postgres psql -d slapdash -tAc 'SELECT count(*) FROM oban_jobs' | grep -q '^0$'"
    )
    status = machine.succeed(
      "curl --silent --output /dev/null --write-out '%{http_code}' -X POST "
      "-H 'content-type: application/json' --data '{}' "
      "http://localhost:4000/webhooks/00000000-0000-0000-0000-000000000000"
    )
    assert status == "404", status

    # Distribution listens on loopback only, and rpc reaches the server.
    machine.succeed("ss -ltnH '( sport = :4369 )' | grep -q '127.0.0.1:4369'")
    machine.fail("ss -ltnpH | grep -E 'beam|epmd' | grep -v -E '127\\.0\\.0\\.1:|\\[::1\\]:|:4000 '")
    output = machine.succeed("slapdash-rpc 'IO.puts(node())'")
    assert "slapdash@127.0.0.1" in output, output
    machine.succeed("stat -c '%U %a' /var/lib/slapdash/cookie | grep -q '^slapdash 600$'")

    # Onboard root without email.
    output = machine.succeed(
      "slapdash-eval 'Slapdash.Release.create_root(\"root@example.com\", public_url: \"http://localhost:4000\")'"
    )
    assert "root@example.com is now root." in output, output
    link = next(line.strip() for line in output.splitlines() if "/magic_link/" in line)
    page = machine.succeed(f"curl --fail --silent '{link}'")
    assert "Sign in to Slapdash" in page, page
  '';
}
