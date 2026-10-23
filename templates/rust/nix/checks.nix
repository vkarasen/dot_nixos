{inputs, ...}: {
  perSystem = {
    pkgs,
    lib,
    system,
    ...
  }: let
    rust = import ./_lib.nix {inherit inputs pkgs lib system;};
  in {
    checks = {
      build = rust.craneLib.cargoBuild (rust.commonArgs // {inherit (rust) cargoArtifacts;});

      fmt = rust.craneLib.cargoFmt rust.commonArgs;

      clippy = rust.craneLib.cargoClippy (rust.commonArgs
        // {
          inherit (rust) cargoArtifacts;
          cargoClippyExtraArgs = "--all-targets -- --deny warnings";
        });

      doc = rust.craneLib.cargoDoc (rust.commonArgs
        // {
          inherit (rust) cargoArtifacts;
          env.RUSTDOCFLAGS = "--deny warnings";
        });

      # cargo-nextest does NOT run doctests; this check does.
      doctest = rust.craneLib.cargoDocTest (rust.commonArgs // {inherit (rust) cargoArtifacts;});

      nextest = rust.craneLib.cargoNextest (rust.commonArgs
        // {
          inherit (rust) cargoArtifacts;
          partitions = 1;
          partitionType = "count";
        });

      audit = rust.craneLib.cargoAudit (rust.commonArgs // {advisory-db = inputs.advisory-db;});

      # default cargoDenyChecks = "bans licenses sources": advisories are NOT
      # checked here because cargo-deny would try to clone the advisory DB over
      # the network (sandbox has none). cargoAudit covers advisories from the
      # pinned `advisory-db` flake input instead.
      deny = rust.craneLib.cargoDeny rust.commonArgs;
    };
  };
}
