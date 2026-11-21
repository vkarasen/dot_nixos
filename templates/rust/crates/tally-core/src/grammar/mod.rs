//! The wire grammar, written with [`winnow`].
//!
//! One record per line:
//!
//! ```text
//! <ts_ms> <LEVEL> <component> [key=value ...]
//! ```
//!
//! # How winnow and serde meet
//!
//! The two ecosystem halves are deliberately kept apart:
//!
//! * **winnow** owns *syntax*. [`raw_line`] recognises the shape of a line and
//!   hands back borrowed slices plus a `Vec` of key/value pairs — no
//!   allocation, no validation.
//! * **serde** owns the *data model*. [`Record`] derives `Serialize` /
//!   `Deserialize`, and the `nutype` newtypes inside it re-run their
//!   validators when deserialised.
//!
//! The bridge is [`RawLine::into_record`]: it is the only place where borrowed
//! syntax turns into owned domain values, and it is the only place that can
//! produce a [`LibError::Validation`]. Nothing downstream re-checks the shape.
//!
//! # Streaming
//!
//! [`raw_line`] is written against [`Partial<&str>`], so winnow reports
//! [`ErrMode::Incomplete`] whenever the buffer might still grow mid-token.
//! [`LineParser`] uses exactly that signal to decide between "buffer more" and
//! "this record is complete". Only [`LineParser::finish`] treats a leftover
//! partial line as an error.

use std::collections::BTreeMap;

use winnow::ascii::{alpha1, digit1, line_ending};
use winnow::combinator::preceded;
use winnow::error::ErrMode;
use winnow::prelude::*;
use winnow::stream::Partial;
use winnow::token::{literal, one_of, take_while};

use crate::error::{LibError, ParseError, ValidationError};
use crate::model::{Component, Level, Record};

/// The winnow input type: a `&str` that may still be appended to.
type LineInput<'i> = Partial<&'i str>;

/// Horizontal whitespace only — `space1` would happily eat the newline that
/// terminates the record and merge two lines into one.
fn hspace(c: char) -> bool {
    c == ' ' || c == '\t'
}

fn space<'i>(input: &mut LineInput<'i>) -> ModalResult<&'i str> {
    take_while(1.., hspace).parse_next(input)
}

/// A key starts with `[a-z]` and continues with `[a-z0-9_]`.
fn attr_key<'i>(input: &mut LineInput<'i>) -> ModalResult<&'i str> {
    let tail = |c: char| c.is_ascii_lowercase() || c.is_ascii_digit() || c == '_';
    (one_of('a'..='z'), take_while(0.., tail))
        .take()
        .parse_next(input)
}

fn attr_value<'i>(input: &mut LineInput<'i>) -> ModalResult<&'i str> {
    take_while(1.., |c: char| !c.is_whitespace()).parse_next(input)
}

fn attribute<'i>(input: &mut LineInput<'i>) -> ModalResult<(&'i str, &'i str)> {
    let key = attr_key.parse_next(input)?;
    literal("=").parse_next(input)?;
    let value = attr_value.parse_next(input)?;
    Ok((key, value))
}

/// Syntax-only view of a record: everything is still borrowed from the input.
struct RawLine<'i> {
    ts: &'i str,
    level: &'i str,
    component: &'i str,
    attrs: Vec<(&'i str, &'i str)>,
}

impl RawLine<'_> {
    /// Turn borrowed syntax into owned, validated domain values.
    fn into_record(self, line: usize, offset: usize) -> Result<Record, LibError> {
        let self_ts = self.ts;
        let ts_ms = self_ts.parse::<u64>().map_err(|err| {
            ParseError::new(
                line,
                offset,
                format!("invalid timestamp `{self_ts}`: {err}"),
            )
        })?;

        let self_level = self.level;
        let level = self_level
            .parse::<Level>()
            .map_err(|err| ParseError::new(line, offset, err.to_string()))?;

        let component =
            Component::try_new(self.component).map_err(|_| ValidationError::EmptyComponent)?;

        let mut attrs = BTreeMap::new();
        for (key, value) in self.attrs {
            if attrs.insert(key.to_owned(), value.to_owned()).is_some() {
                return Err(ValidationError::DuplicateAttribute(key.to_owned()).into());
            }
        }

        Ok(Record {
            ts_ms,
            level,
            component,
            attrs,
        })
    }
}

/// `<ts> SP <LEVEL> SP <component> (SP <key>=<value>)* HSpace* EOL`
///
/// Leading horizontal whitespace is tolerated so that indented input does not
/// suddenly become a syntax error; trailing whitespace is equally ignored.
fn raw_line<'i>(input: &mut LineInput<'i>) -> ModalResult<RawLine<'i>> {
    take_while(0.., hspace).parse_next(input)?;
    let ts = digit1.parse_next(input)?;
    space.parse_next(input)?;
    let level = alpha1.parse_next(input)?;
    space.parse_next(input)?;
    let component = attr_value.parse_next(input)?;
    let attrs: Vec<(&str, &str)> =
        winnow::combinator::repeat(0.., preceded(space, attribute)).parse_next(input)?;
    take_while(0.., hspace).parse_next(input)?;
    line_ending(input)?;

    Ok(RawLine {
        ts,
        level,
        component,
        attrs,
    })
}

