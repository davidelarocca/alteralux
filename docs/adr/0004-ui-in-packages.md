# ADR-0004: Keep the screens and the design system in Swift packages

- Status: Accepted
- Date: 2026-11-19

## Context

The app is sandboxed. A test hosted by a sandboxed app cannot read the source tree, so layout contracts,
screenshots and snapshot tests cannot run there. Raw visual values scattered in feature code drift as the
interface grows.

## Decision

- `apple/DesignSystem` is a local package with the tokens and the shared components. It is the only
  place for raw visual values and depends on nothing app-specific.
- The app model and the screens live in the `SpektrafilmUI` target of the `apple/SpektrafilmKit` package.
- The app target is a shell: the `@main` scene, the resources and the entitlements.
- `docs/architecture-contracts.json` lists the dependencies each target may have.

## Alternatives considered

| Option | Why not |
|---|---|
| Keep the views in the app target | Their tests would need a sandboxed host and could not read the contracts |
| A design system folder inside the app target | No package boundary, no package tests |

## Consequences

- `swift test` builds and tests the whole interface without Xcode, and the end-of-turn check runs it.
- Types the app shell uses (`AppModel`, `MainWindow`, `SpektrafilmCommands`) are `public`.
- Strings in package views are looked up in the app's string catalog
  (`apple/Spektrafilm/Resources/Localizable.xcstrings`): a new string needs its entry there.
