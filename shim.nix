{
  lib,
  runCommandLocal,
  makeBinaryWrapper,
}:
{
  pairs,
  exclude,
}:
let
  passthroughOutputs = [
    "dev"
    "debug"
    "devdoc"
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
      nativeBuildInputs = [ makeBinaryWrapper ];
      passthru =
        (pkg.passthru or { })
        // lib.genAttrs (lib.intersectLists passthroughOutputs pkg.outputs) (o: pkg.${o})
        // {
          laminix = true;
        }
        # overrideAttrs stays the shim's own: testers.testBuildFailure needs it.
        // lib.optionalAttrs (pkg ? override) {
          override = args: shim (pkg.override args);
        };
      # buildEnv resolves outputs as drv.${name}, so passthrough ones still work.
      inherit (pkg) meta;
    } "source ${./shim.sh}";
in
shim
