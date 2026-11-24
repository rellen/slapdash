{
  description = "Slapdash: self-hosted software bots for code repositories and the applications running from them";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      inherit (nixpkgs) lib;

      linuxSystems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      systems = linuxSystems ++ [
        "aarch64-darwin"
      ];

      forSystems = systems: f: lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});

      # The Erlang/OTP and Elixir versions from the toolchain table in
      # AGENTS.md. Change them here and in AGENTS.md together.
      #
      # The release uses `beam_minimal` (no wxWidgets, ODBC or systemd), which
      # keeps the server closure small. The development shell uses the full
      # `beam` so tools such as :observer work.
      beamPackagesFor =
        beam: beam.packages.erlang_29.overrideScope (_final: prev: { elixir = prev.elixir_1_20; });
    in
    {
      packages =
        lib.recursiveUpdate
          (forSystems systems (pkgs: rec {
            slapdash = pkgs.callPackage ./portal/nix/package.nix {
              beamPackages = beamPackagesFor pkgs.beam_minimal;
            };
            default = slapdash;
          }))
          (
            forSystems linuxSystems (pkgs: {
              container = pkgs.callPackage ./portal/nix/container.nix {
                slapdash = self.packages.${pkgs.stdenv.hostPlatform.system}.slapdash;
              };
            })
          );

      nixosModules = rec {
        slapdash = import ./portal/nix/module.nix { inherit self; };
        default = slapdash;
      };

      devShells = forSystems systems (pkgs: rec {
        portal = pkgs.callPackage ./portal/nix/shell.nix { beamPackages = beamPackagesFor pkgs.beam; };
        default = portal;
      });

      checks =
        lib.recursiveUpdate
          (forSystems systems (pkgs: {
            inherit (self.packages.${pkgs.stdenv.hostPlatform.system}) slapdash;
            formatting = pkgs.runCommand "check-nix-formatting" { nativeBuildInputs = [ pkgs.nixfmt ]; } ''
              cd ${self}
              nixfmt --check $(find . -name '*.nix')
              touch $out
            '';
          }))
          (
            forSystems linuxSystems (pkgs: {
              inherit (self.packages.${pkgs.stdenv.hostPlatform.system}) container;
              nixos-module = pkgs.testers.runNixOSTest (import ./portal/nix/test.nix { inherit self; });
            })
          );

      formatter = forSystems systems (pkgs: pkgs.nixfmt-tree);
    };
}
