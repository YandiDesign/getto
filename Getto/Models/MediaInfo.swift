import Foundation

struct MediaInfo: Codable, Identifiable {
    var id: String { videoId }
    var videoId: String
    var title: String
    var channel: String?
    var durationSeconds: Int64?
    var thumbnailURL: String?
    var extractor: String?
    var webpageURL: String?

    var durationString: String {
        guard let d = durationSeconds, d > 0 else { return "—" }
        let h = d / 3600, m = (d % 3600) / 60, s = d % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }
}

enum MediaQuality: String, Codable, CaseIterable {
    case best = "best"
    case q2160 = "2160p"
    case q1440 = "1440p"
    case q1080 = "1080p"
    case q720 = "720p"
    case q480 = "480p"
    case q360 = "360p"

    var ytDlpFormat: String {
        switch self {
        case .best: return "bv*+ba/b"
        case .q2160: return "bv*[height<=2160]+ba/b[height<=2160]/bv*+ba/b"
        case .q1440: return "bv*[height<=1440]+ba/b[height<=1440]/bv*+ba/b"
        case .q1080: return "bv*[height<=1080]+ba/b[height<=1080]/bv*+ba/b"
        case .q720: return "bv*[height<=720]+ba/b[height<=720]/bv*+ba/b"
        case .q480: return "bv*[height<=480]+ba/b[height<=480]/bv*+ba/b"
        case .q360: return "bv*[height<=360]+ba/b[height<=360]/bv*+ba/b"
        }
    }

    var label: String {
        switch self {
        case .best: return NSLocalizedString("quality.best", value: "Terbaik", comment: "")
        default: return rawValue
        }
    }

    /// Varian format yang mengutamakan H.264 (avc1) agar hasilnya bisa diputar
    /// dan di-Quick Look di Mac Intel. Fallback berlapis tetap memungkinkan
    /// resolusi tinggi bila H.264 tak tersedia (mis. 4K yang hanya VP9/AV1).
    var h264Format: String {
        switch self {
        case .best: return "bv*[vcodec^=avc]+ba/b[vcodec^=avc]/bv*+ba/b"
        case .q2160: return h264Capped("2160")
        case .q1440: return h264Capped("1440")
        case .q1080: return h264Capped("1080")
        case .q720: return h264Capped("720")
        case .q480: return h264Capped("480")
        case .q360: return h264Capped("360")
        }
    }

    private func h264Capped(_ h: String) -> String {
        "bv*[height<=\(h)][vcodec^=avc]+ba/b[height<=\(h)][vcodec^=avc]/bv*[height<=\(h)]+ba/b[height<=\(h)]/bv*+ba/b"
    }
}

enum MediaVideoCodec: String, Codable, CaseIterable {
    case auto
    case h264

    var label: String {
        switch self {
        case .auto: return NSLocalizedString("codec.auto", value: "Otomatis", comment: "")
        case .h264: return NSLocalizedString("codec.h264", value: "H.264 (kompatibel)", comment: "")
        }
    }
}

enum MediaVideoContainer: String, Codable, CaseIterable {
    case mp4, mkv, webm
}

enum MediaAudioFormat: String, Codable, CaseIterable {
    case mp3, m4a, opus, flac
}

struct MediaOptions: Codable {
    var quality: MediaQuality = .best
    var container: MediaVideoContainer = .mp4
    var videoCodec: MediaVideoCodec = .auto
    var audioOnly: Bool = false
    var audioFormat: MediaAudioFormat = .mp3
    var subtitleLangs: [String] = []
    var embedSubtitle: Bool = false
}
