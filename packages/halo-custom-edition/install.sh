DESTDIR="$WINEPREFIX@HALO_INSTALL_DIR_WIN32@"
mkdir -p "$DESTDIR"

echo "Copying extracted Halo payload into $DESTDIR"
cp -r @HALOCE_PAYLOAD@/* "$DESTDIR"/
chmod -R u+w "$DESTDIR"

HALOUPDATE_DIR="$WINEPREFIX/drive_c/users/$USER/Temp"
mkdir -p "$HALOUPDATE_DIR"

HALOUPDATE_LOG="$HALOUPDATE_DIR/haloupdate.txt"
HALOUPDATE_STDOUT="$HALOUPDATE_DIR/haloupdate.stdout"
HALOUPDATE_STDERR="$HALOUPDATE_DIR/haloupdate.stderr"
: > "$HALOUPDATE_LOG"
: > "$HALOUPDATE_STDOUT"
: > "$HALOUPDATE_STDERR"
cp '@PATCH_SRC@' "$DESTDIR/_halopat.tmp"
chmod u+w "$DESTDIR/_halopat.tmp"

cp @HALO_PATCH_PAYLOAD@/haloupdate.exe "$DESTDIR"/

VERSION_KEY_HKLM='HKLM\@HALO_REGISTRY_KEY@'
VERSION_KEY_HKCU='HKCU\@HALO_REGISTRY_KEY@'

@WINE_EXE@ reg add "$VERSION_KEY_HKLM" /v "EXE Path" /d "@HALO_UPDATE_LOCATION@" /f
@WINE_EXE@ reg add "$VERSION_KEY_HKLM" /v "Version" /d "@CURRENT_VERSION@" /f
@WINE_EXE@ reg delete "$VERSION_KEY_HKLM" /v "PendingVersion" /f || true
@WINE_EXE@ reg add "$VERSION_KEY_HKCU" /v "EXE Path" /d "@HALO_UPDATE_LOCATION@" /f
@WINE_EXE@ reg add "$VERSION_KEY_HKCU" /v "Version" /d "@CURRENT_VERSION@" /f
@WINE_EXE@ reg delete "$VERSION_KEY_HKCU" /v "PendingVersion" /f || true
@WINE_EXE@ reg add "$VERSION_KEY_HKLM" /v "PendingVersion" /d "@TARGET_VERSION@" /f
@WINE_EXE@ reg add "$VERSION_KEY_HKCU" /v "PendingVersion" /d "@TARGET_VERSION@" /f

pushd "$DESTDIR" >/dev/null
@WINE_EXE@ "$DESTDIR/haloupdate.exe" \
  'processexe="@PATCH_SRC_WIN@"' \
  'updateversion="@TARGET_VERSION@"' \
  'waitprocessid=0' \
  'noextrawait=1' \
  'autoexecmode=1' \
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

echo "Copying maps..."
cp @REFINED_MAPS@/maps/* "$DESTDIR/maps/"
echo "Done"

echo "Installing Chimera..."
cp @CHIMERA@/chimera.ini "$DESTDIR"
cp -r @CHIMERA@/fonts "$DESTDIR"
cp @CHIMERA@/strings.dll "$DESTDIR"
echo "Done"

@WINE_EXE@ tasklist || true
