{
  pkgs,
  nix-overlayfs,
  overlayfsLib,
}: rec {
  halo-custom-edition = pkgs.callPackage ./halo-custom-edition {
    inherit (nix-overlayfs) wineGeWin32Modules;
    inherit (nix-overlayfs) wineTkgWow64Modules;
    inherit overlayfsLib;
  };
  default = halo-custom-edition;
}
