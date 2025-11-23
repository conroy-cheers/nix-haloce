{
  packages,
}:
let
  mkApp = name: pkg: {
    type = "app";
    program = "${pkg}/bin/${pkg.meta.executableName}";
  };

  apps = builtins.mapAttrs mkApp packages;
in
apps
// {
  default = apps.halo-custom-edition;
}
