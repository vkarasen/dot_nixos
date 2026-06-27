---
name: oss-contrib
description: How to contribute to third-party open source repos — issues, PRs, and feature proposals — honoring each project's contribution standards. Use when asked to file an issue, draft a PR, or propose a feature upstream.
---

# OSS Contribution Workflow

## Environment

`gh` is installed system-wide via Nix/home-manager. Always verify auth before anything else:

```bash
gh auth status
```

If authenticated, prefer `gh` over web UI for reading. For *posting*, always check the project's requirements first — some projects enforce templates that only work correctly through the web form.

## Step 1 — Read CONTRIBUTING.md

Before drafting anything, fetch the project's contribution guidelines:

```bash
gh api repos/<owner>/<repo>/contents/CONTRIBUTING.md | jq -r '.content' | base64 -d
```

Or via web_fetch if the repo is public. Look for:

- **Quality bar** — length limits, tone requirements, what gets auto-closed
- **AI/LLM policy** — many projects require "write in your own voice" and prohibit unlabeled AI-generated text
- **Contribution gate** — auto-close for new contributors, required approval steps (e.g. `lgtmi` / `lgtm`)
- **Weekend policy** — some projects deprioritize weekend submissions
- **PR eligibility** — some projects require issue approval before accepting PRs

## Step 2 — Check Issue Templates

```bash
gh api repos/<owner>/<repo>/contents/.github/ISSUE_TEMPLATE | jq -r '.[].name'
```

Fetch the relevant template to understand required fields and constraints:

```bash
gh api repos/<owner>/<repo>/contents/.github/ISSUE_TEMPLATE/<template>.yml | jq -r '.content' | base64 -d
```

If templates exist, the issue **must** be filed through the web form at:
`https://github.com/<owner>/<repo>/issues/new/choose`

`gh issue create` bypasses template enforcement — do not use it when templates are required.

## Step 3 — Search Existing Issues

Before proposing anything, search for prior art:

```bash
gh issue list --repo <owner>/<repo> --search "<keywords>" --json number,title,state | jq
```

Or via web_fetch on the issues search URL. Identify:
- Exact duplicates (do not file)
- Related issues to reference in the new issue
- How the maintainers responded to similar proposals (signals what they value)

## Step 4 — Draft

Keep drafts short and concrete. If the project has a length limit ("fits on one screen"), respect it.

Regarding AI assistance: present the draft to the user in plain text fields matching the template structure. Note that the user should post it themselves and decide whether to disclose AI involvement per the project's policy. Do not post on behalf of the user without explicit confirmation.

When the project prohibits or discourages AI-generated text, flag this clearly and offer to outline the key points instead so the user can write in their own voice.

## Step 5 — Post

Only post after the user has reviewed and approved the final text.

For template-enforced issues: provide the text and the URL, let the user post through the web form.

For non-template issues or when `gh` posting is appropriate:

```bash
gh issue create --repo <owner>/<repo> --title "..." --body "..."
```

## Closing Bad Posts

If an issue was posted incorrectly (wrong format, too long, bypassed template):

```bash
gh issue close <number> --repo <owner>/<repo> --comment "Closing to resubmit correctly."
```

Then repost via the correct path.
