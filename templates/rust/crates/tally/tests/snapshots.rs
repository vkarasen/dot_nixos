//! Encoding snapshots: one fixture, three formats.
//!
//! `insta` records the exact bytes so an accidental change to a field name, a
//! number format or the YAML prologue is a review-visible diff rather than a
//! silent behaviour change.

use tally::formats::{self, Format};
use tally_core::grammar::parse_line;
use tally_core::{Percent, Record};

fn fixture() -> Vec<Record> {
    [
        "1700000000000 INFO engine parent=scheduler latency_ms=12",
        "1700000000001 WARN scheduler retries=3",
        "1700000000002 FATAL db disk=full",
    ]
    .into_iter()
    .map(|line| parse_line(line).expect("valid fixture"))
    .collect()
}

#[test]
fn json_encoding() {
    insta::assert_json_snapshot!(fixture());
}

#[test]
fn yaml_encoding() {
    insta::assert_yaml_snapshot!(fixture());
}

#[test]
fn toml_encoding() {
    // TOML cannot represent a top-level array, so the records are wrapped.
    insta::assert_toml_snapshot!(toml_document());
}

/// The TOML view: `[[records]]` tables.
#[derive(Debug, serde::Serialize, serde::Deserialize)]
struct Document {
    /// The records, in input order.
    records: Vec<Record>,
}

fn toml_document() -> Document {
    Document { records: fixture() }
}

#[test]
fn formats_round_trip_through_the_encoder() {
    // TOML requires a table at the top level, so every format round-trips the
    // same wrapper — which is also why `encodings` above snapshots `Document`.
    let document = toml_document();
    for format in [Format::Json, Format::Yaml, Format::Toml] {
        let encoded = formats::encode(format, &document).expect("encodable");
        let decoded: Document = formats::decode(format, &encoded).expect("decodable");
        assert_eq!(decoded.records, document.records, "{format:?} lost data");
    }
}

#[test]
fn the_newtype_validator_survives_deserialisation() {
    assert!(serde_json::from_str::<Percent>("42").is_ok());
    assert!(serde_json::from_str::<Percent>("420").is_err());
    assert_eq!(
        formats::to_json(&Percent::try_new(75).unwrap()).unwrap(),
        "75"
    );
}
