//! The scatter → fold → reduce chain.
//!
//! Three phases, each a monoid-shaped map/reduce step:
//!
//! 1. **scatter** — `to_pair` turns each item into a `(key, value)`;
//! 2. **fold** — every rayon worker folds its own chunk into a thread-local
//!    [`HashMap`], so no lock and no shared mutable state is involved;
//! 3. **reduce** — the per-thread maps are merged pairwise with
//!    [`Combine::combine`] until one map remains.
//!
//! # Where the zero-cost claims actually live
//!
//! * There is no `dyn` anywhere on the hot path: `I`, `K`, `V` and `F` are all
//!   monomorphised, so the entry API and `V::combine` inline into the fold
//!   loop.
//! * `V::combine` is a static call resolved at compile time; `HashMap<K, V>`
//!   is itself a `Combine` when `V` is one, so nesting maps (component →
//!   level → count) costs no extra dispatch.
//! * The only allocation per fold is the map's own table; the seed is
//!   `HashMap::new()`, which does not allocate until the first insert.

use std::collections::HashMap;
use std::hash::Hash;

use rayon::prelude::*;

use crate::engine::combine::{insert_combined, Combine};

/// Group `items` by key and merge the values of every group.
///
/// The result is independent of the number of rayon threads, which is the
/// property the `aggregate == sequential reference` test pins down.
pub fn aggregate<I, K, V, F>(items: I, to_pair: F) -> HashMap<K, V>
where
    I: IntoParallelIterator,
    I::Item: Send,
    K: Hash + Eq + Clone + Send + Sync,
    V: Combine,
    F: Fn(I::Item) -> (K, V) + Send + Sync,
{
    items
        .into_par_iter()
        .fold(HashMap::new, |mut local, item| {
            let (key, value) = to_pair(item);
            insert_combined(&mut local, key, value);
            local
        })
        .reduce(HashMap::new, Combine::combine)
}
