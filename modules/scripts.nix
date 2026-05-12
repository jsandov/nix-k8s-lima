# Shared script derivations used by both:
#   - the home-manager module (installed into home.packages)
#   - the flake's apps + packages outputs (for `nix run` / `nix shell` / `nix profile install`)
#
# Single source of truth so the CLI surface and the in-shell aliases never drift.

{ pkgs, self, kubeconfigPathDefault ? "$HOME/.kube/rke2.yaml" }:

let
  limaTemplate = "${self}/lima/rke2-lima.yaml.tmpl";

  mkScript = name: text: pkgs.writeShellApplication {
    inherit name text;
    runtimeInputs = with pkgs; [ lima colima coreutils gnused ];
  };
in
{
  rke2-start = mkScript "rke2-start" ''
    # Renders the Lima yaml template with $RKE2_KUBECONFIG_PATH (or a baked default)
    # substituted in for @kubeconfigPath@, then boots the VM and tightens the kubeconfig.
    # Override the template via $RKE2_LIMA_YAML_TMPL if you want a writable working copy.
    KUBECONFIG_PATH="''${RKE2_KUBECONFIG_PATH:-${kubeconfigPathDefault}}"
    LIMA_TMPL="''${RKE2_LIMA_YAML_TMPL:-${limaTemplate}}"

    RENDERED=$(mktemp -t rke2-lima.XXXXXX.yaml)
    trap 'rm -f "$RENDERED"' EXIT
    sed "s|@kubeconfigPath@|$KUBECONFIG_PATH|g" "$LIMA_TMPL" > "$RENDERED"

    mkdir -p "$(dirname "$KUBECONFIG_PATH")"
    echo "Booting RKE2 cluster (first boot ~5-10 min)..."
    limactl start --name=rke2 --tty=false "$RENDERED"
    chmod 600 "$KUBECONFIG_PATH"

    echo
    echo "✓ Cluster ready. To use kubectl:"
    echo "    export KUBECONFIG=$KUBECONFIG_PATH"
    echo "    kubectl get nodes"
  '';

  rke2-stop = mkScript "rke2-stop" ''
    limactl stop rke2
  '';

  rke2-status = mkScript "rke2-status" ''
    limactl list rke2
  '';

  rke2-restart = mkScript "rke2-restart" ''
    limactl stop rke2
    limactl start rke2
  '';

  rke2-delete = mkScript "rke2-delete" ''
    limactl delete -f rke2
  '';

  rke2-kubeconfig = mkScript "rke2-kubeconfig" ''
    # Prints `export KUBECONFIG=...` to stdout. Use `eval "$(rke2-kubeconfig)"`
    # to apply it in the current shell. The home-manager alias version sets
    # the env var directly because aliases expand in the caller's shell.
    KUBECONFIG_PATH="''${RKE2_KUBECONFIG_PATH:-${kubeconfigPathDefault}}"
    if [ ! -f "$KUBECONFIG_PATH" ]; then
      echo "Kubeconfig not found at $KUBECONFIG_PATH" >&2
      echo "Run 'rke2-start' first." >&2
      exit 1
    fi
    echo "export KUBECONFIG=$KUBECONFIG_PATH"
  '';

  k8s-help = mkScript "k8s-help" ''
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
        rke2-kubeconfig              # Connect to cluster (or eval "$(rke2-kubeconfig)")
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

    KUBECTL SHORTCUTS (home-manager only — aliases, not scripts)
    ────────────────────────────────────────────────────────────────────────────
      k                 kubectl
      kgp               kubectl get pods
      kgs               kubectl get services
      kgd               kubectl get deployments
      kgn               kubectl get nodes
      kdp <pod>         kubectl describe pod
      kds <service>     kubectl describe service
      kl <pod>          kubectl logs
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

    ENVIRONMENT VARIABLES (CLI mode)
    ────────────────────────────────────────────────────────────────────────────
      RKE2_KUBECONFIG_PATH       Override the kubeconfig path (default: ~/.kube/rke2.yaml)
      RKE2_LIMA_YAML_TMPL        Override the Lima yaml template (for hot-editing)

    ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    HELP_EOF
  '';
}
