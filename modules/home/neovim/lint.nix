{pkgs, lib, ...}: {
  config = {
    home.packages = with pkgs; [
      nagelfar
      pylint
    ];

    programs.nixvim = {
      plugins = {
        lint = {
          enable = true;
          lintersByFt = {
            tcl = ["nagelfar"];
            python = ["pylint"];
          };
          customLinters.nagelfar = {
            cmd = "${pkgs.nagelfar}/bin/nagelfar";
            stdin = false;
            args = [ "-quiet" ];
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
