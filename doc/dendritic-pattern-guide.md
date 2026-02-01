# Dendritic Pattern for Nix Configurations

## Overview

The **Dendritic Pattern** is a modular design approach for organizing NixOS, nix-darwin, and Home Manager configurations using the **Flake Parts** framework. It structures configuration code into reusable "aspects" organized in a tree-like (dendritic) hierarchical structure, promoting code reuse, maintainability, and clarity.

### Core Purpose
- **Modularity**: Break down monolithic configurations into small, focused, reusable modules
- **Organization**: Create a clear, hierarchical structure that mirrors your system's conceptual organization
- **DRY Principle**: Eliminate duplication through inheritance and composition
- **Flexibility**: Support multiple contexts (NixOS, nix-darwin, Home Manager) from a single codebase

### Key Technologies
1. **Flake Parts**: A framework for writing modular Nix flakes with a composable module system
2. **import-tree**: Library that automatically imports directory hierarchies as nested attribute sets
3. **Aspect Pattern**: Reusable configuration modules that can be combined and composed

---

## Core Concepts

### Flake Parts Framework
Flake Parts allows you to split your flake configuration into multiple modules, where each module can define:
- `flake.parts`: The actual flake outputs (packages, nixosConfigurations, etc.)
- `options`: Configuration options for the module
- `imports`: Other modules to include

### Import-Tree Library
Automatically converts directory structure into nested attribute sets:
```
modules/
  ├── darwin/
  │   ├── homebrew.nix
  │   └── system.nix
  └── home/
      ├── git.nix
      └── shell.nix
```
Becomes:
```nix
{
  darwin = {
    homebrew = import ./modules/darwin/homebrew.nix;
    system = import ./modules/darwin/system.nix;
  };
  home = {
    git = import ./modules/home/git.nix;
    shell = import ./modules/home/shell.nix;
  };
}
```

### Aspects
An "aspect" is a self-contained configuration module that represents a single feature, tool, or configuration concern. Aspects are organized hierarchically and can be composed to build complete system configurations.

---

## The 8 Aspect Patterns

### 1. Simple Aspect
**Purpose**: Basic, standalone configuration module with no dependencies.

**Structure**:
```nix
# modules/home/git.nix
{ config, lib, pkgs, ... }:
{
  programs.git = {
    enable = true;
    userName = "John Doe";
    userEmail = "john@example.com";
  };
}
```

**Use Case**: Individual tool configurations (git, vim, tmux, etc.)

---

### 2. Multi-Context Aspect
**Purpose**: Share configuration across different contexts (NixOS, nix-darwin, Home Manager).

**Structure**:
```nix
# modules/shared/git.nix
{ config, lib, pkgs, ... }:
{
  # Works in both home-manager and system contexts
  programs.git = {
    enable = true;
    # Shared configuration
  };
}
```

**Directory Organization**:
```
modules/
  ├── shared/     # Multi-context aspects
  ├── darwin/     # macOS-only
  ├── nixos/      # NixOS-only
  └── home/       # Home Manager-only
```

**Use Case**: Configurations that should be identical across different system types

---

### 3. Inheritance Aspect
**Purpose**: Create variations of a base configuration through inheritance.

**Structure**:
```nix
# modules/base/shell.nix
{ config, lib, pkgs, ... }:
{
  programs.zsh.enable = true;
  programs.zsh.histSize = 10000;
}

# modules/hosts/workstation/shell.nix
{ config, lib, pkgs, ... }:
{
  imports = [ ../../base/shell.nix ];
  programs.zsh.histSize = 50000;  # Override
  programs.zsh.plugins = [ /* ... */ ];  # Extend
}
```

**Use Case**: Host-specific or user-specific variations of common configurations

---

### 4. Conditional Aspect
**Purpose**: Enable/disable features based on conditions or options.

