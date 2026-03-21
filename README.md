# Halo Custom Edition

Fully reproducible Halo Custom Edition, thanks to [nix-overlayfs](https://github.com/conroy-cheers/nix-overlayfs)

## Usage

```
nix run github:conroy-cheers/nix-haloce
```

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
