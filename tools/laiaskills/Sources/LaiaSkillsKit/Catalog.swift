import Foundation

/// One skills.sh search result.
public struct CatalogResult: Codable, Sendable, Equatable {
    /// `owner/repo`, lowercased by skills.sh.
    public let source: String
    public let skillId: String
    public let name: String?
    public let installs: Int?

    public init(source: String, skillId: String, name: String? = nil, installs: Int? = nil) {
        self.source = source
        self.skillId = skillId
        self.name = name
        self.installs = installs
    }

    /// `third-party/<owner>__<repo>`, the submodule path the source would get.
    public var submodulePath: String? { (try? SourceSpec(source)).map(\.submodulePath) }
}

public enum CatalogError: Error, CustomStringConvertible {
    case queryTooShort
    case requestFailed(String)
    case unreadable

    public var description: String {
        let fallback = "browse a repo directly with `laiaskills browse owner/repo`"
        switch self {
        case .queryTooShort: return "the search needs at least 2 characters"
        case let .requestFailed(detail): return "skills.sh search failed (\(detail)); \(fallback)"
        case .unreadable: return "skills.sh returned a response laiaskills can't read (its API may have changed); \(fallback)"
        }
    }
}

/// Search over skills.sh. Its API is undocumented, so this is the only code that calls it, and decoding
/// only requires `source` and `skillId`. Nothing else in laiaskills depends on a catalog.
public enum Catalog {
    public static let defaultEndpoint = "https://skills.sh/api/search"
    /// Overrides the endpoint; tests point it at a `file://` fixture (curl ignores the query there).
    public static let endpointVariable = "LAIASKILLS_CATALOG_URL"
    public static let unsupported = "unsupported"

    public static var endpoint: String {
        ProcessInfo.processInfo.environment[endpointVariable] ?? defaultEndpoint
    }

    public static func search(_ query: String, limit: Int, endpoint: String = Catalog.endpoint) throws -> [CatalogResult] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else { throw CatalogError.queryTooShort }
        let result = try Shell.run(["curl", "-sS", "--fail", "--max-time", "15", url(trimmed, limit: limit, endpoint: endpoint)])
        guard result.succeeded else {
            throw CatalogError.requestFailed(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return try decode(result.stdoutData)
    }

    static func url(_ query: String, limit: Int, endpoint: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+?#")
        let encoded = query.addingPercentEncoding(withAllowedCharacters: allowed) ?? query
        return "\(endpoint)?q=\(encoded)&limit=\(limit)"
    }

    /// Results with a `source` and `skillId`, in the order given (relevance). Other entries are skipped.
    public static func decode(_ data: Data) throws -> [CatalogResult] {
        struct Entry: Decodable {
            let source: String?
            let skillId: String?
            let name: String?
            let installs: Int?
        }
        struct Response: Decodable {
            let skills: [Entry]
        }
        guard let response = try? JSONDecoder().decode(Response.self, from: data) else { throw CatalogError.unreadable }
        return response.skills.compactMap { entry in
            guard let source = entry.source, let skillId = entry.skillId, !source.isEmpty, !skillId.isEmpty else { return nil }
            return CatalogResult(source: source, skillId: skillId, name: entry.name, installs: entry.installs)
        }
    }

    /// `managed` when the skill is in `skills.json` from this source, `name taken` when a skill with that
    /// name comes from elsewhere, `source added` when only its repo is a submodule, `unsupported` for
    /// sources that are websites, not git repos (skills.sh also lists `.well-known` endpoints), `—` otherwise. Ignores
    /// case: skills.sh lowercases sources.
    public static func status(of result: CatalogResult, skills: [String: SkillEntry], submodules: [Submodule]) -> String {
        guard let path = result.submodulePath?.lowercased() else { return unsupported }
        if let entry = skills.first(where: { $0.key.lowercased() == result.skillId.lowercased() })?.value {
            return entry.source.lowercased() == path ? "managed" : "name taken"
        }
        return submodules.contains { $0.path.lowercased() == path } ? "source added" : "—"
    }
}
