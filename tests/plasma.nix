{
  pkgs,
  module,
}:
pkgs.testers.runNixOSTest {
  name = "laminix-plasma";
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
    security.polkit.extraConfig = ''
      polkit.addRule(function (action, subject) {
        if (action.id == "org.kde.kio.admin.commands" && subject.user == "alice") return polkit.Result.YES;
      });
    '';
    environment.laminix = {
      enable = true;
      pruneProfiles = true;
    };
    virtualisation = {
      memorySize = 3072;
      qemu.options = [ "-vga none -device virtio-gpu-pci" ];
    };
  };

  testScript = ''
    start_all()
    machine.wait_until_succeeds("pgrep -x plasmashell", timeout=300)
    machine.wait_until_succeeds("pgrep -f bin/.kwin_wayland-wrapped", timeout=60)
    wayland = machine.succeed("tr '\\0' '\\n' </proc/$(pgrep -x plasmashell)/environ | grep ^WAYLAND_DISPLAY=").strip()

    def stray(comm):
        env = machine.succeed(f"tr '\\0' '\\n' </proc/$(pgrep -x '{comm}' | head -n1)/environ | grep ^XDG_DATA_DIRS=")
        dirs = env.strip().split("=", 1)[1].split(":")
        return [d for d in dirs if d.startswith("/nix/store/") and not d.endswith("-desktops/share")]

    with subtest("Plasma searches no per-dependency store paths"):
        assert not stray("plasmashell"), stray("plasmashell")

    with subtest("Dolphin draws its window and searches no per-dependency store paths"):
        machine.execute(f"su - alice -c 'XDG_RUNTIME_DIR=/run/user/1000 {wayland} dolphin >&2 &'")
        machine.wait_for_text("Dolphin", timeout=120)
        machine.screenshot("session")
        assert not stray("dolphin|\\.dolphin-wrappe"), stray("dolphin|\\.dolphin-wrappe")

    with subtest("Helpers the system bus starts keep their wrappers"):
        machine.succeed("su - alice -c 'XDG_RUNTIME_DIR=/run/user/1000 QT_QPA_PLATFORM=offscreen kioclient ls admin:///etc' | grep -x passwd")

    with subtest("Session trusts shims and loads KPackages"):
        journal = machine.succeed("journalctl -b --no-pager -o cat")
        assert "PlasmaWindowManagement protocol hasn't activated" not in journal, "kwin denied plasmashell"
        assert "Path traversal attempt" not in journal, "a KPackage was split"
  '';
}
