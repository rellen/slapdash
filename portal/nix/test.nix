# NixOS VM test for services.ramshackle: the service starts against a local
# PostgreSQL, runs its migrations, generates its secrets on first boot and
# serves the home page, and root can be onboarded with ramshackle-eval.
{ self }:
{
  name = "ramshackle";

  nodes.machine =
    { pkgs, ... }:
    {
      imports = [ self.nixosModules.ramshackle ];

      virtualisation.memorySize = 2048;
      environment.systemPackages = [ pkgs.curl ];

      # Test-only master key. Real deployments keep it out of the Nix store,
      # for example with sops-nix or agenix.
      environment.etc."ramshackle/master-key".text = "dGVzdC1tYXN0ZXIta2V5LTAxMjM0NTY3ODlhYmNkZWY=";

      services.postgresql.package = pkgs.postgresql_17;

      services.ramshackle = {
        enable = true;
        masterKeyFile = "/etc/ramshackle/master-key";
      };
    };

  testScript = ''
    machine.wait_for_unit("ramshackle.service")
    machine.wait_for_open_port(4000)
    machine.succeed("curl --fail --silent http://localhost:4000/ | grep -i '<html'")
    machine.succeed(
      "sudo -u postgres psql -d ramshackle -tAc 'SELECT count(*) FROM schema_migrations' | grep -qv '^0$'"
    )

    # First boot generated and stored the secrets.
    machine.succeed(
      "sudo -u postgres psql -d ramshackle -tAc 'SELECT count(*) FROM instance_boot_secrets' | grep -q '^1$'"
    )

    # Distribution listens on loopback only, and rpc reaches the server.
    machine.succeed("ss -ltnH '( sport = :4369 )' | grep -q '127.0.0.1:4369'")
    machine.fail("ss -ltnpH | grep -E 'beam|epmd' | grep -v -E '127\\.0\\.0\\.1:|\\[::1\\]:|:4000 '")
    output = machine.succeed("ramshackle-rpc 'IO.puts(node())'")
    assert "ramshackle@127.0.0.1" in output, output
    machine.succeed("stat -c '%U %a' /var/lib/ramshackle/cookie | grep -q '^ramshackle 600$'")

    # Onboard root without email.
    output = machine.succeed(
      "ramshackle-eval 'Ramshackle.Release.create_root(\"root@example.com\", public_url: \"http://localhost:4000\")'"
    )
    assert "root@example.com is now root." in output, output
    link = next(line.strip() for line in output.splitlines() if "/magic_link/" in line)
    page = machine.succeed(f"curl --fail --silent '{link}'")
    assert "Sign in to Ramshackle" in page, page
  '';
}
