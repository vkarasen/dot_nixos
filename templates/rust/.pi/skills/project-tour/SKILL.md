---
name: project-tour
description: Guided tour of this Rust template — why each crate was chosen, where
  the architecture/business-logic line falls, how the zero-cost claims are kept,
  how the nix side is wired, and what each tally subcommand demonstrates. Use
  whenever asked "how is X done in this project", "explain the aggregate command",
  "what's the nix wiring", "why <crate>", or to understand a file before changing
  it. Load this before reverse-engineering the tree from scratch.
---

# Tour of this project

This is the design rationale for the `tally` workspace template. The `README.md`
next to it documents *what* the flake does; this skill documents *why* the code
is shaped the way it is, and points at the file that proves each claim. Read the
file before quoting it — the snippets here are deliberately short.

## Overview: the pipeline in one paragraph

`tally` is an instructive record-aggregation pipeline, not a hello-world:

```text
custom line format  →  streaming parse  →  validated typed records
                    →  parallel scatter/gather  →  serialized output
```

One record is one line: `<ts_ms> <LEVEL> <component> [key=value ...]`. The
reserved attribute `parent=<component>` means "this component depends on
`<component>`" and is what feeds the dependency graph.

Two crates, deliberately asymmetric:

| crate | role | dependencies |
|---|---|---|
| `crates/tally-core` | the library artifact: grammar, model, engine, numeric, graph, source, typestate | **no tokio, no format crates** (no `serde_json`/`toml`/YAML), no `clap`, no `miette` |
| `crates/tally` | the CLI: five subcommands, format conversion, logging | everything presentation-shaped |

The split is the point: `tally-core` is publishable on its own. If a dependency
would force the library to know about a terminal, a runtime or a file format, it
belongs in `crates/tally/Cargo.toml` — see
`crates/tally-core/Cargo.toml` vs `crates/tally/Cargo.toml`.

## Architecture vs business logic

The crate is divided along a line that has nothing to do with the domain:

**Domain-agnostic architecture** (could serve any project):

- `crates/tally-core/src/engine/` — the `Combine` monoid
  (`engine/combine.rs:17`) and the rayon `aggregate`
  (`engine/aggregate.rs:33`, `par_iter().fold().reduce()`). It knows about
  *keys, values and a merge*, not about logs.
- `crates/tally-core/src/source/` — the runtime-agnostic async trait
  (`source/mod.rs:36`, `LocalRecordSource` → `RecordSource` via
  `trait_variant`). It knows about *pulling the next item*, not about files.
- `crates/tally-core/src/graph/` — petgraph algorithms over any
  `DiGraph<Component, ()>` (alias at `graph/mod.rs:22`; algorithms at `:69`,
  `:85`). The algorithms are
  generic over the graph type; only the node payload is domain.

**The domain**:

- `crates/tally-core/src/model/` — `Level`, `Record`, and the nutype newtypes
  (`model/record.rs:30`, `:135`, `model/value.rs:55`, `:80`, `:102`, `:124`).
- `crates/tally-core/src/grammar/` — the winnow parser for the line format
  (`grammar/mod.rs:209`, `:260`).

**The test of that separation:** the `engine/` tree can be lifted into its own
crate *unchanged* — no `use crate::model::…` appears in it. If you find yourself
adding a domain type to `engine/`, the separation has been broken and the fix is
to pass a closure/`Combine` impl instead. `numeric.rs` sits between the two: it
uses the same fold/reduce shape with an `ndarray` accumulator, so it depends on
`model` for the row/column labels but shares no code with `engine`.

## Zero-cost philosophy

Four techniques, each with a place in the tree where you can check it:

### Monomorphized generics, no `dyn` in hot paths

`aggregate<I, K, V, F>` (`engine/aggregate.rs:33`) is fully generic, so the
entry-API insert and `V::combine` inline into the fold loop. There is no trait
object anywhere on the parse → aggregate path. The doc comment at the top of
`engine/aggregate.rs` states the claim explicitly; grep for `dyn` under
`crates/tally-core/src/` and you will find none.

### Traits as compile-time seams

The seams are traits, but they are all *statically* dispatched:

- `Combine` (`engine/combine.rs:17`) — the monoid the engine folds with.
  `impl Combine for u64` (saturating add) and `impl Combine for HashMap<K, V>`
  (key-wise merge) are the two that make nesting free: a
  `HashMap<String, HashMap<Level, u64>>` is a `Combine` because its values are.
- `FromStr` / `TryFrom` — the grammar hands raw `&str` to the newtypes, which
  validate in `try_new`. This is why `Component::try_new` cannot be bypassed.
- `Serialize` — `Pipeline<Aggregated>::serialize` is generic over
  `serde::Serializer`, so the library never names a format while still letting
  the CLI emit JSON, YAML or TOML.

