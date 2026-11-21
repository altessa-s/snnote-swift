// Copyright 2026 ALTESSA SOLUTIONS INC.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import CoreGraphics
import Foundation
import SNNote
import Testing

// The pieces of the format on their own: the run-length code, the tag
// blocks, the palettes, and a stroke record built by hand.

// MARK: - RATTA_RLE

private func codes(_ bytes: [UInt8], width: Int, height: Int = 1) throws -> [UInt8] {
    try #require(try SNBitmap(encoding: .rattaRLE, data: Data(bytes)).codes(width: width, height: height))
}

@Test func shortRunsAreOneMoreThanTheirLength() throws {
    #expect(try codes([0x61, 0x02, 0x62, 0x00], width: 4) == [0x61, 0x61, 0x61, 0x62])
}

/// `0xFF` is a block of 0x4000 pixels.
@Test func theBlockMarkerIsSixteenThousandPixels() throws {
    let pixels = try codes([0x62, 0xFF], width: 0x4000)
    #expect(pixels.count == 0x4000)
    #expect(pixels.allSatisfy { $0 == 0x62 })
}

/// A held length followed by the same colour joins into one long run:
/// `1 + 5 + ((0x81 & 0x7F) + 1) << 7` = 262.
@Test func aHeldLengthJoinsTheNextRunOfTheSameColour() throws {
    let pixels = try codes([0x61, 0x81, 0x61, 0x05, 0x62, 0x01], width: 264)
    #expect(pixels.prefix(262).allSatisfy { $0 == 0x61 })
    #expect(pixels.suffix(2) == [0x62, 0x62])
}

/// A held length followed by another colour stands alone: `(1 + 1) << 7`.
@Test func aHeldLengthBeforeAnotherColourStandsAlone() throws {
    let pixels = try codes([0x61, 0x81, 0x62, 0x00], width: 257)
    #expect(pixels.prefix(256).allSatisfy { $0 == 0x61 })
    #expect(pixels.last == 0x62)
}

/// A held length at the very end is cut to the largest power-of-two step that
/// fits what is left of the sheet.
@Test func aHeldTailIsCutToFit() throws {
    // Ten pixels, then a tail of 256 at most: the largest of 256, 128, …, 2
    // that fits what is left. Sixteen fill a sheet of 26 exactly; on a sheet
    // of 32 they leave six pixels nothing covers, and a stream that does not
    // cover its sheet was not written for it.
    #expect(throws: SNParseError.self) { try codes([0x61, 0x09, 0x62, 0x81], width: 32) }
    let pixels = try codes([0x61, 0x09, 0x62, 0x81], width: 26)
    #expect(pixels.suffix(16).allSatisfy { $0 == 0x62 })
}

@Test func aStreamLongerThanTheSheetIsRefused() {
    #expect(throws: SNParseError.self) { try codes([0x61, 0x7F], width: 10) }
    #expect(throws: SNParseError.self) { try codes([0x61, 0x01], width: 10) }
}

// MARK: - Palettes

@Test func theLegacyPaletteNamesItsCodes() {
    let palette = SNPalette.legacy
    #expect(palette.ink(for: 0x61) == .init(gray: 0, isOpaque: true))
    #expect(palette.ink(for: 0x62).isOpaque == false)
    #expect(palette.ink(for: 0x63).gray == 157)
    #expect(palette.ink(for: 0x64).gray == 201)
    #expect(palette.ink(for: 0x65).gray == 254)
    #expect(palette.ink(for: 0x68).gray == 201)
    // Any other code is no colour at all.
    #expect(palette.ink(for: 0x10).isOpaque == false)
    #expect(palette.ink(for: 0x9D).isOpaque == false)
}

