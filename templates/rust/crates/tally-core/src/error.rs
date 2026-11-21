//! The single error type shared by every fallible operation in this crate.
//!
//! Errors are split in two layers:
//!
//! * [`LibError`] is what callers see. It is deliberately *not* `Clone`/`Eq`
//!   because it wraps [`std::io::Error`], which is neither.
//! * [`ParseError`] and [`ValidationError`] are the value-level leaves. Both
//!   are plain data and therefore cheap to clone and compare in tests.

/// One line of input that could not be turned into a [`Record`][crate::Record].
///
/// The location is always expressed in terms of the *original* input: `line`
/// is 1-based, `offset` is the byte offset of the first byte of that line.
#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
#[error("line {line} (byte offset {offset}): {reason}")]
pub struct ParseError {
    /// 1-based line number inside the input the record was read from.
    pub line: usize,
    /// Byte offset of the start of that line.
    pub offset: usize,
    /// Human-readable description of what went wrong.
    pub reason: String,
}

impl ParseError {
    /// Build a parse error for `line`/`offset` with a formatted `reason`.
    #[must_use]
    pub fn new(line: usize, offset: usize, reason: impl Into<String>) -> Self {
        Self {
            line,
            offset,
            reason: reason.into(),
        }
    }
}

/// A value that parsed cleanly but violates a domain invariant.
#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum ValidationError {
    /// A component name was empty.
    #[error("component name must not be empty")]
    EmptyComponent,
    /// The level token is not one of the six known names.
    #[error("`{0}` is not a log level")]
    UnknownLevel(String),
    /// The attribute key does not match `[a-z][a-z0-9_]*`.
    #[error("`{0}` is not a valid attribute key")]
    InvalidAttributeKey(String),
    /// The same attribute key appeared twice in one record.
    #[error("attribute `{0}` appears more than once")]
    DuplicateAttribute(String),
}

/// Everything that can go wrong while parsing, aggregating or analysing records.
#[derive(Debug, thiserror::Error)]
pub enum LibError {
    /// The input did not match the record grammar.
    #[error(transparent)]
    Parse(#[from] ParseError),
    /// The input parsed but broke a domain invariant.
    #[error(transparent)]
    Validation(#[from] ValidationError),
    /// Reading the underlying stream failed.
    #[error("i/o error: {0}")]
    Io(#[from] std::io::Error),
    /// The caller handed us nothing at all.
    #[error("input contained no records")]
    EmptyInput,
    /// The dependency graph is cyclic, so no topological order exists.
    #[error("dependency cycle involving component `{component}`")]
    GraphCycle {
        /// One component that participates in the cycle.
        component: String,
    },
}

impl LibError {
    /// True if this error describes a malformed or incompatible input line.
    #[must_use]
    pub fn is_parse_error(&self) -> bool {
        matches!(self, Self::Parse(_) | Self::Validation(_))
    }
}
