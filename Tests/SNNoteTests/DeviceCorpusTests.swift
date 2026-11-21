// Copyright 2026 ALTESSA SOLUTIONS INC.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import Foundation
import SNNote
import Testing

// Device notebooks in `SNNOTE_CORPUS` can cover newer firmware than the
// bundled fixtures. These checks verify decoding without recording handwriting.
@Suite(.enabled(if: DeviceCorpus.isAvailable, "set SNNOTE_CORPUS to directories of device notebooks"))
struct DeviceCorpusTests {
    @Test func everyDeviceNotebookReadsWhole() throws {
        let files = DeviceCorpus.files()
        #expect(!files.isEmpty)
        for url in files {
            let name = url.lastPathComponent
            let notebook = try SNParser.parse(Data(contentsOf: url))
            #expect(notebook.skippedPages == 0, "\(name)")
            for page in notebook.pages {
                #expect(page.skippedStrokes == 0, "\(name) p\(page.number)")
                #expect(page.strokes.allSatisfy { $0.style != nil }, "\(name) p\(page.number): a tail unread")
                let raster = try page.raster()
                #expect(raster.width == Int(page.size.width), "\(name) p\(page.number)")
            }
        }
    }
}
