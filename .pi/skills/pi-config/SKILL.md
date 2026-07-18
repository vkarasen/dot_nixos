---
name: pi-config
description: How to modify the pi coding agent configuration in this NixOS/home-manager repo. Use when adding packages, skills, prompt templates, or extra Nix build dependencies to pi.
---

# Pi Configuration in this repo

Pi is managed via home-manager. Treat `modules/home/pi/` as the primary area,
but discover the current shape with semantic tools instead of relying on a
frozen inventory. The stable landmarks are:

- `default.nix` — declares the `flake.modules.homeManager.pi` aspect
- `private.nix` — declares the `flake.modules.homeManager.pi-private` aspect
  for private skills and policies (sops-encrypted, gated by `my.is_private`)
- `skills-private/` — sops-encrypted `.md` files for private skill content
  and private AGENTS.md policy sections
- `_module.nix` — helper that defines
  `options.programs.pi-coding-agent.{skills,promptTemplates}` and wires them
  into `programs.pi-coding-agent.settings`
- `_skills.nix` — builders for complex skills that need a Nix derivation at build time
- `policies.nix` — the source of truth for public always-on AGENTS.md policy sections
  (private policies are declared here too but materialized by `private.nix`)
- `prompts/` — role prompt templates / slash commands
- server-specific adjunct aspects such as
  `google-workspace.nix`

## Skill placement guide

When you ask me to create a new skill, use the destination to encode intent:

- `.pi/skills/<name>/SKILL.md` — project-local helper skills loaded for work in
  this repo only. They are not exported through Nix and should not be treated
  as global pi capabilities.
- `skills/<name>/SKILL.md` — exported helper skills packaged with this repo
  for downstream consumers. The canonical example is
  `skills/corporate-pi-wiring`, which is intended to be imported by a
  corporate flake using this repo as an input, but is not part of the local
  `.pi` skill set.
- `modules/home/pi/skills/<name>/SKILL.md` plus wiring in
  `modules/home/pi/default.nix` — regular pi skills that are installed
  globally via Nix. These propagate into consumers like the corporate flake
  unless gated by `my.is_private`.
