# Flake-parts core: enables flake.modules.<class>.<aspect> via flakeModules.modules
{ inputs, ... }: {
  imports = [
    inputs.flake-parts.flakeModules.modules
  ];

  systems = [ "x86_64-linux" "x86_64-darwin" ];
}

