# Standalone wrapped packages produced from home-manager aspects.
# Each entry becomes a packages.<name> derivation consumable via `nix run`.
# Uses hm-wrapper-modules to evaluate the HM module, extract packages/files,
# and present config at expected XDG paths via bubblewrap (Linux).
{ inputs, config, ... }: {
  imports = [ inputs.hm-wrapper-modules.flakeModules.default ];

  hmWrappers = {
    home-manager = inputs.home-manager;
    stateVersion = "26.05";
  };

  perSystem = { pkgs, ... }: {
    hmWrappers.programs.pi = {
      mainPackage = pkgs.pi-coding-agent;
      homeModules = [ config.flake.modules.homeManager.pi ];
    };
  };
}
