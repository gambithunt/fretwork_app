#if DEBUG
import SwiftUI
import UIKit

/// DEBUG-only harness that proves the iPad sidebar selection highlight slides
/// rather than jumps. Launched with `-IOSSidebarGlideCapture`, it settles the
/// shell, posts `notification` (synthetic taps don't drive SwiftUI selection —
/// CLAUDE.md workflow 6), and records ~16 ms frames of the left sidebar strip so
/// an offline pass can track the highlight's centroid across frames.
///
/// Compiled out of Release entirely.
enum IOSSidebarGlideCapture {
    static let notification = Notification.Name("FretworkIOSSidebarGlide")
    static var isActive: Bool { CommandLine.arguments.contains("-IOSSidebarGlideCapture") }
    /// The module the capture slides to. Notes by default; pass
    /// `-IOSSidebarGlideIntervals` to slide to Intervals instead (a module row
    /// with a longer subtitle, so both can be checked for subtitle visibility).
    static var target: AppScreen {
        CommandLine.arguments.contains("-IOSSidebarGlideIntervals") ? .module(.intervals) : .module(.notes)
    }

    /// The capture needs the sidebar visible. iPad `NavigationSplitView`
    /// collapses it in portrait (`columnVisibility == .automatic`), so force
    /// landscape — the same `requestGeometryUpdate` the snapshot harness uses.
    /// A cold launch can drop a request made before the window scene connects,
    /// so retry on three widening delays rather than hoping one sticks.
    @MainActor
    static func requestLandscape() {
        Task { @MainActor in
            for delay in [1.0, 2.0, 3.0] {
                try? await Task.sleep(for: .seconds(delay))
                if let scene = UIApplication.shared.connectedScenes
                    .compactMap({ $0 as? UIWindowScene }).first {
                    scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscapeRight))
                }
            }
        }
    }

    /// The one window that owns the sidebar. `nil` while the scene isn't
    /// connected yet, which the settle delay in `IOSAppRootView` avoids.
    @MainActor
    static func keyWindow() -> UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?
            .keyWindow
    }

    /// Captures the window at full resolution (the screen's own scale) at ~16 ms
    /// intervals for `seconds`, writing numbered JPEGs to the app's tmp dir.
    /// After `preFrames` resting frames it calls `trigger` once, so a run records
    /// the resting state before the selection change, then the slide — proving
    /// the highlight and the detail are driven by the same selection.
    @MainActor
    static func record(seconds: Double, preFrames: Int, trigger: @escaping @MainActor () -> Void) async {
        guard let window = keyWindow() else { return }
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("fw-sidebar-glide")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // A fresh run: drop any frames a previous launch left behind.
        for old in (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [] {
            try? FileManager.default.removeItem(at: old)
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = window.screen.scale
        let bounds = window.bounds
        let start = ContinuousClock.now
        var index = 0
        var didTrigger = false
        while ContinuousClock.now - start < .seconds(seconds) {
            autoreleasepool {
                let renderer = UIGraphicsImageRenderer(bounds: bounds, format: format)
                let image = renderer.image { _ in
                    window.drawHierarchy(in: bounds, afterScreenUpdates: false)
                }
                if let data = image.jpegData(compressionQuality: 0.85) {
                    let url = dir.appendingPathComponent(String(format: "frame_%04d.jpg", index))
                    try? data.write(to: url)
                }
            }
            index += 1
            if !didTrigger && index >= preFrames {
                didTrigger = true
                trigger()
            }
            try? await Task.sleep(until: start + .milliseconds(16 * index), clock: .continuous)
        }
        print("FW-GLIDE: wrote \(index) frames to \(dir.path)")
    }
}
#endif
