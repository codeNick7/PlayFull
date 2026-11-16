import SwiftUI
import AppKit
import Observation
import UniformTypeIdentifiers

// MARK: - App Delegate & Notification

extension Notification.Name {
    static let lower3rdOpenFileNotification = Notification.Name("lower3rdOpenFileNotification")
}

class AppDelegate: NSObject, NSApplicationDelegate {
    static var initialOpenedURLs: [URL] = []

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        let urls = filenames.map { URL(fileURLWithPath: $0) }
        guard !urls.isEmpty else { return }
        Self.initialOpenedURLs = urls
        Task { @MainActor in
            NotificationCenter.default.post(name: .lower3rdOpenFileNotification, object: urls)
        }
    }
}

// MARK: - App Entry

@main
struct Lower3rdApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 960, height: 600)
    }
}

// MARK: - Player State

@MainActor
@Observable
class PlayerState {
    let bridge = VLCBridge()
    var isPlaying = false
    var hasMedia  = false
    var isIntro   = false
    var currentMetadata: TrackMetadata = .empty
    var showOverlay = false

    // Playlist
    var playlist: [URL] = []
    var currentIndex: Int = 0

    // Time & Seek
    var currentTime: Double = 0
    var duration: Double = 0
    var progress: Double = 0
    var isDraggingSlider = false

    // Volume (Default to 75%)
    var volume: Double = 75
    var isMuted: Bool = false

    // Multi-track Audio & Subtitles
    var audioTracks: [MediaTrackItem] = []
    var currentAudioTrackId: Int32 = -1
    var subtitleTracks: [MediaTrackItem] = []
    var currentSubtitleTrackId: Int32 = -1

    var loadedSubtitleName: String? = nil
    var subtitleNotificationText: String? = nil
    var showSubtitleNotification: Bool = false

    // Audio Equalizer & Enhancements
    var isEQEnabled: Bool = false
    var eqPreamp: Float = 0.0
    var eqBands: [Float] = Array(repeating: 0.0, count: 10)
    var selectedEQPresetName: String? = nil

    private var subtitleNotificationTask: Task<Void, Never>?
    private var overlayTask: Task<Void, Never>?
    private var timer: Timer?

    static let supportedExtensions: Set<String> = [
        "mp4", "mkv", "mov", "avi", "webm", "m4v", "flv", "wmv", "ts", "mpg", "mpeg", "3gp",
        "mp3", "m4a", "wav", "flac", "ogg", "aac", "aiff", "wma"
    ]

    static let supportedSubtitleExtensions: Set<String> = [
        "srt", "vtt", "ass", "ssa", "sub", "smi", "idx"
    ]

    /// Dynamic Window Title based on playing media and metadata
    var windowTitle: String {
        guard hasMedia && !isIntro else { return "Lower3rd" }

        let meta = currentMetadata
        let cleanArtist = meta.artist.flatMap(TrackMetadata.clean)
        let cleanTrack  = meta.track.flatMap(TrackMetadata.clean)
        let cleanAlbum  = meta.album.flatMap(TrackMetadata.clean)

        if let artist = cleanArtist, let track = cleanTrack {
            if let album = cleanAlbum {
                return "\(artist) — \(track) (\(album))"
            }
            return "\(artist) — \(track)"
        } else if let track = cleanTrack {
            if let year = meta.year {
                return "\(track) (\(year))"
            }
            return track
        } else if let artist = cleanArtist {
            return artist
        } else if playlist.indices.contains(currentIndex) {
            return playlist[currentIndex].deletingPathExtension().lastPathComponent
        }
        return "Lower3rd"
    }

    init() {
        // Clean shutdown on quit
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.bridge.stop()
        }

