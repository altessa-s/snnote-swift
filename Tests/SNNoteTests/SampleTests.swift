// Copyright 2026 ALTESSA SOLUTIONS INC.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import CoreGraphics
import Foundation
import SNNote
import Testing

// Notebooks made to hold one feature each (`Fixtures/samples`).

private let textBoxesAndLinks = "textbox-links-n6-20260016.note"

/// Three Cyrillic text boxes retain their font path, sizes and positions.
@Test func textBoxesCarryTheirTextFontAndPlace() throws {
    let page = try Samples.notebook(textBoxesAndLinks).pages[0]
    let boxes = page.textBoxes
    #expect(boxes.map(\.text) == [
        "Проверка текстового блока",
        "Проверка текстового блока 2, другой размер",
        "Еще один текстовый блок",
    ])
    #expect(boxes.map(\.fontSize) == [48, 68, 40])
    #expect(boxes.map(\.fontPath) == [
        "/system/fonts/Sample.ttf",
        "/system/fonts/Sample.ttf",
        "/system/fonts/Sample.ttf",
    ])
    #expect(boxes.map(\.rect) == [
        CGRect(x: 136, y: 372, width: 1244, height: 64),
        CGRect(x: 114, y: 745, width: 1234, height: 154),
        CGRect(x: 132, y: 1013, width: 1197, height: 52),
    ])
    // The page fences the boxes off from the pen, in the same rectangles.
    #expect(page.disabledAreas == boxes.map(\.rect))
    // A text box's frame is not ink.
    #expect(page.drawnStrokes.allSatisfy { $0.category != .textBox && $0.kind != .frame })
}

/// A link to a page of the same notebook, and a link to the web.
@Test func linksReachAPageAndTheWeb() throws {
    let notebook = try Samples.notebook(textBoxesAndLinks)
    #expect(notebook.links.count == 2)

    let toPage = notebook.links[0]
    #expect(toPage.targetPath == "/storage/emulated/0/Note/sample.note")
    #expect(toPage.kind == 0)
    #expect(toPage.pageNumber == 1)
    #expect(toPage.targetFileID == notebook.fileID)
    #expect(toPage.targetPageNumber == 2)
    #expect(notebook.pages.first { $0.id == toPage.targetPageID }?.number == 2)
    #expect(toPage.url == nil)

    let toWeb = notebook.links[1]
    #expect(toWeb.kind == 4)
    #expect(toWeb.url == URL(string: "https://example.com"))
    #expect(toWeb.targetFileID == nil)
    #expect(toWeb.targetPageID == nil)

    // Each link's frame in the stroke log names the same target.
    let frames = notebook.pages[0].strokes.filter { $0.category == .link }
    #expect(frames.count == 2)
    #expect(frames.allSatisfy { !$0.isDrawn })
    #expect(frames[1].attributes.contains("https://example.com"))
}

/// A heading over an imported template, and the template itself.
@Test func aHeadingOnAnImportedTemplate() throws {
    let notebook = try Samples.notebook(textBoxesAndLinks)
    #expect(notebook.titles.map(\.style.rawValue) == [1_000_254])
    #expect(notebook.titles.first?.rect == CGRect(x: 840, y: 263, width: 256, height: 78))
    let page = notebook.pages[0]
    #expect(page.template == "user_Sample")
    #expect(page.layer(.background)?.bitmap?.encoding == .png)
    #expect(page.strokes.contains { $0.category == .heading && $0.isDrawn })
}

/// The whole sample reads: no page lost, no record skipped, every tail read.
@Test func samplesReadWhole() throws {
    for url in try Samples.files() {
        let notebook = try SNParser.parse(Data(contentsOf: url))
        #expect(notebook.skippedPages == 0, "\(url.lastPathComponent)")
        for page in notebook.pages {
            #expect(page.skippedStrokes == 0)
            #expect(page.strokes.allSatisfy { $0.style != nil })
            #expect(try page.raster().width == Int(page.size.width))
        }
    }
}

private let pictureLinksCover = "picture-links-cover-n6-20260016.note"

