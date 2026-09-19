{
  description = "WeatherLockscreen dev environment (lua5.1 for syntax checks, gettext for translations)";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      packages = forAllSystems (pkgs: {
        default = pkgs.buildEnv {
          name = "weatherlockscreen-tools";
          paths = [ pkgs.lua5_1 pkgs.gettext pkgs.bash pkgs.rsync pkgs.zip pkgs.unzip ];
        };
      });

      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          name = "weatherlockscreen-dev";
          buildInputs = [ pkgs.lua5_1 pkgs.gettext pkgs.bash pkgs.rsync pkgs.zip pkgs.unzip ];
          shellHook = ''
            echo "WeatherLockscreen dev shell: luac $(luac -v 2>&1 | head -n1), $(msgfmt --version | head -n1)"
          '';
        };
      });
    };
}
