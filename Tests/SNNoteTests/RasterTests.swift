// Copyright 2026 ALTESSA SOLUTIONS INC.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import CoreGraphics
import Foundation
import ImageIO
import SNNote
import Testing

// The raster's own API: building one, reading a pixel, stacking, and handing
// it to the platform as an image.

@Test func aRasterRefusesPlanesOfTheWrongSize() {
    #expect(SNRaster(width: 2, height: 2, gray: [0, 0, 0], alpha: [255, 255, 255, 255]) == nil)
    #expect(SNRaster(width: -1, height: 2, gray: [], alpha: []) == nil)
    #expect(SNRaster(width: Int.max, height: 2, gray: [], alpha: []) == nil)
    #expect(SNRaster(width: 2, height: 1, gray: [1, 2], alpha: [255, 255]) != nil)
}

@Test func aRasterTooLargeToCountIsEmpty() {
    let raster = SNRaster(width: Int.max, height: Int.max)
    #expect(raster.width == 0 && raster.height == 0 && raster.gray.isEmpty)
}

@Test func aPixelOutsideTheRasterIsNil() throws {
    let raster = try #require(SNRaster(width: 2, height: 1, gray: [10, 20], alpha: [255, 0]))
    #expect(raster.pixel(x: 1, y: 0)?.gray == 20)
    #expect(raster.pixel(x: 1, y: 0)?.alpha == 0)
    #expect(raster.pixel(x: 2, y: 0) == nil)
    #expect(raster.pixel(x: 0, y: 1) == nil)
    #expect(raster.pixel(x: -1, y: 0) == nil)
}

/// Covered replaces, uncovered shows through, half covered blends.
@Test func stackingBlendsByCoverage() throws {
    let top = try #require(SNRaster(width: 3, height: 1, gray: [0, 0, 0], alpha: [255, 0, 128]))
    let below = try #require(SNRaster(width: 3, height: 1, gray: [200, 200, 200], alpha: [255, 255, 255]))
    let stacked = try top.over(below)
    #expect(stacked.gray[0] == 0)
    #expect(stacked.gray[1] == 200)
    #expect((95...105).contains(stacked.gray[2]))
    #expect(stacked.alpha == [255, 255, 255])

    let wrong = SNRaster(width: 2, height: 1)
    #expect(throws: SNParseError.self) { try top.over(wrong) }
}

@Test func flatteningPutsTheRasterOnPaper() throws {
    let raster = try #require(SNRaster(width: 3, height: 1, gray: [0, 0, 0], alpha: [255, 0, 128]))
    let paper = raster.flattened()
    #expect(paper.gray[0] == 0)
    #expect(paper.gray[1] == 255)
    #expect((120...135).contains(paper.gray[2]))
    #expect(paper.alpha == [255, 255, 255])
}

/// A page's raster goes out as a PNG and comes back as the same greys.
@Test func aRasterRoundTripsThroughPNG() throws {
    let page = try Corpus.notebook("heading-n5-20260016-backgrounds-marker.note").pages[1]
    let raster = try page.raster()
    let image = try #require(raster.cgImage())
    #expect(image.width == raster.width && image.height == raster.height)

    let png = try #require(raster.pngData())
    let source = try #require(CGImageSourceCreateWithData(png as CFData, nil))
    let decoded = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    #expect(decoded.width == 1920 && decoded.height == 2560)
    let back = try Notelib.grayRaster(png: png)
    #expect(back.gray == raster.gray)
}

@Test func anEmptyRasterHasNoImage() {
    #expect(SNRaster(width: 0, height: 0).cgImage() == nil)
    #expect(SNRaster(width: 0, height: 0).pngData() == nil)
}
