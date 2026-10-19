import Foundation
import Darwin

// MARK: - Logging

enum Log {
    private static let queue = DispatchQueue(label: "dshpet.log")
    private static let fmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    static func write(_ message: String) {
        queue.async {
            let line = fmt.string(from: Date()) + " " + message + "\n"
            guard let data = line.data(using: .utf8) else { return }
            let url = PetPaths.logURL
            let fm = FileManager.default
            if let size = (try? fm.attributesOfItem(atPath: url.path)[.size]) as? NSNumber,
               size.intValue >= 1_048_576 {
                let previous = url.appendingPathExtension("1")
                // rename replaces the previous rotation atomically.
                _ = rename(url.path, previous.path)
            }
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                _ = fm.createFile(atPath: url.path, contents: data, attributes: [.posixPermissions: 0o600])
            }
        }
    }
}

// MARK: - Paths

enum PetPaths {
    static let support: URL = {
        let fm = FileManager.default
        // DSHPET_HOME makes the pet self-contained (portable mode, and how the
        // build's own end-to-end test keeps its state out of the real profile).
        if let override = ProcessInfo.processInfo.environment["DSHPET_HOME"], !override.isEmpty {
            let dir = URL(fileURLWithPath: (override as NSString).expandingTildeInPath, isDirectory: true)
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            return dir
        }
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support")
        let dir = base.appendingPathComponent("DSHBalancePet", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        return dir
    }()

    static var logURL: URL { support.appendingPathComponent("pet.log") }
    static var stateURL: URL { support.appendingPathComponent("state.json") }
    /// Liveness/geometry snapshot, rewritten about once a second while running.
    static var statusURL: URL { support.appendingPathComponent("status.json") }
    static var userKeyURL: URL { support.appendingPathComponent("apikey.txt") }

    /// apikey.txt shipped next to the executable (inside the .app, or next to the raw binary).
    static var sidecarKeyURL: URL {
        executableDir.appendingPathComponent("apikey.txt")
    }

    static var executableDir: URL {
        URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().deletingLastPathComponent()
    }

    static var soundURL: URL? {
        let candidates: [URL?] = [
            Bundle.main.url(forResource: "hit", withExtension: "mp3"),
            Bundle.main.url(forResource: "hit", withExtension: "wav"),
            support.appendingPathComponent("hit.mp3"),
            support.appendingPathComponent("hit.wav"),
            executableDir.appendingPathComponent("hit.mp3"),
            executableDir.appendingPathComponent("hit.wav"),
        ]
        return candidates.compactMap { $0 }.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    static let dshCredentials = URL(fileURLWithPath: NSHomeDirectory() + "/.dsh/.credentials.yaml")
}

// MARK: - Credentials

enum AuthMode {
    case apiKey    // sk-... -> https://api.deepseek.com/user/balance  (Authorization: Bearer)
    case account   // DSH platform grant -> <issuer>/api/v0/users/get_user_summary  (x-dsh-auth-token)
}

struct Credential {
    let mode: AuthMode
    let token: String
    let endpoint: URL
    let source: String

    var shortDescription: String {
        switch mode {
        case .apiKey:  return "API Key · " + source
        case .account: return "DSH 账号凭证 · " + source
        }
    }
}

enum CredentialStore {
    static let apiKeyEndpoint = "https://api.deepseek.com/user/balance"

    /// First configured source wins. Offline diagnostics must never read a real key.
    static func resolve() -> Credential? {
        let env = ProcessInfo.processInfo.environment
        if env["DSHPET_OFFLINE"] == "1" { return nil }
        if let value = env["DSHPET_KEY"], !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return apiKey(value, source: "环境变量 DSHPET_KEY")
        }
        if let value = readKeyFile(PetPaths.sidecarKeyURL) {
            return apiKey(value, source: "apikey.txt（应用目录）")
        }
        if let value = readKeyFile(PetPaths.userKeyURL) {
            return apiKey(value, source: "apikey.txt（配置目录）")
        }
        let yaml = (try? String(contentsOf: PetPaths.dshCredentials, encoding: .utf8)) ?? ""
        if let key = yamlAPIKey(from: yaml) { return apiKey(key, source: "~/.dsh/.credentials.yaml") }
        if let grant = accountGrant(from: yaml),
           let endpoint = accountEndpoint(issuer: grant.issuer, path: env["DSHPET_API_PATH"] ?? "/api/v0/users/get_user_summary") {
            return Credential(mode: .account, token: grant.token, endpoint: endpoint,
                              source: "DSH 账号（\(endpoint.host ?? "")）")
        }
        return nil
    }

    static func isValidToken(_ value: String) -> Bool {
        // Credentials are single-line HTTP header values, never arbitrary text.
        !value.isEmpty && value.utf8.count <= 16_384 && value.unicodeScalars.allSatisfy { $0.value >= 33 && $0.value <= 126 }
    }

    static func isSafeEndpoint(_ url: URL) -> Bool {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme?.lowercased() == "https", let host = parts.host, !host.isEmpty,
              parts.user == nil, parts.password == nil, parts.fragment == nil,
              parts.query == nil else { return false }
        return !host.contains(where: { $0.isWhitespace })
    }

    static func accountEndpoint(issuer: String, path: String) -> URL? {
        guard !issuer.contains(where: { $0.isWhitespace || $0 == "\\" }),
              let base = URL(string: issuer), isSafeEndpoint(base),
              var parts = URLComponents(url: base, resolvingAgainstBaseURL: false),
              path.hasPrefix("/"), !path.hasPrefix("//"),
              !path.contains(where: { $0.isWhitespace || $0 == "\\" || $0 == "?" || $0 == "#" || $0 == "%" }),
              !path.split(separator: "/").contains(where: { $0 == "." || $0 == ".." }) else { return nil }
        parts.path = parts.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        parts.path = (parts.path.isEmpty ? "" : "/" + parts.path) + path
        guard let url = parts.url, isSafeEndpoint(url) else { return nil }
        return url
    }

    private static func apiKey(_ raw: String, source: String) -> Credential? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidToken(value), let url = URL(string: apiKeyEndpoint) else { return nil }
        return Credential(mode: .apiKey, token: value, endpoint: url, source: source)
    }

