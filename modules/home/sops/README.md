# Secrets Management with sops-nix

This directory holds the **sops aspect pair** for this flake: the home-manager
aspect (`modules/home/sops/default.nix`) and — separately — the NixOS-level
aspect (`modules/nixos/sops.nix`). Both read the **same** encrypted file,
`modules/home/sops/secrets/secrets.yaml`, but they decrypt it with different
keys and expose the result in different places.

## Two layers

| | NixOS layer (`modules/nixos/sops.nix`, `modules/nixos/wifi.nix`) | home-manager layer (`modules/home/sops/default.nix`) |
| --- | --- | --- |
| decryption key | the **host** key `/persist/etc/ssh/ssh_host_ed25519_key` (`sops.age.sshKeyPaths`) | `~/.config/sops/age/keys.txt` — the age private key **derived from that same host key** |
| when | boot / activation, before any user session exists | user session, via the `sops-nix` user service |
| output | `/run/secrets-for-users/` (`neededForUsers`), `/run/secrets/`, rendered env files under `/run/secrets/rendered/` | `$XDG_RUNTIME_DIR/secrets/` |
| secrets declared | `user-password` (with `neededForUsers`, so it decrypts before login and `users.users.vkarasen.hashedPasswordFile` resolves), `wifi-home-psk` (+ `sops.templates."wifi-home-psk-env"` feeding `networking.networkmanager.ensureProfiles`) | `tavily_api_key`, `anthropic_api_key`, `deepseek_api_key`, `google_oauth_client_id`, `google_oauth_client_secret`, `linkedin_api_key`, `rclone_gdrive_conf`, `rclone_nextcloud_conf` — all inside `lib.mkIf config.my.is_private` |

A secret that is **declared in Nix but missing from `secrets.yaml`** makes the
corresponding layer fail at activation: sops-nix refuses to start rather than
expose a partially populated secret set. (`mcp_proxy_auth_token` is declared
only when `my.pi.mcpProxy.requireAuth` is enabled, which is off by default.)

## Setup Instructions

### 1. Recipients are machine host keys

This config does **not** use a personal/user age key. Every recipient in
`.sops.yaml` is a **NixOS host's** ed25519 SSH host key, converted to an age
recipient with `ssh-to-age`. Secrets are then decryptable on that host (and
only there) without any user-held key, and adding a machine is the only way the
recipient list grows:

```bash
# on the host (or on the staged key before first install):
ssh-to-age < /persist/etc/ssh/ssh_host_ed25519_key.pub   # → age1… recipient
```

The private half **never** leaves the machine's `/persist` (plus an offline
copy in the KeePassXC database as an attachment — it is the only thing that can
decrypt `secrets.yaml`).

For the home-manager sops module, `~/.config/sops/age/keys.txt` must hold the
age **private** key derived from that same host key — not from
`~/.ssh/id_ed25519`, which is not a recipient at all:

```bash
(umask 077; sudo ssh-to-age -private-key -i /persist/etc/ssh/ssh_host_ed25519_key > /tmp/keys.txt)
mkdir -p ~/.config/sops/age
install -m 600 /tmp/keys.txt ~/.config/sops/age/keys.txt && rm /tmp/keys.txt
```

### 2. Configure .sops.yaml

Add the host's recipient as an anchor under `keys:` **and** reference it in
**every** `creation_rules` entry — a recipient enrolled in only one rule leaves
the other path family undecryptable on that host. Real shape of this repo's
file (`modules/home/sops/secrets/*` + `modules/home/pi/skills-private/*.md`):

```yaml
keys:
  - &troy age1…       # derived from troy's /persist/etc/ssh/ssh_host_ed25519_key
  - &sarasti age1…    # derived from sarasti's, pre-seeded before install

creation_rules:
  - path_regex: modules/home/sops/secrets/[^/]+\.(yaml|json|env|ini)$
    key_groups:
      - age: [*troy, *sarasti]
  - path_regex: modules/home/pi/skills-private/[^/]+\.md$
    key_groups:
      - age: [*troy, *sarasti]
```

