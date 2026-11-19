use spektrafilm_core::params::RuntimeParams;

/// RGB color spaces the engine understands, for input and output.
///
/// Values are always linear (no transfer function). On the Swift side each
/// case maps to the matching linear `CGColorSpace` (for example
/// `CGColorSpace.linearSRGB` and `CGColorSpace.linearITUR_2020`).
#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum ColorSpace {
    /// Linear sRGB / Rec. 709 primaries, D65.
    Srgb,
    /// Linear ITU-R BT.2020 primaries, D65.
    Rec2020,
    /// Linear ProPhoto RGB (ROMM) primaries, D50.
    ProPhoto,
}

impl ColorSpace {
    /// The name the upstream engine uses for this space.
    pub(crate) fn engine_name(self) -> &'static str {
        match self {
            ColorSpace::Srgb => "sRGB",
            ColorSpace::Rec2020 => "ITU-R BT.2020",
            ColorSpace::ProPhoto => "ProPhoto RGB",
        }
    }
}

/// Color handling for one render.
#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Record)]
pub struct RenderColor {
    /// Space of the scene-linear source pixels.
    pub input: ColorSpace,
    /// Space of the display-linear output pixels.
    ///
    /// `Srgb` reproduces the reference spektrafilm look exactly, including its
    /// perceptual output gamut compression. The engine only implements that
    /// compression for sRGB; other output spaces keep wider colors but skip it.
    pub output: ColorSpace,
}

impl Default for RenderColor {
    fn default() -> Self {
        Self { input: ColorSpace::Rec2020, output: ColorSpace::Srgb }
    }
}

/// Forces the linear-in / linear-out contract onto `params`.
pub(crate) fn apply(params: &mut RuntimeParams, color: RenderColor) {
    params.io.input_color_space = color.input.engine_name().to_string();
    params.io.input_cctf_decoding = false;
    params.io.output_color_space = color.output.engine_name().to_string();
    params.io.output_cctf_encoding = false;
}
