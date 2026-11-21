// Copyright 2026 ALTESSA SOLUTIONS INC.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import Foundation
import SNNote
import Testing

// Every page of every file, decoded here, against the same page rendered by
// the converter of a running Supernote Private Cloud (see `Notelib`).
// Pixel for pixel: the palette and the layer stacking are the two things this
// package could get plausibly wrong, and only the tablet's own code can say
// what right is.
//
// A grey off by one is not a difference: the converter draws black as 1, and
// nothing anyone looks at can tell the two apart.

/// The pixels of `ours` that differ from `theirs` by more than `tolerance`
/// levels.
private func differingPixels(_ ours: SNRaster, _ theirs: SNRaster, tolerance: Int) -> Int {
    zip(ours.gray, theirs.gray).reduce(0) { count, pair in
        count + (abs(Int(pair.0) - Int(pair.1)) > tolerance ? 1 : 0)
    }
}

private func compareWithNotelib(_ url: URL) async throws {
    let data = try Data(contentsOf: url)
    let notebook = try SNParser.parse(data)
    let reference = try await Notelib.render(data)
    let name = url.lastPathComponent
    #expect(reference.count == notebook.pages.count, "\(name): page count")
    for (page, theirs) in zip(notebook.pages, reference) {
        let ours = try page.raster()
        #expect(ours.width == theirs.width && ours.height == theirs.height, "\(name) p\(page.number): size")
        guard ours.width == theirs.width, ours.height == theirs.height else { continue }
        // A page over a template imported as a PNG is composed in colour and
        // reduced to grey at the end, through a gamma-2.2 grey space rather
        // than sRGB: every grey on the page comes out a level or three darker
        // in the shadows and lighter in the highlights (63 → 60, 201 → 203).
        // A property of the converter's output, not of the file, so those
        // pages are held to four levels instead of one.
        let importedTemplate = page.layer(.background)?.bitmap?.encoding == .png
        let differing = differingPixels(ours, theirs, tolerance: importedTemplate ? 4 : 1)
        #expect(differing == 0, "\(name) p\(page.number): \(differing) pixels differ")
    }
}

@Suite(
    .serialized,
    .enabled(if: Notelib.isAvailable, "set SNNOTE_NOTELIB_CONTAINER to a Private Cloud service container")
)
struct NotelibOracleTests {
    @Test(arguments: try (Corpus.files() + Samples.files()).filter { $0.pathExtension == "note" })
    func corpusPageMatchesTheConvertersRender(_ url: URL) async throws {
        try await compareWithNotelib(url)
    }

    @Test(.enabled(if: DeviceCorpus.isAvailable, "set SNNOTE_CORPUS to directories of device notebooks"))
    func deviceNotebooksMatchTheConvertersRender() async throws {
        for url in DeviceCorpus.files() {
            try await compareWithNotelib(url)
        }
    }
}
