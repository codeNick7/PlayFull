import Foundation

/// Extracts metadata from embedded container tags via the libvlc C API.
/// Calls libvlc_media_parse_with_options() and waits for parsing to finish
/// before reading tags.
enum EmbeddedMetadata {

    /// Parses and returns metadata from a libvlc media pointer.
    /// - Parameter media: An `OpaquePointer` to a `libvlc_media_t`.
    /// - Returns: A `TrackMetadata` populated with whatever tags are present.
    static func resolve(from media: OpaquePointer) -> TrackMetadata {
        // Request local file parsing (non-network, no artwork fetch).
        libvlc_media_parse_with_options(media, libvlc_media_parse_local, 2000)

        // Spin-wait until parsed or timeout (max ~3 s).
        var ticks = 30
        while libvlc_media_get_parsed_status(media) != libvlc_media_parsed_status_done, ticks > 0 {
            Thread.sleep(forTimeInterval: 0.1)
            ticks -= 1
        }

        var meta = TrackMetadata(source: .embedded)
        meta.artist = string(from: media, type: libvlc_meta_Artist)
        meta.track  = string(from: media, type: libvlc_meta_Title)
        meta.album  = string(from: media, type: libvlc_meta_Album)
        if let dateStr = string(from: media, type: libvlc_meta_Date) {
            meta.year = Int(dateStr.prefix(4))
        }
        return meta
    }

    // MARK: Private

    private static func string(from media: OpaquePointer, type: libvlc_meta_t) -> String? {
        guard let raw = libvlc_media_get_meta(media, type) else { return nil }
        let value = String(cString: raw)
        free(raw)                       // libvlc allocates; caller must free
        return value.isEmpty ? nil : value
    }
}