**Structure**:
```nix
# modules/features/development.nix
{ config, lib, pkgs, ... }:
{
  options.features.development = {
    enable = lib.mkEnableOption "development tools";
    languages = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
    };
  };

  config = lib.mkIf config.features.development.enable {
    home.packages = with pkgs;
      lib.optionals (lib.elem "python" config.features.development.languages) [
        python3
        python3Packages.pip
      ]
      ++ lib.optionals (lib.elem "rust" config.features.development.languages) [
        rustc
        cargo
      ];
  };
}
```

**Use Case**: Optional features that can be toggled per host/user

---

### 5. Collector Aspect
**Purpose**: Aggregate multiple related aspects into a single namespace.

**Structure**:
```nix
# modules/collections/development.nix
{ config, lib, pkgs, ... }:
{
  imports = [
    ../tools/git.nix
    ../tools/vim.nix
    ../tools/tmux.nix
    ../languages/python.nix
    ../languages/rust.nix
  ];
}

# Usage in host configuration
{
  imports = [ ./modules/collections/development.nix ];
}
```

**Directory Organization**:
```
modules/
  ├── tools/
  │   ├── git.nix
  │   ├── vim.nix
  │   └── tmux.nix
  ├── languages/
  │   ├── python.nix
  │   └── rust.nix
  └── collections/
      └── development.nix  # Imports all development-related modules
```

**Use Case**: Group related functionality for easy bulk importing

---

### 6. Constants Aspect
**Purpose**: Define shared constants, variables, and configuration data.

**Structure**:
```nix
# modules/constants/users.nix
{
  users = {
    primary = {
      name = "john";
      fullName = "John Doe";
      email = "john@example.com";
      sshKeys = [
        "ssh-ed25519 AAAAC3... john@workstation"
      ];
    };
  };
}

# modules/constants/networks.nix
{
  networks = {
    home = {
      subnet = "192.168.1.0/24";
      gateway = "192.168.1.1";
      dns = [ "1.1.1.1" "8.8.8.8" ];
    };
  };
}

# Usage
{ config, lib, pkgs, constants, ... }:
{
  users.users.${constants.users.primary.name} = {
    description = constants.users.primary.fullName;
    # ...
  };
}
```

**Use Case**: Centralize configuration data that's referenced across multiple modules

---

### 7. DRY (Don't Repeat Yourself) Aspect
**Purpose**: Extract common patterns into reusable functions or configurations.

**Structure**:
```nix
# modules/lib/mkService.nix
{ lib }:
{
  # Helper function to create systemd services
  mkService = { name, script, description, ... }: {
    systemd.services.${name} = {
      inherit description script;
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
    };
  };
}

# Usage
{ config, lib, helpers, ... }:
{
  imports = [
    (helpers.mkService {
      name = "backup";
      script = "rsync -av /data /backup";
      description = "Backup service";
    })
  ];
}
```

**Use Case**: Eliminate repetitive configuration patterns through abstraction

---

### 8. Factory Aspect
**Purpose**: Generate multiple similar configurations from a specification.

**Structure**:
```nix
# modules/factories/docker-services.nix
{ lib, pkgs, ... }:
let
  mkDockerService = { name, image, ports ? [], volumes ? [], env ? {} }: {
    virtualisation.oci-containers.containers.${name} = {
      inherit image;
      ports = map (p: "${toString p.host}:${toString p.container}") ports;
      volumes = map (v: "${v.host}:${v.container}") volumes;
      environment = env;
    };
  };

  services = [
    {
      name = "postgres";
      image = "postgres:15";
      ports = [{ host = 5432; container = 5432; }];
      volumes = [{ host = "/data/postgres"; container = "/var/lib/postgresql/data"; }];
      env = { POSTGRES_PASSWORD = "secret"; };
    }
    {
      name = "redis";
      image = "redis:7";
      ports = [{ host = 6379; container = 6379; }];
    }
  ];
in
{
  imports = map mkDockerService services;
}
```

**Use Case**: Generate multiple similar resources (services, users, networks) from data

---

## Project Structure

