// App Store Connect's API for TestFlight builds, as the nightly workflow (.github/workflows/nightly.yml)
// and `Scripts/release-ios.sh --whats-new` use it (docs/release-checklist.md, "Nightlies"): wait for an
// uploaded build to be processed, give it What to Test, add it to TestFlight's groups, and submit it
// for Beta App Review when it goes to the public beta group. Foundation and CryptoKit only.
//
//   swiftc -O -o .build/asc/asc Scripts/asc.swift     (or run it as a script: swift Scripts/asc.swift …)
//   asc groups      --key-file F --key-id ID --issuer ID
//       lists the app's TestFlight groups: internal or external, automatic distribution, public link.
//       Reads only.
//   asc build-state --key-file F --key-id ID --issuer ID --version 0.6.0 --build 983
//       prints one word on stdout: missing (App Store Connect lists no such build yet), PROCESSING,
//       VALID, FAILED or INVALID. Reads only.
//   asc whats-new   --key-file F --key-id ID --issuer ID --version 0.6.0 --build 983 --whats-new FILE
//       waits for the build to be processed, then gives it FILE as What to Test (English, U.S.).
//   asc distribute  --key-file F --key-id ID --issuer ID --version 0.6.0 --build 983 --whats-new FILE
//                   [--public-beta [--public-beta-group NAME]]
//       the same, then the build goes to every internal group, and with --public-beta to the public
//       beta group too, and to Beta App Review when TestFlight asks for that.
//
// Options for all four:
//   --bundle-id ID        the app, by default me.saffer.sill
//   --wait-minutes N      how long to wait for processing (default 90; App Store Connect usually takes
//                         5 to 40 minutes)
//   --poll-seconds N      how often to look meanwhile (default 60)
//   --retry-seconds N     the first wait before trying a request again after a 429, a 5xx or no answer
//                         (default 5; then 3 and 6 times that; tests give 0)
//   --api-base URL        https://api.appstoreconnect.apple.com, the default, or a stand-in on this Mac
//                         for tests (http or https on 127.0.0.1, localhost or [::1]): the token goes to
//                         no other host, and a next-page link to another host is not followed.
//
// The groups, in `distribute`:
// - Every internal group (App Store Connect users only, no review) gets the build. One with automatic
//   distribution ("access to all builds") gets every processed build by itself and is left alone.
// - The public beta group is the external group with the public link on (or the one named with
//   --public-beta-group). It gets the build only with --public-beta, which is refused unless the
//   environment also says SILL_NIGHTLY_PUBLIC_BETA=true: the nightly workflow passes both only while
//   the repository variable of that name is true (Noah, 2026-10-29: "hold off on giving the testflight
//   build to public beta until I try it out in Insiders first tomorrow"). Without both, no external
//   group is ever touched and nothing goes to Beta App Review.
// - Beta App Review: only right after the build went to that external group, and only when TestFlight
//   says it waits for a submission (externalBuildState READY_FOR_BETA_SUBMISSION). The first build of a
//   version is reviewed in full; a later build of the same version is submitted the same way and
//   usually approved within minutes. A build already in review or approved is left as it is.
//
// The token: an ES256 JWT (header alg ES256, kid the Key ID, typ JWT; claims iss the Issuer ID, iat,
// exp 15 minutes later, aud appstoreconnect-v1; App Store Connect refuses more than 20 minutes) signed
// with the .p8 key, made again every 10 minutes during a long wait. It goes only into the
// Authorization header of requests to the API base above; it is never printed, logged or written to a
// file, and neither is the key. Redirects are not followed.
//
// Exit status: 0 done; 1 App Store Connect refused a request, the build failed processing, or the wait
// ran out; 2 a usage error (a missing or malformed option, a key file that isn't a key, --public-beta
// without SILL_NIGHTLY_PUBLIC_BETA=true).
import CryptoKit
import Foundation

setvbuf(stdout, nil, _IOLBF, 0)   // progress lines during a long wait show as they happen in a pipe

let environment = ProcessInfo.processInfo.environment
let inActions = environment["GITHUB_ACTIONS"] == "true"
let usageText = """
    usage: asc groups      --key-file F --key-id ID --issuer ID [--bundle-id ID]
           asc build-state --key-file F --key-id ID --issuer ID --version V --build N
           asc whats-new   --key-file F --key-id ID --issuer ID --version V --build N --whats-new FILE
           asc distribute  --key-file F --key-id ID --issuer ID --version V --build N --whats-new FILE
                           [--public-beta [--public-beta-group NAME]]
           [--wait-minutes 90] [--poll-seconds 60] [--retry-seconds 5] [--api-base URL]
    Scripts/asc.swift's header says what each does; docs/release-checklist.md, "Nightlies".
    """

