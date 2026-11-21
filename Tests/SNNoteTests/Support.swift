// Copyright 2026 ALTESSA SOLUTIONS INC.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import Foundation
import SNNote
import Testing

/// The third-party corpus (Apache-2.0, see the LICENSE beside it): `.note`
/// files written on an A5X, an A6X, a Nomad and a Manta, format versions 11
/// to 16.
enum Corpus {
    static func directory() throws -> URL {
        try #require(Bundle.module.resourceURL).appendingPathComponent("Fixtures/supernote-typescript")
    }

    static func url(_ name: String) throws -> URL {
        try directory().appendingPathComponent(name)
    }

    static func notebook(_ name: String) throws -> SNNotebook {
        try SNParser.parse(Data(contentsOf: url(name)))
    }

    /// Every file of the corpus, sorted by name.
    static func files() throws -> [URL] {
        try FileManager.default
            .contentsOfDirectory(at: directory(), includingPropertiesForKeys: nil)
            .filter { ["note", "mark"].contains($0.pathExtension) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}

/// This package's own samples (`Fixtures/samples`): notebooks made to hold
/// one feature each, where the third-party corpus has none.
enum Samples {
    static func url(_ name: String) throws -> URL {
        try #require(Bundle.module.resourceURL).appendingPathComponent("Fixtures/samples/\(name)")
    }

    static func notebook(_ name: String) throws -> SNNotebook {
        try SNParser.parse(Data(contentsOf: url(name)))
    }

    static func files() throws -> [URL] {
        let directory = try #require(Bundle.module.resourceURL).appendingPathComponent("Fixtures/samples")
        return try FileManager.default
            .contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { ["note", "mark"].contains($0.pathExtension) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}

/// Notebooks from a real device, outside the repository: whatever
/// directories `SNNOTE_CORPUS` names, colon-separated. Private handwriting
/// stays where its owner keeps it; the tests that read it are skipped when the
/// variable is not set.
enum DeviceCorpus {
    static var directories: [URL] {
        guard let value = ProcessInfo.processInfo.environment["SNNOTE_CORPUS"], !value.isEmpty else { return [] }
        return value.split(separator: ":").map { URL(fileURLWithPath: String($0), isDirectory: true) }
    }

    static var isAvailable: Bool { !directories.isEmpty }

    static func files() -> [URL] {
        directories.flatMap { directory -> [URL] in
            let walker = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil)
            return (walker?.allObjects as? [URL] ?? []).filter { $0.pathExtension == "note" }
        }
        .sorted { $0.path < $1.path }
    }
}
