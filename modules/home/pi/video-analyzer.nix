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
      type = "stdio";
      command = "npx";
      args = ["-y" "mcp-video-analyzer@latest"];
      description = "Video analysis: transcripts, key frames, OCR, and metadata for video URLs and local files";
      # Keep the orchestrator's declared tool set clean: these tools stay out of
      # the model's prompt and are reached through tool_search. Subagent
      # bundles still get them directly via the `mcp:video_analyzer` selector,
      # which bypasses exposure (docs/agents.md).
      exposure = "deferred";
      # Frame extraction + OCR are CPU-bound and can take minutes on long
      # videos — raise the request timeout (seconds) well above pi's 60s
      # default so the slow path (full-analysis queries) has headroom.
      timeout = 300;
    };
  };
}
