{
  pkgs,
  shim,
  checkProfile,
}:
let
  inherit (pkgs)
    lib
    runCommand
    makeBinaryWrapper
    testers
    ;
  extract = makeBinaryWrapper.extractCmd;
  # Unlike multicall coreutils, this ignores argv0.
  true' = "${pkgs.runCommandCC "laminix-test-true" { } ''
    echo 'int main(void) { return 0; }' | $CC -x c - -o $out
  ''}";

  shimWith = shim {
    pairs = [
      "XDG_DATA_DIRS:share"
      "QT_PLUGIN_PATH:lib/qt-6/plugins"
    ];
    exclude = [ "share/dbus-1" ];
  };

  profile =
    name: paths:
    pkgs.buildEnv {
      inherit name paths;
      nativeBuildInputs = [ pkgs.binutils-unwrapped ];
      postBuild = ''
        extractCmd=${extract}
        source ${checkProfile}
      '';
    };

  dep = runCommand "laminix-test-dep" { } ''
    mkdir -p $out/share/icons/hicolor $out/share/dbus-1/services $out/lib/qt-6/plugins $out/share/gsettings-schemas/dep
    touch $out/share/icons/hicolor/dep.png $out/share/dbus-1/services/dep.service
    touch $out/lib/qt-6/plugins/dep.so $out/share/gsettings-schemas/dep/schema
  '';

  dep2 = runCommand "laminix-test-dep2" { } "mkdir -p $out/share; touch $out/share/dep2-marker";

  mkApp =
    name: extra:
    runCommand name
      {
        nativeBuildInputs = [ makeBinaryWrapper ];
        outputs = [
          "out"
          "sessions"
        ];
      }
      ''
        mkdir -p $out/bin $out/share/applications $out/share/dbus-1/services $out/nix-support
        mkdir -p $out/share/plasma/plasmoids/org.laminix.widget/contents
        cp ${true'} $out/bin/.app-wrapped
        makeBinaryWrapper $out/bin/.app-wrapped $out/bin/app --inherit-argv0 \
          --prefix XDG_DATA_DIRS : ${dep}/share \
          --prefix QT_PLUGIN_PATH : ${dep}/lib/qt-6/plugins \
          --prefix XDG_DATA_DIRS : ${dep}/share/gsettings-schemas/dep \
          --set-default LAMINIX_TEST kept
        cp ${true'} $out/bin/.bare-wrapped
        makeBinaryWrapper $out/bin/.bare-wrapped $out/bin/bare --inherit-argv0 \
          --prefix XDG_DATA_DIRS : ${dep}/share
        printf '[Desktop Entry]\nExec=%s %%U\nX-KDE-Wayland-Interfaces=org_kde_plasma_window_management\n' \
          $out/bin/bare >$out/share/applications/bare.desktop
        printf '[D-BUS Service]\nExec=%s\n' $out/bin/app >$out/share/dbus-1/services/app.service
        echo '{}' >$out/share/plasma/plasmoids/org.laminix.widget/metadata.json
        echo 'Item {}' >$out/share/plasma/plasmoids/org.laminix.widget/contents/main.qml

        cp ${true'} $out/bin/.twice-wrapped
        makeBinaryWrapper $out/bin/.twice-wrapped $out/bin/.twice-wrapped_ --inherit-argv0 \
          --prefix QT_PLUGIN_PATH : ${dep}/lib/qt-6/plugins
        makeBinaryWrapper $out/bin/.twice-wrapped_ $out/bin/twice --inherit-argv0 \
          --prefix XDG_DATA_DIRS : ${dep}/share
        printf '[Desktop Entry]\nExec=%s\nX-KDE-Wayland-Interfaces=org_kde_plasma_window_management\n' \
          $out/bin/twice >$out/share/applications/twice.desktop
        makeBinaryWrapper $out/bin/.app-wrapped $out/bin/suffixed --inherit-argv0 \
          --suffix XDG_DATA_DIRS : ${dep}/share
        makeBinaryWrapper ${true'} $out/bin/external --inherit-argv0 \
          --prefix XDG_DATA_DIRS : ${dep}/share

        echo ${dep2} >$out/nix-support/propagated-user-env-packages
        mkdir -p $sessions/share/wayland-sessions
        printf '[Desktop Entry]\nExec=%s\n' $out/bin/app >$sessions/share/wayland-sessions/app.desktop
        ${extra}
      '';

  app = mkApp "laminix-test-app" "";
  shimmed = shimWith app;
  env = profile "laminix-test-env" [ shimmed ];

  fails =
    drv: pattern:
    runCommand "${drv.name}-fails" { } ''
      grep -F ${lib.escapeShellArg pattern} ${testers.testBuildFailure drv}/testBuildFailure.log
      touch $out
    '';

  splitApp = mkApp "laminix-test-split" ''
    echo "$out/bin/app" >$out/share/plasma/plasmoids/org.laminix.widget/contents/launch
  '';

  plain = runCommand "laminix-test-plain" { } "mkdir -p $out/bin; cp ${true'} $out/bin/plain";

  untrusted = runCommand "laminix-test-untrusted" { } ''
    mkdir -p $out/bin $out/share/applications
    cp ${true'} $out/bin/.bare-wrapped
    ln -s $out/bin/.bare-wrapped $out/bin/bare
    printf '[Desktop Entry]\nExec=%s\nX-KDE-Wayland-Interfaces=org_kde_plasma_window_management\n' \
      $out/bin/bare >$out/share/applications/bare.desktop
  '';

  untrustedLinked =
    runCommand "laminix-test-untrusted-linked" { nativeBuildInputs = [ makeBinaryWrapper ]; }
      ''
        mkdir -p $out/bin $out/share/applications
        ln -s ${true'} $out/bin/.bare-wrapped
        makeBinaryWrapper $out/bin/.bare-wrapped $out/bin/bare --inherit-argv0
        printf '[Desktop Entry]\nExec=%s\nX-KDE-Wayland-Interfaces=org_kde_plasma_window_management\n' \
          $out/bin/bare >$out/share/applications/bare.desktop
      '';

  widgetFrom =
    name: file:
    runCommand name { } ''
      mkdir -p $out/share/plasma/plasmoids/org.laminix.split
      echo '{}' >$out/share/plasma/plasmoids/org.laminix.split/${file}
    '';
in
{
  shim = runCommand "laminix-test-shim" { nativeBuildInputs = [ pkgs.binutils-unwrapped ]; } ''
    set -x
    absent() {
      if grep -qF "$1" <<<"$2"; then
        echo "unexpected: $1" >&2
        exit 1
      fi
    }
    s=${shimmed}

    cmd=$(${extract} $s/bin/app)
    absent "'${dep}/share'" "$cmd"
    absent "'${dep}/lib/qt-6/plugins'" "$cmd"
    grep -F "'${dep}/share/gsettings-schemas/dep'" <<<"$cmd"
    grep -F "'LAMINIX_TEST' 'kept'" <<<"$cmd"
    grep -F "'$s/bin/.app-wrapped'" <<<"$cmd"

    [[ -f $s/bin/bare && ! -L $s/bin/bare ]]
    cmp $s/bin/bare ${app}/bin/.bare-wrapped

    grep -F "Exec=$s/bin/bare" $s/share/applications/bare.desktop
    grep -F "Exec=$s/bin/app" $s/share/dbus-1/services/app.service

    [[ -L $s/share/plasma ]]

    cmd=$(${extract} $s/bin/twice)
    grep -F "'$s/bin/.twice-wrapped_'" <<<"$cmd"
    absent "'${dep}/share'" "$cmd"
    cmd=$(${extract} $s/bin/.twice-wrapped_)
    grep -F "'$s/bin/.twice-wrapped'" <<<"$cmd"
    absent "'${dep}/lib/qt-6/plugins'" "$cmd"
    cmp $s/bin/.twice-wrapped ${app}/bin/.twice-wrapped

    [[ -f $s/bin/suffixed && ! -L $s/bin/suffixed ]]

    cmd=$(${extract} $s/bin/external)
    grep -F "'${true'}'" <<<"$cmd"
    absent "'${dep}/share'" "$cmd"

    grep -F ${dep2} $s/nix-support/propagated-user-env-packages

    grep -F "Exec=$s/bin/app" ${shimmed.sessions}/share/wayland-sessions/app.desktop

    e=${env}
    [[ -e $e/share/icons/hicolor/dep.png ]]
    [[ -e $e/lib/qt-6/plugins/dep.so ]]
    [[ ! -e $e/share/dbus-1/services/dep.service ]]
    [[ -e $e/share/dbus-1/services/app.service ]]
    [[ -e $e/share/dep2-marker ]]

    for b in app bare twice suffixed external; do
      $e/bin/$b
    done
    touch $out
  '';

  shim-refuses-kpackage-split = fails (shimWith splitApp) "would split KPackage share/plasma/plasmoids/org.laminix.widget";
  shim-refuses-unwrapped = fails (shimWith plain) "found no binary wrappers";
  shim-failure-names-laminix = fails (shimWith plain) "laminix: failed to shim laminix-test-plain";
  profile-refuses-untrusted = fails (profile "laminix-test-untrusted-env" [
    untrusted
  ]) "kwin won't trust";
  profile-refuses-untrusted-linked = fails (profile "laminix-test-untrusted-linked-env" [
    untrustedLinked
  ]) "kwin won't trust";
  profile-refuses-kpackage-split = fails (profile "laminix-test-split-env" [
    (widgetFrom "laminix-test-widget-a" "metadata.json")
    (widgetFrom "laminix-test-widget-b" "main.qml")
  ]) "split KPackage";
}
