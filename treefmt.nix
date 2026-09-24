# nixpkgs' own Nix formatting and lint, from its ci/treefmt.nix.
{
  treefmt,
  nixf-diagnose,
  nixfmt,
  markdown-code-runner,
  writers,
}:
treefmt.withConfig {
  runtimeInputs = [
    nixf-diagnose
    nixfmt
    markdown-code-runner
  ];
  settings = {
    tree-root-file = "flake.nix";
    on-unmatched = "debug";
    formatter = {
      nixf-diagnose = {
        command = "nixf-diagnose";
        options = [ "--auto-fix" ];
        includes = [ "*.nix" ];
        priority = -1;
      };
      nixfmt = {
        command = "nixfmt";
        includes = [ "*.nix" ];
      };
      markdown-code-runner = {
        command = "mdcr";
        options = [
          "--config=${
            writers.writeTOML "markdown-code-runner-config" {
              presets.nixfmt = {
                language = "nix";
                command = [ "nixfmt" ];
              };
            }
          }"
        ];
        includes = [ "*.md" ];
      };
    };
  };
}
