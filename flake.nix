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
    extra-substituters = [
      "https://cache.corncheese.org/nix-cache"
      "https://nix-gaming.cachix.org"
    ];
    extra-trusted-public-keys = [
      "nix-cache:kWK431WqAGFMswlTp4Y6XEC3eNTE0awBqtI/PWylnTg="
      "nix-gaming.cachix.org-1:nbjlureqMbRAxR1gJ/f3hxemL9svXaZF/Ees8vCUUs4="
    ];
  };

  outputs = inputs @ {
    self,
    nixpkgs,
    ...
  }: let
    lib = nixpkgs.lib;
    systems = ["x86_64-linux" "aarch64-linux"];
    forAllSystems = lib.genAttrs systems;
    mkPkgsFor = system:
      import nixpkgs {
        inherit system;
        overlays = [self.overlays.default];
      };
    pkgsFor = forAllSystems mkPkgsFor;
    packageSets = forAllSystems (system: pkgsFor.${system}.nix-haloce);
    x86System = "x86_64-linux";
  in {
    overlays.default = final: _prev: {
      nix-haloce = import ./pkgs/top-level {
        pkgs = final;
        inherit inputs;
      };
    };

    legacyPackages = forAllSystems (
      system: {
        nix-haloce = lib.dontRecurseIntoAttrs packageSets.${system};
      }
    );

    packages = forAllSystems (
      system:
        packageSets.${system}.packages
        // lib.optionalAttrs (system == x86System) {
          haloce-live-iso = self.nixosConfigurations.haloce-live.config.system.build.isoImage;
          haloce-usb-image = self.nixosConfigurations.haloce-live.config.system.build.image;
          haloce-headless-test = import ./nixos/tests/headless.nix {
            pkgs = pkgsFor.${system};
            inherit self;
          };
          haloce-ubuntu-24-04-headless-test = import ./tests/ubuntu-24.04-headless.nix {
            pkgs = pkgsFor.${system};
            haloPackage = self.packages.${system}.halo-custom-edition;
          };
        }
    );

    apps = forAllSystems (system: packageSets.${system}.apps);

    checks = forAllSystems (
      system:
        lib.optionalAttrs (system == x86System) {
          haloce-headless = self.packages.${system}.haloce-headless-test;
          haloce-ubuntu-24-04-headless = self.packages.${system}.haloce-ubuntu-24-04-headless-test;
        }
    );

    nixosModules = {
      haloce-kiosk = ./nixos/modules/haloce-kiosk.nix;
    };

    nixosConfigurations.haloce-live = lib.nixosSystem {
      system = x86System;
      specialArgs = {inherit inputs self;};
      modules = [
        {
          nixpkgs.overlays = [self.overlays.default];
        }
        ./nixos/haloce-live.nix
      ];
    };

    hydraJobs = {
      x86_64-linux = self.packages.x86_64-linux // self.checks.x86_64-linux;
    };

    inherit inputs;
  };
}
