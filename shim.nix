{
  lib,
  runCommandLocal,
  makeBinaryWrapper,
  binutils-unwrapped,
}:
{
  pairs,
  exclude,
}:
let
  # Nothing runs from these, so a shim doesn't read them or need them to exist.
  passthroughOutputs = [
    "dev"
    "debug"
    "devdoc"
    "devtools"
    "python"
  ];

  shim =
    pkg:
    let
      outputs = lib.subtractLists passthroughOutputs pkg.outputs;
    in
    runCommandLocal pkg.name {
      inherit outputs;
      srcPaths = map (o: "${pkg.${o}}") outputs;
      pairs = toString pairs;
      exclude = toString exclude;
      inherit (makeBinaryWrapper) extractCmd;
      # 26.05's extractCmd runs strings from PATH.
      nativeBuildInputs = [
        makeBinaryWrapper
        binutils-unwrapped
      ];
      passthru =
        (pkg.passthru or { })
        // lib.intersectAttrs {
          pname = null;
          version = null;
        } pkg
        // lib.genAttrs (lib.intersectLists passthroughOutputs pkg.outputs) (o: pkg.${o})
        // {
          laminix = true;
        };
      # buildEnv resolves outputs as drv.${name}, so passthrough ones still work.
      inherit (pkg) meta;
    } "source ${./shim.sh}";
in
shim
