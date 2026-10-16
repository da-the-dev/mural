import Foundation
import AVFoundation
import AppKit

/// Transcodes wallpaper videos to HEVC (.mov) — what the macOS wallpaper service
/// plays — and extracts a preview frame. Uses AVFoundation (no ffmpeg needed).
public enum VideoTranscoder {

    public static func transcodeToHEVC(_ source: URL, to destination: URL) async throws {
        let asset = AVURLAsset(url: source)
        guard let session = AVAssetExportSession(asset: asset,
                                                 presetName: AVAssetExportPresetHEVCHighestQuality) else {
            throw WallpaperError.encodeFailed("could not create an export session")
        }
        session.outputURL = destination
        session.outputFileType = .mov
        session.shouldOptimizeForNetworkUse = false

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            session.exportAsynchronously {
                switch session.status {
                case .completed:
                    continuation.resume()
                case .cancelled:
                    continuation.resume(throwing: WallpaperError.encodeFailed("cancelled"))
                default:
                    continuation.resume(throwing: session.error
                        ?? WallpaperError.encodeFailed("export status \(session.status.rawValue)"))
                }
            }
        }
    }

    public static func writePreview(of url: URL, to pngURL: URL) async throws {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 640, height: 640)
        let result = try await generator.image(at: .zero)
        let rep = NSBitmapImageRep(cgImage: result.image)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw WallpaperError.encodeFailed("could not encode preview")
        }
        try data.write(to: pngURL, options: .atomic)
    }
}
