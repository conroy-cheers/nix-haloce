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
    {
      nixpkgs,
      ...
    }@inputs:
    let
      transposeAttrs =
        attrs:
        nixpkgs.lib.foldlAttrs (
          acc: outer: inner:
          nixpkgs.lib.recursiveUpdate acc (nixpkgs.lib.mapAttrs (k: v: { ${outer} = v; }) inner)
        ) { } attrs;

      generateSystems = (
        {
          self,
          nixpkgs,
          nix-overlayfs,
        }@inputs:
        nixpkgs.lib.genAttrs [ "x86_64-linux" ] (
          system:
          let
            p = {
              inherit self;
              pkgs = nixpkgs.legacyPackages.${system};
              nix-overlayfs = nix-overlayfs.packages.${system};
            };

            packages = import ./packages {
              inherit (p) pkgs nix-overlayfs;
              overlayfsLib = (nix-overlayfs.lib.${system});
            };
          in
          {
            inherit packages;
            apps = import ./apps { inherit packages; };
          }
        )
      );
    in
    (transposeAttrs (generateSystems inputs))
    // {
      inherit inputs;
    };
}
