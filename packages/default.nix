{
  lib,
  pkgs,
  inputs,
  nix-overlayfs,
  overlayfsLib,
}:
let
  isAarch64 = pkgs.stdenv.hostPlatform.isAarch64;
  dxvkPackage =
    let
      dxvkPkgs =
        if isAarch64 then
          import inputs.nixpkgs {
            system = pkgs.stdenv.hostPlatform.system;
            config.allowUnsupportedSystem = true;
          }
        else
          pkgs;
    in
    dxvkPkgs.dxvk;

  nativeInstallLayer =
    if !isAarch64 then
      pkgs.callPackage ./halo-custom-edition/install-layer.nix {
        inherit overlayfsLib;
        modules = nix-overlayfs.moduleScopes.nativeModules;
        enableLegacyPatch = true;
        enableAarch64RuntimePatches = false;
      }
    else
      null;

  aarch64InstallLayer =
    if isAarch64 then
      pkgs.callPackage ./halo-custom-edition/install-layer.nix {
        inherit overlayfsLib;
        modules = nix-overlayfs.moduleScopes.x64FexModules;
        enableLegacyPatch = false;
        enableAarch64RuntimePatches = true;
      }
    else
      null;
in
lib.optionalAttrs (!isAarch64) {
  nativeModules = nix-overlayfs.moduleScopes.nativeModules;
  installSupport = {
    basePackage = nativeInstallLayer.basePackage;
  };
  runtimeSupport = {
    inherit dxvkPackage;
  };
}
// lib.optionalAttrs isAarch64 {
  x64FexModules = nix-overlayfs.moduleScopes.x64FexModules;
  installSupport = {
    basePackage = aarch64InstallLayer.basePackage;
  };
  runtimeSupport = {
    inherit dxvkPackage;
  };
}
