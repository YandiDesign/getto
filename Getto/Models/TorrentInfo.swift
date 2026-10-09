import Foundation

struct TorrentFileEntry: Identifiable, Codable, Hashable {
    var id: Int { index }
    var index: Int
    var path: String
    var length: Int64
    var selected: Bool = true
}

struct TorrentInfo: Codable {
    var infoHash: String?
    var name: String
    var totalLength: Int64
    var files: [TorrentFileEntry] = []
    var numSeeds: Int = 0
    var numPeers: Int = 0
    var downloadSpeed: Int64 = 0
    var uploadSpeed: Int64 = 0
    var progress: Double = 0
    var ratio: Double = 0
    var etaSeconds: Int64 = 0
}
