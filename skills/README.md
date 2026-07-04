# Exported helper skills

This directory is for skills that are **packaged with the repo** but are not
part of the local `.pi` skill set.

These skills are **exported for downstream consumers** and should not be
loaded automatically when working in this repository directly.

They are intended to be imported by downstream consumers — most notably the
corporate flake that uses this repository as an input — to understand the
repo's exposed pi wiring or other reusable guidance.

Canonical example:

- `corporate-pi-wiring/`

If a skill should load automatically whenever we work in this repo, put it
under `.pi/skills/` instead.
