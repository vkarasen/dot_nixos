# Dendritic aspect: pi-mcp-proxy (home-manager class).
#
# Shared MCP proxy singleton: spawns the stdio MCP servers contributed via
# my.pi.mcpProxyServers exactly once (by a systemd user service running
# mcp-proxy) and exposes them over streamable HTTP. pi sessions then connect
# to the proxied servers over HTTP instead of each spawning their own stdio
# copy — one npx child per server regardless of how many pi sessions run.
#
# The proxy config file is a Claude-Desktop-shaped JSON document with a
# top-level "mcpServers" object. It is read only via the
# --named-server-config flag, and each named server is served at
#   http://127.0.0.1:8799/servers/<name>/mcp
# (streamable HTTP — pi rejects SSE). Health is at /status.
#
# The URL entries themselves live in my.pi.mcpServers and are written by the
# pi-mcp aspect into ~/.pi/agent/mcp.json; this aspect owns the stdio side.
{...}: {
  flake.modules.homeManager.pi-mcp-proxy = {
    config,
    lib,
    pkgs,
    ...
  }: let
    isPrivate = config.my.is_private;
    # mcp-proxy 0.12.0 is patched twice:
    #
    # 1. mcp-proxy-forward-cursor.patch — a real upstream bug fix. Upstream
    #    0.12.0 drops the request cursor in its list handlers, so a client that
    #    paginates loops forever on page 1. Forward the cursor (upstream PR
    #    #239) until the fix lands in nixpkgs. Keep this one.
    #
    # 2. mcp-proxy-strip-resources.patch — TEMPORARY workaround. It deletes
    #    `resources` from the capabilities advertised in the `initialize` reply
    #    on the HTTP/SSE serving path (mcp_server.py), because pi misbehaves
    #    against a proxied server that advertises resources:
    #      https://github.com/earendil-works/pi/issues/10526
    #    RIP OUT once pi fixes #10526: delete the patch file and drop its entry
    #    from the patches list below. Nothing else depends on it.
    mcpProxy = pkgs.mcp-proxy.overrideAttrs (old: {
      patches =
        (old.patches or [])
        ++ [
          ./mcp-proxy-forward-cursor.patch
          ./mcp-proxy-strip-resources.patch
        ];
    });
  in {
    home.file.".config/pi-mcp/mcp-servers.json".text = builtins.toJSON {
      mcpServers = config.my.pi.mcpProxyServers;
    };

    systemd.user.services.pi-mcp-proxy = {
      Unit = {
        Description = "Shared MCP proxy (google-workspace + video-analyzer) over streamable HTTP";
        After = ["sops-nix.service" "network-online.target"];
        Wants = ["network-online.target"];
        # Bound the Restart=on-failure loop so a permanently-broken server
        # (e.g. missing credentials) does not restart forever.
        StartLimitIntervalSec = 300;
        StartLimitBurst = 3;
      };
      Service = {
        Type = "exec";
        WorkingDirectory = "%h";
        # npx resolves its command via PATH, and HM's sessionPath does not reach
        # systemd user units — put nodejs (+ yt-dlp for video-analyzer, +
        # coreutils for the readiness probe) on PATH.
        Environment = ["PATH=${pkgs.nodejs}/bin:${pkgs.yt-dlp}/bin:${pkgs.coreutils}/bin:${pkgs.bash}/bin"];
        # Personal-only: wait for the google-workspace OAuth client credentials
        # to be present before starting, mirroring the readiness probe idea.
        ExecStartPre = lib.mkIf isPrivate "${pkgs.bash}/bin/bash -c 'for i in $(seq 1 60); do [ -f \"$HOME/.config/google-workspace-mcp/credentials.json\" ] && exit 0; sleep 1; done; exit 1'";
        ExecStart = "${mcpProxy}/bin/mcp-proxy --named-server-config %h/.config/pi-mcp/mcp-servers.json --host 127.0.0.1 --port 8799";
        Restart = "on-failure";
        RestartSec = 5;
        TimeoutStopSec = 15;
      };
      Install.WantedBy = ["default.target"];
    };
  };
}
