{...}: {
  perSystem = {
    self',
    lib,
    ...
  }: {
    apps.default = {
      type = "app";
      program = lib.getExe self'.packages.default;
      meta = self'.packages.default.meta;
    };
  };
}
