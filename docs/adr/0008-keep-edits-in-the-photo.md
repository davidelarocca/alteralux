# ADR-0008: Keep a photo's adjustments in the photo itself

- Status: Accepted
- Date: 2026-11-20

## Context

Adjustments were lost when the app quit. They have to be kept, and
[ADR 0005](0005-organize-through-the-finder.md) asks that what the app remembers about a photo follows
the file when it is moved in the Finder, with no catalogue of the app's own. The vision left the place
open: a file beside the photo, extended attributes, or a store of the app's.

The app is sandboxed with access to the files the user selects, read and write. What that allows was
tried inside the built app on 2026-11-20:

- a photo the user opened can be written, and takes an extended attribute, also when it was opened from
  the Finder with the app declared as a viewer of its type;
- a file beside an opened photo cannot be created: the sandbox gives access to the photo, not to its
  folder. A sidecar is possible only inside a folder the user adds (the library, roadmap step 6) or by
  declaring related items in `Info.plist`;
- a file the user never opened cannot be touched.

An extended attribute leaves the pixels and the modification date alone. The Finder keeps it when the
photo is moved, renamed, duplicated or archived (tried: `cp`, a move, a Finder duplicate, a zip made
and opened with `ditto`). It is lost on services and disks that do not carry extended attributes
(Dropbox and the like, mail, some network shares).

## Decision

- A photo's adjustments are written into the photo, as the extended attribute
  `io.github.davidelarocca.alteralux.edit#S`: a JSON object with a format version and the
  `DevelopSettings`. The `#S` suffix asks the system to keep it when the file is synced.
- A photo that cannot be written (a read-only disk, a locked card) has its adjustments kept in the
  app's Application Support folder, in a file named after the photo's path. The first time the photo
  can be written they move into it.
- There is no Save command. The adjustments are kept when they have stood still for a moment, when
  another photo is selected and when a photo leaves the strip. A photo that was only looked at is not
  written.
- `DevelopSettings` reads what any earlier version saved: a value that is missing takes its default.
  Adjustments saved by a later format version are left alone: this version cannot read them, so it
  does not replace them, and keeps its own for that photo in the app's folder.
- Undo and redo are the window's `UndoManager`: one step per change (a whole drag, a film chosen, a
  reset), not per value. They are not kept between launches.

`EditStore` (AlteraluxKit) does the reading and writing; `EditHistory` (AlteraluxUI) decides when and
registers the undo steps.

## Alternatives considered

| Option | Why not |
|---|---|
| A sidecar file beside the photo | The sandbox forbids it for single opened photos; it can be added for the library's folders, for people who sync through services that drop attributes |
| A store of the app's as the main place | The adjustments would stay behind when the photo moves to another disk or Mac: against ADR 0005 |
| Writing into the photo's metadata (XMP inside the file) | It rewrites the original file, which the app must never do |
| A history of its own instead of the window's `UndoManager` | The Edit menu, its shortcuts and the undo of text fields are the system's: a second history would have to replace them |

## Consequences

- A photo opened again, on this Mac or on another after a copy that keeps attributes, shows the
  adjustments it was left with.
- The app writes to the user's originals, though not to their contents. Backup tools that watch
  attribute changes see the file as changed.
- Adjustments do not travel through services that drop extended attributes: the sidecar is the answer
  when the library exists.
- The "discarded" mark of the library can be kept the same way.
- A change made in the last tenth of a second before quitting is not kept.
- Tests of the app model keep the fallback folder out of the user's Library: a model given the
  engine's data folder, as tests do, uses a temporary folder unless told otherwise.
