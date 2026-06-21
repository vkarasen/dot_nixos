# Standalone wrapped packages produced from home-manager aspects.
# Uses the hm-wrapper-modules direct API so we can compose a pre-creation
# shell wrapper around the bwrap invocation: on a foreign machine (no HM
# activation) bwrap bind destinations don't exist yet, so we touch them
# first. bwrap is kept (not replaced with XDG_CONFIG_HOME redirect) so
# that $HOME/.config remains writable for pi's npm package state.
{ inputs, config, ... }: {
  perSystem = { pkgs, lib, ... }: let
    wlib = inputs.hm-wrapper-modules.lib;

    base = wlib.wrapHomeModule {
      inherit pkgs;
      mainPackage = pkgs.pi-coding-agent;
      homeModules = [ config.flake.modules.homeManager.pi ];
      home-manager = inputs.home-manager;
    };

    bwrapped = base.wrap ({ config, lib, ... }: {
      imports = [ wlib.modules.bwrapConfig ];
      bwrapConfig.binds.ro = wlib.mkBinds base.passthru.hmAdapter;
      env.XDG_CONFIG_HOME = lib.mkIf config.bwrapConfig.enable (lib.mkForce null);
    });

    # Produce mkdir+touch lines for every xdg config file the adapter
    # extracted — ensures bwrap has a real destination to mount over.
    precreate = lib.concatMapStringsSep "\n" (name: ''
      mkdir -p "$HOME/.config/$(dirname "${name}")"
      touch "$HOME/.config/${name}" 2>/dev/null || true
    '') (builtins.attrNames base.passthru.hmAdapter.xdgConfigFiles);
  in {
    packages.pi = pkgs.writeShellScriptBin "pi" ''
      ${precreate}
      exec ${bwrapped}/bin/pi "$@"
    '';
  };
}
