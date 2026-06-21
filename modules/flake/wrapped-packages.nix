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

    # Single source of truth for bwrap binds and pre-creation.
    # Values are paths relative to $HOME (e.g. ".pi/agent/settings.json",
    # ".config/rpiv-web-tools/config.json").
    binds = wlib.mkBinds base.passthru.hmAdapter;

    # programs.pi-coding-agent.extraPackages (nodejs, bun) are wired into
    # the pi-coding-agent-wrapped makeWrapper PATH by the HM module —
    # the hm-adapter doesn't capture that, and accessing hmConfig.programs.*
    # forces full HM module evaluation (hits unrelated removed-option errors).
    # Declare them explicitly so npm is available when pi installs packages.
    bwrapped = base.wrap ({ config, lib, ... }: {
      imports = [ wlib.modules.bwrapConfig ];
      bwrapConfig.binds.ro = binds;
      env.XDG_CONFIG_HOME = lib.mkIf config.bwrapConfig.enable (lib.mkForce null);
      extraPackages = [ pkgs.nodejs pkgs.bun ];
    });

    # Pre-create every bwrap bind destination so bwrap can mount over them
    # on a foreign machine where HM has never activated.
    precreate = lib.concatMapStringsSep "\n" (dest: ''
      mkdir -p "$HOME/$(dirname "${dest}")"
      touch "$HOME/${dest}" 2>/dev/null || true
    '') (builtins.attrValues binds);
  in {
    packages.pi = pkgs.writeShellScriptBin "pi" ''
      ${precreate}
      exec ${bwrapped}/bin/pi "$@"
    '';
  };
}
