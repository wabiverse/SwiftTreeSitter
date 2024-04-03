import XCTest

import SwiftTreeSitter
import SwiftTreeSitterLayer
import TestTreeSitterSwift


extension Point {
	init(_ row: Int, _ column: Int) {
		self.init(row: row, column: column)
	}
}

#if !os(WASI)
final class LanguageLayerTests: XCTestCase {
	private static let swiftConfig: LanguageConfiguration = {
		let language = Language(language: tree_sitter_swift())

		let queryText = """
["func"] @keyword.function
["var" "let"] @keyword
"""

		let highlightQuery = try! Query(language: language, data: queryText.data(using: .utf8)!)

		return LanguageConfiguration(language,
									 name: "Swift",
									 queries: [.highlights: highlightQuery])
	}()

	private static let selfInjectingSwiftConfig: LanguageConfiguration = {
		let queryText = """
((line_str_text) @injection.content (#set! injection.language "swift"))
"""
		let injectionQuery = try! Query(language: swiftConfig.language, data: queryText.data(using: .utf8)!)

		var queries = swiftConfig.queries

		queries[.injections] = injectionQuery

		return LanguageConfiguration(swiftConfig.language,
									 name: swiftConfig.name,
									 queries: queries)
	}()
}

extension LanguageLayerTests {
	func testExecuteQuery() throws {
		let config = LanguageLayer.Configuration()
		let tree = try LanguageLayer(languageConfig: Self.swiftConfig, configuration: config)

		let text = """
func main() {
}
"""
		tree.replaceContent(with: text)

		let cursor = try tree.executeQuery(.highlights, in: NSRange(0..<text.utf16.count))
		let highlights = cursor.highlights()

		let expected = [
			NamedRange(name: "keyword.function", range: NSRange(0..<4), pointRange: Point(row: 0, column: 0)..<Point(row: 0, column: 8)),
		]

		XCTAssertEqual(highlights, expected)
	}

	func testSingleInjection() throws {
		let config = LanguageLayer.Configuration(languageProvider: { name in
			precondition(name == "swift")

			return Self.swiftConfig
		})

		let tree = try LanguageLayer(languageConfig: Self.selfInjectingSwiftConfig, configuration: config)

		let text = """
let a = "var a = 1"

func main() {}
"""
		tree.replaceContent(with: text)

		let highlights = try tree.highlights(in: NSRange(0..<text.utf16.count), provider: { _, _ in nil })

		let expected = [
			NamedRange(name: "keyword", range: NSRange(0..<3), pointRange: Point(0, 0)..<Point(0, 6)),
			NamedRange(name: "keyword", range: NSRange(9..<12), pointRange: Point(0, 18)..<Point(0, 24)),
			NamedRange(name: "keyword.function", range: NSRange(21..<25), pointRange: Point(2, 0)..<Point(2, 8)),
		]

		XCTAssertEqual(highlights, expected)
	}

	func testMultipleInjectionsinSameLayer() throws {
		let config = LanguageLayer.Configuration(languageProvider: { name in
			precondition(name == "swift")

			return Self.swiftConfig
		})

		let tree = try LanguageLayer(languageConfig: Self.selfInjectingSwiftConfig, configuration: config)

		let text = """
let a = "var a = 1"
let b = "var b = 1"
"""
		tree.replaceContent(with: text)

		let highlights = try tree.highlights(in: NSRange(0..<text.utf16.count), provider: { _, _ in nil })

		let expected = [
			NamedRange(name: "keyword", range: NSRange(0..<3), pointRange: Point(0, 0)..<Point(0, 6)),
			NamedRange(name: "keyword", range: NSRange(9..<12), pointRange: Point(0, 18)..<Point(0, 24)),
			NamedRange(name: "keyword", range: NSRange(20..<23), pointRange: Point(1, 0)..<Point(1, 6)),
			NamedRange(name: "keyword", range: NSRange(29..<32), pointRange: Point(1, 18)..<Point(1, 24)),
		]

		XCTAssertEqual(highlights, expected)
	}

	func testExpandingQueryRangesByParentMatches() throws {
		let language = Language(language: tree_sitter_swift())

		// this query conflicts with the injection
		let queryText = """
["var" "let"] @keyword
(line_str_text) @string
"""

		let highlightQuery = try! Query(language: language, data: queryText.data(using: .utf8)!)

		let injectionQueryText = """
((line_str_text) @injection.content (#set! injection.language "swift"))
"""
		let injectionQuery = try! Query(language: language, data: injectionQueryText.data(using: .utf8)!)

		let queries: [Query.Definition: Query] = [
			.highlights: highlightQuery,
			.injections: injectionQuery,
		]

		let swiftConfig = LanguageConfiguration(
			language,
			name: "Swift",
			queries: queries
		)

		let config = LanguageLayer.Configuration(languageProvider: { name in
			precondition(name == "swift")

			return swiftConfig
		})

		let tree = try LanguageLayer(languageConfig: swiftConfig, configuration: config)

		let text = """
let a = "var a = 1"
"""
		tree.replaceContent(with: text)

		// target a space within the string. This will match in the root but not in the injection
		let highlights = try tree.highlights(in: NSRange(12..<13), provider: { _, _ in nil })

		let expected = [
			NamedRange(name: "string", range: NSRange(9..<18), pointRange: Point(0, 18)..<Point(0, 36)),
			NamedRange(name: "keyword", range: NSRange(9..<12), pointRange: Point(0, 18)..<Point(0, 24)),
		]

		XCTAssertEqual(highlights, expected)
	}
}

#endif
