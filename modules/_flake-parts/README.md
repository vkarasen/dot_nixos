# Flake-Parts Module Exports

This directory contains flake-parts modules that expose the configuration modules for external consumption following the **dendritic pattern**.

## Exposed Modules

The flake exposes modules via `flake.modules.<class>.<aspect>`:

### Home Manager Modules (`flake.modules.homeManager`)

```
homeManager
├── base                    # Base home-manager configuration
├── aspects
│   ├── git                 # Git configuration
│   ├── shell
│   │   ├── bash           # Bash shell configuration
│   │   └── packages       # Shell packages
│   ├── terminal
│   │   ├── tmux           # Tmux configuration
│   │   └── lf             # LF file manager
│   ├── editor
│   │   └── nixvim         # Nixvim home-manager integration
│   └── security
│       ├── sops           # SOPS secrets management
│       └── ssh            # SSH configuration
├── collections
│   ├── development        # Development tools bundle
│   ├── editor             # Editor configurations
│   ├── shell              # Shell configurations
│   ├── terminal           # Terminal configurations
│   └── security           # Security configurations
├── users
│   └── vkarasen           # User-specific configuration
└── constants
    ├── users              # User constants
    └── system             # System constants
```

### Nixvim Modules (`flake.modules.nixvim`)

```
nixvim
├── default                 # Complete nixvim configuration
├── base                    # Base nixvim configuration
└── aspects
    ├── git                 # Git integration (fugitive, gitsigns)
    ├── lsp                 # LSP configuration
    ├── treesitter          # Treesitter configuration
    ├── telescope           # Telescope fuzzy finder
    ├── markdown            # Markdown support
    ├── lint                # Linting configuration
    ├── latex               # LaTeX support
    ├── mini                # Mini.nvim plugins
    ├── which-key           # Which-key bindings
    └── dap                 # Debug Adapter Protocol
```

## Usage in External Flakes

### Adding as Input

```nix
{
  inputs = {
    dot_nixos.url = "github:vkarasen/dot_nixos";
    # or local path for development
    # dot_nixos.url = "path:/home/vkarasen/nix/dot_nixos";
  };
}
```

### Using Home Manager Modules

```nix
# In your home-manager configuration
{ inputs, ... }:
{
  imports = [
    # Import specific aspects
    inputs.dot_nixos.modules.homeManager.aspects.git
    inputs.dot_nixos.modules.homeManager.aspects.terminal.tmux

    # Or import a collection
    inputs.dot_nixos.modules.homeManager.collections.development
  ];
}
```

### Using Nixvim Modules

```nix
# In your nixvim configuration
{ inputs, ... }:
{
  imports = [
    # Import complete nixvim config
    inputs.dot_nixos.modules.nixvim.default

    # Or import specific aspects
    inputs.dot_nixos.modules.nixvim.base
    inputs.dot_nixos.modules.nixvim.aspects.lsp
    inputs.dot_nixos.modules.nixvim.aspects.telescope
  ];
}
```

### Using with Standalone Nixvim Package

```nix
# Create a standalone nixvim package with custom modules
nixvim.legacyPackages.${system}.makeNixvimWithModule {
  inherit pkgs;
  module = {
    imports = [
      inputs.dot_nixos.modules.nixvim.default
      # Add your own customizations
      ./my-custom-config.nix
    ];
  };
}
```

## Directory Structure

```
modules/_flake-parts/
├── default.nix            # Main entry point, defines flake.modules
└── README.md              # This file
```

## Design Notes

- All module paths are relative to allow proper resolution
- Constants are exposed for reference but typically imported directly in modules
- The `default` nixvim module includes all aspects for a complete setup
- Individual aspects can be composed for customized configurations

