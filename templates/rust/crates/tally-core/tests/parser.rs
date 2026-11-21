//! Parser tests: table-driven cases, a streaming contract, and two properties
//! (round-trip and never-panic).

use proptest::prelude::*;
use rstest::rstest;
use tally_core::grammar::{parse_line, LineParser};
use tally_core::{Component, Level, LibError, Record};

/// A shared fixture: three records with overlapping components.
#[rstest::fixture]
fn records() -> Vec<Record> {
    [
        "1700000000000 INFO engine parent=scheduler latency_ms=12",
        "1700000000001 WARN scheduler",
        "1700000000002 INFO engine",
    ]
    .into_iter()
    .map(|line| parse_line(line).expect("fixture lines are valid"))
    .collect()
}

#[rstest]
#[case("1700000000000 INFO engine", Level::Info, "engine")]
#[case("0 TRACE tiny", Level::Trace, "tiny")]
#[case("42 debug mixed-case", Level::Debug, "mixed-case")]
#[case("  43    warn   spaced   ", Level::Warn, "spaced")]
#[case("9 FATAL boom crash_code=42", Level::Fatal, "boom")]
fn parses_valid_lines(#[case] line: &str, #[case] level: Level, #[case] component: &str) {
    let record = parse_line(line).expect("valid line");
    assert_eq!(record.level, level);
    assert_eq!(record.component, Component::try_new(component).unwrap());
}

#[rstest]
#[case("")]
#[case("   ")]
#[case("not-a-timestamp INFO engine")]
#[case("1700000000000 INFO")]
#[case("1700000000000 INFO engine key")]
#[case("1700000000000 INFO engine Key=1")]
#[case("1700000000000 INFO engine k=")]
#[case("1700000000000 INFO engine k=1 k=2")]
#[case("1700000000000 SILLY engine")]
#[case("1700000000000 INFO engine\n1700000000001 INFO other")]
fn rejects_invalid_lines(#[case] line: &str) {
    let error = parse_line(line).expect_err("must not parse");
    assert!(
        error.is_parse_error() || matches!(error, LibError::Validation(_)),
        "unexpected error: {error:?}"
    );
}

#[rstest]
fn attrs_end_up_in_a_sorted_map(records: Vec<Record>) {
    let first = &records[0];
    assert_eq!(first.parent(), Some("scheduler"));
    assert_eq!(
        first.attrs.get("latency_ms").map(String::as_str),
        Some("12")
    );
    assert_eq!(first.ts_ms, 1_700_000_000_000);
}

#[rstest]
fn streaming_reassembles_across_chunk_boundaries(records: Vec<Record>) {
    let mut text = String::new();
    for record in &records {
        text.push_str(&record.to_string());
        text.push('\n');
    }
    let mut parser = LineParser::new();
    let mut out = Vec::new();
    // One byte at a time: every token boundary is crossed mid-chunk.
    for byte in text.as_bytes() {
        let chunk = std::str::from_utf8(std::slice::from_ref(byte)).expect("ascii");
        out.extend(parser.feed(chunk).expect("no syntax errors"));
    }
    out.extend(parser.finish().expect("stream ended cleanly"));
    assert_eq!(out, records);
}

#[rstest]
fn finish_rejects_a_truncated_tail() {
    let mut parser = LineParser::new();
    let complete = parser
        .feed("1700000000000 INFO engine\n")
        .expect("complete line");
    assert_eq!(complete.len(), 1);
    assert_eq!(parser.buffered(), "");
    parser
        .feed("1700000000001 INFO eng")
        .expect("partial line is buffered");
    let error = parser.finish().expect_err("truncated tail must fail");
    assert!(error.is_parse_error(), "unexpected error: {error:?}");
}

fn level_strategy() -> impl Strategy<Value = Level> {
    prop_oneof![
        Just(Level::Trace),
        Just(Level::Debug),
        Just(Level::Info),
        Just(Level::Warn),
        Just(Level::Error),
        Just(Level::Fatal),
    ]
}

prop_compose! {
    /// Arbitrary but *renderable* records: every field can survive a trip
    /// through the wire format.
    fn record_strategy()(
        ts_ms in any::<u64>(),
        level in level_strategy(),
        name in "[a-z][a-z0-9]{0,7}",
        attrs in proptest::collection::btree_map("[a-z][a-z0-9_]{0,7}", "[a-zA-Z0-9_.=:-]{1,8}", 0..4),
    ) -> Record {
        Record::builder()
            .ts_ms(ts_ms)
            .level(level)
            .component(Component::try_new(name).expect("strategy cannot produce empty"))
            .attrs(attrs)
            .build()
    }
}

proptest! {
    #![proptest_config(ProptestConfig { cases: 96, ..ProptestConfig::default() })]

    #[test]
    fn render_parse_round_trip(record in record_strategy()) {
        let rendered = record.to_string();
        let parsed = parse_line(&rendered).expect("rendered records always parse");
        prop_assert_eq!(parsed, record);
    }

    #[test]
    fn parser_never_panics_on_arbitrary_text(text in any::<String>()) {
        let _ = parse_line(&text);
        let mut parser = LineParser::new();
        let _ = parser.feed(&text);
        let _ = parser.finish();
    }

    #[test]
    fn parser_never_panics_on_arbitrary_bytes(bytes in proptest::collection::vec(any::<u8>(), 0..64)) {
        // Bytes are only interesting if they are valid UTF-8; the point of the
        // property is that the *parser* is total, not that the converter is.
        if let Ok(text) = std::str::from_utf8(&bytes) {
            let _ = parse_line(text);
        }
    }
}
