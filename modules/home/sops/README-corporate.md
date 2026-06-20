# SOPS in the Corporate Environment

The sops aspect (`modules/home/sops/default.nix`) is fully cross-flake
portable. It uses `lib.mkIf config.my.is_private` to gate all private-only
secrets, so importing it into a corporate flake with the default
`my.is_private = false` gives you a clean sops-nix baseline with no private
secrets wired in.

## How to wire the corporate flake

The authoritative guide for importing aspects from this flake into the
corporate flake is the **`corporate-pi-wiring` skill**, located at
`skills/corporate-pi-wiring/SKILL.md` in this repo. Import it into the
corporate pi agent:

```nix
skills."corporate-pi-wiring" = skills.mkSourceSkill "corporate-pi-wiring"
  (inputs.private + "/skills/corporate-pi-wiring");
```

That skill covers the full import pattern, the `extraSpecialArgs` contract
(now just `inherit inputs`), and the aspect dependency inventory.

## What the corporate environment gets from this aspect

With `my.is_private = false`:

- `pkgs.sops` installed
- `sops.age.keyFile` pointed at `~/.config/sops/age/keys.txt`
- `sops.defaultSopsFile = null` — set your own in the corporate flake
- No private secrets declared — add corporate secrets in the corporate aspect

## Adding corporate secrets

In a corporate aspect:

```nix
config.sops = {
  defaultSopsFile = ./secrets/corporate.yaml;
  secrets.my_corp_secret = {};
};
config.home.sessionVariables = {
  MY_CORP_VAR = "$(cat ${config.sops.secrets.my_corp_secret.path})";
};
```

See `README.md` in this directory for general sops-nix setup (key generation,
`.sops.yaml` configuration, editing secrets files).
