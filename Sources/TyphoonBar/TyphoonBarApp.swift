import SwiftUI
import AppKit

extension NSImage {
    static let typhoonGlyphIcon: NSImage = {
        let image = NSImage(size: NSSize(width: 22, height: 22), flipped: false) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.setStrokeColor(NSColor.black.cgColor)
            context.setFillColor(NSColor.black.cgColor)
            context.setLineWidth(3.15)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            context.translateBy(x: 11, y: 11)

            for index in 0..<3 {
                context.saveGState()
                context.rotate(by: CGFloat(index) * 2 * .pi / 3)
                let arc = CGMutablePath()
                arc.move(to: CGPoint(x: 1.0, y: -0.25))
                arc.addCurve(to: CGPoint(x: 6.3, y: -7.25),
                             control1: CGPoint(x: -0.25, y: -3.75),
                             control2: CGPoint(x: 2.1, y: -6.9))
                context.addPath(arc)
                context.strokePath()
                context.restoreGState()
            }
            context.fillEllipse(in: CGRect(x: -1.1, y: -1.1, width: 2.2, height: 2.2))
            return true
        }
        image.isTemplate = true
        return image
    }()

    static let typhoonStatusIcon: NSImage = {
        let size = NSSize(width: 22, height: 22)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 2.25, dy: 2.25)).fill()

            NSImage.typhoonGlyphIcon.draw(in: NSRect(x: 4, y: 4, width: 14, height: 14),
                                          from: .zero, operation: .destinationOut, fraction: 1)
            return true
        }
        image.isTemplate = true
        return image
    }()
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
              let icon = NSImage(contentsOf: url) else { return }
        NSApplication.shared.applicationIconImage = icon
    }
}

@main
struct TyphoonBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = TyphoonStore()

    var body: some Scene {
        MenuBarExtra {
            TyphoonPanel(store: store)
                .task { await store.start() }
        } label: {
            Image(nsImage: .typhoonStatusIcon)
                .resizable()
                .frame(width: 22, height: 22)
            .accessibilityLabel("台风监测")
        }
        .menuBarExtraStyle(.window)
    }
}
