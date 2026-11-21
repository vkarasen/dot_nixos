# Rust workspace template (flake-parts + crane + fenix)

A batteries-included Rust **cargo workspace** flake: dendritic modules, a
generated-and-committed lockfile pair, an 8-check verification suite, four
build targets (native dynamic, native musl static, two cross builds) and a
reproducible fenix devshell.

The workspace it ships is deliberately *not* a hello-world: **`tally-core`** (a
library) and **`tally`** (a CLI over it) form a small but complete program that
exercises the whole toolchain — parsing, parallel aggregation, a graph algorithm
and async I/O — so every check and every cross target has something real to
build.

- **flake-parts + import-tree** — one file per concern under `nix/`.
- **crane** — incremental `cargoArtifacts` so dependency builds are cached.
- **fenix** — toolchain pinned by `rust-toolchain.toml`, not by nixpkgs.
- **two toolchains** — stable plus a dated-pinned nightly, in parallel.
- **8 checks**, four build targets, devshell with nextest/deny/audit.

> **Understanding the project.** This template ships a guided tour as an agent
> skill at [`templates/rust/.pi/skills/project-tour/SKILL.md`](.pi/skills/project-tour/SKILL.md)
> (`.pi/skills/project-tour/SKILL.md` once the template is materialized). It
> explains *why* each crate was chosen, where the architecture/business-logic
> line falls, how the library keeps its zero-cost claims, and how the nix side
> is wired. Ask your agent to load the `project-tour` skill — e.g. "load the
> project-tour skill and explain the aggregate command" — instead of asking it
> to reverse-engineer the tree.

## What is `tally`?

A toolkit for one line-oriented log format:

```text
<ts_ms> <LEVEL> <component> [key=value ...]

1700000000000 INFO engine parent=scheduler latency_ms=12
```

- `ts_ms` — unsigned milliseconds since the Unix epoch.
- `LEVEL` — `TRACE|DEBUG|INFO|WARN|ERROR|FATAL` (parsed case-insensitively,
  rendered upper-case on the wire, serialised lower-case).
- `component` — a non-empty token, no whitespace.
- `key=value` — keys are `[a-z][a-z0-9_]*`, values are non-empty tokens. The
  key `parent` is reserved: it records a dependency edge.

| crate | role |
|---|---|
| `crates/tally-core` | library: grammar, model, engine, numeric, graph, async source, typestate pipeline |
| `crates/tally` | CLI: five subcommands, format conversion, logging |

```bash
nix run .# -- parse --files app.log               # echo records in canonical form
nix run .# -- aggregate --files app.log --summary # counts per component
nix run .# -- aggregate --files app.log --matrix  # components x levels matrix
nix run .# -- graph --files app.log               # topological dependency order
nix run .# -- graph --files app.log --scc         # strongly connected components
nix run .# -- convert --files app.log --format yaml
nix run .# -- inspect --files app.log --threshold 60
cat app.log | nix run .# -- parse --stdin -vv
```

Every subcommand takes either `--stdin` or `--files <FILE>...` (never both) and
honours the global `--format json|yaml|toml`, `-v/-vv/-vvv` and `-L <LEVEL>`.

### Crates on display

| crate | what the template demonstrates with it |
|---|---|
| `winnow` | a `Partial`-based streaming grammar (`LineParser`) |
| `nutype` + `serde` | invariants enforced at construction *and* deserialisation |
| `bon` | a struct builder (`Record`) and a function builder (`count_by`) |
| `rayon` + `ndarray` | scatter/fold/reduce into a map and into a dense matrix |
| `petgraph` | dependency graph, toposort, strongly connected components |
| `trait-variant` | an `async fn` trait the library defines and the CLI implements |
| `clap` + `miette` | argument groups and fancy diagnostics |
| `tokio` (CLI only) | concurrent file/stdin reading; the library never links it |
| `insta` + `rstest` + `proptest` | snapshots, table tests, round-trip properties |

## Examples

Three input files under [`examples/`](examples/) are enough to exercise every
subcommand:

| file | shape | shows off |
|---|---|---|
| `examples/basic.log` | 10 records, 4 components, all six levels, mostly flat | `parse`, `aggregate`, `convert`, `inspect` |
| `examples/dependencies.log` | a clean 5-node DAG via `parent=` (`lb → router → {gateway → api, cache}`) | `graph` toposort, `--scc` |
| `examples/cycle.log` | a 2-node cycle (`a parent=b`, `b parent=a`) | `graph` cycle detection |

