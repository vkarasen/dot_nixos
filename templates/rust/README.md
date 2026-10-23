# Rust workspace template (flake-parts + crane + fenix)

A batteries-included Rust **cargo workspace** flake: dendritic modules, a
generated-and-committed lockfile pair, an 8-check verification suite, four
build targets (native dynamic, native musl static, two cross builds) and a
reproducible fenix devshell.

- **flake-parts + import-tree** — one file per concern under `nix/`.
- **crane** — incremental `cargoArtifacts` so dependency builds are cached.
- **fenix** — toolchain pinned by `rust-toolchain.toml`, not by nixpkgs.
- **two toolchains** — stable plus a dated-pinned nightly, in parallel.
- **8 checks**, four build targets, devshell with nextest/deny/audit.

## Quick start

```bash
nix flake init -t <this-flake>#rust      # materialize into an empty dir
git init && git add -A                   # flake.lock/Cargo.lock are committed

nix run .#                               # build + run ./bin (prints "Hello, world!")
nix run .# -- --help                     # Usage: my-cli [NAME]
nix develop .#                           # rustc/cargo/rustfmt/clippy + nextest/deny/audit
nix flake check                          # the 8 checks below
nix build .#static                       # static musl binary (native arch)
nix build .#aarch64-dynamic              # dynamic cross to ARM aarch64 (glibc)
nix build .#powerpc64le-static           # static musl cross to ppc64le (nightly)
```

Replace the `my-lib` / `my-cli` crates (and the `my-cli` references in
`nix/packages.nix` + the bin name in `crates/my-cli/Cargo.toml`) with your
own.

## Dendritic layout

`flake.nix` stays thin — it only wires inputs and hands `./nix` to
import-tree:

```nix
outputs = inputs: inputs.flake-parts.lib.mkFlake {inherit inputs;} (inputs.import-tree ./nix);
```

Every file under `nix/` is therefore a flake-parts module:

| file | role |
|---|---|
| `nix/_lib.nix` | shared crane + **both** toolchains |
| `nix/systems.nix` | `systems` (flake-parts has **no default** here) |
| `nix/checks.nix` | the 8 `checks` |
| `nix/packages.nix` | `default`, `static`, `aarch64-dynamic`, `powerpc64le-static` |
| `nix/apps.nix` | `apps.default` |
| `nix/devshell.nix` | `devShells.default` + `formatter` |

`_lib.nix` is **underscore-prefixed on purpose**: import-tree ignores any path
containing `/_`, so the helper is never registered as a top-level module. It is
consumed *by reference* — each aspect does
`import ./_lib.nix {inherit inputs pkgs lib system;}` and gets back
`{toolchain, craneLib, src, commonArgs, cargoArtifacts, meta, nightlyToolchain,
nightlyCraneLib}` plus the shared `lib` and `pkgs`. Add new shared values there,
not in a new top-level module.

## Non-Nix config files

| file | purpose |
|---|---|
| `Cargo.toml` | workspace members, shared `[workspace.package]` + `[workspace.lints.clippy]` |
| `rust-toolchain.toml` | toolchain source of truth: channel, components, targets |
| `rustfmt.toml` | rustfmt style, consumed by the `fmt` check |
| `clippy.toml` | clippy `msrv`, consumed by the `clippy` check |
| `deny.toml` | cargo-deny bans/licenses/sources policy, consumed by `deny` |
| `.cargo/config.toml` | cargo aliases (see below) |
| `.config/nextest.toml` | nextest profile (`fail-fast = false`, slow-timeout) |
| `.config/wt.toml` | Worktrunk project config: `post-switch` copy-ignored hook (see below) |

`.cargo/config.toml` defines one alias: `cargo xtest` =
`nextest run --workspace`, so inside `nix develop .#` you can run the whole
test suite with `cargo xtest` instead of the longer form.

`.config/wt.toml` makes `wt switch` warm: on every switch it auto-copies
**gitignored build dirs** (notably `target/`) from the previous worktree into
the new one, so a fresh worktree reuses compiled dependencies instead of
rebuilding them — reflinked (copy-on-write) on btrfs/XFS/APFS, so the copy costs
~no extra disk. It excludes `.direnv/`, `result` and `result-*`: `.direnv/` is
a per-directory cache of absolute store paths for *this* source tree, so
copying it across worktrees would serve a stale env (the devshell derivation is
already shared via the Nix store). Because it is a **project** hook, Worktrunk
prompts for a one-time approval per repository on first run.

