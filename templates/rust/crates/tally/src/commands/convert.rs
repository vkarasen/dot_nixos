//! `tally convert` — rewrite the input in another encoding.

use miette::Result;
use tracing::info;

use crate::cli::{CommonArgs, InputGroup};
use crate::commands::read_all;
use crate::formats;

/// Arguments for `tally convert`.
#[derive(Debug, clap::Args)]
pub struct Args {
    /// Where the records come from.
    #[command(flatten)]
    pub input: InputGroup,
}

/// Parse the input and emit the whole `Vec<Record>` in the requested format.
///
/// # Errors
///
/// Fails on unreadable input, a malformed line, or a serialisation error.
pub async fn handle(args: Args, common: &CommonArgs) -> Result<()> {
    info!(target: "cli", command = "convert", format = ?common.format, "converting");
    let records = read_all(&args.input).await?;
    let rendered = formats::encode(common.format, &records)?;
    println!("{rendered}");
    Ok(())
}
