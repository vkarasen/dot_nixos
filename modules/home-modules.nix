# Declare the flake.homeModules option so multiple modules can contribute to it
{ lib, ... }: {
  options.flake.homeModules = lib.mkOption {
    type = lib.types.lazyAttrsOf lib.types.raw;
    default = {};
    description = "Home Manager modules exported by this flake";
  };
}

