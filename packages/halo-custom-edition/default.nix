{
  lib,
  stdenv,
  mesa,
  patchelf,
  glibcLocales,

  overlayfsLib,
  modules,
  basePackage,
  dxvkPackage ? null,
}:
let
  haloVersion = "1.0.10";
  haloInstallSuffix = "/Microsoft Games/Halo Custom Edition";
  runtime = modules.runtime;
  isAarch64 = stdenv.hostPlatform.isAarch64;
  haloInstallDir = "${runtime.programFiles32Path}${haloInstallSuffix}";
  sysarm32SeedSource = "${runtime.baseEnvLayer}/basePackage/drive_c/windows/system32";
  dxvkLayer =
    if isAarch64 && dxvkPackage != null then
      modules.callPackage ./dxvk-layer.nix { dxvk = dxvkPackage; }
    else
      null;
  runtimeInitLayer =
    if isAarch64 then
      modules.callPackage ./init-layer.nix {
        inherit basePackage dxvkLayer;
      }
    else
      null;

  runtimeLocaleEnv = {
    LOCALE_ARCHIVE = "${glibcLocales}/lib/locale/locale-archive";
    LC_ALL = "C";
    LANG = "C";
  };

  runtimeBootstrapCommands = ''
    halo_rewrite_runtime_registry() {
      if [ -f "$tempdir/overlay/user.reg" ]; then
        sed -i "s#C:\\\\\\\\users\\\\\\\\nixbld#C:\\\\\\\\users\\\\\\\\$USER#g" "$tempdir/overlay/user.reg"
        sed -i "s#\\\\users\\\\nixbld#\\\\users\\\\$USER#g" "$tempdir/overlay/user.reg"
        sed -i "s#\"HOMEPATH\"=\"\\\\users\\\\nixbld\"#\"HOMEPATH\"=\"\\\\users\\\\$USER\"#g" "$tempdir/overlay/user.reg"
        sed -i "s#\"USERNAME\"=\"nixbld\"#\"USERNAME\"=\"$USER\"#g" "$tempdir/overlay/user.reg"
        sed -i '/^"ExitFlag"=/d' "$tempdir/overlay/user.reg"
        if ! grep -q '^\[Software\\\\Wine\\\\Direct3D\]' "$tempdir/overlay/user.reg"; then
          cat >>"$tempdir/overlay/user.reg" <<'EOF'

[Software\\Wine\\Direct3D]
#time=1dcb93fffffffff
EOF
        fi
        if ! grep -q '^"VideoMemorySize"=' "$tempdir/overlay/user.reg"; then
          sed -i '/^\[Software\\\\Wine\\\\Direct3D\]/a "VideoMemorySize"="2048"' "$tempdir/overlay/user.reg"
        fi
      fi
      if [ -f "$tempdir/overlay/system.reg" ]; then
        sed -i "s#C:\\\\\\\\users\\\\\\\\nixbld#C:\\\\\\\\users\\\\\\\\$USER#g" "$tempdir/overlay/system.reg"
      fi
    }

    if [ ! -f "$appdir/user.reg" ]; then
      ${lib.optionalString (runtimeInitLayer != null) ''
        cp -dR --no-preserve=ownership ${lib.escapeShellArg "${toString runtimeInitLayer}/basePackage"}/. "$appdir"/
      ''}
      touch "$appdir/.update-timestamp"
    fi

    if [ "${lib.boolToString isAarch64}" = true ]; then
      export HALO_SYSARM32_APPDIR="$appdir/drive_c/windows/sysarm32"
      if [ ! -L "$HALO_SYSARM32_APPDIR/rundll32.exe" ]; then
        mkdir -p "$HALO_SYSARM32_APPDIR"
        for source in ${lib.escapeShellArg sysarm32SeedSource}/*; do
          target="$HALO_SYSARM32_APPDIR/$(basename "$source")"
          if [ ! -e "$target" ] && [ ! -L "$target" ]; then
            ln -s "$source" "$target"
          fi
        done
      fi
    fi

    export HALO_USER_DIR="$tempdir/overlay/drive_c/users/$USER"
    export HALO_BUILD_USER_DIR="$tempdir/overlay/drive_c/users/nixbld"
    export HALO_ROOT_USER_DIR="$tempdir/overlay/drive_c/users/root"
    export HALO_SAVE_DIR="$HALO_USER_DIR/Documents/My Games/Halo CE"
    export HALO_PROFILE_DIR="$HALO_SAVE_DIR/saved/player_profiles/default_profile"
    export HALO_PLAYLIST_DIR="$HALO_SAVE_DIR/saved/playlists/default_playlist"
    export HALO_HOSTNAME_UPPER="$(hostname -s | tr '[:lower:]' '[:upper:]')"
    export USERNAME="$USER"
    export USERPROFILE="C:\\users\\$USER"
    export HOMEDRIVE="C:"
    export HOMEPATH="\\users\\$USER"
    export APPDATA="C:\\users\\$USER\\AppData\\Roaming"
    export LOCALAPPDATA="C:\\users\\$USER\\AppData\\Local"
    export USERDOMAIN="$HALO_HOSTNAME_UPPER"
    export LOGONSERVER="\\\\$HALO_HOSTNAME_UPPER"
    mkdir -p \
      "$HALO_USER_DIR/Desktop" \
      "$HALO_SAVE_DIR" \
      "$HALO_PROFILE_DIR" \
      "$HALO_PLAYLIST_DIR" \
      "$HALO_USER_DIR/Favorites" \
      "$HALO_USER_DIR/Music" \
      "$HALO_USER_DIR/Pictures" \
      "$HALO_USER_DIR/Videos" \
      "$HALO_USER_DIR/Downloads" \
      "$HALO_USER_DIR/Saved Games" \
      "$HALO_USER_DIR/Contacts" \
      "$HALO_USER_DIR/Links" \
      "$HALO_USER_DIR/Searches" \
      "$HALO_USER_DIR/AppData/Local/Microsoft/Windows/History" \
      "$HALO_USER_DIR/AppData/Local/Microsoft/Windows/INetCache" \
      "$HALO_USER_DIR/AppData/Local/Microsoft/Windows/INetCookies" \
      "$HALO_USER_DIR/AppData/LocalLow" \
      "$HALO_USER_DIR/AppData/Roaming/Microsoft/Windows/Network Shortcuts" \
      "$HALO_USER_DIR/AppData/Roaming/Microsoft/Windows/Printer Shortcuts" \
      "$HALO_USER_DIR/AppData/Roaming/Microsoft/Windows/Recent" \
      "$HALO_USER_DIR/AppData/Roaming/Microsoft/Windows/SendTo" \
      "$HALO_USER_DIR/AppData/Roaming/Microsoft/Windows/Start Menu/Programs/Administrative Tools" \
      "$HALO_USER_DIR/AppData/Roaming/Microsoft/Windows/Templates"
    mkdir -p \
      "$HALO_BUILD_USER_DIR/AppData/Local/Temp" \
      "$HALO_ROOT_USER_DIR/Desktop" \
      "$HALO_ROOT_USER_DIR/Documents" \
      "$HALO_ROOT_USER_DIR/Favorites" \
      "$HALO_ROOT_USER_DIR/Music" \
      "$HALO_ROOT_USER_DIR/Pictures" \
      "$HALO_ROOT_USER_DIR/Videos" \
      "$HALO_ROOT_USER_DIR/Downloads" \
      "$HALO_ROOT_USER_DIR/Saved Games" \
      "$HALO_ROOT_USER_DIR/Contacts" \
      "$HALO_ROOT_USER_DIR/Links" \
      "$HALO_ROOT_USER_DIR/Searches" \
      "$HALO_ROOT_USER_DIR/AppData/Local/Microsoft/Windows/History" \
      "$HALO_ROOT_USER_DIR/AppData/Local/Microsoft/Windows/INetCache" \
      "$HALO_ROOT_USER_DIR/AppData/Local/Microsoft/Windows/INetCookies" \
      "$HALO_ROOT_USER_DIR/AppData/Local/Temp" \
      "$HALO_ROOT_USER_DIR/AppData/LocalLow" \
      "$HALO_ROOT_USER_DIR/AppData/Roaming/Microsoft/Windows/Network Shortcuts" \
      "$HALO_ROOT_USER_DIR/AppData/Roaming/Microsoft/Windows/Printer Shortcuts" \
      "$HALO_ROOT_USER_DIR/AppData/Roaming/Microsoft/Windows/Recent" \
      "$HALO_ROOT_USER_DIR/AppData/Roaming/Microsoft/Windows/SendTo" \
      "$HALO_ROOT_USER_DIR/AppData/Roaming/Microsoft/Windows/Start Menu/Programs/Administrative Tools" \
      "$HALO_ROOT_USER_DIR/AppData/Roaming/Microsoft/Windows/Templates"
    rm -rf "$HALO_USER_DIR/My Documents"
    ln -s Documents "$HALO_USER_DIR/My Documents"
    if [ ! -f "$HALO_SAVE_DIR/savegame.bin" ]; then
      truncate -s 4718592 "$HALO_SAVE_DIR/savegame.bin"
    fi

    halo_rewrite_runtime_registry

    if [ ! -f "$appdir/.halo-runtime-ready" ]; then
      ${runtime.toolsPackage}/bin/wineboot -u
      ${runtime.toolsPackage}/bin/wineserver --wait
      halo_rewrite_runtime_registry
      touch "$appdir/.halo-runtime-ready"
    fi
    rm -rf "$HALO_USER_DIR/Documents/My Games/Halo CE/hac"
    rm -rf "$tempdir/overlay/drive_c/Program Files (x86)/Microsoft Games/Halo Custom Edition/controls"
  '';

  haloAarch64BootstrapCommands = lib.optionalString isAarch64 ''
    if [ -f "$tempdir/overlay/user.reg" ] && grep -q '^\[Software\\\\Microsoft\\\\Microsoft Games\\\\Halo CE\]' "$tempdir/overlay/user.reg"; then
      if ! grep -q '^"FIRSTRUN"=' "$tempdir/overlay/user.reg"; then
        sed -i '/^\[Software\\\\Microsoft\\\\Microsoft Games\\\\Halo CE\]/a "ATI Radeon 9600 XT (0x4172):147"=hex:6e,30\n"FIRSTRUN"=dword:00000001\n"gamma"=dword:00000001' "$tempdir/overlay/user.reg"
      fi
    fi
  '';

  dxvkBootstrapCommands = lib.optionalString (isAarch64 && dxvkLayer != null) ''
    export DXVK_LOG_LEVEL="${"$"}{DXVK_LOG_LEVEL:-none}"
    export DXVK_STATE_CACHE="${"$"}{DXVK_STATE_CACHE:-0}"
  '';

  mesaBootstrapCommands = lib.optionalString isAarch64 ''
    if [ -n "${"$"}{DISPLAY:-}" ]; then
      unset WAYLAND_DISPLAY
    fi

    wine_rpath="$(${patchelf}/bin/patchelf --print-rpath ${runtime.toolsPackage}/bin/.wine)"
    export LD_LIBRARY_PATH="${mesa}/lib${"$"}{wine_rpath:+:${"$"}wine_rpath}${"$"}{LD_LIBRARY_PATH:+:${"$"}LD_LIBRARY_PATH}"
    export __EGL_VENDOR_LIBRARY_FILENAMES="${mesa}/share/glvnd/egl_vendor.d/50_mesa.json"
    export LIBGL_DRIVERS_PATH="${mesa}/lib/dri"
    export GBM_BACKENDS_PATH="${mesa}/lib/gbm"
    export VK_DRIVER_FILES="${mesa}/share/vulkan/icd.d/asahi_icd.aarch64.json"
    export VK_LAYER_PATH="${mesa}/share/vulkan/explicit_layer.d:${mesa}/share/vulkan/implicit_layer.d"
  '';
in
overlayfsLib.composeWindowsLayers {
  inherit runtime;
  baseLayer = {
    inherit basePackage;
    overlayDependencies = [ ];
    runtimeEnvVars = runtimeLocaleEnv;
  };
  overlayDependencies = lib.optionals (dxvkLayer != null) [ dxvkLayer ];
  packageName = "halo-custom-edition";
  executableName = "haloce";
  executablePath = "${haloInstallDir}/haloce.exe";
  workingDirectory = haloInstallDir;
  runtimeEnvVars = runtimeLocaleEnv;
  extraPreLaunchCommands =
    runtimeBootstrapCommands
    + haloAarch64BootstrapCommands
    + dxvkBootstrapCommands
    + mesaBootstrapCommands;
  entrypointWrapper = entrypoint: ''exec ${entrypoint} -novideo "$@"'';
}
