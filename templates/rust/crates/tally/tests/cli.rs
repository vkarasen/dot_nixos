//! clap-level tests: the argument groups are the contract, so they get tested
//! through `try_parse_from` rather than by hand-constructing the structs.

use clap::error::ErrorKind;
use clap::Parser;
use tally::cli::{Cli, Command};

fn parse(argv: &[&str]) -> Result<Cli, clap::Error> {
    let mut full = vec!["tally"];
    full.extend_from_slice(argv);
    Cli::try_parse_from(full)
}

#[test]
fn accepts_stdin_input() {
    let cli = parse(&["parse", "--stdin"]).expect("valid");
    let Command::Parse(args) = cli.command else {
        panic!("expected the parse subcommand");
    };
    assert!(args.input.stdin);
    assert!(
        args.input.files.is_empty(),
        "stdin input must not carry files"
    );
}

#[test]
fn accepts_one_file() {
    let cli = parse(&["parse", "--files", "a.log"]).expect("valid");
    let Command::Parse(args) = cli.command else {
        panic!("expected the parse subcommand");
    };
    assert_eq!(args.input.files.len(), 1);
}

#[test]
fn accepts_several_files() {
    let cli = parse(&["parse", "--files", "a.log", "b.log", "c.log"]).expect("valid");
    let Command::Parse(args) = cli.command else {
        panic!("expected the parse subcommand");
    };
    assert_eq!(args.input.files.len(), 3);
}

#[test]
fn stdin_and_files_conflict() {
    let error = parse(&["parse", "--stdin", "--files", "a.log"]).expect_err("mutually exclusive");
    assert_eq!(error.kind(), ErrorKind::ArgumentConflict);
}

#[test]
fn input_is_required() {
    let error = parse(&["parse"]).expect_err("one input source is required");
    assert_eq!(error.kind(), ErrorKind::MissingRequiredArgument);
}

#[test]
fn files_needs_at_least_one_value() {
    let error = parse(&["parse", "--files"]).expect_err("needs a value");
    assert!(
        error.to_string().contains("--files"),
        "unexpected error: {error}"
    );
}

#[test]
fn summary_and_matrix_conflict() {
    let error =
        parse(&["aggregate", "--stdin", "--summary", "--matrix"]).expect_err("mutually exclusive");
    assert_eq!(error.kind(), ErrorKind::ArgumentConflict);
}

#[test]
fn aggregate_needs_a_mode() {
    let error = parse(&["aggregate", "--stdin"]).expect_err("a mode is required");
    assert_eq!(error.kind(), ErrorKind::MissingRequiredArgument);
}

#[test]
fn threshold_is_validated_by_the_newtype() {
    let ok = parse(&["aggregate", "--stdin", "--summary", "--threshold", "75"]).expect("in range");
    let Command::Aggregate(args) = ok.command else {
        panic!("expected the aggregate subcommand");
    };
    assert_eq!(args.threshold.map(|percent| *percent), Some(75));

    let error = parse(&["aggregate", "--stdin", "--summary", "--threshold", "101"])
        .expect_err("out of range");
    assert_eq!(error.kind(), ErrorKind::ValueValidation);
}

#[test]
fn global_flags_work_after_the_subcommand() {
    let cli = parse(&["parse", "--stdin", "-vv", "--format", "yaml"]).expect("valid");
    assert_eq!(cli.common.format, tally::formats::Format::Yaml);
}

#[test]
fn log_level_takes_a_tracing_level() {
    let cli = parse(&["parse", "--stdin", "-L", "debug"]).expect("valid");
    assert_eq!(
        cli.common.log_level.map(|level| level.to_string()),
        Some("debug".to_owned())
    );
}
