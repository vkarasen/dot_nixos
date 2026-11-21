//! `tally aggregate` — count records as a summary or a matrix.

use miette::Result;
use serde::Serialize;
use tally_core::build::{Key, Pipeline};
use tally_core::numeric::count_matrix;
use tally_core::{Level, Percent, Record};
use tracing::info;

use crate::cli::{CommonArgs, InputGroup, ModeGroup};
use crate::commands::{passes_threshold, read_all};
use crate::formats;

/// Arguments for `tally aggregate`.
#[derive(Debug, clap::Args)]
pub struct Args {
    /// Where the records come from.
    #[command(flatten)]
    pub input: InputGroup,

    /// Summary or matrix.
    #[command(flatten)]
    pub mode: ModeGroup,

    /// Attribute to group by.
    #[arg(long, value_enum, default_value = "component")]
    pub by: GroupBy,

    /// Keep only records at or above this severity percentage (`0..=100`).
    #[arg(long, value_name = "PERCENT")]
    pub threshold: Option<Percent>,
}

/// The `--by` choices.
#[derive(Debug, Clone, Copy, PartialEq, Eq, clap::ValueEnum)]
pub enum GroupBy {
    /// Group by component name.
    Component,
    /// Group by severity.
    Level,
}

impl From<GroupBy> for Key {
    fn from(value: GroupBy) -> Self {
        match value {
            GroupBy::Component => Self::Component,
            GroupBy::Level => Self::Level,
        }
    }
}

/// A matrix encoded together with its axes, so the output is self-describing.
#[derive(Debug, Serialize)]
struct Matrix {
    /// Row labels, sorted.
    components: Vec<String>,
    /// Column labels, in [`Level::ALL`] order.
    levels: Vec<&'static str>,
    /// `counts[row][column]`.
    counts: Vec<Vec<u64>>,
}

/// Aggregate the input.
///
/// # Errors
///
/// Fails on unreadable input, a malformed line, or a serialisation error.
pub async fn handle(args: Args, common: &CommonArgs) -> Result<()> {
    info!(
        target: "cli",
        command = "aggregate",
        matrix = args.mode.matrix,
        by = ?args.by,
        "aggregating"
    );

    let mut records = read_all(&args.input).await?;
    if let Some(threshold) = args.threshold {
        records.retain(|record| passes_threshold(record.level, threshold));
        info!(target: "cli", kept = records.len(), "threshold applied");
    }

    let rendered = if args.mode.matrix {
        formats::encode(common.format, &matrix_of(&records))?
    } else {
        // Drive the typestate machine: `Parsed -> Aggregated -> emit`.
        let pipeline = Pipeline::new(records).group_by(args.by.into()).aggregate();
        info!(target: "cli", groups = pipeline.emit().len(), "summary built");
        formats::encode(common.format, pipeline.emit())?
    };

    println!("{rendered}");
    Ok(())
}

/// Wrap [`count_matrix`] together with its row/column labels.
fn matrix_of(records: &[Record]) -> Matrix {
    let mut names: Vec<String> = records
        .iter()
        .map(|record| record.component.to_string())
        .collect();
    names.sort();
    names.dedup();

    let array = count_matrix(records);
    let counts = (0..array.nrows())
        .map(|row| (0..array.ncols()).map(|col| array[[row, col]]).collect())
        .collect();

    Matrix {
        components: names,
        levels: Level::ALL.iter().map(|level| level.as_str()).collect(),
        counts,
    }
}
