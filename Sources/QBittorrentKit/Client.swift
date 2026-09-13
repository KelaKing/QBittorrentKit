import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public actor QBittorrentClient {
    public let baseURL: URL
    private let transport: any QBittorrentTransport
    private let decoder = JSONDecoder()
    private var cookies: [HTTPCookie] = []
    private var cachedWebAPIVersion: WebAPIVersion?

    public init(baseURL: URL, transport: any QBittorrentTransport = URLSessionTransport()) throws {
        guard let scheme = baseURL.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              baseURL.host != nil,
              baseURL.query == nil,
              baseURL.fragment == nil else {
            throw QBittorrentError.invalidBaseURL
        }
        self.baseURL = baseURL
        self.transport = transport
    }

    public func login(username: String, password: String) async throws {
        let response = try await send(
            path: "auth/login",
            method: "POST",
            form: [("username", username), ("password", password)]
        )
        guard response.text.isEmpty || response.text == "Ok." else {
            throw QBittorrentError.authenticationFailed(response.text.nilIfEmpty)
        }
    }

    public func logout() async throws {
        try await expectOK(path: "auth/logout")
        cookies.removeAll()
        cachedWebAPIVersion = nil
    }

    public func applicationVersion() async throws -> String {
        try await plainText(path: "app/version")
    }

    public func webAPIVersion(refresh: Bool = false) async throws -> WebAPIVersion {
        if !refresh, let cachedWebAPIVersion { return cachedWebAPIVersion }
        let version = WebAPIVersion(try await plainText(path: "app/webapiVersion"))
        cachedWebAPIVersion = version
        return version
    }

    public func mainData(since rid: Int = 0) async throws -> MainData {
        try await json(path: "sync/maindata", query: [.init(name: "rid", value: String(rid))])
    }

    public func torrents(options: TorrentListOptions = .init()) async throws -> [Torrent] {
        if let limit = options.limit, limit < 0 {
            throw QBittorrentError.invalidRequest("Torrent list limit cannot be negative.")
        }
        var query: [URLQueryItem] = []
        if let filter = options.filter {
            let value: String
            switch filter {
            case .stopped:
                value = try await webAPIVersion() >= Self.startStopVersion ? "stopped" : "paused"
            case .running:
                value = try await webAPIVersion() >= Self.startStopVersion ? "running" : "resumed"
            default:
                value = filter.rawValue
            }
            query.append(.init(name: "filter", value: value))
        }
        if let category = options.category { query.append(.init(name: "category", value: category)) }
        if let tag = options.tag { query.append(.init(name: "tag", value: tag)) }
        if let sort = options.sort { query.append(.init(name: "sort", value: sort.rawValue)) }
        if options.reverse { query.append(.init(name: "reverse", value: "true")) }
        if let limit = options.limit { query.append(.init(name: "limit", value: String(limit))) }
        if let offset = options.offset { query.append(.init(name: "offset", value: String(offset))) }
        if let hashes = options.hashes {
            guard !hashes.isEmpty else {
                throw QBittorrentError.invalidRequest("Torrent hash list cannot be empty.")
            }
            query.append(.init(name: "hashes", value: hashes.joined(separator: "|")))
        }
        return try await json(path: "torrents/info", query: query)
    }

    public func torrentProperties(hash: String) async throws -> TorrentProperties {
        try validateHash(hash)
        return try await json(path: "torrents/properties", query: [.init(name: "hash", value: hash)])
    }

    public func torrentFiles(hash: String, indexes: [Int]? = nil) async throws -> [TorrentFile] {
        try validateHash(hash)
        var query = [URLQueryItem(name: "hash", value: hash)]
        if let indexes {
            guard !indexes.isEmpty else {
                throw QBittorrentError.invalidRequest("File index list cannot be empty.")
            }
            query.append(.init(name: "indexes", value: indexes.map(String.init).joined(separator: "|")))
        }
        return try await json(path: "torrents/files", query: query)
    }

    public func add(urls: [String], options: AddTorrentOptions = .init()) async throws {
        guard !urls.isEmpty else { throw QBittorrentError.invalidRequest("At least one URL is required.") }
        var form = [("urls", urls.joined(separator: "\n"))]
        form.append(contentsOf: try await addOptionFields(options))
        try await expectOK(path: "torrents/add", form: form)
    }

    public func add(
        torrent data: Data,
        filename: String = "upload.torrent",
        options: AddTorrentOptions = .init()
    ) async throws {
        guard !data.isEmpty else { throw QBittorrentError.invalidRequest("Torrent data cannot be empty.") }
        guard !filename.isEmpty, filename.unicodeScalars.allSatisfy({ $0.value >= 0x20 && $0.value != 0x7F }) else {
            throw QBittorrentError.invalidRequest("Torrent filename cannot be empty or contain control characters.")
        }
        let boundary = "QBittorrentKit-\(UUID().uuidString)"
        let fields = try await addOptionFields(options)
        let body = MultipartFormData(boundary: boundary)
            .adding(fields: fields)
            .addingFile(name: "torrents", filename: filename, contentType: "application/x-bittorrent", data: data)
            .data
        let response = try await send(
            path: "torrents/add",
            method: "POST",
            headers: ["Content-Type": "multipart/form-data; boundary=\(boundary)"],
            body: body
        )
        try validateOK(response)
    }

    public func start(_ selection: TorrentSelection) async throws {
        let path = try await webAPIVersion() >= Self.startStopVersion ? "torrents/start" : "torrents/resume"
        try await expectOK(path: path, form: try selectionForm(selection))
    }

    public func stop(_ selection: TorrentSelection) async throws {
        let path = try await webAPIVersion() >= Self.startStopVersion ? "torrents/stop" : "torrents/pause"
        try await expectOK(path: path, form: try selectionForm(selection))
    }

    @available(*, deprecated, message: "Use start(_:); legacy servers are mapped to resume automatically.")
    public func resume(_ selection: TorrentSelection) async throws {
        try await expectOK(path: "torrents/resume", form: try selectionForm(selection))
    }

    @available(*, deprecated, message: "Use stop(_:); legacy servers are mapped to pause automatically.")
    public func pause(_ selection: TorrentSelection) async throws {
        try await expectOK(path: "torrents/pause", form: try selectionForm(selection))
    }

    public func delete(_ selection: TorrentSelection, deleteFiles: Bool) async throws {
        var form = try selectionForm(selection)
        form.append(("deleteFiles", formBool(deleteFiles)))
        try await expectOK(path: "torrents/delete", form: form)
    }

    public func recheck(_ selection: TorrentSelection) async throws {
        try await expectOK(path: "torrents/recheck", form: try selectionForm(selection))
    }

    public func setForceStart(_ enabled: Bool, for selection: TorrentSelection) async throws {
        var form = try selectionForm(selection)
        form.append(("value", formBool(enabled)))
        try await expectOK(path: "torrents/setForceStart", form: form)
    }

    public func setFilePriority(hash: String, indexes: [Int], priority: FilePriority) async throws {
        try validateHash(hash)
        guard !indexes.isEmpty, indexes.allSatisfy({ $0 >= 0 }) else {
            throw QBittorrentError.invalidRequest("File indexes must be non-empty and non-negative.")
        }
        try await expectOK(path: "torrents/filePrio", form: [
            ("hash", hash),
            ("id", indexes.map(String.init).joined(separator: "|")),
            ("priority", String(priority.rawValue))
        ])
    }

    public func categories() async throws -> [String: Category] {
        try await json(path: "torrents/categories")
    }

    public func createCategory(name: String, savePath: String = "") async throws {
        try await expectOK(path: "torrents/createCategory", form: [("category", name), ("savePath", savePath)])
    }

    public func deleteCategories(_ names: [String]) async throws {
        try await expectOK(path: "torrents/removeCategories", form: [("categories", try joined(names, label: "categories", separator: "\n"))])
    }

    public func setCategory(_ category: String, for selection: TorrentSelection) async throws {
        var form = try selectionForm(selection)
        form.append(("category", category))
        try await expectOK(path: "torrents/setCategory", form: form)
    }

    public func tags() async throws -> [String] {
        try await json(path: "torrents/tags")
    }

    public func createTags(_ tags: [String]) async throws {
        try await expectOK(path: "torrents/createTags", form: [("tags", try joined(tags, label: "tags"))])
    }

    public func deleteTags(_ tags: [String]) async throws {
        try await expectOK(path: "torrents/deleteTags", form: [("tags", try joined(tags, label: "tags"))])
    }

    public func addTags(_ tags: [String], to selection: TorrentSelection) async throws {
        var form = try selectionForm(selection)
        form.append(("tags", try joined(tags, label: "tags")))
        try await expectOK(path: "torrents/addTags", form: form)
    }

    public func removeTags(_ tags: [String], from selection: TorrentSelection) async throws {
        var form = try selectionForm(selection)
        form.append(("tags", try joined(tags, label: "tags")))
        try await expectOK(path: "torrents/removeTags", form: form)
    }

    public func removeAllTags(from selection: TorrentSelection) async throws {
        var form = try selectionForm(selection)
        form.append(("tags", ""))
        try await expectOK(path: "torrents/removeTags", form: form)
    }

    public func transferInfo() async throws -> TransferInfo {
        try await json(path: "transfer/info")
    }

    public func globalDownloadLimit() async throws -> Int64 {
        try await integer(path: "transfer/downloadLimit")
    }

    public func setGlobalDownloadLimit(_ bytesPerSecond: Int64) async throws {
        try validateRate(bytesPerSecond)
        try await expectOK(path: "transfer/setDownloadLimit", form: [("limit", String(bytesPerSecond))])
    }

    public func globalUploadLimit() async throws -> Int64 {
        try await integer(path: "transfer/uploadLimit")
    }

    public func setGlobalUploadLimit(_ bytesPerSecond: Int64) async throws {
        try validateRate(bytesPerSecond)
        try await expectOK(path: "transfer/setUploadLimit", form: [("limit", String(bytesPerSecond))])
    }

    public func alternativeSpeedLimitsEnabled() async throws -> Bool {
        try await integer(path: "transfer/speedLimitsMode") != 0
    }

    public func toggleAlternativeSpeedLimits() async throws {
        try await expectOK(path: "transfer/toggleSpeedLimitsMode")
    }

    public func torrentDownloadLimits(_ selection: TorrentSelection) async throws -> [String: Int64] {
        try await json(path: "torrents/downloadLimit", query: try selectionQuery(selection))
    }

    public func setTorrentDownloadLimit(_ bytesPerSecond: Int64, for selection: TorrentSelection) async throws {
        try validateRate(bytesPerSecond)
        var form = try selectionForm(selection)
        form.append(("limit", String(bytesPerSecond)))
        try await expectOK(path: "torrents/setDownloadLimit", form: form)
    }

    public func torrentUploadLimits(_ selection: TorrentSelection) async throws -> [String: Int64] {
        try await json(path: "torrents/uploadLimit", query: try selectionQuery(selection))
    }

    public func setTorrentUploadLimit(_ bytesPerSecond: Int64, for selection: TorrentSelection) async throws {
        try validateRate(bytesPerSecond)
        var form = try selectionForm(selection)
        form.append(("limit", String(bytesPerSecond)))
        try await expectOK(path: "torrents/setUploadLimit", form: form)
    }

    private static let startStopVersion = WebAPIVersion("2.11.0")

    private func addOptionFields(_ options: AddTorrentOptions) async throws -> [(String, String)] {
        var fields: [(String, String)] = []
        if let savePath = options.savePath { fields.append(("savepath", savePath)) }
        if let category = options.category { fields.append(("category", category)) }
        if !options.tags.isEmpty { fields.append(("tags", options.tags.joined(separator: ","))) }
        let version = try await webAPIVersion()
        fields.append((version >= Self.startStopVersion ? "stopped" : "paused", formBool(!options.start)))
        fields.append(("skip_checking", formBool(options.skipChecking)))
        fields.append(("sequentialDownload", formBool(options.sequentialDownload)))
        fields.append(("firstLastPiecePrio", formBool(options.firstLastPiecePriority)))
        if let limit = options.downloadLimit {
            try validateRate(limit)
            fields.append(("dlLimit", String(limit)))
        }
        if let limit = options.uploadLimit {
            try validateRate(limit)
            fields.append(("upLimit", String(limit)))
        }
        return fields
    }

    private func plainText(path: String) async throws -> String {
        try await send(path: path).text
    }

    private func integer(path: String) async throws -> Int64 {
        let text = try await plainText(path: path)
        guard let value = Int64(text) else {
            throw QBittorrentError.decoding("Expected an integer, received \(text.debugDescription).")
        }
        return value
    }

    private func json<T: Decodable>(path: String, query: [URLQueryItem] = []) async throws -> T {
        let response = try await send(path: path, query: query)
        do {
            return try decoder.decode(T.self, from: response.data)
        } catch {
            throw QBittorrentError.decoding(String(describing: error))
        }
    }

    private func expectOK(path: String, form: [(String, String)] = []) async throws {
        try validateOK(try await send(path: path, method: "POST", form: form))
    }

    private func validateOK(_ response: Response) throws {
        guard response.text.isEmpty || response.text == "Ok." else {
            throw QBittorrentError.apiFailure(response.text)
        }
    }

    private func send(
        path: String,
        method: String = "GET",
        query: [URLQueryItem] = [],
        form: [(String, String)]? = nil,
        headers: [String: String] = [:],
        body: Data? = nil
    ) async throws -> Response {
        var request = URLRequest(url: try endpointURL(path: path, query: query))
        request.httpMethod = method
        request.setValue("QBittorrentKit/0.1", forHTTPHeaderField: "User-Agent")
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        if let form {
            request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
            request.httpBody = FormEncoding.encode(form)
        } else {
            request.httpBody = body
        }
        let applicableCookies = cookies.filter { $0.matches(request.url!) }
        if !applicableCookies.isEmpty {
            for (name, value) in HTTPCookie.requestHeaderFields(with: applicableCookies) {
                request.setValue(value, forHTTPHeaderField: name)
            }
        }

        do {
            let (data, response) = try await transport.data(for: request)
            storeCookies(from: response)
            let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard (200..<300).contains(response.statusCode) else {
                if response.statusCode == 401 || response.statusCode == 403 {
                    throw QBittorrentError.authenticationFailed(text.nilIfEmpty)
                }
                throw QBittorrentError.http(statusCode: response.statusCode, message: text.nilIfEmpty)
            }
            return Response(data: data, text: text)
        } catch is CancellationError {
            throw QBittorrentError.cancelled
        } catch let error as URLError {
            if error.code == .cancelled { throw QBittorrentError.cancelled }
            throw QBittorrentError.network(error)
        } catch {
            throw error
        }
    }

    private func endpointURL(path: String, query: [URLQueryItem]) throws -> URL {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        let prefix = baseURL.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let suffix = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components?.path = "/" + [prefix, "api/v2", suffix].filter { !$0.isEmpty }.joined(separator: "/")
        components?.queryItems = query.isEmpty ? nil : query
        guard let url = components?.url else {
            throw QBittorrentError.invalidRequest("Could not construct endpoint URL.")
        }
        return url
    }

    private func storeCookies(from response: HTTPURLResponse) {
        guard let url = response.url else { return }
        let fields = response.allHeaderFields.reduce(into: [String: String]()) { result, item in
            if let name = item.key as? String, let value = item.value as? String { result[name] = value }
        }
        for cookie in HTTPCookie.cookies(withResponseHeaderFields: fields, for: url) {
            cookies.removeAll { $0.name == cookie.name && $0.domain == cookie.domain && $0.path == cookie.path }
            if cookie.expiresDate.map({ $0 > Date() }) ?? true { cookies.append(cookie) }
        }
        cookies.removeAll { $0.expiresDate.map { $0 <= Date() } ?? false }
    }

    private func selectionForm(_ selection: TorrentSelection) throws -> [(String, String)] {
        [("hashes", try selectionValue(selection))]
    }

    private func selectionQuery(_ selection: TorrentSelection) throws -> [URLQueryItem] {
        [.init(name: "hashes", value: try selectionValue(selection))]
    }

    private func selectionValue(_ selection: TorrentSelection) throws -> String {
        switch selection {
        case .all:
            return "all"
        case let .hashes(hashes):
            guard !hashes.isEmpty else {
                throw QBittorrentError.invalidRequest("Torrent selection must contain at least one hash.")
            }
            try hashes.forEach(validateHash)
            return hashes.joined(separator: "|")
        }
    }

    private func validateHash(_ hash: String) throws {
        let validLength = hash.count == 40 || hash.count == 64
        let isHex = hash.unicodeScalars.allSatisfy {
            (0x30...0x39).contains($0.value)
                || (0x41...0x46).contains($0.value)
                || (0x61...0x66).contains($0.value)
        }
        guard validLength, isHex else {
            throw QBittorrentError.invalidRequest("Torrent hashes must be complete 40- or 64-character hexadecimal values.")
        }
    }

    private func validateRate(_ value: Int64) throws {
        guard value >= 0 else {
            throw QBittorrentError.invalidRequest("Rate limits are bytes per second and cannot be negative; zero means unlimited.")
        }
    }

    private func joined(_ values: [String], label: String, separator: String = ",") throws -> String {
        guard !values.isEmpty, values.allSatisfy({ !$0.isEmpty }) else {
            throw QBittorrentError.invalidRequest("\(label.capitalized) must contain at least one non-empty value.")
        }
        return values.joined(separator: separator)
    }
}

