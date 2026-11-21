//! Merge laws and the parallel/sequential equivalence of `engine::aggregate`.

use std::collections::HashMap;

use proptest::prelude::*;
use rstest::rstest;
use tally_core::build::{count_by, Key, Pipeline};
use tally_core::engine::{aggregate, Combine};
use tally_core::grammar::parse_line;
use tally_core::{Level, Record};

fn sample() -> Vec<Record> {
    [
        "1 INFO engine",
        "2 INFO scheduler",
        "3 WARN engine",
        "4 ERROR scheduler",
        "5 INFO engine",
        "6 FATAL db",
    ]
    .into_iter()
    .map(|line| parse_line(line).expect("valid fixture"))
    .collect()
}

#[test]
fn assignment_is_the_identity() {
    for value in [0u64, 1, u64::MAX] {
        assert_eq!(value.combine(u64::neutral()), value);
        assert_eq!(u64::neutral().combine(value), value);
    }
}

proptest! {
    #![proptest_config(ProptestConfig { cases: 128, ..ProptestConfig::default() })]

    #[test]
    fn addition_is_associative_and_commutative(a in any::<u64>(), b in any::<u64>(), c in any::<u64>()) {
        prop_assert_eq!((a.combine(b)).combine(c), a.combine(b.combine(c)));
        prop_assert_eq!(a.combine(b), b.combine(a));
    }
}

#[rstest]
#[case("engine", 2u64)]
#[case("scheduler", 1)]
#[case("db", 1)]
fn map_combine_merges_counts(#[case] component: &str, #[case] expected: u64) {
    let mut left = HashMap::new();
    left.insert(component.to_owned(), expected);
    let merged = left.clone().combine(left);
    assert_eq!(
        merged.get(component),
        Some(&(expected.saturating_add(expected)))
    );
    assert_eq!(HashMap::<String, u64>::neutral(), HashMap::new());
}

#[test]
fn aggregate_matches_a_sequential_reference() {
    let records = sample();
    let parallel = aggregate(&records, |record| (record.component.to_string(), 1u64));

    let mut sequential: HashMap<String, u64> = HashMap::new();
    for record in &records {
        *sequential
            .entry(record.component.to_string())
            .or_insert(0u64) += 1;
    }

    assert_eq!(parallel, sequential);
}

#[test]
fn function_builder_and_typestate_agree() {
    let records = sample();

    let built = count_by().records(&records).key(Key::Level).call();
    let pipelined = Pipeline::new(records.clone())
        .group_by(Key::Level)
        .aggregate();

    assert_eq!(built.len(), pipelined.emit().len());
    assert_eq!(built.get("INFO"), Some(&3));
    assert_eq!(pipelined.emit().get("INFO"), Some(&3));
    assert_eq!(pipelined.key(), Key::Level);
    assert_eq!(pipelined.records().len(), records.len());
    assert!(Level::ALL
        .iter()
        .all(|level| level.as_str() == level.to_string()));
}
