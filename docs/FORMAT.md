# The Supernote `.note` format

The Swift package reads this format through the vendored snnote-lib C23 decoder. Its public headers live in
`Sources/CSNNote/include/snnote`. The C decoder handles container recovery, stroke logs, recognition and native
bitmap decoding. Swift composes the returned planes and uses ImageIO for embedded images.

## 1. Container

A heap of length-prefixed blocks addressed by absolute offset, with a map of them at the end.

```
0      "note" | "mark"                       kind of file
4      "SN_FILE_VER_" + 8 digits             format version, e.g. 20260016
24     u32 length, <KEY:VALUE>…              header (address: FILE_FEATURE in the footer, usually 24)
…      blocks: layers, bitmaps, stroke logs, titles, keywords, links, templates
F      u32 length, <KEY:VALUE>…              footer
       "tail"                                newer files only
-4     u32 F                                 the footer's address — the last four bytes
```

All numbers little-endian. The block at address `A` is a `u32` length at `A`, then that many bytes. Address `0` means "nothing
here", not the start of the file.

The file is appended to: a block rewritten later is written anew and the footer points at the new one, leaving the old in place.
The header is found through `FILE_FEATURE` for that reason — on a file saved more than once it is no longer the block at 24.

The format version is not a firmware version. Known versions: `20200001`–`20200008`, `20210009`, `20210010`,
`20220011`–`20220013`, `20230014`, `20230015`, `20260016`. The first Supernotes (A5, A6) wrote another container,
`SN_FILE_ASA_…`, which this package does not read and names `unsupportedFormat`.

### Tag blocks

Header, footer, page, layer, title, keyword, link — all are blocks of `<KEY:VALUE><KEY:VALUE>…`. A key runs to the first `:`, the
value to the closing `>`, colons included. A key **may repeat**: the footer is appended to, and a heading saved again leaves its
`TITLE_…` twice.

`none`, `0` and the empty string in a text field mean "not set".

## 2. Header and footer

The header (`FILE_FEATURE`) holds the file's properties. Needed for reading: `APPLY_EQUIPMENT` (the device), `FILE_ID` (the file's
identity, which links point at). The others: `MODULE_LABEL`, `FILE_TYPE`, `FINALOPERATION_PAGE`, `FINALOPERATION_LAYER`,
`DEVICE_DPI`, `SOFT_DPI`, `FILE_PARSE_TYPE`, `RATTA_ETMD`, `APP_VERSION`, `FILE_RECOGN_TYPE`, `FILE_RECOGN_LANGUAGE`,
`HORIZONTAL_CHECK`, `IS_OLD_APPLY_EQUIPMENT`, `ANTIALIASING_CONVERT`, `ORIGINAL_STYLE`, `ORIGINAL_STYLEMD5`, and for `.mark` files
`PDFSTYLE`, `PDFSTYLEMD5`, `STYLEUSAGETYPE` and `HIGHLIGHTINFO` (the address of a highlight block).

The footer is the map:

| Key | Value |
|---|---|
| `FILE_FEATURE` | the header's address |
| `PAGE<n>` | the address of page `n`'s block, from 1 |
| `STYLE_<name>` | the address of the template bitmap of that name |
| `COVER_<n>` | the cover's address (`0`: none). The digit is the cover's kind, not a page: `0` none, `2` a picture the user chose; the bitmap may be RLE, PNG or JPEG |
| `TITLE_<page:4><y:4>[<x:4>]` | a heading's block |
| `KEYWORD_<page:4><y:4>` | a keyword's block |
| `LINKO_<page:4>…` / `LINKI_…` | a link's block (outgoing / incoming) |
| `PDFSTYLELIST` | `.mark`: the document styles used |
| `DIRTY` | a service flag |

The four digits after the prefix are the page the object is on. For links this is the reliable source of the page: `OBJPAGE`
inside the block names the target, not the source.

## 3. Device and sheet

A bitmap is stored as run lengths with no width or height, so a page cannot be laid out without the sheet's size, and the header
gives it only by naming the device.

