{
  pkgs,
}:
let
  system = pkgs.stdenv.hostPlatform.system;
in
{
  preferredNamespaceByApp =
    {
      aarch64-linux = {
        halo-custom-edition = "x64Fex";
      };
      x86_64-linux = {
        halo-custom-edition = "native";
      };
    }
    .${system}
    or { };
}
