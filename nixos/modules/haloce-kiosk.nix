{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.nix-haloce.kiosk;

  haloExecutable = lib.getExe' cfg.package cfg.executableName;
  haloArguments = lib.escapeShellArgs cfg.arguments;

  haloSessionScript = pkgs.writeShellScriptBin "halo-ce-session" ''
    set -u

    export NIX_OVERLAYFS_GRAPHICS_STACK="''${NIX_OVERLAYFS_GRAPHICS_STACK:-system}"

    if [ -z "''${HALO_USE_DXVK+x}" ]; then
      if ${lib.getExe' pkgs.vulkan-tools "vulkaninfo"} --summary >/dev/null 2>&1; then
        export HALO_USE_DXVK=1
      else
        export HALO_USE_DXVK=0
      fi
    fi

    ${lib.getExe pkgs.xset} -dpms >/dev/null 2>&1 || true
    ${lib.getExe pkgs.xset} s off >/dev/null 2>&1 || true
    ${lib.getExe pkgs.xsetroot} -solid black >/dev/null 2>&1 || true

    ${lib.getExe' pkgs.openbox "openbox"} &
    window_manager_pid=$!

    cleanup() {
      kill "$window_manager_pid" >/dev/null 2>&1 || true
    }
    trap cleanup EXIT

    while true; do
      ${haloExecutable} ${haloArguments}
      status=$?
      echo "Halo CE exited with status $status; restarting in 3 seconds" >&2
      sleep 3
    done
  '';

  haloSessionPackage = pkgs.runCommand "halo-ce-xsession" {
    passthru.providedSessions = [ cfg.sessionName ];
  } ''
    mkdir -p "$out/share/xsessions"
    cat >"$out/share/xsessions/${cfg.sessionName}.desktop" <<EOF
    [Desktop Entry]
    Name=Halo Custom Edition
    Comment=Launch Halo Custom Edition
    Exec=${haloSessionScript}/bin/halo-ce-session
    Type=Application
    DesktopNames=HaloCE
    EOF
  '';
in
{
  options.nix-haloce.kiosk = {
    enable = lib.mkEnableOption "a single-purpose Halo Custom Edition graphical session";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.nix-haloce.packages.halo-custom-edition;
      defaultText = lib.literalExpression "pkgs.nix-haloce.packages.halo-custom-edition";
      description = "Package providing the Halo Custom Edition launcher.";
    };

    executableName = lib.mkOption {
      type = lib.types.str;
      default = "haloce";
      description = "Executable inside the configured Halo package to run.";
    };

    arguments = lib.mkOption {
      type = with lib.types; listOf str;
      default = [ ];
      example = [
        "-vidmode"
        "1280,720,60"
      ];
      description = "Arguments passed to the Halo launcher.";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "halo";
      description = "Unprivileged user that runs the Halo session.";
    };

    sessionName = lib.mkOption {
      type = lib.types.str;
      default = "halo-ce";
      description = "Display-manager session name for the Halo kiosk session.";
    };
  };

  config = lib.mkIf cfg.enable {
    users.users.${cfg.user} = {
      isNormalUser = true;
      createHome = true;
      home = "/home/${cfg.user}";
      initialHashedPassword = "";
      extraGroups = [
        "audio"
        "input"
        "networkmanager"
        "render"
        "video"
      ];
    };

    fileSystems."/home" = {
      device = "tmpfs";
      fsType = "tmpfs";
      options = [
        "mode=0755"
        "size=25%"
      ];
    };

    systemd.tmpfiles.rules = [
      "d /home/${cfg.user} 0755 ${cfg.user} users - -"
    ];

    boot.tmp = {
      useTmpfs = true;
      tmpfsSize = "50%";
    };

    services.xserver = {
      enable = true;
      videoDrivers = lib.mkDefault [
        "modesetting"
        "fbdev"
        "vesa"
      ];
      displayManager.lightdm = {
        enable = true;
        greeter.enable = false;
        autoLogin.timeout = 0;
      };
    };

    services.displayManager = {
      defaultSession = cfg.sessionName;
      sessionPackages = [ haloSessionPackage ];
      autoLogin = {
        enable = true;
        user = cfg.user;
      };
    };

    hardware = {
      bluetooth.enable = lib.mkDefault true;
      graphics = {
        enable = true;
        enable32Bit = pkgs.stdenv.hostPlatform.isx86_64;
      };
      steam-hardware.enable = true;
    };

    security.rtkit.enable = true;

    services.pipewire = {
      enable = true;
      audio.enable = true;
      pulse.enable = true;
      alsa = {
        enable = true;
        support32Bit = pkgs.stdenv.hostPlatform.isx86_64;
      };
    };

    environment.systemPackages = [
      cfg.package
      pkgs.mesa-demos
      pkgs.networkmanager
      pkgs.openbox
      pkgs.pciutils
      pkgs.usbutils
      pkgs.vulkan-tools
    ];

    services.udev.packages = [ pkgs.game-devices-udev-rules ];
  };
}
