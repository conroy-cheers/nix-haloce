{
  pkgs,
  overlayfsLib,
  packageScopes,
}:
let
  lib = pkgs.lib;
in
{
  halo-custom-edition = {
    variants = {
      x86 = modules: pkgs.callPackage ../packages/halo-custom-edition {
        inherit modules overlayfsLib;
        basePackage = packageScopes.installSupport.basePackage;
        dxvkPackage = lib.attrByPath [ "runtimeSupport" "dxvkPackage" ] null packageScopes;
      };
    };
  };
}
