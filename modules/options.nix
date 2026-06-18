# Class-agnostic custom options (my.*). Declared under the `generic` class so
# the same option set is reusable by future nixos/darwin configs, not just home.
{
  flake.modules.generic.my-options = {lib, ...}: {
    options.my.is_private = lib.mkOption {
      type = lib.types.bool;
      default = false;
    };
    options.my.git.email = lib.mkOption {
      type = lib.types.nonEmptyStr;
      default = "vkarasen@gmail.com";
    };
    options.my.portable = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
      };
      path = lib.mkOption {
        type = lib.types.nonEmptyStr;
        default = "~/nix/nix-portable";
      };
    };
    options.my.homeConfigurationName = lib.mkOption {
      type = lib.types.nonEmptyStr;
      default = let
        user = builtins.getEnv "USER";
      in
        if user != ""
        then user
        else "vkarasen";
      description = "Name of the home configuration to use for LSP settings";
    };
  };
}
