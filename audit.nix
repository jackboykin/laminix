{
  lib,
  writeShellApplication,
  strace,
  gawk,
  gnugrep,
  coreutils,
}:
writeShellApplication {
  name = "laminix-audit";
  runtimeInputs = [
    strace
    gawk
    gnugrep
    coreutils
  ];
  text = builtins.readFile ./audit.sh;
  meta = {
    description = "Count a command's failed file lookups by directory";
    homepage = "https://github.com/jackboykin/laminix";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "laminix-audit";
  };
}
