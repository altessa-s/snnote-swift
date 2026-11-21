// Copyright 2026 ALTESSA SOLUTIONS INC.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import CoreGraphics
import Foundation
import ImageIO
import SNNote
import Testing

// Forms of the format the corpus does not carry — the compressed stroke log,
// the record's tail and its style ranges, a sheet per page, covers by kind —
// on files built by hand where the corpus has none.

// MARK: - The compressed stroke log

@Test func aCompressedLogReadsLikeAPlainOne() throws {
    let records = (1...5).map { NoteBuilder.strokeRecord(id: Int32($0)) }
    let file = NoteBuilder.onePage(strokeLog: NoteBuilder.strokeLog(records))
    let plain = try #require(try SNParser.parse(file).pages.first)
    let packed = try #require(
        try SNParser.parse(NoteBuilder.onePage(strokeLog: NoteBuilder.compressedStrokeLog(records))).pages.first
    )
    #expect(packed.strokes == plain.strokes)
    #expect(packed.strokes.map(\.id) == [1, 2, 3, 4, 5])
    #expect(packed.skippedStrokes == 0)
}

/// A compressed log whose lengths lie costs the page's strokes, not the page.
@Test func aCompressedLogThatLiesIsCounted() throws {
    var log = NoteBuilder.compressedStrokeLog([NoteBuilder.strokeRecord()])
    log.replaceSubrange(8..<12, with: le32(0x7FFF_FFFF))  // the expanded length
    let page = try #require(try SNParser.parse(NoteBuilder.onePage(strokeLog: log)).pages.first)
    #expect(page.strokes.isEmpty)
    #expect(page.skippedStrokes == 1)
}

// MARK: - The record's tail

/// A heading's box carries its `TITLESTYLE` and, as fields, the title block's
/// values.
@Test func aHeadingBoxCarriesItsStyle() throws {
    let notebook = try Corpus.notebook("heading-n5-20260016-backgrounds-marker.note")
    let boxes = notebook.pages[1].strokes.filter { $0.kind == .headingBox }
    #expect(boxes.map(\.style) == notebook.titles.map { UInt32($0.style.rawValue) })
    #expect(boxes.allSatisfy { $0.category == .heading && $0.isDrawn })
    #expect(boxes.first?.attributes.prefix(3) == ["0", "0", "1000254"])

    // The oldest file's tail is laid out differently, and reads the same.
    let old = try Corpus.notebook("test-a5x-20220011-old-pen-ids.note").pages[0].strokes
    #expect(old.first { $0.kind == .headingBox }?.style == 1_000_254)
}

/// A link's frame carries the link's style and the link's own values: its
/// type, direction, style, time, rects, the target's path, file and page.
@Test func aLinkFrameCarriesItsLink() throws {
    let notebook = try Corpus.notebook("link-n6-3.26.40-partial-erase-3p.note")
    let frames = notebook.pages[1].strokes.filter { $0.kind == .frame }
    #expect(!frames.isEmpty)
    #expect(frames.allSatisfy { $0.category == .link && !$0.isDrawn })
    let fields = try #require(frames.first?.attributes)
    #expect(fields.prefix(4) == ["0", "0", "20000000", "20240303150035347363"])
    #expect(fields.contains("/storage/emulated/0/Note/Perso/Obsidian plugin test/nomad-3.26.40-link-tag-3p.note"))
}

/// Ink carries style 0 and no fields, on every device and format.
@Test func inkCarriesNoStyle() throws {
    for file in ["blank-n5-20230015-manta.note", "turkish-a6x-20230015-handwriting-erase.note",
                 "stroke-n5-20260016-isolation-tools-colors-widths.note"] {
        let ink = try Corpus.notebook(file).pages[0].strokes.filter { $0.kind == .freehand }
        #expect(ink.allSatisfy { $0.style == 0 && $0.category == .ordinary && $0.attributes.isEmpty }, "\(file)")
    }
}

/// Every record of the corpus has a tail this version reads, on every device
/// and format version — a firmware that moves it shows up here first.
@Test func everyRecordsTailReads() throws {
    for url in try Corpus.files() {
        let notebook = try SNParser.parse(Data(contentsOf: url))
        let unread = notebook.pages.flatMap(\.strokes).filter { $0.style == nil }
        #expect(unread.isEmpty, "\(url.lastPathComponent): \(unread.count) tails unread")
    }
}

