//! A hand-rolled typestate machine over the aggregation engine.
//!
//! [`Pipeline<S>`] carries its progress in a type parameter, so an invalid
//! order of operations is a *compile* error rather than a runtime one:
//!
//! ```text
//! Pipeline::<Parsed>::new(records)  ->  .aggregate()  ->  Pipeline<Aggregated>  ->  .emit()
//! ```
//!
//! `Aggregated` has no public constructor: the only way to obtain a
//! `Pipeline<Aggregated>` is to call [`Pipeline::<Parsed>::aggregate`]. There
//! is nothing to forget and nothing to check at runtime.
//!
//! This module also shows the second half of `bon`: [`count_by`] is a *function
//! builder*, complementing the *struct builder* derived on
//! [`Record`](crate::Record).

pub mod typestate;

use std::collections::HashMap;

use rayon::prelude::*;

use crate::engine::aggregate;
use crate::model::Record;

pub use typestate::{Aggregated, Parsed, Pipeline};

/// Which field of a [`Record`] an aggregation groups by.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum Key {
    /// Group by component name.
    #[default]
    Component,
    /// Group by severity.
    Level,
}

impl Key {
    /// The grouping value of `record`, as a string.
    #[must_use]
    pub fn of(self, record: &Record) -> &str {
        match self {
            Self::Component => record.component.as_ref(),
            Self::Level => record.level.as_str(),
        }
    }
}

/// Count records, grouped by the requested [`Key`].
///
/// `#[bon::builder]` turns the positional signature into a named-argument
/// builder, so the call site reads as a sentence:
///
/// ```
/// # use tally_core::build::{Key, count_by};
/// # use tally_core::grammar::parse_line;
/// let records = vec![parse_line("1 INFO engine").unwrap()];
/// let counts = count_by().records(&records).key(Key::Level).call();
/// assert_eq!(counts.get("INFO"), Some(&1));
/// ```
#[bon::builder]
#[must_use]
pub fn count_by(records: &[Record], key: Key) -> HashMap<String, u64> {
    aggregate(records.par_iter(), |record| {
        (key.of(record).to_owned(), 1u64)
    })
}
