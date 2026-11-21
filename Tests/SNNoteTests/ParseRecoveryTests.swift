// Copyright 2026 ALTESSA SOLUTIONS INC.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import Foundation
import SNNote
import Testing

// What a file that will not wholly read does. A file that is not a notebook,
// or whose map of itself is gone, is an error; anything smaller costs only the
// part that would not read, and is counted.

@Test func bytesThatAreNotANotebookAreNamed() {
    #expect(throws: SNParseError.unsupportedFormat("%PDF-1.7????????????????")) {
        try SNParser.parse(Data("%PDF-1.7".utf8) + Data(count: 40))
    }
    // The first Supernotes wrote a container of their own; it is named, not
    // misread.
    #expect(throws: SNParseError.self) {
        try SNParser.parse(Data("noteSN_FILE_ASA_20190529".utf8) + Data(count: 40))
    }
    #expect(throws: SNParseError.unsupportedFormat("")) { try SNParser.parse(Data()) }
}

@Test func aFooterAddressOutsideTheFileIsAnError() {
    var file = NoteBuilder.onePage(strokeLog: nil)
    file.replaceSubrange((file.count - 4)..<file.count, with: le32(UInt32(file.count + 100)))
    #expect(throws: SNParseError.self) { try SNParser.parse(file) }
}

@Test func aFileCutShortIsAnError() {
    let file = NoteBuilder.onePage(strokeLog: nil)
    #expect(throws: SNParseError.self) { try SNParser.parse(file.prefix(30)) }
}

/// A slice of a larger buffer reads the same as a copy of it.
@Test func aSliceReadsLikeACopy() throws {
    let file = NoteBuilder.onePage(strokeLog: NoteBuilder.strokeLog([NoteBuilder.strokeRecord()]))
    let padded = Data(count: 13) + file
    let slice = padded[13...]
    #expect(try SNParser.parse(slice) == SNParser.parse(file))
}

/// A stroke record that will not read costs that stroke, and the next is read
/// all the same: the walk steps by the record's declared length.
@Test func anUnreadableStrokeIsCountedAndSteppedOver() throws {
    let broken = Data(count: 20)  // a record far shorter than its header
    let log = NoteBuilder.strokeLog([
        NoteBuilder.strokeRecord(id: 1),
        broken,
        NoteBuilder.strokeRecord(id: 3),
    ])
    let page = try #require(try SNParser.parse(NoteBuilder.onePage(strokeLog: log)).pages.first)
    #expect(page.strokes.map(\.id) == [1, 3])
    #expect(page.skippedStrokes == 1)
}

/// A log that claims more records than it holds keeps those it has and counts
/// the rest.
@Test func aLogCutShortKeepsWhatItHas() throws {
    var log = NoteBuilder.strokeLog([NoteBuilder.strokeRecord(id: 1), NoteBuilder.strokeRecord(id: 2)])
    log.replaceSubrange(0..<4, with: le32(5))
    let page = try #require(try SNParser.parse(NoteBuilder.onePage(strokeLog: log)).pages.first)
    #expect(page.strokes.map(\.id) == [1, 2])
    #expect(page.skippedStrokes == 3)
}

/// A count the file declares is a declaration, not a measurement: believed,
/// four billion points is a reservation nobody has the memory for.
@Test func aHugeDeclaredCountIsRefusedNotReserved() throws {
    var record = NoteBuilder.strokeRecord(id: 1)
    record.replaceSubrange(212..<216, with: le32(0xFFFF_FFF0))  // the point count
    let page = try #require(
        try SNParser.parse(NoteBuilder.onePage(strokeLog: NoteBuilder.strokeLog([record]))).pages.first
    )
    #expect(page.strokes.isEmpty)
    #expect(page.skippedStrokes == 1)
}

/// A page whose block points outside the file is left out and counted; the
/// notebook's other pages are read.
@Test func anUnreadablePageIsCountedAndTheRestKept() throws {
    var builder = NoteBuilder()
    let header = builder.append(tags: [("APPLY_EQUIPMENT", "N6")])
    let page = builder.append(tags: [("PAGESTYLE", "style_white"), ("PAGEID", "P2")])
    let file = builder.finish(footer: [
        ("FILE_FEATURE", String(header)),
        ("PAGE1", "99999999"),
        ("PAGE2", String(page)),
    ])
    let notebook = try SNParser.parse(file)
    #expect(notebook.pages.map(\.number) == [2])
    #expect(notebook.skippedPages == 1)
}

/// The sheet of a device this version does not know is measured from its
/// bitmaps.
@Test func anUnknownDeviceHasItsSheetMeasured() throws {
    var builder = NoteBuilder()
    let header = builder.append(tags: [("APPLY_EQUIPMENT", "X9")])
    let bitmap = builder.append(NoteBuilder.blankRLE(pixels: 1920 * 2560))
    let layer = builder.append(tags: [("LAYERBITMAP", String(bitmap))])
    let page = builder.append(tags: [("MAINLAYER", String(layer)), ("LAYERSEQ", "MAINLAYER")])
    let file = builder.finish(footer: [("FILE_FEATURE", String(header)), ("PAGE1", String(page))])
    let notebook = try SNParser.parse(file)
    #expect(notebook.equipment == .other("X9"))
    #expect(notebook.sheet == CGSize(width: 1920, height: 2560))
}

