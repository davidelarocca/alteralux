# Component registry

One entry per shared component or behavior. Updated in the same change as the code, never later.
Read this before adding any UI element.

Checked at the end of every turn that changes code: each File must exist and declare the Name, IDs and
names are unique, a Retired ID is no longer under Components. File holds paths from the repository root,
comma-separated. Write a literal pipe inside a cell as `\|`. Keep the column headers.

## Components

| ID | Name | Purpose | Use when | Don't use when | API entry point | File | Used by | Tests |
|---|---|---|---|---|---|---|---|---|
| UI-001 | ParameterSlider | The system slider with its title and value above it. It fills from the default value to the current one. A value in the thousands is written without a separator (a temperature: 5250). Disabled, its title and value are dimmed. Takes the keyboard focus: arrows move it one step, Delete or a double-click resets it. With `isOn` it has a switch on its row, flipped by Space; with `.labelsHidden()` only the slider is drawn | Adjusting one numeric parameter | Choosing among a few named options (use a `Picker`) | `ParameterSlider(_:value:in:step:defaultValue:fractionDigits:showsSign:isOn:)` | apple/DesignSystem/Sources/DesignSystem/Components/ParameterSlider.swift | InspectorView, ZoomControls | previews, snapshots, keyboard |
| UI-002 | ThumbnailCell | Photo thumbnail with a selection outline and a placeholder. In a strip it has one size and the photo fills it; the library's grid gives each one the size of its photo's own shape, so an upright one is not cut and none sits in empty bands | Showing a photo in a strip or grid | Showing the photo itself (use the viewer) | `ThumbnailCell(image:isSelected:size:showsWholePhoto:)` | apple/DesignSystem/Sources/DesignSystem/Components/ThumbnailCell.swift | FilmstripView, LibraryGrid | previews, snapshots |
| UI-003 | StatusBadge | Short status label over content | Saying which rendering is on screen | Anything the user can click | `StatusBadge(_:)` | apple/DesignSystem/Sources/DesignSystem/Components/StatusBadge.swift | PhotoStage | previews, snapshots |
| UI-004 | InspectorSection | The system's collapsible section of a form. Collapsed, it shows the values of the controls it hides beside its title | Grouping the controls of a form under a title the user can collapse | A group that is always open (use a `Section`), or outside a `Form` | `InspectorSection(_:isExpanded:summary:content:)` | apple/DesignSystem/Sources/DesignSystem/Components/InspectorSection.swift | InspectorView | previews, snapshots |
| UI-005 | HeadingButton | The heading of a pane: a line of context over a name, with the mark of a pop-up choice. A button that opens the list to change what the pane is about | The one thing a pane is about, when it can be changed (the film) | A choice among a few options (use a `Picker`) | `HeadingButton(caption:title:action:)` | apple/DesignSystem/Sources/DesignSystem/Components/HeadingButton.swift | InspectorView | previews, snapshots |
| UI-006 | FilmEmblem | The small emblem of a film: a ground, a band and the speed, in two of the emblem inks. Decoration, hidden from assistive technologies | Telling films apart at a glance in a list | Showing how a film renders (that is the photo) | `FilmEmblem(ground:band:label:)` | apple/DesignSystem/Sources/DesignSystem/Components/FilmEmblem.swift | FilmPicker | previews, snapshots |
| UI-007 | FormSheet | The one shape of a sheet, drawn after the system's alert: a title in bold, a line of explanation, the system's grouped form, and wide round buttons side by side, the default one last. Return presses the default button, Escape the other. Without a default button it shows something going on, with the one button that stops it | Asking the user for options before acting, or showing a progress they can stop | A question with a yes or no answer, a name to type, or the confirmation of something that cannot be undone (use the system's alert or confirmation dialog) | `FormSheet(_:message:confirm:cancel:content:)` with `SheetAction(_:isEnabled:action:)` | apple/DesignSystem/Sources/DesignSystem/Components/FormSheet.swift | ExportSheet | previews, snapshots |
| UI-008 | FloatingBar | A bar of actions that floats over content near its bottom edge: a round-ended panel of the system's material with a soft shadow, as wide as what it holds. Its buttons and menus are the system's, drawn round | The actions on what is selected, shown while something is selected | Actions that are always there (use the toolbar), or a message (use an alert) | `FloatingBar(content:)` | apple/DesignSystem/Sources/DesignSystem/Components/FloatingBar.swift | LibrarySelectionBar | previews, snapshots |

## Internal

Views, modifiers and styles in the design system that are not meant for reuse by features (galleries,
building blocks of a registered component). Listed here so they are not reported as missing.

| Name | Why not registered |
|---|---|
| GalleryView | The visual inventory of the design system, shown from previews |

## To consolidate

Duplicates or near-duplicates found in the code that still need to be merged into a shared component.

| Element | Locations | Differences | Plan |
|---|---|---|---|

## Retired

Components removed or replaced, with what replaced them.

| ID | Replaced by | Date |
|---|---|---|
