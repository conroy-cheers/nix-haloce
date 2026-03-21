{
  pkgs,
  inputs,
}:
let
  system = pkgs.stdenv.hostPlatform.system;
  overlayfsPackages = inputs.nix-overlayfs.legacyPackages.${system}.nix-overlayfs;
  overlayfsLib = overlayfsPackages.lib;
  packageScopes = import ../../packages {
    inherit (pkgs) lib;
    inherit pkgs overlayfsLib inputs;
    nix-overlayfs = overlayfsPackages;
  };
  appsListing = import ../../apps {
    inherit pkgs packageScopes overlayfsLib;
  };
  derivationPackageScopes = pkgs.lib.filterAttrs (_: v: pkgs.lib.isDerivation v) packageScopes;
in
{
  lib = overlayfsLib;
  packages = derivationPackageScopes // appsListing.packages;
  apps = appsListing.apps;

  moduleScopes = packageScopes;
  packageVariants = appsListing.packageVariants;
  appVariants = appsListing.appVariants;
}
