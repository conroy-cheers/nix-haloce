{
  description = "Fully reproducible Halo Custom Edition for Linux";

  inputs = {
    nixpkgs = {
      url = "github:nixos/nixpkgs?ref=nixos-unstable";
    };
    nix-overlayfs = {
      url = "github:conroy-cheers/nix-overlayfs";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  nixConfig = {
    allowInsecure = true;
    extra-substituters = [ "https://nix-gaming.cachix.org" ];
    extra-trusted-public-keys = [
      "nix-gaming.cachix.org-1:nbjlureqMbRAxR1gJ/f3hxemL9svXaZF/Ees8vCUUs4="
    ];
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      ...
    }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
      mkPkgsFor =
        system:
        import nixpkgs {
          inherit system;
          overlays = [ self.overlays.default ];
        };
      pkgsFor = forAllSystems mkPkgsFor;
      packageSets = forAllSystems (system: pkgsFor.${system}.nix-haloce);
    in
    {
      overlays.default = final: _prev: {
        nix-haloce = import ./pkgs/top-level {
          pkgs = final;
          inherit inputs;
        };
      };

      legacyPackages = forAllSystems (
        system:
        {
          nix-haloce = nixpkgs.lib.dontRecurseIntoAttrs packageSets.${system};
        }
      );

      packages = forAllSystems (system: packageSets.${system}.packages);

      apps = forAllSystems (system: packageSets.${system}.apps);

      inherit inputs;
    };
}
