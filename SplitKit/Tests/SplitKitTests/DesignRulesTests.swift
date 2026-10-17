import Foundation
import Testing

/// Docs/Design.md §9: chrome and styles take every value from the tokens or the style constants.
/// Outside `SplitKitTokens.swift` and `SplitKitStyleConstants.swift`, sources in `Sources/SplitKit/Chrome`
/// and `Sources/SplitKit/Styles` contain no numeric literal other than 0 and 1, no colour built from
/// components or hex, and no fixed-size or custom font. Comments and string literals are ignored.
@Suite struct DesignRulesTests {
    static let packageRoot = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    static let scannedFolders = ["Sources/SplitKit/Chrome", "Sources/SplitKit/Styles"]
    static let valueFiles: Set<String> = ["SplitKitTokens.swift", "SplitKitStyleConstants.swift"]

    @Test func chromeAndStylesContainNoLiteralValues() throws {
        let files = Self.scannedFiles()
        #expect(files.contains { $0.lastPathComponent == "PaneHeaderStyle.swift" }, "scan found no style sources")
        for file in files where !Self.valueFiles.contains(file.lastPathComponent) {
            let source = try String(contentsOf: file, encoding: .utf8)
            let violations = DesignRuleScanner.violations(in: source)
            #expect(violations.isEmpty, "\(file.lastPathComponent): \(violations)")
        }
    }

    @Test func scannerFindsEveryForbiddenForm() {
        let source = """
            let a = 6
            let b = 0.18
            let c = 0x1F
            let d = Color(red: 0, green: 0, blue: 1)
            let e = Color(hex: "#FF0000")
            let f = Font.system(size: 1)
            let g = Text("").font(.system(size: 1))
            let h = NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
            let i = Color(.sRGB, white: 0)
            """
        let violations = DesignRuleScanner.violations(in: source)
        for expected in ["6", "0.18", "0x1F", "Color(red:", "Color(hex:", "Font.system(size:", ".system(size:",
                         "NSColor(srgbRed:", "Color(.sRGB"] {
            #expect(violations.contains(expected), "missed \(expected) in \(violations)")
        }
    }

    @Test func scannerIgnoresAllowedForms() {
        let source = """
            // Design.md §2: 28 pt, Color(red: 1)
            /* 0.5 opacity */
            let a = opacity(isDragged ? Constants.draggedSourceOpacity : 1)
            let b = Spacer(minLength: 0)
            let c = "Copy 2 of 3"
            let d = [0.0, 1.0]
            let e = headerItemSpacing2.value
            """
        #expect(DesignRuleScanner.violations(in: source) == [])
    }

    static func scannedFiles() -> [URL] {
        scannedFolders.flatMap { folder -> [URL] in
            let directory = packageRoot.appending(path: folder)
            guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) else { return [] }
            return enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
        }
    }
}

enum DesignRuleScanner {
    static let forbiddenPatterns = [
        #"(?<![A-Za-z0-9_])0[xX][0-9A-Fa-f_]+"#,
        #"(?<![A-Za-z0-9_.])[0-9][0-9_]*(\.[0-9]+)?([eE][-+]?[0-9]+)?(?![A-Za-z0-9_])"#,
        #"\bColor\(\s*(red|hue|white|hex|\.sRGB|\.displayP3|\.sRGBLinear)\b:?"#,
        #"\bNSColor\(\s*(red|srgbRed|calibratedRed|deviceRed|displayP3Red|hue|calibratedHue|white|calibratedWhite|deviceWhite|hex)\b:?"#,
        #"#colorLiteral"#,
        #"\bFont\.(system\(\s*size|custom)\b:?"#,
        #"(?<![A-Za-z0-9_])\.system\(\s*size\b:?"#,
        #"(?<![A-Za-z0-9_])\.custom\(\s*\""#,
    ]

    /// The forbidden fragments in `source`, in source order per pattern.
    static func violations(in source: String) -> [String] {
        let code = stripCommentsAndStrings(source)
        var found: [String] = []
        for pattern in forbiddenPatterns {
            let regex = try! NSRegularExpression(pattern: pattern)
            for match in regex.matches(in: code, range: NSRange(code.startIndex..., in: code)) {
                let fragment = String(code[Range(match.range, in: code)!])
                if let value = Double(fragment.replacingOccurrences(of: "_", with: "")), value == 0 || value == 1 { continue }
                found.append(fragment)
            }
        }
        return found
    }

    /// Replaces comments and string literal contents with spaces so they are never scanned.
    static func stripCommentsAndStrings(_ source: String) -> String {
        var output = ""
        var index = source.startIndex
        func peek(_ text: String) -> Bool { source[index...].hasPrefix(text) }
        func skip(until terminator: String, keep: String) {
            output += keep
            while index < source.endIndex, !peek(terminator) {
                if source[index] == "\\" { index = source.index(after: index) }
                if index < source.endIndex { index = source.index(after: index) }
            }
            if index < source.endIndex { index = source.index(index, offsetBy: terminator.count) }
            output += keep
        }
        while index < source.endIndex {
            if peek("//") {
                skip(until: "\n", keep: "\n")
            } else if peek("/*") {
                index = source.index(index, offsetBy: 2)
                skip(until: "*/", keep: " ")
            } else if peek("\"\"\"") {
                index = source.index(index, offsetBy: 3)
                skip(until: "\"\"\"", keep: "\"")
            } else if peek("\"") {
                index = source.index(after: index)
                skip(until: "\"", keep: "\"")
            } else {
                output.append(source[index])
                index = source.index(after: index)
            }
        }
        return output
    }
}
