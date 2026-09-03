import AppKit
import SwiftUI

/// A small "unlocking" card, shown only if reading the encrypted store takes
/// long enough to notice — which in practice means the Keychain is asking the
/// user to authorise access. It never flashes on a normal launch.
@MainActor
final class UnlockNotice {
    private var window: NSWindow?
    private var timer: Timer?
    private var dismissed = false

    func showAfterDelay(_ delay: TimeInterval = 0.6) {
        timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.dismissed else { return }
                self.present()
            }
        }
    }

    func dismiss() {
        dismissed = true
        timer?.invalidate()
        timer = nil
        window?.orderOut(nil)
        window = nil
    }

    private func present() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 96),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.contentView = NSHostingView(rootView: UnlockNoticeView())
        panel.center()
        panel.orderFront(nil)
        window = panel
    }
}

private struct UnlockNoticeView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "lock.open")
                .font(.system(size: 18))
                .foregroundStyle(.secondary)
            Text("Unlocking your notes")
                .font(.system(size: 13, weight: .medium))
            Text("Waiting for Keychain access.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
