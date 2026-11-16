import Foundation

/// Reads metadata from a JSON sidecar file adjacent to the video file.
///
/// Expected format:
/// ```json
/// { "artist": "...", "track": "...", "album": "...", "year": 1998 }
/// ```
/// All fields are optional — only present keys are used.
enum SidecarMetadata {

    private struct Sidecar: Decodable {
        var artist: String?
        var track:  String?
        var album:  String?
        var year:   Int?
    }

    /// - Parameter videoURL: The URL of the video file being played.
    /// - Returns: `TrackMetadata` from the sidecar, or `nil` if no sidecar exists.
    static func resolve(for videoURL: URL) -> TrackMetadata? {
        let sidecarURL = videoURL.deletingPathExtension().appendingPathExtension("json")
        guard FileManager.default.fileExists(atPath: sidecarURL.path),
              let data = try? Data(contentsOf: sidecarURL),
              let sidecar = try? JSONDecoder().decode(Sidecar.self, from: data)
        else { return nil }

        var meta = TrackMetadata(source: .sidecar)
        meta.artist = sidecar.artist?.nilIfEmpty
        meta.track  = sidecar.track?.nilIfEmpty
        meta.album  = sidecar.album?.nilIfEmpty
        meta.year   = sidecar.year
        return meta
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
