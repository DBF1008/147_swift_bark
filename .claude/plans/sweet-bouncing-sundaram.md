# Server Address Normalization & Deduplication Fix

## Context

The Bark app allows users to add self-hosted server addresses via manual input, QR code scanning, and URL scheme deep links. Currently, addresses are stored verbatim with no normalization or deduplication. This causes:

1. **Same server stored as multiple records**: `https://example.com` and `https://example.com/` create two separate entries
2. **Home page title mismatch**: The title shows `currentServer.host` but the registration target uses the raw `server.address`, which can differ across duplicates
3. **Double-slash in API URLs**: Moya appends `/register` to a base URL that may already end in `/`, producing `https://example.com//register`

## Approach: Normalize at Construction Time

Normalize `server.address` inside `Server.init()` and `Server.init(from:)` rather than changing `address` from `let` to `var`. This ensures:
- `let` immutability is preserved (no Codable migration risk)
- Every code path that creates a Server automatically normalizes — no caller can forget
- Persisted data migrates transparently when servers are decoded from UserDefaults on app launch

## Changes

### 1. Add `normalizedServerAddress()` pure function — `Common/String+Extension.swift`

Add a new `String` extension method:
```swift
func normalizedServerAddress() -> String
```

Normalization rules:
- Trim leading/trailing whitespace and newlines
- If no scheme present, prepend `https://`
- Parse via `URLComponents`
- Lowercase `scheme` and `host`
- Remove trailing `/` from `path` (and collapse empty path to `""`)
- Remove default ports (`:80` for http, `:443` for https)
- Return `url.string` (the reassembled canonical form)
- If parsing fails entirely, return the trimmed original string as a fallback

### 2. Apply normalization in `Server` init — `Common/ServerManager.swift`

**In `Server.init(address:key:state:)`** (line 26):
```swift
self.address = address.normalizedServerAddress()
```

**In `Server.init(from decoder:)`** (line 44):
```swift
address = try container.decode(String.self, forKey: .address).normalizedServerAddress()
```

This handles both new server creation and transparent migration of persisted data.

**In `ServerManager.init()`**, after loading servers from UserDefaults, call `saveServers()` once to persist the migrated (normalized) addresses back:
```swift
// After self.servers = servers (line 55), add:
self.saveServers()  // persist normalized addresses
```

### 3. Add deduplication in `addServer()` — `Common/ServerManager.swift`

Add a result enum:
```swift
enum AddServerResult {
    case added(Server)
    case alreadyExists(Server)
}
```

Change `addServer` to check for duplicates by normalized address:
```swift
@discardableResult
func addServer(server: Server) -> AddServerResult {
    if let existing = servers.first(where: { $0.address == server.address }) {
        return .alreadyExists(existing)
    }
    self.servers.append(server)
    saveServers()
    return .added(server)
}
```

Since `address` is already normalized by `Server.init`, a simple `==` comparison on the address field is sufficient for deduplication.

### 4. Update callers to handle dedup result

**`Controller/NewServerViewModel.swift`** (line 78-81):
```swift
// Before:
let server = Server(address: strongSelf.url, key: "")
ServerManager.shared.addServer(server: server)
ServerManager.shared.setCurrentServer(serverId: server.id)

// After:
let server = Server(address: strongSelf.url, key: "")
let result = ServerManager.shared.addServer(server: server)
let activeServer: Server
switch result {
case .added(let newServer):
    activeServer = newServer
case .alreadyExists(let existingServer):
    activeServer = existingServer
}
ServerManager.shared.setCurrentServer(serverId: activeServer.id)
ServerManager.shared.syncAllServers()
strongSelf.pop.accept(activeServer.host)
```

**`Bark/AppDelegate.swift`** (line 204-207) — URL scheme handler:
```swift
// Before:
let server = Server(address: serverAddress.absoluteString, key: "")
ServerManager.shared.addServer(server: server)
ServerManager.shared.setCurrentServer(serverId: server.id)

// After:
let server = Server(address: serverAddress.absoluteString, key: "")
let result = ServerManager.shared.addServer(server: server)
let activeServer: Server
switch result {
case .added(let newServer):
    activeServer = newServer
case .alreadyExists(let existingServer):
    activeServer = existingServer
}
ServerManager.shared.setCurrentServer(serverId: activeServer.id)
```

**`ServerManager.init()` legacy migration** (line 71) — `@discardableResult` means no change needed here; the legacy migration path can safely ignore the return value.

### 5. No Moya-layer changes needed

Moya constructs URLs as `baseURL.appendingPathComponent(path)`. After normalization strips trailing slashes from stored addresses, the double-slash problem is resolved automatically:
- Before: `https://example.com/` + `/register` → `https://example.com//register`
- After: `https://example.com` + `/register` → `https://example.com/register`

### 6. Add regression tests — `BarkTests/ServerManagerTests.swift`

Create a new test file with the following test cases:

**Normalization tests** (`testNormalizedServerAddress`):
- Trailing slash stripped: `"https://example.com/"` → `"https://example.com"`
- Multiple trailing slashes: `"https://example.com///"` → `"https://example.com"`
- Lowercase host: `"https://EXAMPLE.COM"` → `"https://example.com"`
- Lowercase scheme: `"HTTP://example.com"` → `"http://example.com"`
- No scheme defaults to https: `"example.com"` → `"https://example.com"`
- Whitespace trimmed: `"  https://example.com  "` → `"https://example.com"`
- Default port removed: `"https://example.com:443"` → `"https://example.com"`
- Non-default port kept: `"https://example.com:8080"` → `"https://example.com:8080"`
- Path preserved: `"https://example.com/path"` → `"https://example.com/path"`
- Path trailing slash stripped: `"https://example.com/path/"` → `"https://example.com/path"`

**Deduplication tests** (`testAddServerDeduplication`):
- Adding same address twice returns `.alreadyExists` the second time
- Adding with trailing slash deduplicates against one without
- Server list count stays at 1 after duplicate add attempts
- Returned server from `.alreadyExists` is the original server object

**Integration test** (`testHomeTitleMatchesRegistration`):
- Create two servers with equivalent but differently-formatted addresses
- Verify they normalize to the same address and `host` property matches

## Files Modified

| File | Change |
|------|--------|
| `Common/String+Extension.swift` | Add `normalizedServerAddress()` method |
| `Common/ServerManager.swift` | Normalize in `Server.init`/`init(from:)`; add `AddServerResult` enum; dedup in `addServer()`; migrate on init |
| `Controller/NewServerViewModel.swift` | Handle `AddServerResult` for correct switch + display |
| `Bark/AppDelegate.swift` | Handle `AddServerResult` in URL scheme handler |
| `BarkTests/ServerManagerTests.swift` | **New file** — normalization + dedup regression tests |

## Verification

1. Build the project: `xcodebuild -workspace Bark.xcworkspace -scheme Bark build`
2. Run tests: `xcodebuild test -workspace Bark.xcworkspace -scheme Bark`
3. Manual smoke: add `https://example.com` manually, then scan a QR code for `https://example.com/` — should show only one entry in server list, home page title matches
