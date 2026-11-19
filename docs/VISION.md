# Vision

What spektrafilm for macOS is meant to become. `docs/ROADMAP.md` says in which order; this document says
where it is going and what "finished" means. Agreed on 2026-11-19; a change of direction is a change to
this file.

## In one paragraph

A developing bench for digital photos. You open your photos, choose a film and a paper, and get the look
the real materials would give, computed by a spectral model of film instead of a color filter. It should
feel like a darkroom: quiet, dark, precise, with the photo as the only thing that has color. And it
should respect a photographer's time: a look chosen once develops a whole shoot, adapted to each photo,
without hours spent on single frames.

## Who it is for

Photographers who shoot digital and want the rendering of film: people who know what Portra or Velvia
look like and want that, not an approximation. They already keep their photos somewhere (folders, Photos)
and do not want another library to maintain.

## Principles

1. **The look is the engine's.** The app never restyles what the film model produces. Everything the app
   adds happens before the film (decoding, white balance, corrections of camera and lens, framing) or
   after it (export).
2. **The photo is the only color.** The interface is neutral and dark, so nothing saturated sits next to
   the picture and skews the judgment of its colors. An accent color is used sparingly, never on large
   areas beside the photo.
3. **Immediate.** Moving a control changes the picture as the hand moves. A wait that the user can see
   is a defect, not a cost of quality.
4. **Photos stay where they are.** The app works on files in place and writes next to them or where it
   is told. Organizing is optional and light.
5. **A Mac app.** Standard behavior wherever a standard exists: menus, shortcuts, undo, drag and drop,
   keyboard access, VoiceOver, the sandbox. The character comes from proportion, type and restraint, not
   from custom chrome.
6. **Minutes, not hours.** Whatever is done to one photo can be done to many: looks are saved, applied in
   batches, and adapted to the exposure of each photo.

## The finished product

- **Develop.** Film and paper, exposure, print filters, grain, halation, sharpening, white balance, crop
  and straighten, comparison with the original. Edits are kept for each photo between launches, with
  undo and redo.
- **Looks.** A set of adjustments saved under a name, applied to one photo or to many, copied from one
  photo to others.
- **Adaptive application.** Applying a look does not give every photo the same numbers: the starting
  exposure of each photo is measured, so a bright frame and a dark one both land where the look intends.
  The engine's automatic metering is the starting point.
- **Camera and lens corrections.** Color profiles for cameras and corrections for lenses (distortion,
  vignetting, chromatic aberration), chosen automatically from the photo's metadata, with a way to add
  one's own.
- **Batch and export.** Several photos exported in one action: format, color profile, size, destination.
- **Light organization.** Folders as they are on disk, and collections for those who want them. Simple,
  optional, pleasant to use; never a requirement for developing a photo.
- **From the Finder.** Select photos, choose a workflow the user has defined (a look, the automatic
  corrections, an export format, a destination such as a subfolder beside the originals), and get the
  developed files without opening the app. The app provides the actions for Shortcuts; the shortcut the
  user builds from them saves the files, so the app needs no access to the folder.
- **With Photos.** For people whose archive is the Photos library: developing photos from it and saving
  back to it.
- **Distribution.** A signed and notarized download from the project's releases. The project is GPLv3,
  so the Mac App Store is excluded (ADR 0001).

## Version 1.0

What the first public version needs on top of what exists today:

1. An interface that follows the principles above: the inspector and its controls redrawn.
2. Editing that feels immediate (principle 3), measured and not assumed.
3. White balance.
4. Edits that persist, with undo and redo.
5. Looks: save, apply, copy between photos, export several photos at once, with adaptive application.
6. Crop and straighten.
7. Camera and lens corrections.
8. Workflows from the Finder: actions for Shortcuts that develop the selected photos with a look and hand
   the results back for saving.
9. An icon, a decision on the name, and the notarized release.

After 1.0, in an order still to decide: collections, the Photos integration, more of the engine's
parameters.

## Visual direction

A darkroom, close to standard macOS. Under review on mockups, two variants of the same layout:

- **Neutral darkroom.** Grays and white only, the system typeface, thin sliders that fill from their
  neutral point, the film as the heading of the inspector.
- **Black and red.** Black surfaces, one red accent used for the selected frame, the slider needle and
  the export action, a monospaced face for numbers and labels, sliders drawn as graduated scales.

What is already settled: no saturated system accent color on the controls, sliders that show their
neutral point, and numbers set in tabular or monospaced digits.

## Ideas proposed, not decided

- **Film browser.** Choose the film by seeing the current photo developed in each stock, not from a list
  of names.
- **Contact sheet.** A shoot shown as a sheet of frames with their looks, for choosing and batch work.
- **Split comparison.** A divider dragged across the photo, original on one side, developed on the other.
- **Versions.** Two or three developments of the same photo side by side (two stocks, two papers).
- **Sidecar files.** Each photo's edits in a small file beside it, so they travel with the photo and the
  Finder workflows need no database.
- **Borders.** Export with a white print border or the film's rebate.
- **Histogram and clipping warnings.**

## Open questions

- **Camera and lens profiles: the source.** What Core Image already applies when decoding RAW files, and
  whether an open database of lens corrections can be used and shipped under the GPL. To verify before
  designing the feature.
- **Photos.** As far as we know, an editing extension receives a rendered image, not the RAW original
  (see `docs/ROADMAP.md`). Reading originals through PhotoKit from the app is the alternative.
