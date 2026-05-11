{ limaYamlPath, kubeconfigPath }:

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

  # ---------- RKE2 via Lima ----------
  rke2-start = ''limactl start --name=rke2 --tty=false ${limaYamlPath} && chmod 600 "${kubeconfigPath}" && export KUBECONFIG="${kubeconfigPath}"'';
  rke2-stop = "limactl stop rke2";
  rke2-restart = "limactl stop rke2 && limactl start rke2";
  rke2-status = "limactl list rke2";
  rke2-delete = "limactl delete rke2";
  rke2-kubeconfig = ''export KUBECONFIG="${kubeconfigPath}" && echo "KUBECONFIG set to RKE2 cluster"'';
}
