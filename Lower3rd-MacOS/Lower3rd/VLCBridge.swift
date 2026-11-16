import Foundation
import AppKit

/// Model representing an audio or subtitle track
struct MediaTrackItem: Identifiable, Equatable {
    let id: Int32
    let name: String
}

/// Thin Swift wrapper around the libvlc C API.
/// Owns the libvlc instance and media player for their full lifetime.
class VLCBridge: NSObject {

    private var instance: OpaquePointer?
    private var player: OpaquePointer?
    private var equalizer: OpaquePointer?

    /// Most recently resolved metadata for the current file.
    private(set) var currentMetadata: TrackMetadata = .empty

    override init() {
        super.init()

        // Point libvlc at VLC.app's codec plugins.
        let vlcApp = "/Applications/VLC.app/Contents/MacOS"
        setenv("VLC_PLUGIN_PATH", "\(vlcApp)/plugins", 1)
        setenv("VLC_DATA_PATH",   "\(vlcApp)/share",   1)

        // Disable libvlc's default low-res title OSD
        let args: [String] = [
            "--no-video-title-show",
            "--no-osd"
        ]
        let cArgs = args.map { strdup($0) }
        instance = libvlc_new(Int32(cArgs.count), cArgs.map { UnsafePointer($0) })
        cArgs.forEach { free($0) }
        player = libvlc_media_player_new(instance)
    }

    deinit {
        if let equalizer {
            libvlc_audio_equalizer_release(equalizer)
        }
        libvlc_media_player_stop(player)
        libvlc_media_player_release(player)
        libvlc_release(instance)
    }

    // MARK: - Video Surface

    /// Tells libvlc to render video into the given NSView.
    func setDrawable(_ view: NSView) {
        guard let player else { return }
        libvlc_media_player_set_nsobject(player, Unmanaged.passUnretained(view).toOpaque())
    }

    // MARK: - Playback Controls

    /// Opens a local file URL and starts playback immediately.
    /// Returns the resolved TrackMetadata.
    @discardableResult
    func play(url: URL, muted: Bool = false) -> TrackMetadata {
        guard let instance, let player else { return .empty }
        guard let media = libvlc_media_new_path(instance, url.path) else { return .empty }

        // Resolve metadata before releasing the media pointer.
        currentMetadata = MetadataResolver.resolve(url: url, media: media)
        print("[Lower3rd] Resolved Metadata: \(currentMetadata)")

        libvlc_media_player_set_media(player, media)
        libvlc_media_release(media)

        if muted {
            libvlc_audio_set_mute(player, 1)
        } else {
            libvlc_audio_set_mute(player, 0)
        }

        libvlc_media_player_play(player)

        // Re-apply active equalizer if present
        if let equalizer {
            libvlc_media_player_set_equalizer(player, equalizer)
        }

        return currentMetadata
    }

    func resume() {
        guard let player else { return }
        libvlc_media_player_play(player)
    }

    func pause() {
        guard let player else { return }
        libvlc_media_player_pause(player)
    }

    func stop() {
        guard let player else { return }
        libvlc_media_player_stop(player)
    }

    func togglePlayPause() {
        guard let player else { return }
        let state = libvlc_media_player_get_state(player)
        if state == libvlc_Playing {
            libvlc_media_player_pause(player)
        } else {
            libvlc_media_player_play(player)
        }
    }

    // MARK: - Volume Controls

    var volume: Int {
        guard let player else { return 50 }
        let vol = libvlc_audio_get_volume(player)
        return vol >= 0 ? Int(vol) : 50
    }

    func setVolume(_ vol: Int) {
        guard let player else { return }
        libvlc_audio_set_volume(player, Int32(max(0, min(100, vol))))
    }

    var isMuted: Bool {
        guard let player else { return false }
        return libvlc_audio_get_mute(player) != 0
    }

    func toggleMute() {
        guard let player else { return }
        libvlc_audio_toggle_mute(player)
    }

    func setMuted(_ muted: Bool) {
        guard let player else { return }
        libvlc_audio_set_mute(player, muted ? 1 : 0)
    }

    // MARK: - Playback State & Metrics

    var isPlaying: Bool {
        guard let player else { return false }
        let state = libvlc_media_player_get_state(player)
        return state == libvlc_Playing || state == libvlc_Opening || state == libvlc_Buffering
    }

    var isEnded: Bool {
        guard let player else { return false }
        return libvlc_media_player_get_state(player) == libvlc_Ended
    }

    /// Current playback time in seconds.
    var currentTime: Double {
        guard let player else { return 0 }
        let ms = libvlc_media_player_get_time(player)
        return ms > 0 ? Double(ms) / 1000.0 : 0
    }

    /// Total media duration in seconds.
    var duration: Double {
        guard let player else { return 0 }
        let ms = libvlc_media_player_get_length(player)
        return ms > 0 ? Double(ms) / 1000.0 : 0
    }

