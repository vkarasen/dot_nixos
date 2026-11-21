//! Dependency-graph tests: ordering, cycle detection and SCCs.

use tally_core::grammar::parse_line;
use tally_core::graph::{build_dependency_graph, strongly_connected, topological_order};
use tally_core::LibError;
use tally_core::Record;

fn parse_all(lines: &[&str]) -> Vec<Record> {
    lines
        .iter()
        .map(|line| parse_line(line).expect("valid fixture"))
        .collect()
}

#[test]
fn topological_order_puts_parents_first() {
    let records = parse_all(&[
        "1 INFO db",
        "2 INFO cache parent=db",
        "3 INFO api parent=cache",
        "4 INFO web parent=api",
    ]);

    let graph = build_dependency_graph(&records);
    let order = topological_order(&graph).expect("acyclic");

    let position = |name: &str| {
        order
            .iter()
            .position(|component| component.as_ref() == name)
            .unwrap_or_else(|| panic!("{name} missing from {order:?}"))
    };
    assert!(position("db") < position("cache"));
    assert!(position("cache") < position("api"));
    assert!(position("api") < position("web"));
    assert_eq!(order.len(), 4);
}

#[test]
fn a_cycle_is_reported_with_a_culprit() {
    let records = parse_all(&[
        "1 INFO a parent=c",
        "2 INFO b parent=a",
        "3 INFO c parent=b",
    ]);

    let graph = build_dependency_graph(&records);
    let error = topological_order(&graph).expect_err("cycle must be detected");
    let LibError::GraphCycle { component } = &error else {
        panic!("expected a graph cycle, got {error:?}");
    };
    assert!(["a", "b", "c"].contains(&component.as_str()));
}

#[test]
fn strongly_connected_groups_a_cycle() {
    let records = parse_all(&[
        "1 INFO a parent=c",
        "2 INFO b parent=a",
        "3 INFO c parent=b",
        "4 INFO lonely",
    ]);

    let groups = strongly_connected(&build_dependency_graph(&records));
    let cycle = groups
        .iter()
        .find(|group| group.len() == 3)
        .expect("the three-component cycle is one SCC");
    let mut names: Vec<&str> = cycle.iter().map(AsRef::as_ref).collect();
    names.sort_unstable();
    assert_eq!(names, ["a", "b", "c"]);
    assert!(groups.iter().any(|group| group.len() == 1));
}

#[test]
fn isolated_components_still_get_nodes() {
    let records = parse_all(&["1 INFO solo"]);
    let graph = build_dependency_graph(&records);
    assert_eq!(graph.node_count(), 1);
    assert_eq!(graph.edge_count(), 0);
    assert_eq!(topological_order(&graph).expect("acyclic").len(), 1);
}