The examples below were run from `templates/rust/` (after
`git init && git add -A` there). Replace the `cargo run -p tally --` prefix
with `nix run .# --` to run the packaged binary instead, e.g.
`nix run .# -- parse --files examples/basic.log`. Inside `nix develop .#` the
`cargo run -p tally -- …` prefix is the shortest form.

### Parse and echo the canonical form

```bash
cargo run -p tally -- parse --files examples/basic.log
```

```text
1700000000000 INFO engine hits=3 latency_ms=12
1700000000100 WARN engine latency_ms=840 retries=2
1700000000200 ERROR engine queue_depth=97
1700000000300 DEBUG engine latency_ms=7
1700000000400 INFO router hits=1042
1700000000500 INFO router latency_ms=31 parent=engine
1700000000600 TRACE router queue_depth=0
1700000000700 INFO cache hits=998 latency_ms=2
1700000000800 FATAL cache queue_depth=512 retries=5
1700000000900 WARN metrics hits=17
```

Every record is re-rendered: attributes are sorted by key (`hits=3
latency_ms=12`), the level is upper-case on the wire. That is the round-trip
property the `proptest` suite pins down.

### Verbosity: `-v` ladder vs `-L`

Logs go to **stderr**, records to stdout, so the two never mix in a pipe. The
ladder (from `clap-verbosity-flag`, default = `ERROR`) is:

| flag | max level |
|---|---|
| _(none)_ | `ERROR` |
| `-v` | `WARN` |
| `-vv` | `INFO` |
| `-vvv` | `DEBUG` |
| `-vvvv` | `TRACE` |
| `-q` | `OFF` (all logging muted) |

The ladder is a single counter: `-v` and `-q` move it in opposite directions
from the `ERROR` baseline, so `-q` is one step below the default and mutes the
subscriber entirely (further `-q` flags stay at `OFF`). `--quiet` is long form
for `-q`. `-q` and `-v` **conflict** — clap rejects the combination:

```text
$ cargo run -p tally -- parse --files examples/basic.log -q -v
error: the argument '--quiet...' cannot be used with '--verbose...'
```

`--pretty` switches the formatter from compact to multi-line: each event gets
its own indented block with the source location underneath (it keeps the same
level filter, it only changes the shape). With `--pretty -vv`:

```text
  2026-11-21T19:40:56.527056Z  INFO cli: parsing records, command: "parse"
    at crates/tally/src/commands/parse.rs:23

  2026-11-21T19:40:56.527483Z  INFO cli: parsed records, count: 10
    at crates/tally/src/commands/parse.rs:25
…
```

`-L/--log-level <LEVEL>` is a hard override (it takes precedence over `-v` and
still lets `RUST_LOG` refine it). At `DEBUG` the two commands look the same:

```bash
cargo run -p tally -- parse --files examples/basic.log -vvv
cargo run -p tally -- parse --files examples/basic.log -L debug
```

```text
2026-11-21T19:26:23.078738Z  INFO cli: parsing records command="parse"
2026-11-21T19:26:23.079254Z  INFO cli: parsed records count=10
1700000000000 INFO engine hits=3 latency_ms=12
…
```

Note the **target** column, which is how library events stay distinguishable
from the CLI's own:

- `cli` — emitted by `crates/tally/src/commands/*.rs` (the `parse`, `aggregate`,
  `graph`, `convert`, `inspect` handlers).
- `tally_core::…` — emitted by the library, one per module path:
  `tally_core::build::typestate` at `DEBUG` (visible from `-vvv`, e.g.
  `aggregate`), `tally_core::grammar` at `TRACE` (visible from `-vvvv`).

`aggregate -vvv` shows both targets interleaved:

```text
2026-11-21T19:26:25.149497Z  INFO cli: aggregating command="aggregate" matrix=false by=Component
2026-11-21T19:26:25.150790Z DEBUG tally_core::build::typestate: pipeline aggregated records=10 groups=4 by=Component
2026-11-21T19:26:25.150824Z  INFO cli: summary built groups=4
```

### Aggregate: summary

```bash
cargo run -p tally -- aggregate --files examples/basic.log --summary --by component
```

```json
{
  "cache": 2,
  "engine": 4,
  "metrics": 1,
  "router": 3
}
```

`--by level` swaps the grouping key:

```bash
cargo run -p tally -- aggregate --files examples/basic.log --summary --by level
```

```json
{
  "DEBUG": 1,
  "ERROR": 1,
  "FATAL": 1,
  "INFO": 4,
  "TRACE": 1,
  "WARN": 2
}
```