### Zero-copy parsing

`winnow` is used with a `Partial` stream so the parser borrows from the input
`&str` and only allocates at the boundary where the owned AST (`Record`) is
built. `LineParser` (`grammar/mod.rs:260`, `feed` at `:290`) keeps its own
buffered offset so a
line can be fed in pieces; `parse_line` (`grammar/mod.rs:209`) is the
one-shot form used by tests and doctests.

### Element-wise `Add` as the ndarray monoid

`numeric.rs:21` is the second flavour of the same three-part monoid: the
identity is `Array2::zeros(shape)`, the fold is `acc[[row, col]] += 1`, and the
reduce is element-wise `a + b` — ndarray's own `Add`. Same structure as the
hash-map engine, different accumulator.

**Where a machine-specific implementation would slot in:** as an alternate
`Combine` impl selected by `#[cfg(target_feature = "avx2")]` — e.g. a SIMD
u64-count combiner for the `numeric` path. The engine, the grammar and the model
would not change, because the only thing that varies is which `impl Combine for
T` the compiler picked. That is the practical payoff of keeping the seam a
trait with static dispatch.

## Illegal states unrepresentable

Three complementary mechanisms, all in `model/`:

- **Enums for closed sets** — `Level` (`model/record.rs:30`) has exactly six
  variants; `Level::ALL` and `Level::COUNT` derive from it, so a matrix column
  count cannot drift. Note the three spellings documented there: wire form is
  upper-case (`INFO`), serde is lower-case (`info`), parsing is
  case-insensitive. `Deserialize` is hand-written for exactly that reason.
- **`nutype` newtypes** — `Component` (`model/value.rs:55`), `AttrKey`
  (`:80`), `AttrValue` (`:102`), `Percent` (`:124`). Validation runs in `try_new`
  *and* on serde deserialisation, because nutype generates the serde impl
  through the same constructor. That is the trust-boundary property
  `crates/tally/tests/serde.rs` checks.
- **Typestate** — `Pipeline<Parsed>` → `Pipeline<Aggregated>`
  (`build/typestate.rs:27`, `aggregate` at `:63`). `Aggregated` has no public
  constructor, so the only way to reach `.emit()` is to aggregate first.
  `group_by` is only available in the `Parsed` state. The state is
  `PhantomData`, so it costs nothing at runtime.

## Crate rationale (the "why" behind each dependency)

Read this before swapping a dependency: several of these are "same name you
know, different lineage" choices.

**serde — the lingua-franca adaptor.** The model derives `Serialize`/
`Deserialize`; nothing in `tally-core` ever serialises to a concrete format. The
format adaptors (`serde_json`, `toml`, `serde_yaml`) live in
`crates/tally/src/formats.rs:41` because *which* encoding the user wants is a
presentation concern.

**`yaml_serde`, pulled in under the name `serde_yaml`.** `serde_yaml` is
abandoned upstream; `yaml_serde` is the official YAML fork. The rename lives in
`Cargo.toml`:

```toml
serde_yaml = { package = "yaml_serde", version = "0.10" }
```

which is why `formats.rs` still reads `serde_yaml::to_string(...)`.

**winnow over nom.** nom is in maintenance mode; winnow is its actively
developed fork — same lineage, same combinator style, and it adds the `Partial`
streaming mode `LineParser` relies on. It is also what `toml`'s own parser uses
now, so the toolchain is coherent.

**bon.** Compile-time typestate builders — a *struct* builder on `Record`
(`model/record.rs:134` derives `bon::Builder`) and a *function* builder on
`count_by` (`build/mod.rs:62` attribute, `:64` fn). The call site reads as named
arguments (`count_by().records(&r).key(Key::Level).call()`) with no runtime
allocation and no separate manual builder type.

**nutype.** Validated newtypes with the invariant enforced *even on serde
deserialisation* — see "Illegal states" above.

**rayon.** Uncontested choice for CPU-bound data-parallelism here:
`par_iter().fold().reduce()` is exactly the shape of a monoid aggregation, so
the code is barely longer than the sequential version. The equivalence is pinned
by `aggregate_matches_a_sequential_reference` in
`crates/tally-core/tests/engine.rs`.

**tokio — CLI only.** The library uses native `async fn` in a trait, specialised
into a `Send` flavour by `trait_variant`, and **never spawns**: a source only
*returns* a future, the caller decides when to drive it. The real consumer is
`BufferedReaderSource` (`crates/tally/src/source.rs:26`), which the CLI drives
from a tokio runtime and hands to `JoinSet::spawn` in
`crates/tally/src/commands/mod.rs`. This is why `tokio` appears in
`crates/tally/Cargo.toml` and not in `tally-core`.