    /// Position from 0.0 to 1.0.
    var position: Double {
        guard let player else { return 0 }
        let pos = libvlc_media_player_get_position(player)
        return pos >= 0 ? Double(pos) : 0
    }

    /// Seek to a relative position between 0.0 and 1.0.
    func seek(to position: Double) {
        guard let player else { return }
        libvlc_media_player_set_position(player, Float(max(0.0, min(1.0, position))))
    }

    /// Seek by adding or subtracting seconds.
    func seekBy(seconds: Double) {
        guard let player else { return }
        let target = max(0, currentTime + seconds)
        libvlc_media_player_set_time(player, libvlc_time_t(target * 1000.0))
    }

    // MARK: - Audio Tracks (Channels / Languages)

    /// Returns list of all available audio tracks in the playing media
    func getAudioTracks() -> [MediaTrackItem] {
        guard let player else { return [] }
        guard let descHead = libvlc_audio_get_track_description(player) else { return [] }
        defer { libvlc_track_description_list_release(descHead) }

        var items: [MediaTrackItem] = []
        var current: UnsafeMutablePointer<libvlc_track_description_t>? = descHead
        while let node = current {
            let id = node.pointee.i_id
            if id >= 0 {
                let nameStr: String
                if let pszName = node.pointee.psz_name {
                    nameStr = String(cString: pszName)
                } else {
                    nameStr = "Audio Track \(id)"
                }
                items.append(MediaTrackItem(id: id, name: nameStr))
            }
            current = node.pointee.p_next
        }
        return items
    }

    /// Current active audio track ID
    var currentAudioTrack: Int32 {
        guard let player else { return -1 }
        return libvlc_audio_get_track(player)
    }

    /// Switches active audio track
    func setAudioTrack(_ trackId: Int32) {
        guard let player else { return }
        libvlc_audio_set_track(player, trackId)
    }

    // MARK: - Subtitles

    /// Loads an external subtitle file (.srt, .vtt, .ass, etc.)
    @discardableResult
    func addSubtitle(url: URL) -> Bool {
        guard let player else { return false }
        
        let path = url.path
        let fileResult = libvlc_video_set_subtitle_file(player, path)
        if fileResult != 0 {
            return true
        }

        let uri = url.isFileURL ? url.absoluteString : path
        let slaveResult = libvlc_media_player_add_slave(player, libvlc_media_slave_type_subtitle, uri, true)
        return slaveResult == 0
    }

    /// Returns list of all available subtitle tracks in the playing media
    func getSubtitleTracks() -> [MediaTrackItem] {
        guard let player else { return [] }
        guard let descHead = libvlc_video_get_spu_description(player) else { return [] }
        defer { libvlc_track_description_list_release(descHead) }

        var items: [MediaTrackItem] = []
        var current: UnsafeMutablePointer<libvlc_track_description_t>? = descHead
        while let node = current {
            let id = node.pointee.i_id
            if id >= 0 {
                let nameStr: String
                if let pszName = node.pointee.psz_name {
                    nameStr = String(cString: pszName)
                } else {
                    nameStr = "Subtitle Track \(id)"
                }
                items.append(MediaTrackItem(id: id, name: nameStr))
            }
            current = node.pointee.p_next
        }
        return items
    }

    /// Current subtitle track ID (-1 = disabled)
    var currentSubtitleTrack: Int32 {
        guard let player else { return -1 }
        return libvlc_video_get_spu(player)
    }

    /// Sets the subtitle track ID (-1 to disable)
    func setSubtitleTrack(_ trackId: Int32) {
        guard let player else { return }
        libvlc_video_set_spu(player, trackId)
    }

    /// Total count of available subtitle tracks
    var subtitleTrackCount: Int32 {
        guard let player else { return 0 }
        return libvlc_video_get_spu_count(player)
    }

    // MARK: - Audio Equalizer & Enhancements

    /// Applies or disables the 10-band audio equalizer on the media player.
    func setEqualizer(enabled: Bool, preamp: Float = 0.0, bands: [Float] = []) {
        guard let player else { return }

        if !enabled {
            libvlc_media_player_set_equalizer(player, nil)
            return
        }

        if equalizer == nil {
            equalizer = libvlc_audio_equalizer_new()
        }

        guard let equalizer else { return }

        // Set Preamp gain (-20.0 to +20.0 dB)
        libvlc_audio_equalizer_set_preamp(equalizer, max(-20.0, min(20.0, preamp)))

        // Set each frequency band
        for (i, amp) in bands.enumerated() {
            guard i < 10 else { break }
            libvlc_audio_equalizer_set_amp_at_index(equalizer, max(-20.0, min(20.0, amp)), UInt32(i))
        }

        libvlc_media_player_set_equalizer(player, equalizer)
    }
}
