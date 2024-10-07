btw I use Nix

# Bootstrapping

## non nixOS

Install Nix: https://nixos.org/download/

`nix run nixpkgs#nh -- home switch github:vkarasen/dot_nixos#vkarasen`

### WSL

Use alacritty as terminal to start WSL

Use
[Noto Nerd Font](https://github.com/ryanoasis/nerd-fonts/releases/download/v3.2.1/Noto.zip)

Alacritty config on windows goes into `%AppData%/alacritty/alacritty.yml`

Relevant example config:

```yaml
font:
    normal:
        family: 'NotoMono Nerd Font Mono'
shell:
    program: 'wsl.exe'
    args:
        - '~ -u <username>'
```
