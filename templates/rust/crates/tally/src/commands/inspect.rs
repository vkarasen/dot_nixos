//! `tally inspect` — look at a single record in detail.

use miette::Result;
use tally_core::{Level, Percent};
use tracing::info;

use crate::cli::{CommonArgs, InputGroup};
use crate::commands::{passes_threshold, read_all};
use crate::formats;

/// Arguments for `tally inspect`.
#[derive(Debug, clap::Args)]
pub struct Args {
    /// Where the records come from.
    #[command(flatten)]
    pub input: InputGroup,

    /// Only consider records at or above this severity percentage.
    #[arg(long, value_name = "PERCENT")]
    pub threshold: Option<Percent>,
}

/// Show the first record that survives the threshold.
///
/// # Errors
///
/// Fails on unreadable input, a malformed line, an empty selection, or a
/// serialisation error.
pub async fn handle(args: Args, common: &CommonArgs) -> Result<()> {
    info!(target: "cli", command = "inspect", "inspecting");
    let records = read_all(&args.input).await?;

    let threshold = args.threshold;
    let first = records
        .into_iter()
        .find(|record| threshold.is_none_or(|percent| passes_threshold(record.level, percent)))
        .ok_or_else(|| miette::miette!("no record at or above the requested threshold"))?;

    println!("{} ({} attributes)", first, first.attrs.len());
    println!("severity rank: {}/{}", first.level.rank(), Level::COUNT - 1);
    println!("{}", formats::encode(common.format, &first)?);
    Ok(())
}
