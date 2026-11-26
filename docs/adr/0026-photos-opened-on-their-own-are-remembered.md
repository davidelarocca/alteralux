# ADR-0026: Photos opened on their own are remembered

- Status: Accepted
- Date: 2026-11-26

## Context

A photo opened from the Finder, the Open panel or a drop, outside the library's folders, went only to
the strip: developing a photo of a folder replaced the strip, and the photo could not be found in the
app again. The roadmap left a sidebar entry for them open (step 6); the user chose it on 2026-11-26 and
agreed to the plan below.

The app is sandboxed with `files.user-selected.read-write`: such a photo can be read and written (its
adjustments go into it), and a security-scoped bookmark of it gives it back at the next launch, but its
folder is not given, so the photo cannot be renamed, duplicated, moved or put in the Trash from there.

## Decision

- `OpenedPhotos` (AlteraluxKit) remembers each photo opened outside the library's folders with a
  bookmark (`Library/opened-photos.plist`, beside the folders), in the order opened; one that cannot be
  found at launch is forgotten.
- The sidebar shows **Opened Photos** above the folders while there are any, with their count. The grid
  shows them as a folder's photos (`LibraryPlace.opened`), with the same filters, order and strip.
- A photo in a folder of the library never goes there; adding the folder that holds one takes it out.
- Their menu and the selection bar leave out Move to, Duplicate, Rename and Move to Trash. Remove from
  Opened Photos, and Clear Opened Photos on the entry, forget them; the files stay.

## Alternatives considered

| Option | Why not |
|---|---|
| Ask for the photo's folder to give the missing actions | A panel for each photo opened; adding the folder to the library does it, and takes the photo there |
| Remember them for the session only | The entry would be empty at each launch, and the photo lost again |
| Offer the actions and report the failure | Commands that always fail |

## Consequences

- The library is no longer empty with photos opened and no folder: the way back in the toolbar shows,
  and the app opens on them at launch.
- The menus of the strip and of the photo being developed are unchanged for these photos.
