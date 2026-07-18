---
name: edit-private-skill
description: Create or edit sops-encrypted private skills (SKILL.md) and private AGENTS.md policy sections. Use when the user asks to add a skill or global instruction that should not be publicly readable, or when working with files under modules/home/pi/skills-private/. Covers both `my.pi.privateSkills` and path-valued `my.pi.globalAgentPolicies` entries.
---

# Editing Private Skills and Policies

Private skills and policy sections live under `modules/home/pi/skills-private/`
as sops-encrypted `.md` files. Their content must never appear in plaintext in
the public git repository.

## Key locations

| Path | Purpose |
|---|---|
| `modules/home/pi/skills-private/*.md` | Sops-encrypted skill or policy content |
| `modules/home/pi/private.nix` | Declares skills (`my.pi.privateSkills`) and private policies (`my.pi.globalAgentPolicies`) |
| `modules/options.nix` | Option type declarations |
| `.sops.yaml` | sops encryption rules (key selection) |

## Creating a new private skill

### 1. Create the encrypted file

```bash
sops modules/home/pi/skills-private/<name>.md
```

This opens your editor. Write the full SKILL.md with frontmatter, for example:

```markdown
---
name: my-private-skill
description: Does X. Use when working on Y. This skill is encrypted.
---

## Instructions
...
```

Save and exit — sops encrypts the file in place automatically.

### 2. Declare the skill in private.nix

Add to the `my.pi.privateSkills` attrset in `modules/home/pi/private.nix`:

```nix
my.pi.privateSkills."<name>" = ./skills-private/<name>.md;
```

### 3. Verify

```bash
git add modules/home/pi/skills-private/<name>.md
nix flake check --no-build
```

## Creating a new private policy section

Same flow but declare in `my.pi.globalAgentPolicies`:

```bash
sops modules/home/pi/skills-private/<policy-name>.md
```

In `modules/home/pi/private.nix`, add:

```nix
my.pi.globalAgentPolicies."<order>-<name>" = ./skills-private/<name>.md;
```

The key prefix (e.g. `"92-"`) controls ordering among all policy sections.
Policy files do NOT need skill frontmatter — they're raw markdown sections
appended directly to AGENTS.md.

## Editing an existing private skill or policy

### Interactive (human)

```bash
sops modules/home/pi/skills-private/<name>.md
```

Edit, save, exit. Done. Stage with `git add`.

### Programmatic (agent)

Use sops decrypt → edit → encrypt pipeline:

```bash
# 1. Decrypt to a temp file
sops decrypt --output /tmp/skill-edit.md modules/home/pi/skills-private/<name>.md

# 2. Edit /tmp/skill-edit.md using the edit tool or write tool

# 3. Re-encrypt back
sops encrypt --output modules/home/pi/skills-private/<name>.md /tmp/skill-edit.md

# 4. Clean up
rm /tmp/skill-edit.md
```

### Verifying the encrypted file is valid

```bash
sops decrypt modules/home/pi/skills-private/<name>.md > /dev/null && echo "OK"
```

## Recognizing when content should be private

Flag content as private when it includes any of:

- Internal deployment procedures, server addresses, or infrastructure details
- Proprietary workflows or business logic
- Internal tool credentials or access patterns (even if not literal secrets)
- Security-sensitive architectural details
- Any information that would aid an attacker if the repo were public

When in doubt, ask the user: *"Should this be a private skill?"*

## After making changes

```bash
git add modules/home/pi/skills-private/ modules/home/pi/private.nix
nix flake check --no-build
```

Never commit plaintext versions of encrypted files. Always use `sops` to
create or edit them — never write to `skills-private/` directly.

## See also

- **`pi-config`** skill — the authoritative guide to the pi configuration
  architecture in this repo. Covers the Nix wiring, option types, and how
  public vs. private skills/policies fit together. Load it when you need the
  broader context beyond the sops workflow.
