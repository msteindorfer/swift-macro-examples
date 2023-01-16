import RegexBuilder
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

  func testRegexPatternEmbeddingWithOneQuantification() {
    let sf: SourceFileSyntax =
      """
      #embed(Regex("\\w+"))
      """
    var context = MacroExpansionContext(
      moduleName: "MyModule", fileName: "test.swift"
    )
    let transformedSF = sf.expand(macros: testMacros, in: &context)
    XCTAssertEqual(
      transformedSF.description,
      """
      Regex<Substring>(instructions: [
        0x1500000000000000, // > [0] beginCapture 0
        0x1400002008040008, // > [1] quantify builtin 1 unbounded
        0x1600000000000000, // > [2] endCapture 0
        0x1A00000000000000, // > [3] accept
      ] as [UInt64])
      """
    )
  }

  func testRegexDslEmbeddingWithOneQuantification() {
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
      Regex<Substring>(instructions: [
        0x1500000000000000, // > [0] beginCapture 0
        0x1400002008040008, // > [1] quantify builtin 1 unbounded
        0x1600000000000000, // > [2] endCapture 0
        0x1A00000000000000, // > [3] accept
      ] as [UInt64])
      """
    )
  }

  func testRegexDslEmbeddingWithMultipleQuantifications() {
    let sf: SourceFileSyntax =
      """
      #embed(
        Regex {
          OneOrMore(.word)
          OneOrMore(.whitespace)
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
      Regex<Substring>(instructions: [
        0x1500000000000000, // > [0] beginCapture 0
        0x1400002008040008, // > [1] quantify builtin 1 unbounded
        0x1400002008040007, // > [2] quantify builtin 1 unbounded
        0x1400002008040008, // > [3] quantify builtin 1 unbounded
        0x1600000000000000, // > [4] endCapture 0
        0x1A00000000000000, // > [5] accept
      ] as [UInt64])
      """
    )
  }
}