## The 8 checks

| check | enforces |
|---|---|
| `build` | `cargo build` succeeds |
| `fmt` | `cargo fmt --check` (rustfmt.toml) |
| `clippy` | `--all-targets -- --deny warnings` |
| `doc` | rustdoc with `RUSTDOCFLAGS=--deny warnings` (denies rustdoc warnings) |
| `doctest` | doc examples actually run (nextest does **not** run doctests) |
| `nextest` | unit + integration tests via cargo-nextest |
| `audit` | advisories, from the pinned `rustsec/advisory-db` flake input |
| `deny` | `bans licenses sources` per deny.toml |

`deny` deliberately runs the default `bans licenses sources` set rather than
adding `advisories`: cargo-deny would try to **clone** the advisory database
over the network, and the build sandbox has none. `audit` covers advisories
instead, reading the `advisory-db` input from the nix store.

## Build targets

`systems` covers **x86_64-linux** and **aarch64-linux**. Four packages:

| package | target | linkage | toolchain |
|---|---|---|---|
| `.#default` | native | dynamic (glibc) | stable |
| `.#static` | native musl | static | stable |
| `.#aarch64-dynamic` | `aarch64-unknown-linux-gnu` (cross) | **dynamic** | stable |
| `.#powerpc64le-static` | `powerpc64le-unknown-linux-musl` (cross) | **static** | nightly |

```bash
nix build .#default             # native, dynamically linked (glibc)
nix build .#static              # native static musl
nix build .#aarch64-dynamic     # aarch64 glibc, DYNAMIC, cross from x86_64
nix build .#powerpc64le-static  # ppc64le musl, STATIC, cross (nightly)
```

`static` picks the triple for the current system via the `muslTargets` map in
`nix/packages.nix` — `x86_64-unknown-linux-musl` on an x86_64 host,
`aarch64-unknown-linux-musl` on an aarch64 host. Both cross outputs are defined
for either system, so they can be built from an x86_64 or an aarch64 host.

### Two cross mechanisms

**Dynamic cross needs a real C toolchain.** A glibc target is dynamically
linked, so something has to produce the ELF interpreter and glibc `NEEDED`
entries. `aarch64-dynamic` therefore points the linker at the target-prefixed
`-cc` of a cross gcc from `pkgsCross`:

```nix
CARGO_BUILD_TARGET = "aarch64-unknown-linux-gnu";
CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_LINKER =
  "${pkgs.pkgsCross.aarch64-multiplatform.stdenv.cc}/bin/aarch64-unknown-linux-gnu-cc";
```

**Static musl cross needs no sysroot.** Pure-Rust crates link with `rust-lld`
plus the self-contained musl crt objects bundled in that target's `rust-std`:

```nix
"CARGO_TARGET_POWERPC64LE_UNKNOWN_LINUX_MUSL_LINKER" = "rust-lld";
"CARGO_TARGET_POWERPC64LE_UNKNOWN_LINUX_MUSL_RUSTFLAGS" =
  "-C link-self-contained=yes -C target-feature=+crt-static";
```

These are generated by `staticFor` (`lib.toUpper` over the triple) and are
**target-scoped, never a global `RUSTFLAGS`** — a global one would also apply to
the glibc `default` build, changing the flags hash and invalidating the shared
`cargoArtifacts` cache.

## Two toolchains

`nix/_lib.nix` defines two parallel toolchains and exports a crane lib for each:

1. **stable** — `fenix.packages.<system>.fromToolchainFile` reading
   `rust-toolchain.toml`. Drives `checks`, `devShells`, `default`, `static` and
   `aarch64-dynamic`.
2. **dated nightly** — `fenix.packages.<system>.toolchainOf { channel = "nightly";
   date = "2026-10-22"; sha256 = "..."; }`. Used **only** by
   `powerpc64le-static`, wrapped as `nightlyCraneLib`.

This is the recipe for running several toolchains in one flake without them
interfering: each gets its own `overrideToolchain` and its own
`cargoArtifacts`, so nothing is shared between them.

A cross target's `rust-std` is **not** in `toolchainOf`'s result (that set is
host-only). Request it per target and `combine` it in:

```nix
powerpc64leMuslStd =
  (fenixPkgs.targets.powerpc64le-unknown-linux-musl.toolchainOf nightlyArgs).rust-std;

nightlyToolchain = fenixPkgs.combine [
  nightlyTools.rustc
  nightlyTools.cargo
  nightlyTools.rust-std
  powerpc64leMuslStd
];
```