/// A link to a document, a link over a text box, a tag with no region, and a
/// picture chosen as the cover.
@Test func linksToADocumentAndOverATextBox() throws {
    let notebook = try Samples.notebook(pictureLinksCover)
    let document = try #require(notebook.links.first { $0.kind == 2 })
    #expect(document.targetPath == "/storage/emulated/0/Document/sample.epub")
    #expect(document.targetFileID == nil)
    #expect(document.rect == CGRect(x: 454, y: 256, width: 328, height: 225))

    let toPage = try #require(notebook.links.first { $0.kind == 0 })
    #expect(toPage.targetPath == "/storage/emulated/0/Note/sample.note")
    #expect(notebook.pages.first { $0.id == toPage.targetPageID }?.number == 2)
    // That link sits over the page's one text box.
    let box = try #require(notebook.pages[0].textBoxes.first)
    #expect(box.text == "Текст для проверки Ссылки")
    #expect(toPage.rect.intersects(box.rect))

    #expect(notebook.keywords.map(\.text) == ["Test"])
    #expect(notebook.keywords.first?.rect == .zero)

    #expect(notebook.coverType == 2)
    #expect(notebook.cover?.encoding == .png)
    // A page with nothing written on it has no stroke log at all.
    #expect(notebook.pages[1].strokes.isEmpty)
}

/// Every link's footer block has its record in the stroke log of the page it
/// is on, whose fields say the same: type, style, timestamp, rect and target.
@Test func aLinksRecordRepeatsItsFooterBlock() throws {
    for name in [textBoxesAndLinks, pictureLinksCover] {
        let notebook = try Samples.notebook(name)
        #expect(notebook.links.count == 2, "\(name)")
        for link in notebook.links {
            let records = notebook.pages[link.pageNumber - 1].strokes.filter { $0.category == .link }
            let record = try #require(records.first { $0.attributes.count > 9 && $0.attributes[3] == link.timestamp })
            let fields = record.attributes
            #expect(fields[0] == String(link.kind), "\(name)")
            #expect(fields[2] == String(link.style), "\(name)")
            #expect(fields[4] == link.metadata["LINKRECT"], "\(name)")
            #expect(fields[6] == link.targetPath, "\(name)")
            #expect(fields[7] == link.targetFileID ?? "none", "\(name)")
            #expect(fields[8] == link.targetPageID ?? "none", "\(name)")
            #expect(fields[9] == String(link.targetPageNumber ?? 0), "\(name)")
            #expect(record.style == UInt32(link.style), "\(name)")
            #expect(record.bounds.insetBy(dx: -2, dy: -2).contains(link.rect.insetBy(dx: 2, dy: 2)), "\(name)")
        }
    }
}

private let layersDense = "layers-dense-n6-20260016.note"

/// Three drawing layers: layer 1 shown, layer 2 hidden, layer 3 deleted. The
/// layer table is stored in base64 here, and the hidden layer is left out of
/// the stack while its bitmap and strokes stay in the file.
@Test func aHiddenLayerIsStoredButNotShown() throws {
    let page = try Samples.notebook(layersDense).pages[0]
    #expect(page.layerInfo.map(\.layerID) == [3, 2, 1, 0, -1])
    #expect(page.layerInfo.first { $0.layerID == 2 }?.isVisible == false)
    #expect(page.layerInfo.first { $0.layerID == 3 }?.isDeleted == true)

    #expect(page.layers.map(\.name) == [.layer1, .main, .background, .layer2])
    let hidden = try #require(page.layer(.layer2))
    #expect(!hidden.isStacked)
    #expect(!hidden.isVisible)
    #expect(hidden.bitmap != nil)
    #expect(page.layer(.layer1)?.isVisible == true)

    // Its strokes are in the log and not on the page.
    #expect(page.strokes.filter { $0.layer == 2 }.count == 6)
    #expect(page.drawnStrokes.allSatisfy { $0.layer != 2 })
    #expect(page.drawnStrokes.count == 48)
}

