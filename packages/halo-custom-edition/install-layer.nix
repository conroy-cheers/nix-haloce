{
  lib,
  fetchurl,
  stdenvNoCC,
  p7zip,

  overlayfsLib,
  modules,
}:
let
  haloVersion = "1.0.10";
  installerVersion = "1.0.0";
  refinedVersion = "5.01";
  chimeraVersion = "1.0.0r1096.55407763";

  currentVersion = "01.00.00.0609";
  targetVersion = "01.00.10.0621";
  patchUpdateVersion = "1.10";
  haloRegistryKey = "Software\\Microsoft\\Microsoft Games\\Halo CE";
  haloInstallSuffix = "/Microsoft Games/Halo Custom Edition";
  runtime = modules.runtime;
  haloInstallDir = "${runtime.programFiles32Path}${haloInstallSuffix}";
  haloUpdateLocation = "C:\\Program Files (x86)\\Microsoft Games\\Halo Custom Edition";
  installedVersion = currentVersion;

  installOverlayDeps = with modules; [
    msvcp60
    msxml4
  ];

  renderScript = template: replacements:
    lib.replaceStrings
      (map (entry: entry.placeholder) replacements)
      (map (entry: entry.value) replacements)
      (builtins.readFile template);

  patchSrc = fetchurl {
    url = "https://web.archive.org/web/20141022155617/http://halo.bungie.net/images/games/halopc/patch/110/haloce-patch-1.0.10.exe";
    hash = "sha256-M4GPP1a33dyMYdZUr2VnycW5IgynXWrCOlJhEDgldQg=";
  };
  patchSrcWin = "Z:${lib.replaceStrings [ "/" ] [ "\\\\" ] (toString patchSrc)}";
  installerSrc = fetchurl {
    url = "http://vaporeon.io/hosted/halo/original_files/halocesetup_en_1.00.exe";
    hash = "sha256-ARsDthY0Vh18G2CQ5yKf4KLfQN4sKhS0WsjwRV1dmQ8=";
  };

  mkExtractedP7zipPayload =
    {
      pname,
      version,
      src,
    }:
    stdenvNoCC.mkDerivation {
      inherit pname version src;
      nativeBuildInputs = [ p7zip ];
      unpackPhase = ''
        runHook preUnpack

        7z x $src -o$out

        runHook postUnpack
      '';
    };

  refinedMaps = mkExtractedP7zipPayload {
    pname = "halo-refined-custom-edition";
    version = refinedVersion;
    src = fetchurl {
      url = "http://vaporeon.io/hosted/halo/refined/halo_refined_custom_edition_en_v5.01.7z";
      hash = "sha256-0KrkVuokCLkrK4nCEihHCw+tmJbGlp+kHO+AUuDd1bo=";
    };
  };

  chimera = mkExtractedP7zipPayload {
    pname = "chimera";
    version = chimeraVersion;
    src = fetchurl {
      url = "https://github.com/SnowyMouse/chimera/releases/download/1.0.0r1224/chimera-1.0.0r1224.7z";
      hash = "sha256:b75624a0397c21dd4670d9be4d94742b0dd07f56615f3f45da020ddff0c9bf79";
    };
  };

  halocePostInstallScript =
    {
      wineExe,
      wineserverExe,
    }:
    renderScript ./install.sh [
      {
        placeholder = "@WINE_EXE@";
        value = wineExe;
      }
      {
        placeholder = "@WINESERVER_EXE@";
        value = wineserverExe;
      }
      {
        placeholder = "@HALO_INSTALL_DIR@";
        value = haloInstallDir;
      }
      {
        placeholder = "@PATCH_SRC@";
        value = toString patchSrc;
      }
      {
        placeholder = "@PATCH_SRC_WIN@";
        value = patchSrcWin;
      }
      {
        placeholder = "@HALO_REGISTRY_KEY@";
        value = haloRegistryKey;
      }
      {
        placeholder = "@HALO_UPDATE_LOCATION@";
        value = haloUpdateLocation;
      }
      {
        placeholder = "@CURRENT_VERSION@";
        value = installedVersion;
      }
      {
        placeholder = "@TARGET_VERSION@";
        value = targetVersion;
      }
      {
        placeholder = "@PATCH_UPDATE_VERSION@";
        value = patchUpdateVersion;
      }
      {
        placeholder = "@AUTOHOTKEY_EXE_PATH@";
        value = runtime.autohotkeyLayer.executablePath;
      }
      {
        placeholder = "@REFINED_MAPS@";
        value = toString refinedMaps;
      }
      {
        placeholder = "@CHIMERA@";
        value = toString chimera;
      }
    ];
in
overlayfsLib.mkWindowsPackage {
  inherit runtime;
  pname = "halo-custom-edition";
  version = haloVersion;
  src = installerSrc;
  packageName = "halo-custom-edition";
  executableName = "";
  executablePath = "";
  ahkScript = builtins.readFile ./install.ahk;
  postInstall = halocePostInstallScript {
    wineExe = "${runtime.toolsPackage}/bin/wine";
    wineserverExe = "${runtime.toolsPackage}/bin/wineserver";
  };
  overlayDependencies = installOverlayDeps;
  launchVncServer = false;
}