/// A text box is not ink: its record is not drawn, and the page lists it
/// with its fields.
@Test func aTextBoxIsListedNotDrawn() throws {
    let records = [
        NoteBuilder.strokeRecord(id: 1, style: 0),
        NoteBuilder.strokeRecord(pen: 0, kind: "others", id: 2, style: 5_000_000, fields: ["hello", "font"]),
        NoteBuilder.strokeRecord(pen: 0, kind: "others", id: 3, style: 25_000_000),
        NoteBuilder.strokeRecord(pen: 0, kind: "others", id: 4, style: 24_000_001),
    ]
    let file = NoteBuilder.onePage(strokeLog: NoteBuilder.strokeLog(records))
    let page = try #require(try SNParser.parse(file).pages.first)
    #expect(page.strokes.map(\.category) == [.ordinary, .textBox, .textLink, .pictureLink])
    #expect(page.drawnStrokes.map(\.id) == [1])
    #expect(page.textBoxes.map(\.id) == [2])
    #expect(page.textBoxes.first?.attributes == ["hello", "font"])
}

// MARK: - The sheet, page by page

/// A page made on another device keeps that device's sheet: named by the
/// page, or measured from its bitmap.
@Test func aPageKeepsTheSheetItWasMadeOn() throws {
    var builder = NoteBuilder()
    let header = builder.append(tags: [("APPLY_EQUIPMENT", "N6")])
    let manta = builder.append(NoteBuilder.blankRLE(pixels: 1920 * 2560))
    let nomad = builder.append(NoteBuilder.blankRLE(pixels: 1404 * 1872))
    func page(bitmap: Int, extra: [(String, String)]) -> Int {
        let layer = builder.append(tags: [("LAYERBITMAP", String(bitmap))])
        return builder.append(tags: [("MAINLAYER", String(layer)), ("LAYERSEQ", "MAINLAYER")] + extra)
    }
    let named = page(bitmap: manta, extra: [("PAGEMACHINETYPE", "5")])
    let measured = page(bitmap: manta, extra: [])
    let own = page(bitmap: nomad, extra: [])
    let file = builder.finish(footer: [
        ("FILE_FEATURE", String(header)),
        ("PAGE1", String(named)), ("PAGE2", String(measured)), ("PAGE3", String(own)),
    ])
    let notebook = try SNParser.parse(file)
    #expect(notebook.pages.map(\.size) == [
        CGSize(width: 1920, height: 2560), CGSize(width: 1920, height: 2560), CGSize(width: 1404, height: 1872),
    ])
    #expect(try notebook.pages[1].raster().width == 1920)
}

// MARK: - Covers

/// The digit of `COVER_<n>` is a kind, and a cover can be a JPEG.
@Test func aCoverIsTypedAndMayBeAJPEG() throws {
    var builder = NoteBuilder()
    let header = builder.append(tags: [("APPLY_EQUIPMENT", "N6")])
    let cover = builder.append(try jpeg(width: 8, height: 6))
    let file = builder.finish(footer: [("FILE_FEATURE", String(header)), ("COVER_2", String(cover))])
    let notebook = try SNParser.parse(file)
    #expect(notebook.coverType == 2)
    let bitmap = try #require(notebook.cover)
    #expect(bitmap.encoding == .jpeg)
    #expect(try bitmap.raster(width: 8, height: 6).gray.count == 48)
}

private func jpeg(width: Int, height: Int) throws -> Data {
    let context = try #require(CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
    ))
    context.setFillColor(gray: 0.5, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let image = try #require(context.makeImage())
    let output = NSMutableData()
    let destination = try #require(CGImageDestinationCreateWithData(output, "public.jpeg" as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, nil)
    #expect(CGImageDestinationFinalize(destination))
    return output as Data
}

// MARK: - Links

@Test func linksCarryTheirStyleTimeAndTargetPage() throws {
    let links = try Corpus.notebook("link-n6-3.26.40-partial-erase-3p.note").links
    #expect(links.map(\.style) == [20_000_000, 20_000_000, 20_000_000])
    #expect(links[0].timestamp == "20240303150035347363")
    #expect(links[0].targetPageNumber == 1)
    #expect(links[2].targetPageNumber == nil)
}