/// Format 15 on: a grey per code, eight values swapped with the old palette
/// codes — which is why an anti-aliasing ramp of 17, 33, 49, 65, 81, 97 is
/// stored as 17, 33, 0x67, 65, 0x68, 0x00.
@Test func theCurrentPaletteIsGreysWithEightSwaps() {
    let palette = SNPalette.current
    #expect(palette.ink(for: 0x61).gray == 0)
    #expect(palette.ink(for: 0x00).gray == 0x61)
    #expect(palette.ink(for: 0x66).gray == 1)
    #expect(palette.ink(for: 0x67).gray == 49)
    #expect(palette.ink(for: 0x68).gray == 81)
    #expect(palette.ink(for: 0xFF).gray == 0x62)
    #expect(palette.ink(for: 0x9D).gray == 157)
    #expect(palette.ink(for: 0x62).isOpaque == false)
    #expect((0...255).filter { !palette.ink(for: UInt8($0)).isOpaque } == [0x62])
    #expect(SNPalette.forFormat(20_220_011) == .legacy)
    #expect(SNPalette.forFormat(20_230_015) == .current)
    #expect(SNPalette.forFormat(20_260_016) == .current)
}

// MARK: - Tag blocks

@Test func tagBlocksKeepOrderAndRepeats() {
    let metadata = SNMetadata(parsing: Data("<A:1><TITLE_1:20><B:x:y><TITLE_1:30>junk<C:>".utf8))
    #expect(metadata.entries.map(\.key) == ["A", "TITLE_1", "B", "TITLE_1", "C"])
    #expect(metadata["TITLE_1"] == "20")
    #expect(metadata.values(for: "TITLE_1") == ["20", "30"])
    // A value runs to its closing bracket, colons and all.
    #expect(metadata["B"] == "x:y")
    #expect(metadata["C"]?.isEmpty == true)
}

@Test func aTruncatedTagIsDropped() {
    let metadata = SNMetadata(parsing: Data("<A:1><B:2".utf8))
    #expect(metadata.entries.map(\.key) == ["A"])
}

// MARK: - A stroke record built by hand

/// The transform from digitiser units: y scaled by the range over the
/// sheet's height, x mirrored and scaled by its own.
@Test func digitiserUnitsBecomePagePixels() throws {
    let record = NoteBuilder.strokeRecord(points: [(y: 15819, x: 11864), (y: 0, x: 0)])
    let notebook = try SNParser.parse(NoteBuilder.onePage(strokeLog: NoteBuilder.strokeLog([record])))
    let stroke = try #require(notebook.pages.first?.strokes.first)
    let expected = [CGPoint(x: 0, y: 1872), CGPoint(x: 1404, y: 0)]
    for (point, want) in zip(stroke.points.map(\.position), expected) {
        #expect(abs(point.x - want.x) < 1e-9 && abs(point.y - want.y) < 1e-9, "\(point)")
    }
    #expect(stroke.points.allSatisfy { $0.pressure == 2048 })
    #expect(stroke.pen == .needlePoint)
    #expect(stroke.kind == .freehand)
    #expect(stroke.isDrawn)
}

@Test func whatIsNotInkIsNotDrawn() throws {
    let records = [
        NoteBuilder.strokeRecord(status: -99, id: 1),                           // erased
        NoteBuilder.strokeRecord(pen: 3, color: 255, role: -2, id: 2),          // an eraser's motion
        NoteBuilder.strokeRecord(pen: 4, role: -5, id: 3),                      // a lasso
        NoteBuilder.strokeRecord(pen: 0, kind: "0000", role: 0, id: 4),         // a link's frame
        NoteBuilder.strokeRecord(pen: 1, color: 255, role: -1, id: 5),          // a Nomad eraser
        NoteBuilder.strokeRecord(id: 6),                                        // ink
    ]
    let file = NoteBuilder.onePage(strokeLog: NoteBuilder.strokeLog(records))
    let page = try #require(try SNParser.parse(file).pages.first)
    #expect(page.strokes.map(\.id) == [1, 2, 3, 4, 5, 6])
    #expect(page.drawnStrokes.map(\.id) == [6])
    #expect(page.strokes[0].status == .erased)
    #expect(page.strokes[1].role == .eraser)
    #expect(page.strokes[2].role == .lasso)
    #expect(page.strokes[3].kind == .frame)
}
