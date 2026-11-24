//! Pixel buffers crossing the Swift boundary.

use std::sync::{Arc, Mutex};

use rayon::prelude::*;
use spektrafilm_core::stages::filming;
use spektrafilm_math::image::ImageBuf;
use spektrafilm_math::precision::{Scalar, from_f32, to_f32};

use crate::color::ColorSpace;
use crate::engine::RenderStats;
use crate::error::{EngineError, catch_panic};

/// Layout of the bytes returned by [`RenderedImage::pixels`].
#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum PixelFormat {
    /// 4 × IEEE half float per pixel, little endian, alpha = 1.
    /// Matches `MTLPixelFormat.rgba16Float` / Core Image `RGBAh`.
    RgbaF16,
    /// 4 × IEEE single float per pixel, little endian, alpha = 1.
    /// Matches `MTLPixelFormat.rgba32Float` / Core Image `RGBAf`.
    RgbaF32,
}

/// A scene-linear source image owned by the engine.
///
/// Created once per opened photo; every render of that photo reuses it. The
/// downscaled copies for interactive previews are cached alongside it.
#[derive(uniffi::Object)]
pub struct SourceImage {
    pub(crate) image: Arc<ImageBuf>,
    /// Most recently used first. The app alternates between a small size while
    /// a control moves and a larger one when it stops: scaling a 24 MP source
    /// takes about 250 ms, far more than rendering the preview.
    previews: Mutex<Vec<(u32, Arc<ImageBuf>)>>,
}

/// How many preview sizes a source keeps. At 2048 px a copy is about 33 MB.
const CACHED_PREVIEW_SIZES: usize = 3;

#[uniffi::export]
impl SourceImage {
    /// Builds a source from interleaved little-endian `f32` pixels with 3
    /// (RGB) or 4 (RGBA, alpha ignored) channels and no row padding.
    #[uniffi::constructor]
    pub fn from_f32_pixels(
        width: u32,
        height: u32,
        channels: u8,
        pixels: Vec<u8>,
    ) -> Result<Arc<Self>, EngineError> {
        if width == 0 || height == 0 {
            return Err(EngineError::invalid("image dimensions must be non-zero"));
        }
        if channels != 3 && channels != 4 {
            return Err(EngineError::invalid(format!("unsupported channel count {channels}")));
        }
        let pixel_count = (width as usize)
            .checked_mul(height as usize)
            .ok_or_else(|| EngineError::invalid("image too large"))?;
        let expected = pixel_count
            .checked_mul(channels as usize * 4)
            .ok_or_else(|| EngineError::invalid("image too large"))?;
        if pixels.len() != expected {
            return Err(EngineError::invalid(format!(
                "expected {expected} bytes for {width}×{height}×{channels} f32, got {}",
                pixels.len()
            )));
        }
        let stride = channels as usize * 4;
        let mut data: Vec<Scalar> = vec![from_f32(0.0); pixel_count * 3];
        data.par_chunks_exact_mut(3)
            .zip(pixels.par_chunks_exact(stride))
            .for_each(|(dst, src)| {
                for c in 0..3 {
                    let v = f32::from_le_bytes(src[c * 4..c * 4 + 4].try_into().unwrap());
                    // Non-finite values would poison every downstream blur.
                    dst[c] = from_f32(if v.is_finite() { v } else { 0.0 });
                }
            });
        Ok(Arc::new(Self::new(ImageBuf::from_data(width, height, data))))
    }

    pub fn width(&self) -> u32 {
        self.image.width
    }

    pub fn height(&self) -> u32 {
        self.image.height
    }

    /// Scales the source for previews of `max_dimension` ahead of time, so the
    /// first render at that size does not wait for it. Does nothing when the
    /// size is already cached or is not smaller than the source.
    pub fn prepare_preview(&self, max_dimension: u32) {
        let _ = self.scaled_for(max_dimension);
    }

