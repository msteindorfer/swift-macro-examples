import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import MacroExamplesPlugin
import XCTest

var testMacros: [String: Macro.Type] = [
  "stringify" : StringifyMacro.self,
  "embed" : RegexMacro.self,
]

final class MacroExamplesPluginTests: XCTestCase {
  func testStringify() {
    let sf: SourceFileSyntax =
      #"""
      let a = #stringify(x + y)
      let b = #stringify("Hello, \(name)")
      """#
    let context = BasicMacroExpansionContext.init(
      sourceFiles: [sf: .init(moduleName: "MyModule", fullFilePath: "test.swift")]
    )
    let transformedSF = sf.expand(macros: testMacros, in: context)
    XCTAssertEqual(
      transformedSF.description,
      #"""
      let a = (x + y, "x + y")
      let b = ("Hello, \(name)", #""Hello, \(name)""#)
      """#
    )
  }

  func testRegexEmbedding() {
    let sf: SourceFileSyntax =
      """
      #embed(
        Regex {
          OneOrMore(.word)
        }
      )
      """
    var context = MacroExpansionContext(
      moduleName: "MyModule", fileName: "test.swift"
    )
    let transformedSF = sf.expand(macros: testMacros, in: &context)
    XCTAssertEqual(
      transformedSF.description,
      """
      (
        Regex {
          OneOrMore(.word)
        }, "\\n  Regex {\\n    OneOrMore(.word)\\n  }")
      """
    )
  }
}
