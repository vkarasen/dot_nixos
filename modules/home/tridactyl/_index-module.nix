# Library module: the `programs.tridactyl-index` option set and its
# implementation — builds the generated Tridactyl index, materializes it at
# xdg.configFile."tridactyl/index.json", and wires the television `tridactyl`
# channel that consumes it. Imported by default.nix (the tridactyl aspect);
# exposed for cross-flake import as flake.homeModules.tridactyl-index-module.
# The source tree is supplied by the consumer (e.g. a github:tridactyl/tridactyl
# flake input). Keep this generic: no repo-specific settings here.
{
  pkgs,
  lib,
  config,
  ...
}: let
  cfg = config.programs.tridactyl-index;

  # Self-contained channel helper scripts: jq + coreutils are baked onto the
  # script's PATH by writeShellApplication, so a consumer needs no jq of their
  # own for the channel commands.
  tridactyl-source = pkgs.writeShellApplication {
    name = "tridactyl-source";
    runtimeInputs = [pkgs.jq pkgs.coreutils];
    text = ''
      test -f ~/.config/tridactyl/index.json && jq -r 'keys[]' ~/.config/tridactyl/index.json || true
    '';
  };

  tridactyl-preview = pkgs.writeShellApplication {
    name = "tridactyl-preview";
    runtimeInputs = [pkgs.jq pkgs.coreutils];
    text = ''
      jq -r --arg k "$1" '.[$k] as $o | $o.description, "", (if $o.kind == "excmd" then ("Params: " + ([($o.params // [])[] | .name] | join(", "))) + "   Mode: " + ($o.mode // "") else ("Type: " + (if ($o.type // "") == "" then "n/a" else $o.type end)) + "   Default: " + $o.default end), ("Source: " + $o.source)' ~/.config/tridactyl/index.json | fold -s -w 80
    '';
  };

  # Generated Tridactyl index: :set settings (from src/lib/config.ts,
  # namespaced `set.*`) plus ex commands (from src/excmds.ts, namespaced
  # `excmd.*`), built from the configured source tree by
  # _parse-config.cjs + _parse-excmds.cjs, merged into one index.json.
  tridactylIndex =
    pkgs.runCommand "tridactyl-index" {
      buildInputs = [pkgs.nodejs pkgs.jq];
      NODE_PATH = "${pkgs.typescript_5}/lib/node_modules";
    } ''
      mkdir -p $out
      node ${./_parse-config.cjs} ${cfg.source}/src/lib/config.ts > settings.json
      node ${./_parse-excmds.cjs} ${cfg.source}/src/excmds.ts > excmds.json
      jq -s 'add' settings.json excmds.json > $out/index.json
    '';
in {
  options.programs.tridactyl-index = {
    enable = lib.mkEnableOption "the generated Tridactyl settings/ex-command index (and its television channel)";

    source = lib.mkOption {
      type = lib.types.path;
      description = "Tridactyl source tree (e.g. a github:tridactyl/tridactyl flake input)";
    };
  };

  config = lib.mkIf cfg.enable {
    # The generated Tridactyl index (`set.*` settings + `excmd.*` commands),
    # built from the configured source tree at build time (tridactylIndex above)
    # and materialized at ~/.config/tridactyl/index.json.
    xdg.configFile."tridactyl/index.json" = {
      source = "${tridactylIndex}/index.json";
    };

    # Tridactyl index: `set.*` settings + `excmd.*` ex commands, from the index
    # generated above. The source command tolerates the index's absence
    # (`|| true`) because television is always-on while the index is only
    # materialized when programs.tridactyl-index.enable is set.
    programs.television.channels.tridactyl = {
      metadata = {
        name = "tridactyl";
        description = "Tridactyl settings + ex commands (generated index)";
      };
      source.command = lib.mkDefault "${tridactyl-source}/bin/tridactyl-source";
      preview.command = lib.mkDefault "${tridactyl-preview}/bin/tridactyl-preview '{}'";
    };
  };
}
