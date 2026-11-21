//! Tokio-backed implementations of the core's runtime-agnostic `RecordSource`.
//!
//! `tally-core` defines the trait and never depends on a runtime; this module
//! is the CLI's half of that bargain — `tokio::io::AsyncBufReadExt` supplies
//! the bytes and the tokio runtime supplies the executor.
//!
//! The impl targets the **`Send` flavour** of the trait (`RecordSource`, the
//! variant `trait_variant` generates), because handlers read several files
//! concurrently and hand those futures to `JoinSet::spawn`, which requires
//! `Send`.

use std::collections::VecDeque;
use std::future::Future;

use tally_core::grammar::LineParser;
use tally_core::source::RecordSource;
use tally_core::{LibError, Record};
use tokio::io::{AsyncBufRead, AsyncBufReadExt};

/// A [`RecordSource`] over any tokio buffered reader (file or stdin).
///
/// Every input path in the CLI goes through this type, so `--stdin` and
/// `--files` cannot drift apart: both parse line by line, and both skip blank
/// lines instead of failing on them.
#[derive(Debug)]
pub struct BufferedReaderSource<R> {
    /// The reader supplying raw bytes.
    reader: R,
    /// Incremental line parser shared by every record read from `reader`.
    parser: LineParser,
    /// Records parsed from the current chunk but not handed out yet.
    ready: VecDeque<Record>,
    /// Set once EOF has been observed and the parser has been flushed.
    done: bool,
}

impl<R> BufferedReaderSource<R> {
    /// Wrap a buffered reader.
    #[must_use]
    pub fn new(reader: R) -> Self {
        Self {
            reader,
            parser: LineParser::new(),
            ready: VecDeque::new(),
            done: false,
        }
    }
}

impl<R: AsyncBufRead + Unpin + Send> RecordSource for BufferedReaderSource<R> {
    // `async fn` cannot be used here: `RecordSource` is the `Send`-bounded
    // variant that `trait_variant` generates, whose signature is
    // `fn(..) -> impl Future<..> + Send`. Spelling the future out is required,
    // not stylistic.
    #[allow(
        clippy::manual_async_fn,
        reason = "trait_variant generates a fn returning impl Future + Send"
    )]
    fn next_record(&mut self) -> impl Future<Output = Result<Option<Record>, LibError>> + Send {
        async move {
            loop {
                if let Some(record) = self.ready.pop_front() {
                    return Ok(Some(record));
                }
                if self.done {
                    return Ok(None);
                }

                let mut line = String::new();
                let read = self.reader.read_line(&mut line).await?;
                if read == 0 {
                    // EOF: flush the parser exactly once, so a final line
                    // without a trailing newline is still a record.
                    self.done = true;
                    match self.parser.finish() {
                        Ok(records) => self.ready.extend(records),
                        Err(failure) => {
                            self.ready.extend(failure.parsed);
                            return Err(failure.error);
                        }
                    }
                    continue;
                }

                // A blank line is neither a record nor an error.
                if line.trim().is_empty() {
                    continue;
                }

                match self.parser.feed(&line) {
                    Ok(records) => self.ready.extend(records),
                    Err(failure) => {
                        // Keep whatever parsed before the bad line.
                        self.ready.extend(failure.parsed);
                        return Err(failure.error);
                    }
                }
            }
        }
    }
}
