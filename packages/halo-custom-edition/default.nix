{
  lib,
  stdenvNoCC,
  fetchurl,
  p7zip,

  overlayfsLib,
  wineGeWin32Modules,
}:
let
  patchSrc = fetchurl {
    url = "https://web.archive.org/web/20141022155617/http://halo.bungie.net/images/games/halopc/patch/110/haloce-patch-1.0.10.exe";
    hash = "sha256-M4GPP1a33dyMYdZUr2VnycW5IgynXWrCOlJhEDgldQg=";
  };

  refinedMaps = stdenvNoCC.mkDerivation {
    pname = "halo-refined-custom-edition";
    version = "5.01";
    src = fetchurl {
      url = "http://vaporeon.io/hosted/halo/refined/halo_refined_custom_edition_en_v5.01.7z";
      hash = "sha256-0KrkVuokCLkrK4nCEihHCw+tmJbGlp+kHO+AUuDd1bo=";
    };
    nativeBuildInputs = [ p7zip ];
    unpackPhase = ''
      runHook preUnpack

      7z x $src -o$out

      runHook postUnpack
    '';
  };

  chimera = stdenvNoCC.mkDerivation {
    pname = "chimera";
    version = "1.0.0r1096.55407763";
    src = fetchurl {
      url = "https://github.com/SnowyMouse/chimera/releases/download/1.0.0r1142/chimera-1.0.0r1142.59488299.7z";
      hash = "sha256-I+hCgH03F5hxNp3T/RukBlDBLV9bK9COIAC1KsqyWvg=";
    };
    nativeBuildInputs = [ p7zip ];
    unpackPhase = ''
      runHook preUnpack

      7z x $src -o$out

      runHook postUnpack
    '';
  };

  haloce = overlayfsLib.mkWinePackage {
    inherit (wineGeWin32Modules) wine;
    pname = "halo-custom-edition";
    version = "1.0.10";
    src = fetchurl {
      url = "http://vaporeon.io/hosted/halo/original_files/halocesetup_en_1.00.exe";
      hash = "sha256-ARsDthY0Vh18G2CQ5yKf4KLfQN4sKhS0WsjwRV1dmQ8=";
    };
    ahkScript = builtins.readFile ./install.ahk;
    postInstall = ''
      DESTDIR="$WINEPREFIX${wineGeWin32Modules.wine.programFiles32Path}/Microsoft Games/Halo Custom Edition"

      HALOUPDATE_LOG="$WINEPREFIX/drive_c/users/$USER/Temp/haloupdate.txt"
      touch "$HALOUPDATE_LOG"
      touch "$DESTDIR/_halopat.tmp"

      ${lib.getExe wineGeWin32Modules.wine} "${patchSrc}"

      tail -F "$HALOUPDATE_LOG" | \
      while IFS= read -r line; do
        echo "$line"
        if [[ "$line" == *"manual update SUCCEEDED!"* ]]; then
          echo "Patch succeeded: killing haloupdate..."
          ${lib.getExe wineGeWin32Modules.wine} taskkill /f /im haloupdate.exe
          break
        fi
      done

      echo "Copying maps..."
      cp ${refinedMaps}/* "$DESTDIR/maps/"
      echo "Done"

      echo "Installing Chimera..."
      cp ${chimera}/chimera.ini "$DESTDIR"
      cp -r ${chimera}/fonts "$DESTDIR"
      cp ${chimera}/strings.dll "$DESTDIR"
      echo "Done"

      ${lib.getExe wineGeWin32Modules.wine} tasklist
    '';
    overlayDependencies = with wineGeWin32Modules; [
      msvcp60
      msxml4
    ];
    packageName = "halo-custom-edition";
    executableName = "haloce";
  };
in
overlayfsLib.composeWineLayers {
  inherit (wineGeWin32Modules) wine;
  baseLayer = haloce;
  overlayDependencies = with wineGeWin32Modules; [
    wine-dxvk
  ];
  packageName = "halo-custom-edition";
  executableName = "haloce";
  executablePath = "${wineGeWin32Modules.wine.programFiles32Path}/Microsoft Games/Halo Custom Edition/haloce.exe";
  workingDirectory = "${wineGeWin32Modules.wine.programFiles32Path}/Microsoft Games/Halo Custom Edition";
  entrypointWrapper = entrypoint: ''
    if [[ -x $(command -v gamescope) ]]
    then
      gamescope --force-grab-cursor -f --expose-wayland $@ -- ${entrypoint}
    else
      ${entrypoint}
    fi
  '';
}