Then re-encrypt every covered file (`sops updatekeys -y <file>`, one file at a
time) and commit — the flake only sees the git tree. The full enrolment
procedure, including pre-seeding the host key before a fresh install, is in
`docs/nixos-install.md` §8 **Step 0.5**.

### 3. Add or edit a secret

The file already exists and is encrypted — edit it in place (never delete and
recreate it; a fresh file would come back with the current `.sops.yaml`
recipients and no other content):

```bash
sops modules/home/sops/secrets/secrets.yaml
```

`sops` decrypts to a temp file, opens `$EDITOR`, and re-encrypts on save. Add
plain YAML entries, e.g. `my_new_secret: <value>`.

### 4. Declare the secret in Nix

A key that exists only in `secrets.yaml` is never decrypted; it also has to be
declared by the layer that consumes it.

**home-manager layer** — inside the existing `sops.secrets = lib.mkIf
config.my.is_private { … }` block in `modules/home/sops/default.nix`:

```nix
secrets = lib.mkIf config.my.is_private {
  # … existing entries …
  my_new_secret = {};
};
```

If something needs it as an environment variable, follow the pattern already
used there (one `lib.mkIf` entry inside `home.sessionVariables`):

```nix
(lib.mkIf (config.my.is_private && config.sops.secrets ? my_new_secret) {
  MY_NEW_SECRET = "$(cat ${config.sops.secrets.my_new_secret.path})";
})
```

**NixOS layer** — inside `sops.secrets` in `modules/nixos/sops.nix` (secrets
that must exist before login) or, if only some hosts need it, in the aspect
that consumes it (see `modules/nixos/wifi.nix`, which declares
`wifi-home-psk` itself so it decrypts only on hosts that opt into wifi).

### 5. Apply the configuration

```bash
git add modules/home/sops/secrets/secrets.yaml   # the flake only sees git-tracked files
nh os switch .                                   # NixOS host (system layer)
nh home switch                                   # portable home-manager config
```

The home-manager layer is decrypted by the `sops-nix` user service into
`$XDG_RUNTIME_DIR/secrets/` at login; the NixOS layer is decrypted during
activation (`sops-install-secrets`).

## Usage Examples

### Environment Variables

Secrets are automatically available as environment variables in new shells:

```bash
echo $TAVILY_API_KEY
echo $OPENAI_API_KEY
```

### Service Dependencies

If you have systemd user services that need secrets, make them depend on sops-nix:

```nix
systemd.user.services.myservice = {
  unitConfig.After = [ "sops-nix.service" ];
  # ... rest of service config
};
```

### Templates

You can embed secrets in configuration files using templates:

```nix
sops.templates."myapp-config.toml".content = ''
  api_key = "${config.sops.placeholder.tavily_api_key}"
  database_url = "postgres://user:${config.sops.placeholder.db_password}@localhost/mydb"
'';
```

### Full-file secrets for rclone mounts

The rclone mount module expects a complete
`~/.config/rclone/rclone.conf` file to be stored as a single sops secret
named `rclone_gdrive_conf`.

That means the one-time auth procedure is:

1. Run `rclone config` once and complete the Google OAuth browser flow.
2. Confirm the remote works.
3. Copy the resulting `rclone.conf` contents into the encrypted sops file
   under `rclone_gdrive_conf`.
4. Rebuild Home Manager; the mount service will read the decrypted file on
   every machine.

If you prefer to keep the Google Workspace MCP client and the Drive mount
fully separate, create a dedicated OAuth client for rclone and place its
client ID, client secret, and token inside that `rclone.conf` blob.

A Nextcloud remote needs a **second** full-file secret, `rclone_nextcloud_conf`,
holding its own `[nextcloud]` config section. It uses an app password instead of
an OAuth browser flow:

```bash
rclone config create nextcloud webdav vendor=nextcloud \
  url=https://nextcloud.zqnr.de/remote.php/dav/files/vkarasen \
  user=vkarasen pass='<app-password>'
```

`rclone config create` obscures the password automatically. Copy the resulting
`[nextcloud]` section into sops from the config **file** — NOT `rclone config
show`, which masks `pass` as `*** ENCRYPTED ***`:

```bash
sed -n '/\[nextcloud\]/,$p' ~/.config/rclone/rclone.conf
```

