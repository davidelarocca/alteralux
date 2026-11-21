# ADR-0014: The Finder and Shortcuts hand photos to the app, which develops them with a workflow

- Status: Accepted
- Date: 2026-11-21

## Context

Step 10 of the roadmap brings workflows ([ADR 0013](0013-workflows-are-recipes-with-their-files.md))
to the Finder and to Shortcuts. A probe app, on 2026-11-21, showed what the sandbox allows without a
developer team: an extension cannot read the app's workflows (App Groups need a provisioning profile);
a Finder Quick Action is hidden until the user enables it; an entry in the Services menu, declared in
the app's Info.plist, shows in the Finder's right-click menu and hands the selected files to the app,
which can read them but not write beside them. Nothing written beside an original is allowed until the
user grants its folder.

## Decision

- The Finder: "Develop with alteralux…" is an `NSServices` entry in `apple/Alteralux/Info.plist`, for the
  kinds of photo the app opens; no extension, no new entitlement. The user approved this change to the
  protected file on 2026-11-21. Its title is translated in `ServicesMenu.xcstrings`.
- The app receives the photos in `OpenFilesDelegate` (the services provider) and shows the sheet that
  develops photos with a workflow, the one the library uses, over the main window, which comes back if
  it was closed. The photos are not added to the library or the strip.
- A workflow that writes beside the originals asks, for each folder outside the library and not granted
  before, the user's leave with the system's open panel on that folder. The folders granted are kept as
  security-scoped bookmarks (`AppModel.writableFolders`, the same store as the library's folders) and
  never asked for again.
- Shortcuts: "Develop Photos" is an App Intent in the app target, with a `WorkflowEntity` found by id,
  so a renamed workflow stays chosen. It runs in the app through the same `AppModel`
  (`AppDependencyManager`), starting the engine when it is not running. It gives back the files written,
  as data. A workflow with a folder of its own writes there too; one that writes beside the originals
  writes only for the shortcut, because Shortcuts often hands over copies.

## Alternatives considered

| Option | Why not |
|---|---|
| A Finder Quick Action extension | Cannot read the workflows without an App Group, needs a team; hidden until enabled |
| A small window of its own for the Finder | A second window beside the main one, which opens anyway; the sheet is the one the library uses, with its progress and question about files already there |
| Adding the photos' folder to the library | Changes what the library shows for a one-off action |
| Writing beside the originals from Shortcuts | The files are often copies in a temporary folder; the result would be lost or fail without a word |

## Consequences

- The first use in a folder outside the library asks once; moving the folder keeps the grant, through the
  bookmark.
- The Shortcuts action loads the photos it gives back into memory: fine for photos, not for hundreds of
  large TIFFs at once.
- The Services entry and the intent are checked in the built app; the Finder's own menu and the
  Shortcuts editor are checked by the user.
