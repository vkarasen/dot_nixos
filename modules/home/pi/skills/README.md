# Globally wired pi skills

Skills in this directory are the **regular pi skills** that are wired into
`programs.pi-coding-agent.skills` from `modules/home/pi/default.nix`.

They are globally available in this repo's pi configuration and will also
propagate into downstream consumers, including the corporate flake, unless a
particular aspect gates them via `my.is_private` or otherwise overrides them.

If you are adding a skill that should only exist for this workspace, use
`.pi/skills/` instead.
