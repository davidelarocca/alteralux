# ADR-0003: Generate the Xcode project with XcodeGen

- Status: Accepted
- Date: 2026-11-19

## Context

An Xcode project file is large, changes on almost every edit and merges badly. The app target is small:
most code lives in Swift packages, which need no project file at all.

## Decision

Describe the project in `apple/project.yml` and generate `apple/Alteralux.xcodeproj` with a pinned,
checksummed XcodeGen release (`scripts/bootstrap.sh`). The generated project is not committed.

Code signing and hardened runtime settings live in `apple/Alteralux/Signing.xcconfig`, a tracked file,
so a change to them is visible in review and to the checks that watch security settings.

## Alternatives considered

| Option | Why not |
|---|---|
| Commit the Xcode project | Noisy diffs and merge conflicts, for a target that holds one Swift file |
| A Swift package only, without an app target | App extensions, entitlements and the sandbox need an Xcode project |

## Consequences

- After adding a file to the app target (not to a package), regenerate the project:
  `scripts/bootstrap.sh --skip-engine`. `scripts/verify.sh` does it when the project is stale.
- Tools that read build settings from a committed project file do not see them here; that is why the
  security settings are in the `.xcconfig`.
