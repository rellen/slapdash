# The Slapdash server as a Mix release.
#
# `beamPackages` must be a package set built on the Erlang/OTP and Elixir
# versions the project targets (see the root flake.nix).
{
  lib,
  beamPackages,
  esbuild,
  removeReferencesTo,
}:

let
  root = ../.;

  # Read the version from mix.exs so it cannot drift from the Mix project.
  version = builtins.head (
    builtins.match ''.*[[:space:]]version: "([^"]+)".*'' (builtins.readFile (root + "/mix.exs"))
  );

  # Only the files a release build reads. Tests, build output and editor
  # state stay out, so changing them does not trigger a rebuild.
  src = lib.fileset.toSource {
    inherit root;
    fileset = lib.fileset.unions [
      (root + "/mix.exs")
      (root + "/mix.lock")
      (root + "/config")
      (root + "/lib")
      (root + "/priv")
      (root + "/assets")
      (root + "/rel")
    ];
  };

  # Hex and git dependencies, fetched by `mix deps.get`. When mix.lock
  # changes, set `hash` to lib.fakeHash, build, and copy the hash Nix reports.
  mixFodDeps = beamPackages.fetchMixDeps {
    pname = "slapdash-mix-deps";
    inherit version;
    src = lib.fileset.toSource {
      inherit root;
      fileset = lib.fileset.unions [
        (root + "/mix.exs")
        (root + "/mix.lock")
        (root + "/config")
      ];
    };
    hash = "sha256-592/DaQnNGQcXnZ9Vrlnx58vKKKzbAkR38XDhp21rLk=";
  };
in
beamPackages.mixRelease {
  pname = "slapdash";
  inherit version src mixFodDeps;

  # The :esbuild Mix package downloads its binary on first use. Point it at
  # the nixpkgs build instead, since the build has no network access.
  env.MIX_ESBUILD_PATH = lib.getExe esbuild;

  # Build and digest the static assets once the application has compiled, so
  # the colocated hooks and CSS that compilation extracts are available.
  postBuild = ''
    mix do deps.loadpaths --no-deps-check + assets.deploy
  '';

  # config.exs bakes MIX_ESBUILD_PATH into the release's sys.config. esbuild
  # is only used at build time, so drop the reference to keep it out of the
  # runtime closure.
  nativeBuildInputs = [ removeReferencesTo ];
  postFixup = ''
    remove-references-to -t ${esbuild} "$out/releases/${version}/sys.config"
  '';
  disallowedReferences = [ esbuild ];

  passthru = {
    inherit mixFodDeps;
  };

  meta = {
    description = "Self-hosted manager for software repositories and the applications running from them";
    homepage = "https://github.com/rellen/slapdash";
    license = lib.licenses.asl20;
    mainProgram = "slapdash";
    platforms = lib.platforms.unix;
  };
}
