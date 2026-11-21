// Copyright 2026 ALTESSA SOLUTIONS INC.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import CoreGraphics
import Foundation
import SNNote
import Testing

// The third-party corpus (`Fixtures/supernote-typescript`), each file read
// whole, against the numbers it is known to hold.

/// What a file holds.
private struct Expected {
    let version: Int
    let equipment: SNEquipment
    /// Strokes the page shows, per page.
    let drawn: [Int]
}

private let corpus: [String: Expected] = [
    "blank-a6x-3.15.27-shapes-rtr.note": Expected(version: 20_230_015, equipment: .a6x, drawn: [177]),
    "blank-a6x-3.15.27-two-pages.note": Expected(version: 20_230_015, equipment: .a6x, drawn: [159, 227]),
    "blank-a6x-3.26.40-two-pages.note": Expected(version: 20_230_015, equipment: .a6x, drawn: [0, 0]),
    "blank-n5-20230015-manta.note": Expected(version: 20_230_015, equipment: .manta, drawn: [53]),
    "caligraphy-n5-20260016-widths-erase.note": Expected(
        version: 20_260_016,
        equipment: .manta,
        drawn: [21, 9, 10, 7]
    ),
    "color-n6-20230015-unknown-palette.note": Expected(version: 20_230_015, equipment: .nomad, drawn: [64]),
    "demo-a5x-20230015-1to10.note": Expected(
        version: 20_230_015,
        equipment: .a5x,
        drawn: [2, 1, 1, 2, 1, 1, 1, 2, 1, 2]
    ),
    "digest-n5-20230015-test.mark": Expected(version: 20_230_015, equipment: .manta, drawn: [347]),
    "erase-n5-20260016-all-mechanisms.note": Expected(version: 20_260_016, equipment: .manta, drawn: [9]),
    "erase-n5-20260016-mixed-colors.note": Expected(version: 20_260_016, equipment: .manta, drawn: [5, 11]),
    "erase-n5-20260016-no-white-pen.note": Expected(version: 20_260_016, equipment: .manta, drawn: [0]),
    "erase-n5-20260016-white-pen-cover.note": Expected(version: 20_260_016, equipment: .manta, drawn: [2, 2, 2, 1]),
    "erase-n6-20230015-horizontal-1270.note": Expected(version: 20_230_015, equipment: .nomad, drawn: [61]),
    "heading-n5-20260016-backgrounds-marker.note": Expected(
        version: 20_260_016,
        equipment: .manta,
        drawn: [32, 42, 40]
    ),
    "ink-a5x-2.14.28-old-pen-width.note": Expected(version: 20_230_015, equipment: .a5x, drawn: [146]),
    "layout-n5-20230015-horizontal-1090.note": Expected(version: 20_230_015, equipment: .manta, drawn: [51]),
    "layout-n5-20230015-vertical-1000.note": Expected(version: 20_230_015, equipment: .manta, drawn: [53]),
    "layout-n6-20230015-vertical-1180.note": Expected(version: 20_230_015, equipment: .nomad, drawn: [55]),
    "line-n5-20260016-ruler-tool.note": Expected(version: 20_260_016, equipment: .manta, drawn: [6, 2, 0]),
    "link-n6-3.26.40-partial-erase-3p.note": Expected(version: 20_230_015, equipment: .nomad, drawn: [159, 271, 113]),
    "render-n6-20230015-moonchild-user-bg.note": Expected(version: 20_230_015, equipment: .nomad, drawn: [0]),
    "rtr-n5-20230015-recognition.note": Expected(version: 20_230_015, equipment: .manta, drawn: [225]),
    "sticker-n5-20260016-plugin-artwork.note": Expected(version: 20_260_016, equipment: .manta, drawn: [5, 51, 0]),
    "stroke-n5-20260016-20260809.note": Expected(version: 20_260_016, equipment: .manta, drawn: [1, 1, 1, 1, 0]),
    "stroke-n5-20260016-isolation-tools-colors-widths.note": Expected(
        version: 20_260_016,
        equipment: .manta,
        drawn: [1, 4, 4, 4, 2]
    ),
    "test-a5x-20220011-old-pen-ids.note": Expected(version: 20_220_011, equipment: .a5x, drawn: [58, 30]),
    "turkish-a6x-20230015-handwriting-erase.note": Expected(version: 20_230_015, equipment: .a6x, drawn: [152]),
]

@Test func corpusParsesToWhatItHeldWhenTakenIn() throws {
    let urls = try Corpus.files()
    #expect(Set(urls.map(\.lastPathComponent)) == Set(corpus.keys))
    for url in urls {
        let name = url.lastPathComponent
        guard let expected = corpus[name] else { continue }
        let notebook = try SNParser.parse(Data(contentsOf: url))
        #expect(notebook.formatVersion == expected.version, "\(name)")
        #expect(notebook.equipment == expected.equipment, "\(name)")
        #expect(notebook.kind == (url.pathExtension == "mark" ? .mark : .note), "\(name)")
        #expect(notebook.pages.map(\.number) == Array(1...expected.drawn.count), "\(name)")
        #expect(notebook.pages.map { $0.drawnStrokes.count } == expected.drawn, "\(name)")
        // Every page and every stroke record in the corpus is one this
        // version reads. A firmware that changes the record shows up here
        // first.
        #expect(notebook.skippedPages == 0, "\(name)")
        #expect(notebook.pages.allSatisfy { $0.skippedStrokes == 0 }, "\(name)")
    }
}