### Typical Dendritic Repository Layout
```
my-nix-config/
├── flake.nix                 # Main flake entry point
├── flake.lock                # Locked dependencies
├── modules/                  # All configuration modules
│   ├── base/                 # Base configurations for inheritance
│   ├── shared/               # Multi-context modules
│   ├── darwin/               # macOS-specific
│   ├── nixos/                # NixOS-specific
│   ├── home/                 # Home Manager-specific
│   ├── hosts/                # Per-host configurations
│   │   ├── workstation/
│   │   └── server/
│   ├── users/                # Per-user configurations
│   ├── collections/          # Collector aspects
│   ├── constants/            # Shared constants
│   ├── lib/                  # Helper functions
│   └── factories/            # Factory aspects
├── secrets/                  # Encrypted secrets (agenix, sops-nix)
└── README.md
```

### Flake.nix Structure
```nix
{
  description = "My Dendritic Nix Configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    import-tree.url = "github:nix-community/import-tree";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    darwin = {
      url = "github:LnL7/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs @ { flake-parts, import-tree, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" ];

      imports = [
        # Import all modules from ./modules directory
        (import-tree.lib.importTree ./modules)
      ];

      flake = {
        # NixOS configurations
        nixosConfigurations = {
          server = inputs.nixpkgs.lib.nixosSystem {
            system = "x86_64-linux";
            modules = [
              ./modules/hosts/server
              inputs.home-manager.nixosModules.home-manager
            ];
          };
        };

        # nix-darwin configurations
        darwinConfigurations = {
          workstation = inputs.darwin.lib.darwinSystem {
            system = "aarch64-darwin";
            modules = [
              ./modules/hosts/workstation
              inputs.home-manager.darwinModules.home-manager
            ];
          };
        };

        # Standalone home-manager configurations
        homeConfigurations = {
          "user@minimal" = inputs.home-manager.lib.homeManagerConfiguration {
            pkgs = inputs.nixpkgs.legacyPackages.x86_64-linux;
            modules = [ ./modules/users/minimal ];
          };
        };
      };
    };
}
```

---

## Migration Guide

### Step 1: Assess Current Configuration
**Goal**: Understand your existing configuration structure

1. **Identify configuration contexts**: Determine if you're using NixOS, nix-darwin, Home Manager, or multiple
2. **Catalog configuration files**: List all `.nix` files and their purposes
3. **Map dependencies**: Note which configurations depend on or reference others
4. **Identify patterns**: Look for repeated code, similar structures, or groupings

**Example Assessment**:
```
Current structure:
├── configuration.nix          # NixOS system config (monolithic)
├── hardware-configuration.nix # Auto-generated hardware
├── home.nix                   # Home Manager config (monolithic)
└── flake.nix                  # Basic flake wrapper

Patterns identified:
- Git config duplicated between system and home
- Multiple development tool configs that could be grouped
- Per-host differences scattered throughout
```

---

### Step 2: Set Up Dendritic Infrastructure
**Goal**: Install required tools and create base structure

1. **Update flake.nix inputs**:
```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    import-tree.url = "github:nix-community/import-tree";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Add darwin if needed
    darwin = {
      url = "github:LnL7/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs @ { flake-parts, import-tree, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" "aarch64-darwin" ];
      imports = [ (import-tree.lib.importTree ./modules) ];
      # ... rest of config
    };
}
```

2. **Create directory structure**:
```bash
mkdir -p modules/{base,shared,nixos,darwin,home,hosts,users,collections,constants,lib}
```

3. **Run initial test**:
```bash
nix flake check
```

---

### Step 3: Extract Constants
**Goal**: Centralize shared data and values

1. **Create constants modules**:
```nix
# modules/constants/users.nix
{
  users.primary = {
    name = "john";
    fullName = "John Doe";
    email = "john@example.com";
  };
}

# modules/constants/system.nix
{
  system = {
    timeZone = "America/New_York";
    locale = "en_US.UTF-8";
  };
}
```

2. **Update references** to use constants instead of hardcoded values

---

### Step 4: Create Simple Aspects
**Goal**: Break monolithic configs into focused modules

