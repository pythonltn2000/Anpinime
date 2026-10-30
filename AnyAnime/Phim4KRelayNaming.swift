import Foundation

/// FFmpeg's HLS demuxer checks segment extensions before fetching them.
/// Keep opaque relay IDs, but retain known media suffixes for source 2.
enum Phim4KRelayNaming {
    static func suffix(for url: URL) -> String {
        if url.path.contains("/stream/hls") { return "m3u8" }
        let ext = url.pathExtension.lowercased()
        let allowed = ["m3u8", "ts", "m4s", "mp4", "m4a", "aac", "mp3", "ac3", "ec3", "vtt", "webvtt"]
        return allowed.contains(ext) ? ext : "bin"
    }
}