Refresh the nightly pin's `sha256` (and the `date`) with:

```bash
nix store prefetch-file --json https://static.rust-lang.org/dist/channel-rust-nightly.toml | jq -r .hash
```

## Toolchain

`rust-toolchain.toml` is the single source of truth for the **stable** toolchain:

```toml
[toolchain]
channel = "stable"
components = ["rustfmt", "clippy", "rust-src"]
targets = ["x86_64-unknown-linux-musl", "aarch64-unknown-linux-musl", "aarch64-unknown-linux-gnu"]
```

The three `targets` are what make the **stable** toolchain's cross builds
buildable: the two musl triples back `static` (and the host side of the musl
work), and `aarch64-unknown-linux-gnu` backs `aarch64-dynamic`.
`powerpc64le-unknown-linux-musl` is deliberately **absent** here — its `rust-std`
comes from the pinned nightly instead (see "Two toolchains"). Keep that line in
sync with the triples the stable toolchain must build for.

fenix's `fromToolchainFile` reads it directly, which is why a `sha256` must be
supplied — it is the hash of the channel manifest for `channel`:

```bash
nix store prefetch-file --json https://static.rust-lang.org/dist/channel-rust-stable.toml | jq -r .hash
```

Refresh that value in `nix/_lib.nix` whenever you bump `channel`. For full
reproducibility, pin a **dated release** instead of the moving `stable`
channel:

```nix
toolchain = inputs.fenix.packages.${system}.toolchainOf {
  channel = "1.99.1";
  sha256 = "sha256-...";   # nix store prefetch-file .../channel-rust-1.99.1.toml
};
```

## Optional features (placeholders)

**Coverage.** Add `"llvm-tools-preview"` to the `components` in
`rust-toolchain.toml`, then add a check built with
`rust.craneLib.cargoLlvmCov rust.commonArgs` (it writes lcov/HTML reports).

**mold linker.** Faster links on the glibc build: either override the linker in
`.cargo/config.toml` (`[target.x86_64-unknown-linux-gnu] linker = "mold"` plus
`-C link-arg=-fuse-ld=mold` in rustflags), or wrap the package's stdenv with
`pkgs.stdenvAdapters.useMoldLinker`.

**Extra cross targets.** aarch64-glibc (dynamic) and ppc64le-musl (static) are
already wired. For another musl architecture, add the triple to `targets` in
`rust-toolchain.toml` and to `muslTargets` in `nix/packages.nix`; for another
**dynamic** glibc target, follow `aarch64-dynamic` — point
`CARGO_TARGET_<TRIPLE>_LINKER` at the target-prefixed `-cc` from
`pkgs.pkgsCross.<target>.stdenv.cc` (or crane's `mkCrossToolchainEnv`), and add
that target's `rust-std` to whichever toolchain builds it.

**Pre-commit hooks.** Wire `git-hooks.nix` or `treefmt-nix` into
`nix/devshell.nix` for fmt/clippy-on-commit. Set
`pre-commit.check.enable = false` there, otherwise `nix flake check` runs the
hooks *and* the `fmt` check, double-formatting and failing spuriously.

**sccache.** Set `RUSTC_WRAPPER = "sccache"` (plus `pkgs.sccache` in
`nativeBuildInputs`) in `commonArgs` for shared compilation caching across
rebuilds.

## Regenerating Cargo.lock

After changing dependencies:

```bash
nix run nixpkgs#cargo -- generate-lockfile
```

## Gotchas

- **Both lockfiles are committed.** `flake.lock` must be re-locked after input
  changes (`nix flake update`), `Cargo.lock` after dependency changes — a stale
  lock is the usual cause of a build that differs from a local `cargo build`.
- **Nix ignores untracked files** in a git flake. After adding a file run
  `git add -N <path>` (or `git add`), or the build silently will not see it.
- **Never put `doCheck` in `commonArgs`.** `cargoNextest` reads `doCheck` and
  silently skips the tests when it is unset. Set `doCheck = false` only on the
  `buildPackage` outputs in `nix/packages.nix`.
- **Each toolchain needs its own `cargoArtifacts`.** `powerpc64le-static` runs
  `buildDepsOnly` on `nightlyCraneLib`, not on the stable one — otherwise deps
  are compiled by stable and the final link mixes `rust-std` versions.
- `nix/systems.nix` is not optional: flake-parts defaults `systems` to
  nothing, so without it every `perSystem` block is empty and `nix flake check`
  passes vacuously.
