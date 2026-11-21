# ADR-0012: Lens profiles from lensfun's database, applied before the engine

- Status: Accepted
- Date: 2026-11-21

## Context

[ADR 0011](0011-recipes-adapt-to-each-photo.md) turned on the lens correction of Apple's RAW decoder,
which covers only the cameras and lenses Apple knows and says nothing about which. The vision asks for
distortion, vignetting and chromatic aberration corrected from the photo's metadata. The only open
collection of lens measurements is lensfun's: its library is LGPLv3, its database CC BY-SA 3.0, which
is not compatible with the GPL as part of the same work (only CC BY-SA 4.0 is, one way). The user
agreed on 2026-11-21 to ship it as a separate file, unmodified, with its attribution.

The engine works linear in, linear out ([ADR 0002](0002-linear-in-linear-out.md)), and the frame is cut
before it ([ADR 0010](0010-crop-before-the-engine.md)).

## Decision

- lensfun's `data/db/*.xml` files are kept in `third_party/lensfun/` exactly as upstream has them, at a
  pinned commit, with their license and a README; `scripts/update-lensfun.sh <commit>` replaces them.
  The app ships them as a folder of its resources and credits them in the About panel and the README.
- No lensfun code is used. `AlteraluxKit/Lens/` reads the XML with Foundation, matches the photo's
  camera and lens as lensfun's `MatchScore` and fuzzy comparison do, interpolates the calibrations as
  lensfun does, and expresses the result (`LensCorrection`) in the photo's pixels, with a Swift
  reference of every formula.
- A Core Image kernel (`LensWarp`), compiled from Metal source at run time, applies it to the RAW
  decoder's scene-linear output, before the frame: distortion with lensfun's autoscale, so the picture
  fills the frame, colored fringes for red and blue, and vignetting. Tests compare the kernel with the
  Swift reference.
- A profile is used only where Apple's decoder has no correction of its own, so a lens is never
  corrected twice, and only for RAWs: a JPEG or TIFF from a camera may already be corrected.
- The same switch as ADR 0011 turns it on and off, with the same rule: new photos on, adjustments saved
  before it existed as they were (here: uncorrected).

## Alternatives considered

| Option | Why not |
|---|---|
| Linking lensfun's library | A C++ build with GLib for what is a few formulas and an XML reader; the database's terms are the same either way |
| Converting the database into Swift tables or our own format | A derivative of the database, which would have to stay CC BY-SA 3.0 inside GPL code |
| Fetching the database at build time | One more download for every build and for CI, for 5 MB that change rarely |
| Adobe's lens profiles (LCP) | Not free to ship |
| Correcting on the CPU over the pixels | Slower for every preview; Core Image keeps it on the GPU and at the preview's size |

## Consequences

- RAWs from lenses lensfun knows are corrected even where Apple's decoder is not.
- lensfun's coverage of recent lenses is what it is; adding a lens means contributing it upstream, or a
  file of our own beside the database (not done yet).
- Before an official release, the license reading should be checked by someone qualified.
