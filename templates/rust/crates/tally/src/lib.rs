//! `tally` — the CLI layer, exposed as a library so the argument grammar and
//! the formatters can be tested in-process.
//!
//! * [`cli`] — the `clap` surface: global flags, the shared `InputGroup` /
//!   `ModeGroup`, and the subcommand enum.
//! * [`commands`] — one module per subcommand, arguments next to handler.
//! * [`formats`] — JSON / YAML / TOML behind a single [`formats::Format`].
//!
//! Logging lives here too ([`init_logging`]) because the *binary* is a thin
//! wrapper: `tally-core` only ever links `tracing`, and the subscriber is
//! installed once, by the process entry point.

#![warn(missing_docs)]

pub mod cli;
pub mod commands;
pub mod formats;

use tracing_subscriber::filter::EnvFilter;

use crate::cli::CommonArgs;

/// Install the global `tracing` subscriber.
///
/// * `-v/-vv/-vvv` becomes a `max_level` filter;
/// * `-L <LEVEL>` overrides it with an [`EnvFilter`] whose *default* directive
///   is that level — so `RUST_LOG` still wins when it is set;
/// * `--pretty` switches to the multi-line, colourised formatter.
///
/// # Panics
///
/// Panics if a global subscriber is already installed; the binary calls this
/// exactly once.
pub fn init_logging(common: &CommonArgs) {
    let builder = tracing_subscriber::fmt()
        .with_writer(std::io::stderr)
        .with_target(true);

    if let Some(level) = common.log_level {
        let filter = EnvFilter::builder()
            .with_default_directive(level.into())
            .from_env_lossy();
        if common.pretty {
            builder.pretty().with_env_filter(filter).init();
        } else {
            builder.compact().with_env_filter(filter).init();
        }
    } else {
        let verbosity = common.verbosity;
        if common.pretty {
            builder.pretty().with_max_level(verbosity).init();
        } else {
            builder.compact().with_max_level(verbosity).init();
        }
    }
}