    /// The exposure the engine's meter gives this image, in stops: what a
    /// render adds before the film when `camera.auto_exposure` is on, read
    /// with the same upstream function. `method` is a value of
    /// `camera.auto_exposure_method`; `input` is the space of the pixels.
    ///
    /// It lets the app meter a photo once and then change its light before
    /// the film without the meter answering the change: the pixels scaled by
    /// two to this power, rendered with the meter off, are the photo the
    /// engine would have exposed itself.
    pub fn metered_ev(&self, method: String, input: ColorSpace) -> Result<f32, EngineError> {
        catch_panic(|| {
            let rgb_to_xyz = filming::input_colorspace_to_xyz(input.engine_name());
            Ok(filming::measure_autoexposure_ev(&self.image, &rgb_to_xyz, &method))
        })
    }
}

impl SourceImage {
    pub(crate) fn new(image: ImageBuf) -> Self {
        Self { image: Arc::new(image), previews: Mutex::new(Vec::new()) }
    }

    /// The image to render for a request limited to `max_dimension` pixels on
    /// its long side (`0` = full resolution). Returns `None` for full
    /// resolution, so the caller can borrow `self.image` without copying.
    pub(crate) fn scaled_for(&self, max_dimension: u32) -> Option<Arc<ImageBuf>> {
        let long_side = self.image.width.max(self.image.height);
        if max_dimension == 0 || max_dimension >= long_side {
            return None;
        }
        let mut cache = self.previews.lock().unwrap_or_else(|p| p.into_inner());
        if let Some(index) = cache.iter().position(|(dim, _)| *dim == max_dimension) {
            let entry = cache.remove(index);
            let scaled = entry.1.clone();
            cache.insert(0, entry);
            return Some(scaled);
        }
        let factor = max_dimension as f32 / long_side as f32;
        let scaled = Arc::new(resize(&self.image, factor));
        cache.insert(0, (max_dimension, scaled.clone()));
        cache.truncate(CACHED_PREVIEW_SIZES);
        Some(scaled)
    }
}

/// Catmull-Rom resize, as the upstream GUI does for its working-resolution
/// previews (`rescale_preview_input_fast`).
fn resize(image: &ImageBuf, factor: f32) -> ImageBuf {
    let new_w = ((image.width as f32 * factor).round() as u32).max(1);
    let new_h = ((image.height as f32 * factor).round() as u32).max(1);
    let f32buf: Vec<f32> = image.data.par_iter().map(|&v| to_f32(v)).collect();
    let src = image::ImageBuffer::<image::Rgb<f32>, _>::from_raw(image.width, image.height, f32buf)
        .expect("ImageBuf dims match its data length");
    let dst = image::imageops::resize(&src, new_w, new_h, image::imageops::FilterType::CatmullRom);
    let data: Vec<Scalar> = dst.into_raw().into_par_iter().map(from_f32).collect();
    ImageBuf::from_data(new_w, new_h, data)
}

/// The display-linear result of a render.
#[derive(uniffi::Object)]
pub struct RenderedImage {
    pub(crate) image: ImageBuf,
    pub(crate) stats: RenderStats,
}

#[uniffi::export]
impl RenderedImage {
    pub fn width(&self) -> u32 {
        self.image.width
    }

    pub fn height(&self) -> u32 {
        self.image.height
    }

    pub fn stats(&self) -> RenderStats {
        self.stats.clone()
    }

    /// Interleaved RGBA pixels, no row padding, top row first.
    pub fn pixels(&self, format: PixelFormat) -> Vec<u8> {
        to_rgba_bytes(&self.image, format)
    }
}

