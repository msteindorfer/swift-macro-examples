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

  func testRegexEmbedding() {
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
      (
        Regex {
          OneOrMore(.word)
          OneOrMore(.whitespace)
          OneOrMore(.word)
        }, "\\n  Regex {\\n    OneOrMore(.word)\\n    OneOrMore(.whitespace)\\n    OneOrMore(.word)\\n  }")
      """
    )
  }

  @available(macOS 13.0, *)
  func testRegexPlayground() {
  //    Regex.init(<#T##content: () -> RegexComponent##() -> RegexComponent#>)

    // Regex<Regex<(Substring, Regex<OneOrMore<Substring>.RegexOutput>.RegexOutput)>.RegexOutput>
    let patternDesugared = Regex {
      let e0 = RegexComponentBuilder.buildExpression(ZeroOrMore(.whitespace))
      let e1 = Capture {
        // TODO: how to desugar `Capture` into builder API calls?
        RegexComponentBuilder.buildExpression(OneOrMore(.word))
      }
      let r0 = RegexComponentBuilder.buildPartialBlock(first: e0)
      let r1 = RegexComponentBuilder.buildPartialBlock(accumulated: r0, next: e1)
      return r1
    }

    // Regex<Regex<(Substring, Regex<OneOrMore<Substring>.RegexOutput>.RegexOutput)>.RegexOutput>
    let pattern = Regex {
      ZeroOrMore(.whitespace)
      Capture {
        OneOrMore(.word)
      }
    }

  //    if let match = try? pattern.firstMatch(in: "   Hello, World!   ") {
  //      print(match.1)
  //    }

    let matchDesugared = try? patternDesugared.firstMatch(in: "   Hello, World!   ")
    XCTAssertEqual(matchDesugared?.1, "Hello")

    let match = try? pattern.firstMatch(in: "   Hello, World!   ")
    XCTAssertEqual(match?.1, "Hello")


    let _: Regex<Regex<OneOrMore<Substring>.RegexOutput>.RegexOutput> = Regex {
      OneOrMore(.word)
    }
  }
}
