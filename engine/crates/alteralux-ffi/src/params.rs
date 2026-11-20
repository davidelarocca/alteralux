//! Parameter JSON handling: defaults, strict deep-merge and pipeline cache keys.

use serde_json::{Map, Value};
use spektrafilm_core::params::RuntimeParams;

use crate::error::EngineError;

/// The engine defaults as a JSON tree.
pub(crate) fn defaults_value() -> Value {
    serde_json::to_value(RuntimeParams::default()).expect("RuntimeParams always serializes")
}

/// Builds `RuntimeParams` from the defaults with `patch_json` deep-merged on top.
///
/// Merge rules: objects merge key by key; any other value (numbers, strings,
/// arrays, `null`) replaces the default. Unlike RFC 7386, `null` does not delete
/// a key: it sets an optional field to "none". Every key in the patch must exist
/// in the defaults, so a misspelled key is an error, not a silent no-op.
pub(crate) fn resolve(patch_json: &str) -> Result<RuntimeParams, EngineError> {
    let mut tree = defaults_value();
    let trimmed = patch_json.trim();
    if !trimmed.is_empty() {
        let patch: Value = serde_json::from_str(trimmed)
            .map_err(|e| EngineError::params(format!("not valid JSON: {e}")))?;
        if !patch.is_object() {
            return Err(EngineError::params("the parameter patch must be a JSON object"));
        }
        merge_strict(&mut tree, &patch, &mut String::new())?;
    }
    serde_json::from_value(tree).map_err(|e| EngineError::params(e.to_string()))
}

fn merge_strict(target: &mut Value, patch: &Value, path: &mut String) -> Result<(), EngineError> {
    match (target, patch) {
        (Value::Object(target), Value::Object(patch)) => merge_objects(target, patch, path),
        (target, patch) => {
            *target = patch.clone();
            Ok(())
        }
    }
}

fn merge_objects(
    target: &mut Map<String, Value>,
    patch: &Map<String, Value>,
    path: &mut String,
) -> Result<(), EngineError> {
    for (key, value) in patch {
        let len = path.len();
        if !path.is_empty() {
            path.push('.');
        }
        path.push_str(key);
        let Some(slot) = target.get_mut(key) else {
            return Err(EngineError::params(format!("unknown parameter `{path}`")));
        };
        // A sub-object can only be patched with an object (or null for an
        // optional struct); replacing it with a scalar is always a mistake.
        if slot.is_object() && !(value.is_object() || value.is_null()) {
            return Err(EngineError::params(format!("parameter `{path}` must be an object")));
        }
        merge_strict(slot, value, path)?;
        path.truncate(len);
    }
    Ok(())
}

