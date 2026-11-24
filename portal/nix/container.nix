# OCI image of the Ramshackle server, for Docker, Podman and similar.
#
#   nix build .#container
#   docker load < result
#   docker run --rm -p 4000:4000 \
#     -e DATABASE_URL=ecto://user:pass@db/ramshackle \
#     -e RAMSHACKLE_MASTER_KEY=... \
#     ramshackle:<version>
#
# Generate the master key once with `openssl rand -base64 32` and keep it.
# The entrypoint runs pending migrations, then starts the server. The release
# commands are on PATH, so root is onboarded with
# `docker exec <container> ramshackle eval 'Ramshackle.Release.create_root(...)'`;
# see portal/README.md.
{
  lib,
  dockerTools,
  writeShellApplication,
  runCommand,
  cacert,
  ramshackle,
}:

let
  # Puts the release command on PATH as `ramshackle`, for `docker exec`. The
  # script resolves the symlink to find the release.
  releaseCommands = runCommand "ramshackle-commands" { } ''
    mkdir -p $out/bin
    ln -s ${lib.getBin ramshackle}/bin/ramshackle $out/bin/ramshackle
  '';

  entrypoint = writeShellApplication {
    name = "ramshackle-entrypoint";
    text = ''
      ${lib.getBin ramshackle}/bin/migrate
      exec ${lib.getBin ramshackle}/bin/server
    '';
  };
in
dockerTools.buildLayeredImage {
  name = "ramshackle";
  tag = ramshackle.version;

  contents = [
    dockerTools.fakeNss
    releaseCommands
  ];

  # The release writes its generated runtime configuration to RELEASE_TMP,
  # and the Nix store is read-only, so give it a writable /tmp.
  extraCommands = ''
    mkdir -m 1777 tmp
  '';

  config = {
    Entrypoint = [ (lib.getExe entrypoint) ];
    User = "nobody:nogroup";
    ExposedPorts."4000/tcp" = { };
    Env = [
      "LANG=C.UTF-8"
      "PORT=4000"
      "RELEASE_TMP=/tmp"
      # Erlang distribution on loopback only, so `docker exec <container>
      # ramshackle rpc ...` and `ramshackle remote` reach the server, and
      # nothing listens outside the container. The cookie is created on first
      # start and shared through /tmp.
      "RELEASE_DISTRIBUTION=name"
      "RELEASE_NODE=ramshackle@127.0.0.1"
      "RELEASE_COOKIE_FILE=/tmp/ramshackle-cookie"
      "ERL_EPMD_ADDRESS=127.0.0.1"
      "ELIXIR_ERL_OPTIONS=-kernel inet_dist_use_interface {127,0,0,1}"
      "SSL_CERT_FILE=${cacert}/etc/ssl/certs/ca-bundle.crt"
    ];
    Labels = {
      "org.opencontainers.image.source" = "https://github.com/rellen/ramshackle";
      "org.opencontainers.image.licenses" = "Apache-2.0";
      "org.opencontainers.image.version" = ramshackle.version;
    };
  };
}
