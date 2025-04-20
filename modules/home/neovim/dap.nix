{pkgs, ...}: {
  programs.nixvim = {
    plugins = {
      dap = {
        enable = true;
        luaConfig.post =
          #lua
          ''
            require'dap'.listeners.after.event_initialized["dapui_config"] = function()
            	require'dapui'.open()
            end
          '';
        signs = {
          dapBreakpoint = {
            text = "";
            texthl = "DapBreakpoint";
          };
          dapBreakpointCondition = {
            text = "";
            texthl = "DapBreakpointCondition";
          };
          dapBreakpointRejected = {
            text = "";
            texthl = "DapBreakpointRejected";
          };
          dapLogPoint = {
            text = "";
            texthl = "DapLogPoint";
          };
          dapStopped = {
            text = "";
            texthl = "DapStopped";
          };
        };
      };
      dap-python.enable = true;
      dap-lldb = {
        enable = true;
        settings = {
          codelldb_path = "${pkgs.vscode-extensions.vadimcn.vscode-lldb.adapter}/bin/codelldb";
        };
      };
      dap-virtual-text = {
        enable = true;
      };
      dap-ui = {
        enable = true;
      };
    };
    keymaps = [
      {
        mode = "n";
        key = "<leader>db";
        action.__raw =
          #lua
          ''
            function()
            	require'dap'.toggle_breakpoint()
            end
          '';
        options.desc = "Add breakpoint at line";
      }
      {
        mode = "n";
        key = "<leader>dc";
        action.__raw =
          #lua
          ''
            function()
            	require'dap'.continue()
            end
          '';
        options.desc = "Start or continue the debugger";
      }
      {
        mode = "n";
        key = "<leader>do";
        action.__raw =
          #lua
          ''
            function()
            	require'dap'.step_over()
            end
          '';
        options.desc = "debug: Step over";
      }
      {
        mode = "n";
        key = "<leader>di";
        action.__raw =
          #lua
          ''
            function()
            	require'dap'.step_into()
            end
          '';
        options.desc = "debug: Step into";
      }
      {
        mode = "n";
        key = "<leader>dO";
        action.__raw =
          #lua
          ''
            function()
            	require'dap'.step_out()
            end
          '';
        options.desc = "debug: Step out";
      }
      {
        mode = "n";
        key = "<leader>dq";
        action.__raw =
          #lua
          ''
            function()
            	require'dap'.terminate()
            end
          '';
        options.desc = "Terminate the debugger";
      }
    ];
  };
}
