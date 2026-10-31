import AppKit
import SwiftUI

/// An invisible titlebar drag strip for the hidden-title-bar window. Starts after the traffic lights.
struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        DragView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class DragView: NSView {
        override func mouseDown(with event: NSEvent) {
            guard let window else { return }
            if event.clickCount == 2 {
                window.zoom(nil)
            } else {
                window.performDrag(with: event)
            }
        }
    }
}
