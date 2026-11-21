// Copyright 2026 ALTESSA SOLUTIONS INC.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import CryptoKit
import Foundation
import SNNote
import Testing

// Check decoded notebook pages and device mark layers against their recorded
// pixel digests. NotelibOracleTests also compares notebook pages with a
// running Private Cloud converter.
//
// After an intentional pixel change, check the affected pages, then run:
//
//     SNNOTE_RECORD_GOLDEN=1 swift test --filter everyPageDecodesToTheCheckedPixels
//
// Copy only the entries for the changed fixtures into `golden` below.

private func digest(_ raster: SNRaster) -> String {
    let hash = SHA256.hash(data: Data(raster.gray))
    return hash.prefix(12).map { String(format: "%02x", $0) }.joined()
}

private func fixtureFiles() throws -> [URL] {
    try Corpus.files().filter { $0.pathExtension == "note" } + Samples.files()
}

/// One file at a time, so the files decode side by side.
@Test(arguments: try fixtureFiles())
func everyPageDecodesToTheCheckedPixels(_ url: URL) throws {
    let notebook = try SNParser.parse(Data(contentsOf: url))
    let record = ProcessInfo.processInfo.environment["SNNOTE_RECORD_GOLDEN"] == "1"
    for page in notebook.pages {
        let name = "\(url.lastPathComponent)#\(page.number)"
        let actual = digest(try page.raster())
        if record {
            print("    \"\(name)\": \"\(actual)\",")
        } else {
            #expect(golden[name] == actual, "\(name)")
        }
    }
}

/// Every page of every fixture has a digest, and every digest a page.
@Test func theDigestsCoverEveryPage() throws {
    let names = try fixtureFiles().flatMap { url in
        try SNParser.parse(Data(contentsOf: url)).pages.map { "\(url.lastPathComponent)#\($0.number)" }
    }
    #expect(Set(golden.keys) == Set(names))
}

