import SwiftUI

// MARK: - Equalizer Presets

struct EQPreset: Identifiable, Equatable {
    let id: String
    let name: String
    let icon: String
    let subtitle: String
    let preamp: Float
    let bands: [Float] // 10 bands: 60Hz, 170Hz, 310Hz, 600Hz, 1kHz, 3kHz, 6kHz, 12kHz, 14kHz, 16kHz

    static let dialogueBoost = EQPreset(
        id: "dialogue",
        name: "Dialogue Booster",
        icon: "bubble.left.and.bubble.right.fill",
        subtitle: "High vocal clarity for movies & TV speech",
        preamp: 4.5,
        bands: [-8.0, -5.0, 2.0, 6.5, 11.0, 13.0, 9.5, 3.5, 0.0, -2.0]
    )

    static let dialogueMax = EQPreset(
        id: "dialogue_max",
        name: "Dialogue Max",
        icon: "waveform.badge.magnifyingglass",
        subtitle: "Maximum voice punch over loud explosions/music",
        preamp: 5.5,
        bands: [-12.0, -7.0, 3.0, 8.5, 14.0, 15.5, 11.5, 4.0, -1.0, -4.0]
    )

    static let bassBoost = EQPreset(
        id: "bass",
        name: "Bass Boost",
        icon: "speaker.wave.3.fill",
        subtitle: "Punchy and deep low-end",
        preamp: 0.0,
        bands: [9.0, 7.5, 4.5, 2.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
    )

    static let nightMode = EQPreset(
        id: "night",
        name: "Night Mode",
        icon: "moon.stars.fill",
        subtitle: "Suppresses loud booms; keeps speech clear",
        preamp: 2.0,
        bands: [-9.0, -6.0, 0.0, 4.0, 7.0, 7.0, 3.0, -2.0, -5.0, -8.0]
    )

    static let rock = EQPreset(
        id: "rock",
        name: "Rock",
        icon: "guitars.fill",
        subtitle: "Crisp guitars & punchy drums",
        preamp: 0.0,
        bands: [5.0, 3.5, -1.0, -2.5, 1.0, 3.0, 5.5, 7.0, 7.5, 8.0]
    )

    static let pop = EQPreset(
        id: "pop",
        name: "Pop",
        icon: "music.note",
        subtitle: "Warm vocals and energetic highs",
        preamp: 0.0,
        bands: [-1.5, 1.0, 4.0, 5.0, 3.5, 1.0, -1.0, -1.5, -1.5, -1.5]
    )

    static let electronic = EQPreset(
        id: "electronic",
        name: "Electronic",
        icon: "bolt.fill",
        subtitle: "Tight bass and airy highs",
        preamp: 0.0,
        bands: [5.5, 4.5, 2.0, 0.0, 1.5, 3.5, 5.0, 4.0, 3.0, 2.0]
    )

    static let flat = EQPreset(
        id: "flat",
        name: "Flat",
        icon: "slider.horizontal.3",
        subtitle: "Neutral unprocessed studio sound",
        preamp: 0.0,
        bands: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
    )

    static let allPresets: [EQPreset] = [
        .dialogueBoost,
        .dialogueMax,
        .bassBoost,
        .nightMode,
        .rock,
        .pop,
        .electronic,
        .flat
    ]

    static let bandFrequencies = [
        "60Hz", "170Hz", "310Hz", "600Hz", "1kHz",
        "3kHz", "6kHz", "12kHz", "14kHz", "16kHz"
    ]
}

// MARK: - Equalizer Popover View

struct AudioEqualizerView: View {
    @Bindable var state: PlayerState

    var body: some View {
        VStack(spacing: 14) {
            // Header with Master Toggle
            HStack(alignment: .center) {
                HStack(spacing: 8) {
                    Image(systemName: "waveform.badge.magnifyingglass")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.cyan)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Audio Enhancements")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                        Text(state.isEQEnabled ? (state.selectedEQPresetName ?? "Custom EQ") : "Equalizer Disabled")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white.opacity(0.6))
                    }
                }

                Spacer()

                // Master EQ Toggle
                Toggle("", isOn: Binding(
                    get: { state.isEQEnabled },
                    set: { state.setEQEnabled($0) }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
            }

            // Quick Preset Grid (2 Rows of 4 Pills, Fully Fitting within View)
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    ForEach(EQPreset.allPresets.prefix(4)) { preset in
                        presetButton(preset)
                    }
                }
                HStack(spacing: 6) {
                    ForEach(EQPreset.allPresets.suffix(4)) { preset in
                        presetButton(preset)
                    }
                }
            }

            Divider()
                .background(Color.white.opacity(0.15))

