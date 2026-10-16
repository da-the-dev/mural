import SwiftUI
import WallpaperKit

/// A titled card that floats on a Liquid Glass surface.
struct GlassCard<Content: View>: View {
    var title: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let title {
                Text(title).font(.headline)
            }
            content
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
    }
}

/// A lock-screen-styled preview: a wallpaper wash, a live clock, and the user name.
struct LockPreview: View {
    var summary: String

    private var name: String { NSFullUserName() }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.10, green: 0.13, blue: 0.20),
                                 Color(red: 0.28, green: 0.34, blue: 0.52),
                                 Color(red: 0.62, green: 0.52, blue: 0.42)],
                        startPoint: .top, endPoint: .bottom)
                )
                .overlay(
                    // a soft aurora to hint at a live wallpaper
                    RadialGradient(colors: [.white.opacity(0.22), .clear],
                                   center: .init(x: 0.7, y: 0.25), startRadius: 4, endRadius: 260)
                )

            VStack(spacing: 8) {
                Text(Date(), style: .time)
                    .font(.system(size: 64, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Text(name)
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.white.opacity(0.9))
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                    Text(summary).lineLimit(1)
                }
                .font(.callout)
                .foregroundStyle(.white.opacity(0.85))
                .padding(.horizontal, 14).padding(.vertical, 8)
                .glassEffect(.regular, in: .capsule)
            }
            .padding(28)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 320)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: 18, y: 10)
    }
}

/// Small status / error banner.
struct StatusBanner: View {
    var text: String
    var isError: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(isError ? .orange : .green)
            Text(text).font(.callout)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .glassEffect(.regular, in: .rect(cornerRadius: 14))
    }
}
