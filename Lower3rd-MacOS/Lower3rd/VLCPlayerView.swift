import SwiftUI
import AppKit

/// NSViewRepresentable that hosts the libvlc video output surface.
/// libvlc renders directly into this NSView's layer.
struct VLCPlayerView: NSViewRepresentable {

    let bridge: VLCBridge

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor
        // Hand the view to libvlc as the render target
        bridge.setDrawable(view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