- `modules/home/pi/skills-private/<name>.md` plus wiring in
  `modules/home/pi/private.nix` — **private** skills encrypted with sops.
  Content never appears in plaintext in the public git repo. See
  [Adding a private skill](#adding-a-private-skill) below.

This repo uses the **dendritic pattern**: every `.nix` file under `modules/` is
auto-imported as a flake-parts module by `import-tree`. Files under `modules/home/pi/`
are mixed: `default.nix` is the aspect entry point, while `_module.nix` and
`_skills.nix` are helpers consumed *by reference* from `default.nix`. The leading
`_` is deliberate: `import-tree` ignores any path containing `/_`. If the repo
layout ever changes, trust the current module tree and the generated policy file
more than this text.

After any edit, verify with (new files must be `git add`ed first — Nix's git
flake fetcher ignores untracked files):

```bash
git add -A && nix flake check --no-build
```

---

## Looking up and suggesting packages

Use the live package catalog / discovery tooling before suggesting Pi
packages. Prefer the current indexed source over a copied list so the guidance
stays in sync with the ecosystem.

When suggesting packages, apply these filters in order:

1. **Prefer established repos.** Look for a linked GitHub repo with a
   reasonable star count, more than one contributor, and a commit history
   longer than a few weeks. A package page that links to a single-commit repo
   or has no repo link at all is a yellow flag.
2. **Warn on very new packages.** If the package was published less than ~4
   weeks ago, say so explicitly. New packages haven't had time to accumulate
   real-world scrutiny.
3. **Warn on heavy transitive dependency trees.** Pi packages are loaded
   directly into the agent process. A package that pulls in dozens of
   transitive npm dependencies is a meaningful supply-chain risk — each
   dependency is an additional trust boundary. Flag this if visible from the
   repo (e.g. a large `package.json` or a lock file with hundreds of entries),
   and prefer packages that are self-contained or have minimal deps.
4. **Prefer higher download counts** as a weak signal of community vetting,
   but don't treat it as a hard filter — a niche but well-crafted package can
   have low numbers.

Present findings as a short comparison (name, description, downloads/mo, age,
dep footprint, any flags) and let the user decide.

---

## Adding an npm or git package

Append to the `packages` list inside `programs.pi-coding-agent.settings` in
`modules/home/pi/default.nix`:

```nix
programs.pi-coding-agent = {
  settings = {
    packages = [
      # ... existing entries ...
      "npm:some-package"             # plain npm package
      "npm:@scope/some-package"      # scoped npm package
      "git:github.com/owner/repo"    # git package
    ];
  };
};
```

---

## Adding extra Nix build dependencies

`extraPackages` makes additional Nix packages available to the pi process
(e.g. runtimes a package needs at runtime). Edit `modules/home/pi/default.nix`:

```nix
programs.pi-coding-agent = {
  extraPackages = [
    pkgs.nodejs
    pkgs.bun
    pkgs.python3   # add whatever pkgs.* you need
  ];
};
```

---

## Adding a skill

### Inline (simple — just markdown)

Add a key to `programs.pi-coding-agent.skills` in `modules/home/pi/default.nix`:

```nix
programs.pi-coding-agent = {
  skills = {
    "my-skill" = ''
      ---
      name: my-skill
      description: What it does and when to use it. Be specific.
      ---

      ## Instructions
      ...
    '';
  };
};
```

The key is the skill directory name (lowercase letters and hyphens only).
`_module.nix` will write the string into a store path as `<name>/SKILL.md` and
add it to `settings.skills` automatically — no activation scripts needed.

### From a local path

If the skill has supporting files (scripts, reference docs), keep it as a
directory under `modules/home/pi/skills/<name>/` containing `SKILL.md`, then
point at it:

```nix
skills."my-skill" = ./skills/my-skill;   # path to dir containing SKILL.md
```

### Derivation-based (skill body generated by a binary)

When the skill content must be produced at build time by a tool (see: ast-bro,
which runs `ast-bro prompt` to emit its instructions), add a builder to
`_skills.nix` following the existing `mkAstBroSkill` pattern:

```nix
# _skills.nix
{ pkgs, my-input, ... }: {
  mkAstBroSkill = ...;          # existing

  mkMySkill =
    pkgs.runCommand "my-skill" {
      buildInputs = [ my-input.packages."x86_64-linux".default ];
    } ''
      mkdir -p $out
      ${my-input.packages."x86_64-linux".default}/bin/my-tool prompt > $out/SKILL.md
    '';
}
```

Then in `default.nix`, pass the new input at the flake-parts level (the outer
`{ inputs, ... }:` function) rather than as an HM module arg, so it stays
cross-flake portable:

```nix
{ inputs, ... }: {
  flake.modules.homeManager.pi = let
    myInput = inputs.my-input;   # close over here
    astBroInput = inputs.ast-bro;
  in { pkgs, lib, config, ... }: let
    skills = import ./_skills.nix {
      inherit pkgs;
      ast-bro = astBroInput;
      my-input = myInput;
    };
    mySkill = skills.mkMySkill;
  in {
    imports = [./_module.nix];
    programs.pi-coding-agent.skills."my-skill" = mySkill;
  };
}
```

The derivation must produce a directory with `SKILL.md` at its root.

---

## Adding a prompt template (slash-command)

Prompt templates become `/name` slash-commands inside pi. Add to
`programs.pi-coding-agent.promptTemplates` in `modules/home/pi/default.nix`:

```nix
programs.pi-coding-agent = {
  promptTemplates = {
    review = ''
      ---
      description: Review staged changes for bugs and security issues
      ---
      Review `git diff --cached`. Focus on bugs, security, and error handling.
    '';
  };
};
```

The key becomes the command name — the above registers `/review`.

---

## Adding a private skill

Private skills are sops-encrypted files whose content must not appear in
plaintext in the public git repository. They are materialized at activation
time into `~/.pi/agent/skills-private/<name>/SKILL.md`.

### Step 1: Create the encrypted skill file

```bash
sops modules/home/pi/skills-private/<name>.md
```

sops will open your editor with a blank file. Write the full SKILL.md content
(frontmatter + body). When you save and exit, sops encrypts it in place.

### Step 2: Declare the skill in private.nix

Open `modules/home/pi/private.nix` and add an entry to `my.pi.privateSkills`:

```nix
my.pi.privateSkills."<name>" = ./skills-private/<name>.md;
```

That's it — the aspect auto-generates the `sops.secrets` entry, handles
decryption at activation, and registers `~/.pi/agent/skills-private/` in
pi's `settings.skills` for auto-discovery.

For the full sops encrypt/edit workflow suitable for an agent, see the
**`edit-private-skill`** skill.

## Adding a private policy section

Private AGENTS.md sections use the same mechanism: sops-encrypted files
declared as path values in `my.pi.globalAgentPolicies`.

### Step 1: Create the encrypted policy file

```bash
sops modules/home/pi/skills-private/<name>.md
```

Write the policy markdown (no frontmatter needed — it's a raw section, not a skill).

### Step 2: Declare the policy in private.nix

```nix
my.pi.globalAgentPolicies."<order>-<name>" = ./skills-private/<name>.md;
```

The key prefix controls ordering among all policies (public and private), e.g.
`"92-secret-nix-workspace"` for a private section that extends `"00-nix-workspace"`.

For the full sops encrypt/edit workflow suitable for an agent, see the
**`edit-private-skill`** skill.

## Adding a global always-on instruction (AGENTS.md policy)

Skills are opt-in (description-triggered). For **always-on** behavioral
directives that apply in every session — e.g. "never search /nix/store",
"prefer Node.js for scripting" — use the `my.pi.globalAgentPolicies` option
instead. Pi loads `~/.pi/agent/AGENTS.md` at startup unconditionally.

The option is declared in `modules/options.nix` (generic class, so it is
available to home-manager, NixOS, and darwin configs alike). Values are merged
by the module system — multiple flakes can each add their own sections without
conflicting.

```nix
# In any home-manager aspect (or the corporate flake's pi module):
my.pi.globalAgentPolicies = {
  # Key is sorted alphabetically; use numeric prefix to control order.
  "90-corporate" = ''
    # Corporate policy
    Always use the internal Artifactory mirror for npm packages.
    Never push to public GitHub from a corporate workspace.
  '';
};
```

Rules:

- Keys are sorted alphabetically before concatenation → use `"00-"`, `"10-"`,
  `"90-"` prefixes to control section order.
- For **public** (string) values: `lib.types.lines` means two modules can write
  the **same** key and both contributions are appended (newline-separated).
- For **private** (path) values: the path must point to a sops-encrypted `.md`
  file under `skills-private/`. The content is decrypted at activation time and
  appended to AGENTS.md in key order. Only active when `my.is_private` is true.
- `lib.mkForce` on a key replaces any lower-priority definition entirely.
- The base always-on policy sections live in `modules/home/pi/policies.nix`.
  Treat the generated `~/.pi/agent/AGENTS.md` or the policy source as the live
  inventory if you need the exact current set; avoid copying it here.

---

## How the wiring works

`_module.nix` converts every `programs.pi-coding-agent.skills` entry into an
absolute Nix store path and appends it to `programs.pi-coding-agent.settings.skills`.
That array is serialised into `settings.json` inside `configDir` (default:
`~/.pi/agent`). Pi reads `settings.json` at startup and loads skills from the
listed paths. The store paths are absolute, so the setup is unaffected by
changes to `configDir`.

Prompt templates follow the same pattern via `settings.prompts`.

`my.pi.globalAgentPolicies` is wired in two stages:

- **Public** (string) sections are collected by the `pi-policies` aspect,
  sorted by key, and written to `home.file.".pi/agent/AGENTS.md"` as a
  Nix-store file.
- **Private** (path) sections are handled by the `pi-private` aspect: at
  activation time, it reads the public base, appends the decrypted private
  sections in key order, and writes the final `AGENTS.md` (overwriting the
  Nix-store symlink with a regular file).

Private skills follow a similar two-stage flow: the `pi-private` aspect
auto-generates `sops.secrets` entries, decrypts at activation, and
materializes each skill into `~/.pi/agent/skills-private/<name>/SKILL.md`.
