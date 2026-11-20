# ADR-0009: A recipe is a look without white balance, kept by the app

- Status: Accepted
- Date: 2026-11-20

## Context

The vision asks for recipes: a set of adjustments saved under a name, applied to one photo or to many,
and copied from one photo to others. Three things had to be settled before writing them: what a recipe
holds, where recipes are kept, and what a photo remembers of the recipe it received.

A photo's adjustments are one value, `DevelopSettings`, kept in the photo itself
([ADR 0008](0008-keep-edits-in-the-photo.md)). Two of its values describe the light of that one photo
and not a look: the temperature and the tint the RAW decoder takes as neutral
([ADR 0007](0007-decode-each-preview-at-its-size.md)). The exposure is different: with the automatic
meter on, which is the default, the engine meters each photo, and the exposure value is a correction on
top of that reading, the same for a bright frame and a dark one.

[ADR 0005](0005-organize-through-the-finder.md) forbids a catalogue of photos. Recipes are not about
any photo: they are tools the user makes, like the presets of other applications.

## Decision

- A recipe is a name and a look: every value of `DevelopSettings` but the temperature and the tint,
  which a recipe never holds. Giving a recipe to a photo replaces the photo's look and leaves its white
  balance as it is.
- Pasting the adjustments of one photo onto others follows the same rule: one rule to learn, and the
  same reason behind it.
- Recipes are kept by the app, in its Application Support folder, one JSON file per recipe with a
  format version. A file that cannot be read, or written by a later version, is left out of the list
  and left alone on disk.
- A photo keeps only the adjustments it received. It does not remember the recipe: renaming, changing
  or deleting a recipe changes no photo.
- Giving a recipe is one edit: one step of undo takes it back whole, on one photo or on many.

`Recipe` and `RecipeStore` (AlteraluxKit) hold the type and the files; `AppModel` (AlteraluxUI) applies
recipes and registers the undo steps.

## Alternatives considered

| Option | Why not |
|---|---|
| A recipe that holds the white balance too | A recipe saved on a photo taken at sunset would shift the colors of every photo it is given to. The automatic correction of the starting temperature belongs to adaptive recipes, a separate option |
| A recipe that leaves the exposure out as well | With the meter on, the exposure correction is part of the look ("a third of a stop over"), and the meter adapts it to each photo |
| A photo that points to its recipe, and follows it when the recipe changes | A change to a recipe would silently change photos already developed and exported, and a photo moved to another Mac would point to a recipe that is not there |
| Recipes in one file, or in the app's preferences | One file per recipe can be given to someone else or carried to another Mac as it is, when importing recipes is added |
| Recipes in a folder the user chooses | Needs one more permission and one more thing to set up before the first recipe; the app's folder needs neither |

## Consequences

- The same recipe gives the same look to photos taken in different light, each keeping its own white
  balance.
- To change many photos after changing a recipe, the recipe is given to them again.
- Recipes stay on the Mac they were made on until importing and exporting recipe files exists.
- Adaptive recipes (roadmap step 7, second part) add what a recipe does before it is applied; they do
  not change what a recipe holds.
