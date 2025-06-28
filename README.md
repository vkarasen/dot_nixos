# 🌟 NixOS Dotfiles Configuration

> *btw I use Nix*

A comprehensive NixOS and Home Manager configuration for a modern development environment. This repository contains my personal dotfiles managed with Nix Flakes, providing reproducible and declarative system configurations.

## 🎯 Overview

This configuration includes a complete development setup with:

- **🖥️ Terminal Environment**: Bash with Starship prompt, Tmux for session management
- **📝 Text Editor**: Neovim (via NixVim) with LSP, treesitter, and extensive plugin configuration
- **🔧 Development Tools**: Git with Delta, FZF, Ripgrep, and many more CLI utilities
- **🎨 Theming**: Catppuccin color scheme across all applications
- **📦 Package Management**: Nix with flakes and Home Manager
- **🔐 SSH & Git**: Configured for secure development workflows
- **🐍 Development Templates**: Ready-to-use templates for Python, Rust, LaTeX, and Jekyll projects

## ✨ Features

### 🖥️ Terminal & Shell Environment
- **Bash** with vi-mode enabled
- **Starship** prompt for beautiful, fast prompts
- **Tmux** with Catppuccin theme and custom keybindings
- **Atuin** for enhanced shell history with search capabilities
- **Zoxide** for smart directory navigation
- **Direnv** with nix-direnv for automatic environment switching

### 📝 Text Editor (Neovim)
- **NixVim** configuration with extensive plugin ecosystem
- **LSP** support for multiple languages with diagnostics
- **Treesitter** for syntax highlighting and code understanding
- **Telescope** for fuzzy finding files, symbols, and more
- **Git integration** with Gitsigns, Fugitive, and Diffview
- **LaTeX** support with VimTeX
- **Markdown** preview capabilities
- **Debugging** support with nvim-dap
- **Which-key** for command discovery
- **Mini.nvim** plugins for enhanced functionality

### 🔧 Development Tools
- **Git** with optimized configuration and Delta diff viewer
- **FZF** for command-line fuzzy finding
- **Ripgrep** for fast text searching
- **Bat** with syntax highlighting (replaces cat)
- **Eza** for enhanced directory listings
- **File management** with LF file manager
- **Compression tools** via patool
- **JSON/YAML** processing with jq and yq
- **Table viewer** with tabiew

### 🎨 Theming & UI
- **Catppuccin Mocha** theme consistently applied across:
  - Terminal (Tmux, Starship)
  - Neovim
  - Bat syntax highlighting
  - Git Delta diff viewer
  - All compatible applications

### 📦 Package Management
- **Nix Flakes** for reproducible builds
- **Home Manager** for user environment management
- **Nix-index** database for fast package searching
- **NH** (Nix Helper) for easier system management
- **Comma** for running packages without installing

### 🐍 Development Templates
Ready-to-use Nix flake templates for different project types:
- **Python/Snakemake**: Scientific computing with numpy, pandas, matplotlib
- **Rust**: Modern systems programming with naersk
- **LaTeX**: Document preparation and typesetting
- **Jekyll**: Static site generation for blogs and websites

### 🔐 Security & Configuration
- **SSH** configuration for secure connections
- **Git** security settings with GPG support
- **Private mode** support for personal vs. work environments
- **Portable Nix** support for systems without native Nix

## 🚀 Installation

### Prerequisites

Before installing this dotfiles configuration, you need to have Nix installed on your system.

#### Installing Nix

1. **For Linux/macOS/WSL:**
   ```bash
   sh <(curl -L https://nixos.org/nix/install) --daemon
   ```

2. **Enable experimental features** (flakes and nix-command):
   ```bash
   mkdir -p ~/.config/nix
   echo "experimental-features = nix-command flakes" >> ~/.config/nix/nix.conf
   ```

3. **Restart your shell** to load the new configuration.

### 🏠 Home Manager Installation

#### Quick Install (Recommended)

For a quick installation using NH (Nix Helper):

```bash
nix --experimental-features 'nix-command flakes' run nixpkgs#nh -- home switch github:vkarasen/dot_nixos -c vkarasen -- --experimental-features 'nix-command flakes'
```

