//! Deserialisation is a *trust boundary*: the wire format is JSON/YAML/TOML
//! input from elsewhere, so the same invariants the grammar enforces must hold
//! for anything that arrives through serde.
//!
//! These tests live in the `tally` crate only because they need `serde_json`;
//! the types themselves are `tally-core`'s.

use tally_core::{Component, Level, Record};

fn record_json(component: &str, attrs: &str) -> String {
    format!(r#"{{"ts_ms":1,"level":"info","component":"{component}","attrs":{attrs}}}"#)
}

#[test]
fn a_well_formed_record_deserialises() {
    let record: Record =
        serde_json::from_str(&record_json("engine", r#"{"latency_ms":"12"}"#)).expect("valid");
    assert_eq!(record.component.as_ref(), "engine");
    assert_eq!(record.attrs.len(), 1);
}

#[test]
fn a_component_containing_whitespace_is_rejected() {
    // The grammar can never produce this, and neither may JSON.
    let error = serde_json::from_str::<Record>(&record_json("with space", "{}"))
        .expect_err("whitespace in a component must fail");
    assert!(
        error.to_string().to_lowercase().contains("component"),
        "{error}"
    );
}

#[test]
fn an_empty_component_is_rejected() {
    assert!(serde_json::from_str::<Record>(&record_json("", "{}")).is_err());
}

#[test]
fn an_invalid_attribute_key_is_rejected() {
    for attrs in [
        r#"{"Latency":"12"}"#,  // upper case
        r#"{"9lives":"1"}"#,    // must start with a letter
        r#"{"has-dash":"1"}"#,  // '-' is not in [a-z0-9_]
        r#"{"has space":"1"}"#, // whitespace
    ] {
        let json = record_json("engine", attrs);
        assert!(
            serde_json::from_str::<Record>(&json).is_err(),
            "key in {attrs} should have been rejected"
        );
    }
}

#[test]
fn an_invalid_attribute_value_is_rejected() {
    for attrs in [r#"{"k":""}"#, r#"{"k":"two words"}"#] {
        let json = record_json("engine", attrs);
        assert!(
            serde_json::from_str::<Record>(&json).is_err(),
            "value in {attrs} should have been rejected"
        );
    }
}

#[test]
fn level_deserialises_in_any_case() {
    for spelling in ["info", "Info", "INFO"] {
        let json = record_json("engine", "{}").replace("\"info\"", &format!("\"{spelling}\""));
        let record: Record = serde_json::from_str(&json).expect("case-insensitive");
        assert_eq!(record.level, Level::Info, "{spelling} did not parse");
    }
    assert!(
        serde_json::from_str::<Record>(&record_json("engine", "{}").replace("info", "loud"))
            .is_err()
    );
}

#[test]
fn component_rejects_whitespace_at_the_type_level() {
    assert!(Component::try_new("with space").is_err());
    assert!(Component::try_new("").is_err());
    assert!(Component::try_new("engine").is_ok());
}
