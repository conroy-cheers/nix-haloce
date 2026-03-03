{
  lib,
  stdenvNoCC,
  fetchurl,
  glibcLocales,
  jq,
  p7zip,
  _7zz,

  overlayfsLib,
  wineGeWin32Modules,
  wineTkgWow64Modules,
}:
let
  haloVersion = "1.0.10";
  installerVersion = "1.0.0";
  refinedVersion = "5.01";
  chimeraVersion = "1.0.0r1096.55407763";

  currentVersion = "01.00.00.0609";
  targetVersion = "01.00.10.0621";
  haloRegistryKey = "Software\\Microsoft\\Microsoft Games\\Halo CE";
  haloInstallSuffix = "/Microsoft Games/Halo Custom Edition";
  haloInstallDirWin32 = "${wineGeWin32Modules.wine.programFiles32Path}${haloInstallSuffix}";
  haloInstallDirWow64 = "${wineTkgWow64Modules.wine.programFilesPath}${haloInstallSuffix}";
  haloUpdateLocation = "C:\\Program Files (x86)\\Microsoft Games\\Halo Custom Edition";

  runtimeLocaleEnv = {
    LOCALE_ARCHIVE = "${glibcLocales}/lib/locale/locale-archive";
    LC_ALL = "C";
    LANG = "C";
  };

  installOverlayDeps = with wineGeWin32Modules; [
    msvcp60
    msxml4
  ];

  runtimeBaseOverlayDeps = with wineTkgWow64Modules; [
    msvcp60
    msxml4
  ];

  runtimeOverlayDeps = with wineTkgWow64Modules; [
    wine-dxvk
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

  mkExtracted7zPayload =
    {
      pname,
      version,
      src,
    }:
    stdenvNoCC.mkDerivation {
      inherit pname version src;
      nativeBuildInputs = [ _7zz ];
      unpackPhase = "true";
      buildPhase = ''
        mkdir payload
        7zz x -y -bd -bso0 -bsp0 -bse1 "$src" -opayload
      '';
      installPhase = ''
        mkdir -p "$out"
        cp -r ./payload/* "$out"/
      '';
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

  halocePayload = mkExtracted7zPayload {
    pname = "halo-custom-edition-payload";
    version = installerVersion;
    src = installerSrc;
  };

  haloPatchPayload = mkExtracted7zPayload {
    pname = "halo-custom-edition-patch-payload";
    version = haloVersion;
    src = patchSrc;
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

  haloceInstallScript =
    { wineExe }:
    renderScript ./install.sh [
      {
        placeholder = "@WINE_EXE@";
        value = wineExe;
      }
      {
        placeholder = "@HALO_INSTALL_DIR_WIN32@";
        value = haloInstallDirWin32;
      }
      {
        placeholder = "@HALOCE_PAYLOAD@";
        value = toString halocePayload;
      }
      {
        placeholder = "@PATCH_SRC@";
        value = toString patchSrc;
      }
      {
        placeholder = "@HALO_PATCH_PAYLOAD@";
        value = toString haloPatchPayload;
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
        value = currentVersion;
      }
      {
        placeholder = "@TARGET_VERSION@";
        value = targetVersion;
      }
      {
        placeholder = "@PATCH_SRC_WIN@";
        value = patchSrcWin;
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

  mergeRegistryJsonScript = renderScript ./merge-registry.sh [
    {
      placeholder = "@WOW64_BASE_ENV@";
      value = toString wineTkgWow64Modules.wine.wine-base-env;
    }
  ];

  haloce = overlayfsLib.mkWinePackage {
    inherit (wineGeWin32Modules) wine;
    pname = "halo-custom-edition";
    version = haloVersion;
    src = installerSrc;
    unshareInstall = haloceInstallScript;
    postInstall = "";
    overlayDependencies = installOverlayDeps;
    packageName = "halo-custom-edition";
    executableName = "haloce";
    launchVncServer = false;
  };

  haloceWow64Base = stdenvNoCC.mkDerivation {
    pname = "halo-custom-edition-wow64-base";
    version = haloce.version;
    src = haloce.basePackage;
    nativeBuildInputs = [
      jq
      overlayfsLib.scripts.json2reg
    ];
    unpackPhase = "true";
    buildPhase = ''
      cp -r "$src" ./base
      chmod -R u+w ./base
      ${mergeRegistryJsonScript}
    '';
    installPhase = ''
      mkdir -p "$out"
      cp -r ./base/* "$out"/
    '';
  };

  haloceWow64RuntimeLayer = haloce // {
    basePackage = haloceWow64Base;
    overlayDependencies = runtimeBaseOverlayDeps;
    runtimeEnvVars = runtimeLocaleEnv;
  };
in
overlayfsLib.composeWineLayers {
  inherit (wineTkgWow64Modules) wine;
  baseLayer = haloceWow64RuntimeLayer;
  overlayDependencies = runtimeOverlayDeps;
  packageName = "halo-custom-edition";
  executableName = "haloce";
  executablePath = "${haloInstallDirWow64}/haloce.exe";
  workingDirectory = haloInstallDirWow64;
  entrypointWrapper = entrypoint: ''
    export LOCALE_ARCHIVE='${runtimeLocaleEnv.LOCALE_ARCHIVE}'
    export LC_ALL='${runtimeLocaleEnv.LC_ALL}'
    export LANG='${runtimeLocaleEnv.LANG}'
    ${entrypoint}
  '';
}
