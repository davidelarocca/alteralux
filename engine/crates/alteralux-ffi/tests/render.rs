//! End-to-end tests of the FFI surface on the CPU backend.
//!
//! The key property: rendering through the bridge must give exactly the same
//! pixels as calling the upstream pipeline directly. The bridge only moves
//! data around; it must never change the look.

use std::path::PathBuf;
use std::sync::Arc;

use spektrafilm_core::pipeline::Pipeline;
use spektrafilm_core::profile;
use alteralux_ffi::{
    BackendPreference, ColorSpace, Engine, EngineError, PixelFormat, RenderColor, RenderRequest,
    SourceImage, StockKind,
};
use spektrafilm_gpu::cpu_backend::CpuBackend;
use spektrafilm_math::image::ImageBuf;
use spektrafilm_math::precision::{from_f32, to_f32};

const W: u32 = 48;
const H: u32 = 32;

fn data_dir() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../vendor/spektrafilm-rs/data")
}

fn engine() -> Arc<Engine> {
    Engine::new(data_dir().to_string_lossy().into_owned(), BackendPreference::Cpu).unwrap()
}

/// A small scene-linear test chart: a grey ramp blended with hue sweeps,
/// spanning from deep shadows to a couple of stops over middle grey.
fn chart_rgb() -> Vec<f32> {
    let mut px = Vec::with_capacity((W * H * 3) as usize);
    for y in 0..H {
        for x in 0..W {
            let t = x as f32 / (W - 1) as f32;
            let s = y as f32 / (H - 1) as f32;
            let grey = 0.184 * 2f32.powf(8.0 * t - 5.0);
            let hue = s * std::f32::consts::TAU;
            let tint = [hue.cos(), (hue - 2.094).cos(), (hue + 2.094).cos()];
            for c in tint {
                px.push(grey * (1.0 + 0.6 * c * s));
            }
        }
    }
    px
}

fn source() -> Arc<SourceImage> {
    let bytes: Vec<u8> = chart_rgb().iter().flat_map(|v| v.to_le_bytes()).collect();
    SourceImage::from_f32_pixels(W, H, 3, bytes).unwrap()
}

fn request(params_json: &str) -> RenderRequest {
    RenderRequest {
        film: "kodak_portra_400".into(),
        print: "kodak_portra_endura".into(),
        params_json: params_json.into(),
        color: RenderColor { input: ColorSpace::Rec2020, output: ColorSpace::Srgb },
        max_dimension: 0,
    }
}

fn rgb_of(image: &alteralux_ffi::RenderedImage) -> Vec<f32> {
    image
        .pixels(PixelFormat::RgbaF32)
        .chunks_exact(16)
        .flat_map(|px| {
            (0..3).map(move |c| f32::from_le_bytes(px[c * 4..c * 4 + 4].try_into().unwrap()))
        })
        .collect()
}

/// Renders the chart by calling the upstream pipeline directly, the way the
/// upstream GUI does, with the same parameter resolution as the bridge.
fn direct_render(film: &str, print: &str, params_json: &str) -> Vec<f32> {
    let engine = engine();
    let resolved = engine.resolve_params_json(params_json.into()).unwrap();
    let mut params: spektrafilm_core::params::RuntimeParams =
        serde_json::from_str(&resolved).unwrap();
    params.io.input_color_space = "ITU-R BT.2020".into();
    params.io.input_cctf_decoding = false;
    params.io.output_color_space = "sRGB".into();
    params.io.output_cctf_encoding = false;
    params.io.upscale_factor = 1.0;
    let film = profile::load_profile_by_name(&data_dir(), film).unwrap();
    let print = profile::load_profile_by_name(&data_dir(), print).unwrap();
    let pipeline = Pipeline::new_with_spectral(film, print, params, &data_dir()).unwrap();
    let input = ImageBuf::from_data(W, H, chart_rgb().into_iter().map(from_f32).collect());
    let out = pipeline
        .process_resident_borrowed(&input, &CpuBackend)
        .unwrap_or_else(|| pipeline.process(input.clone(), &CpuBackend));
    out.data.iter().map(|&v| to_f32(v)).collect()
}

