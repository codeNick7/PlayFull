import Foundation

/// Parses metadata from a video filename using MediaNameParser.
enum FilenameMetadata {

    static func resolve(for url: URL) -> TrackMetadata? {
        let filename = url.lastPathComponent
        let parsed = MediaNameParser.parse(filename)

        guard parsed.title != nil || parsed.artist != nil else { return nil }

        var meta = TrackMetadata(source: .filename)
        meta.artist = parsed.artist
        meta.track  = parsed.title
        meta.year   = parsed.year
        return meta
    }
}
