---
name: obsidian-vault-bootstrap
description: Initialize or repair a standard Obsidian vault skeleton. Use when the user explicitly asks to create/bootstrap a vault or restore missing starter templates/metadata.
---

# Obsidian Vault Bootstrap Workflow

Use this skill only for explicit vault initialization or skeleton repair. Normal
read-only retrieval belongs in `obsidian-vault-read`; ongoing writes and
curation belong in `obsidian-vault-maintenance`.

## Safety boundary

A vault is mutable user state. Bootstrap tooling may create directories and
missing starter files, but it must not overwrite existing notes or templates.

Do **not** run the bootstrap script against a target directory that already
exists unless the user has expressly approved bootstrapping or repairing that
existing vault. This applies even though the script itself is idempotent and
skips existing files.

If the target directory does not exist and the user asked to create a new vault,
you may run the script without `--allow-existing`; it will create the vault
root, standard directories, and starter files.

If the target directory already exists, first explain that bootstrapping will add
only missing standard directories/files and will not overwrite existing files.
Run the script with `--allow-existing` only after the user approves that repair.

## Location

This skill contains both the script and the starter skeleton:

```text
bin/obsidian-vault-bootstrap
skeleton/
```

Resolve those paths relative to this `SKILL.md` / skill directory. The script is
intentionally skill-local and not expected to be on the user's normal `PATH`.

Default target is `$OBSIDIAN_GLOBAL_VAULT_DIR`. You may also pass an explicit
target directory as the final argument.

## Script usage

```bash
# New vault only; refuses if the target directory already exists.
/path/to/skill/bin/obsidian-vault-bootstrap "$OBSIDIAN_GLOBAL_VAULT_DIR"

# Existing vault repair only after explicit user approval.
/path/to/skill/bin/obsidian-vault-bootstrap --allow-existing "$OBSIDIAN_GLOBAL_VAULT_DIR"

# Preview actions.
/path/to/skill/bin/obsidian-vault-bootstrap --dry-run "$OBSIDIAN_GLOBAL_VAULT_DIR"
```

The script:

- refuses an existing target directory unless `--allow-existing` is passed;
- creates the standard vault directories;
- copies starter files from `skeleton/` only when the destination file is
  missing;
- never overwrites existing files;
- exits non-zero on unsafe or ambiguous input.

## Standard directories

The bootstrap script creates:

```text
_meta/
daily/
inbox/
working/
memory/
outputs/
templates/
attachments/
```

## Starter files

The skeleton provides:

```text
_meta/index.md
_meta/conventions.md
_meta/maintenance.md
templates/daily.md
templates/inbox.md
templates/working.md
templates/memory.md
templates/output.md
```

`obsidian.nvim` is configured to use `templates/` as the template directory and
`daily.md` as the daily-note template. If `templates/daily.md` is missing,
`:Obsidian today` / the daily-note workflow may create a sparse note.

## After bootstrapping

After running the script, verify:

```bash
find "$OBSIDIAN_GLOBAL_VAULT_DIR" -maxdepth 2 -type f | sort
```

Report whether the target was newly created or an existing vault repair, and
call out any files that were skipped because they already existed.