#[test]
fn catalogue_lists_films_and_papers() {
    let stocks = engine().stocks().unwrap();
    let portra = stocks.iter().find(|s| s.id == "kodak_portra_400").expect("portra 400");
    assert_eq!(portra.kind, StockKind::Film);
    assert!(!portra.is_positive);
    let endura = stocks.iter().find(|s| s.id == "kodak_portra_endura").expect("endura");
    assert_eq!(endura.kind, StockKind::Paper);
    let velvia = stocks.iter().find(|s| s.id == "fujifilm_velvia_100").expect("velvia");
    assert!(velvia.is_positive);
    // Still and motion picture stocks are told apart.
    assert!(!portra.is_motion_picture);
    let vision = stocks.iter().find(|s| s.id == "kodak_vision3_250d").expect("vision3 250d");
    assert!(vision.is_motion_picture);
    // Films come before papers.
    let first_paper = stocks.iter().position(|s| s.kind == StockKind::Paper).unwrap();
    assert!(stocks[..first_paper].iter().all(|s| s.kind == StockKind::Film));
    assert!(stocks[first_paper..].iter().all(|s| s.kind == StockKind::Paper));
}

#[test]
fn bridge_output_matches_direct_pipeline() {
    let patch = r#"{"camera": {"exposure_compensation_ev": 0.5}}"#;
    let out = engine().render(source(), request(patch)).unwrap();
    assert_eq!((out.width(), out.height()), (W, H));
    let via_bridge = rgb_of(&out);
    let direct = direct_render("kodak_portra_400", "kodak_portra_endura", patch);
    assert_eq!(via_bridge, direct, "the bridge must not alter pipeline output");
    assert!(via_bridge.iter().all(|v| v.is_finite() && (0.0..=1.0).contains(v)));
    // Sanity: the chart is not rendered as a flat field.
    let (min, max) = via_bridge.iter().fold((1f32, 0f32), |(a, b), &v| (a.min(v), b.max(v)));
    assert!(max - min > 0.3, "suspiciously flat output: {min}..{max}");
}

#[test]
fn cached_pipeline_matches_a_fresh_one() {
    // One engine renders a sequence of edits, re-using its cached pipeline
    // where it can; each result must equal a fresh engine's render.
    let warm = engine();
    let edits = [
        r#"{}"#,
        r#"{"enlarger": {"y_filter_shift": 4.0}}"#,
        r#"{"enlarger": {"y_filter_shift": 4.0}, "film_render": {"grain": {"active": false}}}"#,
        r#"{"enlarger": {"y_filter_shift": 4.0}, "camera": {"exposure_compensation_ev": -1.0}}"#,
    ];
    for patch in edits {
        let a = rgb_of(&warm.render(source(), request(patch)).unwrap());
        let b = rgb_of(&engine().render(source(), request(patch)).unwrap());
        assert_eq!(a, b, "cache produced a different result for {patch}");
    }
}

#[test]
fn preview_renders_at_the_requested_size() {
    let mut req = request("");
    req.max_dimension = 24;
    let out = engine().render(source(), req).unwrap();
    assert_eq!((out.width(), out.height()), (24, 16));
    assert_eq!(out.pixels(PixelFormat::RgbaF16).len(), 24 * 16 * 8);
}

#[test]
fn slide_film_can_be_scanned_directly() {
    let mut req = request(r#"{"io": {"scan_film": true}}"#);
    req.film = "fujifilm_velvia_100".into();
    req.print = "does_not_matter".into();
    let out = engine().render(source(), req).unwrap();
    assert!(rgb_of(&out).iter().all(|v| v.is_finite()));
}

#[test]
fn errors_are_reported_not_panicked() {
    let e = engine();
    let mut req = request("");
    req.film = "no_such_film".into();
    assert!(matches!(e.render(source(), req), Err(EngineError::Profile { .. })));
    let mut req = request("");
    req.film = "../profiles/kodak_portra_400".into();
    assert!(matches!(e.render(source(), req), Err(EngineError::Profile { .. })));
    let req = request(r#"{"camera": {"exposure": 1}}"#);
    assert!(matches!(e.render(source(), req), Err(EngineError::Params { .. })));
    assert!(Engine::new("/nonexistent".into(), BackendPreference::Cpu).is_err());
}