/// Annotations over an EPUB: a `.mark`, holding only the document's pages
/// that carry anything — here page 22 — with its mark-specific header and footer.
@Test func aMarkHoldsOnlyTheDocumentsAnnotatedPages() throws {
    let url = try Samples.url("epub-n6-20260016.mark")
    let data = try Data(contentsOf: url)
    let mark = try SNParser.parse(data)
    #expect(mark.kind == .mark)
    #expect(mark.header["FILE_TYPE"] == "MARK")
    #expect(mark.header["APP_VERSION"] == "3")
    #expect(mark.footer["FILE_FEATURE"] == "24")
    #expect(mark.pages.map(\.number) == [22])

    let page = try #require(mark.pages.first)
    #expect(page.template == nil)
    #expect(page.layers.map(\.name) == [.main])
    // A stroke written and erased, then two selections: nothing is left.
    #expect(page.strokes.map(\.status) == [.erased, .live, .live])
    #expect(page.strokes.map(\.role) == [.ink, .lasso, .lasso])
    #expect(page.drawnStrokes.isEmpty)
    #expect(try page.raster().gray.allSatisfy { $0 == 255 })
    #expect(page.strokes.allSatisfy { $0.style != nil })
}

/// Highlights and an underline on a PDF's text, one with a comment, beside a
/// generated sine wave.
@Test func highlightsOnAPDFCarryTheirLinesAndComment() throws {
    let mark = try Samples.notebook("pdf-highlights-n6-20260016.mark")
    #expect(mark.kind == .mark)
    #expect(mark.header["HIGHLIGHTINFO"] == "24")

    let marks = mark.highlights
    #expect(marks.map(\.pageNumber) == [1, 1, 1])
    #expect(marks.map(\.kind) == [0, 0, 1])
    #expect(marks.map(\.comment) == [nil, "Test comment", nil])
    #expect(marks.map(\.rects.count) == [3, 2, 2])
    #expect(marks[0].rects[0] == CGRect(x: 114, y: 538, width: 1159, height: 21))
    #expect(marks[0].documentRects[0] == CGRect(x: 50, y: 223, width: 505, height: 9))
    // An underline is a thin band under the line, not a block over it.
    #expect(marks[2].rects.allSatisfy { $0.height <= 3 })
    #expect(marks.allSatisfy { $0.date != nil })

    // The two coordinate systems are the document fitted to the sheet: one
    // scale, the page centred — the same mapping for every line.
    let pairs = marks.flatMap { zip($0.documentRects, $0.rects) }
    let scale = pairs[0].1.width / pairs[0].0.width
    for (document, sheet) in pairs {
        #expect(abs(sheet.minX - document.minX * scale) < 2)
        #expect(abs(sheet.maxY - (document.maxY * scale + 26)) < 2)
    }

    // Every centreline point on the wave coincides with ink in the stored bitmap.
    let page = try #require(mark.pages.first)
    #expect(page.drawnStrokes.count == 1)
    #expect(page.drawnStrokes[0].points.count == 440)
    let raster = try page.raster()
    let onInk = page.drawnStrokes[0].points.filter { point in
        let x = Int(point.position.x.rounded())
        let y = Int(point.position.y.rounded())
        return (-2...2).contains { dy in
            (-2...2).contains { dx in
                let px = x + dx
                let py = y + dy
                return px >= 0 && py >= 0 && px < raster.width && py < raster.height
                    && raster.gray[py * raster.width + px] < 250
            }
        }
    }
    #expect(onInk.count == page.drawnStrokes[0].points.count)
}

/// A notebook has no highlights.
@Test func aNotebookHasNoHighlights() throws {
    #expect(try Samples.notebook("textbox-links-n6-20260016.note").highlights.isEmpty)
}

/// A frame's box is the rectangle its corners make: a text box's frame is the
/// text box, a heading's box is the heading.
@Test func framesAreBoxedByTheirCorners() throws {
    let notebook = try Samples.notebook(textBoxesAndLinks)
    let page = notebook.pages[0]
    for box in page.textBoxes {
        let frame = try #require(page.strokes.first { $0.id == box.id })
        #expect(abs(frame.bounds.minX - box.rect.minX) <= 1)
        #expect(abs(frame.bounds.minY - box.rect.minY) <= 1)
        #expect(abs(frame.bounds.width - box.rect.width) <= 2)
        #expect(abs(frame.bounds.height - box.rect.height) <= 2)
    }
    let heading = try #require(page.strokes.first { $0.kind == .headingBox })
    let title = try #require(notebook.titles.first)
    #expect(abs(heading.bounds.minX - title.rect.minX) <= 2)
    #expect(abs(heading.bounds.width - title.rect.width) <= 2)
}
