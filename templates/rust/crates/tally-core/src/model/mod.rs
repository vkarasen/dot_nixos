//! Domain model: validated values and the record they compose into.

pub mod record;
pub mod value;

pub use record::{Level, Record, PARENT_ATTR};
pub use value::{Component, Percent};
