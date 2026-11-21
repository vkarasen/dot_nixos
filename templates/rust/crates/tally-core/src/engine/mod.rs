//! Mergeable ("scatter → fold → reduce") aggregation primitives.

pub mod aggregate;
pub mod combine;

pub use aggregate::aggregate;
pub use combine::Combine;
