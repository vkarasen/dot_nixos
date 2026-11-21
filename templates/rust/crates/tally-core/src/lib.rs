//! Tiny greeting library used to exercise the flake.

/// Return a greeting for `name`.
///
/// ```
/// assert_eq!(my_lib::greet("world"), "Hello, world!");
/// ```
#[must_use]
pub fn greet(name: &str) -> String {
    format!("Hello, {name}!")
}

#[cfg(test)]
mod tests {
    use super::greet;

    #[test]
    fn greets_world() {
        assert_eq!(greet("world"), "Hello, world!");
    }

    #[test]
    fn greets_empty() {
        assert_eq!(greet(""), "Hello, !");
    }
}
