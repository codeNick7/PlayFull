import Foundation

/// Robust parser for video filenames and raw embedded media titles.
/// Converts scene release strings, torrent titles, and music video names into clean Artist / Track / Year.
enum MediaNameParser {

    struct Result {
        var artist: String?
        var title: String?
        var year: Int?
    }

    /// Parses any raw title or filename string.
    static func parse(_ raw: String) -> Result {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return Result() }

        // 1. Remove file extensions (.mp4, .mkv, .avi, etc.)
        let extensions = [".mp4", ".mkv", ".avi", ".mov", ".webm", ".m4v", ".flv", ".wmv", ".ts"]
        for ext in extensions {
            if s.lowercased().hasSuffix(ext) {
                s = String(s.dropLast(ext.count))
            }
        }

        // 2. Remove URLs anywhere in the string
        if let urlRegex = try? NSRegularExpression(pattern: #"(?:\s*-\s*)?(?:https?://|www\.)\S+"#, options: .caseInsensitive) {
            s = urlRegex.stringByReplacingMatches(in: s, options: [], range: NSRange(location: 0, length: s.utf16.count), withTemplate: "")
        }

        // 3. Normalise delimiters (e.g. "_-_", "_-", "-_" -> " - ")
        s = s.replacingOccurrences(of: "_-_", with: " - ")
        s = s.replacingOccurrences(of: "_-", with: " - ")
        s = s.replacingOccurrences(of: "-_", with: " - ")

        // Check if there is an explicit " - " separating Artist and Title (Music Video style)
        if s.contains(" - ") {
            let parts = s.components(separatedBy: " - ")
                .map { cleanFragment($0) }
                .filter { !$0.isEmpty }

            if parts.count == 2 {
                let parsedTitle = cleanSceneTags(parts[1])
                return Result(
                    artist: cleanFragment(parts[0]),
                    title: parsedTitle.title,
                    year: parsedTitle.year
                )
            } else if parts.count >= 3 {
                let parsedTitle = cleanSceneTags(parts.last!)
                return Result(
                    artist: cleanFragment(parts[0]),
                    title: parsedTitle.title,
                    year: parsedTitle.year
                )
            }
        }

        // Scene / Movie style parsing (e.g. "CODA.2021.720p.BluRay.x264.AAC-[YTS.MX]")
        let sceneResult = cleanSceneTags(s)
        return Result(
            artist: nil,
            title: sceneResult.title,
            year: sceneResult.year
        )
    }

    // MARK: - Scene Tag Cleaner

    private static func cleanSceneTags(_ raw: String) -> (title: String, year: Int?) {
        // Strip trailing release group brackets like -[YTS.MX], [RARBG], -TEPES, etc.
        var s = raw
        if let groupRegex = try? NSRegularExpression(pattern: #"\s*-?\s*\[[^\]]+\]$"#) {
            s = groupRegex.stringByReplacingMatches(in: s, options: [], range: NSRange(location: 0, length: s.utf16.count), withTemplate: "")
        }

        // Replace dots and underscores with spaces
        s = s.replacingOccurrences(of: ".", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "\"", with: "")

        // Noise words / codec tags to cut at (case-insensitive words)
        let cutKeywords = [
            "720p", "1080p", "2160p", "4k", "uhd", "bluray", "blu-ray", "bdrip", "brrip",
            "web-dl", "webrip", "webdl", "dvdrip", "hdtv", "hdrip",
            "x264", "x265", "h264", "h265", "hevc", "avc", "10bit",
            "aac", "ac3", "ddp5 1", "ddp5.1", "dd5 1", "dd5.1", "dts", "atmos",
            "amzn", "repack", "remastered", "unrated", "directors cut", "director's cut"
        ]

        // Find year (1900..2099)
        var parsedYear: Int?
        var cutIndex = s.count

        if let yearRegex = try? NSRegularExpression(pattern: #"\b(19\d\d|20\d\d)\b"#) {
            let nsString = s as NSString
            let matches = yearRegex.matches(in: s, range: NSRange(location: 0, length: nsString.length))
            // Pick the last match before video tags, or the primary release year
            if let match = matches.last {
                // If the year is not at the very beginning (e.g. not movie "2010"), use it as release year
                if match.range.location > 0 {
                    let yearStr = nsString.substring(with: match.range)
                    parsedYear = Int(yearStr)
                    cutIndex = min(cutIndex, match.range.location)
                }
            }
        }

        // Also check if any cut keywords appear before the year
        let lower = s.lowercased()
        for kw in cutKeywords {
            if let range = lower.range(of: "\\b\(kw)\\b", options: .regularExpression) {
                let idx = s.distance(from: s.startIndex, to: range.lowerBound)
                if idx > 0 {
                    cutIndex = min(cutIndex, idx)
                }
            }
        }

        let cleanTitle = String(s.prefix(cutIndex)).trimmingCharacters(in: .whitespacesAndNewlines)
        return (title: cleanFragment(cleanTitle.isEmpty ? s : cleanTitle), year: parsedYear)
    }

    private static func cleanFragment(_ raw: String) -> String {
        var s = raw.replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "\"", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let noiseSuffixes = [
            " - Official Video",          " - Official Music Video",
            " (Official Video)",          " (Official Music Video)",
            " [Official Video]",          " [Official Music Video]",
            " - Official Audio",          " (Official Audio)",           " [Official Audio]",
            " - Official Visualizer",     " (Official Visualizer)",      " [Official Visualizer]",
            " - Director's Cut",          " (Director's Cut)",           " [Director's Cut]",
            " - Lyrics",                  " (Lyrics)",                   " [Lyrics]",
            " - Lyric Video",             " (Lyric Video)",              " [Lyric Video]",
            " - HD",                      " (HD)",                       " [HD]",
            " - 4K",                      " (4K)",                       " [4K]",
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

        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
