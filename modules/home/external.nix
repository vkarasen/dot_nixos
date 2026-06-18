# External home-manager modules pulled from flake inputs, plus the bits that
# used to live inline in the old flake.nix homeManagerModules list:
# nix-index, catppuccin auto-enable, nixvim, sops, the ast-bro package and the
# flake registry pin.
{inputs, ...}: {
  flake.modules.homeManager.external = {pkgs, ...}: {
    imports = [
      inputs.nix-index-database.homeModules.nix-index
      inputs.catppuccin.homeModules.catppuccin
      inputs.nixvim.homeModules.nixvim
      inputs.sops-nix.homeManagerModules.sops
    ];

    programs.nix-index-database.comma.enable = true;

    home.packages = [
      inputs.ast-bro.packages.${pkgs.stdenv.hostPlatform.system}.default
    ];

    catppuccin = {
      autoEnable = true;
      enable = true;
    };

    nix.registry.nixpkgs.flake = inputs.nixpkgs;
  };
}
