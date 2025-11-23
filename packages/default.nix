{
  pkgs,
  nix-overlayfs,
  overlayfsLib,
}:
{
  halo-custom-edition = pkgs.callPackage ./halo-custom-edition {
    inherit (nix-overlayfs) wineGeWin32Modules;
    inherit overlayfsLib;
  };
}