At activation every `rclone_*_conf` blob is concatenated into the single
`~/.config/rclone/rclone.conf`, so all mounts and syncs share one config file.
## Managing Secrets

### Edit existing secrets

```bash
sops modules/home/sops/secrets/secrets.yaml
```

### Add a new secret

1. Add the value: `sops modules/home/sops/secrets/secrets.yaml`
2. Declare it in the layer that consumes it (see §4 above)
3. `git add` the re-encrypted file — an unstaged edit is invisible to the flake
4. `nh os switch .` / `nh home switch`

### Add a host

A host is added as a **recipient** by enrolling its ed25519 SSH host key: add
the `age1…` anchor to `.sops.yaml` **and reference it in every
`creation_rules` entry** (shape in §2), then re-encrypt every covered file.
The full procedure — including pre-seeding the host key for a fresh install —
is `docs/nixos-install.md` §8 **Step 0.5**.

### Rotate keys / re-encrypt for a new recipient list

```bash
nix run nixpkgs#sops -- updatekeys -y modules/home/sops/secrets/secrets.yaml
# each encrypted private skill/policy is its own file — repeat per file:
nix run nixpkgs#sops -- updatekeys -y modules/home/pi/skills-private/<name>.md
```

`updatekeys` has to **decrypt** the data key first, so it must run on a machine
that already holds an enrolled recipient's private key — i.e. **troy** or
**sarasti** (their `/persist/etc/ssh/ssh_host_ed25519_key`), never on a host
whose key is not yet enrolled and never on a checkout that only has git access.
Commit the re-encrypted files; the flake only sees git-tracked content.

## Security Notes

- The **root of trust is the host key**: `/persist/etc/ssh/ssh_host_ed25519_key`
  on each host, whose private half also lives in the KeePassXC database
  (`~/sync/private/vkarasen.kdbx`) as an attachment. Lose both host keys and
  `secrets.yaml` is unreadable — there is no user key and no recovery path.
- `~/.config/sops/age/keys.txt` is a derived copy of that identity (mode 600).
  It must never be created from `~/.ssh/id_ed25519` — that key is not a
  recipient.
- Encrypted `.sops` files are safe to commit to version control; plaintext is
  never written to the nix store.
- home-manager secrets land in `$XDG_RUNTIME_DIR/secrets/` (memory-backed);
  NixOS-level secrets land under `/run/secrets*` — the wifi PSK additionally
  renders into `/run/secrets/rendered/wifi-home-psk-env` (0400, root).

## Troubleshooting

### Secrets not available (home-manager layer)

- Check the user service: `systemctl --user status sops-nix`
- Logs: `journalctl --user -u sops-nix`
- **First thing to check is the key identity.** `~/.config/sops/age/keys.txt`
  must be derived from the **host** key, and its public half must equal a
  recipient in `.sops.yaml`:
  ```bash
  age-keygen -y ~/.config/sops/age/keys.txt   # compare with the age1… anchors
  ```
  No match = the file was derived from the wrong key (e.g. `~/.ssh/id_ed25519`)
  or copied from another machine. Re-derive it on the host:
  `(umask 077; sudo ssh-to-age -private-key -i /persist/etc/ssh/ssh_host_ed25519_key > /tmp/keys.txt)`
  then `install -m 600 /tmp/keys.txt ~/.config/sops/age/keys.txt && rm /tmp/keys.txt`.

### System secrets not available (NixOS layer)

- `systemctl status sops-install-secrets` — a failed unit here means the host
  key cannot decrypt: either it is not the enrolled key or the `.sops.yaml` /
  `updatekeys` commit was not the one deployed (the flake only sees git).
- `sudo test -s /run/secrets-for-users/user-password && echo system-ok` is the
  canonical check (`neededForUsers` puts it there).

### Permission denied

- `chmod 600 ~/.config/sops/age/keys.txt`; the directory must not be
  world-readable.

### Can't edit secrets

- `sops` is in `home.packages`; otherwise `nix run nixpkgs#sops -- …`.
- Verify `.sops.yaml` still lists this host's recipient, and that it can decrypt:
  `nix run nixpkgs#sops -- -d modules/home/sops/secrets/secrets.yaml > /dev/null`.
