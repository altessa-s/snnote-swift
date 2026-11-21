// Copyright 2026 ALTESSA SOLUTIONS INC.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import CoreGraphics
import Foundation
import SNNote
import Testing

// What the footer records beside the pages — headings, keywords, links — and
// what the tablet recognised on a page.

/// Four headings, one per background the tablet offers: black, dark grey,
/// light grey, hatched. The style's digits say the box's grey and the grey
/// the writing inside is shown in.
@Test func headingStylesSpellTheirGreys() throws {
    let titles = try Corpus.notebook("heading-n5-20260016-backgrounds-marker.note").titles
    #expect(titles.map(\.style.rawValue) == [1_000_254, 1_157_254, 1_201_000, 1_000_000])
    #expect(titles.map(\.style.background) == [0, 157, 201, 0])
    #expect(titles.map(\.style.foreground) == [254, 254, 0, 0])
    #expect(titles.map(\.style.isHatched) == [false, false, false, true])
    #expect(titles.allSatisfy { $0.pageNumber == 2 && $0.level == 1 })
    #expect(titles[0].rect == CGRect(x: 500, y: 329, width: 356, height: 148))
    let bitmap = try #require(titles[0].bitmap)
    #expect(bitmap.encoding == .rattaRLE)
}

/// A heading's box is the same rectangle the stroke log holds for it.
@Test func aHeadingsRectIsItsBoxRecord() throws {
    let notebook = try Corpus.notebook("heading-n5-20260016-backgrounds-marker.note")
    let boxes = notebook.pages[1].strokes.filter { $0.kind == .headingBox }
    for title in notebook.titles {
        let matched = boxes.contains { box in
            let corners = box.points.map(\.position)
            let rect = CGRect(
                x: min(corners[0].x, corners[1].x),
                y: min(corners[0].y, corners[1].y),
                width: abs(corners[0].x - corners[1].x),
                height: abs(corners[0].y - corners[1].y)
            )
            return abs(rect.minX - title.rect.minX) <= 2 && abs(rect.minY - title.rect.minY) <= 2
                && abs(rect.width - title.rect.width) <= 2 && abs(rect.height - title.rect.height) <= 2
        }
        #expect(matched, "\(title.rect)")
    }
}

@Test func keywordsCarryTheirText() throws {
    let old = try Corpus.notebook("test-a5x-20220011-old-pen-ids.note").keywords
    #expect(old.map(\.text) == ["dummy", "Different"])
    #expect(old.map(\.pageNumber) == [1, 2])

    // A tag has no inline copy of its text and no page of its own; the text is
    // in its block and the page in its key.
    let tags = try Corpus.notebook("link-n6-3.26.40-partial-erase-3p.note").keywords
    #expect(tags.map(\.text) == ["Supemote Keyword", "Multiple keywords", "New tag"])
    #expect(tags.map(\.pageNumber) == [3, 3, 3])
}

@Test func linksPointAtTheirTargets() throws {
    let notebook = try Corpus.notebook("link-n6-3.26.40-partial-erase-3p.note")
    #expect(notebook.links.count == 3)
    let first = notebook.links[0]
    #expect(first.pageNumber == 2)
    #expect(first.rect == CGRect(x: 118, y: 1253, width: 743, height: 132))
    #expect(first.targetPath == "/storage/emulated/0/Note/Perso/Obsidian plugin test/nomad-3.26.40-link-tag-3p.note")
    #expect(first.targetFileID == "F20260603095359900766vRyIMdOjySUH")
    #expect(first.targetPageID == "P20240303144624294784hYDadze19JFd")
    // A link to a file names no page.
    #expect(notebook.links[2].kind == 1)
    #expect(notebook.links[2].targetPageID == nil)
}

/// A link to a page of the same notebook names that page's identity.
@Test func aLinkWithinTheNotebookFindsItsPage() throws {
    let notebook = try Corpus.notebook("blank-a6x-3.15.27-two-pages.note")
    let link = try #require(notebook.links.first)
    #expect(link.pageNumber == 2)
    #expect(notebook.pages.first { $0.id == link.targetPageID }?.number == 1)
    #expect(notebook.fileID == link.targetFileID)
}

@Test func recognitionIsReadOutOfThePage() throws {
    let page = try Corpus.notebook("blank-a6x-3.15.27-shapes-rtr.note").pages[0]
    let recognition = try #require(page.recognition)
    #expect(recognition.text == "Square\nTriangle\nCircle\nStar")
    let words = recognition.elements[0].words
    #expect(words.map(\.label) == ["Square", "\n", "Triangle", "\n", "Circle"])
    #expect(words[1].box == nil)
    #expect(words[0].box?.minX ?? 0 > 5)
    // The engine's working files ride along as stored.
    #expect(page.recognitionArchive?.starts(with: Array("PK".utf8)) == true)
}

/// Text beyond ASCII survives: the stored JSON is UTF-8 under base64.
@Test func recognitionKeepsItsAlphabet() throws {
    let page = try Corpus.notebook("turkish-a6x-20230015-handwriting-erase.note").pages[0]
    let text = try #require(page.recognition?.text)
    #expect(text.hasPrefix("Şimdi ben buraya neden çıktım?"))
}

/// Recognised and found nothing is not the same as never recognised.
@Test func emptyRecognitionIsNotAbsentRecognition() throws {
    let notebook = try Corpus.notebook("heading-n5-20260016-backgrounds-marker.note")
    #expect(notebook.pages[1].recognition?.elements.isEmpty == true)
    #expect(notebook.pages[2].recognition == nil)
}
