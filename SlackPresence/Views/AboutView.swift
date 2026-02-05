import SwiftUI

struct AboutView: View {
    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            // App Icon with shadow
            Image(systemName: "message.badge.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.blue)
                .shadow(color: .blue.opacity(0.3), radius: 8, y: 2)

            // Title
            Text("Slack Presence")
                .font(.title)
                .fontWeight(.bold)

            // Tagline
            Text("Automate your Slack availability")
                .font(.subheadline)
                .foregroundColor(.secondary)

            // Version
            Text("Version 1.1")
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.7))

            Divider()
                .padding(.horizontal, 40)

            // Author
            VStack(spacing: 8) {
                Text("Created by")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("Tomer Brami")
                    .font(.headline)
            }

            // GitHub Link
            Link(destination: URL(string: "https://github.com/tomerbr1")!) {
                HStack(spacing: 6) {
                    Image(systemName: "link")
                        .font(.caption)
                    Text("github.com/tomerbr1")
                        .font(.callout)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color(.controlBackgroundColor))
                .cornerRadius(8)
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .padding(32)
        .frame(width: 300, height: 340)
    }
}

#Preview {
    AboutView()
}