// MARK: - Output

/// A GitHub Actions annotation's message: a %, a carriage return or a newline would otherwise end it
/// or start a command of its own.
func annotation(_ text: String) -> String {
    text.replacingOccurrences(of: "%", with: "%25").replacingOccurrences(of: "\r", with: "%0D")
        .replacingOccurrences(of: "\n", with: "%0A")
}

func say(_ text: String) { print(text) }

func warn(_ text: String) {
    let line = inActions ? "::warning::\(annotation(text))" : "warning: \(text)"
    FileHandle.standardError.write(Data((line + "\n").utf8))
}

func fail(_ text: String, status: Int32 = 1) -> Never {
    let line = inActions ? "::error::\(annotation(text))" : "error: \(text)"
    FileHandle.standardError.write(Data((line + "\n").utf8))
    exit(status)
}

/// Text from App Store Connect, made safe to print on one line: control characters (newlines among
/// them, which in a GitHub log could start a workflow command) become spaces, and it is cut at 300.
func clean(_ text: String) -> String {
    let scalars = text.unicodeScalars.map { CharacterSet.controlCharacters.contains($0) ? " " : Character($0) }
    let joined = String(scalars).split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
    return joined.count > 300 ? String(joined.prefix(300)) + "…" : joined
}

// MARK: - Options

struct Options {
    var command = ""
    var keyFile = ""
    var keyID = ""
    var issuer = ""
    var bundleID = "me.saffer.sill"
    var version = ""
    var build = ""
    var whatsNewFile = ""
    var publicBeta = false
    var publicBetaGroup: String?
    var waitMinutes = 90.0
    var pollSeconds = 60.0
    var retrySeconds = 5.0
    var apiBase = "https://api.appstoreconnect.apple.com"
}

func usageError(_ text: String) -> Never {
    FileHandle.standardError.write(Data("error: \(text)\n\(usageText)\n".utf8))
    exit(2)
}

func parseOptions(_ arguments: [String]) -> Options {
    var options = Options()
    var rest = arguments[...]
    guard let command = rest.popFirst() else { usageError("no command") }
    if command == "-h" || command == "--help" { print(usageText); exit(0) }
    guard ["groups", "build-state", "whats-new", "distribute"].contains(command) else {
        usageError("unknown command '\(clean(command))'")
    }
    options.command = command
    func number(_ name: String, _ text: String) -> Double {
        guard let value = Double(text), value.isFinite, value >= 0 else { usageError("\(name) takes a number, not '\(clean(text))'") }
        return value
    }
    while let argument = rest.popFirst() {
        var name = argument
        var value: String?
        if argument.hasPrefix("--"), let equals = argument.firstIndex(of: "=") {
            name = String(argument[..<equals])
            value = String(argument[argument.index(after: equals)...])
        }
        if name == "--public-beta" {
            if value != nil { usageError("--public-beta takes no value") }
            options.publicBeta = true
            continue
        }
        if name == "-h" || name == "--help" { print(usageText); exit(0) }
        let flags = ["--key-file", "--key-id", "--issuer", "--bundle-id", "--version", "--build", "--whats-new",
                     "--public-beta-group", "--wait-minutes", "--poll-seconds", "--retry-seconds", "--api-base"]
        guard flags.contains(name) else { usageError("unknown option '\(clean(argument))'") }
        if value == nil {
            guard let next = rest.popFirst() else { usageError("\(name) needs a value") }
            value = next
        }
        let text = value ?? ""
        switch name {
        case "--key-file": options.keyFile = text
        case "--key-id": options.keyID = text
        case "--issuer": options.issuer = text
        case "--bundle-id": options.bundleID = text
        case "--version": options.version = text
        case "--build": options.build = text
        case "--whats-new": options.whatsNewFile = text
        case "--public-beta-group": options.publicBetaGroup = text
        case "--wait-minutes": options.waitMinutes = number(name, text)
        case "--poll-seconds": options.pollSeconds = number(name, text)
        case "--retry-seconds": options.retrySeconds = number(name, text)
        case "--api-base": options.apiBase = text
        default: usageError("unknown option '\(clean(argument))'")
        }
    }
    return options
}

func matches(_ text: String, _ pattern: String) -> Bool {
    text.range(of: pattern, options: .regularExpression) != nil
}

/// The default base, or a stand-in on this Mac for tests: the token is never sent anywhere else.
func allowedBase(_ url: URL) -> Bool {
    if url.scheme == "https", url.host == "api.appstoreconnect.apple.com", url.port == nil,
       url.path.isEmpty || url.path == "/" { return true }
    guard url.scheme == "http" || url.scheme == "https", url.user == nil, url.password == nil,
          let host = url.host else { return false }
    return ["127.0.0.1", "localhost", "::1", "[::1]"].contains(host)
}