/// What a single attempt at reading one framed line produced.
enum Step {
    /// A complete record plus the number of bytes it occupied.
    Complete(Record, usize),
    /// The buffer ends mid-record; more input may complete it.
    NeedMore,
    /// The bytes cannot become a record, no matter how much more arrives.
    Failed(LibError),
}

/// Try to read one newline-terminated record off the front of `input`.
fn read_one(input: &str, line: usize, offset: usize) -> Step {
    tracing::trace!(line, offset, buffered = input.len(), "attempting a record");
    let mut stream = Partial::new(input);
    match raw_line.parse_next(&mut stream) {
        Ok(raw) => {
            let rest = stream.into_inner();
            let consumed = input.len().saturating_sub(rest.len());
            match raw.into_record(line, offset) {
                Ok(record) => Step::Complete(record, consumed),
                Err(err) => Step::Failed(err),
            }
        }
        Err(ErrMode::Incomplete(_)) => Step::NeedMore,
        Err(ErrMode::Backtrack(_) | ErrMode::Cut(_)) => {
            Step::Failed(LibError::Parse(ParseError::new(
                line,
                offset,
                "expected `<ts_ms> <LEVEL> <component> [key=value ...]`",
            )))
        }
    }
}

/// Parse exactly one record from an already-complete line.
///
/// The line is framed with a synthetic trailing newline so the same
/// [`Partial`]-based parser can serve both complete and streaming callers:
/// without a terminator, the final token of a line would be indistinguishable
/// from a token that is still being appended.
///
/// # Errors
///
/// Returns [`LibError::Parse`] if the line does not match the grammar and
/// [`LibError::Validation`] if a field broke a domain invariant.
pub fn parse_line(line: &str) -> Result<Record, LibError> {
    let unterminated = line
        .strip_suffix('\n')
        .map_or(line, |cut| cut.strip_suffix('\r').unwrap_or(cut));
    if unterminated.contains('\n') {
        return Err(ParseError::new(1, 0, "input holds more than one line").into());
    }

    let mut framed = String::with_capacity(unterminated.len() + 1);
    framed.push_str(unterminated);
    framed.push('\n');

    match read_one(&framed, 1, 0) {
        Step::Complete(record, _) => Ok(record),
        Step::NeedMore => Err(ParseError::new(1, 0, "truncated line").into()),
        Step::Failed(err) => Err(err),
    }
}

/// Incremental record parser for chunked input.
///
/// Feed arbitrary chunks with [`LineParser::feed`]; every *complete* line is
/// returned as a [`Record`] immediately and removed from the buffer, a
/// trailing partial line stays buffered. Call [`LineParser::finish`] once the
/// stream is exhausted so a truncated last line is reported instead of
/// silently dropped.
#[derive(Debug, Default)]
pub struct LineParser {
    /// Bytes received but not yet turned into records.
    buf: String,
    /// Number of records handed out so far, used for 1-based line numbers.
    lines: usize,
    /// Byte offset of `buf[0]` within the whole stream.
    consumed: usize,
}

impl LineParser {
    /// Create an empty parser.
    #[must_use]
    pub fn new() -> Self {
        Self::default()
    }

    /// The bytes still buffered, i.e. an incomplete trailing line.
    #[must_use]
    pub fn buffered(&self) -> &str {
        &self.buf
    }

    /// Append `chunk` and return every record that is now complete.
    ///
    /// # Errors
    ///
    /// Returns [`LibError::Parse`] or [`LibError::Validation`] for the first
    /// line that can never parse, no matter how much more input arrives.
    pub fn feed(&mut self, chunk: &str) -> Result<Vec<Record>, LibError> {
        self.buf.push_str(chunk);
        let mut out = Vec::new();
        loop {
            match read_one(&self.buf, self.lines + 1, self.consumed) {
                Step::Complete(record, used) => {
                    out.push(record);
                    self.buf.drain(..used);
                    self.consumed += used;
                    self.lines += 1;
                }
                Step::NeedMore => break,
                Step::Failed(err) => return Err(err),
            }
        }
        Ok(out)
    }

    /// Close the stream: drain the final record and reject a truncated tail.
    ///
    /// # Errors
    ///
    /// Returns [`LibError::Parse`] if the leftover buffer is a truncated line.
    pub fn finish(&mut self) -> Result<Vec<Record>, LibError> {
        let out = self.feed("")?;
        let leftover = self.buf.trim();
        if !leftover.is_empty() {
            let at = self.lines + 1;
            let offset = self.consumed;
            return Err(ParseError::new(at, offset, "truncated line at end of input").into());
        }
        self.buf.clear();
        Ok(out)
    }
}
