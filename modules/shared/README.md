# Shared Modules

This directory contains **multi-context aspects** - configuration modules that work across different contexts (NixOS, nix-darwin, Home Manager).

## Purpose

Place modules here when:
- The configuration should be identical across different system types
- The module uses options available in multiple contexts
- You want to share settings between NixOS system configuration and Home Manager

## Example

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

This can then be imported from both NixOS and Home Manager configurations.

