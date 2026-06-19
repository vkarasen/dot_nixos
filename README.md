btw I use Nix

# Bootstrapping

## non nixOS

Install Nix: <https://nixos.org/download/>

`nix --experimental-features 'nix-command flakes' run nixpkgs#nh -- home switch github:vkarasen/dot_nixos -c vkarasen -- --experimental-features 'nix-command flakes'`

The common `experimental-features` flags will be written to the user specifig nix config (default `~/.config/nix/nix.conf`), so the `--experimental-features` argument is only needed for the initial invocation

### WSL

Use alacritty as terminal to start WSL

Use
[Noto Nerd Font](https://github.com/ryanoasis/nerd-fonts/releases/download/v3.2.1/Noto.zip)

Alacritty config on windows goes into `%AppData%/alacritty/alacritty.toml` ( or `/mnt/c/Users/<windows_username>/AppData/Roaming/alacritty/alacritty.toml` under WSL)

Relevant example config:

```toml
[font]
size = 10.0

[font.normal]
family = "NotoMono Nerd Font Mono"

[[keyboard.bindings]]
key = "Enter"
mods = "Shift"
chars = "\u001b[13;2u"

[terminal.shell]
program = "wsl.exe"
args = ["~ -u <wsl_username>"]
```

Note: The keyboard binding for Shift+Enter is required for pi keybindings to work correctly in tmux with extended keys format.

### Nix portable

Follow install instructions for [nix-portable](https://github.com/DavHau/nix-portable)

For home config, a new option is provided at `options.my.portable` Override in config to get access to a `nix_activate` bash function that will activate a nixified virtual environment

# TODO

- Autocompletion, maybe [nvim-cmp](https://nix-community.github.io/nixvim/plugins/cmp/index.html) or [blink.cmp](https://github.com/Saghen/blink.cmp) or [coq](https://nix-community.github.io/nixvim/plugins/coq-nvim/index.html#coq-nvim)
