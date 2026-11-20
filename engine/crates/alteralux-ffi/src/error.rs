use std::any::Any;

/// Errors surfaced to Swift as a throwing `EngineError` enum.
#[derive(Debug, thiserror::Error, uniffi::Error)]
pub enum EngineError {
    /// A caller-supplied argument is malformed (sizes, buffer lengths, ...).
    #[error("invalid argument: {message}")]
    InvalidArgument { message: String },
    /// A film or paper profile could not be found or parsed.
    #[error("profile error: {message}")]
    Profile { message: String },
    /// The parameter JSON is malformed, has an unknown key or a wrong type.
    #[error("invalid parameters: {message}")]
    Params { message: String },
    /// The pipeline could not be built (missing data files, bad calibration).
    #[error("pipeline error: {message}")]
    Pipeline { message: String },
    /// The engine panicked. The panic is contained; the engine stays usable.
    #[error("internal engine error: {message}")]
    Internal { message: String },
}

impl EngineError {
    pub(crate) fn invalid(message: impl Into<String>) -> Self {
        Self::InvalidArgument { message: message.into() }
    }
    pub(crate) fn params(message: impl Into<String>) -> Self {
        Self::Params { message: message.into() }
    }
}

/// Runs `f`, turning a panic inside the engine into `EngineError::Internal`.
///
/// Unwinding across the FFI boundary is undefined behaviour, so every exported
/// entry point that calls into the engine goes through this.
pub(crate) fn catch_panic<T>(
    f: impl FnOnce() -> Result<T, EngineError>,
) -> Result<T, EngineError> {
    std::panic::catch_unwind(std::panic::AssertUnwindSafe(f))
        .unwrap_or_else(|payload| Err(EngineError::Internal { message: panic_message(&payload) }))
}

fn panic_message(payload: &Box<dyn Any + Send>) -> String {
    if let Some(s) = payload.downcast_ref::<&str>() {
        (*s).to_string()
    } else if let Some(s) = payload.downcast_ref::<String>() {
        s.clone()
    } else {
        "unknown panic".to_string()
    }
}
