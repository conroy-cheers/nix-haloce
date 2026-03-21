{
  lib,
  pkgs,
  inputs,
  nix-overlayfs,
  overlayfsLib,
}:
let
  isAarch64 = pkgs.stdenv.hostPlatform.isAarch64;
  pruneHaloBasePackage =
    basePackage:
    pkgs.stdenvNoCC.mkDerivation {
      pname = "${basePackage.pname}-runtime-data";
      inherit (basePackage) version;
      dontUnpack = true;
      installPhase = ''
      app_dir="$out/drive_c/Program Files (x86)/Microsoft Games"
      mkdir -p "$app_dir"

      cp -r "${basePackage}/drive_c/Program Files (x86)/Microsoft Games/Halo Custom Edition" "$app_dir/"
      '';
    };
  mkDxvkBinaryPackage =
    {
      version,
      hash,
    }:
    pkgs.stdenvNoCC.mkDerivation {
      pname = "dxvk";
      inherit version;
      src = pkgs.fetchzip {
        url = "https://github.com/doitsujin/dxvk/releases/download/v${version}/dxvk-${version}.tar.gz";
        inherit hash;
        stripRoot = false;
      };
      dontUnpack = true;
      installPhase = ''
        mkdir -p "$out"
        cp -r "$src/dxvk-${version}/x32" "$out/"
        cp -r "$src/dxvk-${version}/x64" "$out/"
      '';
    };
  x86Pkgs =
    if isAarch64 then
      import inputs.nixpkgs {
        system = "x86_64-linux";
      }
    else
      null;
  x86OverlayfsPackages =
    if isAarch64 then
      inputs.nix-overlayfs.legacyPackages.x86_64-linux.nix-overlayfs
    else
      null;
  dxvkPackages = {
    legacy = mkDxvkBinaryPackage {
      version = "1.10.3";
      hash = "sha256-7/mP7XrZpeV6SY5bPTQE8ehJEdSUC+stJh3cVqgyfWk=";
    };
    current = mkDxvkBinaryPackage {
      version = "2.7.1";
      hash = "sha256-gLvC5MxJom3LLBZw4Di+vUfZC1gykvyuyVgqcwZAgWg=";
    };
  };
  dxvkPackage = if isAarch64 then dxvkPackages.legacy else dxvkPackages.current;

  nativeInstallLayer =
    if !isAarch64 then
      pkgs.callPackage ./halo-custom-edition/install-layer.nix {
        inherit overlayfsLib;
        modules = nix-overlayfs.moduleScopes.nativeModules;
      }
    else
      null;

  aarch64InstallLayer =
    if isAarch64 then
      x86Pkgs.callPackage ./halo-custom-edition/install-layer.nix {
        overlayfsLib = x86OverlayfsPackages.lib;
        modules = x86OverlayfsPackages.moduleScopes.nativeModules;
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
    inherit dxvkPackage dxvkPackages;
  };
}
// lib.optionalAttrs isAarch64 {
  x64FexModules = nix-overlayfs.moduleScopes.x64FexModules;
  installSupport = {
    basePackage = pruneHaloBasePackage aarch64InstallLayer.basePackage;
  };
  runtimeSupport = {
    inherit dxvkPackage dxvkPackages;
  };
}
