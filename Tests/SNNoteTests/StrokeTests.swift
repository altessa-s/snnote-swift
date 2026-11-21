// Copyright 2026 ALTESSA SOLUTIONS INC.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import CoreGraphics
import Foundation
import SNNote
import Testing

// The stroke record decoded field by field, against pages that isolate one
// tool, colour or width each.

private let isolation = "stroke-n5-20260016-isolation-tools-colors-widths.note"

/// Page 2: one stroke per tool — needle point, ink pen, marker, calligraphy.
@Test func eachToolHasItsOwnNumber() throws {
    let strokes = try Corpus.notebook(isolation).pages[1].drawnStrokes
    #expect(Set(strokes.map(\.pen)) == [.needlePoint, .inkPen, .marker, .calligraphy])
    let marker = try #require(strokes.first { $0.pen == .marker })
    // The marker writes its colour `+1`.
    #expect(marker.color.rawValue == 1)
    #expect(marker.color.isMarkerForm)
    #expect(marker.color.gray == 0)
    #expect(marker.thickness == 3800)
}

/// Page 3: one ink-pen stroke per colour — black, dark grey, light grey, white.
@Test func coloursAreTheGreysThemselves() throws {
    let strokes = try Corpus.notebook(isolation).pages[2].drawnStrokes
    #expect(strokes.map(\.color.rawValue) == [0, 157, 201, 254])
    #expect(strokes.map(\.color.gray) == [0, 157, 201, 254])
}

/// Page 4: one needle-point stroke per width — 1.0, 0.6, 0.3, 0.1 on the
/// slider, which the tablet's own export draws 12, 7, 4 and 2 pixels wide.
@Test func thicknessIsHundredthsOfAPixel() throws {
    let strokes = try Corpus.notebook(isolation).pages[3].drawnStrokes
    #expect(strokes.map(\.thickness) == [1200, 700, 400, 200])
}

/// The oldest file numbers its tools and greys differently: ink pen `1`,
/// marker `5`, and the greys as ids `48` and `81` — which the tablet's export
/// of that file draws as 157 and 201.
@Test func theOldestFileUsesTheOldNumbers() throws {
    let strokes = try Corpus.notebook("test-a5x-20220011-old-pen-ids.note").pages[0].drawnStrokes
    let pens = Set(strokes.filter { $0.kind == .freehand }.map(\.pen))
    #expect(pens == [.inkPenLegacy, .markerLegacy])
    let greys = strokes.filter { $0.color.rawValue == 48 }
    #expect(greys.count == 21)
    #expect(greys.allSatisfy { $0.color.gray == 157 })
    let markers = strokes.filter { $0.pen == .markerLegacy }
    #expect(markers.count == 3)
    #expect(markers.allSatisfy { $0.color.rawValue == 81 && $0.color.gray == 201 && $0.color.isMarkerForm })
}

@Test func strokeKindsAreNamedByTheRecord() throws {
    // A heading's box: two points, opposite corners.
    let headings = try Corpus.notebook("heading-n5-20260016-backgrounds-marker.note").pages[1].strokes
        .filter { $0.kind == .headingBox }
    #expect(headings.count == 4)
    #expect(headings.allSatisfy { $0.points.count == 2 && $0.role == .derived && $0.isDrawn })

    // A ruled line: two points, its ends — not a box.
    let lines = try Corpus.notebook("line-n5-20260016-ruler-tool.note").pages[0].strokes
    #expect(lines.count == 6)
    #expect(lines.allSatisfy { $0.kind == .straightLine && $0.points.count == 2 })

    // A star mark, whose pen the tablet overwrote.
    let star = try #require(
        Corpus.notebook("blank-a6x-3.15.27-shapes-rtr.note").pages[0].strokes.first { $0.kind == .star }
    )
    #expect(star.pen == .markerLegacy)
    #expect(star.thickness == 100)
}

/// A link's frame and a lasso loop are records of the page, never ink.
@Test func framesAndLassoesAreNotDrawn() throws {
    let notebook = try Corpus.notebook("link-n6-3.26.40-partial-erase-3p.note")
    // The links are drawn on page 2; the keywords were lassoed on page 3.
    let frames = notebook.pages[1].strokes.filter { $0.kind == .frame }
    let lassoes = notebook.pages[2].strokes.filter { $0.role == .lasso }
    #expect(!frames.isEmpty)
    #expect(!lassoes.isEmpty)
    #expect(frames.allSatisfy { !$0.isDrawn })
    #expect(lassoes.allSatisfy { !$0.isDrawn })
    #expect(lassoes.allSatisfy { $0.pen == .lasso })
}

/// A partial erase marks the stroke `-4` and writes what survived as records
/// of their own: no centreline, only an outline. The page shows the pieces and
/// not the stroke.
@Test func aPartialEraseLeavesItsPiecesAsOutlines() throws {
    let page = try Corpus.notebook("blank-a6x-3.15.27-two-pages.note").pages[1]
    let cut = page.strokes.filter { $0.status == .partiallyErased }
    #expect(cut.count == 10)
    #expect(cut.allSatisfy { !$0.isDrawn })
    let pieces = page.drawnStrokes.filter { $0.points.isEmpty }
    #expect(!pieces.isEmpty)
    #expect(pieces.allSatisfy { !$0.contour.isEmpty })
}

@Test func removalStatusesAreDecoded() throws {
    let deleted = try Corpus.notebook("color-n6-20230015-unknown-palette.note").pages[0].strokes
    #expect(deleted.filter { $0.status == .deleted }.count == 33)
    let moved = try Corpus.notebook("erase-n5-20260016-mixed-colors.note").pages[1].strokes
    #expect(moved.filter { $0.status == .moved }.count == 9)
    let cleared = try Corpus.notebook("line-n5-20260016-ruler-tool.note").pages[2].strokes
    #expect(cleared.map(\.status) == [.cleared])
}

/// The outline is in page pixels, around the centreline: its box is the
/// centreline's widened by about half the stroke.
@Test func theOutlineSurroundsTheCentreline() throws {
    let page = try Corpus.notebook("blank-n5-20230015-manta.note").pages[0]
    for stroke in page.drawnStrokes {
        let outline = stroke.contour.flatMap { $0 }
        guard !outline.isEmpty, stroke.points.count > 1 else { continue }
        let line = box(stroke.points.map(\.position))
        let ring = box(outline)
        let slack = Double(stroke.thickness) / 100 + 2
        #expect(ring.insetBy(dx: -slack, dy: -slack).contains(line), "stroke \(stroke.id)")
    }
}

/// The box the record declares agrees with its centreline.
@Test func theDeclaredBoundsHoldTheCentreline() throws {
    let page = try Corpus.notebook("turkish-a6x-20230015-handwriting-erase.note").pages[0]
    for stroke in page.drawnStrokes where stroke.points.count > 1 {
        let line = box(stroke.points.map(\.position))
        #expect(stroke.bounds.insetBy(dx: -2, dy: -2).contains(line), "stroke \(stroke.id)")
    }
}

/// Numbers are the page's own, counting from 1, and each stroke names its
/// page.
@Test func strokesNameTheirPage() throws {
    let notebook = try Corpus.notebook("demo-a5x-20230015-1to10.note")
    for page in notebook.pages {
        #expect(page.strokes.allSatisfy { $0.pageNumber == page.number })
    }
}

private func box(_ points: [CGPoint]) -> CGRect {
    let xs = points.map(\.x)
    let ys = points.map(\.y)
    guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else { return .null }
    return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
}
