# Development shell for portal/: the Erlang/OTP and Elixir versions from
# AGENTS.md, PostgreSQL, and esbuild, which the Mix project would otherwise
# download.
{
  lib,
  stdenv,
  mkShell,
  beamPackages,
  esbuild,
  postgresql_17,
  inotify-tools,
  nixfmt,
}:

mkShell {
  packages = [
    beamPackages.erlang
    beamPackages.elixir
    beamPackages.elixir-ls
    esbuild
    postgresql_17
    nixfmt
  ]
  # Phoenix's live reloader watches files with inotify on Linux.
  ++ lib.optionals stdenv.hostPlatform.isLinux [ inotify-tools ];

  env = {
    # Use the nixpkgs esbuild rather than letting `mix assets.setup`
    # download an unpatched one, which does not run on NixOS.
    MIX_ESBUILD_PATH = lib.getExe esbuild;
    # Keep IEx history between sessions.
    ERL_AFLAGS = "-kernel shell_history enabled";
  };
}
