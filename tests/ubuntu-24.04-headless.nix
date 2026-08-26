{
  pkgs,
  haloPackage,
}:
let
  ubuntuImage = pkgs.fetchurl {
    url = "https://cloud-images.ubuntu.com/releases/noble/release-20260814/ubuntu-24.04-server-cloudimg-amd64.img";
    hash = "sha256-bkDAeucV90T4SvC+x2QVzBmH3RFbS43kN4GFYfAaNzM=";
  };

  # Keep guest evaluation tiny and offline while still making `nix run` execute
  # the exact package produced by this repository's flake evaluation.
  haloRunnerFlake = pkgs.writeTextDir "flake.nix" ''
    {
      outputs = { self }: {
        apps.x86_64-linux.default = {
          type = "app";
          program = "${haloPackage}/bin/${haloPackage.meta.executableName}";
        };
      };
    }
  '';

  storeClosure = pkgs.closureInfo {
    rootPaths = [
      pkgs.nix
      haloPackage
      haloRunnerFlake
    ];
  };

  guestTest = pkgs.writeShellScript "nix-haloce-ubuntu-24.04-headless-test" ''
    set -euo pipefail

    exec > /dev/ttyS0 2>&1

    test_succeeded=false
    failed_line=unknown
    failed_command=unknown
    finish() {
      status=$?
      trap - ERR EXIT
      if [ "$test_succeeded" != true ]; then
        echo "HALOCE_UBUNTU_TEST_FAILURE (status $status at line $failed_line: $failed_command)"
        printf 'status %s at line %s: %s\n' "$status" "$failed_line" "$failed_command" \
          >/run/test-result/failure
        for log in /tmp/nix-daemon.log /tmp/xvfb.log /tmp/haloce-required.log /tmp/haloce.log /tmp/processes.log /tmp/windows.log; do
          if [ -f "$log" ]; then
            echo "--- $log"
            cat "$log"
            cp "$log" "/run/test-result/$(basename "$log")" || true
          fi
        done
        sync /run/test-result
        systemctl poweroff --force
        exit "$status"
      fi
    }
    trap 'failed_line=$LINENO; failed_command=$BASH_COMMAND' ERR
    trap finish EXIT

    . /etc/os-release
    test "$ID" = ubuntu
    test "$VERSION_ID" = 24.04
    # Model Ubuntu's defaults: do not relax its AppArmor user-namespace policy.
    test "$(cat /proc/sys/kernel/apparmor_restrict_unprivileged_userns)" = 1

    install -d -m 0755 \
      /etc/nix \
      /nix/var/log/nix/drvs \
      /nix/var/nix/daemon-socket \
      /nix/var/nix/db \
      /nix/var/nix/gcroots/per-user \
      /nix/var/nix/profiles/per-user
    ${pkgs.nix}/bin/nix-store --load-db < ${storeClosure}/registration
    ln -s ${pkgs.nix} /nix/var/nix/profiles/default
    cat >/etc/nix/nix.conf <<'EOF'
    experimental-features = nix-command flakes
    sandbox = false
    trusted-users = root ubuntu
    EOF

    ${pkgs.nix}/bin/nix-daemon >/tmp/nix-daemon.log 2>&1 &
    nix_daemon_pid=$!
    for _ in $(seq 1 30); do
      if [ -S /nix/var/nix/daemon-socket/socket ]; then
        break
      fi
      sleep 1
    done
    test -S /nix/var/nix/daemon-socket/socket

    runuser -u ubuntu -- env \
      HOME=/home/ubuntu \
      NIX_REMOTE=daemon \
      ${pkgs.nix}/bin/nix --version
    echo "HALOCE_UBUNTU_TEST_STAGE nix-installed"

    modprobe fuse
    test -c /dev/fuse

    id ubuntu
    install -d -m 0700 -o ubuntu -g ubuntu /run/user/1000

    runuser -u ubuntu -- env \
      HOME=/home/ubuntu \
      XDG_RUNTIME_DIR=/run/user/1000 \
      ${pkgs.xorg-server}/bin/Xvfb :99 -screen 0 1024x768x24 -nolisten tcp \
      >/tmp/xvfb.log 2>&1 &
    xvfb_pid=$!

    for _ in $(seq 1 30); do
      if runuser -u ubuntu -- env DISPLAY=:99 ${pkgs.xdpyinfo}/bin/xdpyinfo >/dev/null 2>&1; then
        break
      fi
      sleep 1
    done
    runuser -u ubuntu -- env DISPLAY=:99 ${pkgs.xdpyinfo}/bin/xdpyinfo >/dev/null
    echo "HALOCE_UBUNTU_TEST_STAGE xvfb-ready"

    set +e
    runuser -u ubuntu -- env \
      DISPLAY=:99 \
      HOME=/home/ubuntu \
      USER=ubuntu \
      XDG_RUNTIME_DIR=/run/user/1000 \
      NIX_REMOTE=daemon \
      NIX_OVERLAYFS_NAMESPACE_MODE=required \
      HALO_USE_DXVK=0 \
      WINEDEBUG=-all \
      ${pkgs.nix}/bin/nix run \
        --offline \
        path:${haloRunnerFlake} \
        -- -window -nosound \
      >/tmp/haloce-required.log 2>&1
    required_status=$?
    set -e
    test "$required_status" -ne 0
    grep -F '/proc/self/uid_map: Operation not permitted' /tmp/haloce-required.log
    echo "HALOCE_UBUNTU_TEST_STAGE required-mode-rejected"

    # No namespace override: exercise the package's declarative auto default.
    runuser -u ubuntu -- env \
      DISPLAY=:99 \
      HOME=/home/ubuntu \
      USER=ubuntu \
      XDG_RUNTIME_DIR=/run/user/1000 \
      NIX_REMOTE=daemon \
      HALO_USE_DXVK=0 \
      WINEDEBUG=-all \
      ${pkgs.nix}/bin/nix run \
        --offline \
        path:${haloRunnerFlake} \
        -- -window -nosound \
      >/tmp/haloce.log 2>&1 &
    launcher_pid=$!
    echo "HALOCE_UBUNTU_TEST_STAGE nix-run-started"

    halo_window=""
    for _ in $(seq 1 180); do
      if ! kill -0 "$launcher_pid" 2>/dev/null; then
        wait "$launcher_pid"
      fi
      halo_window="$(${pkgs.xwininfo}/bin/xwininfo -display :99 -root -tree 2>/dev/null | grep -i '"Halo"' || true)"
      if [ -n "$halo_window" ]; then
        break
      fi
      sleep 1
    done

    if [ -z "$halo_window" ]; then
      echo "Halo did not create a window"
      ps -ef > /tmp/processes.log
      ${pkgs.xwininfo}/bin/xwininfo -display :99 -root -tree > /tmp/windows.log 2>&1 || true
      cat /tmp/xvfb.log
      cat /tmp/haloce.log
      false
    fi

    grep -F 'warning: nix-overlayfs: user/mount namespaces are unavailable; using direct FUSE mode' /tmp/haloce.log
    ! grep -F 'unknown argument ignored' /tmp/haloce.log
    test "$(cat /proc/sys/kernel/apparmor_restrict_unprivileged_userns)" = 1
    echo "$halo_window"
    echo "HALOCE_UBUNTU_TEST_SUCCESS"
    test_succeeded=true
    touch /run/test-result/success
    sync /run/test-result

    kill "$launcher_pid" 2>/dev/null || true
    kill "$xvfb_pid" 2>/dev/null || true
    kill "$nix_daemon_pid" 2>/dev/null || true
    systemctl poweroff
  '';

  seedImage =
    pkgs.runCommand "nix-haloce-ubuntu-24.04-cloud-init.iso"
      {
        nativeBuildInputs = [ pkgs.xorriso ];
      }
      ''
        mkdir seed
        cat >seed/meta-data <<'EOF'
        instance-id: nix-haloce-ubuntu-24.04
        local-hostname: nix-haloce-ubuntu
        EOF
        cat >seed/network-config <<'EOF'
        version: 2
        ethernets:
          test:
            match:
              name: "en*"
            dhcp4: true
        EOF
        cat >seed/user-data <<'EOF'
        #cloud-config
        package_update: false
        package_upgrade: false
        runcmd:
          - [ /bin/bash, -c, "mkdir -p /nix/store /nix/.ro-store /nix/.rw-store/upper /nix/.rw-store/work /run/test-result && mount -t 9p -o trans=virtio,version=9p2000.L,ro nixstore /nix/.ro-store && mount -t 9p -o trans=virtio,version=9p2000.L testresult /run/test-result && mount -t overlay overlay -o lowerdir=/nix/.ro-store,upperdir=/nix/.rw-store/upper,workdir=/nix/.rw-store/work /nix/store && exec ${guestTest}" ]
        EOF
        xorriso -as mkisofs -quiet -volid cidata -joliet -rock -o "$out" seed
      '';
