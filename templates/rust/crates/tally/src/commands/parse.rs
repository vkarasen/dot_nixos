//! `tally parse` — read records and echo them in canonical form.

use miette::Result;
use tracing::info;

use crate::cli::{CommonArgs, InputGroup};
use crate::commands::read_all;

/// Arguments for `tally parse`.
#[derive(Debug, clap::Args)]
pub struct Args {
    /// Where the records come from.
    #[command(flatten)]
    pub input: InputGroup,
}

/// Parse every input and print one canonical line per record.
///
/// # Errors
///
/// Fails on unreadable input or a malformed line.
pub async fn handle(args: Args, _common: &CommonArgs) -> Result<()> {
    info!(target: "cli", command = "parse", "parsing records");
    let records = read_all(&args.input).await?;
    info!(target: "cli", count = records.len(), "parsed records");

    for record in &records {
        println!("{record}");
    }
    Ok(())
}
