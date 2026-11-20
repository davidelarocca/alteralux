# Vision

What alteralux for macOS is meant to become. `docs/ROADMAP.md` says in which order; this document says
where it is going and what "finished" means. Until 2026-11-20 the app was called spektrafilm for
macOS, after the upstream project whose film model it uses; it has had a name of its own since then. Agreed on 2026-11-19 and revised on 2026-11-20 after the
mockups of the whole interface, and again the same day when the first of it was seen in the running
app; a change of direction is a change to this file.

## In one paragraph

A developing bench for digital photos. You open your photos, choose a film and a paper, and get the look
the real materials would give, computed by a spectral model of film instead of a color filter. It should
feel like a darkroom: quiet, dark, precise, with the photo as the only thing that has color. And it
should respect a photographer's time: a recipe chosen once develops a whole shoot, adapted to each
photo, without hours spent on single frames.

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
   is told. It keeps no catalogue of its own: its folders are the Finder's folders and its tags are the
   Finder's tags ([ADR 0005](adr/0005-organize-through-the-finder.md)).
5. **A Mac app.** Standard behavior wherever a standard exists: menus, shortcuts, undo, drag and drop,
   keyboard access, VoiceOver, the sandbox. The character comes from proportion, type and restraint, not
   from custom chrome.
6. **Minutes, not hours.** Whatever is done to one photo can be done to many: recipes are saved, applied
   in batches, and adapted to each photo.

## The finished product

- **Develop.** Film and paper, exposure, print filters, grain, halation, sharpening, white balance, crop
  and straighten, comparison with the original. Edits are kept for each photo between launches, with
  undo and redo.
- **Recipes.** A set of adjustments saved under a name ("Recipe" in the interface, in every language),
  applied to one photo or to many, copied from one photo to others. Applying a recipe is one edit: one
  undo takes it back whole.
- **Adaptive recipes.** A recipe can be made adaptive, with two options under it: adapt to the exposure
  and adapt to the temperature. Before the recipe is applied, a photo that starts too far off is
  corrected, so a bright frame and a dark one, a warm one and a cold one, land where the recipe
  intends. Exposure starts from the engine's automatic metering; temperature from an automatic white
  balance computed on the Mac. The interface says "adaptive": it does not promise AI while there is no
  model behind it.
- **Camera and lens corrections.** Color profiles for cameras and corrections for lenses (distortion,
  vignetting, chromatic aberration), chosen automatically from the photo's metadata, with a way to add
  one's own.
- **Batch and export.** Several photos exported in one action: format, color profile, size, destination.
  The same sheet for four photos or four hundred: a count, no list of photos, one progress indicator,
  and at the end only the photos that failed.
- **Library.** A view of the folders as they are on disk: the folders the user adds, their subfolders,
  a grid of the photos. A double-click develops a photo; the way back to the folder is always in the
  toolbar. Selecting one or more photos brings up their actions: move, copy, tag, apply a recipe,
  export, discard. Tags are the Finder's. Discarding marks a photo and hides it; the files go to the
  Trash only when the user empties the discarded ones. There are no albums or collections that exist
  only in the app. Opening single files stays possible: the library is never a requirement for
  developing a photo.
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
5. The library: the Finder's folders, the grid, the actions on a selection, tags, discard.
6. Recipes: save, apply, copy between photos, export several photos at once, adaptive.
7. Crop and straighten.
8. Camera and lens corrections.
9. Workflows from the Finder: actions for Shortcuts that develop the selected photos with a recipe and
   hand the results back for saving.
10. An icon and the notarized release.

After 1.0, in an order still to decide: the Photos integration, more of the engine's parameters.

## Visual direction

A neutral darkroom made of the system's controls: sliders, switches, pop-up buttons, collapsible
sections, lists, forms and the toolbar are macOS's own, drawn as the system draws them, with the system
typeface and numbers in tabular digits. The accent color shows only where the system puts it, on small
things: a switch that is on, the selected segment. The direction was chosen on 2026-11-20 on mockups of every step of
the roadmap (the black and red variant was set aside); the same day, seen in the running app, the
hand-drawn controls of the mockups were dropped for the system's
([ADR 0006](adr/0006-use-the-systems-controls.md)). The mockups stay the guide to what is where:

- **Sliders** are the system's and fill from their neutral point. A parameter that can be switched off
  (grain, halation) has its switch on the slider's row.
- **Inspector.** A grouped form. The film is its heading. The sections follow the path of light and can
  be collapsed; a collapsed section shows its values. The controls keep clear of the scroll bar.
- **Choosing the film.** A vertical list that scrolls, grouped by kind, with search. Each film has a
  small emblem of its own: a ground, a band and the speed, in colors suggested by the film's character.
  The emblems are original, they copy no brand's packaging. No rendered previews: they would cost a
  render per film.
- **Toolbar.** On the left the way back to the folder, then previous and next, beside the window's title
  (the file name over its film and paper). On the right undo and redo, crop, the original, Recipe and export. Icons alone wherever the icon is
  clear, always with an accessible label.
- **Zoom** controls sit under the photo on the right, above the strip: fit, 100% and a slider, whose
  neutral point is the fitted photo.
- **The strip of thumbnails** is visible by default; a setting collapses or hides it.
- **Export in progress** is drawn as a print coming up in the developer, with one count. It stays still
  with Reduce Motion.

## Ideas proposed, not decided

- **Split comparison.** A divider dragged across the photo, original on one side, developed on the other.
- **Versions.** Two or three developments of the same photo side by side (two stocks, two papers).
- **Sidecar files.** Each photo's edits in a small file beside it, so they travel with the photo and the
  Finder workflows need no database.
- **Borders.** Export with a white print border or the film's rebate.
- **Histogram and clipping warnings.**

## Open questions

- **A sidecar beside the photo.** Each photo's adjustments and its "discarded" mark are kept in the
  photo itself, as extended attributes ([ADR 0008](adr/0008-keep-edits-in-the-photo.md)). Services
  that drop extended attributes lose them: a sidecar file, possible inside the library's folders,
  is still to decide.
- **Finder tags in the sandbox.** Verified on 2026-11-20 with a probe app signed like this one: in a
  folder the user has added, tags are read and written with the access the sandbox gives, and so are
  moving, copying, the Trash and a file beside a photo. The tag menu is still to design.
- **Automatic white balance.** Which method gives the starting temperature for adaptive recipes, and
  when a photo counts as "too far off". To settle on real photos.

- **Camera and lens profiles: the source.** What Core Image already applies when decoding RAW files, and
  whether an open database of lens corrections can be used and shipped under the GPL. To verify before
  designing the feature.
- **Photos.** As far as we know, an editing extension receives a rendered image, not the RAW original
  (see `docs/ROADMAP.md`). Reading originals through PhotoKit from the app is the alternative.
