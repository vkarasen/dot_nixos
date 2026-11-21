//! Subcommand implementations.
//!
//! Every subcommand owns its argument struct and its handler side by side, so
//! adding a flag never means hunting through a second file. [`dispatch`] is the
//! only place that knows they exist.

pub mod aggregate;
pub mod convert;
pub mod graph;
pub mod inspect;
pub mod parse;

use miette::{IntoDiagnostic, Result};
use tally_core::grammar::LineParser;
use tally_core::{Level, Percent, Record};
use tokio::io::AsyncBufReadExt;

use crate::cli::{Cli, Command, InputGroup};

/// Run the parsed command line.
///
/// # Errors
///
/// Propagates whatever the selected handler reports.
pub async fn dispatch(cli: Cli) -> Result<()> {
    let common = cli.common;
    match cli.command {
        Command::Parse(args) => parse::handle(args, &common).await,
        Command::Aggregate(args) => aggregate::handle(args, &common).await,
        Command::Graph(args) => graph::handle(args, &common).await,
        Command::Convert(args) => convert::handle(args, &common).await,
        Command::Inspect(args) => inspect::handle(args, &common).await,
    }
}

/// Read every record described by `input`.
///
/// stdin is consumed line by line through [`LineParser`], which is the
/// streaming path; files are parsed concurrently on the tokio runtime and then
/// put back into command-line order so the output stays deterministic.
///
/// # Errors
///
/// Fails on unreadable files and on the first line that cannot parse.
pub(crate) async fn read_all(input: &InputGroup) -> Result<Vec<Record>> {
    if input.stdin {
        return read_stdin().await;
    }

    let mut tasks = tokio::task::JoinSet::new();
    for (index, path) in input.files.iter().cloned().enumerate() {
        tasks.spawn(async move {
            let records = read_file(&path).await?;
            Ok::<_, miette::Report>((index, records))
        });
    }

    let mut collected = Vec::with_capacity(input.files.len());
    while let Some(joined) = tasks.join_next().await {
        collected.push(joined.into_diagnostic()??);
    }
    collected.sort_by_key(|(index, _)| *index);

    Ok(collected
        .into_iter()
        .flat_map(|(_, records)| records)
        .collect())
}

async fn read_file(path: &std::path::Path) -> Result<Vec<Record>> {
    let file = tokio::fs::File::open(path).await.into_diagnostic()?;
    let reader = tokio::io::BufReader::new(file);
    let mut lines = reader.lines();
    let mut out = Vec::new();
    while let Some(line) = lines.next_line().await.into_diagnostic()? {
        if line.trim().is_empty() {
            continue;
        }
        out.push(tally_core::parse_line(&line).into_diagnostic()?);
    }
    Ok(out)
}

async fn read_stdin() -> Result<Vec<Record>> {
    let mut reader = tokio::io::BufReader::new(tokio::io::stdin());
    let mut parser = LineParser::new();
    let mut out = Vec::new();
    let mut line = String::new();
    loop {
        line.clear();
        let read = reader.read_line(&mut line).await.into_diagnostic()?;
        if read == 0 {
            break;
        }
        out.extend(parser.feed(&line).into_diagnostic()?);
    }
    out.extend(parser.finish().into_diagnostic()?);
    Ok(out)
}

/// Does `level` reach the `--threshold` percentage?
///
/// The six levels are evenly spaced over `0..=100`, so `TRACE` is `0` and
/// `FATAL` is `100`.
#[must_use]
pub(crate) fn passes_threshold(level: Level, threshold: Percent) -> bool {
    u16::from(level.rank()) * 20 >= u16::from(*threshold)
}
