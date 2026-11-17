import Foundation
import Testing
@testable import FlickerGuard

private func catalog(_ language: String) throws -> [String: String] {
    let url = try #require(AppInfo.resources.url(forResource: "Localizable", withExtension: "strings", subdirectory: nil, localization: language))
    let data = try Data(contentsOf: url)
    return try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String])
}

@Test func englishAndFrenchHaveMatchingKeysAndNamedPlaceholders() throws {
    let english = try catalog("en")
    let french = try catalog("fr")
    #expect(!english.isEmpty)
    #expect(Set(english.keys) == Set(french.keys))
    for key in english.keys {
        let en = try #require(english[key])
        let fr = try #require(french[key])
        #expect(!en.isEmpty && !fr.isEmpty)
        let enNames = Set(en.matches(of: /\{([A-Za-z][A-Za-z0-9_]*)\}/).map { String($0.1) })
        let frNames = Set(fr.matches(of: /\{([A-Za-z][A-Za-z0-9_]*)\}/).map { String($0.1) })
        #expect(enNames == frNames)
    }
    #expect(english["ui.disable"] == "Disable")
    #expect(french["ui.disable"] == "Désactiver")
    #expect(english["ui.hardware"] == "Hardware brightness")
    #expect(french["ui.hardware"] == "Luminosité matérielle")
}

@Test func allLiteralTranslationKeysExistInBothCatalogs() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let sources = root.appendingPathComponent("Sources/FlickerGuard")
    let files = try #require(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
    let keys = Set(try catalog("en").keys)
    let pattern = #/tr\("([A-Za-z][A-Za-z0-9_.]*)"/#
    for case let file as URL in files where file.pathExtension == "swift" {
        let source = try String(contentsOf: file, encoding: .utf8)
        for match in source.matches(of: pattern) {
            #expect(keys.contains(String(match.1)))
        }
    }
}

@Test func translationValuesAreInsertedOnceAndPreserveUnicodeAndLiteralPercentSigns() {
    let template = AppInfo.resources.localizedString(forKey: "diag.model", value: nil, table: nil)
    for value in ["Écran OLED", "👩🏽‍💻", "{value} {code}", "%@ %d 100%", "\0\n{value}", "مرحبا", String(repeating: "é", count: 4096)] {
        #expect(tr("diag.model", ["value": value]) == template.replacingOccurrences(of: "{value}", with: value))
    }
    #expect(!tr("error.hardwareMaximum").contains("{value}"))
}

@Test func packagedVersionIsAvailableAndHasThreeNumericComponents() {
    #expect(AppInfo.version.wholeMatch(of: /[0-9]+\.[0-9]+\.[0-9]+/) != nil)
}
