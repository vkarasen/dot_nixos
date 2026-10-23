{inputs, ...}: {
  perSystem = {
    pkgs,
    lib,
    system,
    ...
  }: let
    rust = import ./_lib.nix {inherit inputs pkgs lib system;};

    # The musl target triple for each supported host system.
    muslTargets = {
      x86_64-linux = "x86_64-unknown-linux-musl";
      aarch64-linux = "aarch64-unknown-linux-musl";
    };

    # Build a fully-static musl binary for `target` with the given crane lib.
    # Pure-Rust crates link with rust-lld plus the self-contained musl crt
    # objects bundled in that target's rust-std, so no pkgsCross / musl sysroot
    # is required.
    staticFor = craneLib: target: let
      upper = lib.toUpper (lib.replaceStrings ["-"] ["_"] target);
      env = {
        CARGO_BUILD_TARGET = target;
        "CARGO_TARGET_${upper}_LINKER" = "rust-lld";
        "CARGO_TARGET_${upper}_RUSTFLAGS" = "-C link-self-contained=yes -C target-feature=+crt-static";
      };
      args = rust.commonArgs // env;
    in
      craneLib.buildPackage (args
        // {
          cargoArtifacts = craneLib.buildDepsOnly (args // {doCheck = false;});
          doCheck = false;
          meta = rust.meta // {mainProgram = "my-cli";};
        });

    # Dynamic aarch64 glibc cross build: rustc emits a dynamically linked ELF,
    # so a real cross C toolchain (for the linker + glibc sysroot) is required.
    # This comes from pkgsCross, not from rust-lld.
    aarch64DynamicArgs =
      rust.commonArgs
      // {
        CARGO_BUILD_TARGET = "aarch64-unknown-linux-gnu";
        CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_LINKER = "${pkgs.pkgsCross.aarch64-multiplatform.stdenv.cc}/bin/aarch64-unknown-linux-gnu-cc";
      };
  in {
    packages = {
      # 1. native dynamic (glibc), stable toolchain
      default = rust.craneLib.buildPackage (rust.commonArgs
        // {
          inherit (rust) cargoArtifacts;
          doCheck = false;
          meta = rust.meta // {mainProgram = "my-cli";};
        });

      # 2. native static musl, stable toolchain
      static = staticFor rust.craneLib muslTargets.${system};

      # 3. aarch64 glibc, DYNAMIC, cross from x86_64, stable toolchain
      aarch64-dynamic = rust.craneLib.buildPackage (aarch64DynamicArgs
        // {
          cargoArtifacts = rust.craneLib.buildDepsOnly (aarch64DynamicArgs // {doCheck = false;});
          doCheck = false;
          meta = rust.meta // {mainProgram = "my-cli";};
        });

      # 4. powerpc64le static musl, cross, NIGHTLY toolchain
      powerpc64le-static = staticFor rust.nightlyCraneLib "powerpc64le-unknown-linux-musl";
    };
  };
}
