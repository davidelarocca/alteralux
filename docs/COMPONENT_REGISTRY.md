# Component registry

One entry per shared component or behavior. Updated in the same change as the code, never later.
Read this before adding any UI element.

Checked at the end of every turn that changes code: each File must exist and declare the Name, IDs and
names are unique, a Retired ID is no longer under Components. File holds paths from the repository root,
comma-separated. Write a literal pipe inside a cell as `\|`. Keep the column headers.

## Components

| ID | Name | Purpose | Use when | Don't use when | API entry point | File | Used by | Tests |
|---|---|---|---|---|---|---|---|---|
| UI-001 | ParameterSlider | Labelled slider with its value, drawn as a thin track that fills from the default value to the current one. Takes the keyboard focus: arrows move it one step, Delete or a double-click resets it | Adjusting one numeric parameter | Choosing among a few named options (use a `Picker`) | `ParameterSlider(_:value:in:step:defaultValue:fractionDigits:showsSign:)` | apple/DesignSystem/Sources/DesignSystem/Components/ParameterSlider.swift | InspectorView | previews, snapshots, keyboard |
| UI-002 | ThumbnailCell | Photo thumbnail with a selection outline and a placeholder | Showing a photo in a strip or grid | Showing the photo itself (use the viewer) | `ThumbnailCell(image:isSelected:)` | apple/DesignSystem/Sources/DesignSystem/Components/ThumbnailCell.swift | FilmstripView | previews, snapshots |
| UI-003 | StatusBadge | Short status label over content | Saying which rendering is on screen | Anything the user can click | `StatusBadge(_:)` | apple/DesignSystem/Sources/DesignSystem/Components/StatusBadge.swift | PhotoStage | previews, snapshots |

## Internal

Views, modifiers and styles in the design system that are not meant for reuse by features (galleries,
building blocks of a registered component). Listed here so they are not reported as missing.

| Name | Why not registered |
|---|---|
| GalleryView | The visual inventory of the design system, shown from previews |
| SliderTrack | The drawn track of `ParameterSlider`: private to its file |

## To consolidate

Duplicates or near-duplicates found in the code that still need to be merged into a shared component.

| Element | Locations | Differences | Plan |
|---|---|---|---|

## Retired

Components removed or replaced, with what replaced them.

| ID | Replaced by | Date |
|---|---|---|
