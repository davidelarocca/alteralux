# ADR-0013: A workflow is a recipe and the files it writes, kept beside the recipes

- Status: Accepted
- Date: 2026-11-21

## Context

On 2026-11-21 the user asked that recipes and the workflows used from the Finder and Shortcuts be
"managed in a smart way and linked": no two lists to keep in step by hand. Step 10 of the roadmap brings
them: developing photos with a recipe and writing them as files, from the app now and from the Finder
and Shortcuts next. A workflow had to be defined before either: what it holds, how it stays linked to
its recipe, where it is kept, and what it does to the photos it develops.

A probe app showed that, without a developer team, an extension cannot share files with the app (App
Groups need a provisioning profile), so the Finder hands the photos to the app, which reads the
workflows itself. The sandbox lets the app write only where the user granted it: a folder chosen once
must be remembered with a security-scoped bookmark.

## Decision

- A workflow is a name, the id of a recipe, the options of an export (format, color profile, quality,
  size, metadata) and a destination: a folder of a given name beside each photo, or one folder the user
  chose, kept as a security-scoped bookmark (`FolderBookmark`).
- It names its recipe by id: renaming a recipe carries to its workflows. Deleting a recipe deletes its
  workflows, and the confirmation names them first. A workflow belongs to the recipe it was made for.
- Workflows are kept by the app like recipes, one JSON file each with a format version, in a folder of
  their own beside the recipes'. Both go through one generic store (`NamedItemStore`); the recipes' files
  keep their format.
- Developing photos with a workflow only writes files: each photo is developed with the recipe given to
  its own adjustments, as giving the recipe would (its white balance, lens correction and frame stay its
  own; a recipe that adapts meters each photo), and the photo keeps its adjustments as they were. The
  user chose this on 2026-11-21: a workflow is an export, not an edit.
- One window, Recipes and Workflows, manages both: the recipes in a list, and the recipe chosen with its
  workflows. The same export options are drawn by one view in the export sheet and in a workflow.
- In the app, the selected photos of the library are developed with a workflow from the selection's bar
  and a photo's menu, through the export sheet, its progress and its question about files already there.

## Alternatives considered

- **A workflow holding a copy of its look**: it would not follow a recipe changed later, and the user
  would keep two lists in step: what they asked not to have.
- **Photos receiving the recipe as they are developed**: a Finder action would change photos the user
  only meant to export; declined by the user.
- **Keeping recipes and workflows in one file**: one broken file would cost all of them, and a rename
  would rewrite everything; one file each keeps the recipes' rule.
- **A workflow that outlives its deleted recipe**: it would develop with nothing, or with a look no
  longer listed anywhere.

## Consequences

- The Finder's Services entry and the Shortcuts action of the next part read the same store, by id.
- A folder chosen for a workflow can be moved or deleted: the bookmark follows a moved folder, and a
  deleted one is named in an alert, with nothing written.
- Workflows cannot be reordered, nor their deletion undone, like recipes.
