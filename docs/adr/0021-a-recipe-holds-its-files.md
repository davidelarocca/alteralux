# ADR-0021: A recipe holds the look and the files it writes; workflows go

- Status: Accepted
- Date: 2026-11-24

## Context

A recipe was a look, and a workflow a way of using it: which recipe, whether it adapted to each photo,
and the files it wrote ([ADR 0013](0013-workflows-are-recipes-with-their-files.md),
[ADR 0014](0014-finder-and-shortcuts-hand-photos-to-the-app.md)). Two lists, one window with both, and
a workflow to make before the Finder's "Develop with alteralux…" could run without a question.

The user, on 2026-11-24, after using it:

> lo scopo di una ricetta è di diventare workflow… forse dobbiamo eliminare questa distinzione?

and, about a workflow that adapts: "va a fare la stessa cosa in pratica" as the Auto switches of Shot
([ADR 0020](0020-automatic-means-automatic.md)). Shown the options, they chose one thing, the recipe,
with the files it writes; saving from the toolbar asks the name and shows the files with an "Edit…";
the Finder and Shortcuts list recipes; the workflows kept so far become recipes.

Told that a recipe then writes one kind of file, where a recipe with two workflows wrote two, they
chose to duplicate the recipe.

## Decision

- **A recipe is a look and the files it writes** (`Recipe.files`, a `RecipeFiles`): format, color
  profile, quality, size, metadata, the files' names and where they go, each of format, size, names and
  destination askable each time. Every recipe has them from the start: files the size of the original,
  named after the photo and the film, beside the photos. There are no workflows.
- **Two things are done with a recipe.** Giving it to photos changes their adjustments, as before
  ([ADR 0009](0009-recipes-are-looks-kept-by-the-app.md)). Developing photos with it writes its files
  and leaves the photos' adjustments alone, as a workflow did: from the library's selection, from the
  Finder's "Develop with alteralux…" and from the Shortcuts action "Develop Photos", which list
  recipes.
- **Adapting follows the recipe.** A recipe remembers whether the exposure and the white balance were
  on Auto when it was saved (`look.autoExposure`, `look.autoWhiteBalance`). With the first, each photo
  is metered; with the second, each photo's white balance is measured in it, unless one was chosen for
  the photo by hand. Otherwise the exposure is the one saved and the white balance stays each photo's
  own: a recipe still never carries a temperature or a tint. The "Adapts to each photo" switch is gone.
- **The same look in other files is a duplicate.** "Duplicate…" in the recipes window opens a copy to
  rename and to give files of its own. A recipe's look does not change after it is saved, so two
  recipes made this way cannot drift apart.
- **Saving** from the toolbar is a sheet (`RecipeEditor`): the name, the two Auto rows, the files in a
  line with "Edit…", which opens them in place. The same sheet changes a recipe (name and files) and
  names a duplicate. The window is "Recipes".
- **From the Finder**: with one recipe that asks nothing, the photos are developed at once; with
  several, or one that leaves settings open, the panel asks which and what is open. The panel no longer
  makes anything: there is always something ready to use once a recipe exists.
- **What was kept**: at the first launch each workflow becomes a recipe with the look of its recipe and
  its own name, files and id (`WorkflowMigration`), so a shortcut that chose it still finds it; one
  that adapted has both Auto on; one with the name of its recipe takes the recipe's place.

## Alternatives considered

| Option | Why not |
|---|---|
| Recipes and workflows as two things (ADR 0013, 0014) | What the user asked to remove: a second list to make and keep before a look can be used from the Finder |
| A recipe with several sets of files | Offered on 2026-11-24 and not chosen: it brings the distinction back inside the recipe, and the Finder would ask which set |
| "Ask each time" as the only way to a second format | The Finder's entry stops being invisible for that recipe; kept as an option, not as the answer |
| An "Adapts to each photo" switch on the recipe | It would say again, in other words, what the two Auto switches already said when the look was saved |
| A recipe on Auto overriding a white balance chosen by hand | The rule of [ADR 0011](0011-recipes-adapt-to-each-photo.md) stays: a choice made for a photo is the photo's |

## Consequences

- Supersedes [ADR 0013](0013-workflows-are-recipes-with-their-files.md) (the workflow as a thing of its
  own, its store, the window of both) and the parts of
  [ADR 0014](0014-finder-and-shortcuts-hand-photos-to-the-app.md) that describe a workflow and the
  panel that makes one. What ADR 0014 says of the Services entry, of staying out of sight, of never
  replacing a file beside the photos, of the permission to write and of Shortcuts stands, with "recipe"
  for "workflow".
- A recipe saved on Auto and given in the app now turns the automatic white balance on for a photo
  whose white balance was not chosen by hand; before, a recipe given in the app never did.
- With several recipes the Finder always asks which one: before, one workflow among many recipes
  developed without a question.
- A recipe's files can be changed after saving; its look cannot. A look to change is saved again.
- The Shortcuts action's parameter is a recipe: a shortcut made before has to choose it again.
- The Services entry keeps its message name, `developWithWorkflow`, in `apple/Alteralux/Info.plist`,
  which is protected: it is a name the user never sees.
