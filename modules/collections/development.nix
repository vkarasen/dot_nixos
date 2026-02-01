{ ... }:
{
  imports = [
    ../aspects/git/default.nix
    ./editor.nix
    ./shell.nix
    ./terminal.nix
  ];
}