**clap derive + `clap-verbosity-flag`.** Derive is the official default. The
"exactly one of these" constraints are `#[group(required = true, multiple =
false)]` structs — `InputGroup` (`crates/tally/src/cli.rs:52`) for
`--stdin` vs `--files`, `ModeGroup` (`:65`) for `--summary` vs `--matrix` — each
flattened into the subcommands that need it, so the constraint is declared once.
`--files` uses `num_args(1..)` so one flag can take a list.

**tracing.** A strict superset of `log`: the library links only `tracing` and
emits events with module-path targets; the CLI installs the subscriber once
(`init_logging`, `crates/tally/src/lib.rs:36`). That is why `cli` and
`tally_core::build::typestate` are distinguishable in the same output — see the
README's verbosity section.

**thiserror (library) / miette-fancy (CLI).** `tally-core` owns one error enum,
`LibError`, derived with `thiserror` (`crates/tally-core/src/error.rs`); the CLI
returns `miette::Result` and uses `fancy` for the rendered diagnostics.

**petgraph 0.8.** Pinned at 0.8 deliberately: 0.9 is a breaking release on the
horizon. The graph helpers are written against the generic algorithm bounds, so
the bump should be mechanical.

**ndarray, not nalgebra or faer.** nalgebra is a low-dimensional linear-algebra
library (vectors and small matrices for mechanics/geometry); faer targets heavy
dense LA. `numeric.rs` needs a *dense counter* whose reduce is element-wise
`Add` — ndarray's `Array2<u64>` with the `rayon` feature is exactly that, and
nothing more.

## Nix wiring (`nix/`)

`flake.nix` only wires inputs and hands `./nix` to import-tree, so every file
under `nix/` is a flake-parts module:

| file | role |
|---|---|
| `nix/_lib.nix` | crane + **both** toolchains; underscore-prefixed so import-tree ignores it and it is only consumed by reference |
| `nix/systems.nix` | `systems` — flake-parts has no default, so this is required |
| `nix/checks.nix` | the 8 checks |
| `nix/packages.nix` | the four package outputs |
| `nix/apps.nix` | `apps.default` |
| `nix/devshell.nix` | `devShells.default` + `formatter` (alejandra) |

**crane + fenix.** `craneLib.fileset.commonCargoSources` defines the source
filter (`.rs`, `.toml`, `Cargo.lock`, so `rustfmt.toml`/`clippy.toml`/
`deny.toml` are in the sandbox); `buildDepsOnly` produces the shared
`cargoArtifacts` every check reuses, so dependency compilation is cached per
toolchain. The toolchain comes from
`fenix.packages.<system>.fromToolchainFile`, i.e. `rust-toolchain.toml` — not
from nixpkgs.

**Name derivation.** `pname` and `meta.mainProgram` are read from
`[workspace.metadata.package] name` in `Cargo.toml` (`nix/_lib.nix:72`, `:77`,
`:82`), so renaming the crate is a one-line change on the Rust side and needs no
Nix edit.

**Four package outputs** (`nix/packages.nix`):

| output | target | linkage | toolchain |
|---|---|---|---|
| `.#default` | native | dynamic (glibc) | stable |
| `.#static` | native musl | static | stable |
| `.#aarch64-dynamic` | `aarch64-unknown-linux-gnu` (cross) | dynamic | stable |
| `.#powerpc64le-static` | `powerpc64le-unknown-linux-musl` (cross) | static | nightly |

`static` picks its triple from the `muslTargets` map by host system;
`aarch64-dynamic` points the linker at `pkgsCross`'s cross-gcc;
`powerpc64le-static` links with `rust-lld` + self-contained crt and therefore
needs no sysroot. Those env vars are **target-scoped**
(`CARGO_TARGET_<TRIPLE>_…`), never a global `RUSTFLAGS` — a global one would
change the flags hash and invalidate the shared `cargoArtifacts` cache.

**The 8 checks** (`nix/checks.nix`): `build`, `fmt`, `clippy`
(`--all-targets -- --deny warnings`), `doc` (`RUSTDOCFLAGS=--deny warnings`),
`doctest` (nextest does *not* run doctests), `nextest`, `audit` (advisory DB
from the flake input, because the sandbox has no network), `deny` (`bans
licenses sources` only, for the same reason).

**Devshell / app.** `devShells.default` = the fenix toolchain plus
`cargo-nextest`, `cargo-deny`, `cargo-audit`, with the checks wired in.
`apps.default` is `lib.getExe self'.packages.default`, so `nix run .# -- <cmd>`
is the packaged binary.

## Error handling

Two layers, split along the crate boundary:

- `tally-core` exposes exactly one error type, `LibError`
  (`crates/tally-core/src/error.rs`), with leaves `ParseError` and
  `ValidationError`. The variants are parse / validation / io / graph-cycle /
  empty. Leaves are plain data (`Clone + Eq`) so tests can compare them;
  `LibError` is not, since it wraps `std::io::Error`.
- The CLI returns `miette::Result` and enables `fancy`. Library errors are
  converted once, at the boundary, via `IntoDiagnostic`, and handlers add
  context with `.wrap_err(...)` where it helps. The rendered output is a
  one-block diagnostic — e.g. for the cycle input,
  ``Error:   × dependency cycle involving component `b` `` — and the process
  exits non-zero.

This is why `thiserror` is in the library and `miette` is in the CLI: the
library describes *what failed*, the CLI decides *how to present it*.

## Each subcommand

| command | what it does | what it showcases | key file |
|---|---|---|---|
| `parse` | reads records and echoes them in canonical form | streaming grammar → validated model, `Display` round-trip | `crates/tally/src/commands/parse.rs` |
| `aggregate` | `--summary` counts per key (`--by component\|level`) or `--matrix` components × levels; optional `--threshold` | the typestate `Pipeline` + rayon engine + `ndarray` matrix | `crates/tally/src/commands/aggregate.rs` |
| `graph` | topological order, or `--scc` strongly connected components | petgraph + the `parent=` edge interpretation | `crates/tally/src/commands/graph.rs` |
| `convert` | parses, then re-encodes everything via `--format json\|yaml\|toml` | serde as the format seam | `crates/tally/src/commands/convert.rs` |
| `inspect` | shows the first record at or above `--threshold <PERCENT>`, with severity rank | `Percent` as a clap-validated newtype | `crates/tally/src/commands/inspect.rs` |

Shared plumbing: `crates/tally/src/commands/mod.rs` — `read_all` funnels both
`--stdin` and every `--files` entry through `BufferedReaderSource`, reads files
concurrently, then restores command-line order. `passes_threshold` lives there
too: the six levels are evenly spaced, so the test is `rank * 20 >= percent`.

Try it (from `templates/rust/`, inputs in `examples/`):

```bash
cargo run -p tally -- parse --files examples/basic.log
cargo run -p tally -- aggregate --files examples/basic.log --summary --by component
cargo run -p tally -- graph --files examples/dependencies.log
cargo run -p tally -- graph --files examples/cycle.log        # cycle -> miette error
cargo run -p tally -- convert --files examples/basic.log --format yaml
cargo run -p tally -- inspect --files examples/basic.log --threshold 85
```

## Build and test

```bash
cargo build                       # workspace
cargo test                        # unit + integration
cargo clippy --all-targets -- --deny warnings
cargo fmt --check
cargo xtest                       # alias: nextest run --workspace (.cargo/config.toml)
```

Nix side (docs-only changes do not need this, code changes do):

```bash
nix flake check                   # the 8 checks
nix build .#                      # native dynamic
nix build .#static                # static musl
nix run .# -- --help              # packaged binary
nix develop .#                    # toolchain + nextest/deny/audit
```

**Test strategy** — three tools, three jobs:

- `rstest` — table-driven fixtures/cases (many inputs, one assertion body).
- `proptest` — properties: `parse_line(&record.to_string()) == record`
  (round-trip) and `parser_never_panics_on_arbitrary_bytes` (no-panic on
  arbitrary bytes) in `crates/tally-core/tests/parser.rs`.
- `insta` — snapshots of the serde output, so a wire-format change is visible
  as a diff rather than a silent break.

Where they live: `crates/tally-core/tests/{parser,engine,graph,value}.rs` for
the library, `crates/tally/tests/{cli,serde,snapshots}.rs` for the CLI and the
serde trust boundary. Inline unit tests sit next to the code they test (e.g.
`numeric.rs` pins "parallel == sequential reference").

## Editing this template: the checks that bite

- **New `.rs` file → `git add -N` it** before anything Nix-side, or the flake's
  source filter will not see it (Nix ignores untracked files).
- **Keep `tally-core` free of presentation crates.** A new format or a new
  argument flag goes in `crates/tally`; the library gets a trait seam instead.
- **Adding a subcommand** is three touches: a variant in `Command`
  (`crates/tally/src/cli.rs`), an `Args` + `handle` pair in
  `crates/tally/src/commands/<name>.rs`, and one arm in `dispatch`
  (`commands/mod.rs`).
- **Changing the wire format** means touching the grammar, the `Display` impl
  and the round-trip property test together — the proptest will fail otherwise.
- **Renaming the crate** is `[workspace.metadata.package] name` in `Cargo.toml`
  plus the two crate directories; `pname`/`mainProgram` follow automatically.