        // Periodic state synchronization
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.syncState()
            }
        }
    }

    /// Automatically plays the intro animation once on launch if no file was supplied (capped at 3.5s)
    func playIntroIfNeeded() {
        guard !hasMedia && playlist.isEmpty else { return }

        guard let introURL = Bundle.main.url(forResource: "intro", withExtension: "mp4"),
              FileManager.default.fileExists(atPath: introURL.path) else {
            return
        }

        isIntro = true
        hasMedia = true
        isPlaying = true
        bridge.play(url: introURL, muted: true)

        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3.5))
            guard let self = self, self.isIntro else { return }
            self.bridge.pause()
            self.isPlaying = false
        }
    }

    private func syncState() {
        guard hasMedia else { return }

        let currentlyPlaying = bridge.isPlaying
        if currentlyPlaying != isPlaying && !isIntro {
            isPlaying = currentlyPlaying
        }

        let dur = bridge.duration
        if dur > 0 {
            duration = dur
        }

        if !isDraggingSlider {
            currentTime = bridge.currentTime
            let pos = bridge.position
            progress = pos > 0 ? pos : (duration > 0 ? currentTime / duration : 0)
        }

        // Refresh dynamic multi-track audio channels & subtitles
        if !isIntro {
            let aTracks = bridge.getAudioTracks()
            if aTracks != audioTracks {
                audioTracks = aTracks
            }
            currentAudioTrackId = bridge.currentAudioTrack

            let sTracks = bridge.getSubtitleTracks()
            if sTracks != subtitleTracks {
                subtitleTracks = sTracks
            }
            currentSubtitleTrackId = bridge.currentSubtitleTrack
        }

        if isIntro {
            if currentTime >= 3.5 || bridge.isEnded {
                bridge.pause()
                isPlaying = false
            }
        } else if bridge.isEnded || (duration > 1.0 && currentTime >= duration - 0.25) {
            if playlist.count > 1 && currentIndex < playlist.count - 1 {
                nextTrack()
            } else {
                bridge.pause()
                isPlaying = false
            }
        }
    }

    func triggerOverlaySchedule() {
        overlayTask?.cancel()
        showOverlay = false

        overlayTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(10.0))
            guard let self = self, self.isPlaying, !self.isIntro else { return }

            withAnimation(.easeInOut(duration: 0.4)) {
                self.showOverlay = true
            }

            try? await Task.sleep(for: .seconds(7.5))

            withAnimation(.easeInOut(duration: 0.4)) {
                self.showOverlay = false
            }
        }
    }

    // MARK: - Open Files / Folders

    func openDialog() {
        // Deferred so NSOpenPanel's modal run loop doesn't start while the
        // SwiftUI Menu's own event-tracking run loop is still unwinding —
        // running both at once made the panel silently fail to appear when
        // the app had just launched without a document (issue: Open button
        // did nothing when app was launched from /Applications).
        DispatchQueue.main.async { [weak self] in
            NSApp.activate(ignoringOtherApps: true)

            let panel = NSOpenPanel()
            panel.title                      = "Open Video or Folder"
            panel.allowsMultipleSelection    = true
            panel.canChooseFiles             = true
            panel.canChooseDirectories       = true

            guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
            self?.loadURLs(panel.urls)
        }
    }

    func loadURLs(_ urls: [URL]) {
        isIntro = false
        var items: [URL] = []

        for url in urls {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) {
                if isDir.boolValue {
                    let folderItems = scanFolder(url)
                    items.append(contentsOf: folderItems)
                } else if Self.supportedExtensions.contains(url.pathExtension.lowercased()) {
                    let parentFolder = url.deletingLastPathComponent()
                    let siblings = scanFolder(parentFolder)
                    if !siblings.isEmpty {
                        playlist = siblings
                        currentIndex = siblings.firstIndex(of: url) ?? 0
                        playCurrentIndex()
                        return
                    }
                    items.append(url)
                }
            }
        }

        if !items.isEmpty {
            playlist = items
            currentIndex = 0
            playCurrentIndex()
        }
    }

    private func scanFolder(_ folderURL: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: folderURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var results: [URL] = []
        for case let fileURL as URL in enumerator {
            if Self.supportedExtensions.contains(fileURL.pathExtension.lowercased()) {
                results.append(fileURL)
            }
        }

        return results.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    // MARK: - Playback Controls

    func playCurrentIndex() {
        guard playlist.indices.contains(currentIndex) else { return }
        let url = playlist[currentIndex]

        isIntro = false
        loadedSubtitleName = nil
        let meta = bridge.play(url: url, muted: false)
        bridge.setVolume(Int(volume))
        isMuted = false

        if isEQEnabled {
            bridge.setEqualizer(enabled: true, preamp: eqPreamp, bands: eqBands)
        }

        hasMedia = true
        isPlaying = true
        currentMetadata = meta

        // Query available audio and subtitle tracks
        audioTracks = bridge.getAudioTracks()
        currentAudioTrackId = bridge.currentAudioTrack
        subtitleTracks = bridge.getSubtitleTracks()
        currentSubtitleTrackId = bridge.currentSubtitleTrack

        autoLoadMatchingSubtitle(for: url)
        triggerOverlaySchedule()
    }

    func togglePlayPause() {
        guard hasMedia else { return }
        if isPlaying {
            bridge.pause()
            isPlaying = false
        } else {
            bridge.resume()
            isPlaying = true
        }
    }

    func nextTrack() {
        guard playlist.count > 1 else { return }
        currentIndex = (currentIndex + 1) % playlist.count
        playCurrentIndex()
    }

    func previousTrack() {
        guard playlist.count > 1 else { return }
        if currentTime > 3.0 {
            seek(toProgress: 0)
        } else {
            currentIndex = (currentIndex - 1 + playlist.count) % playlist.count
            playCurrentIndex()
        }
    }

    func seek(toProgress newProgress: Double) {
        progress = newProgress
        bridge.seek(to: newProgress)
        currentTime = newProgress * duration
    }

    func setVolume(_ newVolume: Double) {
        volume = max(0, min(100, newVolume))
        if isMuted && volume > 0 {
            isMuted = false
        }
        bridge.setVolume(Int(volume))
    }

    func toggleMute() {
        isMuted.toggle()
        bridge.setMuted(isMuted)
    }

    // MARK: - Audio Track Selection

    func selectAudioTrack(_ track: MediaTrackItem) {
        bridge.setAudioTrack(track.id)
        currentAudioTrackId = track.id
        showToastNotification("Audio Track: \(track.name)")
    }

    // MARK: - Subtitles Controls

    func selectSubtitleTrack(_ track: MediaTrackItem) {
        bridge.setSubtitleTrack(track.id)
        currentSubtitleTrackId = track.id
        loadedSubtitleName = track.name
        showToastNotification("Subtitles: \(track.name)")
    }

    func disableSubtitles() {
        bridge.setSubtitleTrack(-1)
        currentSubtitleTrackId = -1
        loadedSubtitleName = nil
        showToastNotification("Subtitles Disabled")
    }

    func openSubtitleDialog() {
        DispatchQueue.main.async { [weak self] in
            NSApp.activate(ignoringOtherApps: true)

            let panel = NSOpenPanel()
            panel.title = "Import Subtitles"
            panel.allowsMultipleSelection = false
            panel.canChooseFiles = true
            panel.canChooseDirectories = false
            panel.allowedContentTypes = [
                UTType(filenameExtension: "srt") ?? .text,
                UTType(filenameExtension: "vtt") ?? .text,
                UTType(filenameExtension: "ass") ?? .text,
                UTType(filenameExtension: "ssa") ?? .text,
                UTType(filenameExtension: "sub") ?? .text,
                UTType(filenameExtension: "smi") ?? .text
            ]

            guard panel.runModal() == .OK, let url = panel.url else { return }
            self?.loadSubtitle(url: url)
        }
    }

    func loadSubtitle(url: URL) {
        let success = bridge.addSubtitle(url: url)
        if success {
            loadedSubtitleName = url.lastPathComponent
            subtitleTracks = bridge.getSubtitleTracks()
            currentSubtitleTrackId = bridge.currentSubtitleTrack
            showToastNotification("Subtitles Loaded: \(url.lastPathComponent)")
        } else {
            showToastNotification("Failed to load subtitle file")
        }
    }

    private func autoLoadMatchingSubtitle(for mediaURL: URL) {
        let parentDir = mediaURL.deletingLastPathComponent()
        let baseName = mediaURL.deletingPathExtension().lastPathComponent

        for ext in Self.supportedSubtitleExtensions {
            let candidateURL = parentDir.appendingPathComponent("\(baseName).\(ext)")
            if FileManager.default.fileExists(atPath: candidateURL.path) {
                let success = bridge.addSubtitle(url: candidateURL)
                if success {
                    loadedSubtitleName = candidateURL.lastPathComponent
                    subtitleTracks = bridge.getSubtitleTracks()
                    currentSubtitleTrackId = bridge.currentSubtitleTrack
                    showToastNotification("Subtitles Auto-Loaded: \(candidateURL.lastPathComponent)")
                    return
                }
            }
        }
    }

    // MARK: - Equalizer Controls

    func setEQEnabled(_ enabled: Bool) {
        isEQEnabled = enabled
        bridge.setEqualizer(enabled: enabled, preamp: eqPreamp, bands: eqBands)
        if enabled {
            showToastNotification("Audio Equalizer: Enabled")
        } else {
            showToastNotification("Audio Equalizer: Off (Bypassed)")
        }
    }

    func applyEQPreset(_ preset: EQPreset) {
        isEQEnabled = true
        selectedEQPresetName = preset.name
        eqPreamp = preset.preamp
        eqBands = preset.bands
        bridge.setEqualizer(enabled: true, preamp: eqPreamp, bands: eqBands)
        showToastNotification("Audio Profile: \(preset.name)")
    }

    func setBand(index: Int, value: Float) {
        guard eqBands.indices.contains(index) else { return }
        eqBands[index] = value
        selectedEQPresetName = "Custom"
        if isEQEnabled {
            bridge.setEqualizer(enabled: true, preamp: eqPreamp, bands: eqBands)
        }
    }

    func setPreamp(_ value: Float) {
        eqPreamp = value
        selectedEQPresetName = "Custom"
        if isEQEnabled {
            bridge.setEqualizer(enabled: true, preamp: eqPreamp, bands: eqBands)
        }
    }

    func showToastNotification(_ message: String) {
        subtitleNotificationTask?.cancel()
        subtitleNotificationText = message
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            showSubtitleNotification = true
        }

        subtitleNotificationTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3.0))
            guard let self = self else { return }
            withAnimation(.easeInOut(duration: 0.3)) {
                self.showSubtitleNotification = false
            }
        }
    }
}