    private static func readKeyFile(_ url: URL) -> String? {
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    enum SaveError: LocalizedError {
        case invalidKey
        var errorDescription: String? { "API Key 必须是有效的单行凭证" }
    }

    /// Write a 0600 temporary file and atomically replace the old key. A failure
    /// leaves the previous key intact and is surfaced to the settings dialog.
    static func saveAPIKey(_ raw: String, to destination: URL = PetPaths.userKeyURL) throws {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidToken(value) else { throw SaveError.invalidKey }
        let fm = FileManager.default
        let directory = destination.deletingLastPathComponent()
        try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let temporary = directory.appendingPathComponent(".apikey-" + UUID().uuidString)
        defer { try? fm.removeItem(at: temporary) }
        guard fm.createFile(atPath: temporary.path, contents: Data(value.utf8),
                            attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        // POSIX rename atomically replaces a destination file (or a symlink),
        // preserving the restrictive mode without a world-readable interval.
        guard rename(temporary.path, destination.path) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
    }

    static func yamlAPIKey(from yaml: String) -> String? {
        let matches = yaml.components(separatedBy: .newlines).compactMap(mappingLine)
            .filter { $0.key == "DEEPSEEK_API_KEY" }
        guard matches.count == 1, let value = scalar(matches[0].value), isValidToken(value) else { return nil }
        return value
    }

    /// Read DSH's account record: kind + payload { version, token, issuer }.
    /// Older records store token/issuer directly. Only siblings within one
    /// recognized container may form a grant; unrelated descendants are ignored.
    static func accountGrant(from yaml: String) -> (token: String, issuer: String)? {
        let lines = yaml.components(separatedBy: .newlines)
        let grants = lines.enumerated().filter { mappingLine($0.element)?.key == "deepseek-account-platform/default" }
        guard grants.count == 1, let grant = grants.first,
              let header = mappingLine(grant.element), header.value.isEmpty else { return nil }

        func children(after offset: Int, parentIndent: Int) -> [(offset: Int, item: MappingLine)]? {
            var result: [(offset: Int, item: MappingLine)] = []
            var childIndent: Int?
            for index in (offset + 1)..<lines.count {
                let line = lines[index]
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
                let indent = line.prefix { $0 == " " }.count
                if indent <= parentIndent { break }
                if childIndent == nil { childIndent = indent }
                guard indent == childIndent else { continue }
                guard let item = mappingLine(line) else { return nil }
                result.append((index, item))
            }
            return result
        }

        guard let direct = children(after: grant.offset, parentIndent: header.indent) else { return nil }
        let payloads = direct.filter { $0.item.key == "payload" }
        let legacyFields = direct.filter { ["token", "issuer"].contains($0.item.key) }
        let fields: [(offset: Int, item: MappingLine)]
        if let payload = payloads.first {
            // Multiple payloads, scalar payloads, or a mixture of old/new
            // layouts are ambiguous and must not select an unintended account.
            guard payloads.count == 1, payload.item.value.isEmpty, legacyFields.isEmpty,
                  let nested = children(after: payload.offset, parentIndent: payload.item.indent) else { return nil }
            fields = nested
        } else {
            fields = legacyFields
        }
        var values: [String: String] = [:]
        for field in fields where ["token", "issuer"].contains(field.item.key) {
            guard values[field.item.key] == nil, let value = scalar(field.item.value) else { return nil }
            values[field.item.key] = value
        }
        guard let token = values["token"], isValidToken(token),
              let issuer = values["issuer"], !issuer.isEmpty else { return nil }
        return (token, issuer)
    }

    private struct MappingLine {
        let indent: Int
        let key: String
        let value: String
    }

    private static func mappingLine(_ line: String) -> MappingLine? {
        let indent = line.prefix { $0 == " " }.count
        let text = String(line.dropFirst(indent))
        guard !text.isEmpty, !text.hasPrefix("#"), !text.hasPrefix("\t") else { return nil }
        var quote: Character?
        var escaped = false
        for index in text.indices {
            let character = text[index]
            if escaped { escaped = false; continue }
            if character == "\\", quote == "\"" { escaped = true; continue }
            if character == "\"" || character == "'" {
                if quote == character { quote = nil }
                else if quote == nil { quote = character }
                continue
            }
            if character == ":", quote == nil {
                let next = text.index(after: index)
                guard next == text.endIndex || text[next].isWhitespace else { continue }
                guard let key = scalar(String(text[..<index])) else { return nil }
                let value = stripComment(String(text[next...])).trimmingCharacters(in: .whitespaces)
                return MappingLine(indent: indent, key: key, value: value)
            }
        }
        return nil
    }

    private static func stripComment(_ text: String) -> String {
        var quote: Character?
        var escaped = false
        for index in text.indices {
            let character = text[index]
            if escaped { escaped = false; continue }
            if character == "\\", quote == "\"" { escaped = true; continue }
            if character == "\"" || character == "'" {
                if quote == character { quote = nil }
                else if quote == nil { quote = character }
            } else if character == "#", quote == nil,
                      index == text.startIndex || text[text.index(before: index)].isWhitespace {
                return String(text[..<index])
            }
        }
        return text
    }

    private static func scalar(_ raw: String) -> String? {
        let text = stripComment(raw).trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        if text.hasPrefix("\"") {
            guard let data = text.data(using: .utf8),
                  let value = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) as? String else { return nil }
            return value
        }
        if text.hasPrefix("'") {
            guard text.count >= 2, text.hasSuffix("'") else { return nil }
            let body = String(text.dropFirst().dropLast())
            let value = body.replacingOccurrences(of: "''", with: "'")
            guard !body.replacingOccurrences(of: "''", with: "").contains("'") else { return nil }
            return value
        }
        guard !["null", "Null", "NULL", "~"].contains(text),
              !"!&*[{|>".contains(text.first!) else { return nil }
        return text
    }
}

// MARK: - Persisted state

struct PetState {
    var character: PetCharacter = .deepseek
    var sizeIndex: Int = 1          // index into PetController.sizePresets
    var snapOnRelease: Bool = true
    var soundOn: Bool = true
    var pollSeconds: Double = 30
    var windowOrigin: CGPoint?

