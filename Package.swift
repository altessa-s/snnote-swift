// swift-tools-version: 6.3
// Copyright 2026 ALTESSA SOLUTIONS INC.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

// The Supernote notebook format, read: the `.note` container, its pages and
// layers, the RATTA_RLE bitmaps the tablet draws, the vector strokes behind
// them, and what the tablet recognised in the handwriting. Reading only —
// nothing here draws a stroke, and nothing here has heard of the cloud. That
// is what keeps it testable against a corpus of files: this package depends on
// nothing but the platform, and says what it could not read through
// `SNNoteLog`, whose sink the host installs.
import PackageDescription

let package = Package(
    name: "SNNote",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "SNNote", targets: ["SNNote"]),
    ],
    targets: [
        .target(name: "CSNNote", exclude: ["LICENSE", "COPYRIGHT", "VERSION", "COMMIT"]),
        .target(
            name: "SNNote",
            dependencies: ["CSNNote"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "SNNoteTests",
            dependencies: ["SNNote"],
            // Copied rather than processed: these are `.note` files, the bytes
            // matter, and a resource processor has no business touching them.
            resources: [.copy("Fixtures")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ],
    cLanguageStandard: .c2x
)
