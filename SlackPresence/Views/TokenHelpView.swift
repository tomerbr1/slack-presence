import SwiftUI

// MARK: - Instruction Item

enum InstructionItem {
    case text(String)
    case textWithLink(prefix: String, linkText: String, url: String, suffix: String)
}

// MARK: - Step Card

struct StepCard: View {
    let stepNumber: Int
    let title: String
    let instructions: [InstructionItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("\(stepNumber)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .frame(width: 22, height: 22)
                    .background(Color.blue)
                    .clipShape(Circle())

                Text(title)
                    .font(.headline)
            }

            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(instructions.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(index + 1).")
                            .font(.callout)
                            .foregroundColor(.secondary)
                            .frame(width: 18, alignment: .trailing)

                        instructionView(for: item)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.controlBackgroundColor))
        .cornerRadius(10)
    }

    @ViewBuilder
    private func instructionView(for item: InstructionItem) -> some View {
        switch item {
        case .text(let text):
            Text(text)
                .font(.callout)
        case .textWithLink(let prefix, let linkText, let url, let suffix):
            HStack(spacing: 0) {
                Text(prefix)
                    .font(.callout)
                if let linkURL = URL(string: url) {
                    Link(linkText, destination: linkURL)
                        .font(.callout)
                }
                Text(suffix)
                    .font(.callout)
            }
        }
    }
}

// MARK: - Token Help View

struct TokenHelpView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(spacing: 10) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.blue)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Slack Credentials Setup")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("Follow these steps to connect your Slack account")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.bottom, 4)

            // Step 1: Open Slack Web
            StepCard(
                stepNumber: 1,
                title: "Open Slack Web",
                instructions: [
                    .textWithLink(prefix: "Open ", linkText: "app.slack.com", url: "https://app.slack.com", suffix: " in your browser"),
                    .text("Log into your workspace"),
                    .text("Open DevTools (Cmd+Option+I)")
                ]
            )

            // Step 2: Get API Token
            StepCard(
                stepNumber: 2,
                title: "Get API Token (xoxc-)",
                instructions: [
                    .text("Go to Application tab in DevTools"),
                    .textWithLink(prefix: "Local Storage → ", linkText: "app.slack.com", url: "https://app.slack.com", suffix: ""),
                    .text("Find the key 'localConfig_v2'"),
                    .text("Expand: teams → [your-team-id] → token"),
                    .text("Copy value starting with xoxc-...")
                ]
            )

            // Step 3: Get Session Cookie
            StepCard(
                stepNumber: 3,
                title: "Get Session Cookie (d)",
                instructions: [
                    .text("In DevTools, go to Application tab"),
                    .text("Under Storage → Cookies → https://app.slack.com"),
                    .text("Find the cookie named 'd'"),
                    .text("Double-click its Value to select, then copy")
                ]
            )

            // Token Refresh Warning
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title3)
                    .foregroundColor(.orange)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Token Refresh")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text("Tokens expire when you log out of Slack web. The app will notify you if credentials stop working — just repeat these steps.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.1))
            .cornerRadius(8)

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 20)
        .frame(width: 460, height: 600)
        .textSelection(.enabled)
    }
}

#Preview {
    TokenHelpView()
}
