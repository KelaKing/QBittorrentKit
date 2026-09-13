# QBittorrentKit

A standalone Swift client for remotely managing downloads on a qBittorrent
server through its WebUI API. The package contains no UI and does not download
torrent contents to the Apple device.

## Requirements

- Swift 6.0 or later
- iOS 15 or later
- macOS 12 or later
- qBittorrent 4.6.7 through 5.2.x

The API contracts were checked against the official
[4.1–4.6 WebUI API](https://github.com/qbittorrent/qBittorrent/wiki/WebUI-API-(qBittorrent-4.1))
and [5.0+ WebUI API](https://github.com/qbittorrent/qBittorrent/wiki/WebUI-API-(qBittorrent-5.0))
documentation and the corresponding upstream sources. Automated tests do not
contact a live qBittorrent server. Versions outside the range above are not
currently claimed as supported.

## Installation

Add this repository as a Swift Package dependency and link the
`QBittorrentKit` library product.

```swift
.package(url: "https://github.com/KelaKing/QBittorrentKit.git", branch: "main")
```

## Security and sessions

Prefer an HTTPS server URL. `QBittorrentKit` does not provide an option to
disable TLS verification and never logs requests, passwords, cookies, or
magnet URLs. Each `QBittorrentClient` owns an isolated cookie jar; create a
separate client for every server/account. A reverse-proxy prefix in the base
URL, such as `https://host.example/qbt`, is preserved.

Username/password login is the only authentication method in this release.
API-key authentication introduced by newer servers is intentionally deferred.

```swift
import QBittorrentKit

let client = try QBittorrentClient(
    baseURL: URL(string: "https://nas.example/qbt")!
)
try await client.login(username: "alice", password: password)

let appVersion = try await client.applicationVersion()
let apiVersion = try await client.webAPIVersion()
```

## Common operations

### List torrents

```swift
let torrents = try await client.torrents(options: .init(
    filter: .downloading,
    category: "Linux",
    sort: .downloadSpeed,
    reverse: true,
    limit: 50
))
```

Unknown server torrent states are retained in `TorrentState.rawValue`.
Byte totals and limits use bytes; rates use bytes per second. qBittorrent
sentinels are returned unchanged rather than assigned new meanings.

### Add a magnet or torrent file

```swift
try await client.add(
    urls: ["magnet:?xt=urn:btih:…"],
    options: .init(
        savePath: "/downloads/linux",
        category: "Linux",
        tags: ["iso"],
        start: true
    )
)

let torrentBytes: Data = // data selected by the app
try await client.add(
    torrent: torrentBytes,
    filename: "download.torrent",
    options: .init(start: false)
)
```

URL additions use form encoding and file additions use multipart encoding.
Special characters, Unicode, magnets, and server filesystem paths are encoded
as request data rather than interpolated into URLs.

### Start and stop

```swift
try await client.stop(.hashes([torrent.hash]))
try await client.start(.all)
```

The client caches `app/webapiVersion` and maps these calls to `pause`/`resume`
on qBittorrent 4.6.x (Web API before 2.11.0), or `stop`/`start` on 5.x. The
same mapping is applied to `.stopped` and `.running` list filters.

### Delete explicitly

```swift
// Removes the qBittorrent task but keeps server files.
try await client.delete(.hashes([torrent.hash]), deleteFiles: false)

// Destructive: removes the task and deletes its files from the server.
try await client.delete(.hashes([torrent.hash]), deleteFiles: true)
```

There is no deletion overload with a default value: callers must make the
server-file behavior explicit. `.all` is also explicit and an empty hash list
is rejected.

## Incremental synchronization

Objects inside `MainData.torrents` are **patches**, not complete torrent
records. Missing properties mean “unchanged”; present `false`, `0`, and empty
strings are real updates. Use `MainDataSnapshot` to apply this safely:

```swift
var snapshot = MainDataSnapshot()

while !Task.isCancelled {
    let update = try await client.mainData(since: snapshot.rid)
    snapshot.apply(update)
    render(snapshot.torrents)
}
```

`MainDataSnapshot.apply` clears cached torrents, categories, tags, and server
state before applying a `full_update`. For partial updates it merges fields and
then applies `torrents_removed`, `categories_removed`, and `tags_removed`.
Consumers implementing their own store must follow the same reset/removal
rules and must not decode a `TorrentPatch` as a complete `Torrent`.

## Implemented API

| Area | Endpoints |
| --- | --- |
| App/auth | `auth/login`, `auth/logout`, `app/version`, `app/webapiVersion` |
| Sync | `sync/maindata` plus `MainDataSnapshot` accumulation |
| Torrent reads | `torrents/info`, `torrents/properties`, `torrents/files` |
| Addition | `torrents/add` for URL/magnet and `.torrent` bytes |
| Torrent actions | start/stop or pause/resume, delete, recheck, force start, file priority |
| Categories | list, create, remove, assign/clear |
| Tags | list, create, delete, assign, remove, remove all |
| Transfer | global info, global limits, alternate-speed mode |
| Torrent limits | get/set download and upload limits |

The 4.6.7 compatibility path uses Web API 2.9.x terminology. The 5.x path uses
Web API 2.11+ start/stop terminology and the `stopped` add option. Capability
selection is based on the Web API version, not the application version.

## Errors and concurrency

`QBittorrentError` distinguishes invalid requests, cancellation, `URLError`
network failures, authentication failure, non-success HTTP responses,
plain-text API failures, decoding failures, and unsupported capabilities.
Mutating requests are never retried automatically.

`QBittorrentClient` is an actor. A transport conforming to
`QBittorrentTransport` can be injected for deterministic tests. The default
`URLSessionTransport` uses an ephemeral session with URLSession cookie handling
disabled because the client maintains its own isolated cookie jar.

## Testing

```sh
swift build
swift test
```

Tests use stub transports and require no live server or credentials. For
optional integration testing, create a local test-only qBittorrent instance,
use HTTPS where possible, and pass credentials through the test process
environment. Never commit them.

## Deferred scope and limitations

- Search plugins and search jobs
- RSS feeds and rules
- Full application preference administration
- Tracker, peer, and Web Seed management
- Torrent creation and server filesystem browsing
- API-key authentication
- Live-server compatibility tests and automatic retries

The model set intentionally covers common fields for the initial app workflow;
unknown JSON fields are ignored by `Codable`. Additional version-dependent
fields can be added without changing transport behavior.
