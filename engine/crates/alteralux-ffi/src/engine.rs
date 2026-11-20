//! The `Engine` object: profile catalogue, parameter defaults and rendering.

use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};
use std::time::Instant;

use spektrafilm_core::params::RuntimeParams;
use spektrafilm_core::pipeline::Pipeline;
use spektrafilm_core::profile;
use spektrafilm_gpu::ComputeBackend;
use spektrafilm_math::image::ImageBuf;

use crate::color::{self, RenderColor};
use crate::error::{EngineError, catch_panic};
use crate::image_io::{RenderedImage, SourceImage};
use crate::params;

/// Which compute backend to run the pipeline on.
#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum BackendPreference {
    /// GPU when available (Metal through wgpu on macOS), otherwise CPU.
    Automatic,
    /// Metal GPU; fails if no GPU adapter is available.
    Gpu,
    /// CPU only (multi-threaded). Slower, but bit-for-bit closest to the
    /// reference Python implementation.
    Cpu,
}

/// Film (negative or slide) versus print paper.
#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum StockKind {
    Film,
    Paper,
}

/// One film or paper profile shipped in the data directory.
#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct StockInfo {
    /// Stable identifier (profile file name), e.g. `kodak_portra_400`.
    pub id: String,
    /// Human-readable name from the profile, e.g. `Kodak Portra 400`.
    pub display_name: String,
    pub kind: StockKind,
    /// `true` for reversal (slide) film, which is normally scanned directly
    /// instead of printed.
    pub is_positive: bool,
    pub is_black_and_white: bool,
    /// Paper the profile recommends printing on, if any.
    pub target_print: Option<String>,
    /// Available development times in minutes (black & white families only).
    pub development_times_min: Vec<f64>,
}

/// What to render.
#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct RenderRequest {
    /// Film stock id (see [`StockInfo::id`]).
    pub film: String,
    /// Paper stock id. Ignored when the parameters set `io.scan_film`.
    pub print: String,
    /// Partial parameter tree, deep-merged over the defaults (see
    /// [`Engine::default_params_json`]). Empty string = defaults.
    pub params_json: String,
    pub color: RenderColor,
    /// Long-side pixel limit for fast previews; `0` renders at full resolution.
    pub max_dimension: u32,
}

/// Timings of one render, in milliseconds.
#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct RenderStats {
    pub backend: String,
    /// Time spent (re)building and calibrating the pipeline; ~0 when cached.
    pub pipeline_ms: f64,
    /// Time spent downscaling the source for a preview; ~0 when cached.
    pub scale_ms: f64,
    /// Time spent in the simulation itself.
    pub render_ms: f64,
    pub total_ms: f64,
}

struct CachedPipeline {
    key: String,
    pipeline: Pipeline,
}

/// Entry point of the engine. Thread-safe: renders may run concurrently.
#[derive(uniffi::Object)]
pub struct Engine {
    data_dir: PathBuf,
    backend: Arc<dyn ComputeBackend>,
    pipeline: Mutex<Option<CachedPipeline>>,
}

#[uniffi::export]
impl Engine {
    /// Creates an engine reading profiles and spectral data from `data_dir`
    /// (the upstream `data/` folder, bundled in the app's Resources).
    #[uniffi::constructor]
    pub fn new(data_dir: String, backend: BackendPreference) -> Result<Arc<Self>, EngineError> {
        catch_panic(|| {
            let data_dir = PathBuf::from(data_dir);
            if !data_dir.join("profiles").is_dir() {
                return Err(EngineError::invalid(format!(
                    "{} does not contain a `profiles` folder",
                    data_dir.display()
                )));
            }
            let backend = make_backend(backend)?;
            Ok(Arc::new(Self { data_dir, backend, pipeline: Mutex::new(None) }))
        })
    }

    /// Name of the compute backend in use (for diagnostics).
    pub fn backend_name(&self) -> String {
        self.backend.name().to_string()
    }

    /// All film and paper profiles, films first, each group sorted by name.
    pub fn stocks(&self) -> Result<Vec<StockInfo>, EngineError> {
        catch_panic(|| list_stocks(&self.data_dir))
    }

    /// The complete default parameter tree as pretty-printed JSON. Useful as
    /// documentation of every tunable and as the base for presets.
    pub fn default_params_json(&self) -> String {
        serde_json::to_string_pretty(&params::defaults_value()).expect("serializable")
    }

    /// The full parameter tree that `params_json` resolves to, or the error a
    /// render with it would raise. Lets the app validate presets up front.
    pub fn resolve_params_json(&self, params_json: String) -> Result<String, EngineError> {
        let params = params::resolve(&params_json)?;
        Ok(serde_json::to_string_pretty(&params).expect("serializable"))
    }

    /// Runs the simulation on `source`.
    pub fn render(
        &self,
        source: Arc<SourceImage>,
        request: RenderRequest,
    ) -> Result<Arc<RenderedImage>, EngineError> {
        catch_panic(|| self.render_inner(&source, &request).map(Arc::new))
    }
}