func validate(_ options: Options) -> URL {
    if options.keyFile.isEmpty { usageError("--key-file is required: the App Store Connect key, AuthKey_<Key ID>.p8") }
    if !matches(options.keyID, "^[A-Za-z0-9]{8,16}$") { usageError("--key-id: '\(clean(options.keyID))' is not a Key ID (letters and digits, such as ABC123DEFG)") }
    if !matches(options.issuer, "^[0-9A-Fa-f-]{36}$") { usageError("--issuer: '\(clean(options.issuer))' is not an Issuer ID (a UUID)") }
    if !matches(options.bundleID, "^[A-Za-z0-9.-]{1,155}$") { usageError("--bundle-id: '\(clean(options.bundleID))' is not a bundle ID") }
    if options.command != "groups" {
        if !matches(options.version, "^[0-9]{1,9}(\\.[0-9]{1,9}){0,2}$") { usageError("--version: '\(clean(options.version))' is not a version such as 0.6.0") }
        if !matches(options.build, "^[0-9]{1,18}(\\.[0-9]{1,9}){0,2}$") { usageError("--build: '\(clean(options.build))' is not a build number such as 983") }
    }
    if options.command == "whats-new" || options.command == "distribute" {
        if options.whatsNewFile.isEmpty { usageError("\(options.command) needs --whats-new FILE: the build's What to Test") }
    }
    if options.publicBeta {
        guard options.command == "distribute" else { usageError("--public-beta goes with distribute") }
        guard environment["SILL_NIGHTLY_PUBLIC_BETA"] == "true" else {
            usageError("--public-beta is refused unless the environment also says SILL_NIGHTLY_PUBLIC_BETA=true (the nightly workflow sets it only while the repository variable SILL_NIGHTLY_PUBLIC_BETA is true). Nothing was sent.")
        }
    } else if options.publicBetaGroup != nil {
        usageError("--public-beta-group goes with --public-beta")
    }
    if options.waitMinutes <= 0 || options.waitMinutes > 600 { usageError("--wait-minutes must be more than 0 and at most 600") }
    if options.pollSeconds > 3600 { usageError("--poll-seconds must be at most 3600") }
    if options.retrySeconds > 300 { usageError("--retry-seconds must be at most 300") }
    guard let base = URL(string: options.apiBase), allowedBase(base) else {
        usageError("--api-base: \(clean(options.apiBase)) is neither https://api.appstoreconnect.apple.com nor a stand-in on this Mac (http or https on 127.0.0.1, localhost or [::1])")
    }
    return base
}

/// What to Test from a file: UTF-8, not empty, and within App Store Connect's 4,000 characters
/// (counted as UTF-16, the stricter count); a longer text is cut at its last line that fits, with a
/// line saying where the rest is.
func readWhatsNew(_ path: String) -> String {
    guard let data = FileManager.default.contents(atPath: path) else { usageError("--whats-new: can't read \(path)") }
    guard let text = String(data: data, encoding: .utf8) else { usageError("--whats-new: \(path) is not UTF-8 text") }
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty { usageError("--whats-new: \(path) is empty") }
    let limit = 4000
    if trimmed.utf16.count <= limit { return trimmed }
    let tail = "\n… and more: https://github.com/Saffsanity/sill/releases/tag/nightly"
    var kept: [Substring] = []
    var count = tail.utf16.count
    for line in trimmed.split(separator: "\n", omittingEmptySubsequences: false) {
        let cost = line.utf16.count + 1
        if count + cost > limit { break }
        kept.append(line)
        count += cost
    }
    warn("What to Test was \(trimmed.utf16.count) characters, over App Store Connect's \(limit); cut to \(count).")
    return kept.joined(separator: "\n") + tail
}

// MARK: - The token

