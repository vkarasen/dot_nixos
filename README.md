btw I use Nix

# Bootstrapping

## non nixOS

Install Nix: https://nixos.org/download/

Make sure to enable experimental features:

`sudo echo "experimental-features = nix-command flakes" >> /etc/nix/nix.conf`

`nix run nixpkgs#nh -- home switch github:vkarasen/dot_nixos -c vkarasen`

### WSL

Use alacritty as terminal to start WSL

Use
[Noto Nerd Font](https://github.com/ryanoasis/nerd-fonts/releases/download/v3.2.1/Noto.zip)

Alacritty config on windows goes into `%AppData%/alacritty/alacritty.yml` ( or `/mnt/c/Users/<windows_username>/AppData/Roaming/alacritty/alacritty.yml` under WSL)

Relevant example config:

```yaml
font:
    normal:
        family: 'NotoMono Nerd Font Mono'

size: 10.0

shell:
    program: 'wsl.exe'
    args:
        - '~ -u <wsl_username>'
```

# TODO

- Autocompletion, maybe [nvim-cmp](https://nix-community.github.io/nixvim/plugins/cmp/index.html) or [blink.cmp](https://github.com/Saghen/blink.cmp) or [coq](https://nix-community.github.io/nixvim/plugins/coq-nvim/index.html#coq-nvim)
- Add configurability for extendability in other flakes
- Figure out how to do a portable install