/// Mutated corpus files must never take the process down: a file arrives from
/// a device or a sync service, and a trap inside somebody's app is the one
/// failure nothing can catch. Whatever a mutation does, the answer is a
/// notebook or a thrown error.
@Test(arguments: [
    "blank-a6x-3.15.27-two-pages.note",
    "heading-n5-20260016-backgrounds-marker.note",
    "test-a5x-20220011-old-pen-ids.note",
    "erase-n6-20230015-horizontal-1270.note",
])
func mutatedFilesThrowOrParseButNeverTrap(file: String) throws {
    let original = try Data(contentsOf: Corpus.url(file))
    var generator = SplitMix64(seed: 0x5EED)
    for round in 0..<60 {
        var mutated = original
        for _ in 0..<(1 + round % 8) {
            let index = Int(generator.next() % UInt64(mutated.count))
            mutated[index] = UInt8(truncatingIfNeeded: generator.next())
        }
        if round.isMultiple(of: 10) {
            mutated = mutated.prefix(Int(generator.next() % UInt64(mutated.count)))
        }
        _ = try? SNParser.parse(mutated)
    }
}

/// The same for a bitmap: any bytes decode to a sheet or throw.
@Test func mutatedBitmapsThrowOrDecodeButNeverTrap() throws {
    let template = try #require(Corpus.notebook("color-n6-20230015-unknown-palette.note").templates["style_task_list"])
    var generator = SplitMix64(seed: 0xB17)
    for round in 0..<300 {
        var bytes = template.data.prefix(64 + round)
        for _ in 0..<(1 + round % 4) {
            let index = bytes.startIndex + Int(generator.next() % UInt64(bytes.count))
            bytes[index] = UInt8(truncatingIfNeeded: generator.next())
        }
        let bitmap = SNBitmap(encoding: .rattaRLE, data: Data(bytes))
        _ = try? bitmap.raster(width: 97, height: 83, palette: .current)
        _ = try? SNBitmap(encoding: .png, data: Data(bytes)).raster(width: 97, height: 83)
    }
}

/// A small deterministic generator: the same mutations every run, so a
/// failure is reproducible.
private struct SplitMix64 {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// A page saved again leaves its `PAGE<n>` in the footer twice; the later one
/// is the page, and the notebook has it once.
@Test func aRepeatedPageKeyNamesThePageOnce() throws {
    var builder = NoteBuilder()
    let header = builder.append(tags: [("APPLY_EQUIPMENT", "N6")])
    let old = builder.append(tags: [("PAGEID", "P-old")])
    let new = builder.append(tags: [("PAGEID", "P-new")])
    let file = builder.finish(footer: [
        ("FILE_FEATURE", String(header)), ("PAGE1", String(old)), ("PAGE1", String(new)),
    ])
    let notebook = try SNParser.parse(file)
    #expect(notebook.pages.map(\.id) == ["P-new"])
}

/// A heading saved again leaves its key twice with the same box: one heading,
/// the later. Two headings that share a key but not a box are two.
@Test func aResavedHeadingIsOneHeading() throws {
    var builder = NoteBuilder()
    let header = builder.append(tags: [("APPLY_EQUIPMENT", "N6")])
    let first = builder.append(tags: [("TITLERECT", "10,20,30,40"), ("TITLESTYLE", "1000254")])
    let again = builder.append(tags: [("TITLERECT", "10,20,30,40"), ("TITLESTYLE", "1201000")])
    let other = builder.append(tags: [("TITLERECT", "500,20,30,40"), ("TITLESTYLE", "1000000")])
    let file = builder.finish(footer: [
        ("FILE_FEATURE", String(header)),
        ("TITLE_000100200010", String(first)),
        ("TITLE_000100200010", String(again)),
        ("TITLE_000100200010", String(other)),
    ])
    let titles = try SNParser.parse(file).titles
    #expect(titles.map(\.style.rawValue) == [1_201_000, 1_000_000])
}

/// The annotation types can be built outside the parser — for a consumer's
/// own tests and previews.
@Test func annotationsCanBeBuiltByHand() {
    let link = SNLink(pageNumber: 1, rect: .zero, kind: 4, targetPath: "https://example.com")
    #expect(link.url == URL(string: "https://example.com"))
    let title = SNTitle(
        pageNumber: 1, level: 1, rect: .zero, originalRect: .zero, bitmap: nil,
        style: SNTitle.Style(rawValue: 1_000_000)
    )
    #expect(title.style.isHatched)
    #expect(SNKeyword(pageNumber: 2, rect: .zero, originalRect: .zero, text: "tag").text == "tag")
    #expect(SNTextBox(id: 1, rect: .zero, text: "box").text == "box")
    #expect(SNHighlight(pageNumber: 1, kind: 1, rects: []).kind == 1)
}
