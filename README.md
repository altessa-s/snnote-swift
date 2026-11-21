# SNNote

The Supernote notebook format, read: the `.note` container (and `.mark`, which shares it), its pages and layers, the `RATTA_RLE`
bitmaps the tablet draws, the vector strokes behind them, headings, keywords, links, and what the tablet recognised in the
handwriting. Reading only — nothing here draws a stroke, and nothing here has heard of the cloud.

SNNote is a Swift binding to [snnote-lib v1.0.0](https://github.com/altessa-s/snnote-lib/tree/v1.0.0).
Consumers can build the vendored C23 sources through SwiftPM or link the dynamic `SNNote.xcframework`.

## Why it exists

A notebook on disk holds the same handwriting twice. Each page stores the tablet's own bitmaps — what it shows, at the screen's
resolution — and, beside them, the pen's log: every motion in vector form, erased and moved strokes included, with the tablet's
verdict on each. A thumbnail wants the first; anything that scales, searches or converts wants the second. Both are in an
undocumented container, and a parser that a viewer, a converter and a sync client all have to reach has no business living inside
any one of them.

## What it depends on

SwiftPM compiles the pinned C sources in `Sources/CSNNote` using the package’s `.c2x` setting.
The Swift target uses Foundation, CoreGraphics, ImageIO and Synchronization. Each successful parse copies
the notebook into Swift-owned values before freeing the C arena. Bitmap decoding copies the returned planes
before releasing their C allocation. ImageIO decodes PNG and JPEG data.

To refresh the vendored library on macOS, run `Scripts/update-clib.sh ../snnote-lib` with a clean upstream checkout.
The script replaces the complete target and records the revision in `VERSION` and `COMMIT`.
The upstream MIT licence and copyright notice ship in the source target and the framework bundle.

## Design

**Read, do not draw.** The package decodes what is stored. It stacks a page's stored bitmaps, because that is how the tablet shows a
page and the stored codes leave nothing to interpret, but it does not rasterise strokes: widths, nibs and anti-aliasing are a
renderer's.

**The file says what the page shows.** A stroke log is every motion of the pen. Which of them the page still shows is not worked out
by replaying the eraser — an eraser record and a selection record of the same shape mean opposite things — but read from the record:
`SNStroke.status` is the tablet's own verdict, and `isDrawn` applies it.

**A notebook that will not wholly parse is not a lost notebook.** A stroke record that will not read is stepped over by its declared
length and counted in `SNPage.skippedStrokes`; a page that will not read is counted in `SNNotebook.skippedPages`. Only a file that
is not a notebook at all, or whose map of itself is gone, throws.

**A count the file declares is a declaration.** Every `u32` count is checked against the bytes behind it before anything is
reserved, and every coordinate the file gives is computed in a type that cannot overflow.

## Reading

```swift
let notebook = try SNParser.parse(data)
for page in notebook.pages {
    let ink = page.drawnStrokes                 // vectors, in page pixels
    let picture = try page.raster()             // the stored bitmaps, stacked, on white
    let text = page.recognition?.text           // what the tablet recognised, if it did
}
```

| Error | When |
|---|---|
| `SNParseError.unsupportedFormat` | The bytes do not begin as a Supernote file (or begin as the first generation's `SN_FILE_ASA_` container). The first of them travel with the error. |
| `SNParseError.unexpectedEndOfData` | The file ends before its own map. |
| `SNParseError.malformed` | The map is not one: a footer address outside the file, a footer with no keys, a block declared past the end. |

## The notebook

| Type | What it is |
|---|---|
| `SNNotebook` | One file: kind (`.note`/`.mark`), format version, device, `FILE_ID`, the sheet, pages, headings, keywords, links, templates by name, the cover and its kind, and the header and footer as stored. |
| `SNPage` | One page: `PAGEID`, template, orientation and its own size (a page made on another device keeps its sheet), layers top first, the layer table, the stroke log — plain or LZ4-compressed — its text boxes, recognised text, MyScript's archive, the palette its codes are written in. |
| `SNLayer` | Main, layers 1–3, background: the stored bitmap, whether it is in the page's stack, and what the layer table says about it. |
| `SNBitmap` | A picture as stored — `RATTA_RLE`, PNG or JPEG — decoded on request into codes or an `SNRaster`. |
| `SNPalette` | What an RLE code looks like. Two of them, `legacy` and `current`, chosen by the format version: before version 15 a code names a palette entry, from 15 it is a grey level with eight values swapped. |
| `SNRaster` | Grey and coverage per pixel; `over(_:)` stacks one layer on another, `flattened()` puts it on paper, `pngData()` is for looking at. |
| `SNStroke` | One record of the stroke log: tool, colour, width in hundredths of a pixel, kind, role, status, layer, points in page pixels with pressure, the filled outline the tablet renders, the declared box, and from the record's tail its style — heading, text box, link, link on text or on a picture — with its fields. |
| `SNTitle`, `SNKeyword`, `SNLink` | The footer's annotations: a heading and its style (`1BBBFFF` — box grey, text grey), a keyword and its recognised text, a link and its target — a page, a file or a web address — with its style and time. |
| `SNTextBox` | A box of typed text: its text, font size, font and place. |
| `SNHighlight` | A highlight or underline on a `.mark` file's document: its lines in sheet pixels and in the document's points, its comment and time. |
| `SNRecognition` | The recognition engine's elements and words, boxes in millimetres. |
| `SNMetadata` | Any tag block as stored, repeated keys kept: every typed value above has its block beside it, for the keys nobody has named yet. |

The format itself is in [`docs/FORMAT.md`](docs/FORMAT.md): the container, the palettes, the stroke record field by field.

## Diagnostics

```swift
SNNoteLog.install { level, message in
    switch level {
    case .error: Log.sync.error("\(message, .public)")
    case .debug: Log.sync.debug("\(message, .public)")
    }
}
```

The sink receives the message text and severity supplied by snnote-lib. A skipped stroke record produces one
`error` callback with the text `stroke record does not read`. The page reports the skipped count.

Two levels: a piece of the notebook was lost (`error`), or the file held something this version does not know and read past
(`debug`). Nothing in a message is ever the user's: every value is a count, an offset, a key name or a raw number. The handwriting,
the recognised text and the file names never reach a sink (`LoggingTests` holds a Turkish page to that).

## Using this package

**As a source dependency:**

```swift
dependencies: [
    .package(url: "https://github.com/altessa-s/snnote-swift.git", from: "1.0.0"),
    // or, beside a checkout: .package(path: "../snnote-swift")
],
targets: [
    .target(name: "YourTarget", dependencies: [.product(name: "SNNote", package: "snnote-swift")]),
]
```

`package:` is the package's identity — the repository or directory name, `snnote-swift` — not the `name:` in its manifest.

**As a binary.** `Scripts/build-xcframework.sh` produces `build/SNNote.xcframework` — dynamic, macOS (arm64, x86_64), iOS (arm64)
and the iOS simulator (arm64, x86_64), each slice checked — and the release workflow attaches it to a tag with its checksum:

```sh
Scripts/build-xcframework.sh                        # -> build/SNNote.xcframework
Scripts/build-xcframework.sh ../some-app/Frameworks # and install it there too
```

A binary module carries no testability, so a consumer's tests see the public API only. Every public enum with cases is `@frozen`,
so a consumer's exhaustive `switch` breaks on a new case rather than falling into `@unknown default`; and every one of them with an
associated value spells out its `==` and `hash(into:)`, because a synthesised witness is internal and absent from a binary
framework's symbol table — the comparison then links in a release build and fails to in a debug one.

## What it does not read

- The first generation's container, `SN_FILE_ASA_…` (A5, A6): named as `unsupportedFormat`, not misread.
- The inside of `RECOGNFILE`, MyScript's working archive: handed over as stored.
- `EXTERNALLINKINFO` and `IDTABLE`: kept as stored. `docs/FORMAT.md` §10 lists what is decoded.
- Colour: every device the format has been written by is greyscale, and the stored codes say nothing else. A colour device would
  be the first to need a new palette.

## Tests

```sh
swift test
```

| Suite | What it holds |
|---|---|
| `CorpusTests` | 27 fixtures from [philips/supernote-typescript](Tests/SNNoteTests/Fixtures/supernote-typescript/README.md) (Apache-2.0): A5X, A6X, Nomad, Manta, format versions 11 to 16. Pages, devices and drawn strokes per page; every layer to its sheet; stroke centrelines on their own ink, portrait and landscape. |
| `StrokeTests` | The record field by field, against pages that isolate one tool, colour or width each; old and new pen ids; heading boxes, ruled lines, stars, link frames, lassoes; partial erases and their pieces; removal statuses. |
| `AnnotationTests` | Heading styles, keyword text, link targets, recognition — Turkish included. |
| `FormatTests` | The run-length code, the two palettes, tag blocks, and a stroke record built by hand. |
| `SampleTests` | [Nomad device samples](Tests/SNNoteTests/Fixtures/samples/README.md): text boxes in three sizes; links to a page, a document and the web; a picture cover; a heading over an imported template; three layers with one hidden and one deleted; `.mark` files over an EPUB and over a PDF, with highlights, an underline and a comment. |
| `EngineCoverageTests` | Forms the corpus does not carry, on files built by hand: the LZ4 stroke log, the record's tail and style ranges, text boxes and link kinds, a sheet per page, covers by kind, typed link fields. |
| `ParseRecoveryTests` | What a broken file costs, and mutated corpus files and bitmaps that must throw or parse but never trap. |
| `LoggingTests` | The sink: errors reported, silence by default, no handwriting in a message. |
| `RasterTests` | The raster's own API: planes of the wrong size refused, a pixel outside it `nil`, stacking by coverage, a round trip through PNG. |
| `GoldenRasterTests` | Pixel digests for every notebook page and both device mark layers. |
| `NotelibOracleTests` | **Every page against the Supernote Private Cloud's renderer** — opt-in, see below. |
| `DeviceCorpusTests` | Notebooks from a real device, outside the repository — opt-in, see below. |

### Against the Private Cloud's renderer

The Supernote Private Cloud runs `notelib`, the converter behind its web viewer, as a container of its own: JSON over TCP on port
6000, reachable from inside the compose network, which downloads a `.note` from a URL and uploads a PNG per page to others. The
oracle tests bring both ends — a loopback HTTP server in the test process, and a Perl one-liner run in the service container with
`docker exec` — and compare each page to the pixel. No account is involved and nothing is stored in the cloud.

```sh
SNNOTE_NOTELIB_CONTAINER=sn-supernote-service swift test -c release --filter NotelibOracleTests
```

`SNNOTE_NOTELIB_HOST` is how a container reaches this machine (`host.docker.internal` by default). Pages match to within one grey
level; a page over an imported PNG template is held to four, because the converter reduces those to grey through a gamma-2.2 space.

### Notebooks from a device

```sh
SNNOTE_CORPUS="$HOME/…/Supernote/Note:$HOME/…/other" swift test -c release
```

Colon-separated directories, searched recursively. The files stay where their owner keeps them: private handwriting does not belong
in a repository, so these tests assert that every part reads and — with `SNNOTE_NOTELIB_CONTAINER` set as well — that every page
matches the Private Cloud's render, and nothing about the content.

Release builds are worth it for the two opt-in suites: they decode every layer of every page, five megapixels a layer on a Manta.

CI (`.github/workflows/ci.yml`) runs on every push to `main` and `develop` and on every pull request: the release tests, an Address Sanitizer run,
SwiftLint `--strict`, and the xcframework built the way a release builds it. The two opt-in suites skip themselves there — a runner
has neither a Private Cloud nor anybody's notebooks — and `GoldenRasterTests` carries their answer instead. After a change meant to
move pixels, check against the converter again and record new digests: `SNNOTE_RECORD_GOLDEN=1 swift test --filter everyPageDecodesToTheCheckedPixels`.

## Branches and releases

Development happens on `develop`. Releases are tagged on `main`, starting with `v1.0.0`.
The workflow also accepts tags without the `v` prefix and marks tags with a hyphen as pre-releases.

```sh
git tag v1.0.0
git push origin v1.0.0
```

The workflow runs the tests first, builds the framework with the version from the tag,
zips it with `ditto` — an `.xcframework` is a bundle of symlinks a plain `zip` breaks — computes the checksum from the very bytes it
uploads, and publishes the `.binaryTarget` lines to paste. To reproduce a release build locally:

```sh
SNNOTE_VERSION=1.0.0 Scripts/build-xcframework.sh
```

## Licence

SNNote is distributed under the [MIT licence](LICENSE).

## Trademark

Supernote is a trademark of Ratta Software. This project is not affiliated with, endorsed by or sponsored by Ratta Software.
