//! Serialisation helpers shared by every subcommand.
//!
//! The three formats are behind one [`Format`] enum, so no subcommand has to
//! care which one the user asked for. `yaml_serde` is pulled in under the name
//! `serde_yaml`, which is why the YAML arm reads exactly like the JSON one.

use clap::ValueEnum;
use miette::{IntoDiagnostic, Result};
use serde::de::DeserializeOwned;
use serde::Serialize;

/// Output encoding selected by `--format`.
#[derive(Debug, Clone, Copy, PartialEq, Eq, ValueEnum)]
pub enum Format {
    /// JSON — the default.
    Json,
    /// YAML.
    Yaml,
    /// TOML.
    Toml,
}

impl Format {
    /// File-name extension matching the format.
    #[must_use]
    pub const fn extension(self) -> &'static str {
        match self {
            Self::Json => "json",
            Self::Yaml => "yaml",
            Self::Toml => "toml",
        }
    }
}

/// Encode `value` in `format`.
///
/// # Errors
///
/// Propagates the serialiser's diagnostics (for example a TOML value that
/// cannot be represented as a table).
pub fn encode<T: Serialize>(format: Format, value: &T) -> Result<String> {
    match format {
        Format::Json => to_json(value),
        Format::Yaml => to_yaml(value),
        Format::Toml => to_toml(value),
    }
}

/// Decode `text` in `format`.
///
/// # Errors
///
/// Propagates the parser's diagnostics.
pub fn decode<T: DeserializeOwned>(format: Format, text: &str) -> Result<T> {
    match format {
        Format::Json => from_json(text),
        Format::Yaml => from_yaml(text),
        Format::Toml => from_toml(text),
    }
}

/// Encode as JSON.
///
/// # Errors
///
/// Propagates `serde_json`'s error.
pub fn to_json<T: Serialize>(value: &T) -> Result<String> {
    serde_json::to_string_pretty(value).into_diagnostic()
}

/// Encode as YAML.
///
/// # Errors
///
/// Propagates the YAML serialiser's error.
pub fn to_yaml<T: Serialize>(value: &T) -> Result<String> {
    serde_yaml::to_string(value).into_diagnostic()
}

/// Encode as TOML.
///
/// # Errors
///
/// Propagates `toml`'s error.
pub fn to_toml<T: Serialize>(value: &T) -> Result<String> {
    toml::to_string_pretty(value).into_diagnostic()
}

/// Decode JSON.
///
/// # Errors
///
/// Propagates `serde_json`'s error.
pub fn from_json<T: DeserializeOwned>(text: &str) -> Result<T> {
    serde_json::from_str(text).into_diagnostic()
}

/// Decode YAML.
///
/// # Errors
///
/// Propagates the YAML deserialiser's error.
pub fn from_yaml<T: DeserializeOwned>(text: &str) -> Result<T> {
    serde_yaml::from_str(text).into_diagnostic()
}

/// Decode TOML.
///
/// # Errors
///
/// Propagates `toml`'s error.
pub fn from_toml<T: DeserializeOwned>(text: &str) -> Result<T> {
    toml::from_str(text).into_diagnostic()
}
