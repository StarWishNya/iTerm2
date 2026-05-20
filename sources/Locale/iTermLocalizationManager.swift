//
//  iTermLocalizationManager.swift
//  iTerm2 - Runtime Menu Localization
//
//  This implementation loads .strings files from .lproj bundles at runtime
//  and applies translations to the main menu bar without modifying XIB files.
//
//  Pattern adapted from sources/MainMenu/MainMenuMangler.swift (lines 364-394)
//  Hook point: iTermApplicationDelegate.m applicationDidFinishLaunching:
//
//  Usage:
//    iTermLocalizationManager.shared.loadAndApplyLocalization()
//
//  To add new languages:
//    1. Create new directory: iTerm2/XX.lproj/ (e.g., iTerm2/ja.lproj/)
//    2. Copy zh_CN.lproj/MainMenu.strings as template
//    3. Translate all values to the target language
//    4. Xcode will automatically include it in the app bundle
//    5. No code changes required!
//

import Foundation
import AppKit

@objc(iTermLocalizationManager)
final class iTermLocalizationManager: NSObject {
    @objc static let shared = iTermLocalizationManager()
    
    private var translations: [String: String] = [:]
    private var isLocalized = false
    
    // MARK: - Public Interface
    
    /// Main entry point: detect system language and apply localizations
    @objc
    func loadAndApplyLocalization() {
        guard !isLocalized else {
            DLog("Localization already applied, skipping")
            return
        }
        
        // Get the user's preferred language(s)
        let preferredLanguages = NSLocale.preferredLanguages
        guard !preferredLanguages.isEmpty else {
            DLog("No preferred languages found")
            return
        }
        
        // Try each preferred language in order of preference
        for languageCode in preferredLanguages {
            // Convert language code to .lproj directory name
            let lprojName = lprojDirectoryName(for: languageCode)
            
            if loadTranslations(forLprojDirectory: lprojName) {
                applyLocalizations(to: NSApp.mainMenu)
                isLocalized = true
                DLog("Applied localizations for language: \(languageCode) (directory: \(lprojName))")
                return
            }
        }
        
        DLog("No localizations found for preferred languages: \(preferredLanguages)")
    }
    
    // MARK: - Private: Language Detection
    
    /// Convert system language code to iTerm2 .lproj directory name
    /// Examples: "zh-Hans" → "zh_CN", "ja" → "ja", "en" → "en"
    private func lprojDirectoryName(for languageCode: String) -> String {
        // Map full language codes to .lproj directory names
        let components = languageCode.components(separatedBy: "-")
        guard !components.isEmpty else { return languageCode }
        
        let language = components[0]
        
        // Handle specific mappings for complex language codes
        if languageCode.hasPrefix("zh") {
            // Simplified Chinese
            if languageCode.contains("Hans") {
                return "zh_CN"
            }
            // Traditional Chinese
            if languageCode.contains("Hant") {
                return "zh_TW"
            }
        }
        
        // Default: use first component (language code)
        return language
    }
    
    // MARK: - Private: Loading Translations

    /// Load translations from a specific .lproj directory's .strings files
    private func loadTranslations(forLprojDirectory lprojName: String) -> Bool {
        guard let bundleURL = Bundle.main.url(forResource: lprojName, withExtension: "lproj") else {
            return false
        }

        guard let bundle = Bundle(url: bundleURL) else {
            return false
        }

        // Load all .strings files from the lproj directory
        let stringsFiles = ["MainMenu", "PreferencePanel", "AddressBook",
                           "PseudoTerminal", "configPanel", "iTerm"]
        var allTranslations: [String: String] = [:]

        for fileName in stringsFiles {
            guard let stringsPath = bundle.path(forResource: fileName, ofType: "strings"),
                  let content = try? String(contentsOfFile: stringsPath, encoding: .utf8) else {
                continue
            }
            let parsed = parseStringsFile(content)
            allTranslations.merge(parsed) { _, new in new }
        }

        translations = allTranslations
        return !translations.isEmpty
    }
    
    // MARK: - Private: String File Parsing
    
    /// Parse macOS .strings file format: "key" = "value";
    /// Handles escape sequences and multi-line comments
    private func parseStringsFile(_ content: String) -> [String: String] {
        var result: [String: String] = [:]
        let lines = content.components(separatedBy: .newlines)
        
        var i = 0
        while i < lines.count {
            let line = lines[i].trimmingCharacters(in: .whitespaces)
            
            // Skip empty lines and comments
            if line.isEmpty || line.hasPrefix("/*") {
                // Skip multi-line comment
                while i < lines.count && !lines[i].contains("*/") {
                    i += 1
                }
                i += 1
                continue
            }
            
            // Parse "key" = "value"; format
            if let (key, value) = parseStringLine(line) {
                result[key] = value
            }
            
            i += 1
        }
        
        return result
    }
    
    /// Parse a single line in .strings format: "key" = "value";
    private func parseStringLine(_ line: String) -> (String, String)? {
        // Format: "key" = "value";
        guard line.hasSuffix(";") else { return nil }

        // Find the pattern: "..." = "..."
        // Split on " = " to handle values containing =
        guard let separatorRange = line.range(of: "\" = \"") else {
            return nil
        }

        let keyPart = String(line[line.startIndex..<separatorRange.lowerBound]) + "\""
        let valuePart = "\"" + String(line[separatorRange.upperBound..<line.endIndex])

        guard let key = extractQuotedString(keyPart),
              let value = extractQuotedString(valuePart) else {
            return nil
        }

        return (key, value)
    }
    
    /// Extract a quoted string and handle escape sequences
    private func extractQuotedString(_ str: String) -> String? {
        let trimmed = str.trimmingCharacters(in: CharacterSet(charactersIn: "\";"))
        
        // Handle escape sequences: \n, \t, \", \\
        var result = ""
        var i = trimmed.startIndex
        
        while i < trimmed.endIndex {
            if trimmed[i] == "\\" && trimmed.index(after: i) < trimmed.endIndex {
                let next = trimmed.index(after: i)
                switch trimmed[next] {
                case "n":
                    result.append("\n")
                    i = trimmed.index(after: next)
                case "t":
                    result.append("\t")
                    i = trimmed.index(after: next)
                case "\"":
                    result.append("\"")
                    i = trimmed.index(after: next)
                case "\\":
                    result.append("\\")
                    i = trimmed.index(after: next)
                default:
                    result.append(trimmed[i])
                    i = trimmed.index(after: i)
                }
            } else {
                result.append(trimmed[i])
                i = trimmed.index(after: i)
            }
        }
        
        return result
    }
    
    // MARK: - Private: Menu Traversal and Localization
    
    /// Recursively traverse the menu and apply translations
    /// Pattern from: sources/MainMenu/MainMenuMangler.swift lines 364-394
    private func applyLocalizations(to menu: NSMenu?) {
        guard let menu = menu else { return }
        
        for item in menu.items {
            // Skip separator items
            if item.isSeparatorItem {
                continue
            }
            
            // Translate the item's title if we have a translation
            if let translation = translations[item.title] {
                item.title = translation
            }
            
            // Recursively process submenus
            if item.hasSubmenu, let submenu = item.submenu {
                applyLocalizations(to: submenu)
            }
        }
    }
}

// MARK: - Integration Helper

extension iTermApplicationDelegate {
    /// Call this from applicationDidFinishLaunching: to apply menu localizations
    @objc
    func localizeMainMenu() {
        iTermLocalizationManager.shared.loadAndApplyLocalization()
    }
}
