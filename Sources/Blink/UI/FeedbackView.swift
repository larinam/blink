import AppKit
import SwiftUI

enum FeedbackContact {
    static let address = "blink@wellkernel.com"
    static let url = URL(string: "mailto:\(address)?subject=Blink%20feedback")!
    static let gmailURL: URL = {
        var components = URLComponents(string: "https://mail.google.com/mail/")!
        components.queryItems = [
            URLQueryItem(name: "view", value: "cm"),
            URLQueryItem(name: "fs", value: "1"),
            URLQueryItem(name: "to", value: address),
            URLQueryItem(name: "su", value: "Blink feedback"),
        ]
        return components.url!
    }()
}

struct FeedbackView: View {
    var emailURL: URL = FeedbackContact.url
    @Environment(\.openURL) private var openURL
    @State private var status: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 6) {
                SectionEyebrow(text: "Feedback")
                Text("Help make Blink better.").font(.system(size: 27, weight: .semibold, design: .rounded))
                Text("Have an idea or found a problem?").font(.system(size: 13)).foregroundStyle(.secondary)
            }
            Card {
                VStack(alignment: .leading, spacing: 16) {
                    Text(FeedbackContact.address)
                        .font(.system(size: 19, weight: .medium, design: .rounded))
                        .textSelection(.enabled)
                    VStack(spacing: 10) {
                        Button { open(emailURL) } label: {
                            Label("Open email app", systemImage: "envelope").actionTarget(expands: true)
                        }.help("Uses your default email app")
                        Button { open(FeedbackContact.gmailURL) } label: {
                            Label("Open Gmail", systemImage: "arrow.up.right.square").actionTarget(expands: true)
                        }.help("Compose feedback in Gmail in your browser")
                        Button(action: copyAddress) {
                            Label("Copy email address", systemImage: "doc.on.doc").actionTarget(expands: true)
                        }
                    }.buttonStyle(.bordered).controlSize(.large).font(.system(size: 13))
                    Text("If your email app doesn’t open a draft, use Gmail or copy the address into your email service.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true).lineSpacing(3)
                    if let status {
                        Text(status).font(.system(size: 12)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            Text("Blink attaches no data and sends nothing automatically. You choose what to write and send.")
                .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(3)
            Spacer(minLength: 0)
        }
    }

    private func open(_ url: URL) {
        status = nil
        // macOS can deliver the completion on a LaunchServices background queue.
        openURL(url) { @Sendable accepted in
            Task { @MainActor in
                if !accepted { status = "Couldn’t open that option. You can copy the email address instead." }
            }
        }
    }

    private func copyAddress() {
        NSPasteboard.general.clearContents()
        let copied = NSPasteboard.general.setString(FeedbackContact.address, forType: .string)
        let message = copied ? "Email address copied." : "Couldn’t copy. Select the email address above to copy it."
        status = message
        NSAccessibility.post(element: NSApplication.shared, notification: .announcementRequested,
                             userInfo: [.announcement: message, .priority: NSAccessibilityPriorityLevel.medium.rawValue])
    }
}
