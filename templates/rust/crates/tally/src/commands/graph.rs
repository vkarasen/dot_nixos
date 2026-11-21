//! `tally graph` — dependency ordering and cycle detection.

use miette::{IntoDiagnostic, Result};
use tally_core::graph::{build_dependency_graph, strongly_connected, topological_order};
use tracing::info;

use crate::cli::{CommonArgs, InputGroup};
use crate::commands::read_all;
use crate::formats;

/// Arguments for `tally graph`.
#[derive(Debug, clap::Args)]
pub struct Args {
    /// Where the records come from.
    #[command(flatten)]
    pub input: InputGroup,

    /// Report strongly connected components instead of a topological order.
    #[arg(long)]
    pub scc: bool,
}

/// Build the dependency graph and report on it.
///
/// # Errors
///
/// Fails on unreadable input, a malformed line, a dependency cycle (unless
/// `--scc` is given, which *reports* cycles instead), or a serialisation error.
pub async fn handle(args: Args, common: &CommonArgs) -> Result<()> {
    info!(target: "cli", command = "graph", scc = args.scc, "analysing dependencies");
    let records = read_all(&args.input).await?;
    let graph = build_dependency_graph(&records);
    info!(
        target: "cli",
        nodes = graph.node_count(),
        edges = graph.edge_count(),
        "graph built"
    );

    let rendered = if args.scc {
        let groups: Vec<Vec<String>> = strongly_connected(&graph)
            .into_iter()
            .map(|group| group.into_iter().map(|name| name.to_string()).collect())
            .collect();
        info!(target: "cli", components = groups.len(), "strongly connected components");
        formats::encode(common.format, &groups)?
    } else {
        let order = topological_order(&graph).into_diagnostic()?;
        let names: Vec<String> = order.into_iter().map(|name| name.to_string()).collect();
        formats::encode(common.format, &names)?
    };

    println!("{rendered}");
    Ok(())
}
