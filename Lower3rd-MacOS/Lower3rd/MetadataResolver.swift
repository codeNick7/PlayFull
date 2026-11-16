import Foundation

/// Coordinates all three metadata sources with priority:
/// **embedded tags → sidecar JSON → filename convention**
///
/// Fields are cleaned and normalized via MediaNameParser.
enum MetadataResolver {

    /// Resolve metadata for a given file URL + its already-parsed libvlc media.
    static func resolve(url: URL, media: OpaquePointer) -> TrackMetadata {
        var embedded  = EmbeddedMetadata.resolve(from: media)
        let sidecar   = SidecarMetadata.resolve(for: url)
        let fromFile  = FilenameMetadata.resolve(for: url)

        // Clean and parse embedded track / title if present
        if let rawTrack = embedded.track {
            let parsed = MediaNameParser.parse(rawTrack)
            if let parsedArtist = parsed.artist, embedded.artist == nil {
                embedded.artist = parsedArtist
            }
            embedded.track = parsed.title ?? embedded.track
            if embedded.year == nil, let parsedYear = parsed.year {
                embedded.year = parsedYear
            }
        }

        // Clean embedded artist if present
        if let rawArtist = embedded.artist {
            embedded.artist = TrackMetadata.clean(rawArtist)
        }

        // Build merged result by taking the first non-nil value per field.
        var result = TrackMetadata()
        result.artist = embedded.artist ?? sidecar?.artist ?? fromFile?.artist
        result.track  = embedded.track  ?? sidecar?.track  ?? fromFile?.track
        result.album  = embedded.album  ?? sidecar?.album  ?? fromFile?.album
        result.year   = embedded.year   ?? sidecar?.year   ?? fromFile?.year

        // Final pass: if track still looks like a raw scene string, parse it
        if let currentTrack = result.track {
            let parsed = MediaNameParser.parse(currentTrack)
            if result.artist == nil, let parsedArtist = parsed.artist {
                result.artist = parsedArtist
            }
            if let cleanTitle = parsed.title, !cleanTitle.isEmpty {
                result.track = cleanTitle
            }
            if result.year == nil, let parsedYear = parsed.year {
                result.year = parsedYear
            }
        }

        // Record dominant source
        result.source = dominantSource(embedded: embedded, sidecar: sidecar, filename: fromFile)

        return result
    }

    // MARK: Private

    private static func dominantSource(
        embedded: TrackMetadata,
        sidecar:  TrackMetadata?,
        filename: TrackMetadata?
    ) -> MetadataSource {
        if embedded.hasAnyField  { return .embedded }
        if sidecar?.hasAnyField  == true { return .sidecar  }
        if filename?.hasAnyField == true { return .filename }
        return .none
    }
}
