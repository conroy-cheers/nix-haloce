# Halo CE ARM64 Bring-Up Journal

## 2026-03-21

- Switched the flake to the newer multi-platform layout with flat `packages` and `apps` outputs plus richer `legacyPackages`.
- Reworked Halo packaging to consume a runtime module scope from `nix-overlayfs` instead of hard-coding legacy Wine module sets.
- Moved runtime selection to host-specific namespaces so `x86_64-linux` uses the native WoW64 path and `aarch64-linux` uses the ARM64EC/FEX path.
- Removed the old win32-prefix-to-wow64 registry graft from the main package path and now install directly into the selected runtime prefix under `Program Files (x86)`.
- Dropped the `dxvk` overlay from the default Halo runtime because the current local `nix-overlayfs` checkout still recurses when its `dxvk` wine-module is forced; getting the native ARM64EC/FEX runtime working takes priority.
- Split install-time prefix generation from runtime composition so `aarch64-linux` can reuse an `x86_64-linux`-built Halo prefix instead of executing the legacy x86 patcher inside the ARM64EC/FEX environment.
- When that cross-system path turned out to be unavailable under the current Nix policy, switched the `aarch64-linux` installer path to a prepatched portable `v1.10` payload from the HaloCustomEdition GitHub mirror instead of the crashing official updater.
- Restored the DXVK overlay on `aarch64-linux` with explicit package plumbing from the flake so the ARM64EC/FEX runtime can use native Vulkan-backed D3D9 on Asahi.
- Added Mesa/Asahi Vulkan environment setup plus runtime overrides for Wine user data, DXVK logging, and first-run cleanup so the generated overlay stays reproducible across 4k and 16k page-size systems.
- Patched the portable `haloce.exe` during install on `aarch64-linux` at the two startup failure sites that blocked the renderer from reaching the title screen under the ARM64EC/FEX runtime.
- Captured the live `Halo` Xwayland window after the declarative runtime patches and confirmed the rendered title screen via screenshot OCR of the `gearbox` and `BUNGIE` branding.
- Fixed a bad install-time patch writer that had briefly emitted literal `\xNN` ASCII into `haloce.exe` instead of raw bytes; the current store build now carries the intended binary patches at `0x11ad7f` and `0x1829ea`.
- Confirmed that a writable seeded appdir materially changes startup behavior on clean runs: without it the wrapper stalls in Wine bootstrap, while with a seeded appdir Halo reaches DXVK and the main-menu title screen.
- Tried replacing the ad hoc seeded appdir with a deterministic first-run copy from the same store layers mounted by `nix-overlayfs`; that copy now materializes the prefix tree correctly, but pristine first-launch still needs one more fix because Wine reports `could not load kernel32.dll, status c0000135` from the self-seeded appdir path.
