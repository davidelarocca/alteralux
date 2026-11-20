# ADR-0005: Organize photos through the Finder, with no catalogue of the app's own

- Status: Accepted
- Date: 2026-11-20

## Context

The app needs a way to browse a shoot, choose photos and do light organizing before version 1.0. The
vision says photos stay where they are and that organizing must never be a requirement for developing
a photo. Photo applications usually answer this with a catalogue: a database of imported photos, albums
and tags that exists only inside the application and must be kept in step with the disk.

## Decision

- The library shows the folders the user adds, as they are on disk. There is no import and no database
  of photos.
- Moving, copying and renaming act on the real files.
- Tags are the Finder's tags, stored on the files.
- There are no albums or collections that exist only in the app.
- Discarding a photo marks it and hides it; the file goes to the Trash only when the user empties the
  discarded photos.
- What the app must remember about a photo (its adjustments, the "discarded" mark) is kept so that it
  follows the file. Where exactly is an open question in `docs/VISION.md`.

## Alternatives considered

| Option | Why not |
|---|---|
| A catalogue with import, albums and its own tags | A second source of truth to keep in step with the disk; it breaks when files move in the Finder |
| Virtual albums on top of the Finder's folders | They need the same store, for a need the Finder's tags already cover |
| No browsing at all, single files only | A shoot of hundreds of photos cannot be chosen from an Open panel and a strip |

## Consequences

- What the user sees in the app is what is on disk, and what they do in the Finder shows in the app.
- A photo cannot be in two places without a copy. Tags are the way to group across folders.
- The sandbox gives access only to the folders the user adds: each one is added once and remembered
  with a security-scoped bookmark.
- Tags are limited to what the Finder offers: names and seven colors, no hierarchy.
- The app has to notice changes made on disk while it is open.
