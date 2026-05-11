{ self }:
{ config, lib, pkgs, ... }:

let
  cfg = config.services.k8s-lima;
in
{
  options.services.k8s-lima = {
    enable = lib.mkEnableOption "Lima/RKE2/Kubernetes/container tooling (system layer)";

    enableHomebrew = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Add awscli/helm/eksctl/grafana to homebrew.brews";
    };

    extraPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      description = "Extra Nix packages to install alongside the k8s/container set";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages =
      (import ./packages.nix { inherit pkgs; }) ++ cfg.extraPackages;

    homebrew.brews = lib.mkIf cfg.enableHomebrew (import ./homebrew-brews.nix);
  };
}
