{
  lib,
  overlayfsLib,
  runtime,
  dxvk,
}:
let
  installPath32 =
    if runtime.windowsArch == "wow64" then
      "windows/syswow64"
    else
      "windows/system32";
  installPath64 = "windows/system32";
  dllsToInstall = [
    "d3d8.dll"
    "d3d9.dll"
    "d3d10core.dll"
    "d3d11.dll"
    "dxgi.dll"
  ];
in
overlayfsLib.mkWindowsPackage {
  inherit runtime;
  pname = "dxvk-overlay";
  inherit (dxvk) version;
  src = lib.getBin dxvk;
  unshareInstall =
    { ... }:
    ''
      cp $src/x32/* "$WINEPREFIX/drive_c/${installPath32}"
    ''
    + lib.optionalString (runtime.windowsArch == "wow64") ''
      cp $src/x64/* "$WINEPREFIX/drive_c/${installPath64}"
    '';
  extraPathsToInclude =
    (map (dll: installPath32 + "/" + dll) dllsToInstall)
    ++ lib.optionals (runtime.windowsArch == "wow64") (map (dll: installPath64 + "/" + dll) dllsToInstall);
  packageName = "dxvk";
  runtimeEnvVars = {
    WINEDLLOVERRIDES = "d3d8,d3d9,d3d10core,d3d11,dxgi=n";
  };
}
