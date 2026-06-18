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

  # AI-gateway scripts drive kind + helm + kubectl (not Lima/RKE2), so they get
  # their own runtimeInputs. Manifests are vendored in-repo and referenced via ${self}.
  gwManifests = "${self}/manifests/ai-gateway";

  mkGwScript = name: text: pkgs.writeShellApplication {
    inherit name text;
    runtimeInputs = with pkgs; [ kind kubectl kubernetes-helm coreutils ];
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

    LOCAL AI GATEWAY (kind + Envoy AI Gateway → Anthropic, for Claude Code)
    ────────────────────────────────────────────────────────────────────────────
      export ANTHROPIC_GATEWAY_API_KEY=sk-ant-...   # real key (cluster Secret only)
      ai-gw-up          Create kind cluster, install gateways, route, port-forward
      ai-gw-claude-env  Print ANTHROPIC_BASE_URL/_API_KEY (eval "$(ai-gw-claude-env)")
      ai-gw-status      Show cluster / gateway / route / pod status
      ai-gw-logs        Tail controller + Envoy data-plane logs
      ai-gw-down        Delete the kind cluster
      (override the local port with AI_GW_PORT; see manifests/ai-gateway/README.md)

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

  # ───────────────────────── AI gateway (kind + Envoy AI Gateway) ─────────────────────────
  # Local Claude Code → Envoy AI Gateway → Anthropic. See manifests/ai-gateway/README.md
  # and docs/ai-gateway-prd-research.md. Pinned: Envoy Gateway v1.8.1, Envoy AI Gateway v0.7.0.

  ai-gw-up = mkGwScript "ai-gw-up" ''
    CLUSTER="ai-gw"
    PORT="''${AI_GW_PORT:-8888}"
    EG_VERSION="v1.8.1"
    AIGW_VERSION="v0.7.0"
    KIND_CONFIG="${gwManifests}/kind-cluster.yaml"
    ROUTE_MANIFEST="${gwManifests}/anthropic.yaml"

    # The real sk-ant-... key goes ONLY into an in-cluster Secret (the gateway injects
    # it upstream). Your shell's ANTHROPIC_API_KEY stays a placeholder.
    if [ -z "''${ANTHROPIC_GATEWAY_API_KEY:-}" ]; then
      echo "ERROR: export ANTHROPIC_GATEWAY_API_KEY=sk-ant-... (your real key) first." >&2
      exit 1
    fi

    if kind get clusters | grep -qx "$CLUSTER"; then
      echo "✓ kind cluster '$CLUSTER' already exists"
    else
      echo "Creating kind cluster '$CLUSTER' (pinned k8s node image)..."
      kind create cluster --config "$KIND_CONFIG"
    fi
    KCTX="kind-$CLUSTER"

    echo "Installing Envoy Gateway $EG_VERSION..."
    helm upgrade --install eg oci://docker.io/envoyproxy/gateway-helm \
      --version "$EG_VERSION" --kube-context "$KCTX" \
      -n envoy-gateway-system --create-namespace
    kubectl --context "$KCTX" -n envoy-gateway-system \
      wait --timeout=5m deployment/envoy-gateway --for=condition=Available

    echo "Installing Envoy AI Gateway $AIGW_VERSION..."
    helm upgrade --install aieg-crd oci://docker.io/envoyproxy/ai-gateway-crds-helm \
      --version "$AIGW_VERSION" --kube-context "$KCTX" \
      -n envoy-ai-gateway-system --create-namespace
    helm upgrade --install aieg oci://docker.io/envoyproxy/ai-gateway-helm \
      --version "$AIGW_VERSION" --kube-context "$KCTX" \
      -n envoy-ai-gateway-system
    kubectl --context "$KCTX" -n envoy-ai-gateway-system \
      wait --timeout=3m deployment/ai-gateway-controller --for=condition=Available

    echo "Creating/updating the Anthropic API-key Secret..."
    kubectl --context "$KCTX" -n default create secret generic ai-gw-anthropic-apikey \
      --from-literal=apiKey="$ANTHROPIC_GATEWAY_API_KEY" \
      --dry-run=client -o yaml | kubectl --context "$KCTX" apply -f -

    echo "Applying Anthropic routing..."
    kubectl --context "$KCTX" apply -f "$ROUTE_MANIFEST"

    echo "Waiting for the gateway data-plane..."
    kubectl --context "$KCTX" -n envoy-gateway-system \
      wait --timeout=3m --for=condition=Ready pods \
      -l gateway.envoyproxy.io/owning-gateway-name=ai-gw || true

    ENVOY_SVC="$(kubectl --context "$KCTX" -n envoy-gateway-system get svc \
      --selector=gateway.envoyproxy.io/owning-gateway-namespace=default,gateway.envoyproxy.io/owning-gateway-name=ai-gw \
      -o jsonpath='{.items[0].metadata.name}')"
    if [ -z "$ENVOY_SVC" ]; then
      echo "ERROR: Envoy data-plane service not found yet. Re-run ai-gw-up in a moment." >&2
      exit 1
    fi

    echo ""
    echo "✓ AI gateway up on kind cluster '$CLUSTER'. Next, in another shell:"
    # shellcheck disable=SC2016
    echo '    eval "$(ai-gw-claude-env)"'
    echo "    claude -p 'reply with OK'"
    echo ""
    echo "Port-forwarding localhost:$PORT -> svc/$ENVOY_SVC:80 (Ctrl-C to stop; cluster stays up)."
    exec kubectl --context "$KCTX" -n envoy-gateway-system port-forward "svc/$ENVOY_SVC" "$PORT:80"
  '';

  ai-gw-down = mkGwScript "ai-gw-down" ''
    kind delete cluster --name ai-gw
  '';

  ai-gw-status = mkGwScript "ai-gw-status" ''
    KCTX="kind-ai-gw"
    echo "=== kind clusters ==="
    kind get clusters || true
    echo "=== gateways / AI routes / backends ==="
    kubectl --context "$KCTX" get gateways,aigatewayroutes,aiservicebackends,backendsecuritypolicies -A || true
    echo "=== pods (envoy-gateway-system) ==="
    kubectl --context "$KCTX" -n envoy-gateway-system get pods || true
    echo "=== pods (envoy-ai-gateway-system) ==="
    kubectl --context "$KCTX" -n envoy-ai-gateway-system get pods || true
  '';

  ai-gw-logs = mkGwScript "ai-gw-logs" ''
    KCTX="kind-ai-gw"
    echo "=== ai-gateway-controller (last 100 lines) ==="
    kubectl --context "$KCTX" -n envoy-ai-gateway-system logs deployment/ai-gateway-controller --tail=100 || true
    echo "=== Envoy data-plane (last 100 lines) ==="
    POD="$(kubectl --context "$KCTX" -n envoy-gateway-system get pods \
      -l gateway.envoyproxy.io/owning-gateway-name=ai-gw \
      -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
    if [ -n "$POD" ]; then
      kubectl --context "$KCTX" -n envoy-gateway-system logs "$POD" --tail=100 || true
    else
      echo "(no data-plane pod found yet — run ai-gw-up)"
    fi
  '';

  ai-gw-claude-env = mkGwScript "ai-gw-claude-env" ''
    PORT="''${AI_GW_PORT:-8888}"
    # eval "$(ai-gw-claude-env)" to load these into your shell.
    # The /anthropic path prefix is REQUIRED — Claude Code appends /v1/messages.
    echo "export ANTHROPIC_BASE_URL=http://localhost:$PORT/anthropic"
    echo "export ANTHROPIC_API_KEY=placeholder-local-key"
  '';
}