The default output is pretty-printed JSON (`--format json`); `--format yaml`
and `--format toml` swap the encoder. `--threshold <PERCENT>` drops records
below a severity percentage first (the six levels are evenly spaced, so
`TRACE` is `0` and `FATAL` is `100`).

### Aggregate: matrix

```bash
cargo run -p tally -- aggregate --files examples/basic.log --matrix --format yaml
```

```yaml
components:
- cache
- engine
- metrics
- router
levels:
- TRACE
- DEBUG
- INFO
- WARN
- ERROR
- FATAL
counts:
- - 0
  - 0
  - 1
  - 0
  - 0
  - 1
…
```

Rows are the sorted components, columns are `Level::ALL` order; the output is
self-describing because the CLI encodes the axes next to the counts (the
`--format json` default is the same object, just multi-line JSON).
`--summary` and `--matrix` are mutually exclusive and one is required.

### Graph: topological order, SCCs, and cycles

```bash
cargo run -p tally -- graph --files examples/dependencies.log
```

```json
[
  "lb",
  "router",
  "cache",
  "gateway",
  "api"
]
```

Edges point `parent → child`, so the order is the order components can be
brought up. `--scc` reports strongly connected components instead:

```bash
cargo run -p tally -- graph --files examples/dependencies.log --scc --format yaml
```

```yaml
- - cache
- - api
- - gateway
- - router
- - lb
```

A cycle is a hard error (exit status 1), rendered by `miette`'s fancy handler:

```bash
cargo run -p tally -- graph --files examples/cycle.log
```

```text
Error:   × dependency cycle involving component `b`
```

> **These three outputs are illustrative, not canonical.** The exact
topological order, the order of the `--scc` groups, and the particular
component petgraph names in a cycle diagnostic are all algorithm-determined
internals of `petgraph` (and its `toposort`/`tarjan_scc` implementations). They
can differ between `petgraph` versions and between runs, so assert on *membership*
(the set of nodes, the existence of an error) rather than on these exact lines.

### Convert

```bash
cargo run -p tally -- convert --files examples/basic.log --format yaml
```

```yaml
- ts_ms: 1700000000000
  level: info
  component: engine
  attrs:
    hits: '3'
    latency_ms: '12'
- ts_ms: 1700000000100
  level: warn
  component: engine
  attrs:
    latency_ms: '840'
    retries: '2'
…
```

Note that `level` is **lower-case** under serde (`info`) while `parse` renders
it upper-case (`INFO`) — the wire form and the structured form are deliberately
different. `convert` is the round-trip entry point: `convert --format json`
emits exactly the shape that `crates/tally/tests/serde.rs` feeds back in to
prove the type invariants hold through serde too.

### Inspect

```bash
cargo run -p tally -- inspect --files examples/basic.log --threshold 85
```

```text
1700000000800 FATAL cache queue_depth=512 retries=5 (2 attributes)
severity rank: 5/5
{
  "ts_ms": 1700000000800,
  "level": "fatal",
  "component": "cache",
  "attrs": {
    "queue_depth": "512",
    "retries": "5"
  }
}
```

`--threshold 85` keeps only `FATAL` (`5 × 20 = 100 ≥ 85`), so the first
surviving record is the last line. Lower it to see an earlier record:
`--threshold 60` stops at the `WARN` on line 2. Without `--threshold` the first
record is reported.

## Quick start

```bash
nix flake init -t <this-flake>#rust      # materialize into an empty dir
git init && git add -A                   # flake.lock/Cargo.lock are committed

nix run .# -- --help                     # the five subcommands
nix develop .#                           # rustc/cargo/rustfmt/clippy + nextest/deny/audit
nix flake check                          # the 8 checks below
nix build .#static                       # static musl binary (native arch)
nix build .#aarch64-dynamic              # dynamic cross to ARM aarch64 (glibc)
nix build .#powerpc64le-static           # static musl cross to ppc64le (nightly)
```

To make it your own, rename the two crates and set
`[workspace.metadata.package].name` in `Cargo.toml` — `pname` and
`meta.mainProgram` are derived from it, so the Nix side needs no edit.

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
`{toolchain, craneLib, src, commonArgs, cargoArtifacts, meta, packageName,
nightlyToolchain, nightlyCraneLib}` plus the shared `lib` and `pkgs`. Add new
shared values there, not in a new top-level module.

## Non-Nix config files

| file | purpose |
|---|---|
| `Cargo.toml` | workspace members, shared `[workspace.package]`, dependency versions, `[workspace.lints.clippy]`, and `[workspace.metadata.package].name` (drives `pname`/`mainProgram`) |
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
