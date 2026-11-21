# ADR-0014: A workflow is how a recipe is used, run from the Finder's right-click menu and from Shortcuts

- Status: Accepted
- Date: 2026-11-21

## Context

Step 10 of the roadmap brings workflows ([ADR 0013](0013-workflows-are-recipes-with-their-files.md))
to the Finder and to Shortcuts. A first version opened a sheet in the app for the photos sent from the
Finder; trying it, the user found it not immediate, and said what recipes and workflows are to be:

> un flusso è un modo di sfruttare una ricetta. la ricetta è l'insieme delle modifiche impostate in una
> foto, che può essere applicata in modo adattivo all'interno di un flusso… nel flusso si seleziona il
> tipo di export di base, come sarà la foto, che tipo di renaming, che tipo di file, dimensioni etc e dove
> la foto sarà sviluppata (se nella stessa cartella della foto stessa, se in una sotto cartella o in una
> cartella preimpostata uguale per tutte) … direttamente dal Finder, premendo tasto destro.

A probe app, on 2026-11-21, showed what the sandbox allows without a developer team: an extension
cannot read the app's workflows (App Groups need a provisioning profile); a Finder Quick Action is
hidden until the user enables it; an entry in the Services menu, declared in the app's Info.plist,
shows in the Finder's right-click menu and hands the selected files to the app, which can read them
but not write beside them until the user grants their folder. Services entries are fixed in
Info.plist: one entry per workflow is not possible without an extension.

## Decision

- **A recipe is a look**, the adjustments of a photo saved under a name. Whether a photo starts from its
  own light (adapting) is no longer the recipe's: a recipe given in the app is given as it is.
- **A workflow is how a recipe is used**: which recipe, whether it adapts to each photo (on for a new
  workflow), the files (format, color profile, quality, size, metadata), their names (the photo's name
  and the film, the photo's name, or the photo's name and a text) and where they go: beside the photos,
  in a folder of a name beside them, or in one folder. A new workflow writes beside the photos.
- **A workflow can leave settings open**: its format, size, file names and destination can each be
  "asked each time". Settled ones are never asked.
- **The Finder**: "Develop with alteralux…" is an `NSServices` entry in `apple/Alteralux/Info.plist`, for
  the kinds of photo the app opens; no extension, no new entitlement (approved by the user on
  2026-11-21). It is invisible when the workflow says everything: with one workflow that leaves nothing
  open, the photos are developed and the files appear. Otherwise a small panel at the center of the
  screen (`FinderPanel`, a non-activating panel drawn as the app's sheets) asks only what is open:
  which workflow, when there are several, and the settings the chosen one leaves open (one folder is
  chosen with the system's panel, as Save As does); the answers are offered first next time. With no
  workflow, the panel asks the few choices that make one, and keeps it. With no recipe, or when
  something goes wrong, the system's alert says so. The app's window never opens for it.
- **Out of sight**: started by the system for photos from the Finder (their request reaches the app
  before launching ends), the app takes no Dock icon, opens no window, and quits once the photos are
  developed. Opened by the user, it shows its main window, which no longer opens by itself at launch
  (`defaultLaunchBehavior(.suppressed)`); the app delegate holds the model from launch.
- The photos are not added to the library or the strip.
- **Beside the photos nothing is replaced**: in a photo's own folder a file of the same name may be an
  original, so the export never counts a file there as an earlier export, never takes one away, and
  never writes over a photo being developed, whatever the policy.
- **Permission**: a workflow that writes beside the photos asks, for each folder outside the library and
  not granted before, the user's leave with the system's open panel on that folder; a folder that holds
  it allows everything inside. The folders granted are kept as security-scoped bookmarks
  (`AppModel.writableFolders`, the same store as the library's folders) and never asked for again.
- **Shortcuts**: "Develop Photos" is an App Intent in the app target, with a `WorkflowEntity` found by
  id, so a renamed workflow stays chosen. It runs in the app through the same `AppModel`
  (`AppDependencyManager`), starting the engine when it is not running. It gives back the files written,
  as data. A workflow with one folder of its own writes there too; one that writes beside the photos
  writes only for the shortcut, because Shortcuts often hands over copies.

## Alternatives considered

| Option | Why not |
|---|---|
| A Finder Quick Action or Finder Sync extension listing each workflow | Cannot read the workflows without an App Group, which needs a developer team; to be done once the app is signed with one |
| A sheet in the app for the photos sent from the Finder | The first version: the user found it not immediate |
| A menu of workflows at the pointer | The second version: it opened wherever the pointer was by then, once over the Dock; the user wants it invisible, or a small panel at the center |
| Telling the Finder's launch from the launch event (`keyAELaunchedAsServiceItem`, `NSApplicationLaunchIsDefaultLaunchKey`) | Measured on 2026-11-21: no launch event reaches the delegate, and the launch is reported as a default one |
| Adapting kept in the recipe | The user sees adapting as a way of using a recipe, chosen with the files and their place |
| Adding the photos' folder to the library | Changes what the library shows for a one-off action |
| Writing beside the originals from Shortcuts | The files are often copies in a temporary folder; the result would be lost or fail without a word |

## Consequences

- Supersedes the part of [ADR 0011](0011-recipes-adapt-to-each-photo.md) that made adapting a recipe's:
  a recipe file that still says so is read without it, and a workflow kept before reads as not adapting.
- From the Finder there is no progress on screen: the files appear as they are written; only a failure
  is shown, in the system's alert.
- The first use in a folder outside the library asks once.
- The Shortcuts action loads the photos it gives back into memory: fine for photos, not for hundreds of
  large TIFFs at once.
