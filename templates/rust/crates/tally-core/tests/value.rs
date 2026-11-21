//! `nutype` tests: the invariants are enforced by every entry point, including
//! serde deserialisation and `FromStr`.

use rstest::rstest;
use tally_core::{Component, Percent};

#[rstest]
#[case("engine")]
#[case("a")]
#[case("with-dash")]
#[case("uppercase_OK")]
fn components_accept_any_non_empty_token(#[case] raw: &str) {
    let component = Component::try_new(raw).expect("non-empty");
    assert_eq!(component.as_ref(), raw);
    assert_eq!(component.to_string(), raw);
}

#[test]
fn components_reject_the_empty_string() {
    assert!(Component::try_new("").is_err());
    assert!("".parse::<Component>().is_err());
}

#[rstest]
#[case(0u8)]
#[case(50)]
#[case(100)]
fn percent_accepts_the_closed_range(#[case] raw: u8) {
    let percent = Percent::try_new(raw).expect("in range");
    assert_eq!(*percent, raw);
    assert_eq!(
        raw.to_string().parse::<Percent>().expect("in range"),
        percent
    );
}

#[rstest]
#[case(101u8)]
#[case(255)]
fn percent_rejects_out_of_range(#[case] raw: u8) {
    assert!(Percent::try_new(raw).is_err());
    assert!(raw.to_string().parse::<Percent>().is_err());
}

#[test]
fn percent_rejects_negative_parse() {
    // `FromStr` goes through the same validator as `try_new`.
    assert!("-1".parse::<Percent>().is_err());
    assert!("abc".parse::<Percent>().is_err());
}
