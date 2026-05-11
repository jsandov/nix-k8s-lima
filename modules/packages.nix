{ pkgs }:

[
  # Container tools
  pkgs.colima           # Container runtime manager and VM for Docker/Kubernetes dev
  pkgs.docker           # Docker CLI for managing containers
  pkgs.docker-compose   # Define and run multi-container Docker applications
  pkgs.dive             # Container image inspection and layer analysis
  pkgs.lazydocker       # Simple terminal UI for both docker and docker-compose
  pkgs.lima             # Lightweight VM manager for running Linux VMs (supports RKE2)

  # Kubernetes tools
  pkgs.k9s              # Interactive TUI for K8s clusters (best for real-time monitoring)
  pkgs.kubectl          # Main K8s CLI (official Kubernetes command-line tool)
  pkgs.kubectx          # Context and namespace switching (includes kubens)
  pkgs.kube-score       # Manifest static analysis (checks best practices)
  pkgs.krew             # Kubectl plugin manager (extends kubectl functionality)
  pkgs.stern            # Pod log streamer (tail logs from multiple pods at once)
  pkgs.popeye           # Cluster linting/hygiene checker (identifies issues)
  pkgs.kind             # Kubernetes IN Docker (run local K8s clusters using Docker containers)
]
