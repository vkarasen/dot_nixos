# Nix code formatter
{ ... }: {
  perSystem = {pkgs, ...}: {
    formatter = pkgs.alejandra;
  };
}