func base64URL(_ data: Data) -> String {
    data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

func loadKey(_ path: String) -> P256.Signing.PrivateKey {
    guard let data = FileManager.default.contents(atPath: path), let pem = String(data: data, encoding: .utf8) else {
        usageError("--key-file: \(path) is not a file this user can read")
    }
    guard pem.contains("-----BEGIN PRIVATE KEY-----") else {
        usageError("--key-file: \(path) is not an App Store Connect key, the .p8 file that begins -----BEGIN PRIVATE KEY-----")
    }
    guard let key = try? P256.Signing.PrivateKey(pemRepresentation: pem) else {
        usageError("--key-file: \(path) holds no P-256 private key (App Store Connect's keys are P-256)")
    }
    return key
}

/// An ES256 JWT for App Store Connect: 15 minutes long (it refuses more than 20).
func makeToken(keyID: String, issuer: String, key: P256.Signing.PrivateKey, now: Date) -> String {
    let issued = Int(now.timeIntervalSince1970)
    let header: [String: Any] = ["alg": "ES256", "kid": keyID, "typ": "JWT"]
    let claims: [String: Any] = ["iss": issuer, "iat": issued, "exp": issued + 15 * 60, "aud": "appstoreconnect-v1"]
    guard let headerJSON = try? JSONSerialization.data(withJSONObject: header, options: [.sortedKeys]),
          let claimsJSON = try? JSONSerialization.data(withJSONObject: claims, options: [.sortedKeys]) else {
        fail("couldn't encode the token's header and claims")
    }
    let input = base64URL(headerJSON) + "." + base64URL(claimsJSON)
    guard let signature = try? key.signature(for: Data(input.utf8)) else { fail("couldn't sign the token with the key") }
    return input + "." + base64URL(signature.rawRepresentation)
}

// MARK: - Requests

struct Answer {
    let status: Int
    let data: Data
    let retryAfter: Double?

    var json: [String: Any]? { (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] }
}

/// URLSession's answer, handed from its queue to the waiting thread.
final class Box: @unchecked Sendable {
    var answer: Answer?
    var error: Error?
}

/// Refuses every redirect: App Store Connect's API doesn't redirect, and a redirect could carry the
/// Authorization header elsewhere.
final class NoRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

final class Client {
    let base: URL
    let keyID: String
    let issuer: String
    let key: P256.Signing.PrivateKey
    let retrySeconds: Double
    let session: URLSession
    private var token: (value: String, made: Date)?

    init(base: URL, keyID: String, issuer: String, key: P256.Signing.PrivateKey, retrySeconds: Double) {
        self.base = base
        self.keyID = keyID
        self.issuer = issuer
        self.key = key
        self.retrySeconds = retrySeconds
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForRequest = 60
        session = URLSession(configuration: configuration, delegate: NoRedirects(), delegateQueue: nil)
    }

    /// A token made in the last 10 minutes, or a new one.
    private func bearer() -> String {
        let now = Date()
        if let token, now.timeIntervalSince(token.made) < 600, now >= token.made { return token.value }
        let value = makeToken(keyID: keyID, issuer: issuer, key: key, now: now)
        token = (value, now)
        return value
    }

    func url(_ path: String, _ query: [(String, String)] = []) -> URL {
        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        components.path = path
        components.queryItems = query.isEmpty ? nil : query.map { URLQueryItem(name: $0.0, value: $0.1) }
        guard let url = components.url else { fail("couldn't make the address of \(path)") }
        return url
    }

    /// Where a request went, for messages: the path and query, never the token.
    func shown(_ url: URL) -> String {
        url.path + (url.query.map { "?" + ($0.removingPercentEncoding ?? $0) } ?? "")
    }

    func sameOrigin(_ url: URL) -> Bool {
        url.scheme == base.scheme && url.host == base.host && url.port == base.port
    }

    /// One request, tried again after a 429, a 5xx or no answer (four tries in all, waiting
    /// retrySeconds, then 3 and 6 times as long, or what Retry-After asks up to a minute).
    func send(_ method: String, _ url: URL, json: Any? = nil) -> Answer {
        guard sameOrigin(url) else { fail("refusing to send the token to \(url.host ?? "another host"): not \(base.host ?? "the API base")") }
        let waits = [1.0, 3.0, 6.0].map { $0 * retrySeconds }
        var attempt = 0
        while true {
            var request = URLRequest(url: url, timeoutInterval: 60)
            request.httpMethod = method
            request.setValue("Bearer \(bearer())", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            if let json {
                guard let body = try? JSONSerialization.data(withJSONObject: json, options: [.sortedKeys]) else {
                    fail("couldn't encode the body of \(method) \(url.path)")
                }
                request.httpBody = body
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }
            let box = Box()
            let done = DispatchSemaphore(value: 0)
            session.dataTask(with: request) { data, response, error in
                if let error {
                    box.error = error
                } else if let http = response as? HTTPURLResponse {
                    box.answer = Answer(status: http.statusCode, data: data ?? Data(),
                                        retryAfter: http.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init))
                } else {
                    box.error = URLError(.badServerResponse)
                }
                done.signal()
            }.resume()
            done.wait()
            let retryable = box.error != nil || (box.answer.map { $0.status == 429 || $0.status >= 500 } ?? false)
            if retryable && attempt < waits.count {
                let wait = min(max(box.answer?.retryAfter ?? waits[attempt], waits[attempt]), 60)
                let why = box.error.map { clean($0.localizedDescription) } ?? "HTTP \(box.answer?.status ?? 0)"
                say("  \(method) \(shown(url)): \(why); trying again in \(Int(wait)) s")
                attempt += 1
                if wait > 0 { Thread.sleep(forTimeInterval: wait) }
                continue
            }
            if let error = box.error {
                fail("couldn't reach App Store Connect (\(method) \(shown(url))): \(clean(error.localizedDescription))")
            }
            return box.answer!
        }
    }

    /// App Store Connect's own words for a refusal, and what usually explains it.
    func explain(_ answer: Answer, _ what: String) -> String {
        var parts: [String] = []
        if let errors = answer.json?["errors"] as? [[String: Any]] {
            for error in errors.prefix(5) {
                // "<title> <detail> [<code>]": App Store Connect's titles and details are sentences.
                var words = [error["title"] as? String, error["detail"] as? String].compactMap { $0 }.map(clean)
                    .filter { !$0.isEmpty }.map { $0.last.map { ".!?:".contains($0) } == true ? $0 : $0 + "." }
                    .joined(separator: " ")
                if let code = error["code"] as? String, !clean(code).isEmpty { words += (words.isEmpty ? "" : " ") + "[\(clean(code))]" }
                if !words.isEmpty { parts.append(words) }
            }
        }
        if parts.isEmpty {
            let text = clean(String(decoding: answer.data.prefix(300), as: UTF8.self))
            parts.append(text.isEmpty ? "no details" : text)
        }
        var line = "\(what): App Store Connect answered HTTP \(answer.status): \(parts.joined(separator: "; "))"
        switch answer.status {
        case 401: line += " The key, its Key ID or the Issuer ID is wrong, or the key was revoked (App Store Connect › Users and Access › Integrations)."
        case 403: line += " The key's role may not do this: the nightly's key needs the Admin role."
        case 300..<400: line += " (A redirect: not followed.)"
        default: break
        }
        return line
    }

    /// Every page of a list: its data and its included resources.
    func list(_ path: String, _ query: [(String, String)]) -> (data: [[String: Any]], included: [[String: Any]]) {
        var next: URL? = url(path, query)
        var data: [[String: Any]] = []
        var included: [[String: Any]] = []
        var pages = 0
        while let page = next {
            pages += 1
            if pages > 50 { fail("GET \(path): more than 50 pages; stopped") }
            let answer = send("GET", page)
            guard answer.status == 200, let object = answer.json else { fail(explain(answer, "GET \(shown(page))")) }
            data += object["data"] as? [[String: Any]] ?? []
            included += object["included"] as? [[String: Any]] ?? []
            next = nil
            if let link = (object["links"] as? [String: Any])?["next"] as? String {
                guard let linked = URL(string: link), sameOrigin(linked) else {
                    fail("GET \(path): App Store Connect's next page is not on \(base.host ?? "the API base"); not following it with the token")
                }
                next = linked
            }
        }
        return (data, included)
    }

    func get(_ path: String, _ query: [(String, String)] = []) -> [String: Any] {
        let address = url(path, query)
        let answer = send("GET", address)
        guard answer.status == 200, let object = answer.json else { fail(explain(answer, "GET \(shown(address))")) }
        return object
    }
}

func attributes(_ resource: [String: Any]) -> [String: Any] { resource["attributes"] as? [String: Any] ?? [:] }
func identifier(_ resource: [String: Any]) -> String { resource["id"] as? String ?? "" }

// MARK: - App Store Connect's resources

struct Group {
    let id: String
    let name: String
    let isInternal: Bool
    let publicLinkEnabled: Bool
    let allBuilds: Bool

    var described: String {
        if isInternal { return "internal '\(name)'" + (allBuilds ? " (automatic distribution: every build)" : "") }
        return "external '\(name)'" + (publicLinkEnabled ? " (public link)" : "")
    }
}

struct Build {
    let id: String
    let processingState: String
    let expired: Bool
}

func findApp(_ client: Client, bundleID: String) -> (id: String, name: String) {
    let (apps, _) = client.list("/v1/apps", [("filter[bundleId]", bundleID), ("fields[apps]", "bundleId,name"), ("limit", "200")])
    guard let app = apps.first(where: { attributes($0)["bundleId"] as? String == bundleID }), !identifier(app).isEmpty else {
        fail("App Store Connect lists no app with the bundle ID \(bundleID) for this key's team (docs/release-checklist.md, TestFlight §1)")
    }
    return (identifier(app), clean(attributes(app)["name"] as? String ?? bundleID))
}

func listGroups(_ client: Client, appID: String) -> [Group] {
    let (groups, _) = client.list("/v1/betaGroups", [("filter[app]", appID),
        ("fields[betaGroups]", "name,isInternalGroup,publicLinkEnabled,hasAccessToAllBuilds"), ("limit", "200")])
    return groups.compactMap { resource in
        let attributes = attributes(resource)
        guard !identifier(resource).isEmpty else { return nil }
        return Group(id: identifier(resource), name: clean(attributes["name"] as? String ?? "?"),
                     isInternal: attributes["isInternalGroup"] as? Bool ?? false,
                     publicLinkEnabled: attributes["publicLinkEnabled"] as? Bool ?? false,
                     allBuilds: attributes["hasAccessToAllBuilds"] as? Bool ?? false)
    }.sorted { ($0.isInternal ? 0 : 1, $0.name) < ($1.isInternal ? 0 : 1, $1.name) }
}

/// Build `build` of version `version`, if App Store Connect lists it yet.
func findBuild(_ client: Client, appID: String, version: String, build: String) -> Build? {
    let (builds, _) = client.list("/v1/builds", [("filter[app]", appID), ("filter[version]", build),
        ("filter[preReleaseVersion.version]", version), ("fields[builds]", "version,processingState,expired,uploadedDate"),
        ("limit", "10")])
    guard let found = builds.first(where: { attributes($0)["version"] as? String == build }) else { return nil }
    let attributes = attributes(found)
    return Build(id: identifier(found), processingState: attributes["processingState"] as? String ?? "?",
                 expired: attributes["expired"] as? Bool ?? false)
}

/// The build's TestFlight states: (internal, external).
func betaStates(_ client: Client, buildID: String) -> (internalState: String, externalState: String) {
    let object = client.get("/v1/builds/\(buildID)/buildBetaDetail",
                            [("fields[buildBetaDetails]", "internalBuildState,externalBuildState")])
    let attributes = attributes(object["data"] as? [String: Any] ?? [:])
    return (attributes["internalBuildState"] as? String ?? "?", attributes["externalBuildState"] as? String ?? "?")
}

/// A length of time in minutes as the messages say it: "90 min", or seconds under a minute.
func minutes(_ value: Double) -> String { value < 1 ? "\(Int(value * 60)) s" : "\(Int(value)) min" }

func elapsed(since start: Date) -> String {
    let seconds = Int(Date().timeIntervalSince(start))
    return seconds < 60 ? "\(seconds) s" : "\(seconds / 60) min \(seconds % 60) s"
}

/// Waits until App Store Connect has processed the build and TestFlight may give it to testers.
func waitForBuild(_ client: Client, appID: String, options: Options) -> Build {
    let start = Date()
    let deadline = start.addingTimeInterval(options.waitMinutes * 60)
    let what = "build \(options.build) of \(options.version)"
    say("Waiting for App Store Connect to process \(what): a look every \(Int(options.pollSeconds)) s, for \(minutes(options.waitMinutes)) at most")
    var build: Build?
    while true {
        build = findBuild(client, appID: appID, version: options.version, build: options.build)
        if let build {
            if build.expired { fail("\(what) has expired in TestFlight") }
            switch build.processingState {
            case "VALID":
                say("  \(what) is processed (\(elapsed(since: start)))")
            case "FAILED", "INVALID":
                fail("App Store Connect could not process \(what) (\(build.processingState)). Its email to the account holder says why (often ITMS-91053: a required-reason API the privacy manifest doesn't declare); nothing was given to testers.")
            default:
                say("  \(what): \(clean(build.processingState)) (\(elapsed(since: start)))")
            }
            if build.processingState == "VALID" { break }
        } else {
            say("  \(what) is not listed yet (\(elapsed(since: start)))")
        }
        if Date().addingTimeInterval(options.pollSeconds) > deadline {
            fail("App Store Connect has not finished processing \(what) after \(minutes(options.waitMinutes)). It shows in TestFlight once it has: give it What to Test and its groups there (or run this job again).")
        }
        if options.pollSeconds > 0 { Thread.sleep(forTimeInterval: options.pollSeconds) }
    }
    // Processed is not yet testable: TestFlight's own state follows within a few minutes.
    while true {
        let states = betaStates(client, buildID: build!.id)
        switch states.internalState {
        case "READY_FOR_BETA_TESTING", "IN_BETA_TESTING":
            say("  TestFlight: \(states.internalState) (internal), \(clean(states.externalState)) (external)")
            return build!
        case "MISSING_EXPORT_COMPLIANCE":
            fail("TestFlight holds \(what) for export compliance: the app's ITSAppUsesNonExemptEncryption should be NO (iOSClient/Info.plist); answer it in TestFlight, then run this again.")
        case "PROCESSING_EXCEPTION", "EXPIRED":
            fail("TestFlight says \(what) is \(states.internalState); nothing was given to testers.")
        default:
            say("  TestFlight: \(clean(states.internalState)) (\(elapsed(since: start)))")
        }
        if Date().addingTimeInterval(options.pollSeconds) > deadline {
            fail("TestFlight has not made \(what) ready for testing after \(minutes(options.waitMinutes)) (it says \(clean(states.internalState))).")
        }
        if options.pollSeconds > 0 { Thread.sleep(forTimeInterval: options.pollSeconds) }
    }
}

/// The build's What to Test in English (U.S.): the localization changed if it exists, made if not.
func setWhatsNew(_ client: Client, build: Build, text: String) {
    let (localizations, _) = client.list("/v1/builds/\(build.id)/betaBuildLocalizations",
                                         [("fields[betaBuildLocalizations]", "locale,whatsNew"), ("limit", "50")])
    if let existing = localizations.first(where: { attributes($0)["locale"] as? String == "en-US" }) {
        let address = client.url("/v1/betaBuildLocalizations/\(identifier(existing))")
        let answer = client.send("PATCH", address, json: ["data": ["type": "betaBuildLocalizations", "id": identifier(existing),
                                                                     "attributes": ["whatsNew": text]]])
        guard answer.status == 200 else { fail(client.explain(answer, "What to Test (PATCH \(client.shown(address)))")) }
    } else {
        let address = client.url("/v1/betaBuildLocalizations")
        let answer = client.send("POST", address, json: ["data": ["type": "betaBuildLocalizations",
            "attributes": ["locale": "en-US", "whatsNew": text],
            "relationships": ["build": ["data": ["type": "builds", "id": build.id]]]]])
        guard answer.status == 201 else { fail(client.explain(answer, "What to Test (POST \(client.shown(address)))")) }
    }
    say("What to Test set (English (U.S.), \(text.count) characters)")
}

/// Adds the build to one group. Asked again for a build already there, App Store Connect changes nothing.
func add(_ client: Client, build: Build, to group: Group, publicBetaAllowed: Bool) {
    // The rule in one place: no external group without --public-beta and SILL_NIGHTLY_PUBLIC_BETA=true.
    precondition(group.isInternal || publicBetaAllowed, "an external group without the public beta's permission")
    let address = client.url("/v1/betaGroups/\(group.id)/relationships/builds")
    let answer = client.send("POST", address, json: ["data": [["type": "builds", "id": build.id]]])
    guard (200..<300).contains(answer.status) else { fail(client.explain(answer, "Adding the build to \(group.described)")) }
}

/// Beta App Review for a build that just went to the public beta group, when TestFlight waits for it.
func submitForReview(_ client: Client, build: Build, options: Options) {
    let start = Date()
    while true {
        let state = betaStates(client, buildID: build.id).externalState
        switch state {
        case "READY_FOR_BETA_SUBMISSION":
            let address = client.url("/v1/betaAppReviewSubmissions")
            let answer = client.send("POST", address, json: ["data": ["type": "betaAppReviewSubmissions",
                "relationships": ["build": ["data": ["type": "builds", "id": build.id]]]]])
            if answer.status == 201 {
                say("Submitted build \(options.build) of \(options.version) for Beta App Review: the first build of a version is reviewed in full, a later one is usually approved within minutes. External testers get it once it is approved.")
            } else if answer.status == 409 {
                // Typically another build of the version still in review: the next nightly tries again.
                warn(client.explain(answer, "Beta App Review submission") + " The public beta group has the build; it reaches its testers once a submission is accepted (TestFlight › the build › Submit for Review, or the next nightly).")
            } else {
                fail(client.explain(answer, "Beta App Review submission"))
            }
            return
        case "WAITING_FOR_BETA_REVIEW", "IN_BETA_REVIEW":
            say("Beta App Review: the build is already waiting or in review (\(state)).")
            return
        case "BETA_APPROVED", "IN_BETA_TESTING", "READY_FOR_BETA_TESTING":
            say("Beta App Review: nothing to submit; the build is \(state) for external testers.")
            return
        case "BETA_REJECTED":
            fail("Beta App Review rejected build \(options.build) of \(options.version): App Store Connect › TestFlight says why.")
        case "MISSING_EXPORT_COMPLIANCE", "EXPIRED", "PROCESSING_EXCEPTION":
            fail("The build can't go to Beta App Review: TestFlight says it is \(state).")
        default:
            if Date().timeIntervalSince(start) > 10 * 60 {
                warn("TestFlight's external state for the build is still \(clean(state)) after 10 min; nothing was submitted for Beta App Review.")
                return
            }
            say("  TestFlight's external state is \(clean(state)); looking again in \(Int(min(options.pollSeconds, 30))) s")
            if options.pollSeconds > 0 { Thread.sleep(forTimeInterval: min(options.pollSeconds, 30)) }
        }
    }
}

// MARK: - The commands

let options = parseOptions(Array(CommandLine.arguments.dropFirst()))
let base = validate(options)
let whatsNew = options.whatsNewFile.isEmpty ? nil : readWhatsNew(options.whatsNewFile)
let client = Client(base: base, keyID: options.keyID, issuer: options.issuer, key: loadKey(options.keyFile),
                    retrySeconds: options.retrySeconds)
let app = findApp(client, bundleID: options.bundleID)

switch options.command {
case "groups":
    let groups = listGroups(client, appID: app.id)
    say("\(app.name) (\(options.bundleID), App Store Connect \(app.id)): \(groups.count) TestFlight group\(groups.count == 1 ? "" : "s")")
    for group in groups { say("  \(group.described)") }

case "build-state":
    let build = findBuild(client, appID: app.id, version: options.version, build: options.build)
    FileHandle.standardError.write(Data("Build \(options.build) of \(options.version): \(build.map { clean($0.processingState) } ?? "not listed")\n".utf8))
    print(build.map { matches($0.processingState, "^[A-Z_]{1,40}$") ? $0.processingState : "UNKNOWN" } ?? "missing")

case "whats-new":
    let build = waitForBuild(client, appID: app.id, options: options)
    setWhatsNew(client, build: build, text: whatsNew!)

case "distribute":
    // The groups first: a wrong key or a missing group shows now, not after the wait.
    let groups = listGroups(client, appID: app.id)
    let internalGroups = groups.filter(\.isInternal)
    let externalGroups = groups.filter { !$0.isInternal }
    var publicBeta: Group?
    if options.publicBeta {
        let candidates = options.publicBetaGroup.map { name in externalGroups.filter { $0.name == name } }
            ?? externalGroups.filter(\.publicLinkEnabled)
        if candidates.count != 1 {
            let named = options.publicBetaGroup.map { "named '\(clean($0))'" } ?? "with the public link on"
            fail("--public-beta: \(candidates.count) external groups \(named) (external groups: \(externalGroups.map(\.described).joined(separator: ", ").ifEmpty("none"))). Name one with --public-beta-group. Nothing was given to testers.")
        }
        publicBeta = candidates[0]
    }
    say("\(app.name): \(internalGroups.count) internal group\(internalGroups.count == 1 ? "" : "s") (\(internalGroups.map(\.name).joined(separator: ", ").ifEmpty("none"))), \(externalGroups.count) external (\(externalGroups.map(\.described).joined(separator: ", ").ifEmpty("none")))")
    let build = waitForBuild(client, appID: app.id, options: options)
    setWhatsNew(client, build: build, text: whatsNew!)
    var given: [String] = []
    var automatic: [String] = []
    for group in internalGroups {
        if group.allBuilds {
            automatic.append(group.name)
            say("Internal group '\(group.name)': gets every build by itself (automatic distribution); left as it is")
        } else {
            add(client, build: build, to: group, publicBetaAllowed: false)
            given.append(group.name)
            say("Internal group '\(group.name)': given build \(options.build) of \(options.version)")
        }
    }
    if internalGroups.isEmpty { warn("The app has no internal TestFlight group: nobody inside the team gets this build (TestFlight › Internal Testing › +).") }
    if let publicBeta {
        add(client, build: build, to: publicBeta, publicBetaAllowed: true)
        given.append(publicBeta.name)
        say("Public beta group '\(publicBeta.name)' (\(publicBeta.publicLinkEnabled ? "public link" : "external")): given build \(options.build) of \(options.version) (SILL_NIGHTLY_PUBLIC_BETA is true)")
        submitForReview(client, build: build, options: options)
    } else {
        let withLink = externalGroups.filter(\.publicLinkEnabled).map { "'\($0.name)'" }.joined(separator: ", ")
        say("Public beta: not given\(withLink.isEmpty ? "" : " to \(withLink)"): the repository variable SILL_NIGHTLY_PUBLIC_BETA is not true. No external group was touched and nothing went to Beta App Review.")
    }
    say("Assigned build \(options.build) of \(options.version) to: \(given.joined(separator: ", ").ifEmpty("no group"))\(automatic.isEmpty ? "" : "; by automatic distribution: \(automatic.joined(separator: ", "))").")

default:
    usageError("unknown command")
}

extension String {
    func ifEmpty(_ other: String) -> String { isEmpty ? other : self }
}
