[
  "awscli"   # AWS command-line interface
  # helm is now provided by nixpkgs (pkgs.kubernetes-helm in packages.nix) so the
  # ai-gw-* gateway install is nix-native and version-consistent. Re-add here only
  # if you specifically want Homebrew's helm — but avoid two helms on PATH.
  "eksctl"   # Simple command-line tool for creating clusters on Amazon EKS
  "grafana"  # Metrics visualization platform
]