private struct Response {
    let data: Data
    let text: String
}

private enum FormEncoding {
    static func encode(_ fields: [(String, String)]) -> Data {
        Data(fields.map { "\(escape($0.0))=\(escape($0.1))" }.joined(separator: "&").utf8)
    }

    private static func escape(_ value: String) -> String {
        value.utf8.map { byte -> String in
            switch byte {
            case 0x41...0x5A, 0x61...0x7A, 0x30...0x39, 0x2D, 0x2E, 0x5F, 0x7E:
                String(UnicodeScalar(byte))
            case 0x20:
                "+"
            default:
                String(format: "%%%02X", byte)
            }
        }.joined()
    }
}

private struct MultipartFormData {
    let boundary: String
    var data = Data()

    func adding(fields: [(String, String)]) -> Self {
        fields.reduce(self) { $0.addingField(name: $1.0, value: $1.1) }
    }

    func addingField(name: String, value: String) -> Self {
        var copy = self
        copy.data.append(Data("--\(boundary)\r\n".utf8))
        copy.data.append(Data("Content-Disposition: form-data; name=\"\(quoted(name))\"\r\n\r\n".utf8))
        copy.data.append(Data(value.utf8))
        copy.data.append(Data("\r\n".utf8))
        return copy
    }

    func addingFile(name: String, filename: String, contentType: String, data: Data) -> Self {
        var copy = self
        copy.data.append(Data("--\(boundary)\r\n".utf8))
        copy.data.append(Data("Content-Disposition: form-data; name=\"\(quoted(name))\"; filename=\"\(quoted(filename))\"\r\n".utf8))
        copy.data.append(Data("Content-Type: \(contentType)\r\n\r\n".utf8))
        copy.data.append(data)
        copy.data.append(Data("\r\n--\(boundary)--\r\n".utf8))
        return copy
    }

    private func quoted(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }
}

private extension HTTPCookie {
    func matches(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        let cookieDomain = domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        let domainMatches = host == cookieDomain || host.hasSuffix("." + cookieDomain)
        let requestPath = url.path.isEmpty ? "/" : url.path
        let pathMatches = requestPath == path
            || (requestPath.hasPrefix(path)
                && (path.hasSuffix("/") || requestPath.dropFirst(path.count).first == "/"))
        return domainMatches && pathMatches && (!isSecure || url.scheme?.lowercased() == "https")
    }
}

private func formBool(_ value: Bool) -> String {
    value ? "true" : "false"
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