1. **Identify logical units**: Each tool, service, or feature should be a separate aspect
2. **Create aspect files**:
```nix
# modules/home/git.nix
{ config, lib, pkgs, ... }:
{
  programs.git = {
    enable = true;
    userName = "John Doe";
    userEmail = "john@example.com";
    extraConfig = {
      init.defaultBranch = "main";
      pull.rebase = true;
    };
  };
}

# modules/nixos/docker.nix
{ config, lib, pkgs, ... }:
{
  virtualisation.docker = {
    enable = true;
    autoPrune = {
      enable = true;
      dates = "weekly";
    };
  };
}
```

3. **Test each aspect** independently by temporarily importing it

---

### Step 5: Identify Multi-Context Aspects
**Goal**: Move shared configurations to `modules/shared/`

1. **Find duplicated configs** across NixOS/darwin/home contexts
2. **Extract to shared modules**:
```nix
# modules/shared/shell.nix
{ config, lib, pkgs, ... }:
{
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    syntaxHighlighting.enable = true;
  };
}
```

3. **Import shared aspects** from host/user configs

---

### Step 6: Build Collections
**Goal**: Group related aspects for easier management

1. **Identify aspect groups** (e.g., "development", "productivity", "server-base")
2. **Create collector modules**:
```nix
# modules/collections/development.nix
{ ... }:
{
  imports = [
    ../shared/git.nix
    ../shared/vim.nix
    ../home/vscode.nix
    ../nixos/docker.nix
  ];
}
```

3. **Use collections in host configs**:
```nix
# modules/hosts/workstation/default.nix
{
  imports = [
    ../../collections/development.nix
    ../../collections/productivity.nix
  ];
}
```

---

### Step 7: Implement Conditional Aspects
**Goal**: Add toggleable features

1. **Create feature options**:
```nix
# modules/features/gui.nix
{ config, lib, pkgs, ... }:
{
  options.features.gui.enable = lib.mkEnableOption "graphical user interface";

  config = lib.mkIf config.features.gui.enable {
    # GUI-specific configuration
    services.xserver.enable = true;
    programs.firefox.enable = true;
  };
}
```

2. **Enable features in host configs**:
```nix
# modules/hosts/workstation/default.nix
{
  features.gui.enable = true;
}
```

---

### Step 8: Create Base + Inheritance Structure
**Goal**: Use inheritance for host/user variations

1. **Create base configurations**:
```nix
# modules/base/nixos-base.nix
{ config, lib, pkgs, ... }:
{
  # Common to all NixOS hosts
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  system.stateVersion = "24.05";
}
```

2. **Create host-specific overrides**:
```nix
# modules/hosts/server/default.nix
{
  imports = [
    ../../base/nixos-base.nix
    ../../collections/server.nix
  ];

  # Server-specific overrides
  networking.hostName = "my-server";
  services.openssh.enable = true;
}
```

---

### Step 9: Apply DRY and Factory Patterns (Advanced)
**Goal**: Eliminate remaining duplication with abstractions

1. **Extract common patterns**:
```nix
# modules/lib/mkUser.nix
{ lib }:
{
  mkUser = { name, uid, shell ? "zsh", groups ? [] }: {
    users.users.${name} = {
      inherit uid shell;
      isNormalUser = true;
      extraGroups = [ "wheel" ] ++ groups;
    };
  };
}
```

2. **Use factories for bulk creation**:
```nix
# modules/factories/users.nix
{ lib, helpers, ... }:
let
  userSpecs = [
    { name = "alice"; uid = 1000; groups = ["docker"]; }
    { name = "bob"; uid = 1001; }
  ];
in
{
  imports = map helpers.mkUser userSpecs;
}
```

---

### Step 10: Test and Validate
**Goal**: Ensure migration is complete and functional

1. **Run flake checks**:
```bash
nix flake check
```

2. **Build configurations without applying**:
```bash
# NixOS
nixos-rebuild build --flake .#hostname

# nix-darwin
darwin-rebuild build --flake .#hostname

# Home Manager
home-manager build --flake .#user@host
```

3. **Test in VM** (for NixOS):
```bash
nixos-rebuild build-vm --flake .#hostname
./result/bin/run-*-vm
```

