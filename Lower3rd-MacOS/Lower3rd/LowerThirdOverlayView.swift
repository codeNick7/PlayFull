import SwiftUI

/// 90s music-television inspired on-air lower-third overlay.
/// Recreates classic broadcast character-generator graphics:
/// - Positioned in the lower-left third
/// - Vibrant retro yellow/gold Artist with expanded tracking
/// - Quoted uppercase Track title & Album / Year in crisp white
/// - Bold Futura broadcast typography with heavy solid black outline & drop shadow
/// - Zero background box/card
struct LowerThirdOverlayView: View {
    let metadata: TrackMetadata
    let isVisible: Bool

    var body: some View {
        let lines = metadata.lowerThirdLines

        if metadata.hasAnyField {
            VStack(alignment: .leading, spacing: 4) {
                // Line 1: Artist (Classic Retro Yellow/Gold, Heavy Condensed ALL CAPS)
                if let artist = lines.artist, !artist.isEmpty {
                    Text(artist.uppercased())
                        .font(
                            Font.custom("Futura-CondensedExtraBold", size: 28)
                                .weight(.heavy)
                        )
                        .foregroundColor(Color(red: 0.96, green: 0.93, blue: 0.28))
                        .tracking(2.2)
                        // Broadcast character generator hard outline & shadow
                        .shadow(color: .black, radius: 0, x: 2, y: 2)
                        .shadow(color: .black, radius: 0, x: -1.5, y: 1.5)
                        .shadow(color: .black, radius: 0, x: 1.5, y: -1.5)
                        .shadow(color: .black, radius: 0, x: -1.5, y: -1.5)
                        .shadow(color: .black.opacity(0.9), radius: 6, x: 2, y: 3)
                }

                // Line 2: Track Title (Quoted in pure crisp white)
                if let track = lines.track, !track.isEmpty {
                    Text("\"\(track.uppercased())\"")
                        .font(
                            Font.custom("Futura-Bold", size: 20)
                                .weight(.bold)
                        )
                        .foregroundColor(.white)
                        .tracking(1.2)
                        .shadow(color: .black, radius: 0, x: 2, y: 2)
                        .shadow(color: .black, radius: 0, x: -1.5, y: 1.5)
                        .shadow(color: .black, radius: 0, x: 1.5, y: -1.5)
                        .shadow(color: .black, radius: 0, x: -1.5, y: -1.5)
                        .shadow(color: .black.opacity(0.9), radius: 5, x: 2, y: 3)
                }

                // Line 3: Album & Year Details
                if let detail = lines.detail, !detail.isEmpty {
                    Text(detail.uppercased())
                        .font(
                            Font.custom("Futura-Medium", size: 15)
                                .weight(.semibold)
                        )
                        .foregroundColor(Color(red: 1.0, green: 0.95, blue: 0.88))
                        .tracking(1.4)
                        .shadow(color: .black, radius: 0, x: 1.5, y: 1.5)
                        .shadow(color: .black, radius: 0, x: -1, y: 1)
                        .shadow(color: .black, radius: 0, x: 1, y: -1)
                        .shadow(color: .black.opacity(0.9), radius: 4, x: 2, y: 2)
                }
            }
            .fixedSize(horizontal: true, vertical: true)
            .opacity(isVisible ? 1.0 : 0.0)
            .offset(y: isVisible ? 0 : 10)
            .animation(.easeInOut(duration: isVisible ? 0.35 : 0.45), value: isVisible)
            .allowsHitTesting(false)
        }
    }
}