| `APPLY_EQUIPMENT` | Device | Portrait sheet |
|---|---|---|
| `A5X`, `A6X` | A5X, A6X | 1404 × 1872 |
| `N6` | Nomad (A6X2) | 1404 × 1872 |
| `N5` | Manta (A5X2) | 1920 × 2560 |

Devices are also numbered: A5 0, A6 1, A6X 2, A5X 3, Nomad 4, Manta 5. A page made on another device than the notebook's names it
in its own `PAGEMACHINETYPE`, by number or by name, and keeps that device's sheet.

An RLE stream carries no dimensions but does carry a pixel count, so the sheet of an unknown device — or of a page whose bitmap does
not cover the notebook's sheet — can be measured: the known sheet the stream covers exactly is the one.

A page's `ORIENTATION`: `1000` and `1180` are portrait, `1090` and `1270` landscape. A landscape page's bitmaps are stored turned:
width and height swapped.

## 4. Page and layers

The page block:

| Key | Value |
|---|---|
| `PAGESTYLE` | the template: `style_8mm_ruled_line_a5x2`, or `user_…` for an imported one |
| `PAGESTYLEMD5` | the template's hash |
| `PAGEID` | the page's identity, which links point at |
| `LAYERSEQ` | the stack, top first, e.g. `LAYER1,MAINLAYER,BGLAYER`; a hidden layer is left out of it, though its block and bitmap stay |
| `MAINLAYER`, `LAYER1`–`LAYER3`, `BGLAYER` | the layers' blocks |
| `LAYERINFO` | the layer table — JSON with every `:` written `#`, or the JSON in base64 |
| `TOTALPATH` | the stroke log (§6) |
| `RECOGNTEXT` | the recognised text (§9) |
| `RECOGNFILE` | a ZIP of the recognition engine's working files |
| `RECOGNSTATUS`, `RECOGNTYPE`, `RECOGNFILESTATUS`, `RECOGNLANGUAGE` | recognition state |
| `ORIENTATION` | the turn (§3) |
| `PAGEMACHINETYPE` | the device the page was made on, when not the notebook's (§3) |
| `PAGETEXTBOX` | `1` when the page has text boxes, `0` when not — a flag, not an address |
| `DISABLE` | `x,y,w,h\|x,y,w,h\|…` — the regions where the pen does not write: the page's text boxes |
| `EXTERNALLINKINFO` | web link information; not decoded |
| `IDTABLE` | `b64(n),b64(id)\|…` — a map from strokes to recognition ids |
| `THUMBNAILTYPE` | service value |
| `LAYERSWITCH`, `FIVESTAR` | older files only |

Without `LAYERSEQ` the layers stack in the order `LAYER3,LAYER2,LAYER1,MAINLAYER,BGLAYER`.

The layer block: `LAYERNAME`, `LAYERPROTOCOL` (`RATTA_RLE`), `LAYERBITMAP` (the bitmap's address), `LAYERTYPE`, `LAYERPATH`,
`LAYERVECTORGRAPH`, `LAYERRECOGN`. A layer is named by the page's key that points at it; `LAYERNAME` can disagree (an old background
calls itself `MAINLAYER`).

The background of an imported template is the PNG file itself, though the layer's protocol says `RATTA_RLE`; it is told by its
signature.

## 5. `RATTA_RLE`

Pairs of bytes: a code and a length.

- a length below `0x80` is a run of `length + 1` pixels;
- `0xFF` is a run of `0x4000`;
- anything else is *held* until the next pair. If that pair repeats the code, the two combine into
  `1 + next + ((held & 0x7F) + 1) << 7`; if not, the held run stands alone, `((held & 0x7F) + 1) << 7`;
- a held length that ends the stream is cut to the largest `((x & 0x7F) + 1) << k`, `k = 7…0`, that fits what is left of the
  sheet.

A stream that does not cover its sheet exactly is an error. A variant of the oldest A5X blank template reads `0xFF` as `0x400`; it
applies only where the ordinary reading overshoots.

### The palette — by format version

**Before version 15** a code names a palette entry:

| Code | Colour |
|---|---|
| `0x61` | black (0) |
| `0x62` | background — transparent |
| `0x63` | dark grey (157) |
| `0x64` | grey (201) |
| `0x65` | white (254) |
| `0x66`–`0x68` | the marker's forms of the first three, drawn in the same greys |
| any other | no colour — transparent |

**From version 15** a code is a grey level, so that an anti-aliased edge can carry a ramp (15, 31, 47, … on black ink). Eight
values are swapped with the old palette codes, so the old codes keep their meaning:

```
0x61 ↔ 0     0x62 ↔ 255    0x63 ↔ 48    0x64 ↔ 80
0x65 ↔ 254   0x66 ↔ 1      0x67 ↔ 49    0x68 ↔ 81
```

So code `0x00` is grey 97 and code `0xFF` an opaque grey 98. Only `0x62` is transparent. Newer devices write the dark grey directly
as 157/158 and the light as 201/202 (`+1` is the marker).

### Stacking

Top down by `LAYERSEQ`: an opaque pixel of an upper layer covers the ones below, a transparent one shows them, white paper under
everything. A layer outside `LAYERSEQ`, or hidden or deleted in `LAYERINFO`, is not drawn, and neither are its strokes. A marker's grey in the bitmap is already the grey that shows.

This is how a page is exported. The tablet's screen differs at the edges of the ink: there a grey `g` of a drawing layer is black at
alpha `255 − g` (except 0, 1, 157, 158, 201, 202 and 254, which stay opaque), so an anti-aliased edge lets a template line show
through; over the PDF of a `.mark` file every grey is treated so. A renderer that wants the screen's look applies that rule itself.

## 6. The stroke log, `TOTALPATH`

```
u32 record count
count × { u32 length; length bytes of record }
```

or, compressed:

```
u32 0xFFFFFFFF
u32 record count
u32 decompressed length
u32 compressed length
raw LZ4 block → count × { u32 length; record }
```

A record is read field by field as far as its length allows, and stepped over by its length.

### The record

```
header             208 bytes
disableAreaList    u32 n + n × 24
points             u32 n + n × 8      (y, x) u32 pairs, digitiser units
pressures          u32 n + n × 2      u16
angles             u32 n + n × 4
flagDraw           u32 n + n × 1
epaPoints          u32 n + n × 8
epaGrays           u32 n + n × 4
status block       52 bytes
controlNums        u32 n + n × 4
group block        10 bytes
pointContour       u32 rings; per ring u32 n + n × (f32 x, f32 y) — page pixels
entries            u32 n + n × 20      (n × 16 + 4 on …0011 files)
13 bytes           a double (1.0), a u32, a byte
u32 m + m × 4
u32 width, height  the sheet the record was made on (1404 × 1872 on heading and link records on every device)
u32 style          what the record is for, §6.6
u8
u32 length + bytes the record's fields: comma-separated base64, or `none`
…                  more strings and counters, depending on the firmware
```

The header:

| Offset | Field | |
|---|---|---|
| 0 | `penType` i32 | the tool, §6.1 |
| 4 | `penColor` u32 | the colour, §6.2 |
| 8 | `m_thickness` u32 | width in hundredths of a pixel: 400 is a 4 px line |
| 28 | `pageNum` u32 | the page, from 1 |
| 40 | `preNum` i32 | the record's role, §6.3 |
| 44 | `layer` u32 | the layer: 0 main, 1–3 the others |
| 48 | `predictName` char[52] | the record's kind, §6.4 |
| 100 | `upLeftPoint` i32 × 2 | box corner, page pixels |
| 108 | `keyPoint` i32 × 2 | box centre |
| 116 | `downRightPoint` i32 × 2 | box corner |
| 128 | `maxY` u32 | digitiser range along the sheet's height |
| 132 | `maxX` u32 | range along its width |
| 136 | document name char[52] | `superNoteNote` on a notebook's ink, `superNoteDocument` on a `.mark`'s |

