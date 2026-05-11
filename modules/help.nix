''
  k8s-help() {
    cat <<'HELP_EOF'
  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                      KUBERNETES & LIMA QUICKSTART
  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  🚀 START A KUBERNETES CLUSTER (Choose One):
  ────────────────────────────────────────────────────────────────────────────
    Option A: K3s (Lightweight - Recommended for quick testing)
      k8s-start                    # Start cluster
      k get nodes                  # Verify it's ready

    Option B: RKE2 (Production-grade - For realistic testing)
      rke2-start                   # Start cluster (takes 3-5 min first time)
      rke2-kubeconfig              # Connect to cluster
      k get nodes                  # Verify it's ready

  📦 DEPLOY YOUR FIRST APP (Copy & Paste):
  ────────────────────────────────────────────────────────────────────────────
    k create deployment webapp --image=nginx --port=80
    k expose deployment webapp --type=NodePort --port=80
    kgp                            # See pods
    kgs                            # See services

  🔍 ESSENTIAL DEBUGGING:
  ────────────────────────────────────────────────────────────────────────────
    kl -f <pod-name>               # Follow logs for a pod
    stern webapp                   # Stream logs from all webapp pods
    k9s                            # Interactive UI (press '?' for help)
    kdp <pod-name>                 # Describe pod (troubleshooting)

  🛑 STOP CLUSTER WHEN DONE:
  ────────────────────────────────────────────────────────────────────────────
    k8s-stop                       # Stop K3s
    rke2-stop                      # Stop RKE2

  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                      DETAILED COMMAND REFERENCE
  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  K3S CLUSTER MANAGEMENT (via Colima)
  ────────────────────────────────────────────────────────────────────────────
    k8s-start         Start K3s cluster (4 CPU, 8GB RAM)
    k8s-stop          Stop cluster
    k8s-restart       Restart cluster
    k8s-status        Show cluster status
    k8s-delete        Delete cluster (⚠️  removes all data)

  RKE2 CLUSTER MANAGEMENT (via Lima)
  ────────────────────────────────────────────────────────────────────────────
    rke2-start        Start RKE2 cluster
    rke2-stop         Stop cluster
    rke2-restart      Restart cluster
    rke2-status       Show cluster status
    rke2-kubeconfig   Set KUBECONFIG for current shell to RKE2
    rke2-delete       Delete cluster (⚠️  removes all data)

  KUBECTL SHORTCUTS
  ────────────────────────────────────────────────────────────────────────────
    k                 kubectl
    kgp               kubectl get pods
    kgs               kubectl get services
    kgd               kubectl get deployments
    kgn               kubectl get nodes
    kdp <pod>         kubectl describe pod
    kds <service>     kubectl describe service
    kl <pod>          kubectl logs
    kl -f <pod>       kubectl logs --follow
    kx                kubectx (switch context)
    kn                kubens (switch namespace)

  KUBERNETES TOOLS
  ────────────────────────────────────────────────────────────────────────────
    k9s               Interactive Kubernetes UI
    stern <pattern>   Stream logs from multiple pods
    helm              Kubernetes package manager
    popeye            Cluster health checker
    kube-score        Manifest validator

  CONTAINER TOOLS
  ────────────────────────────────────────────────────────────────────────────
    docker            Docker CLI
    lazydocker        Docker terminal UI
    dive <image>      Inspect container image layers
    colima            Container runtime manager

  ADVANCED WORKFLOWS
  ────────────────────────────────────────────────────────────────────────────
    # Work with namespaces
    k create namespace dev && kn dev

    # Scale applications
    k scale deployment webapp --replicas=3

    # Switch between K3s and RKE2 contexts
    kx colima                      # Use K3s cluster
    kx rke2                        # Use RKE2 cluster

    # Port forwarding for local development
    k port-forward deployment/webapp 8080:80

    # Check cluster health
    popeye                         # Scan for issues

  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  HELP_EOF
  }
''
