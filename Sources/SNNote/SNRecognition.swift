// Copyright 2026 ALTESSA SOLUTIONS INC.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import CoreGraphics
import Foundation

/// What the tablet recognised in a page's handwriting (`RECOGNTEXT`).
///
/// Stored as base64 of a JSON document the recognition engine produced: a list
/// of elements, each a block of recognised text and its words. Only pages
/// recognised on the device carry it — real-time recognition notebooks, or a
/// page converted by hand — and a page that was recognised and found nothing
/// carries an empty list, which is a different answer from no recognition at
/// all (`SNPage.recognition == nil`).
public struct SNRecognition: Sendable, Hashable {
    public let elements: [Element]

    public init(elements: [Element]) {
        self.elements = elements
    }

    /// The text of every text element, one element per line group, in the
    /// engine's order.
    public var text: String {
        elements.filter { $0.kind == "Text" }.compactMap(\.label).joined(separator: "\n")
    }

    /// One block the engine recognised.
    public struct Element: Sendable, Hashable {
        /// The engine's type name: `Text` for handwriting it read, `Raw
        /// Content` for ink it did not classify, and others for diagrams.
        public let kind: String
        /// The recognised text, line breaks included. `nil` for an element
        /// that is not text.
        public let label: String?
        public let words: [Word]

        public init(kind: String, label: String?, words: [Word]) {
            self.kind = kind
            self.label = label
            self.words = words
        }
    }

    /// One word, or one separator: the engine writes the spaces and line
    /// breaks between words as words of their own, without a box.
    public struct Word: Sendable, Hashable {
        public let label: String
        /// Where the word sits on the page, in millimetres from its top-left
        /// corner — the engine's unit, not the page's pixels. `nil` on a
        /// separator.
        public let box: CGRect?

        public init(label: String, box: CGRect?) {
            self.label = label
            self.box = box
        }
    }
}