pub(crate) fn to_rgba_bytes(image: &ImageBuf, format: PixelFormat) -> Vec<u8> {
    let clean = |v: Scalar| {
        let v = to_f32(v);
        if v.is_finite() { v } else { 0.0 }
    };
    match format {
        PixelFormat::RgbaF16 => {
            let one = half::f16::ONE.to_le_bytes();
            let mut out = vec![0u8; image.pixel_count() * 8];
            out.par_chunks_exact_mut(8).zip(image.data.par_chunks_exact(3)).for_each(|(dst, px)| {
                for c in 0..3 {
                    let h = half::f16::from_f32(clean(px[c])).to_le_bytes();
                    dst[c * 2..c * 2 + 2].copy_from_slice(&h);
                }
                dst[6..8].copy_from_slice(&one);
            });
            out
        }
        PixelFormat::RgbaF32 => {
            let one = 1.0f32.to_le_bytes();
            let mut out = vec![0u8; image.pixel_count() * 16];
            out.par_chunks_exact_mut(16).zip(image.data.par_chunks_exact(3)).for_each(|(dst, px)| {
                for c in 0..3 {
                    dst[c * 4..c * 4 + 4].copy_from_slice(&clean(px[c]).to_le_bytes());
                }
                dst[12..16].copy_from_slice(&one);
            });
            out
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn f32_bytes(values: &[f32]) -> Vec<u8> {
        values.iter().flat_map(|v| v.to_le_bytes()).collect()
    }

    #[test]
    fn rgba_input_drops_alpha_and_sanitizes() {
        let px = f32_bytes(&[0.1, 0.2, 0.3, 1.0, f32::NAN, f32::INFINITY, 0.5, 0.0]);
        let src = SourceImage::from_f32_pixels(2, 1, 4, px).unwrap();
        let d: Vec<f32> = src.image.data.iter().map(|&v| to_f32(v)).collect();
        assert_eq!(d, vec![0.1, 0.2, 0.3, 0.0, 0.0, 0.5]);
    }

    #[test]
    fn input_size_is_validated() {
        assert!(SourceImage::from_f32_pixels(2, 2, 3, vec![0; 47]).is_err());
        assert!(SourceImage::from_f32_pixels(0, 2, 3, vec![]).is_err());
        assert!(SourceImage::from_f32_pixels(1, 1, 2, vec![0; 8]).is_err());
        assert!(SourceImage::from_f32_pixels(2, 2, 3, vec![0; 48]).is_ok());
    }

    #[test]
    fn output_round_trips_through_both_formats() {
        let img = ImageBuf::from_data(2, 1, [0.25f32, 0.5, 1.0, 0.0, 0.125, 0.75].map(from_f32).to_vec());
        let f32s = to_rgba_bytes(&img, PixelFormat::RgbaF32);
        let back: Vec<f32> =
            f32s.chunks_exact(4).map(|b| f32::from_le_bytes(b.try_into().unwrap())).collect();
        assert_eq!(back, vec![0.25, 0.5, 1.0, 1.0, 0.0, 0.125, 0.75, 1.0]);
        let f16s = to_rgba_bytes(&img, PixelFormat::RgbaF16);
        let back: Vec<f32> = f16s
            .chunks_exact(2)
            .map(|b| half::f16::from_le_bytes(b.try_into().unwrap()).to_f32())
            .collect();
        assert_eq!(back, vec![0.25, 0.5, 1.0, 1.0, 0.0, 0.125, 0.75, 1.0]);
    }

    #[test]
    fn preview_scaling_is_cached_and_bounded() {
        let src = SourceImage::new(ImageBuf::from_data(400, 200, vec![from_f32(0.5); 400 * 200 * 3]));
        assert!(src.scaled_for(0).is_none());
        assert!(src.scaled_for(400).is_none());
        let a = src.scaled_for(100).unwrap();
        assert_eq!((a.width, a.height), (100, 50));
        let b = src.scaled_for(100).unwrap();
        assert!(Arc::ptr_eq(&a, &b));
    }

    #[test]
    fn alternating_preview_sizes_are_both_kept() {
        let src = SourceImage::new(ImageBuf::from_data(400, 200, vec![from_f32(0.5); 400 * 200 * 3]));
        let small = src.scaled_for(100).unwrap();
        let large = src.scaled_for(200).unwrap();
        assert!(Arc::ptr_eq(&small, &src.scaled_for(100).unwrap()));
        assert!(Arc::ptr_eq(&large, &src.scaled_for(200).unwrap()));
        src.prepare_preview(50);
        assert_eq!(src.previews.lock().unwrap().len(), 3);
        // A fourth size drops the one used longest ago.
        let _ = src.scaled_for(25);
        let kept: Vec<u32> = src.previews.lock().unwrap().iter().map(|(dim, _)| *dim).collect();
        assert_eq!(kept, vec![25, 50, 200]);
    }
}
