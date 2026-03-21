DESTDIR="$WINEPREFIX@HALO_INSTALL_DIR@"
mkdir -p "$DESTDIR"

patch_binary_bytes() {
  local file="$1"
  local offset="$2"
  local expected_hex="$3"
  local replacement_hex="$4"
  local byte_count=$(( ${#replacement_hex} / 2 ))
  local current_hex

  current_hex="$(
    dd if="$file" bs=1 skip="$offset" count="$byte_count" status=none \
      | od -An -tx1 -v \
      | tr -d ' \n'
  )"

  if [[ "$current_hex" != "$expected_hex" && "$current_hex" != "$replacement_hex" ]]; then
    echo "Unexpected bytes in $file at offset 0x$(printf '%x' "$offset"): got $current_hex, expected $expected_hex"
    exit 1
  fi

  if [[ "$current_hex" == "$replacement_hex" ]]; then
    return
  fi

  printf '%b' "$(echo "$replacement_hex" | sed 's/../\\x&/g')" \
    | dd of="$file" bs=1 seek="$offset" conv=notrunc status=none
}

echo "Copying extracted Halo payload into $DESTDIR"
cp -r @HALOCE_PAYLOAD@/* "$DESTDIR"/
chmod -R u+w "$DESTDIR"

if [[ "@ENABLE_AARCH64_RUNTIME_PATCHES@" == "1" ]]; then
  HALO_EXE="$DESTDIR/haloce.exe"
  echo "Applying aarch64 runtime compatibility patches to $HALO_EXE"
  patch_binary_bytes "$HALO_EXE" $((0x1829ea)) e8c1f3ffff b802000000
  patch_binary_bytes "$HALO_EXE" $((0x11ad7f)) 32db b301
fi

HALOUPDATE_DIR="$WINEPREFIX/drive_c/users/$USER/Temp"
mkdir -p "$HALOUPDATE_DIR"

HALOUPDATE_LOG="$HALOUPDATE_DIR/haloupdate.txt"
HALOUPDATE_STDOUT="$HALOUPDATE_DIR/haloupdate.stdout"
HALOUPDATE_STDERR="$HALOUPDATE_DIR/haloupdate.stderr"
HALO_EULA_VBS="$HALOUPDATE_DIR/halo-eula.vbs"
: > "$HALOUPDATE_LOG"
: > "$HALOUPDATE_STDOUT"
: > "$HALOUPDATE_STDERR"

SYSARM32_DIR="$WINEPREFIX/drive_c/windows/sysarm32"
SYSTEM32_DIR="$WINEPREFIX/drive_c/windows/system32"
mkdir -p "$SYSARM32_DIR"
for helper in cmd.exe msiexec.exe regsvr32.exe rundll32.exe; do
  if [[ ! -e "$SYSARM32_DIR/$helper" && -e "$SYSTEM32_DIR/$helper" ]]; then
    cp "$SYSTEM32_DIR/$helper" "$SYSARM32_DIR/$helper"
    chmod u+w "$SYSARM32_DIR/$helper"
  fi
done

cp '@PATCH_SRC@' "$DESTDIR/_halopat.tmp"
chmod u+w "$DESTDIR/_halopat.tmp"

cp @HALO_PATCH_PAYLOAD@/haloupdate.exe "$DESTDIR"/
cp '@HALO_PATCH_RTP@' "$DESTDIR/patch.rtp"

VERSION_KEY_HKLM='HKLM\@HALO_REGISTRY_KEY@'
VERSION_KEY_HKCU='HKCU\@HALO_REGISTRY_KEY@'

@WINE_EXE@ reg add "$VERSION_KEY_HKLM" /v "EXE Path" /d "@HALO_UPDATE_LOCATION@" /f
@WINE_EXE@ reg add "$VERSION_KEY_HKLM" /v "Version" /d "@CURRENT_VERSION@" /f
@WINE_EXE@ reg delete "$VERSION_KEY_HKLM" /v "PendingVersion" /f || true
@WINE_EXE@ reg add "$VERSION_KEY_HKCU" /v "EXE Path" /d "@HALO_UPDATE_LOCATION@" /f
@WINE_EXE@ reg add "$VERSION_KEY_HKCU" /v "Version" /d "@CURRENT_VERSION@" /f
@WINE_EXE@ reg delete "$VERSION_KEY_HKCU" /v "PendingVersion" /f || true

cat > "$HALO_EULA_VBS" <<'EOF'
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
if [[ "@ENABLE_LEGACY_PATCH@" == "1" ]]; then
  @WINE_EXE@ reg add "$VERSION_KEY_HKLM" /v "PendingVersion" /d "@TARGET_VERSION@" /f
  @WINE_EXE@ reg add "$VERSION_KEY_HKCU" /v "PendingVersion" /d "@TARGET_VERSION@" /f

  pushd "$DESTDIR" >/dev/null
  @WINE_EXE@ "$DESTDIR/haloupdate.exe" \
    'processrtp="@HALO_PATCH_RTP_WIN@"' \
    'updateversion="@TARGET_VERSION@"' \
    'programname="Halo Patch"' \
    >"$HALOUPDATE_STDOUT" \
    2>"$HALOUPDATE_STDERR" &
  HALOUPDATE_PID=$!
  popd >/dev/null

  PATCH_SUCCESS=
  HALOUPDATE_EXITED_OK=
  for _ in $(seq 1 40); do
    if grep -Eq "processrtp SUCCEEDED!|manual update SUCCEEDED!" "$HALOUPDATE_LOG"; then
      PATCH_SUCCESS=1
      break
    fi
    if [[ -z "$HALOUPDATE_EXITED_OK" ]] && ! kill -0 "$HALOUPDATE_PID" 2>/dev/null; then
      wait "$HALOUPDATE_PID"
      HALOUPDATE_STATUS=$?
      if [[ "$HALOUPDATE_STATUS" -ne 0 ]]; then
        echo "haloupdate exited early with status $HALOUPDATE_STATUS"
        sed -n '1,200p' "$HALOUPDATE_LOG" || true
        sed -n '1,200p' "$HALOUPDATE_STDOUT" || true
        sed -n '1,200p' "$HALOUPDATE_STDERR" || true
        exit "$HALOUPDATE_STATUS"
      fi
      HALOUPDATE_EXITED_OK=1
    fi
    sleep 1
  done

  if [[ -z "$PATCH_SUCCESS" ]]; then
    echo "Timed out waiting for haloupdate success."
    sed -n '1,200p' "$HALOUPDATE_LOG" || true
    sed -n '1,200p' "$HALOUPDATE_STDOUT" || true
    sed -n '1,200p' "$HALOUPDATE_STDERR" || true
    @WINE_EXE@ taskkill /f /im haloupdate.exe || true
    @WINE_EXE@ tasklist || true
    exit 1
  fi

  echo "Patch succeeded: killing haloupdate..."
  @WINE_EXE@ taskkill /f /im haloupdate.exe || true
else
  echo "Skipping legacy Halo updater on this runtime."
fi

if [[ "@ENABLE_LEGACY_PATCH@" == "1" ]]; then
  echo "Copying maps..."
  cp @REFINED_MAPS@/maps/* "$DESTDIR/maps/"
  echo "Done"

  echo "Installing Chimera..."
  cp @CHIMERA@/chimera.ini "$DESTDIR"
  cp -r @CHIMERA@/fonts "$DESTDIR"
  cp @CHIMERA@/strings.dll "$DESTDIR"
  echo "Done"
else
  echo "Using bundled v1.10 portable payload on this runtime."
  rm -rf "$DESTDIR/controls"
fi

echo "Seeding Halo first-run state..."
pushd "$DESTDIR" >/dev/null
@WINE_EXE@ "$DESTDIR/haloce.exe" -novideo -windowed -safemode \
  >"$HALOUPDATE_DIR/haloce-first-run.stdout" \
  2>"$HALOUPDATE_DIR/haloce-first-run.stderr" &
HALO_FIRST_RUN_PID=$!

@WINE_EXE@ wscript //nologo "Z:${HALO_EULA_VBS}" || true
sleep 5
@WINE_EXE@ taskkill /f /im haloce.exe || true
wait "$HALO_FIRST_RUN_PID" || true
popd >/dev/null

@WINE_EXE@ reg delete "$VERSION_KEY_HKCU" /v "ExitFlag" /f || true

@WINE_EXE@ tasklist || true