/// The record says whether the tablet still draws a stroke, and the count
/// of drawn strokes is the count of paths in the tablet's PDF of the page.
@Test(arguments: [
    ("turkish-a6x-20230015-handwriting-erase.note", 1, 189, 152),
    ("erase-n6-20230015-horizontal-1270.note", 1, 82, 61),
    ("link-n6-3.26.40-partial-erase-3p.note", 3, 143, 113),
])
func drawnStrokesMatchTheTabletsOwnExport(file: String, page: Int, ink: Int, drawn: Int) throws {
    let notebook = try Corpus.notebook(file)
    let strokes = notebook.pages[page - 1].strokes.filter { $0.role == .ink && $0.color != .eraser }
    #expect(strokes.count == ink)
    #expect(strokes.filter(\.isDrawn).count == drawn)
}

/// Every stored bitmap decodes to exactly the page's sheet, turned with it.
@Test func everyLayerDecodesToItsSheet() throws {
    for url in try Corpus.files() {
        let notebook = try SNParser.parse(Data(contentsOf: url))
        for page in notebook.pages {
            for layer in page.layers {
                guard let bitmap = layer.bitmap else { continue }
                let width = Int(page.size.width)
                let height = Int(page.size.height)
                if bitmap.encoding == .png {
                    #expect(try bitmap.raster(width: width, height: height).gray.count == width * height)
                } else {
                    let codes = try #require(try bitmap.codes(width: width, height: height))
                    #expect(codes.count == width * height, "\(url.lastPathComponent)")
                }
            }
        }
    }
}

/// The two records of the same handwriting agree: a drawn stroke's centreline
/// lies on the ink the tablet rendered for it. This is what pins the
/// coordinate transform — the digitiser's mirrored axis, its range per axis,
/// and the sheet turned on a landscape page.
@Test(arguments: [
    "blank-n5-20230015-manta.note",
    "erase-n6-20230015-horizontal-1270.note",
    "layout-n5-20230015-horizontal-1090.note",
    "ink-a5x-2.14.28-old-pen-width.note",
    "test-a5x-20220011-old-pen-ids.note",
    "turkish-a6x-20230015-handwriting-erase.note",
])
func strokesLieOnTheirOwnInk(file: String) throws {
    let page = try Corpus.notebook(file).pages[0]
    let raster = try page.raster(includeBackground: false)
    var onInk = 0
    var total = 0
    for stroke in page.drawnStrokes where stroke.role == .ink && stroke.color.gray.map({ $0 < 250 }) == true {
        for point in stroke.points {
            total += 1
            if inkNear(point.position, in: raster) { onInk += 1 }
        }
    }
    #expect(total > 0)
    #expect(Double(onInk) / Double(total) > 0.98, "\(file): \(onInk) of \(total) points on ink")
}

private func inkNear(_ point: CGPoint, in raster: SNRaster) -> Bool {
    let x = Int(point.x.rounded())
    let y = Int(point.y.rounded())
    for dy in -2...2 {
        for dx in -2...2 {
            let px = x + dx
            let py = y + dy
            if px >= 0, py >= 0, px < raster.width, py < raster.height, raster.gray[py * raster.width + px] < 250 {
                return true
            }
        }
    }
    return false
}

@Test func landscapePagesAreTurned() throws {
    let nomad = try Corpus.notebook("erase-n6-20230015-horizontal-1270.note")
    #expect(nomad.sheet == CGSize(width: 1404, height: 1872))
    #expect(nomad.pages[0].orientation == .landscape)
    #expect(nomad.pages[0].size == CGSize(width: 1872, height: 1404))

    let manta = try Corpus.notebook("layout-n5-20230015-horizontal-1090.note")
    #expect(manta.pages[0].size == CGSize(width: 2560, height: 1920))
    #expect(try Corpus.notebook("layout-n6-20230015-vertical-1180.note").pages[0].orientation == .portrait)
}

/// The palette is chosen by the format version: the oldest file stores
/// palette ids, every later one grey levels.
@Test func paletteFollowsTheFormatVersion() throws {
    #expect(try Corpus.notebook("test-a5x-20220011-old-pen-ids.note").pages[0].palette == .legacy)
    #expect(try Corpus.notebook("demo-a5x-20230015-1to10.note").pages[0].palette == .current)
}

@Test func layersStackInTheOrderThePageDeclares() throws {
    let page = try Corpus.notebook("test-a5x-20220011-old-pen-ids.note").pages[0]
    #expect(page.layers.map(\.name) == [.layer1, .main, .background])
    #expect(page.layer(.layer1)?.isVisible == true)
    #expect(page.layerInfo.count == 5)
    // Strokes name their layer: the page has real content on layer 1.
    #expect(page.strokes.contains { $0.layer == 1 })
    #expect(page.strokes.contains { $0.layer == 0 })
}

@Test func templatesAreCarriedByName() throws {
    let notebook = try Corpus.notebook("color-n6-20230015-unknown-palette.note")
    #expect(Set(notebook.templates.keys) == [
        "style_5mm_grid", "style_8mm_ruled_line", "style_task_list", "style_white",
    ])
    let imported = try Corpus.notebook("render-n6-20230015-moonchild-user-bg.note").pages[0]
    #expect(imported.template == "user_7mm_lined")
    #expect(imported.layer(.background)?.bitmap?.encoding == .png)
}