in
pkgs.runCommand "nix-haloce-ubuntu-24.04-headless"
  {
    nativeBuildInputs = [ pkgs.qemu ];
    requiredSystemFeatures = [ "kvm" ];
    meta = {
      description = "Launch Halo Custom Edition headlessly on Ubuntu 24.04";
      timeout = 900;
    };
  }
  ''
    cp --reflink=auto ${ubuntuImage} ubuntu.qcow2
    chmod +w ubuntu.qcow2
    qemu-img resize ubuntu.qcow2 12G
    mkdir guest-result
    mkfifo serial.pipe

    tee serial.log <serial.pipe &
    tee_pid=$!
    set +e
    qemu-system-x86_64 \
      -machine accel=kvm \
      -cpu host \
      -smp 4 \
      -m 4096 \
      -nographic \
      -no-reboot \
      -nic user,restrict=on \
      -drive file=ubuntu.qcow2,format=qcow2,if=virtio \
      -drive file=${seedImage},format=raw,if=virtio,readonly=on \
      -virtfs local,path=/nix/store,mount_tag=nixstore,security_model=none,readonly=on \
      -virtfs local,path="$PWD/guest-result",mount_tag=testresult,security_model=none \
      >serial.pipe 2>&1 &
    qemu_pid=$!

    deadline=$((SECONDS + 720))
    while kill -0 "$qemu_pid" 2>/dev/null; do
      if [ -e guest-result/success ] || [ -e guest-result/failure ]; then
        break
      fi
      if [ "$SECONDS" -ge "$deadline" ]; then
        break
      fi
      sleep 1
    done

    if kill -0 "$qemu_pid" 2>/dev/null; then
      kill "$qemu_pid"
    fi
    wait "$qemu_pid"
    qemu_status=$?
    wait "$tee_pid"
    set -e

    if [ -e guest-result/failure ]; then
      echo "Ubuntu guest failure: $(cat guest-result/failure)" >&2
      for log in guest-result/*.log; do
        if [ -f "$log" ]; then
          echo "--- $log" >&2
          tail -n 80 "$log" >&2
        fi
      done
      exit 1
    fi
    if [ ! -e guest-result/success ]; then
      echo "Ubuntu guest did not report success (QEMU status $qemu_status)" >&2
      tr '\r' '\n' < serial.log | tail -n 120 >&2
      exit 1
    fi

    mkdir "$out"
    cp serial.log "$out/"
  ''
