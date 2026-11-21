// Copyright 2026 ALTESSA SOLUTIONS INC.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import Foundation

/// One of a page's five layers.
///
/// A page is a stack: up to three drawing layers and the main layer over a
/// background, which holds the template. Each stores a bitmap of what is on
/// it — the tablet's own rendering, the thing it shows — while the strokes
/// that made the drawing layers live in the page's stroke log.
public struct SNLayer: Sendable, Hashable {
    public let name: Name
    /// The layer's picture, or `nil` when the layer stores none.
    public let bitmap: SNBitmap?
    /// What the page's layer table says about this layer, when it says
    /// anything.
    public let info: SNLayerInfo?
    /// The layer's block as stored.
    public let metadata: SNMetadata

    /// Whether the layer is in the page's stack (`LAYERSEQ`). A layer the user
    /// hid is still stored, with its bitmap, and left out of the stack.
    public let isStacked: Bool

    /// Whether the tablet shows the layer: in the stack, and neither hidden
    /// nor deleted in the layer table. A layer the table does not describe
    /// is shown if it is stacked.
    public var isVisible: Bool {
        guard isStacked else { return false }
        guard let info else { return true }
        return info.isVisible && !info.isDeleted
    }

    public init(name: Name, bitmap: SNBitmap?, info: SNLayerInfo?, metadata: SNMetadata, isStacked: Bool = true) {
        self.name = name
        self.bitmap = bitmap
        self.info = info
        self.metadata = metadata
        self.isStacked = isStacked
    }

    /// The five slots, by the keys a page names them with.
    ///
    /// Frozen: an exhaustive `switch` over these cases in a consumer is the
    /// point.
    @frozen
    public enum Name: Sendable, Hashable, CaseIterable {
        case main
        case layer1
        case layer2
        case layer3
        case background

        public init?(key: String) {
            switch key {
            case "MAINLAYER": self = .main
            case "LAYER1": self = .layer1
            case "LAYER2": self = .layer2
            case "LAYER3": self = .layer3
            case "BGLAYER": self = .background
            default: return nil
            }
        }

        public var key: String {
            switch self {
            case .main: "MAINLAYER"
            case .layer1: "LAYER1"
            case .layer2: "LAYER2"
            case .layer3: "LAYER3"
            case .background: "BGLAYER"
            }
        }

        /// The number the layer table and the stroke records use: `-1` the
        /// background, `0` the main layer, `1`–`3` the others.
        public var layerID: Int {
            switch self {
            case .background: -1
            case .main: 0
            case .layer1: 1
            case .layer2: 2
            case .layer3: 3
            }
        }
    }
}

/// One row of a page's layer table (`LAYERINFO`): what the user did to a
/// layer in the tablet's layer panel.
public struct SNLayerInfo: Sendable, Hashable {
    /// `-1` the background, `0` the main layer, `1`–`3` the others.
    public let layerID: Int
    /// The name the panel shows.
    public let name: String
    public let isBackground: Bool
    public let isVisible: Bool
    public let isDeleted: Bool
    /// The layer the pen was on when the page was last edited.
    public let isCurrent: Bool

    public init(layerID: Int, name: String, isBackground: Bool, isVisible: Bool, isDeleted: Bool, isCurrent: Bool) {
        self.layerID = layerID
        self.name = name
        self.isBackground = isBackground
        self.isVisible = isVisible
        self.isDeleted = isDeleted
        self.isCurrent = isCurrent
    }
}
