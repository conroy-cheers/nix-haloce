{
  lib,
  writeText,
  runCommand,
  overlayfsLib,
  runtime,
  basePackage,
  dxvkLayer ? null,
}:
let
  haloInstallDir = "${runtime.programFiles32Path}/Microsoft Games/Halo Custom Edition";
  basePackageLayer = runCommand "halo-custom-edition-runtime-base-layer" { } ''
    mkdir -p "$out"
    ln -s ${basePackage} "$out/basePackage"
  '';
in
overlayfsLib.mkWindowsPackage {
  inherit runtime;
  pname = "halo-custom-edition-runtime-init";
  version = basePackage.version;
  src = writeText "halo-custom-edition-runtime-init.txt" "";
  packageName = "halo-custom-edition-runtime-init";
  overlayDependencies = [ basePackageLayer runtime.autohotkeyLayer ] ++ lib.optionals (dxvkLayer != null) [ dxvkLayer ];
  unshareInstall =
    { session, ... }:
    ''
      halo_dir="$WINEPREFIX${haloInstallDir}"
      halo_exe="$halo_dir/haloce.exe"
      eula_ahk="$PWD/halo-first-run-eula.ahk"

      patch_binary_bytes() {
        local file="$1"
        local offset="$2"
        local expected_hex="$3"
        local replacement_hex="$4"
        local byte_count=$(( ''${#replacement_hex} / 2 ))
        local current_hex

        current_hex="$(
          dd if="$file" bs=1 skip="$offset" count="$byte_count" status=none \
            | od -An -tx1 -v \
            | tr -d ' \n'
        )"

        if [[ "$current_hex" != "$expected_hex" && "$current_hex" != "$replacement_hex" ]]; then
          echo "Skipping aarch64 runtime patch for $file at offset 0x$(printf '%x' "$offset"): got $current_hex, expected $expected_hex" >&2
          return 1
        fi

        if [[ "$current_hex" == "$replacement_hex" ]]; then
          return
        fi

        printf '%b' "$(echo "$replacement_hex" | sed 's/../\\x&/g')" \
          | dd of="$file" bs=1 seek="$offset" conv=notrunc status=none
      }

      patch_binary_bytes "$halo_exe" $((0x1829ea)) e8c1f3ffff b802000000 || true
      patch_binary_bytes "$halo_exe" $((0x11ad7f)) 32db b301 || true

      cat > "$eula_ahk" <<'EOF'
#Persistent
SetTitleMatchMode, 2

EulaWinTitle := "Halo - End User License Agreement"

Loop
{
    IfWinExist, %EulaWinTitle%
    {
        WinActivate, %EulaWinTitle%
        Sleep, 300
        ControlClick, Button1, %EulaWinTitle%
        Sleep, 300
        Send, {Enter}
    }
    Sleep, 500
}
EOF

      ${session.commands.wine} "$halo_exe" -novideo -windowed -safemode \
        >"$PWD/haloce-init.stdout" \
        2>"$PWD/haloce-init.stderr" &
      halo_pid=$!

      ${session.commands.wine} "$WINEPREFIX${runtime.autohotkeyLayer.executablePath}" "Z:$eula_ahk" \
        >"$PWD/haloce-init-automation.stdout" \
        2>"$PWD/haloce-init-automation.stderr" &
      eula_pid=$!
      sleep 5
      ${session.commands.wine} taskkill /f /im haloce.exe || true
      ${session.commands.wine} taskkill /f /im AutoHotkey.exe || true
      wait "$halo_pid" || true
      wait "$eula_pid" || true
      ${session.commands.wineserver} --wait
    '';
}
