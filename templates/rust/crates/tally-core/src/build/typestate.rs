//! The [`Pipeline`] typestate machine itself.

use std::collections::BTreeMap;
use std::marker::PhantomData;

use rayon::prelude::*;
use serde::Serialize;

use crate::build::Key;
use crate::engine::aggregate;
use crate::model::Record;

/// State marker: records are parsed, nothing is aggregated yet.
#[derive(Debug, Clone, Copy)]
pub struct Parsed;

/// State marker: aggregation has run.
#[derive(Debug, Clone, Copy)]
pub struct Aggregated;

/// A two-stage pipeline whose operations depend on its state.
///
/// The state lives only in [`PhantomData`]; at runtime a pipeline is the
/// vector of records plus (once aggregated) the summary, so the typestate costs
/// nothing.
#[derive(Debug)]
pub struct Pipeline<S> {
    /// The records the pipeline was built from.
    records: Vec<Record>,
    /// Filled in by the `Parsed -> Aggregated` transition.
    summary: BTreeMap<String, u64>,
    /// Which field grouping uses.
    key: Key,
    /// Zero-sized state tag.
    state: PhantomData<S>,
}

impl Pipeline<Parsed> {
    /// Start a pipeline from already-parsed records.
    ///
    /// Grouping defaults to [`Key::Component`]; override it with
    /// [`Pipeline::group_by`] before aggregating.
    #[must_use]
    pub fn new(records: Vec<Record>) -> Self {
        Self {
            records,
            summary: BTreeMap::new(),
            key: Key::Component,
            state: PhantomData,
        }
    }

    /// Choose the grouping key, still in the `Parsed` state.
    #[must_use]
    pub fn group_by(mut self, key: Key) -> Self {
        self.key = key;
        self
    }

    /// Run the aggregation. This is the *only* way to reach
    /// [`Pipeline<Aggregated>`].
    #[must_use]
    pub fn aggregate(self) -> Pipeline<Aggregated> {
        let key = self.key;
        let count = self.records.len();
        let summary = aggregate(self.records.par_iter(), |record| {
            (key.of(record).to_owned(), 1u64)
        });
        // A module-path target: this shows up as `tally_core::build::typestate`,
        // which is how library events stay distinguishable from the CLI's own
        // `cli` target in the same subscriber.
        tracing::debug!(
            records = count,
            groups = summary.len(),
            by = ?key,
            "pipeline aggregated"
        );
        Pipeline {
            records: self.records,
            summary: summary.into_iter().collect(),
            key,
            state: PhantomData,
        }
    }
}

impl Pipeline<Aggregated> {
    /// The summary in deterministic (key-sorted) order.
    #[must_use]
    pub fn emit(&self) -> &BTreeMap<String, u64> {
        &self.summary
    }

    /// Which field the summary is grouped by.
    #[must_use]
    pub fn key(&self) -> Key {
        self.key
    }

    /// Feed the summary into any [`serde::Serializer`].
    ///
    /// Keeping `serialize` generic is what lets the CLI choose between JSON,
    /// YAML and TOML without this crate depending on any of those formats.
    ///
    /// # Errors
    ///
    /// Propagates the serializer's own error, e.g. a map with non-string keys.
    pub fn serialize<S: serde::Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        self.summary.serialize(serializer)
    }

    /// The records the summary was computed from.
    #[must_use]
    pub fn records(&self) -> &[Record] {
        &self.records
    }
}
