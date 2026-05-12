{
  description = "Lima/RKE2/Kubernetes/container tooling for nix-darwin + home-manager (also usable from the CLI via `nix run` / `nix shell`)";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-25.05-darwin";

  outputs = { self, nixpkgs }:
    let
      # Lima runs on macOS only. Keep this flake's CLI surface scoped to darwin.
      systems = [ "aarch64-darwin" "x86_64-darwin" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
      # Lima 1.0.7 is currently flagged "insecure" in nixpkgs. We accept the
      # risk explicitly here so the standalone packages/apps/devShells outputs
      # evaluate cleanly. Module consumers should also set
      # `nixpkgs.config.permittedInsecurePackages = [ "lima-1.0.7" ]` (or
      # rely on the darwin module which sets this for them).
      pkgsFor = system: import nixpkgs {
        inherit system;
        config.permittedInsecurePackages = [ "lima-1.0.7" ];
      };

      scriptsFor = system:
        import ./modules/scripts.nix { pkgs = pkgsFor system; inherit self; };

      # Combine the Nix package list + all wrapped scripts into a single buildEnv
      # so `nix shell github:jsandov/nix-k8s-lima` drops you into a session with
      # kubectl/k9s/lima/colima/... plus rke2-start, k8s-help, etc. on PATH.
      toolset = system:
        let
          pkgs = pkgsFor system;
          scripts = scriptsFor system;
        in
          pkgs.buildEnv {
            name = "k8s-lima-toolset";
            paths =
              (import ./modules/packages.nix { inherit pkgs; })
              ++ (builtins.attrValues scripts);
          };
    in
    {
      # ---------- Modules (nix-darwin + home-manager consumers) ----------
      darwinModules.default      = import ./modules/darwin.nix      { inherit self; };
      homeManagerModules.default = import ./modules/home-manager.nix { inherit self; };

      # ---------- Library exports ----------
      lib.packages = pkgs: import ./modules/packages.nix { inherit pkgs; };
      lib.scripts  = { pkgs }: import ./modules/scripts.nix { inherit pkgs self; };

      # ---------- CLI surface ----------
      # `nix shell github:jsandov/nix-k8s-lima`  → toolset on PATH
      # `nix profile install github:jsandov/nix-k8s-lima` → toolset persistent
      packages = forAllSystems (system: {
        default = toolset system;
        k8s-lima-toolset = toolset system;
      });

      # `nix run github:jsandov/nix-k8s-lima#rke2-start` (etc.)
      # `nix run github:jsandov/nix-k8s-lima`           → k8s-help
      apps = forAllSystems (system:
        let
          scripts = scriptsFor system;
          mkApp = name: { type = "app"; program = "${scripts.${name}}/bin/${name}"; };
        in {
          rke2-start       = mkApp "rke2-start";
          rke2-stop        = mkApp "rke2-stop";
          rke2-status      = mkApp "rke2-status";
          rke2-restart     = mkApp "rke2-restart";
          rke2-delete      = mkApp "rke2-delete";
          rke2-kubeconfig  = mkApp "rke2-kubeconfig";
          k8s-help         = mkApp "k8s-help";
          default          = mkApp "k8s-help";
        }
      );

      # `nix develop github:jsandov/nix-k8s-lima` → dev shell with the toolset
      devShells = forAllSystems (system: {
        default = (pkgsFor system).mkShell {
          packages = [ (toolset system) ];
          shellHook = ''
            echo "k8s-lima toolset ready. Type 'k8s-help' for the quickstart."
          '';
        };
      });
    };
}
