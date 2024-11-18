{
  pkgs,
  lib,
  ...
}: let
  nagelfar_wrapped = pkgs.writeShellApplication {
    name = "nagelfar_wrapped";
    runtimeInputs = with pkgs; [
      nagelfar
      tcl
    ];
    text =
      #bash
      ''
        args=()

        if [[ -v NAGELFAR_SYNTAX_PATH ]] ; then
        	mapfile <<<"$NAGELFAR_SYNTAX_PATH" -td :
        	for syntaxdb in "''${MAPFILE[@]%$'\n'}" ; do
        		args+=("-s" "$syntaxdb")
        	done
        fi

        args+=("$@")

        nagelfar "''${args[@]}"
      '';
  };
in {
  config = {
    home.packages = with pkgs;
      [
        pylint
      ]
      ++ [nagelfar_wrapped];

    programs.nixvim = {
      plugins = {
        lint = {
          enable = true;
          lintersByFt = {
            tcl = ["nagelfar"];
            python = ["pylint"];
          };
          customLinters.nagelfar = {
            cmd = "${nagelfar_wrapped}/bin/nagelfar_wrapped";
            stdin = false;
            args = ["-quiet"];
            ignore_exitcode = true;
            parser =
              #lua
              ''
                require("lint.parser").from_pattern(
                    "^Line%s+(%d+): ([WNE]) (.*)$",
                    {
                        'lnum',
                        'severity',
                        'message'
                    },
                    {
                        ['W'] = vim.diagnostic.severity.WARN,
                        ['N'] = vim.diagnostic.severity.INFO,
                        ['E'] = vim.diagnostic.severity.ERROR,
                    },
                    {['source'] = 'nagelfar'},
                    {}
                )
              '';
          };
        };
      };
    };
  };
}
