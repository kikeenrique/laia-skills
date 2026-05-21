# AsyncHTTPClient support

> **Heads up: [AsyncHTTPClient](https://github.com/swift-server/async-http-client) is a separate, external package** maintained by the Swift Server Work Group — Replay does **not** bundle it. You'll already have it as a dependency if your code uses it; otherwise, skip this file and use the default `URLSession`-based `.replay(...)` trait.

`AsyncHTTPClient` is built on SwiftNIO, not Foundation's URL Loading System. That means `URLProtocol`-based interception — which powers the `@Test(.replay(…))` trait — **cannot** intercept its traffic. Replay provides an alternative: the `HTTPClientProtocol` abstraction, gated behind an opt-in SwiftPM package trait so projects that don't use AsyncHTTPClient aren't forced to pull in SwiftNIO.

## Enable the package trait

```swift
dependencies: [
    .package(
        url: "https://github.com/mattt/Replay.git",
        from: "0.4.0",
        traits: ["AsyncHTTPClient"]
    )
]
```

Note: this is a **SwiftPM package trait**, not a Swift Testing trait.

## Design your client against the protocol

```swift
import AsyncHTTPClient
import NIOCore

actor APIClient {
    let httpClient: any HTTPClientProtocol

    init(httpClient: any HTTPClientProtocol) {
        self.httpClient = httpClient
    }

    func fetchUser(id: Int) async throws -> User {
        let request = HTTPClientRequest(url: "https://api.example.com/users/\(id)")
        let response = try await httpClient.execute(request, timeout: .seconds(30))
        let body = try await response.body.collect(upTo: 1024 * 1024)
        return try JSONDecoder().decode(User.self, from: body)
    }
}
```

Both `HTTPClient` (production) and `ReplayHTTPClient` (tests) conform to `HTTPClientProtocol`. Inject one or the other.

## Using `ReplayHTTPClient` with stubs

```swift
@Test("fetch user from stub")
func fetchUser() async throws {
    let client = try await ReplayHTTPClient(
        stubs: [
            Stub(
                .get,
                "https://api.example.com/users/42",
                status: 200,
                headers: ["Content-Type": "application/json"],
                body: #"{"id":42,"name":"Alice"}"#
            )
        ]
    )
    let api = APIClient(httpClient: client)
    let user = try await api.fetchUser(id: 42)
    #expect(user.name == "Alice")
}
```

## Using `ReplayHTTPClient` with a HAR file

```swift
let client = try await ReplayHTTPClient(
    configuration: PlaybackConfiguration(
        source: .file(archiveURL),
        playbackMode: .strict,
        matchers: [.method, .path]
    )
)
```

## Why not use the trait?

The `@Test(.replay(…))` trait wires up `URLProtocol`, which only `URLSession` consults. `AsyncHTTPClient` ignores `URLProtocol`. Dependency injection through `HTTPClientProtocol` is the equivalent mechanism — wire `ReplayHTTPClient` into your client explicitly from the test.
