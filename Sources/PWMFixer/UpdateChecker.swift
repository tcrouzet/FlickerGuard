import Foundation

enum UpdateChecker {
    private struct Release: Decodable {
        let tagName: String
    }

    static func latestVersion() async throws -> String {
        var request = URLRequest(
            url: URL(string: "https://api.github.com/repos/yilmazonline/PWMFixer/releases/latest")!,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 15
        )
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("PWMFixer/\(AppInfo.version)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(Release.self, from: data).tagName
    }

    static func isNewer(_ latest: String, than current: String) throws -> Bool {
        func components(_ version: String) throws -> [Int] {
            guard version.wholeMatch(of: /(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)/) != nil else {
                throw URLError(.cannotParseResponse)
            }
            let values = version.split(separator: ".").compactMap { Int($0) }
            guard values.count == 3 else { throw URLError(.cannotParseResponse) }
            return values
        }
        return try components(current).lexicographicallyPrecedes(components(latest))
    }
}
