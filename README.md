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

The flake follows the newer `nix-overlayfs` layout:

- `packages.<system>` exposes only buildable derivations
- `apps.<system>` exposes only flat runnable apps
- `legacyPackages.<system>.nix-haloce` exposes the richer package set, including runtime-namespaced variants
