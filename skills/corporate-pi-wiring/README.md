# Corporate wiring skill

This directory contains an exported helper skill that is packaged with this
repo for downstream consumers.

It is **not** part of the local `.pi` skill set, so it should not be loaded
when working in this repository directly.

Instead, downstream flakes — especially the corporate flake — can import it as
an input and use it like a regular skill in their own pi configuration.

If you are looking for repo-local helper skills, see `.pi/skills/`.