    static func load(from url: URL = PetPaths.stateURL) -> PetState {
        var s = PetState()
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return s }
        if let value = obj["character"] as? String, let character = PetCharacter(rawValue: value) {
            s.character = character
        }
        if let v = obj["sizeIndex"] as? Int, (0...3).contains(v) { s.sizeIndex = v }
        if let v = obj["snapOnRelease"] as? Bool { s.snapOnRelease = v }
        if let v = obj["soundOn"] as? Bool { s.soundOn = v }
        if let v = obj["pollSeconds"] as? Double, v.isFinite { s.pollSeconds = min(300, max(10, v)) }
        if let x = obj["originX"] as? Double, let y = obj["originY"] as? Double, x.isFinite, y.isFinite {
            s.windowOrigin = CGPoint(x: x, y: y)
        }
        return s
    }

    func save(to url: URL = PetPaths.stateURL) {
        var obj: [String: Any] = [
            "character": character.rawValue,
            "sizeIndex": min(3, max(0, sizeIndex)),
            "snapOnRelease": snapOnRelease,
            "soundOn": soundOn,
            "pollSeconds": pollSeconds.isFinite ? min(300, max(10, pollSeconds)) : 30,
        ]
        if let o = windowOrigin, o.x.isFinite, o.y.isFinite {
            obj["originX"] = Double(o.x)
            obj["originY"] = Double(o.y)
        }
        if let data = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: url, options: .atomic)
        }
    }
}
