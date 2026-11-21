// Copyright 2026 ALTESSA SOLUTIONS INC.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import CoreGraphics
import Foundation

/// One page of a notebook.
///
/// Two records of the same handwriting sit side by side here, and they are
/// not redundant. `layers` hold the tablet's own bitmaps — what it shows, at
/// the screen's resolution, eraser marks already applied. `strokes` hold the
/// pen's log — every motion, in vector form, with the tablet's verdict on each.
/// A thumbnail wants the first; anything that scales, searches or converts
/// wants the second.
public struct SNPage: Sendable, Hashable {
    /// The page's place in the notebook, counting from 1.
    public let number: Int
    /// The page's identity (`PAGEID`), which links point at. `nil` on files
    /// older than the field.
    public let id: String?
    /// The template's name (`PAGESTYLE`): `style_8mm_ruled_line_a5x2`, or
    /// `user_…` for one the user imported.
    public let template: String?
    public let orientation: SNOrientation
    /// The sheet in pixels, turned with the page.
    public let size: CGSize
    /// The layers the page stores, top first — the order the tablet stacks
    /// them, from `LAYERSEQ` — and after them any layer stored outside the
    /// stack (`SNLayer.isStacked`).
    public let layers: [SNLayer]
    /// The page's layer table.
    public let layerInfo: [SNLayerInfo]
    /// The stroke log, in the order the pen wrote it. See `SNStroke.isDrawn`
    /// for which of them the page shows.
    public let strokes: [SNStroke]
    /// Stroke records this version could not read. Counted so that a loss
    /// is visible rather than silent.
    public let skippedStrokes: Int
    /// What the tablet recognised in the handwriting, or `nil` when the page
    /// was never recognised.
    public let recognition: SNRecognition?
    /// The recognition engine's own working files for the page (a ZIP), kept
    /// as stored.
    public let recognitionArchive: Data?
    /// The regions where the pen does not write (`DISABLE`): the page's text
    /// boxes, in page pixels.
    public let disabledAreas: [CGRect]
    /// The page's block as stored, for keys this type does not name.
    public let metadata: SNMetadata
    /// What the codes in the page's RLE bitmaps mean — fixed by the file's
    /// format version (see `SNPalette`).
    public let palette: SNPalette

    /// The layer stored under `name`.
    public func layer(_ name: SNLayer.Name) -> SNLayer? {
        layers.first { $0.name == name }
    }

    /// The strokes the page shows: drawn records on a layer that is shown. A
    /// stroke on a hidden or deleted layer is the layer's, and goes with it.
    public var drawnStrokes: [SNStroke] {
        let hidden = Set(layers.filter { !$0.isVisible }.map(\.name.layerID))
        return strokes.filter { $0.isDrawn && !hidden.contains($0.layer) }
    }

    /// The page's text boxes: their text, font and place. The text itself is
    /// drawn into the layer's bitmap; these are what it says.
    public let textBoxes: [SNTextBox]

    /// The page as the tablet shows it, from its stored bitmaps: every visible
    /// layer stacked over the next, bottom up, on white.
    ///
    /// `includeBackground: false` leaves the template out — the handwriting
    /// alone, on white.
    ///
    /// The codes are read through `palette`, the one the file's format version
    /// writes them in unless another is given.
    public func raster(palette: SNPalette? = nil, includeBackground: Bool = true) throws -> SNRaster {
        let width = Int(size.width)
        let height = Int(size.height)
        var page = SNRaster(width: width, height: height)
        for layer in layers.reversed() where layer.isVisible {
            guard let bitmap = layer.bitmap else { continue }
            if layer.name == .background, !includeBackground { continue }
            page = try bitmap.raster(width: width, height: height, palette: palette ?? self.palette).over(page)
        }
        return page.flattened()
    }
}

extension SNPage {
    public init(
        number: Int,
        id: String?,
        template: String?,
        orientation: SNOrientation,
        size: CGSize,
        layers: [SNLayer],
        layerInfo: [SNLayerInfo],
        strokes: [SNStroke],
        skippedStrokes: Int,
        recognition: SNRecognition?,
        recognitionArchive: Data?,
        metadata: SNMetadata,
        palette: SNPalette = .current,
        disabledAreas: [CGRect] = []
    ) {
        self.init(number: number, id: id, template: template, orientation: orientation, size: size,
                  layers: layers, layerInfo: layerInfo, strokes: strokes, skippedStrokes: skippedStrokes,
                  recognition: recognition, recognitionArchive: recognitionArchive, disabledAreas: disabledAreas,
                  metadata: metadata, palette: palette,
                  textBoxes: strokes.compactMap(SNTextBox.init(stroke:)))
    }
}
