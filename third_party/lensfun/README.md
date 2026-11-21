# lensfun lens database

The files in `db/` are the lens database of the [lensfun](https://lensfun.github.io) project, copied
unmodified from [github.com/lensfun/lensfun](https://github.com/lensfun/lensfun) (`data/db`) at the
commit in `COMMIT`. They describe cameras and lenses and how to correct each lens's distortion,
vignetting and chromatic aberration.

**License.** The database is © the lensfun contributors and licensed under the Creative Commons
Attribution-ShareAlike 3.0 Unported license (CC BY-SA 3.0); the full text is in
`COPYING.CC_BY-SA_3.0`. It is not covered by alteralux's GPL: it is kept here as separate files,
unmodified, shipped inside the app as they are and read at run time. alteralux's own code that reads
the files and applies the corrections (`apple/AlteraluxKit/Sources/AlteraluxKit/Lens/`) is written
from the published lens models and is GPL-3.0 like the rest of the app; none of lensfun's library code
is used.

**Updating.** `scripts/update-lensfun.sh <commit>` replaces the files with those of another commit.
Do not edit them by hand: changes or additions to the database belong upstream, or in files of their
own beside these.
