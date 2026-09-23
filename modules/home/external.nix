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
      # The DE surface is themed by Stylix; disable catppuccin's copy so the
      # two don't fight over the same config files. (Nothing to disable for
      # GTK: catppuccin/nix >= 25.05 dropped GTK theming from its home-manager
      # module, so it no longer sets a Papirus icon theme here.)
      # Everything else (terminals, CLI/TUI tools) stays catppuccin's.
      hyprland.enable = false;
      waybar.enable = false;
      mako.enable = false;
      fuzzel.enable = false;
      hyprlock.enable = false;
      # Firefox is themed by Stylix's firefox-gnome-theme target (userChrome.css),
      # not catppuccin's Firefox Color extension (whose settings home-manager
      # writes to a legacy storage.js that modern Firefox ignores).
      firefox.enable = false;
    };

    nix.registry.nixpkgs.flake = inputs.nixpkgs;
  };
}
