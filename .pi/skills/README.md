# Project-local skills

Skills in this directory are **local to this repo/workspace**.

Use them for guidance that should be loaded whenever we're working here, but
that should **not** be exported as a global pi skill through Nix.

Examples:

- repo-specific workflow guidance
- conventions for editing this configuration
- helper skills for interacting with this workspace

If a skill is meant to be packaged with the repo for downstream consumers,
place it under `skills/` instead.