// MARK: - Main Content View

struct ContentView: View {
    @State private var state = PlayerState()
    @State private var isDragTargeted = false
    @State private var showEqualizerPopover = false
    @State private var showOpenLogoSplash = false

    // Auto-hide Control Bar state
    @State private var isControlsVisible = true
    @State private var isControlsHovered = false
    @State private var isArrowHovered = false
    @State private var isWatermarkHovered = false
    @State private var autoHideTask: Task<Void, Never>? = nil

    // Full Screen
    @State private var isFullScreen = false

    // Cursor reveal on key press
    @State private var keyMonitor: Any? = nil

    private func toggleFullScreen() {
        NSApp.keyWindow?.toggleFullScreen(nil)
    }

    private func scheduleAutoHide() {
        autoHideTask?.cancel()
        guard !isControlsHovered && !showEqualizerPopover && state.hasMedia && !state.isIntro else { return }

        autoHideTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(5.0))
            guard !Task.isCancelled else { return }
            if !isControlsHovered && !showEqualizerPopover {
                withAnimation(.easeInOut(duration: 0.8)) {
                    isControlsVisible = false
                }
            }
        }
    }

    private func revealControls() {
        autoHideTask?.cancel()
        withAnimation(.easeInOut(duration: 0.35)) {
            isControlsVisible = true
        }
        scheduleAutoHide()
    }

    private func openFilesWithLogoSplash(_ urls: [URL]) {
        guard !urls.isEmpty else { return }

        if state.isIntro {
            state.bridge.stop()
            state.isIntro = false
            state.hasMedia = false
        }

        withAnimation(.easeIn(duration: 0.2)) {
            showOpenLogoSplash = true
        }

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.0))

            withAnimation(.easeOut(duration: 0.3)) {
                showOpenLogoSplash = false
            }

            let ext = urls[0].pathExtension.lowercased()
            if PlayerState.supportedSubtitleExtensions.contains(ext) {
                state.loadSubtitle(url: urls[0])
            } else {
                state.loadURLs(urls)
            }
            revealControls()
        }
    }

    private var dialogueBadgeText: String? {
        guard state.isEQEnabled else { return nil }
        switch state.selectedEQPresetName {
        case EQPreset.dialogueMax.name: return "MAX"
        case EQPreset.dialogueBoost.name: return "DLG"
        default: return nil
        }
    }

    private func toastIconName(for text: String) -> String {
        if text.contains("Audio Track") {
            return "waveform.and.person.filled"
        } else if text.contains("Equalizer") || text.contains("Profile") || text.contains("Boost") || text.contains("Mode") || text.contains("Rock") || text.contains("Pop") || text.contains("Flat") {
            return "waveform.badge.magnifyingglass"
        }
        return "captions.bubble.fill"
    }

    var body: some View {
        ZStack(alignment: .top) {
            // ── Video surface ──────────────────────────────────────
            VLCPlayerView(bridge: state.bridge)
                .ignoresSafeArea()

            // ── Phase 2 Animated Lower-Third Overlay (Lower-Left) ───
            if !state.isIntro && !showOpenLogoSplash {
                VStack {
                    Spacer()
                    HStack {
                        LowerThirdOverlayView(
                            metadata: state.currentMetadata,
                            isVisible: state.showOverlay
                        )
                        .padding(.leading, 48)
                        .padding(.bottom, 100)

                        Spacer()
                    }
                }
                .allowsHitTesting(false)
            }

            // ── Watermark Logo (Bottom Right) ──────────────────────
            if !state.isIntro && !showOpenLogoSplash {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Image("Logo")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 48, height: 48)
                            .opacity(isWatermarkHovered ? 0.85 : 0.42)
                            .shadow(color: .black.opacity(0.6), radius: 6, x: 1, y: 2)
                            .padding(.trailing, 32)
                            .padding(.bottom, 80)
                            .animation(.easeInOut(duration: 0.25), value: isWatermarkHovered)
                            .onHover { hovering in
                                isWatermarkHovered = hovering
                            }
                    }
                }
                .allowsHitTesting(true)
            }

            // ── 1-Second Logo Splash Screen on External File Open ───
            if showOpenLogoSplash {
                ZStack {
                    Color.black.opacity(0.92)
                        .ignoresSafeArea()

                    VStack(spacing: 16) {
                        Image("Logo")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 110, height: 110)
                            .shadow(color: .cyan.opacity(0.6), radius: 24, x: 0, y: 0)
                            .shadow(color: .black.opacity(0.8), radius: 10, x: 0, y: 4)

                        Text("LOWER3RD")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .tracking(5)
                            .foregroundColor(.white)
                            .shadow(color: .cyan.opacity(0.5), radius: 12, x: 0, y: 0)
                    }
                    .scaleEffect(showOpenLogoSplash ? 1.0 : 0.88)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
                .transition(.opacity)
                .zIndex(20)
            }

            // ── Subtitle / Toast HUD Notification ─────────────────
            if state.showSubtitleNotification, let text = state.subtitleNotificationText {
                VStack {
                    HStack(spacing: 8) {
                        Image(systemName: toastIconName(for: text))
                            .foregroundColor(.cyan)
                            .font(.system(size: 13, weight: .semibold))
                        Text(text)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(.ultraThinMaterial)
                            .shadow(color: .black.opacity(0.4), radius: 8, x: 0, y: 3)
                    )
                    .overlay(
                        Capsule()
                            .stroke(Color.cyan.opacity(0.35), lineWidth: 1)
                    )
                    .padding(.top, 64)
                    .transition(.move(edge: .top).combined(with: .opacity))

                    Spacer()
                }
                .allowsHitTesting(false)
            }

            // ── Bottom Sensor Region for Pull-Up ───────────────────
            if !isControlsVisible && state.hasMedia && !state.isIntro {
                VStack {
                    Spacer()
                    Color.black.opacity(0.001)
                        .frame(height: 38)
                        .contentShape(Rectangle())
                        .onHover { hovering in
                            if hovering {
                                revealControls()
                            }
                        }
                }
            }

            // ── Translucent Pull-Up Arrow Tab ─────────────────────
            if !isControlsVisible && state.hasMedia && !state.isIntro {
                VStack(spacing: 0) {
                    Spacer()

                    HStack(spacing: 4) {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white.opacity(isArrowHovered ? 1.0 : 0.6))
                    }
                    .frame(width: 56, height: 22)
                    .background(
                        Capsule()
                            .fill(.ultraThinMaterial)
                            .shadow(color: .black.opacity(0.4), radius: 6, x: 0, y: 2)
                    )
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(isArrowHovered ? 0.45 : 0.18), lineWidth: 1)
                    )
                    .contentShape(Rectangle())
                    .padding(.bottom, 6)
                    .onHover { hovering in
                        isArrowHovered = hovering
                        if hovering {
                            revealControls()
                        }
                    }
                    .onTapGesture {
                        revealControls()
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                .zIndex(10)
            }

            // ── Transport bar (bottom) ─────────────────────────────
            VStack {
                Spacer()

                HStack(spacing: 12) {
                    transportButtons
                    timeAndSeekTrack
                    audioAndSubtitleControls
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .shadow(color: .black.opacity(0.4), radius: 8, x: 0, y: 4)
                )
                .padding(.bottom, 14)
                .offset(y: isControlsVisible ? 0 : 85)
                .opacity(isControlsVisible ? 1.0 : 0.0)
                .animation(isControlsVisible ? .easeInOut(duration: 0.35) : .easeInOut(duration: 0.8), value: isControlsVisible)
                .allowsHitTesting(isControlsVisible)
                .onHover { hovering in
                    isControlsHovered = hovering
                    if hovering {
                        autoHideTask?.cancel()
                    } else {
                        scheduleAutoHide()
                    }
                }
            }
            .allowsHitTesting(isControlsVisible)
            .zIndex(5)

            // ── Drag & Drop visual overlay ─────────────────────────
            if isDragTargeted {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.cyan, style: StrokeStyle(lineWidth: 3, dash: [8]))
                    .background(Color.cyan.opacity(0.12))
                    .ignoresSafeArea()
            }
        }
        .frame(minWidth: 720, minHeight: 440)
        .background(Color.black)
        .navigationTitle(state.windowTitle)
        .onAppear {
            if !AppDelegate.initialOpenedURLs.isEmpty {
                let urls = AppDelegate.initialOpenedURLs
                AppDelegate.initialOpenedURLs = []
                openFilesWithLogoSplash(urls)
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    if AppDelegate.initialOpenedURLs.isEmpty && !state.hasMedia {
                        state.playIntroIfNeeded()
                    }
                }
            }
            scheduleAutoHide()
        }
        .onReceive(NotificationCenter.default.publisher(for: .lower3rdOpenFileNotification)) { notification in
            if let urls = notification.object as? [URL], !urls.isEmpty {
                openFilesWithLogoSplash(urls)
            }
        }
        .onOpenURL { url in
            openFilesWithLogoSplash([url])
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { _ in
            isFullScreen = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { _ in
            isFullScreen = false
        }
        .onChange(of: state.hasMedia) { _, hasMedia in
            if hasMedia {
                revealControls()
            } else {
                NSCursor.setHiddenUntilMouseMoves(false)
            }
        }
        .onChange(of: isControlsVisible) { _, visible in
            if visible {
                NSCursor.setHiddenUntilMouseMoves(false)
            } else if state.hasMedia && !state.isIntro {
                NSCursor.setHiddenUntilMouseMoves(true)
            }
        }
        .onAppear {
            guard keyMonitor == nil else { return }
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                NSCursor.setHiddenUntilMouseMoves(false)
                return event
            }
        }
        .onDisappear {
            if let keyMonitor {
                NSEvent.removeMonitor(keyMonitor)
                self.keyMonitor = nil
            }
            NSCursor.setHiddenUntilMouseMoves(false)
        }
        .onChange(of: showEqualizerPopover) { _, isPresented in
            if !isPresented {
                scheduleAutoHide()
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isDragTargeted) { providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let url = url {
                        Task { @MainActor in
                            openFilesWithLogoSplash([url])
                        }
                    }
                }
            }
            return true
        }
    }

    // MARK: - Subviews for Transport Bar

    @ViewBuilder
    private var transportButtons: some View {
        HStack(spacing: 8) {
            Menu {
                Button("Open Media File / Folder...") {
                    state.openDialog()
                    revealControls()
                }
                Button("Import Subtitle File...") {
                    state.openSubtitleDialog()
                    revealControls()
                }
                Divider()
                Button(isFullScreen ? "Exit Full Screen" : "Enter Full Screen") {
                    toggleFullScreen()
                }
            } label: {
                Label("Open", systemImage: "folder.fill")
                    .font(.system(size: 12, weight: .medium))
            }
            .menuStyle(.borderlessButton)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.12))
            .cornerRadius(6)

            Divider()
                .frame(height: 16)
                .background(Color.white.opacity(0.2))

            Button {
                state.previousTrack()
                revealControls()
            } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor((state.playlist.count > 1 && !state.isIntro) ? .white : .white.opacity(0.35))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .disabled(state.playlist.count <= 1 || state.isIntro)
            .keyboardShortcut(.leftArrow, modifiers: [.command])

            Button {
                state.togglePlayPause()
                revealControls()
            } label: {
                Image(systemName: (state.isPlaying && !state.isIntro) ? "pause.fill" : "play.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor((!state.hasMedia || state.isIntro) ? .white.opacity(0.35) : .white)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .disabled(!state.hasMedia || state.isIntro)
            .keyboardShortcut(.space, modifiers: [])

            Button {
                state.nextTrack()
                revealControls()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor((state.playlist.count > 1 && !state.isIntro) ? .white : .white.opacity(0.35))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .disabled(state.playlist.count <= 1 || state.isIntro)
            .keyboardShortcut(.rightArrow, modifiers: [.command])
        }
    }

    @ViewBuilder
    private var timeAndSeekTrack: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                Text(formatTime(state.currentTime))
                    .monospacedDigit()
                Text("/")
                    .foregroundColor(.white.opacity(0.4))
                Text(formatTime(state.duration))
                    .monospacedDigit()
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(state.hasMedia && !state.isIntro ? .white : .white.opacity(0.35))
            .frame(minWidth: 90)

            Slider(
                value: Binding(
                    get: { state.progress },
                    set: { newProg in
                        state.seek(toProgress: newProg)
                        revealControls()
                    }
                ),
                in: 0...1,
                onEditingChanged: { editing in
                    state.isDraggingSlider = editing
                    if editing {
                        autoHideTask?.cancel()
                    } else {
                        scheduleAutoHide()
                    }
                }
            )
            .tint(Color(red: 0.0, green: 0.82, blue: 1.0))
            .accentColor(Color(red: 0.0, green: 0.82, blue: 1.0))
            .disabled(!state.hasMedia || state.isIntro)
            .frame(height: 20)

            if state.playlist.count > 1 && !state.isIntro {
                Text("\(state.currentIndex + 1)/\(state.playlist.count)")
                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                    .foregroundColor(.cyan)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.cyan.opacity(0.18))
                    .cornerRadius(4)
            }
        }
    }

    @ViewBuilder
    private var audioAndSubtitleControls: some View {
        HStack(spacing: 8) {
            // ── Audio Channel / Language Selection (Appears ONLY if file has > 1 audio track) ──
            if state.audioTracks.count > 1 && !state.isIntro {
                Menu {
                    Section("Audio Language / Channel") {
                        ForEach(state.audioTracks) { track in
                            Button {
                                state.selectAudioTrack(track)
                            } label: {
                                if state.currentAudioTrackId == track.id {
                                    Text("✓ \(track.name)")
                                } else {
                                    Text(track.name)
                                }
                            }
                        }
                    }
                } label: {
                    Image(systemName: "waveform.and.person.filled")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.cyan)
                        .frame(width: 24, height: 24)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 26, height: 24)
                .help("Audio Track Selection (\(state.audioTracks.count) tracks available)")
            }

            // ── Subtitles Selection (Appears ONLY if file has embedded subtitles or imported subtitle) ──
            if (!state.subtitleTracks.isEmpty || state.loadedSubtitleName != nil) && !state.isIntro {
                Menu {
                    Button {
                        state.disableSubtitles()
                    } label: {
                        if state.currentSubtitleTrackId == -1 && state.loadedSubtitleName == nil {
                            Text("✓ Subtitles Disabled")
                        } else {
                            Text("Disable Subtitles")
                        }
                    }

                    if !state.subtitleTracks.isEmpty {
                        Divider()
                        Section("Subtitle Tracks") {
                            ForEach(state.subtitleTracks) { track in
                                Button {
                                    state.selectSubtitleTrack(track)
                                } label: {
                                    if state.currentSubtitleTrackId == track.id {
                                        Text("✓ \(track.name)")
                                    } else {
                                        Text(track.name)
                                    }
                                }
                            }
                        }
                    }

                    Divider()
                    Button("Import Subtitle File...") {
                        state.openSubtitleDialog()
                    }
                } label: {
                    let hasActiveSub = state.currentSubtitleTrackId >= 0 || state.loadedSubtitleName != nil
                    Image(systemName: hasActiveSub ? "captions.bubble.fill" : "captions.bubble")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(hasActiveSub ? .cyan : .white.opacity(0.85))
                        .frame(width: 24, height: 24)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 26, height: 24)
                .help("Subtitles Selection")
            }

            // ── Audio Equalizer & Dialogue Booster Button ──
            Button {
                showEqualizerPopover.toggle()
                if showEqualizerPopover {
                    autoHideTask?.cancel()
                } else {
                    scheduleAutoHide()
                }
            } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "slider.vertical.3")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(state.isEQEnabled ? .cyan : .white.opacity(0.85))
                        .frame(width: 24, height: 24)

                    if state.isEQEnabled, let badge = dialogueBadgeText {
                        Text(badge)
                            .font(.system(size: 7, weight: .bold))
                            .foregroundColor(.black)
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.cyan))
                            .offset(x: 6, y: -4)
                    }
                }
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showEqualizerPopover, arrowEdge: .bottom) {
                AudioEqualizerView(state: state)
            }
            .help(dialogueBadgeText.map { "Audio Equalizer — Dialogue \($0 == "MAX" ? "Max" : "Boost") active" } ?? "Audio Equalizer & Dialogue Booster")

            Divider()
                .frame(height: 16)
                .background(Color.white.opacity(0.2))

            // ── Mute & Volume Slider ──
            Button {
                state.toggleMute()
                revealControls()
            } label: {
                Image(systemName: state.isMuted || state.volume == 0
                      ? "speaker.slash.fill"
                      : (state.volume < 50 ? "speaker.wave.1.fill" : "speaker.wave.2.fill"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)

            Slider(
                value: Binding(
                    get: { state.isMuted ? 0 : state.volume },
                    set: {
                        state.setVolume($0)
                        revealControls()
                    }
                ),
                in: 0...100
            )
            .frame(width: 70)
            .accentColor(.white.opacity(0.8))

            Divider()
                .frame(height: 16)
                .background(Color.white.opacity(0.2))

            // ── Full Screen Toggle ──
            Button {
                toggleFullScreen()
            } label: {
                Image(systemName: isFullScreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .keyboardShortcut("f", modifiers: [.command, .control])
            .help(isFullScreen ? "Exit Full Screen" : "Enter Full Screen")
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        guard !seconds.isNaN && !seconds.isInfinite && seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        let hrs = total / 3600
        let mins = (total % 3600) / 60
        let secs = total % 60

        if hrs > 0 {
            return String(format: "%d:%02d:%02d", hrs, mins, secs)
        } else {
            return String(format: "%d:%02d", mins, secs)
        }
    }
}
