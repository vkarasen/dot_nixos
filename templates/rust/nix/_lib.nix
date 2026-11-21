# Plain helper (underscore-prefixed => import-tree ignores it; imported by reference).
{
  inputs,
  pkgs,
  lib,
  system,
}: let
  fenixPkgs = inputs.fenix.packages.${system};

  # ---- toolchain 1: stable, pinned by rust-toolchain.toml -------------------
  # The sha256 is that of the *upstream* channel-rust-stable.toml manifest, so it
  # must be refreshed whenever stable is released (independent of the fenix
  # revision). Refresh with:
  #   nix store prefetch-file --json \
  #     https://static.rust-lang.org/dist/channel-rust-stable.toml | jq -r .hash
  toolchain = fenixPkgs.fromToolchainFile {
    file = ../rust-toolchain.toml;
    sha256 = "sha256-MFHoWVcPZKjFrLnQnodCXbUsfZcofGfo9tV9fTTvklg=";
  };

  craneLib = (inputs.crane.mkLib pkgs).overrideToolchain toolchain;

  # ---- toolchain 2: dated nightly, for the powerpc64le musl cross build -----
  # `date` + `sha256` make this fully reproducible; the hash is that of
  # https://static.rust-lang.org/dist/<date>/channel-rust-nightly.toml
  # (identical to the undated channel-rust-nightly.toml when the date is
  # today's nightly). Refresh with:
  #   nix store prefetch-file --json \
  #     https://static.rust-lang.org/dist/channel-rust-nightly.toml | jq -r .hash
  nightlyArgs = {
    channel = "nightly";
    date = "2026-10-22";
    sha256 = "sha256-V6dLt89/mszjKbYHRZ2s6fSfFTvoMrTv9o1Y4BDCMWk=";
  };

  nightlyTools = fenixPkgs.toolchainOf nightlyArgs;

  # `toolchainOf` only yields the HOST rust-std. A cross target's std must be
  # requested through `fenixPkgs.targets.<triple>.toolchainOf` — the same dated
  # manifest, restricted to that target (verified: its rust-std contains only
  # lib/rustlib/powerpc64le-unknown-linux-musl).
  powerpc64leMuslStd =
    (fenixPkgs.targets.powerpc64le-unknown-linux-musl.toolchainOf nightlyArgs).rust-std;

  nightlyToolchain = fenixPkgs.combine [
    nightlyTools.rustc
    nightlyTools.cargo
    nightlyTools.rust-std
    powerpc64leMuslStd
  ];

  nightlyCraneLib = (inputs.crane.mkLib pkgs).overrideToolchain nightlyToolchain;

  # commonCargoSources unions `*.rs`, `*.toml` and `Cargo.lock`, so rustfmt.toml,
  # clippy.toml, deny.toml, rust-toolchain.toml, .cargo/config.toml and
  # .config/nextest.toml are all present in the build source. It does NOT pick
  # up insta's `*.snap` fixtures, so those are unioned in explicitly — without
  # them every snapshot assertion fails in the sandbox.
  src = lib.fileset.toSource {
    root = ../.;
    fileset = lib.fileset.unions [
      (craneLib.fileset.commonCargoSources ../.)
      (lib.fileset.fileFilter (file: file.hasExt "snap") ../.)
    ];
  };

  cargoToml = builtins.fromTOML (builtins.readFile ../Cargo.toml);

  # `[workspace.metadata.package].name` is the single source of truth for the
  # derivation name (`pname`) and for `meta.mainProgram`. Renaming the crate is
  # therefore a one-line Cargo.toml edit, not a search-and-replace through Nix.
  packageName = cargoToml.workspace.metadata.package.name;

  meta = {
    description = cargoToml.workspace.package.description;
    license = lib.getLicenseFromSpdxId cargoToml.workspace.package.license;
    mainProgram = packageName;
  };

  commonArgs = {
    inherit src;
    pname = packageName;
    version = cargoToml.workspace.package.version;
    strictDeps = true;
    nativeBuildInputs = [pkgs.pkg-config];
    # NB: do NOT set `doCheck = false` here: cargoNextest reads `doCheck` and
    # silently skips running the tests ("doCheck is not set, nextest tests will
    # not run!"). Set it only on the buildPackage outputs in packages.nix.
  };

  cargoArtifacts = craneLib.buildDepsOnly commonArgs;
in {
  inherit toolchain craneLib src commonArgs cargoArtifacts meta;
  inherit nightlyToolchain nightlyCraneLib;
  inherit packageName;
  inherit lib pkgs;
}