            // 10-Band Sliders Rack (Clean, Centered, Perfectly Proportioned)
            HStack(spacing: 8) {
                ForEach(0..<10, id: \.self) { index in
                    let value = state.eqBands.indices.contains(index) ? state.eqBands[index] : 0.0
                    VStack(spacing: 5) {
                        // Current dB Label
                        Text(formatDB(value))
                            .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                            .foregroundColor(state.isEQEnabled ? (value > 0 ? .cyan : (value < 0 ? .orange : .white.opacity(0.6))) : .white.opacity(0.3))
                            .frame(width: 30)

                        // Vertical Slider Track
                        CustomVerticalSlider(
                            value: Binding(
                                get: { Double(state.eqBands.indices.contains(index) ? state.eqBands[index] : 0) },
                                set: { state.setBand(index: index, value: Float($0)) }
                            ),
                            range: -20.0...20.0,
                            isEnabled: state.isEQEnabled
                        )
                        .frame(width: 20, height: 110)

                        // Frequency Label
                        Text(EQPreset.bandFrequencies[index])
                            .font(.system(size: 8.5, weight: .medium))
                            .foregroundColor(state.isEQEnabled ? .white.opacity(0.85) : .white.opacity(0.3))
                            .frame(width: 30)
                    }
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black.opacity(0.35))
            )

            // Preamp & Reset Bottom Bar
            HStack(spacing: 8) {
                Image(systemName: "dial.low.fill")
                    .font(.system(size: 11))
                    .foregroundColor(state.isEQEnabled ? .white.opacity(0.7) : .white.opacity(0.3))

                Text("Preamp")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(state.isEQEnabled ? .white.opacity(0.85) : .white.opacity(0.3))

                Slider(
                    value: Binding(
                        get: { Double(state.eqPreamp) },
                        set: { state.setPreamp(Float($0)) }
                    ),
                    in: -20.0...20.0
                )
                .accentColor(.cyan)
                .disabled(!state.isEQEnabled)
                .frame(width: 110)

                Text(formatDB(state.eqPreamp))
                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                    .foregroundColor(state.isEQEnabled ? .cyan : .white.opacity(0.3))
                    .frame(width: 38, alignment: .leading)

                Spacer()

                Button {
                    state.applyEQPreset(.flat)
                } label: {
                    Text("Reset EQ")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundColor(.white.opacity(0.85))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.12))
                        .cornerRadius(5)
                }
                .buttonStyle(.plain)
                .disabled(!state.isEQEnabled)
            }
            .padding(.horizontal, 2)
        }
        .padding(14)
        .frame(width: 490)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.5), radius: 12, x: 0, y: 6)
        )
    }

    @ViewBuilder
    private func presetButton(_ preset: EQPreset) -> some View {
        let isSelected = state.isEQEnabled && state.selectedEQPresetName == preset.name
        let isDialogue = preset.id.starts(with: "dialogue")
        Button {
            state.applyEQPreset(preset)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: preset.icon)
                    .font(.system(size: 9, weight: .semibold))
                Text(preset.name)
                    .font(.system(size: 10, weight: isSelected ? .bold : .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 5)
            .background(
                isSelected
                    ? Color.cyan.opacity(0.9)
                    : (isDialogue ? Color.cyan.opacity(0.18) : Color.white.opacity(0.08))
            )
            .foregroundColor(isSelected ? .black : (isDialogue ? .cyan : .white.opacity(0.85)))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? Color.clear : (isDialogue ? Color.cyan.opacity(0.4) : Color.white.opacity(0.12)), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func formatDB(_ val: Float) -> String {
        if val > 0 {
            return String(format: "+%.1f", val)
        } else {
            return String(format: "%.1f", val)
        }
    }
}

// MARK: - Custom Vertical Slider

struct CustomVerticalSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let isEnabled: Bool

    var body: some View {
        GeometryReader { geo in
            let height = geo.size.height
            let width = geo.size.width
            let normalized = CGFloat((value - range.lowerBound) / (range.upperBound - range.lowerBound))
            let thumbY = (1.0 - normalized) * height

            ZStack(alignment: .top) {
                // Background Track
                Capsule()
                    .fill(Color.white.opacity(isEnabled ? 0.15 : 0.06))
                    .frame(width: 4)
                    .position(x: width / 2, y: height / 2)

                // 0dB Center Line
                Rectangle()
                    .fill(Color.white.opacity(isEnabled ? 0.35 : 0.1))
                    .frame(width: 10, height: 1)
                    .position(x: width / 2, y: height / 2)

                // Active Fill
                let midY = height / 2
                let fillHeight = abs(thumbY - midY)
                let fillY = min(thumbY, midY) + (fillHeight / 2)
                Capsule()
                    .fill(isEnabled ? (value >= 0 ? Color.cyan.opacity(0.8) : Color.orange.opacity(0.8)) : Color.white.opacity(0.15))
                    .frame(width: 4, height: max(0, fillHeight))
                    .position(x: width / 2, y: fillY)

                // Thumb Knob
                Circle()
                    .fill(isEnabled ? (value >= 0 ? Color.cyan : Color.orange) : Color.gray)
                    .frame(width: 12, height: 12)
                    .shadow(color: .black.opacity(0.4), radius: 3, x: 0, y: 1)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.8), lineWidth: 1.2)
                    )
                    .position(x: width / 2, y: thumbY)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        guard isEnabled else { return }
                        let newY = max(0, min(height, gesture.location.y))
                        let newNorm = 1.0 - (newY / height)
                        let rawVal = range.lowerBound + Double(newNorm) * (range.upperBound - range.lowerBound)
                        // Snap near 0
                        if abs(rawVal) < 0.4 {
                            value = 0.0
                        } else {
                            value = round(rawVal * 2.0) / 2.0
                        }
                    }
            )
        }
    }
}
