DESTDIR="$WINEPREFIX@HALO_INSTALL_DIR@"

@WINESERVER_EXE@ --wait

if [[ ! -f "$DESTDIR/haloce.exe" ]]; then
  echo "Halo installer did not produce $DESTDIR/haloce.exe"
  exit 1
fi

chmod -R u+w "$DESTDIR"

HALOUPDATE_DIR="$WINEPREFIX/drive_c/users/$USER/Temp"
HALOUPDATE_APPDATA_DIR="$WINEPREFIX/drive_c/users/$USER/AppData/Local/Temp"
mkdir -p "$HALOUPDATE_DIR"
mkdir -p "$HALOUPDATE_APPDATA_DIR"

HALOUPDATE_LOG="$HALOUPDATE_APPDATA_DIR/haloupdate.txt"
HALOUPDATE_STDOUT="$HALOUPDATE_DIR/haloupdate.stdout"
HALOUPDATE_STDERR="$HALOUPDATE_DIR/haloupdate.stderr"
HALO_EULA_AHK="$HALOUPDATE_DIR/halo-eula.ahk"
: > "$HALOUPDATE_LOG"
: > "$HALOUPDATE_STDOUT"
: > "$HALOUPDATE_STDERR"

rm -f "$DESTDIR/_haloext.tmp" "$DESTDIR/_halopat.tmp"
cp '@PATCH_SRC@' "$DESTDIR/_halopat.tmp"
chmod u+w "$DESTDIR/_halopat.tmp"

VERSION_KEY_HKLM='HKLM\@HALO_REGISTRY_KEY@'
VERSION_KEY_HKCU='HKCU\@HALO_REGISTRY_KEY@'

halo_registry_value_contains() {
  local key="$1"
  local value_name="$2"
  local needle="$3"
  local query_output

  if ! query_output="$(@WINE_EXE@ reg query "$key" /v "$value_name" 2>/dev/null)"; then
    return 1
  fi

  printf '%s\n' "$query_output" | grep -Fq "$needle"
}

halo_patch_applied() {
  halo_registry_value_contains "$VERSION_KEY_HKLM" "Version" "@TARGET_VERSION@" \
    || halo_registry_value_contains "$VERSION_KEY_HKCU" "Version" "@TARGET_VERSION@" \
    || halo_registry_value_contains "$VERSION_KEY_HKLM" "Version" "@PATCH_UPDATE_VERSION@" \
    || halo_registry_value_contains "$VERSION_KEY_HKCU" "Version" "@PATCH_UPDATE_VERSION@"
}

@WINE_EXE@ reg add "$VERSION_KEY_HKLM" /v "EXE Path" /d "@HALO_UPDATE_LOCATION@" /f
@WINE_EXE@ reg add "$VERSION_KEY_HKLM" /v "Version" /d "@CURRENT_VERSION@" /f
@WINE_EXE@ reg delete "$VERSION_KEY_HKLM" /v "PendingVersion" /f || true
@WINE_EXE@ reg add "$VERSION_KEY_HKCU" /v "EXE Path" /d "@HALO_UPDATE_LOCATION@" /f
@WINE_EXE@ reg add "$VERSION_KEY_HKCU" /v "Version" /d "@CURRENT_VERSION@" /f
@WINE_EXE@ reg delete "$VERSION_KEY_HKCU" /v "PendingVersion" /f || true

cat > "$HALO_EULA_AHK" <<'EOF'
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
@WINE_EXE@ reg add "$VERSION_KEY_HKLM" /v "PendingVersion" /d "@TARGET_VERSION@" /f
@WINE_EXE@ reg add "$VERSION_KEY_HKCU" /v "PendingVersion" /d "@TARGET_VERSION@" /f

pushd "$DESTDIR" >/dev/null
@WINE_EXE@ "$DESTDIR/haloupdate.exe" \
  'processexe="@PATCH_SRC_WIN@"' \
  'updateversion="@PATCH_UPDATE_VERSION@"' \
  'autoexecmode=1' \
  'noextrawait=1' \
  'programname=Halo Patch' \
  >"$HALOUPDATE_STDOUT" \
  2>"$HALOUPDATE_STDERR" &
HALOUPDATE_PID=$!
popd >/dev/null

PATCH_SUCCESS=
HALOUPDATE_EXITED_OK=
for _ in $(seq 1 180); do
  if grep -Eq "processrtp SUCCEEDED!|manual update SUCCEEDED!|processexe SUCCEEDED!|autoexec SUCCEEDED!" "$HALOUPDATE_LOG" || halo_patch_applied; then
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
    if halo_patch_applied; then
      PATCH_SUCCESS=1
      break
    fi
  fi
  sleep 1
done

if [[ -z "$PATCH_SUCCESS" ]]; then
  echo "Timed out waiting for haloupdate success."
  sed -n '1,200p' "$HALOUPDATE_LOG" || true
  sed -n '1,200p' "$HALOUPDATE_STDOUT" || true
  sed -n '1,200p' "$HALOUPDATE_STDERR" || true
  @WINE_EXE@ reg query "$VERSION_KEY_HKLM" /v "Version" || true
  @WINE_EXE@ reg query "$VERSION_KEY_HKCU" /v "Version" || true
  @WINE_EXE@ reg query "$VERSION_KEY_HKLM" /v "PendingVersion" || true
  @WINE_EXE@ reg query "$VERSION_KEY_HKCU" /v "PendingVersion" || true
  @WINE_EXE@ taskkill /f /im haloupdate.exe || true
  @WINE_EXE@ tasklist || true
  exit 1
fi

echo "Patch succeeded: killing haloupdate..."
@WINE_EXE@ taskkill /f /im haloupdate.exe || true

echo "Copying maps..."
cp @REFINED_MAPS@/maps/* "$DESTDIR/maps/"
echo "Done"

echo "Installing Chimera..."
cp @CHIMERA@/chimera.ini "$DESTDIR"
cp -r @CHIMERA@/fonts "$DESTDIR"
cp @CHIMERA@/strings.dll "$DESTDIR"
echo "Done"

echo "Seeding Halo first-run state..."
pushd "$DESTDIR" >/dev/null
@WINE_EXE@ "$DESTDIR/haloce.exe" -novideo -windowed -safemode \
  >"$HALOUPDATE_DIR/haloce-first-run.stdout" \
  2>"$HALOUPDATE_DIR/haloce-first-run.stderr" &
HALO_FIRST_RUN_PID=$!

@WINE_EXE@ "$WINEPREFIX@AUTOHOTKEY_EXE_PATH@" "Z:$HALO_EULA_AHK" \
  >"$HALOUPDATE_DIR/haloce-first-run-automation.stdout" \
  2>"$HALOUPDATE_DIR/haloce-first-run-automation.stderr" &
HALO_EULA_AHK_PID=$!
sleep 5
@WINE_EXE@ taskkill /f /im haloce.exe || true
@WINE_EXE@ taskkill /f /im AutoHotkey.exe || true
wait "$HALO_FIRST_RUN_PID" || true
wait "$HALO_EULA_AHK_PID" || true
popd >/dev/null

@WINE_EXE@ reg delete "$VERSION_KEY_HKCU" /v "ExitFlag" /f || true

@WINE_EXE@ tasklist || true