> **Note:** The `--experimental-features` flag is only needed for the initial invocation. After this, the configuration will be written to your user-specific Nix config (`~/.config/nix/nix.conf`).

#### Manual Installation

1. **Clone the repository:**
   ```bash
   git clone https://github.com/vkarasen/dot_nixos.git ~/dot_nixos
   cd ~/dot_nixos
   ```

2. **Install Home Manager and apply the configuration:**
   ```bash
   nix run nixpkgs#home-manager -- switch --flake .#vkarasen
   ```

#### Updating the Configuration

To update your configuration after changes:

```bash
# If you cloned the repository
cd ~/dot_nixos
git pull
home-manager switch --flake .#vkarasen

# Or using the GitHub flake directly
nh home switch github:vkarasen/dot_nixos -c vkarasen
```

### 🪟 Windows Subsystem for Linux (WSL)

For WSL users, additional setup is recommended for the best experience:

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

### Nix portable

Follow install instructions for [nix-portable](https://github.com/DavHau/nix-portable)

For home config, a new option is provided at `options.my.portable` Override in config to get access to a `nix_activate` bash function that will activate a nixified virtual environment

## 🛠️ Usage

### 📂 Development Templates

This repository includes several development templates that can be used to quickly start new projects:

```bash
# List available templates
nix flake show github:vkarasen/dot_nixos

# Initialize a new Python project
nix flake init -t github:vkarasen/dot_nixos#py-venv

# Initialize a new Rust project
nix flake init -t github:vkarasen/dot_nixos#rust

# Initialize a new LaTeX project
nix flake init -t github:vkarasen/dot_nixos#latex

# Initialize a new Jekyll project
nix flake init -t github:vkarasen/dot_nixos#jekyll
```

### 🔧 Common Commands

#### Package Management
```bash
# Update Home Manager configuration
nh home switch github:vkarasen/dot_nixos -c vkarasen

# Search for packages
nix search nixpkgs python

# Run a package without installing
nix run nixpkgs#hello

# Use comma for temporary package access
, cowsay "Hello from Nix!"
```

#### Git Workflow
```bash
# Git is configured with Delta for better diffs
git diff  # Shows beautiful side-by-side diffs
git log --oneline --graph  # Pretty commit history
git status  # Enhanced status display
```

#### File Management
```bash
# Enhanced directory listing
ls  # Uses eza with icons and git status
ll  # Long format with all details
lt  # Sort by modification time
ldo # List only directories
lfo # List only files
```

#### Text Search and Navigation
```bash
# Fast text search with ripgrep
grep "pattern" --type py  # Search in Python files
rg "pattern" -A 3 -B 3    # Show context around matches

# Smart directory navigation
z <partial-path>  # Jump to frequently visited directories
cd <tab>         # Use fzf for fuzzy directory completion

# File finding with fzf
<ctrl+t>         # Fuzzy find files
<ctrl+r>         # Fuzzy search command history
```

#### Tmux Session Management
```bash
# Start tmux session
tmux new-session -s work

# List sessions
tmux list-sessions

# Attach to session
tmux attach-session -t work

# Key bindings (prefix: Ctrl+A)
# Ctrl+A + f: Fuzzy find and switch windows
# Ctrl+A + |: Split window vertically
# Ctrl+A + -: Split window horizontally
```

### 🎨 Neovim Usage

The Neovim configuration includes extensive functionality:

#### Key Bindings
- **Leader key**: `;` (semicolon)
- **Local leader**: `<space>`

#### Common Operations
```vim
# File navigation
:Telescope find_files  # Find files
:Telescope live_grep   # Search text across files
:Telescope buffers     # Switch between buffers

# LSP features
gd    # Go to definition
gr    # Find references
K     # Show hover documentation
<leader>ca  # Code actions

# Git integration
:Gitsigns blame_line   # Show git blame
:DiffviewOpen         # Open diff view
:Git                  # Fugitive git interface

# File explorer
<leader>nt  # Toggle Neotree
```

### 🔍 Shell History with Atuin

Enhanced shell history with search capabilities:

```bash
# Search history
<ctrl+r>  # Interactive history search

# Atuin commands
atuin search <query>    # Search command history
atuin stats            # Show usage statistics
atuin history list     # List recent commands
```

### 📦 Nix Development

```bash
# Enter development shell
nix develop

# Build and run
nix build
nix run

# Check flake
nix flake check

# Update flake inputs
nix flake update
```

## 🎛️ Customization

### Personal Configuration

The configuration supports personal customization through options:

```nix
# home-manager configuration
{
  config.my = {
    is_private = true;  # Enable private mode
    git.email = "your.email@example.com";
    portable = {
      enable = true;
      path = "~/nix/nix-portable";
    };
  };
}
```

### Adding Packages

To add new packages, modify the `shellPackages.nix` file:

```nix
# Add to home.packages
home.packages = with pkgs; [
  # Your additional packages here
  htop
  tree
  # ...
];
```

### Customizing Neovim

The Neovim configuration is modular. You can:

1. **Add plugins**: Modify files in `modules/home/neovim/`
2. **Configure LSP**: Edit `modules/home/neovim/lsp.nix`
3. **Add keybindings**: Update `modules/home/neovim/default.nix`

### Environment Variables

Set environment variables in your shell configuration:

```bash
# Add to ~/.bashrc or shell init
export EDITOR=nvim
export BROWSER=firefox
export TERM=xterm-256color
```

## 🔧 Troubleshooting

### Common Issues

#### Nix Installation Issues
```bash
# Ensure daemon is running
sudo systemctl start nix-daemon
sudo systemctl enable nix-daemon

# Check Nix configuration
nix doctor
```

#### Home Manager Issues
```bash
# Remove old Home Manager generation
home-manager remove-generations 30d

# Rebuild from scratch
home-manager switch --flake .#vkarasen --recreate-lock-file
```

#### Font Issues
```bash
# Install Nerd Fonts
nix-shell -p nerdfonts --run "fc-cache -fv"

# Verify font installation
fc-list | grep -i nerd
```

#### SSH Key Issues
```bash
# Generate new SSH key
ssh-keygen -t ed25519 -C "your.email@example.com"

# Add to SSH agent
ssh-add ~/.ssh/id_ed25519
```

### Performance Optimization

```bash
# Enable automatic garbage collection
nix-env --delete-generations 14d
nix-store --gc

# Optimize store
nix store optimise
```

### Getting Help

- **Nix Manual**: https://nixos.org/manual/nix/stable/
- **Home Manager Manual**: https://nix-community.github.io/home-manager/
- **NixVim Documentation**: https://nix-community.github.io/nixvim/
- **Catppuccin Theme**: https://github.com/catppuccin

# TODO

## 🚧 Planned Improvements

### 📝 Neovim Enhancements
- [ ] **Autocompletion System**: Implement advanced autocompletion using one of:
  - [nvim-cmp](https://nix-community.github.io/nixvim/plugins/cmp/index.html) - Popular completion engine
  - [blink.cmp](https://github.com/Saghen/blink.cmp) - Fast Rust-based completion
  - [coq](https://nix-community.github.io/nixvim/plugins/coq-nvim/index.html#coq-nvim) - Alternative completion framework
- [ ] **Snippet Support**: Add snippet expansion capabilities
- [ ] **Code Formatting**: Integrate formatters for various languages
- [ ] **Testing Integration**: Add test runner plugins

### 🔧 Development Environment
- [ ] **Language-Specific Configurations**: 
  - Python: Enhanced virtual environment management
  - Rust: Improved cargo integration
  - JavaScript/TypeScript: Node.js development setup
- [ ] **Docker Integration**: Add Docker and container development tools
- [ ] **Database Tools**: CLI tools for database management

### 🎨 UI/UX Improvements
- [ ] **Status Line**: Enhanced status line with more information
- [ ] **Theme Variants**: Support for different Catppuccin flavors
- [ ] **Custom Keybindings**: More ergonomic key mappings

### 📦 System Integration
- [ ] **NixOS Configuration**: Full system configuration module
- [ ] **Secrets Management**: Encrypted secrets handling
- [ ] **Backup Solutions**: Automated dotfiles backup

### 🔍 Additional Tools
- [ ] **Monitoring**: System monitoring and resource usage tools
- [ ] **Network Tools**: Enhanced networking utilities
- [ ] **Media Tools**: Image and media processing capabilities

## 💡 Contributing

Feel free to open issues or submit pull requests for any of the planned improvements or new features you'd like to see!
