//! Swift-facing API over the spektrafilm-rs spectral film engine.
//!
//! The macOS app talks to the engine only through this crate. UniFFI
//! generates the Swift bindings from the `#[uniffi::export]` items below.
//!
//! Design contract:
//! - **Linear in, linear out.** The app decodes images (RAW via Core Image,
//!   TIFF/EXR via ImageIO) to *scene-linear* RGB and hands them over. The engine
//!   returns *display-linear* RGB in `[0, 1]`. Every transfer function and
//!   color-management step on either side is done natively by macOS
//!   (ColorSync / Core Image), never by the engine.
//! - **Parameters are JSON.** The full upstream `RuntimeParams` tree is exposed
//!   as JSON: the app sends a partial tree (a "patch") that is deep-merged over
//!   the engine defaults. Unknown keys are rejected so typos surface as errors
//!   instead of being silently ignored.
//! - **Pixels cross the boundary as bytes** (`Data` in Swift), so a frame is a
//!   single memcpy rather than a per-element conversion.

mod color;
mod engine;
mod error;
mod image_io;
mod params;

pub use color::{ColorSpace, RenderColor};
pub use engine::{BackendPreference, Engine, RenderRequest, RenderStats, StockInfo, StockKind};
pub use error::EngineError;
pub use image_io::{PixelFormat, RenderedImage, SourceImage};

uniffi::setup_scaffolding!();

/// Version of this bridge crate (the app shows it in its About panel).
#[uniffi::export]
pub fn bridge_version() -> String {
    env!("CARGO_PKG_VERSION").to_string()
}

/// Version of the upstream engine this bridge is built with: the film model
/// that gives a look its pixels. The app writes it beside the adjustments and
/// the recipes it saves, so a look made with an earlier model can be told
/// apart once the engine is updated.
#[uniffi::export]
pub fn engine_version() -> String {
    env!("SPEKTRAFILM_VERSION").to_string()
}
