//! Hands the bridge the version of the upstream engine it is built with.
//!
//! Cargo tells a crate its own version, not its dependencies'. The upstream
//! engine is a path dependency (the `vendor/spektrafilm-rs` submodule), so its
//! version is read from its workspace manifest and passed to the crate as
//! `SPEKTRAFILM_VERSION`.

use std::path::Path;

fn main() {
    let manifest = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../vendor/spektrafilm-rs/Cargo.toml");
    println!("cargo:rerun-if-changed={}", manifest.display());
    let text = std::fs::read_to_string(&manifest)
        .unwrap_or_else(|error| panic!("cannot read {}: {error}", manifest.display()));
    let version = workspace_version(&text).unwrap_or_else(|| {
        panic!(
            "no version under [workspace.package] in {}",
            manifest.display()
        )
    });
    println!("cargo:rustc-env=SPEKTRAFILM_VERSION={version}");
}

/// The `version = "…"` of the `[workspace.package]` table.
fn workspace_version(manifest: &str) -> Option<String> {
    let mut in_table = false;
    for line in manifest.lines().map(str::trim) {
        if line.starts_with('[') {
            in_table = line == "[workspace.package]";
            continue;
        }
        if !in_table {
            continue;
        }
        let Some((key, value)) = line.split_once('=') else {
            continue;
        };
        if key.trim() == "version" {
            let version = value.trim().trim_matches('"');
            return (!version.is_empty()).then(|| version.to_string());
        }
    }
    None
}
