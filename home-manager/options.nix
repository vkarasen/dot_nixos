{lib, ...}: {
  options.my.is_private = lib.mkOption {
    type = lib.types.bool;
    default = false;
  };
}
