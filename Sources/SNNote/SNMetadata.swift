// Copyright 2026 ALTESSA SOLUTIONS INC.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import Foundation

/// One of the format's tag blocks, as written: `<KEY:VALUE><KEY:VALUE>…`.
///
/// Every structural part of a `.note` is one of these — the header, the
/// footer, a page, a layer, a title, a keyword, a link — and the values that
/// matter are numbers, names or the addresses of further blocks. The typed
/// properties on `SNNotebook`, `SNPage` and the rest read the keys this
/// package understands; this keeps the rest, in order, because a firmware
/// adds keys faster than anyone documents them, and a key nobody has named yet
/// is still worth being able to look at.
///
/// A key may occur more than once. The footer is written append-only, and a
/// heading re-saved in place leaves its `TITLE_…` key twice — keeping only
/// one of them silently drops a title, which is what a dictionary would do.
public struct SNMetadata: Sendable, Hashable {
    /// The pairs in file order, repeats included.
    public let entries: [Entry]

    public struct Entry: Sendable, Hashable {
        public let key: String
        public let value: String

        public init(key: String, value: String) {
            self.key = key
            self.value = value
        }
    }

    public init(entries: [Entry]) {
        self.entries = entries
    }

    /// The first value under `key`.
    public subscript(key: String) -> String? {
        entries.first { $0.key == key }?.value
    }

    /// Every value under `key`, in file order.
    public func values(for key: String) -> [String] {
        entries.filter { $0.key == key }.map(\.value)
    }

    /// Reads `<KEY:VALUE>` pairs out of a block.
    ///
    /// A key runs to the first `:`; the value runs to the `>` that closes the
    /// tag, colons included. Bytes between tags are ignored. A block that was
    /// cut off in the middle of a tag keeps everything before it.
    public init(parsing bytes: Data) {
        var entries: [Entry] = []
        let raw = [UInt8](bytes)
        var index = 0
        while index < raw.count {
            guard raw[index] == UInt8(ascii: "<") else {
                index += 1
                continue
            }
            var colon = index + 1
            while colon < raw.count, raw[colon] != UInt8(ascii: ":"), raw[colon] != UInt8(ascii: "<"),
                  raw[colon] != UInt8(ascii: ">") {
                colon += 1
            }
            guard colon < raw.count, raw[colon] == UInt8(ascii: ":") else {
                index = colon
                continue
            }
            var close = colon + 1
            while close < raw.count, raw[close] != UInt8(ascii: ">"), raw[close] != UInt8(ascii: "<") {
                close += 1
            }
            guard close < raw.count, raw[close] == UInt8(ascii: ">") else {
                index = close
                continue
            }
            let key = String(decoding: raw[(index + 1)..<colon], as: UTF8.self)
            let value = String(decoding: raw[(colon + 1)..<close], as: UTF8.self)
            if !key.isEmpty {
                entries.append(Entry(key: key, value: value))
            }
            index = close + 1
        }
        self.entries = entries
    }
}

extension String {
    /// `none` and `0` are how the format spells "not set" in a text field.
    var unlessUnset: String? {
        self == "none" || self == "0" || isEmpty ? nil : self
    }
}
