{
  config,
  lib,
  modulesPath,
  pkgs,
  ...
}:
{
  imports = [
    "${modulesPath}/installer/cd-dvd/installation-cd-graphical-base.nix"
    ./modules/haloce-kiosk.nix
  ];

  nix-haloce.kiosk.enable = true;

  nixpkgs.config.allowUnfree = true;

  networking.hostName = "haloce";

  boot = {
    kernelPackages = lib.mkDefault pkgs.linuxPackages_latest;
    kernelParams = [ "copytoram" ];
    loader.timeout = lib.mkDefault 3;
    supportedFilesystems = {
      bcachefs = true;
      zfs = lib.mkForce false;
    };
  };

  fileSystems = lib.mkForce (
    config.lib.isoFileSystems
    // {
      "/home" = {
        device = "tmpfs";
        fsType = "tmpfs";
        options = [
          "mode=0755"
          "size=25%"
        ];
      };
    }
  );

  isoImage = {
    edition = "halo-ce";
    volumeID = "NIXOS_HALOCE";
    configurationName = "Halo CE live";
    appendToMenuLabel = " Halo CE";
    makeEfiBootable = true;
    makeUsbBootable = true;
  };

  documentation.enable = lib.mkForce false;
  documentation.nixos.enable = lib.mkForce false;
  programs.git.enable = lib.mkForce false;
  services.openssh.enable = lib.mkForce false;

  system.nixos.variant_id = "haloce-live";
}
