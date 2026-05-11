{ self }:
{ config, lib, pkgs, ... }:

let
  cfg = config.programs.k8s-lima;

  # Render the Lima VM YAML with the consumer's kubeconfigPath substituted in.
  # Lima reads the file from the nix store, so $HOME-style shell vars wouldn't
  # work — kubeconfigPath must be a concrete absolute path at eval time.
  limaYaml = pkgs.writeText "rke2-lima.yaml" (
    builtins.replaceStrings
      [ "@kubeconfigPath@" ]
      [ cfg.kubeconfigPath ]
      (builtins.readFile "${self}/lima/rke2-lima.yaml.tmpl")
  );

  aliases = import ./aliases.nix {
    limaYamlPath = cfg.limaYamlPath;
    inherit (cfg) kubeconfigPath;
  };

  helpSnippet = import ./help.nix;
in
{
  options.programs.k8s-lima = {
    enable = lib.mkEnableOption "k8s-lima shell integration (aliases, completions, k8s-help)";

    kubeconfigPath = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/.kube/rke2.yaml";
      description = ''
        Absolute path on the host where Lima's copyToHost will deposit the
        RKE2 kubeconfig, and where shell aliases will look for it. Must be
        an absolute path (no $HOME or ~) because Lima reads the YAML from
        the nix store and does not expand shell variables.
      '';
    };

    limaYamlPath = lib.mkOption {
      type = lib.types.str;
      default = "${limaYaml}";
      description = ''
        Path to the Lima VM YAML used by `rke2-start`. Defaults to the
        flake-provided template (immutable, in nix store). Override with a
        path to a writable working copy if you want to hot-edit:
          programs.k8s-lima.limaYamlPath = "/path/to/rke2-lima.yaml";
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

    home.shellAliases = aliases;

    programs.zsh.initContent = lib.mkMerge [
      (lib.mkIf cfg.enableCompletions ''
        # Completions for K8s/Lima tooling (fuzzy via fzf-tab if installed)
        source <(eksctl completion zsh)
        source <(kind completion zsh)
        source <(limactl completion zsh)
      '')
      ''
        # Auto-export RKE2_KUBECONFIG if Lima has copied a kubeconfig to the host.
        # Consumers can opt into RKE2 with `export KUBECONFIG=$RKE2_KUBECONFIG`
        # or the `rke2-kubeconfig` alias; this keeps any pre-existing default
        # (e.g. Colima/K3s) as the active context.
        if [ -f "${cfg.kubeconfigPath}" ]; then
          export RKE2_KUBECONFIG="${cfg.kubeconfigPath}"
        fi
      ''
      helpSnippet
    ];
  };
}