The status block: `m_trailStatus` i32 (§6.5), `m_copy` i32 (the operation: erasers 601–603, lasso 604, heading box 400, link frame
500, ink 0/97/99), `m_trailNumInPage` i32 (the stroke's number on its page), then the lasso's shift angles and rectangles.

### Coordinates

```
y = rawY / (maxY / sheet height)
x = sheet width − rawX / (maxX / sheet width)
```

The digitiser's x axis runs right to left. The range is 11864 × 15819 on a Nomad (8.45 units/px), 16224 × 21632 on a Manta,
15725 × 20967 on older A5X files (11.2 units/px), and on some records of the oldest files the sheet's own pixel size, a scale of
one — so the scale is taken from each record. On a landscape page the sheet is turned, and the formula is the same with the turned
size.

`pointContour` is the outline the tablet fills for the stroke, already in page pixels (no mirror, no scale), non-zero winding. It
carries the width that pressure and tilt gave the stroke along its length.

### 6.1. Tool

| `penType` | Tool |
|---|---|
| 1 | ink pen (older firmware); also the Nomad-era eraser, in colour 255 |
| 3 | area eraser |
| 4 | lasso |
| 5 | marker (older firmware); also written over the real tool of a star |
| 9 | selecting eraser |
| 10 | needle point |
| 11 | marker |
| 15 | calligraphy pen |
| 16 | ink pen |
| 0 | geometry the tablet derives (frames) |

### 6.2. Colour

A grey level: 0, 157, 201, 254; the marker writes `+1` (1, 158, 202); 255 is reserved for an eraser's motion. The `…0011` format
stores the greys as ids: 48 and 80 (49 and 81 for the marker), drawn as 157 and 201.

### 6.3. Role (`preNum`)

`5000` ink, `0` derived geometry (a heading's box, a link's frame, a ruled line), `-1`/`-2`/`-4` an eraser's motion, `-5` a lasso
loop.

### 6.4. Kind (`predictName`)

`others` freehand; `straightLine` a ruled line, its two points the ends; `0001` a heading's background, its two points opposite
corners of a filled box (its look is in `TITLESTYLE`, §7); `0000` the frame of a link or a text box, five points closing a
rectangle — the style (§6.6) says which; `fiveStarsSignal` a star.

### 6.5. Status (`m_trailStatus`)

Whether the tablet draws the record: negative is not drawn.

| Code | Meaning |
|---|---|
| `0` | drawn |
| `-2` | page cleared |
| `-3` | moved by a lasso; the ink lives on in a later record |
| `-4` | partly erased; the surviving pieces follow as records of their own, without points, outline only |
| `-16` | deleted through a lasso |
| `-99` | erased whole |

What is drawn: a status that is not negative, a role that is not an eraser or a lasso, a kind that is not a frame, a colour
that is not 255, a tool that is not 3/4/9, and a style that is not a text box's or a link's (§6.6).

### 6.6. Style

| Style | Record |
|---|---|
| `0` | ink |
| 1000000–1255255 | a heading's box; equals its `TITLESTYLE` |
| 5000000–5002000 | a text box |
| 24000000–24000003 | a link on a picture |
| 25000000–25000003 | a link on text |
| 20000000–26000000 | any other link |

The fields behind the style carry, for a heading or a link, the same values as its footer block, in its order. For every kind the
positions are the same:

| Index | Field |
|---|---|
| 0 | type (`LINKTYPE`) |
| 1 | direction |
| 2 | style (`0` on a text box) |
| 3 | timestamp |
| 4, 5 | rect, original rect — `x,y,w,h` in page pixels |
| 6 | target path or address |
| 7, 8 | target file id, page id |
| 9 | target page number |
| 10 | font size, page pixels |
| 11 | font path on the device |
| 12 | text — a text box's own text |
| 13 | text layout parameters |
| 14 | line height |
| 15, 16, 17 | anti-aliased, bold, italic |

For a link the fields repeat its footer block value for value: the same rect, timestamp and target, the path written out
rather than in base64. The snapshot (`LINKBITMAP`) is in the footer block alone, and the footer block is what this package
reads a link from.

A text box's text is drawn into the layer's bitmap; its record is not ink.

## 7. Headings, keywords, links

**Heading** (`TITLE_…`): `TITLESEQNO`, `TITLELEVEL`, `TITLERECT` (`x,y,w,h`, pixels), `TITLERECTORI`, `TITLEBITMAP` (a snapshot,
RLE), `TITLEPROTOCOL`, `TITLESTYLE` — decimal digits `1BBBFFF`: the box's grey and the grey the writing inside is shown in.
`1000254` black box, white text; `1157254`, `1201000`; `1000000` hatched (the one style that spells black on black).

**Keyword** (`KEYWORD_…`): `KEYWORDSEQNO`, `KEYWORDRECT` (`0,0,0,0` on a tag set without a lasso), `KEYWORDRECTORI`, `KEYWORDPAGE` (`0` on tags — the page is then in the
key), `KEYWORDSITE` — the address of the block holding the recognised text, `KEYWORDLEN`, `KEYWORD` — a copy of the text, absent on
tags.

**Link** (`LINKO_…` outgoing, `LINKI_…` incoming): `LINKRECT`, `LINKRECTORI`, `LINKTYPE` (0 a page of a notebook, 1 a notebook, 2 a document, 4 the web),
`LINKINOUT`, `LINKSTYLE` (the §6.6 ranges), `LINKTIMESTAMP`, `LINKFILE` — base64 of the target's path on the device, or of the
web address, `LINKFILEID` — the target's `FILE_ID`, `PAGEID` — the target page's `PAGEID` (`none` for a link to a file or the
web), `OBJPAGE` — the target page's number when the link was made, `LINKBITMAP`, `LINKPROTOCAL`, and for text links `FONTSIZE`,
`FONTPATH`, `FULLTEXT`, `SHOWTEXT`, `BOLD`, `ITALIC`, `ANTI`.

## 8. `.mark` files

A `.mark` holds the handwriting over a document — a PDF or an EPUB — in the same container. Its `FILE_TYPE` is `MARK`. Its pages
are the document's pages that carry anything, numbered as the document's: a mark over a 300-page book written on page 22 has one
key, `PAGE22`. A page has no template and, as a rule, a main layer only; the document itself is not in the file.

The sheet is the document's page fitted to the screen: scaled to the sheet's width and centred along its height. A Letter page
(612 × 792 pt) on a Nomad is drawn at 2.295 px/pt, 26 px from the top.

**Highlights.** The header's `HIGHLIGHTINFO` is the address of a block of base64 JSON: an object whose keys are the document's page
indexes, from `0`, each holding a list of marks on its text:

```json
{"0": [{"annotationType": 0, "colorType": 0, "annotationContent": "Test comment",
        "mupdfRectList": [{"x0": 50.0, "y0": 223.0, "x1": 555.0, "y1": 232.0}, …],
        "rnRectList": [{"left": 114, "top": 538, "right": 1273, "bottom": 559}, …],
        "page": 0, "time": 1791088593555}]}
```

`annotationType` is `0` for a highlight and `1` for an underline; `colorType` the colour; `annotationContent` the comment, absent
when there is none; `mupdfRectList` the marked lines in the document's points, `rnRectList` the same lines in sheet pixels; `time`
milliseconds since 1970.

## 9. Recognised text

`RECOGNTEXT` is base64 of the recognition engine's JSON: `{"elements":[{"type":"Text","label":"…","words":[{"label":"…",
"bounding-box":{"x","y","width","height"}}]}]}`. Spaces and line breaks are words of their own, without a box. Boxes are in
physical millimetres from the top-left corner: ≈ 11.8 px/mm on the A6X, Nomad and Manta (300 dpi), ≈ 8.9 px/mm on the A5X
(226 dpi). An empty element list ("recognised, found nothing") is not the same as no block ("never recognised").

`RECOGNFILE` is a ZIP of the engine's working files (`ink.bink`, `page.bdom`, `style.css`).

## 10. What this package reads

Decoded: everything in §1–§9, except what follows.

Kept as stored, not decoded: `EXTERNALLINKINFO`, `IDTABLE`, the inside of `RECOGNFILE`.

Not read: the `SN_FILE_ASA_…` container.
