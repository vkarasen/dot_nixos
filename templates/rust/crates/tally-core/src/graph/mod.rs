//! Dependency analysis over [`petgraph`].
//!
//! Every record may carry the reserved `parent=<component>` attribute, which is
//! read as "this component depends on `parent`". Edges therefore point
//! `parent -> child`: running a topological sort yields the order in which
//! components must be brought up.
//!
//! Note that `petgraph`'s algorithms are trait-generic over the graph type
//! (`IntoNeighborsDirected + IntoNodeIdentifiers + Visitable`, …), which is why
//! these helpers take `&DiGraph<..>` rather than a concrete owned value — they
//! would work just as well on a `StableDiGraph`.

use std::collections::HashMap;

use petgraph::algo::{tarjan_scc, toposort};
use petgraph::graph::{DiGraph, NodeIndex};

use crate::error::LibError;
use crate::model::{Component, Record};

/// A component dependency graph: `parent -> child`.
pub type DependencyGraph = DiGraph<Component, ()>;

fn node_id(
    graph: &mut DependencyGraph,
    index: &mut HashMap<Component, NodeIndex>,
    name: &Component,
) -> NodeIndex {
    if let Some(existing) = index.get(name) {
        *existing
    } else {
        let id = graph.add_node(name.clone());
        index.insert(name.clone(), id);
        id
    }
}

/// Build the dependency graph described by `records`.
///
/// Components that never appear as a `parent` still get a node, so isolated
/// components show up in the topological order.
#[must_use]
pub fn build_dependency_graph(records: &[Record]) -> DependencyGraph {
    let mut graph = DependencyGraph::new();
    let mut index = HashMap::new();

    for record in records {
        let child = node_id(&mut graph, &mut index, &record.component);
        // Edition 2021: no let-chains, so the two steps stay separate.
        if let Some(name) = record.parent() {
            if let Ok(parent) = Component::try_new(name) {
                let parent = node_id(&mut graph, &mut index, &parent);
                if parent != child {
                    graph.add_edge(parent, child, ());
                }
            }
        }
    }

    graph
}

/// Order components so every dependency comes before its dependents.
///
/// # Errors
///
/// Returns [`LibError::GraphCycle`] when the graph is cyclic. The error names
/// one component that participates in the cycle.
pub fn topological_order(graph: &DependencyGraph) -> Result<Vec<Component>, LibError> {
    let order = toposort(graph, None).map_err(|cycle| LibError::GraphCycle {
        component: graph[cycle.node_id()].to_string(),
    })?;
    Ok(order
        .into_iter()
        .map(|id| graph[id].clone())
        .collect::<Vec<_>>())
}

/// Strongly connected components, largest first.
///
/// Any group with more than one member is a dependency cycle; a singleton is
/// just a node. `tarjan_scc` returns them in reverse topological order.
#[must_use]
pub fn strongly_connected(graph: &DependencyGraph) -> Vec<Vec<Component>> {
    tarjan_scc(graph)
        .into_iter()
        .map(|group| group.into_iter().map(|id| graph[id].clone()).collect())
        .collect()
}