private let golden: [String: String] = [
    "blank-a6x-3.15.27-shapes-rtr.note#1": "d2e4feddd0b30805e3bd7d56",
    "blank-a6x-3.15.27-two-pages.note#1": "79779a283e0797f9a43f3b10",
    "blank-a6x-3.15.27-two-pages.note#2": "307f911a440a78574d9e5f31",
    "blank-a6x-3.26.40-two-pages.note#1": "e1d9db0f93b2fce5babb4c63",
    "blank-a6x-3.26.40-two-pages.note#2": "e1d9db0f93b2fce5babb4c63",
    "blank-n5-20230015-manta.note#1": "726a2d925efcdb19dc346d40",
    "caligraphy-n5-20260016-widths-erase.note#1": "7ec856a304e8e14ed18b1d50",
    "caligraphy-n5-20260016-widths-erase.note#2": "abc8418e2d7972e046fa41f3",
    "caligraphy-n5-20260016-widths-erase.note#3": "da9544b4d4bae2e16fcb7754",
    "caligraphy-n5-20260016-widths-erase.note#4": "73ed55da9b2c99fe9e9decf7",
    "color-n6-20230015-unknown-palette.note#1": "c98c27083d0eb3c3fbb60513",
    "demo-a5x-20230015-1to10.note#1": "6616eca90b232fc2967f278b",
    "demo-a5x-20230015-1to10.note#2": "5bc6905cf1bc0a0e42389058",
    "demo-a5x-20230015-1to10.note#3": "cbda8c45d34abb73bfba0a8d",
    "demo-a5x-20230015-1to10.note#4": "d654d99c5b09c7da9d4f3689",
    "demo-a5x-20230015-1to10.note#5": "df4ddcd59d11fe2d6984a76f",
    "demo-a5x-20230015-1to10.note#6": "b3965ff3831cbf4117d72a4c",
    "demo-a5x-20230015-1to10.note#7": "1e189466d817312dabcc0311",
    "demo-a5x-20230015-1to10.note#8": "c6d67af3fa8061580627f27e",
    "demo-a5x-20230015-1to10.note#9": "8ca9e6187c271234b9463355",
    "demo-a5x-20230015-1to10.note#10": "a23e0cefb7f45d20c76b836d",
    "erase-n5-20260016-all-mechanisms.note#1": "b5a66a072466849eee75a687",
    "erase-n5-20260016-mixed-colors.note#1": "d864063d4a18c5d281ab1636",
    "erase-n5-20260016-mixed-colors.note#2": "0cd57b8df1b176df23b6236c",
    "erase-n5-20260016-no-white-pen.note#1": "2af9d7cdd117f4bddfb09f84",
    "erase-n5-20260016-white-pen-cover.note#1": "8dcbb53bb56c2683530346da",
    "erase-n5-20260016-white-pen-cover.note#2": "2840b5aaa54e8781ea08de11",
    "erase-n5-20260016-white-pen-cover.note#3": "71d4c708e36a4b9a25729a45",
    "erase-n5-20260016-white-pen-cover.note#4": "710c222ef54bf0bfe5a2b874",
    "erase-n6-20230015-horizontal-1270.note#1": "0ab2758c1cc4d1166170b0c0",
    "heading-n5-20260016-backgrounds-marker.note#1": "1df4eb9569ee2ea7ef753817",
    "heading-n5-20260016-backgrounds-marker.note#2": "1d1887d422d6f5fafe863643",
    "heading-n5-20260016-backgrounds-marker.note#3": "ea729049f974e388d9ec5f0b",
    "ink-a5x-2.14.28-old-pen-width.note#1": "340acc2ef470e974560bf42e",
    "layout-n5-20230015-horizontal-1090.note#1": "0ea790d0da431787803a51b3",
    "layout-n5-20230015-vertical-1000.note#1": "726a2d925efcdb19dc346d40",
    "layout-n6-20230015-vertical-1180.note#1": "46eeabc1ecae20045f497ea3",
    "line-n5-20260016-ruler-tool.note#1": "6689605e3b6d09965153e7d2",
    "line-n5-20260016-ruler-tool.note#2": "a9fa7f546071bcd321fec1bf",
    "line-n5-20260016-ruler-tool.note#3": "2af9d7cdd117f4bddfb09f84",
    "link-n6-3.26.40-partial-erase-3p.note#1": "d7dbf25db479bdbf1f48f362",
    "link-n6-3.26.40-partial-erase-3p.note#2": "edc5769eb090f17121039742",
    "link-n6-3.26.40-partial-erase-3p.note#3": "5ee6c72db9e2bd8336c2cd65",
    "render-n6-20230015-moonchild-user-bg.note#1": "7c0b58b02547a813b0420baf",
    "rtr-n5-20230015-recognition.note#1": "e67d13917d61fe5d12261407",
    "sticker-n5-20260016-plugin-artwork.note#1": "c901129db39a46265dfa585b",
    "sticker-n5-20260016-plugin-artwork.note#2": "1c97fb0ab646d5a284a6a72f",
    "sticker-n5-20260016-plugin-artwork.note#3": "2af9d7cdd117f4bddfb09f84",
    "stroke-n5-20260016-20260809.note#1": "447872b30a3fdff4b0e04d03",
    "stroke-n5-20260016-20260809.note#2": "bd482d759c807c7d5e55b857",
    "stroke-n5-20260016-20260809.note#3": "b79dd0a9df14056fad8a0c27",
    "stroke-n5-20260016-20260809.note#4": "22068c45f42262cd786efb00",
    "stroke-n5-20260016-20260809.note#5": "2af9d7cdd117f4bddfb09f84",
    "stroke-n5-20260016-isolation-tools-colors-widths.note#1": "614f5454ac929bd3d6048127",
    "stroke-n5-20260016-isolation-tools-colors-widths.note#2": "cadb6e65070418559d601490",
    "stroke-n5-20260016-isolation-tools-colors-widths.note#3": "0dbc9397b0d71f512902d583",
    "stroke-n5-20260016-isolation-tools-colors-widths.note#4": "0153467b6a68553f9c0c85e4",
    "stroke-n5-20260016-isolation-tools-colors-widths.note#5": "487e6ee61bf9215d62b95801",
    "test-a5x-20220011-old-pen-ids.note#1": "6339edc9e3c054e2bd2676e9",
    "test-a5x-20220011-old-pen-ids.note#2": "af9adb707def638ffa42073c",
    "turkish-a6x-20230015-handwriting-erase.note#1": "2b957932b99a75f02b440df5",
    "epub-n6-20260016.mark#22": "e1d9db0f93b2fce5babb4c63",
    "pdf-highlights-n6-20260016.mark#1": "18f2f3f233e0ace7ce8f385e",
    "layers-dense-n6-20260016.note#1": "b00ca0b452c280c0eb745b61",
    "picture-links-cover-n6-20260016.note#1": "8c8aa7d05a4e349fdcd04c48",
    "picture-links-cover-n6-20260016.note#2": "97488e96180ac708ae3faed9",
    "textbox-links-n6-20260016.note#1": "be63d6994260cd7d359008ad",
    "textbox-links-n6-20260016.note#2": "ce762b71aad7b7098c0c28e4",
]
