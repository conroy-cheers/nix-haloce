# Halo Custom Edition

Fully reproducible Halo Custom Edition, thanks to [nix-overlayfs](https://github.com/conroy-cheers/nix-overlayfs)

## Usage

```
nix run github:conroy-cheers/nix-haloce
```

On Ubuntu and other non-NixOS hosts, run Halo through nixGL wrappers selected
for the host GPU. DXVK needs the Vulkan wrapper as well as the OpenGL wrapper:

```sh
# Mesa (Intel, AMD, or Nouveau)
nixVulkanIntel nixGLIntel nix run github:conroy-cheers/nix-haloce

# Proprietary NVIDIA
nixVulkanNvidia nixGLNvidia nix run github:conroy-cheers/nix-haloce
```

Build nixGL from the same nixpkgs revision as this flake to keep its graphics
userspace and glibc compatible. The package's default graphics mode preserves
the environment supplied by nixGL.

Halo explicitly uses Wine's Pulse audio backend. It works with either a native
PulseAudio server or PipeWire's PulseAudio-compatible server exposed through
the user's runtime directory. Its rootless FUSE overlay runs in direct mode so
the audio server sees the caller's normal credentials.

For local testing against the ARM64EC/FEX checkout:

```sh
nix run .#halo-custom-edition --override-input nix-overlayfs ~/src/nix-overlayfs
```

On `aarch64-linux`, the wrapper defaults to `NIX_OVERLAYFS_GRAPHICS_STACK=auto`, which leaves GL/EGL/Vulkan discovery to the host environment.

The only explicit override now is:

- `NIX_OVERLAYFS_GRAPHICS_STACK=system` uses `/run/opengl-driver` when the host exposes one

If you are running on NVIDIA Jetson or another NixOS ARM64 system with a valid `/run/opengl-driver`, prefer:

```sh
NIX_OVERLAYFS_GRAPHICS_STACK=system nix run .#halo-custom-edition
```

If DXVK fails to initialize on your host Vulkan stack, you can fall back to
Wine's builtin D3D path at runtime:

```sh
HALO_USE_DXVK=0 NIX_OVERLAYFS_GRAPHICS_STACK=system nix run .#halo-custom-edition
```

On `aarch64-linux`, this package currently defaults to legacy `dxvk_1`
(`1.10.3`) instead of DXVK `2.7.1`, since current DXVK requires newer Vulkan
features such as `VK_KHR_maintenance5` that are missing on some Jetson-class
drivers.

If you consume `nix-haloce` as an overlay or through `legacyPackages`, the Halo
package is overrideable and the available DXVK choices are exposed under
`moduleScopes.runtimeSupport.dxvkPackages`:

```nix
let
  pkgs = import nixpkgs {
    system = "aarch64-linux";
    overlays = [ nix-haloce.overlays.default ];
    config.allowUnsupportedSystem = true;
  };
in
pkgs.nix-haloce.packages.halo-custom-edition.override {
  dxvkPackage = pkgs.nix-haloce.moduleScopes.runtimeSupport.dxvkPackages.current;
}
```

Use `dxvkPackages.current` for DXVK `2.7.1` and `dxvkPackages.legacy` for DXVK
`1.10.3`.

The flake follows the newer `nix-overlayfs` layout:

- `packages.<system>` exposes only buildable derivations
- `apps.<system>` exposes only flat runnable apps
- `legacyPackages.<system>.nix-haloce` exposes the richer package set, including runtime-namespaced variants

## Live USB

This flake also exposes a NixOS live configuration that boots straight into
Halo Custom Edition:

```sh
nix build .#haloce-live-iso
```

The resulting ISO is a hybrid USB image and can be written directly to a USB
stick:

```sh
sudo dd if=result/iso/*.iso of=/dev/disk/by-id/<usb-device> bs=4M status=progress oflag=sync
```

The default boot entry includes `copytoram`, and the live system uses tmpfs for
the root and home filesystems, so the USB stick can be removed after boot
finishes. The same image is also available as `.#haloce-usb-image`.

The headless QEMU regression test is exposed as:

```sh
nix build .#checks.x86_64-linux.haloce-headless
```

The package-build regression test forces Halo's installer through the portable
materialized-prefix path used when build namespaces are unavailable:

```sh
nix build .#checks.x86_64-linux.haloce-direct-build
```

The non-NixOS compatibility check boots a pinned Ubuntu 24.04 cloud image with
outbound networking disabled, installs a pinned Nix in the guest, and runs this
flake's real Halo package under Xvfb:

```sh
nix build .#checks.x86_64-linux.haloce-ubuntu-24-04-headless
```

This check requires a builder with the Nix `kvm` system feature.
It keeps Ubuntu's AppArmor user-namespace restriction enabled, proves the
namespace-required launch is rejected, then verifies that the package's default
auto mode falls back to direct rootless FUSE and creates the Halo window.
