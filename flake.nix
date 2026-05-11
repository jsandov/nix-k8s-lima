{
  description = "Lima/RKE2/Kubernetes/container tooling for nix-darwin + home-manager";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-25.05-darwin";

  outputs = { self, nixpkgs }: {
    darwinModules.default      = import ./modules/darwin.nix      { inherit self; };
    homeManagerModules.default = import ./modules/home-manager.nix { inherit self; };

    lib.packages = pkgs: import ./modules/packages.nix { inherit pkgs; };
  };
}
