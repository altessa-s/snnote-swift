// Copyright 2026 ALTESSA SOLUTIONS INC.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import Foundation

/// The errors of reading a notebook.
///
/// What is thrown here is a file that would not read, and nothing else: not a
/// rendering error, not a network one. Most of what can go wrong inside a
/// notebook does not reach the caller at all — a stroke record that will not
/// walk is counted on its page and stepped over — so what does arrive here is
/// a file that cannot be opened as a notebook in the first place.
///
/// Frozen: an exhaustive `switch` over these cases in a consumer is the point.
/// A new case must break its build, not fall into an `@unknown default`.
@frozen
public enum SNParseError: Error, Sendable, Equatable {
    /// The bytes do not begin the way a Supernote file does. The first of them
    /// travel along, because a signature nobody recognises is the one thing
    /// worth looking at.
    case unsupportedFormat(String)
    /// A field or a block runs past the end of the file.
    case unexpectedEndOfData
    /// The bytes are a Supernote file, but something load-bearing in them is
    /// not what the format allows: a footer that is not one, an address
    /// pointing outside the file, a count larger than the bytes behind it.
    case malformed(String)
}

// Equality spelled out rather than synthesised.
//
// `@frozen` lets a consumer compare two values through the witness the
// compiler derives — and that witness is internal, so it is absent from this
// module's symbol table when SNNote is linked as a binary framework. The
// reference resolves in a release build, where the comparison is inlined, and
// fails to link in a debug one. An explicit `==` puts it behind an exported
// symbol.
extension SNParseError {
    public static func == (a: SNParseError, b: SNParseError) -> Bool {
        switch (a, b) {
        case let (.unsupportedFormat(x), .unsupportedFormat(y)): x == y
        case (.unexpectedEndOfData, .unexpectedEndOfData): true
        case let (.malformed(x), .malformed(y)): x == y
        default: false
        }
    }
}
