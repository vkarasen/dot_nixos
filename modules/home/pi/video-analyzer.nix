# Dendritic aspect: video-analyzer (home-manager class).
#
# Wires the mcp-video-analyzer MCP server (guimatheus92/mcp-video-analyzer)
# into pi, giving the agent access to transcripts, key frames, OCR text, and
# metadata for YouTube/Vimeo/TikTok/Instagram/X/Twitch/Dailymotion/Facebook
# URLs, direct video URLs, and local files.
#
# Requirements:
#   - Node.js >= 22.12 — satisfied by pkgs.nodejs (24.x) already in the pi
#     aspect's extraPackages.
#   - yt-dlp on PATH — required for platform URLs; added below.
#   - ffmpeg is bundled (ffmpeg-static) — no system ffmpeg needed.
#   - Chrome/Chromium is an optional frame-extraction fallback; not wired here.
{...}: {
  flake.modules.homeManager.video-analyzer = {pkgs, ...}: {
    programs.pi-coding-agent.extraPackages = [
      pkgs.yt-dlp
    ];

    my.pi.mcpServers."video_analyzer" = {
      url = "http://127.0.0.1:8799/servers/video-analyzer/mcp";
      description = "Video analysis: transcripts, key frames, OCR, and metadata for video URLs and local files";
      # `deferred` keeps the tool set out of the model context until
      # `tool_search` pulls it in — `direct` would declare every tool on every
      # turn. Subagent child sessions register the tools regardless of
      # exposure, because the mcp-proxy singleton strips `resources` from the
      # initialize reply (pi issue
      # https://github.com/earendil-works/pi/issues/10526) — the earlier
      # `direct` was a misdiagnosis of that bug, not a requirement of
      # exposure. The orchestrator's declared tool set still stays clean —
      # the recon-nudge extension hard-blocks `mcp__*` and `tool_search`.
      exposure = "deferred";
      # Frame extraction + OCR are CPU-bound and can take minutes on long
      # videos — raise the request timeout (seconds) well above pi's 60s
      # default so the slow path (full-analysis queries) has headroom.
      timeout = 300;
    };

    # Stdio definition consumed by the shared mcp-proxy singleton
    # (modules/home/pi/mcp-proxy.nix); the proxy spawns it once and serves it
    # at /servers/video-analyzer/mcp.
    my.pi.mcpProxyServers."video-analyzer" = {
      command = "npx";
      args = ["-y" "mcp-video-analyzer@0.10.0"];
      env = {};
    };
  };
}
