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

    my.pi.mcpServers."video-analyzer" = {
      type = "stdio";
      command = "npx";
      args = ["-y" "mcp-video-analyzer@latest"];
      # Frame extraction + OCR are CPU-bound and can take minutes on long
      # videos — raise the request timeout well above the SDK's ~60s default
      # so the slow path (full-analysis queries) has headroom.
      requestTimeoutMs = 300000;
    };
  };
}