/// Key of everything that requires rebuilding (re-calibrating) the pipeline.
///
/// `Pipeline::with_params` is only valid when these inputs are unchanged.
/// This mirrors `preview_pipeline_cache_key` in the upstream spektrafilm-rs GUI
/// (crates/spektrafilm-gui/src/main.rs); keep the two in sync when updating the
/// submodule.
pub(crate) fn pipeline_cache_key(film: &str, print: &str, params: &RuntimeParams) -> String {
    serde_json::json!({
        "film": film,
        "print": print,
        "film_dev": params.film_render.development_time,
        "print_dev": params.print_render.development_time,
        "scan_film": params.io.scan_film,
        "input_color_space": params.io.input_color_space,
        "input_cctf_decoding": params.io.input_cctf_decoding,
        "input_gamut": params.io.input_gamut_compress,
        "output_color_space": params.io.output_color_space,
        "output_gamut": params.io.output_gamut_compress,
        "settings": {
            "rgb_to_raw_method": params.settings.rgb_to_raw_method,
            "apply_hanatos2025_adaptation_window": params.settings.apply_hanatos2025_adaptation_window,
            "apply_hanatos2025_adaptation_surface": params.settings.apply_hanatos2025_adaptation_surface,
            "spectral_gaussian_blur": params.settings.spectral_gaussian_blur,
            "lut_resolution": params.settings.lut_resolution,
            "neutral_print_filters_from_database": params.settings.neutral_print_filters_from_database,
            "use_cat16": params.settings.use_cat16,
        },
        "enlarger": {
            "illuminant": params.enlarger.illuminant,
            "c_filter_neutral": params.enlarger.c_filter_neutral,
            "m_filter_neutral": params.enlarger.m_filter_neutral,
            "y_filter_neutral": params.enlarger.y_filter_neutral,
            "m_filter_shift": params.enlarger.m_filter_shift,
            "y_filter_shift": params.enlarger.y_filter_shift,
            "preflash_exposure": params.enlarger.preflash_exposure,
            "preflash_m_filter_shift": params.enlarger.preflash_m_filter_shift,
            "preflash_y_filter_shift": params.enlarger.preflash_y_filter_shift,
            "normalize_print_exposure": params.enlarger.normalize_print_exposure,
            "print_exposure_compensation": params.enlarger.print_exposure_compensation,
        },
        "exposure_compensation_ev": if params.enlarger.print_exposure_compensation {
            params.camera.exposure_compensation_ev
        } else {
            0.0
        },
    })
    .to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn empty_patch_gives_defaults() {
        let p = resolve("").unwrap();
        let d = RuntimeParams::default();
        assert_eq!(serde_json::to_value(&p).unwrap(), serde_json::to_value(&d).unwrap());
        assert_eq!(
            serde_json::to_value(resolve("{}").unwrap()).unwrap(),
            serde_json::to_value(&d).unwrap()
        );
    }

    #[test]
    fn nested_values_are_merged() {
        let p = resolve(r#"{"camera": {"exposure_compensation_ev": 1.5}, "io": {"scan_film": true}}"#)
            .unwrap();
        assert_eq!(p.camera.exposure_compensation_ev, 1.5);
        assert!(p.io.scan_film);
        // Siblings keep their defaults.
        let d = RuntimeParams::default();
        assert_eq!(p.camera.film_format_mm, d.camera.film_format_mm);
        assert_eq!(p.enlarger.illuminant, d.enlarger.illuminant);
    }

    #[test]
    fn unknown_keys_are_rejected_with_their_path() {
        let err = resolve(r#"{"camera": {"exposure_compensaton_ev": 1.0}}"#).unwrap_err();
        assert!(err.to_string().contains("camera.exposure_compensaton_ev"), "{err}");
        let err = resolve(r#"{"nope": 1}"#).unwrap_err();
        assert!(err.to_string().contains("`nope`"), "{err}");
    }

    #[test]
    fn wrong_types_are_rejected() {
        assert!(resolve(r#"{"camera": {"exposure_compensation_ev": "bright"}}"#).is_err());
        assert!(resolve(r#"{"camera": 3}"#).is_err());
        assert!(resolve("[1, 2]").is_err());
        assert!(resolve("{not json").is_err());
    }

    #[test]
    fn null_sets_optional_fields_to_none() {
        let p = resolve(r#"{"film_render": {"development_time": 7.0}}"#).unwrap();
        assert_eq!(p.film_render.development_time, Some(7.0));
        let p = resolve(r#"{"film_render": {"development_time": null}}"#).unwrap();
        assert_eq!(p.film_render.development_time, None);
    }

    #[test]
    fn cache_key_ignores_non_calibration_params() {
        let a = resolve(r#"{"film_render": {"grain": {"active": false}}}"#).unwrap();
        let b = resolve(r#"{"film_render": {"grain": {"active": true}}}"#).unwrap();
        assert_eq!(pipeline_cache_key("f", "p", &a), pipeline_cache_key("f", "p", &b));
        let c = resolve(r#"{"enlarger": {"y_filter_shift": 3.0}}"#).unwrap();
        assert_ne!(pipeline_cache_key("f", "p", &a), pipeline_cache_key("f", "p", &c));
        assert_ne!(pipeline_cache_key("f", "p", &a), pipeline_cache_key("f", "q", &a));
    }
}
