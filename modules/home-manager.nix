{ self }:
{ config, lib, pkgs, ... }:

let
  cfg = config.programs.k8s-lima;

  scripts = import ./scripts.nix {
    inherit pkgs self;
    kubeconfigPathDefault = cfg.kubeconfigPath;
  };

  aliases = import ./aliases.nix { inherit (cfg) kubeconfigPath; };
in
{
  options.programs.k8s-lima = {
    enable = lib.mkEnableOption "k8s-lima shell integration (scripts on PATH, aliases, completions)";

    kubeconfigPath = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/.kube/rke2.yaml";
      description = ''
        Absolute path on the host where Lima's copyToHost will deposit the
        RKE2 kubeconfig, and where shell aliases and scripts will look for it.
        Must be an absolute path (no $HOME or ~) — the rke2-start script reads
        the Lima yaml template and substitutes this value into the copyToHost
        field at runtime via sed.

        CLI users (without home-manager) override this per-invocation by setting
        the RKE2_KUBECONFIG_PATH environment variable.
      '';
    };

    enableCompletions = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Source eksctl/kind/limactl zsh completions";
    };
  };

  config = lib.mkIf cfg.enable {
    programs.zsh.enable = true;

    # Install all wrapped scripts (rke2-start, rke2-stop, k8s-help, etc.) onto
    # the user's PATH. These are the same derivations exposed via the flake's
    # apps/packages outputs — single source of truth across in-shell and CLI use.
    home.packages = builtins.attrValues scripts;

    # The kubectl shortcuts and Colima k8s-* aliases stay as zero-overhead
    # aliases. rke2-start gets a thin alias wrapper that chains a KUBECONFIG
    # export onto the script (since a script can't export to its parent shell).
    home.shellAliases = aliases;

    programs.zsh.initContent = lib.mkIf cfg.enableCompletions ''
      # Completions for K8s/Lima tooling (fuzzy via fzf-tab if installed)
      source <(eksctl completion zsh)
      source <(kind completion zsh)
      source <(limactl completion zsh)

      # Auto-export RKE2_KUBECONFIG if Lima has copied a kubeconfig to the host.
      # K3s/Colima remains the default kubectl target; opt into RKE2 with
      # `export KUBECONFIG=$RKE2_KUBECONFIG` or the rke2-kubeconfig alias.
      if [ -f "${cfg.kubeconfigPath}" ]; then
        export RKE2_KUBECONFIG="${cfg.kubeconfigPath}"
      fi
    '';
  };
}
