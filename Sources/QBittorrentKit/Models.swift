import Foundation

public struct WebAPIVersion: RawRepresentable, Codable, Sendable, Hashable, Comparable, CustomStringConvertible {
    public let rawValue: String
    private let components: [Int]

    public init(rawValue: String) {
        self.rawValue = rawValue
        self.components = rawValue.split(separator: ".").map { Int($0) ?? 0 }
    }

    public init(_ rawValue: String) {
        self.init(rawValue: rawValue)
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        let count = max(lhs.normalizedComponents.count, rhs.normalizedComponents.count)
        for index in 0..<count {
            let left = index < lhs.normalizedComponents.count ? lhs.normalizedComponents[index] : 0
            let right = index < rhs.normalizedComponents.count ? rhs.normalizedComponents[index] : 0
            if left != right { return left < right }
        }
        return false
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.normalizedComponents == rhs.normalizedComponents
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(normalizedComponents)
    }

    public var description: String { rawValue }

    private var normalizedComponents: [Int] {
        var result = components
        while result.last == 0 { result.removeLast() }
        return result
    }

    public init(from decoder: Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct TorrentState: RawRepresentable, Codable, Sendable, Hashable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static let downloading = Self(rawValue: "downloading")
    public static let uploading = Self(rawValue: "uploading")
    public static let stoppedDownload = Self(rawValue: "stoppedDL")
    public static let stoppedUpload = Self(rawValue: "stoppedUP")
    public static let pausedDownload = Self(rawValue: "pausedDL")
    public static let pausedUpload = Self(rawValue: "pausedUP")
    public static let error = Self(rawValue: "error")

    public init(from decoder: Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public enum TorrentFilter: String, Codable, Sendable {
    case all, downloading, seeding, completed, running, stopped, active, inactive, stalled
    case stalledUploading = "stalled_uploading"
    case stalledDownloading = "stalled_downloading"
    case errored
}

public enum TorrentSort: String, Codable, Sendable {
    case hash, name, size, progress, priority, seeds, peers, ratio, eta, state, category
    case downloadSpeed = "dlspeed"
    case uploadSpeed = "upspeed"
    case addedOn = "added_on"
    case completionOn = "completion_on"
    case lastActivity = "last_activity"
}

public struct TorrentListOptions: Sendable, Equatable {
    public var filter: TorrentFilter?
    public var category: String?
    public var tag: String?
    public var sort: TorrentSort?
    public var reverse: Bool
    public var limit: Int?
    public var offset: Int?
    public var hashes: [String]?

    public init(
        filter: TorrentFilter? = nil,
        category: String? = nil,
        tag: String? = nil,
        sort: TorrentSort? = nil,
        reverse: Bool = false,
        limit: Int? = nil,
        offset: Int? = nil,
        hashes: [String]? = nil
    ) {
        self.filter = filter
        self.category = category
        self.tag = tag
        self.sort = sort
        self.reverse = reverse
        self.limit = limit
        self.offset = offset
        self.hashes = hashes
    }
}

public struct Torrent: Codable, Sendable, Equatable {
    public let hash: String
    public let name: String
    public let state: TorrentState
    public let size: Int64?
    public let totalSize: Int64?
    public let progress: Double?
    public let downloadSpeed: Int64?
    public let uploadSpeed: Int64?
    public let downloaded: Int64?
    public let uploaded: Int64?
    public let eta: Int64?
    public let ratio: Double?
    public let category: String?
    public let tags: String?
    public let savePath: String?
    public let addedOn: Int64?
    public let completionOn: Int64?
    public let forceStart: Bool?

    enum CodingKeys: String, CodingKey {
        case hash, name, state, size, progress, downloaded, uploaded, eta, ratio, category, tags
        case totalSize = "total_size"
        case downloadSpeed = "dlspeed"
        case uploadSpeed = "upspeed"
        case savePath = "save_path"
        case addedOn = "added_on"
        case completionOn = "completion_on"
        case forceStart = "force_start"
    }
}

public struct TorrentPatch: Codable, Sendable, Equatable {
    public var name: String?
    public var state: TorrentState?
    public var size: Int64?
    public var totalSize: Int64?
    public var progress: Double?
    public var downloadSpeed: Int64?
    public var uploadSpeed: Int64?
    public var downloaded: Int64?
    public var uploaded: Int64?
    public var eta: Int64?
    public var ratio: Double?
    public var category: String?
    public var tags: String?
    public var savePath: String?
    public var forceStart: Bool?

    public init(
        name: String? = nil,
        state: TorrentState? = nil,
        size: Int64? = nil,
        totalSize: Int64? = nil,
        progress: Double? = nil,
        downloadSpeed: Int64? = nil,
        uploadSpeed: Int64? = nil,
        downloaded: Int64? = nil,
        uploaded: Int64? = nil,
        eta: Int64? = nil,
        ratio: Double? = nil,
        category: String? = nil,
        tags: String? = nil,
        savePath: String? = nil,
        forceStart: Bool? = nil
    ) {
        self.name = name
        self.state = state
        self.size = size
        self.totalSize = totalSize
        self.progress = progress
        self.downloadSpeed = downloadSpeed
        self.uploadSpeed = uploadSpeed
        self.downloaded = downloaded
        self.uploaded = uploaded
        self.eta = eta
        self.ratio = ratio
        self.category = category
        self.tags = tags
        self.savePath = savePath
        self.forceStart = forceStart
    }

    enum CodingKeys: String, CodingKey {
        case name, state, size, progress, downloaded, uploaded, eta, ratio, category, tags
        case totalSize = "total_size"
        case downloadSpeed = "dlspeed"
        case uploadSpeed = "upspeed"
        case savePath = "save_path"
        case forceStart = "force_start"
    }
}

public struct TorrentSnapshot: Sendable, Equatable {
    public let hash: String
    public var name: String?
    public var state: TorrentState?
    public var size: Int64?
    public var totalSize: Int64?
    public var progress: Double?
    public var downloadSpeed: Int64?
    public var uploadSpeed: Int64?
    public var downloaded: Int64?
    public var uploaded: Int64?
    public var eta: Int64?
    public var ratio: Double?
    public var category: String?
    public var tags: String?
    public var savePath: String?
    public var forceStart: Bool?

    public init(hash: String, patch: TorrentPatch) {
        self.hash = hash
        apply(patch)
    }

    public mutating func apply(_ patch: TorrentPatch) {
        if let value = patch.name { name = value }
        if let value = patch.state { state = value }
        if let value = patch.size { size = value }
        if let value = patch.totalSize { totalSize = value }
        if let value = patch.progress { progress = value }
        if let value = patch.downloadSpeed { downloadSpeed = value }
        if let value = patch.uploadSpeed { uploadSpeed = value }
        if let value = patch.downloaded { downloaded = value }
        if let value = patch.uploaded { uploaded = value }
        if let value = patch.eta { eta = value }
        if let value = patch.ratio { ratio = value }
        if let value = patch.category { category = value }
        if let value = patch.tags { tags = value }
        if let value = patch.savePath { savePath = value }
        if let value = patch.forceStart { forceStart = value }
    }
}

public struct TorrentProperties: Codable, Sendable, Equatable {
    public let savePath: String?
    public let creationDate: Int64?
    public let pieceSize: Int64?
    public let comment: String?
    public let totalWasted: Int64?
    public let totalUploaded: Int64?
    public let totalDownloaded: Int64?
    public let uploadLimit: Int64?
    public let downloadLimit: Int64?

    enum CodingKeys: String, CodingKey {
        case comment
        case savePath = "save_path"
        case creationDate = "creation_date"
        case pieceSize = "piece_size"
        case totalWasted = "total_wasted"
        case totalUploaded = "total_uploaded"
        case totalDownloaded = "total_downloaded"
        case uploadLimit = "up_limit"
        case downloadLimit = "dl_limit"
    }
}

public struct TorrentFile: Codable, Sendable, Equatable {
    public let index: Int
    public let name: String
    public let size: Int64
    public let progress: Double
    public let priority: Int
    public let isSeed: Bool?
    public let pieceRange: [Int]?
    public let availability: Double?

    enum CodingKeys: String, CodingKey {
        case index, name, size, progress, priority, availability
        case isSeed = "is_seed"
        case pieceRange = "piece_range"
    }
}

public struct Category: Codable, Sendable, Equatable {
    public let name: String
    public let savePath: String

    enum CodingKeys: String, CodingKey {
        case name
        case savePath = "savePath"
    }
}

public struct TransferInfo: Codable, Sendable, Equatable {
    public let downloadSpeed: Int64?
    public let uploadSpeed: Int64?
    public let downloaded: Int64?
    public let uploaded: Int64?
    public let downloadRateLimit: Int64?
    public let uploadRateLimit: Int64?
    public let connectionStatus: String?

    enum CodingKeys: String, CodingKey {
        case downloadSpeed = "dl_info_speed"
        case uploadSpeed = "up_info_speed"
        case downloaded = "dl_info_data"
        case uploaded = "up_info_data"
        case downloadRateLimit = "dl_rate_limit"
        case uploadRateLimit = "up_rate_limit"
        case connectionStatus = "connection_status"
    }
}

public struct MainData: Codable, Sendable, Equatable {
    public let rid: Int
    public let fullUpdate: Bool
    public let torrents: [String: TorrentPatch]?
    public let torrentsRemoved: [String]?
    public let categories: [String: Category]?
    public let categoriesRemoved: [String]?
    public let tags: [String]?
    public let tagsRemoved: [String]?
    public let serverState: TransferInfo?

    public init(
        rid: Int,
        fullUpdate: Bool,
        torrents: [String: TorrentPatch]? = nil,
        torrentsRemoved: [String]? = nil,
        categories: [String: Category]? = nil,
        categoriesRemoved: [String]? = nil,
        tags: [String]? = nil,
        tagsRemoved: [String]? = nil,
        serverState: TransferInfo? = nil
    ) {
        self.rid = rid
        self.fullUpdate = fullUpdate
        self.torrents = torrents
        self.torrentsRemoved = torrentsRemoved
        self.categories = categories
        self.categoriesRemoved = categoriesRemoved
        self.tags = tags
        self.tagsRemoved = tagsRemoved
        self.serverState = serverState
    }

    enum CodingKeys: String, CodingKey {
        case rid, torrents, categories, tags
        case fullUpdate = "full_update"
        case torrentsRemoved = "torrents_removed"
        case categoriesRemoved = "categories_removed"
        case tagsRemoved = "tags_removed"
        case serverState = "server_state"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        rid = try container.decode(Int.self, forKey: .rid)
        fullUpdate = try container.decodeIfPresent(Bool.self, forKey: .fullUpdate) ?? false
        torrents = try container.decodeIfPresent([String: TorrentPatch].self, forKey: .torrents)
        torrentsRemoved = try container.decodeIfPresent([String].self, forKey: .torrentsRemoved)
        categories = try container.decodeIfPresent([String: Category].self, forKey: .categories)
        categoriesRemoved = try container.decodeIfPresent([String].self, forKey: .categoriesRemoved)
        tags = try container.decodeIfPresent([String].self, forKey: .tags)
        tagsRemoved = try container.decodeIfPresent([String].self, forKey: .tagsRemoved)
        serverState = try container.decodeIfPresent(TransferInfo.self, forKey: .serverState)
    }
}

public struct MainDataSnapshot: Sendable, Equatable {
    public private(set) var rid = 0
    public private(set) var torrents: [String: TorrentSnapshot] = [:]
    public private(set) var categories: [String: Category] = [:]
    public private(set) var tags: Set<String> = []
    public private(set) var serverState: TransferInfo?

    public init() {}

    public mutating func apply(_ update: MainData) {
        if update.fullUpdate {
            torrents.removeAll(keepingCapacity: true)
            categories.removeAll(keepingCapacity: true)
            tags.removeAll(keepingCapacity: true)
            serverState = nil
        }
        for (hash, patch) in update.torrents ?? [:] {
            if var existing = torrents[hash] {
                existing.apply(patch)
                torrents[hash] = existing
            } else {
                torrents[hash] = TorrentSnapshot(hash: hash, patch: patch)
            }
        }
        for hash in update.torrentsRemoved ?? [] { torrents.removeValue(forKey: hash) }
        for (name, category) in update.categories ?? [:] { categories[name] = category }
        for name in update.categoriesRemoved ?? [] { categories.removeValue(forKey: name) }
        if let newTags = update.tags {
            if update.fullUpdate { tags = Set(newTags) } else { tags.formUnion(newTags) }
        }
        tags.subtract(update.tagsRemoved ?? [])
        if let state = update.serverState { serverState = state }
        rid = update.rid
    }
}

public enum TorrentSelection: Sendable, Equatable {
    case hashes([String])
    case all
}

public struct AddTorrentOptions: Sendable, Equatable {
    public var savePath: String?
    public var category: String?
    public var tags: [String]
    public var start: Bool
    public var skipChecking: Bool
    public var sequentialDownload: Bool
    public var firstLastPiecePriority: Bool
    public var downloadLimit: Int64?
    public var uploadLimit: Int64?

    public init(
        savePath: String? = nil,
        category: String? = nil,
        tags: [String] = [],
        start: Bool = true,
        skipChecking: Bool = false,
        sequentialDownload: Bool = false,
        firstLastPiecePriority: Bool = false,
        downloadLimit: Int64? = nil,
        uploadLimit: Int64? = nil
    ) {
        self.savePath = savePath
        self.category = category
        self.tags = tags
        self.start = start
        self.skipChecking = skipChecking
        self.sequentialDownload = sequentialDownload
        self.firstLastPiecePriority = firstLastPiecePriority
        self.downloadLimit = downloadLimit
        self.uploadLimit = uploadLimit
    }
}

public enum FilePriority: Int, Sendable {
    case doNotDownload = 0
    case normal = 1
    case high = 6
    case maximum = 7
}