4. **Apply incrementally**:
```bash
# Start with non-critical host
nixos-rebuild switch --flake .#test-host

# Once confident, migrate production systems
nixos-rebuild switch --flake .#production
```

---

### Step 11: Clean Up and Document
**Goal**: Finalize migration and ensure maintainability

1. **Remove old monolithic files** (after confirming new structure works)
2. **Update README.md** with:
   - Repository structure explanation
   - How to add new hosts/users
   - How to enable/disable features
   - Common operations
3. **Add comments** to complex aspects
4. **Create examples** for common patterns in your repo

---

## Best Practices

### Module Organization
- **One purpose per module**: Each aspect should have a single, clear responsibility
- **Consistent naming**: Use descriptive names that indicate the aspect's purpose
- **Logical hierarchy**: Structure directories to reflect conceptual relationships
- **Avoid deep nesting**: Keep directory depth reasonable (3-4 levels max)

### Code Quality
- **Use lib.mkEnableOption**: For toggleable features
- **Document options**: Add descriptions to custom options
- **Prefer composition over inheritance**: Use imports and mixins rather than deep inheritance chains
- **Test incrementally**: Validate each change before moving on

### Performance
- **Lazy evaluation**: Leverage Nix's lazy evaluation; unused aspects won't impact build time
- **Avoid heavy computations**: Keep module evaluation lightweight
- **Cache-friendly**: Structure modules to maximize Nix evaluation cache hits

### Maintenance
- **Version pin inputs**: Use flake.lock for reproducibility
- **Document changes**: Keep a changelog for significant structural changes
- **Review regularly**: Periodically refactor and consolidate as patterns emerge

---

## Common Patterns and Examples

### Per-Host Configuration
```nix
# modules/hosts/workstation/default.nix
{ config, lib, pkgs, ... }:
{
  imports = [
    ../../base/darwin-base.nix
    ../../collections/development.nix
    ../../shared/shell.nix
  ];

  networking.hostName = "workstation";
  features.gui.enable = true;
  features.development.languages = [ "python" "rust" "nix" ];
}
```

### Per-User Configuration
```nix
# modules/users/john/default.nix
{ config, lib, pkgs, constants, ... }:
{
  imports = [
    ../../base/home-base.nix
    ../../collections/productivity.nix
  ];

  home = {
    username = constants.users.primary.name;
    homeDirectory = "/home/${constants.users.primary.name}";
    stateVersion = "24.05";
  };

  programs.git = {
    userName = constants.users.primary.fullName;
    userEmail = constants.users.primary.email;
  };
}
```

### Conditional Feature Bundles
```nix
# modules/features/desktop-environment.nix
{ config, lib, pkgs, ... }:
{
  options.features.desktopEnvironment = lib.mkOption {
    type = lib.types.enum [ "none" "gnome" "kde" "i3" ];
    default = "none";
  };

  config = lib.mkMerge [
    (lib.mkIf (config.features.desktopEnvironment == "gnome") {
      services.xserver.desktopManager.gnome.enable = true;
    })
    (lib.mkIf (config.features.desktopEnvironment == "kde") {
      services.xserver.desktopManager.plasma5.enable = true;
    })
    (lib.mkIf (config.features.desktopEnvironment == "i3") {
      services.xserver.windowManager.i3.enable = true;
    })
  ];
}
```

### Secrets Management Integration
```nix
# modules/shared/secrets.nix
{ config, lib, pkgs, inputs, ... }:
{
  imports = [ inputs.agenix.nixosModules.default ];

  age.secrets = {
    github-token = {
      file = ../../secrets/github-token.age;
      mode = "400";
      owner = config.users.users.primary.name;
    };
  };
}
```

---

## Troubleshooting

### Common Issues

**Issue**: `infinite recursion encountered`
- **Cause**: Circular imports between modules
- **Solution**: Review import chains; break cycles by extracting shared dependencies to a common module

**Issue**: `attribute 'X' missing`
- **Cause**: Module not properly imported or import-tree path issue
- **Solution**: Verify directory structure matches expected import paths; check for typos

