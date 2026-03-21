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
  overlayDependencies = [ basePackageLayer ] ++ lib.optionals (dxvkLayer != null) [ dxvkLayer ];
  unshareInstall =
    { session, ... }:
    ''
      halo_dir="$WINEPREFIX${haloInstallDir}"
      eula_vbs="$PWD/halo-first-run-eula.vbs"

      cat > "$eula_vbs" <<'EOF'
Set shell = CreateObject("WScript.Shell")
WScript.Sleep 3000
On Error Resume Next
shell.AppActivate "Halo - End User License Agreement"
WScript.Sleep 500
shell.SendKeys "%a"
WScript.Sleep 500
shell.SendKeys "{ENTER}"
WScript.Sleep 500
shell.SendKeys "%a"
EOF

      ${session.commands.wine} "$halo_dir/haloce.exe" -novideo -windowed -safemode \
        >"$PWD/haloce-init.stdout" \
        2>"$PWD/haloce-init.stderr" &
      halo_pid=$!

      ${session.commands.wine} wscript //nologo "Z:$eula_vbs" || true
      sleep 5
      ${session.commands.wine} taskkill /f /im haloce.exe || true
      wait "$halo_pid" || true
      ${session.commands.wineserver} --wait
    '';
}
