import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import QBittorrentKit

@Suite struct QBittorrentKitTests {
    @Test func loginEncodesCredentialsAndPreservesProxyPrefixAndCookie() async throws {
        let transport = StubTransport([
            .init(body: "Ok.", headers: ["Set-Cookie": "SID=secret; Path=/proxy; HttpOnly"]),
            .init(body: "v5.2.3")
        ])
        let client = try QBittorrentClient(baseURL: #require(URL(string: "https://example.test/proxy/")), transport: transport)

        try await client.login(username: "user+名", password: "p& =?")
        let version = try await client.applicationVersion()

        #expect(version == "v5.2.3")
        let requests = await transport.requests
        #expect(requests[0].url?.path == "/proxy/api/v2/auth/login")
        let loginBody = String(data: try #require(requests[0].httpBody), encoding: .utf8)
        let expectedCredentialBody = "username=user%2B%E5%90%8D&pass" + "word=p%26+%3D%3F"
        #expect(loginBody == expectedCredentialBody)
        #expect(requests[1].value(forHTTPHeaderField: "Cookie") == "SID=secret")
    }

    @Test func loginFailureIsAuthenticationError() async throws {
        let transport = StubTransport([.init(body: "Fails.")])
        let client = try QBittorrentClient(baseURL: #require(URL(string: "http://localhost:8080")), transport: transport)

        await #expect(throws: QBittorrentError.self) {
            try await client.login(username: "bad", password: "bad")
        }
    }

    @Test func cookieSessionsAreIsolatedPerClient() async throws {
        let firstTransport = StubTransport([
            .init(body: "Ok.", headers: ["Set-Cookie": "SID=first; Path=/"]),
            .init(body: "v5")
        ])
        let secondTransport = StubTransport([.init(body: "v5")])
        let url = try #require(URL(string: "https://example.test"))
        let first = try QBittorrentClient(baseURL: url, transport: firstTransport)
        let second = try QBittorrentClient(baseURL: url, transport: secondTransport)

        try await first.login(username: "one", password: "one")
        _ = try await first.applicationVersion()
        _ = try await second.applicationVersion()

        #expect((await firstTransport.requests)[1].value(forHTTPHeaderField: "Cookie") == "SID=first")
        #expect((await secondTransport.requests)[0].value(forHTTPHeaderField: "Cookie") == nil)
    }

    @Test func listBuildsEncodedTypedQueryAndDecodesUnknownState() async throws {
        let transport = StubTransport([.init(body: #"[{"hash":"abc","name":"测试","state":"futureState","progress":0}]"#)])
        let client = try QBittorrentClient(baseURL: #require(URL(string: "https://example.test/qbt")), transport: transport)

        let torrents = try await client.torrents(options: .init(
            filter: .stalledUploading,
            category: "影音 & TV",
            tag: "x/y",
            sort: .downloadSpeed,
            reverse: true,
            limit: 20,
            offset: 5,
            hashes: ["abc", "def"]
        ))

        #expect(torrents[0].state.rawValue == "futureState")
        let requests = await transport.requests
        let requestURL = try #require(requests[0].url)
        let components = try #require(URLComponents(url: requestURL, resolvingAgainstBaseURL: false))
        let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        #expect(items["filter"] == "stalled_uploading")
        #expect(items["category"] == "影音 & TV")
        #expect(items["tag"] == "x/y")
        #expect(items["hashes"] == "abc|def")
    }

    @Test func addMagnetUsesFormEncodingAndVersionSpecificStoppedFlag() async throws {
        let transport = StubTransport([.init(body: "2.11.2"), .init(body: "Ok.")])
        let client = try QBittorrentClient(baseURL: #require(URL(string: "https://example.test")), transport: transport)

        try await client.add(
            urls: ["magnet:?xt=urn:btih:abc&dn=测试 file"],
            options: .init(savePath: "/媒体/TV & Film", category: "影视", tags: ["new", "中文"], start: false)
        )

        let request = (await transport.requests)[1]
        let body = String(data: try #require(request.httpBody), encoding: .utf8) ?? ""
        #expect(body.contains("urls=magnet%3A%3Fxt%3Durn%3Abtih%3Aabc%26dn%3D%E6%B5%8B%E8%AF%95+file"))
        #expect(body.contains("savepath=%2F%E5%AA%92%E4%BD%93%2FTV+%26+Film"))
        #expect(body.contains("stopped=true"))
    }

    @Test func multipartUploadIncludesBinaryAndEscapedFilename() async throws {
        let transport = StubTransport([.init(body: "2.11.2"), .init(body: "Ok.")])
        let client = try QBittorrentClient(baseURL: #require(URL(string: "https://example.test")), transport: transport)
        let bytes = Data([0, 1, 2, 255])

        try await client.add(torrent: bytes, filename: "a\"b.torrent", options: .init(category: "测试"))

        let request = (await transport.requests)[1]
        #expect(request.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data; boundary=") == true)
        let body = try #require(request.httpBody)
        #expect(body.range(of: bytes) != nil)
        let text = String(decoding: body, as: UTF8.self)
        #expect(text.contains(#"filename="a\"b.torrent""#))
        #expect(text.contains("name=\"category\"\r\n\r\n测试"))
    }

    @Test func mutationReportsAPIFailureTextAtHTTP200() async throws {
        let transport = StubTransport([.init(body: "Fails.")])
        let client = try QBittorrentClient(baseURL: #require(URL(string: "https://example.test")), transport: transport)

        await #expect(throws: QBittorrentError.self) {
            try await client.delete(.hashes([String(repeating: "a", count: 40)]), deleteFiles: false)
        }
    }

    @Test func syncAccumulatorMergesExplicitValuesAndRemovalsThenResets() {
        var snapshot = MainDataSnapshot()
        snapshot.apply(.init(
            rid: 1,
            fullUpdate: true,
            torrents: [
                "a": .init(name: "Alpha", progress: 0.5, downloadSpeed: 12, category: "old", forceStart: true),
                "b": .init(name: "Beta")
            ],
            tags: ["one", "two"]
        ))
        snapshot.apply(.init(
            rid: 2,
            fullUpdate: false,
            torrents: ["a": .init(progress: 0, downloadSpeed: 0, category: "", forceStart: false)],
            torrentsRemoved: ["b"],
            tags: ["three"],
            tagsRemoved: ["one"]
        ))

        #expect(snapshot.torrents["a"]?.name == "Alpha")
        #expect(snapshot.torrents["a"]?.progress == 0)
        #expect(snapshot.torrents["a"]?.category == "")
        #expect(snapshot.torrents["a"]?.forceStart == false)
        #expect(snapshot.torrents["b"] == nil)
        #expect(snapshot.tags == ["two", "three"])

        snapshot.apply(.init(rid: 3, fullUpdate: true, torrents: ["c": .init(name: "Gamma")]))
        #expect(Set(snapshot.torrents.keys) == ["c"])
        #expect(snapshot.tags.isEmpty)
    }

    @Test func partialMainDataDefaultsFullUpdateToFalse() async throws {
        let transport = StubTransport([.init(body: #"{"rid":2,"torrents":{"a":{"dlspeed":0}}}"#)])
        let client = try QBittorrentClient(baseURL: #require(URL(string: "https://example.test")), transport: transport)

        let update = try await client.mainData(since: 1)

        #expect(update.fullUpdate == false)
        #expect(update.torrents?["a"]?.downloadSpeed == 0)
    }

    @Test func syncAccumulatorMergesPartialCategoriesAndServerState() async throws {
        let transport = StubTransport([
            .init(body: #"{"rid":1,"full_update":true,"categories":{"movies":{"name":"movies","savePath":"/old"}},"server_state":{"dl_info_speed":10,"up_info_speed":20,"connection_status":"connected"}}"#),
            .init(body: #"{"rid":2,"categories":{"movies":{"savePath":"/new"}},"server_state":{"dl_info_speed":0}}"#)
        ])
        let client = try QBittorrentClient(baseURL: #require(URL(string: "https://example.test")), transport: transport)
        var snapshot = MainDataSnapshot()

        snapshot.apply(try await client.mainData())
        snapshot.apply(try await client.mainData(since: snapshot.rid))

        #expect(snapshot.categories["movies"]?.name == "movies")
        #expect(snapshot.categories["movies"]?.savePath == "/new")
        #expect(snapshot.serverState?.downloadSpeed == 0)
        #expect(snapshot.serverState?.uploadSpeed == 20)
        #expect(snapshot.serverState?.connectionStatus == "connected")
    }

    @Test func startStopRoutesByCachedWebAPIVersion() async throws {
        let modernTransport = StubTransport([.init(body: "2.11.0"), .init(body: ""), .init(body: "")])
        let modern = try QBittorrentClient(baseURL: #require(URL(string: "https://example.test")), transport: modernTransport)
        try await modern.start(.all)
        try await modern.stop(.hashes([String(repeating: "a", count: 40)]))
        let modernRequests = await modernTransport.requests
        #expect(modernRequests.map(\.url?.path) == ["/api/v2/app/webapiVersion", "/api/v2/torrents/start", "/api/v2/torrents/stop"])

        let legacyTransport = StubTransport([.init(body: "2.9.3"), .init(body: ""), .init(body: "")])
        let legacy = try QBittorrentClient(baseURL: #require(URL(string: "https://example.test")), transport: legacyTransport)
        try await legacy.start(.all)
        try await legacy.stop(.all)
        let legacyRequests = await legacyTransport.requests
        #expect(legacyRequests.map(\.url?.path) == ["/api/v2/app/webapiVersion", "/api/v2/torrents/resume", "/api/v2/torrents/pause"])
    }

    @Test func stoppedFilterMapsToLegacyPausedFilter() async throws {
        let transport = StubTransport([.init(body: "2.9.3"), .init(body: "[]")])
        let client = try QBittorrentClient(baseURL: #require(URL(string: "https://example.test")), transport: transport)

        _ = try await client.torrents(options: .init(filter: .stopped))

        let requests = await transport.requests
        let url = try #require(requests[1].url)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(components.queryItems?.first(where: { $0.name == "filter" })?.value == "paused")
    }

    @Test func deleteAndRateLimitEncodeSafeExplicitValues() async throws {
        let transport = StubTransport([.init(body: ""), .init(body: ""), .init(body: "")])
        let client = try QBittorrentClient(baseURL: #require(URL(string: "https://example.test")), transport: transport)

        let firstHash = String(repeating: "a", count: 40)
        let secondHash = String(repeating: "b", count: 40)
        try await client.delete(.hashes([firstHash, secondHash]), deleteFiles: true)
        try await client.setGlobalDownloadLimit(0)
        try await client.setTorrentUploadLimit(1_024, for: .all)

        let requests = await transport.requests
        #expect(requests[0].bodyText == "hashes=\(firstHash)%7C\(secondHash)&deleteFiles=true")
        #expect(requests[1].bodyText == "limit=0")
        #expect(requests[2].bodyText == "hashes=all&limit=1024")
    }

    @Test func explicitHashSelectionRejectsReservedAllValue() async throws {
        let transport = StubTransport([])
        let client = try QBittorrentClient(baseURL: #require(URL(string: "https://example.test")), transport: transport)

        await #expect(throws: QBittorrentError.self) {
            try await client.delete(.hashes(["all"]), deleteFiles: true)
        }
        #expect((await transport.requests).isEmpty)
    }

    @Test func multipartFilenameRejectsHeaderInjection() async throws {
        let transport = StubTransport([])
        let client = try QBittorrentClient(baseURL: #require(URL(string: "https://example.test")), transport: transport)

        await #expect(throws: QBittorrentError.self) {
            try await client.add(torrent: Data([1]), filename: "safe.torrent\r\nX-Bad: yes")
        }
        #expect((await transport.requests).isEmpty)
    }

    @Test func webAPIVersionComparisonAndHashingNormalizeTrailingZeros() {
        let short = WebAPIVersion("2.11")
        let long = WebAPIVersion("2.11.0")

        #expect(short == long)
        #expect(Set([short, long]).count == 1)
        #expect(!(short < long))
        #expect(!(long < short))
    }

    @Test func plainTextJSONAndHTTPFailuresAreDistinguished() async throws {
        let transport = StubTransport([
            .init(body: "2048"),
            .init(body: #"{"dl_info_speed":42,"connection_status":"connected"}"#),
            .init(status: 500, body: "server exploded")
        ])
        let client = try QBittorrentClient(baseURL: #require(URL(string: "https://example.test")), transport: transport)

        #expect(try await client.globalDownloadLimit() == 2_048)
        #expect(try await client.transferInfo().downloadSpeed == 42)
        await #expect(throws: QBittorrentError.self) {
            _ = try await client.applicationVersion()
        }
    }
}

private actor StubTransport: QBittorrentTransport {
    struct Stub: Sendable {
        var status: Int
        var body: Data
        var headers: [String: String]

        init(status: Int = 200, body: String, headers: [String: String] = [:]) {
            self.status = status
            self.body = Data(body.utf8)
            self.headers = headers
        }
    }

    private var stubs: [Stub]
    private(set) var requests: [URLRequest] = []

    init(_ stubs: [Stub]) {
        self.stubs = stubs
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let stub = stubs.removeFirst()
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: stub.status,
            httpVersion: "HTTP/1.1",
            headerFields: stub.headers
        )!
        return (stub.body, response)
    }
}

private extension URLRequest {
    var bodyText: String {
        httpBody.flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }
}
