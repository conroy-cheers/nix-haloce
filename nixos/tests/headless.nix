{
  pkgs,
  self,
}:
let
  fakeHalo = pkgs.writeShellScriptBin "haloce" ''
    set -eu

    mkdir -p "$HOME/.local/state/nix-haloce"
    printf '%s\n' "$@" >"$HOME/.local/state/nix-haloce/argv"
    touch /tmp/halo-ce-session-started
    exec ${pkgs.coreutils}/bin/sleep infinity
  '';
in
pkgs.testers.nixosTest {
  name = "nix-haloce-headless";
  meta.timeout = 180;

  nodes.machine =
    {
      lib,
      pkgs,
      ...
    }:
    {
      imports = [ ../modules/haloce-kiosk.nix ];

      nixpkgs.overlays = [ self.overlays.default ];

      nix-haloce.kiosk = {
        enable = true;
        package = fakeHalo;
        arguments = [
          "-console"
          "-screenshot"
        ];
      };

      documentation.enable = lib.mkForce false;
      virtualisation.memorySize = 2048;
      virtualisation.fileSystems."/home" = {
        device = "tmpfs";
        fsType = "tmpfs";
        options = [
          "mode=0755"
          "size=25%"
        ];
      };
      virtualisation.qemu.options = [
        "-vga"
        "none"
        "-device"
        "virtio-gpu-pci"
      ];
      services.xserver.videoDrivers = lib.mkForce [ "modesetting" ];
    };

  testScript = ''
    start_all()

    machine.wait_for_unit("multi-user.target")
    machine.wait_for_unit("display-manager.service")
    try:
        machine.wait_until_succeeds("test -e /tmp/halo-ce-session-started", timeout=60)
    except Exception:
        print(machine.succeed("systemctl --no-pager --full status display-manager.service || true"))
        print(machine.succeed("journalctl -b --no-pager -u display-manager.service -u systemd-tmpfiles-setup.service || true"))
        print(machine.succeed("loginctl || true"))
        raise

    machine.succeed("pgrep -u halo -f 'sleep infinity'")
    machine.succeed("grep -qx -- '-console' /home/halo/.local/state/nix-haloce/argv")
    machine.succeed("grep -qx -- '-screenshot' /home/halo/.local/state/nix-haloce/argv")
    machine.succeed("findmnt -no FSTYPE /home | grep -qx tmpfs")
    machine.succeed("findmnt -no FSTYPE /tmp | grep -qx tmpfs")
    machine.succeed("test -L /run/opengl-driver")
    machine.succeed("test -L /run/opengl-driver-32")
  '';
}
