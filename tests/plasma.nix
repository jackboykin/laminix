{
  pkgs,
  module,
}:
pkgs.testers.runNixOSTest {
  name = "laminix-plasma";
  # Read-only pkgs forbid the module's overlay.
  node.pkgsReadOnly = false;
  enableOCR = true;

  nodes.machine = {
    imports = [ module ];
    users.users.alice = {
      isNormalUser = true;
      password = "foobar";
    };
    services.displayManager.plasma-login-manager.enable = true;
    services.displayManager.autoLogin = {
      enable = true;
      user = "alice";
    };
    services.desktopManager.plasma6.enable = true;
    environment.laminix = {
      enable = true;
      pruneProfiles = true;
    };
    virtualisation = {
      memorySize = 3072;
      qemu.options = [ "-vga none -device virtio-gpu-pci" ];
    };
  };

  testScript =
    let
      extract = pkgs.makeBinaryWrapper.extractCmd;
      sw = "/run/current-system/sw";
    in
    ''
      start_all()
      machine.wait_until_succeeds("pgrep -x plasmashell", timeout=300)
      machine.wait_until_succeeds("pgrep -f bin/.kwin_wayland-wrapped", timeout=60)

      with subtest("Shims search no per-dependency store paths"):
          for b in ["plasmashell", "dolphin", "konsole"]:
              machine.fail(f"${extract} $(readlink -f ${sw}/bin/{b}) | grep -q XDG_DATA_DIRS")
          env = machine.succeed("tr '\\0' '\\n' </proc/$(pgrep -x plasmashell)/environ | grep ^XDG_DATA_DIRS=")
          dirs = env.strip().split("=", 1)[1].split(":")
          stray = [d for d in dirs if d.startswith("/nix/store/") and not d.endswith("-desktops/share")]
          assert not stray, stray

      with subtest("Dolphin draws its window"):
          machine.execute("su - alice -c 'XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=wayland-0 dolphin >&2 &'")
          machine.wait_for_text("Dolphin", timeout=120)
          machine.screenshot("session")

      with subtest("Session trusts shims and loads KPackages"):
          journal = machine.succeed("journalctl -b --no-pager -o cat")
          assert "PlasmaWindowManagement protocol hasn't activated" not in journal, "kwin denied plasmashell"
          assert "Path traversal attempt" not in journal, "a KPackage was split"
    '';
}
