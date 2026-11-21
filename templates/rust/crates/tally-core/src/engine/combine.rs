//! The [`Combine`] monoid.
//!
//! Rayon's `fold`/`reduce` needs an operation that is *associative* (so the
//! tree of partial results can be combined in any shape), *commutative* (so
//! work-stealing may hand out partial results in any order) and has an
//! identity (so `fold` can start each thread with a cheap seed).

use std::collections::hash_map::Entry;
use std::collections::HashMap;
use std::hash::{BuildHasher, Hash};

/// A mergeable value: identity element plus an associative, commutative merge.
///
/// `Send + Sync + Clone` are required because rayon combines partial results
/// that were produced on different threads and may need a value twice while
/// swapping it into a map slot.
pub trait Combine: Clone + Send + Sync {
    /// The identity element: `x.combine(Self::neutral()) == x`.
    #[must_use]
    fn neutral() -> Self;

    /// Merge `other` into `self`.
    #[must_use]
    fn combine(self, other: Self) -> Self;
}

/// Counts add; saturating so the monoid stays total for `u64`.
impl Combine for u64 {
    fn neutral() -> Self {
        0
    }

    fn combine(self, other: Self) -> Self {
        self.saturating_add(other)
    }
}

/// Maps merge key-by-key, combining values that collide.
impl<K, V, S> Combine for HashMap<K, V, S>
where
    K: Hash + Eq + Clone + Send + Sync,
    V: Combine,
    S: BuildHasher + Default + Clone + Send + Sync,
{
    fn neutral() -> Self {
        Self::default()
    }

    fn combine(mut self, other: Self) -> Self {
        for (key, value) in other {
            insert_combined(&mut self, key, value);
        }
        self
    }
}

/// Insert `value` at `key`, merging with whatever is already there.
///
/// Written with the entry API so a fresh key does not need a clone: the
/// `Vacant` arm moves `value` straight in.
pub(crate) fn insert_combined<K, V, S>(map: &mut HashMap<K, V, S>, key: K, value: V)
where
    K: Hash + Eq,
    V: Combine,
    S: BuildHasher,
{
    match map.entry(key) {
        Entry::Vacant(slot) => {
            slot.insert(value);
        }
        Entry::Occupied(mut slot) => {
            let merged = slot.get().clone().combine(value);
            slot.insert(merged);
        }
    }
}
