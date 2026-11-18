import Foundation

enum AppInfo {
    static let resources = Bundle.module
    static let documentationURL = URL(string: "https://github.com/tcrouzet/FlickerGuard#readme")!
    static let issuesURL = URL(string: "https://github.com/tcrouzet/FlickerGuard/issues/new")!
    static let downloadURL = URL(string: "https://github.com/tcrouzet/FlickerGuard/releases/latest/download/FlickerGuard.app.zip")!
    static let version: String = {
        guard let url = resources.url(forResource: "Version", withExtension: "txt"),
              let value = try? String(contentsOf: url, encoding: .utf8) else { return "development" }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }()
}

func tr(_ key: String, _ values: [String: String] = [:]) -> String {
    let template = AppInfo.resources.localizedString(forKey: key, value: nil, table: nil)
    return template.replacing(/\{([A-Za-z][A-Za-z0-9_]*)\}/) { match in
        values[String(match.1)] ?? String(match.0)
    }
}