**Issue**: `The option 'X' does not exist`
- **Cause**: Using option from a module that isn't imported in current context
- **Solution**: Ensure all required modules are in imports list; check context (NixOS vs darwin vs home-manager)

**Issue**: Build works locally but fails in CI/different machine
- **Cause**: Inconsistent flake.lock or missing input follows
- **Solution**: Commit flake.lock; ensure all inputs use `inputs.nixpkgs.follows = "nixpkgs"`

### Debugging Techniques

1. **Incremental testing**: Comment out imports and add them back one at a time
2. **Eval inspection**: Use `nix eval .#nixosConfigurations.hostname.config.X` to inspect resolved values
3. **Show trace**: Add `--show-trace` to build commands for detailed error context
4. **Check imports**: Verify import-tree is correctly loading modules with `nix repl`

---

## FAQ

### When should I use Dendritic Pattern?
- **Large configurations**: Multiple hosts/users with shared and unique configurations
- **Team environments**: Multiple people managing the same configuration
- **Complex setups**: Many services, tools, and integrations
- **Multiple contexts**: Using NixOS + nix-darwin + Home Manager

### When should I avoid Dendritic Pattern?
- **Simple setups**: Single host with minimal configuration
- **Learning Nix**: Start with simpler patterns first
- **Rapid prototyping**: Overhead may slow down experimentation

### How do I handle secrets?
Integrate with secrets management tools:
- **agenix**: Age-encrypted secrets
- **sops-nix**: SOPS-encrypted secrets
- Create a `modules/shared/secrets.nix` aspect that configures secret management

### Can I mix Dendritic Pattern with other approaches?
Yes! The pattern is flexible:
- Gradually migrate existing configurations
- Use dendritic structure only for specific subsystems
- Combine with other organizational patterns as needed

### How do I share aspects across repositories?
1. **Flake inputs**: Reference another repository as an input
2. **Import external modules**: `imports = [ inputs.other-config.modules.shared.git ];`
3. **Create shared library**: Publish common aspects as a separate flake

### How granular should aspects be?
**Guidelines**:
- **Too granular**: One option per file, excessive imports
- **Too coarse**: Multiple unrelated configurations in one file
- **Just right**: One logical feature/tool per aspect, related options grouped together

### What about hardware-configuration.nix?
Keep auto-generated hardware configurations separate:
```nix
# modules/hosts/myhost/default.nix
{
  imports = [
    ./hardware-configuration.nix  # Keep hardware config separate
    ../../base/nixos-base.nix
    # ... other aspects
  ];
}
```

---

## Additional Resources

### Official Documentation
- **Flake Parts**: https://flake.parts/
- **import-tree**: https://github.com/nix-community/import-tree
- **NixOS Manual**: https://nixos.org/manual/nixos/stable/
- **Home Manager**: https://nix-community.github.io/home-manager/

### Example Repositories
- **dendritic-design-with-flake-parts**: https://github.com/crdueck/dendritic-design-with-flake-parts (reference implementation)

### Community
- **NixOS Discourse**: https://discourse.nixos.org/
- **NixOS Matrix**: https://matrix.to/#/#community:nixos.org
- **r/NixOS**: https://reddit.com/r/NixOS

---

## Summary

The Dendritic Pattern transforms monolithic Nix configurations into modular, maintainable, and reusable aspects organized in a clear hierarchical structure. By combining Flake Parts and import-tree, it enables:

✅ **Modularity**: Small, focused, single-purpose modules
✅ **Reusability**: Share configuration across hosts, users, and contexts
✅ **Clarity**: Logical organization that reflects system structure
✅ **Flexibility**: Easy to add, remove, or modify features
✅ **Maintainability**: Changes isolated to specific aspects
✅ **Scalability**: Grows gracefully from simple to complex setups

The 8 aspect patterns (Simple, Multi-Context, Inheritance, Conditional, Collector, Constants, DRY, Factory) provide proven solutions for common configuration challenges. Following the migration guide, you can incrementally transform existing configurations into a dendritic structure while maintaining functionality throughout the process.

