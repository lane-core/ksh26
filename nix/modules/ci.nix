{ inputs, ... }:

{
  # Generate GitHub Actions matrix from flake checks.
  # Filters to x86_64 systems (what GitHub-hosted runners support).
  # aarch64 builds are validated locally via the linux-builder.
  flake.githubActions = inputs.nix-github-actions.lib.mkGithubMatrix {
    checks = inputs.nixpkgs.lib.getAttrs [
      "x86_64-linux"
      "x86_64-darwin"
    ] inputs.self.checks;
  };
}
