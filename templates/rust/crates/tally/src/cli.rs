//! Command-line surface: global flags, the input group, and the subcommands.
//!
//! Two things here are worth pointing at:
//!
//! * [`InputGroup`] and [`ModeGroup`] are `#[derive(Args)]` structs with a
//!   `#[group(..)]` attribute. clap turns the struct into an [`ArgGroup`], so
//!   the "exactly one of these" constraint is declared once and reused by every
//!   subcommand that flattens it.
//! * `--threshold` is typed as `Percent`, a `nutype` newtype. clap validates
//!   it through the type's `FromStr`, so an out-of-range percentage is a
//!   parse-time usage error and cannot reach the handlers at all.
//!
//! [`ArgGroup`]: clap::ArgGroup

use std::path::PathBuf;

use clap::{Args, Parser, Subcommand};
use clap_verbosity_flag::Verbosity;
use tracing::level_filters::LevelFilter;

use crate::formats::Format;

/// Global options accepted before *and* after the subcommand.
#[derive(Debug, Args)]
pub struct CommonArgs {
    /// `-v/-vv/-vvv` (and `-q`): how loud the logger is.
    #[command(flatten)]
    pub verbosity: Verbosity,

    /// Hard log level, e.g. `debug`. Takes precedence over `-v`, and
    /// `RUST_LOG` still applies as a fallback.
    #[arg(short = 'L', long, global = true, value_name = "LEVEL", value_parser = parse_level)]
    pub log_level: Option<LevelFilter>,

    /// Multi-line, colourised log output.
    #[arg(long, global = true)]
    pub pretty: bool,

    /// Encoding for structured output.
    #[arg(long, global = true, value_enum, default_value = "json")]
    pub format: Format,
}

/// Parse a [`LevelFilter`] as a clap value.
fn parse_level(raw: &str) -> Result<LevelFilter, String> {
    raw.parse::<LevelFilter>().map_err(|err| err.to_string())
}

/// Where the records come from: stdin or a list of files, never both.
#[derive(Debug, Args)]
#[group(required = true, multiple = false)]
pub struct InputGroup {
    /// Read records from standard input.
    #[arg(long)]
    pub stdin: bool,

    /// Read records from one or more files.
    #[arg(long, value_name = "FILE", num_args = 1..)]
    pub files: Vec<PathBuf>,
}

/// Choose exactly one aggregation shape.
#[derive(Debug, Args)]
#[group(required = true, multiple = false)]
pub struct ModeGroup {
    /// One count per group key.
    #[arg(long)]
    pub summary: bool,

    /// A components × levels count matrix.
    #[arg(long)]
    pub matrix: bool,
}

/// `tally` — parse, aggregate and analyse structured log lines.
#[derive(Debug, Parser)]
#[command(name = "tally", version, about)]
pub struct Cli {
    /// Options that apply to every subcommand.
    #[command(flatten)]
    pub common: CommonArgs,

    /// What to do.
    #[command(subcommand)]
    pub command: Command,
}

/// The available subcommands.
#[derive(Debug, Subcommand)]
pub enum Command {
    /// Parse records and echo them in canonical form.
    Parse(crate::commands::parse::Args),
    /// Count records, as a summary or a matrix.
    Aggregate(crate::commands::aggregate::Args),
    /// Analyse the component dependency graph.
    Graph(crate::commands::graph::Args),
    /// Convert records to another encoding.
    Convert(crate::commands::convert::Args),
    /// Show the first record that passes the threshold.
    Inspect(crate::commands::inspect::Args),
}