impl Engine {
    fn render_inner(
        &self,
        source: &SourceImage,
        request: &RenderRequest,
    ) -> Result<RenderedImage, EngineError> {
        let t_total = Instant::now();
        let mut params = params::resolve(&request.params_json)?;
        color::apply(&mut params, request.color);

        let t = Instant::now();
        let scaled = source.scaled_for(request.max_dimension);
        let scale_ms = ms(t);
        // The working resolution is chosen above; never rescale again inside.
        params.io.upscale_factor = 1.0;

        let t = Instant::now();
        let pipeline = self.pipeline_for(&request.film, &request.print, params)?;
        let pipeline_ms = ms(t);

        let t = Instant::now();
        let backend = self.backend.as_ref();
        let output = match scaled {
            Some(image) => pipeline.process((*image).clone(), backend),
            None => run_full_resolution(&pipeline, &source.image, backend),
        };
        let render_ms = ms(t);

        Ok(RenderedImage {
            image: output,
            stats: RenderStats {
                backend: self.backend_name(),
                pipeline_ms,
                scale_ms,
                render_ms,
                total_ms: ms(t_total),
            },
        })
    }

    /// Returns a pipeline for `params`, reusing the calibrated one when only
    /// non-calibration parameters changed (the common case while dragging a
    /// slider).
    fn pipeline_for(
        &self,
        film: &str,
        print: &str,
        params: RuntimeParams,
    ) -> Result<Pipeline, EngineError> {
        let print = if params.io.scan_film { film } else { print };
        let key = params::pipeline_cache_key(film, print, &params);
        {
            let cache = self.pipeline.lock().unwrap_or_else(|p| p.into_inner());
            if let Some(cached) = cache.as_ref().filter(|c| c.key == key) {
                return Ok(cached.pipeline.clone().with_params(params));
            }
        }
        let film_profile = load_profile(&self.data_dir, film)?;
        let print_profile = load_profile(&self.data_dir, print)?;
        let pipeline =
            Pipeline::new_with_spectral(film_profile, print_profile, params, &self.data_dir)
                .map_err(|message| EngineError::Pipeline { message })?;
        let mut cache = self.pipeline.lock().unwrap_or_else(|p| p.into_inner());
        *cache = Some(CachedPipeline { key, pipeline: pipeline.clone() });
        Ok(pipeline)
    }
}

/// Full-resolution path. Mirrors the upstream GUI: the GPU-resident chain runs
/// from a borrowed image (no deep copy) except for directly scanned slide film,
/// which needs the staged path.
fn run_full_resolution(pipeline: &Pipeline, image: &ImageBuf, backend: &dyn ComputeBackend) -> ImageBuf {
    if pipeline.params.io.scan_film && pipeline.film.is_positive() {
        return pipeline.process(image.clone(), backend);
    }
    pipeline
        .process_resident_borrowed(image, backend)
        .unwrap_or_else(|| pipeline.process(image.clone(), backend))
}

fn make_backend(preference: BackendPreference) -> Result<Arc<dyn ComputeBackend>, EngineError> {
    match preference {
        BackendPreference::Automatic => Ok(Arc::from(spektrafilm_gpu::select_backend())),
        BackendPreference::Cpu => Ok(Arc::new(spektrafilm_gpu::cpu_backend::CpuBackend)),
        BackendPreference::Gpu => spektrafilm_gpu::wgpu_backend::WgpuBackend::new()
            .map(|b| Arc::new(b) as Arc<dyn ComputeBackend>)
            .ok_or_else(|| EngineError::Pipeline { message: "no GPU adapter available".into() }),
    }
}

fn load_profile(data_dir: &Path, id: &str) -> Result<profile::Profile, EngineError> {
    // Ids are file stems; refuse anything that could escape the profiles folder.
    if id.is_empty() || id.contains(['/', '\\']) || id.starts_with('.') {
        return Err(EngineError::Profile { message: format!("invalid stock id `{id}`") });
    }
    profile::load_profile_by_name(data_dir, id)
        .map_err(|e| EngineError::Profile { message: format!("`{id}`: {e}") })
}

fn list_stocks(data_dir: &Path) -> Result<Vec<StockInfo>, EngineError> {
    let dir = data_dir.join("profiles");
    let entries = std::fs::read_dir(&dir)
        .map_err(|e| EngineError::Profile { message: format!("{}: {e}", dir.display()) })?;
    let mut stocks = Vec::new();
    for entry in entries.flatten() {
        let file_name = entry.file_name();
        let Some(id) = file_name.to_str().and_then(|n| n.strip_suffix(".json")) else {
            continue;
        };
        // Skip files that are not loadable profiles rather than failing the
        // whole catalogue.
        let Ok(p) = profile::load_profile_by_name(data_dir, id) else {
            tracing::warn!(id, "skipping unreadable profile");
            continue;
        };
        let is_paper = p.info.support == "paper" || p.info.stage == "printing";
        stocks.push(StockInfo {
            id: id.to_string(),
            display_name: p.info.name.clone().unwrap_or_else(|| id.to_string()),
            kind: if is_paper { StockKind::Paper } else { StockKind::Film },
            is_positive: p.is_positive(),
            is_black_and_white: p.is_bw(),
            target_print: p.info.target_print.clone(),
            development_times_min: p.data.development_time.clone(),
        });
    }
    stocks.sort_by(|a, b| {
        (a.kind == StockKind::Paper, &a.display_name).cmp(&(b.kind == StockKind::Paper, &b.display_name))
    });
    Ok(stocks)
}

fn ms(since: Instant) -> f64 {
    since.elapsed().as_secs_f64() * 1000.0
}
