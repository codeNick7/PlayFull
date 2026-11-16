import Foundation

// MARK: - Metadata Source

enum MetadataSource: String {
    case embedded  // libvlc container tags
    case sidecar   // <filename>.json next to the file
    case filename  // parsed from the filename itself
    case none      // no metadata found
}

// MARK: - Track Metadata

struct TrackMetadata: Equatable {
    var artist: String?
    var track:  String?
    var album:  String?
    var year:   Int?
    var source: MetadataSource = .none

    /// True if at least one displayable field was resolved.
    var hasAnyField: Bool {
        artist != nil || track != nil || album != nil
    }

    /// Single-line fallback: "ARTIST — TRACK"
    var marqueeString: String? {
        switch (artist, track) {
        case let (a?, t?): return "\(a) — \(t)"
        case let (nil, t?): return t
        case let (a?, nil): return a
        default:           return nil
        }
    }

    /// 90s-style broadcast lower third lines:
    /// - Line 1 (Large/Bold): Artist
    /// - Line 2 (Medium): Track Title
    /// - Line 3 (Smaller/Muted): Album (Year)
    var lowerThirdLines: (artist: String?, track: String?, detail: String?) {
        let cleanArtist = artist.flatMap(Self.clean)
        let cleanTrack  = track.flatMap(Self.clean)
        let cleanAlbum  = album.flatMap(Self.clean)

        var detailParts: [String] = []
        if let alb = cleanAlbum {
            detailParts.append(alb)
        }
        if let y = year {
            detailParts.append(String(y))
        }
        let detailString = detailParts.isEmpty ? nil : detailParts.joined(separator: " • ")

        return (artist: cleanArtist, track: cleanTrack, detail: detailString)
    }

    // MARK: - Helper Methods

    /// Sanitises a metadata field:
    /// - Replaces underscores with spaces (e.g. Robin_Schulz -> Robin Schulz)
    /// - Strips quotes (e.g. "Sugar" -> Sugar)
    /// - Strips embedded URLs (http/https/www) anywhere in the string
    /// - Strips common YouTube / Rip noise suffixes (Director's Cut, Official Video, etc.)
    /// - Truncates excessively long lines
    static func clean(_ raw: String) -> String? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }

        // Remove any URL occurrences anywhere in the string (e.g. " - https://...")
        if let urlRegex = try? NSRegularExpression(pattern: #"(?:\s*-\s*)?(?:https?://|www\.)\S+"#, options: .caseInsensitive) {
            s = urlRegex.stringByReplacingMatches(in: s, options: [], range: NSRange(location: 0, length: s.utf16.count), withTemplate: "")
            s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Replace underscores with spaces (e.g. Robin_Schulz -> Robin Schulz)
        s = s.replacingOccurrences(of: "_", with: " ")

        // Strip surrounding quotes
        s = s.replacingOccurrences(of: "\"", with: "")

        // Strip noise suffixes iteratively
        let noiseSuffixes = [
            " - Official Video",          " - Official Music Video",
            " (Official Video)",          " (Official Music Video)",
            " [Official Video]",          " [Official Music Video]",
            " - Official Audio",          " (Official Audio)",           " [Official Audio]",
            " - Official Visualizer",     " (Official Visualizer)",      " [Official Visualizer]",
            " - Director's Cut",          " (Director's Cut)",           " [Director's Cut]",
            " - Directors Cut",           " (Directors Cut)",            " [Directors Cut]",
            " - Lyrics",                  " (Lyrics)",                   " [Lyrics]",
            " - Lyric Video",             " (Lyric Video)",              " [Lyric Video]",
            " - HD",                      " (HD)",                       " [HD]",
            " - HQ",                      " (HQ)",                       " [HQ]",
            " - 4K",                      " (4K)",                       " [4K]",
            " - 1080p",                   " (1080p)",                    " [1080p]",
            " - 720p",                    " (720p)",                     " [720p]",
            " (Video)",                   " [Video]",                    " - Video",
            " (Audio)",                   " [Audio]",                    " - Audio",
            " -"
        ]

        var changed = true
        while changed {
            changed = false
            for suffix in noiseSuffixes {
                if s.lowercased().hasSuffix(suffix.lowercased()) {
                    s = String(s.dropLast(suffix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                    changed = true
                }
            }
        }

        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        return s.count > 45 ? String(s.prefix(42)) + "…" : s
    }

    static var empty: TrackMetadata {
        TrackMetadata(source: .none)
    }
}
