---
name: video-analyzer
description: Understand a video (YouTube, Vimeo, TikTok, Instagram, X, Loom, other yt-dlp platforms, direct video URLs, or local files) — transcript, key frames, OCR, metadata — and answer questions about it with timestamps. Use whenever the user shares a video URL or path and wants it summarized or queried, including what is shown on screen.
---

Analyze the given video and answer the user's question (or summarize it if none
was given). Cite timestamps (`M:SS`) in every answer.

## Calling tools

The `video_analyzer` server's tools are exposed to you **directly**, each named
`mcp__video_analyzer__<tool>` (`mcp__video_analyzer__get_transcript`,
`mcp__video_analyzer__get_frame_at`, …). Call them like any other tool, passing
the tool's own arguments — there is no `{tool, args}` wrapper:

```js
mcp__video_analyzer__get_transcript({ url: "<url>" })
```

The main/orchestrator session does **not** have these tools: the server is
declared with `deferred` exposure and the recon gate withholds `tool_search` /
`codemode`, so video work reaches this server only through a subagent whose
frontmatter selects it (`mcp:video_analyzer` — the `media` agent).

Pick the cheapest path that answers the question. Three cover almost everything:

## 1. Text-only questions — summarize, "what's discussed", Q&A from speech

Use the transcript path — no video download, no frame extraction, answers in
seconds:

- `get_transcript` for the full spoken content.
- `analyze_video` with `options.detail: "brief"` when you also want title /
  duration / uploader (returns metadata + truncated transcript, no frames).

## 2. A concrete moment — "what happens at 1:30", "what's on screen at 0:45"

Use a targeted frame tool — it downloads the video but extracts only the
frame(s) you asked for, which is far cheaper than a full pass:

- `get_frame_at` for a single timestamp (one frame):

```js
mcp__video_analyzer__get_frame_at({ url: "<url>", timestamp: "1:30" })
```

- `analyze_moment` for a short range — takes `from`/`to` timestamps
  (e.g. `"1:30"`, `"2:00"`) plus burst frames + transcript segment + OCR.

The frames come back as images — answer visual questions ("what colour t-shirt
is the presenter wearing?") by looking at them.

## 3. Complex / multi-frame questions — "does the demo match the narration", "what changes across the whole video"

Use `analyze_video` (default `standard`, or `options.detail: "detailed"` for
dense sampling). This is the expensive path: full 1080p download + up to 60 key
frames + OCR per frame. Expect it to take minutes — slowness is normal, not
failure. The server's request timeout is already raised to accommodate this; if
a call still times out, narrow the question to a moment (path 2) or tell the
user to raise `requestTimeoutMs`.

## Anything else — discover, don't assume

For anything beyond the three paths above (batch jobs, metadata-only checks,
raising frame width for dense-UI screen recordings, motion/burst frames), read
the tool descriptions rather than guessing:

1. List your `mcp__video_analyzer__*` tools and read their descriptions to find
   the right one.
2. Read the parameters before calling — the parameter descriptions are where
   the per-call options live.

## Gotchas

- **Large results get truncated.** Long transcripts and full analyses exceed
  pi's inline output limit: the tool result shows a truncated preview and
  saves the complete JSON to a temp file (path reported in the result). Read
  that file — `read` with offset/limit, or `grep`/`tail` — to get the full
  content.
- Every result carries a `warnings` array explaining partial results (no
  captions, missing yt-dlp, age-restricted). Relay those to the user; don't
  treat them as tool errors.
- An empty transcript with a "silent"/"no transcript" warning is usually
  content, not failure — frames still work without captions.

## No MCP server connected

Fall back to the one-shot CLI (its `--help` documents the flags):

```bash
npx -y mcp-video-analyzer@latest analyze "<url-or-path>"
```
