# Zero-overhead zsh aliases. Anything more complex (rke2-start, etc.) lives
# as a real script in scripts.nix and is installed via home.packages.
#
# Two aliases here intentionally mask scripts of the same name:
#   - rke2-start: wraps the script with a `&& export KUBECONFIG=...` chain
#     so the env var lands in the caller's shell (a script can't do this).
#   - rke2-kubeconfig: directly exports KUBECONFIG (vs. the CLI script which
#     prints the export line for `eval $(...)` use).

{ kubeconfigPath }:

{
  # ---------- kubectl shortcuts ----------
  k = "kubectl";
  kgp = "kubectl get pods";
  kgs = "kubectl get services";
  kgd = "kubectl get deployments";
  kgn = "kubectl get nodes";
  kdp = "kubectl describe pod";
  kds = "kubectl describe service";
  kl = "kubectl logs";
  kx = "kubectx";
  kn = "kubens";

  # ---------- K3s via Colima ----------
  k8s-start = "colima start --kubernetes --cpu 4 --memory 8";
  k8s-stop = "colima stop";
  k8s-restart = "colima restart";
  k8s-status = "colima status";
  k8s-delete = "colima delete";

  # ---------- RKE2 wrappers around scripts ----------
  # First `rke2-start` expands the alias; the inner `rke2-start` resolves to
  # the script on PATH (zsh doesn't recursively re-expand the same alias).
  rke2-start = ''rke2-start && export KUBECONFIG="${kubeconfigPath}"'';

  # In-shell export — the CLI script equivalent prints the export for eval.
  rke2-kubeconfig = ''export KUBECONFIG="${kubeconfigPath}" && echo "KUBECONFIG set to RKE2 cluster"'';
}
