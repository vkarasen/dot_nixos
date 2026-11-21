//! Dense counts: `components × levels` as an [`ndarray::Array2`].
//!
//! This is the second flavour of the fold/reduce chain. Instead of a hash map
//! it accumulates into a fixed-shape array, which lets [`ndarray`] use its own
//! element-wise `Add` as the reduce step. `Array2::zeros(shape)` is the
//! identity, `acc[[row, col]] += 1` is the fold, and `a + b` (element-wise) is
//! the reduce — the same three monoid pieces as [`crate::engine::aggregate`],
//! with a different accumulator.

use ndarray::Array2;
use rayon::prelude::*;

use crate::model::{Component, Level, Record};

/// Count records per `(component, level)`.
///
/// Rows are the sorted, de-duplicated set of components; columns are
/// [`Level::ALL`] in [`Level::index`] order. The row order is part of the
/// contract, so the matrix is comparable across threads and runs.
#[must_use]
pub fn count_matrix(records: &[Record]) -> Array2<u64> {
    let mut components: Vec<Component> = records
        .iter()
        .map(|record| record.component.clone())
        .collect();
    components.sort_unstable();
    components.dedup();

    let shape = (components.len(), Level::COUNT);
    if components.is_empty() {
        return Array2::zeros(shape);
    }

    records
        .par_iter()
        .fold(
            || Array2::<u64>::zeros(shape),
            |mut acc, record| {
                if let Ok(row) = components.binary_search(&record.component) {
                    acc[[row, record.level.index()]] += 1;
                }
                acc
            },
        )
        .reduce(|| Array2::<u64>::zeros(shape), |left, right| left + right)
}

#[cfg(test)]
mod tests {
    use std::collections::BTreeMap;

    use super::count_matrix;
    use crate::model::{Component, Level, Record};

    fn record(ts_ms: u64, level: Level, component: &str) -> Record {
        Record {
            ts_ms,
            level,
            component: Component::try_new(component).expect("non-empty"),
            attrs: BTreeMap::new(),
        }
    }

    /// The obviously-correct implementation the parallel one must match.
    fn count_matrix_sequential(records: &[Record]) -> ndarray::Array2<u64> {
        let mut components: Vec<Component> = records
            .iter()
            .map(|record| record.component.clone())
            .collect();
        components.sort_unstable();
        components.dedup();
        let mut out = ndarray::Array2::zeros((components.len(), Level::COUNT));
        for record in records {
            let row = components
                .binary_search(&record.component)
                .expect("component came from `records`");
            out[[row, record.level.index()]] += 1;
        }
        out
    }

    #[test]
    fn matches_sequential_reference() {
        let records = vec![
            record(1, Level::Info, "engine"),
            record(2, Level::Warn, "engine"),
            record(3, Level::Info, "scheduler"),
            record(4, Level::Fatal, "engine"),
            record(5, Level::Info, "scheduler"),
        ];
        let parallel = count_matrix(&records);
        let sequential = count_matrix_sequential(&records);
        assert_eq!(parallel, sequential);
        assert_eq!(parallel.shape(), &[2, Level::COUNT]);
        // rows sorted: engine, scheduler; column 2 is INFO.
        assert_eq!(parallel[[0, Level::Info.index()]], 1);
        assert_eq!(parallel[[0, Level::Fatal.index()]], 1);
        assert_eq!(parallel[[1, Level::Info.index()]], 2);
    }

    #[test]
    fn empty_input_yields_empty_matrix() {
        assert_eq!(count_matrix(&[]).shape(), &[0, Level::COUNT]);
    }
}
