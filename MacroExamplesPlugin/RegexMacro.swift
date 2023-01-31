import SwiftSyntax
import SwiftSyntaxBuilder
import _SwiftSyntaxMacros

import RegexBuilder
import _RegexParser
import _StringProcessing

public struct RegexMacro: ExpressionMacro {
  public static func expansion(
    of node: MacroExpansionExprSyntax, in context: inout MacroExpansionContext
  ) -> ExprSyntax {
    // TODO: build up `RegexComponent.regex` instead of `RegexComponent`?
    guard let regexComponent = try? matchAndEvaluateRegex(node) else {
      return eraseMacro(from: node)
    }

    guard let transformedRegexSourceCodeLiteral = try? _openExistential(regexComponent, do: lowerRegexHelper) else {
      return eraseMacro(from: node)
    }

    return "\(transformedRegexSourceCodeLiteral)"
  }

  private static func eraseMacro(from node: MacroExpansionExprSyntax) -> ExprSyntax {
    return "\(String(describing: node).replacing("#regex", with: "Regex", maxReplacements: 1))"
  }

  static func matchAndEvaluateRegex(_ node: MacroExpansionExprSyntax) throws -> any RegexComponent {

    // MARK: Handle `init(_ pattern: String) throws`

    if node.argumentList.count == 1, let stringLiteralExpr = node.argumentList.first?.expression.as(StringLiteralExpr.self), node.trailingClosure == nil {
      do {
        let pattern = String(describing: stringLiteralExpr.segments)
        return try Regex(pattern)
      } catch {
        throw CustomError.message("`init(_ pattern: String)` threw")
      }
    }

    // MARK: Handle Regex DSL composition with trailing closures

    guard node.argumentList.count == 0, node.trailingClosure != nil else {
      throw MatchError.unspecified
    }

    let regexComponents = try node.trailingClosure!.statements.map {
      guard let node = $0.item.as(ExprSyntax.self) else {
        throw MatchError.unspecified
      }

      guard let regexComponent = try? matchAndEvaluateQuantification(node) else {
        throw MatchError.unspecified
      }

      return regexComponent
    }

    guard let firstRegexComponent = regexComponents.first else { return RegexComponentBuilder.buildBlock() }
    let remainingRegexComponents = regexComponents.dropFirst()

    let firstPartialBlock = _openExistential(firstRegexComponent, do: buildPartialBlockHelper) as any RegexComponent

    let buildNextPartialBlock = { (partialBlock: any RegexComponent, regexComponent: any RegexComponent) in
      RegexComponentBuilder.buildPartialBlock(accumulated: partialBlock, next: regexComponent)
    }
    return remainingRegexComponents.reduce(firstPartialBlock, buildNextPartialBlock)
  }

  // TODO: One:                             component
  // TODO: OneOrMore|ZeroOrMore|Optionally: component x behavior
  // TODO: OneOrMore|ZeroOrMore|Optionally:             behavior x componentBuilder
  // TODO: Repeat:                          component x count (etcetera)
  static func matchAndEvaluateQuantification(_ node: ExprSyntax) throws -> any RegexComponent {
    guard let node = node.as(FunctionCallExprSyntax.self),
          let identifierExpr = node.calledExpression.as(IdentifierExpr.self) else {
      throw MatchError.unspecified
    }

    let firstArgumentIndex = node.argumentList.index(atOffset: 0)
    let firstArgumentExpr = node.argumentList[firstArgumentIndex].expression

    guard let regexComponent = try? matchAndEvaluateCharacterClass(firstArgumentExpr) else {
      throw MatchError.unspecified
    }

    var behavior: RegexRepetitionBehavior? = nil
    var count: Int? = nil

    if node.argumentList.count >= 2 {
      let secondArgumentIndex = node.argumentList.index(atOffset: 1)
      let secondArgumentExpr = node.argumentList[secondArgumentIndex].expression

      behavior = try? matchAndEvaluateRegexRepetitionBehavior(secondArgumentExpr)
      count = try? matchAndEvaluateIntegerLiteral(secondArgumentExpr)
    }

    switch identifierExpr.identifier.text {
    case "One":
      return regexComponent // TODO: check if returning the component directly, instead of `One`, is correct
    case "OneOrMore":
      return OneOrMore(regexComponent, behavior)  // _BuiltinRegexComponent
    case "ZeroOrMore":
      return ZeroOrMore(regexComponent, behavior) // _BuiltinRegexComponent
    case "Optionally":
      return Optionally(regexComponent, behavior) // _BuiltinRegexComponent
    case "Repeat" where count != nil:
      return Repeat(regexComponent, count: count!)
    default:
      throw MatchError.unspecified
    }
  }

  static func matchAndEvaluateRegexRepetitionBehavior(_ node: ExprSyntax) throws -> RegexRepetitionBehavior {
    guard let node = node.as(MemberAccessExprSyntax.self) else {
      throw MatchError.unspecified
    }

    switch node.name.text {
    case "eager":
      return .eager
    case "reluctant":
      return .reluctant
    case "possessive":
      return .possessive
    default:
      throw MatchError.unspecified
    }
  }

  static func matchAndEvaluateCharacterClass(_ node: ExprSyntax) throws -> any RegexComponent {
    guard let node = node.as(MemberAccessExprSyntax.self) else {
      throw MatchError.unspecified
    }

    switch node.name.text {
    case "any":
      return .any
    case "whitespace":
      return .whitespace
    case "word":
      return .word
    default:
      throw MatchError.unspecified
    }
  }

  static func matchAndEvaluateIntegerLiteral(_ node: ExprSyntax) throws -> Int {
    guard let node = node.as(IntegerLiteralExprSyntax.self) else {
      throw MatchError.unspecified
    }

    guard let value = Int(node.digits.text) else {
      throw MatchError.unspecified
    }

    return value
  }
}

private func lowerRegexInstructionsHelper<T: RegexComponent>(_ regexComponent: T) throws -> String {
  let regex = regexComponent.regex

  if let instructions: [UInt64] = try? regex.encodeLoweredProgramInstructions(),
     let descriptions: [String] = try? regex.encodeLoweredProgramInstructions() {

    let zipped = zip(instructions, descriptions)

    let formattedInstructionBlock = zipped.map { (instruction, description) in
      let hexcode = String(instruction, radix: 16, uppercase: true)
      let padding = String(repeating: "0", count: instruction.bitWidth / 4 - hexcode.count)

      return "  0x\(padding)\(hexcode), // > \(description)"
    }.joined(separator: "\n")

    return """
    Regex<Substring>(instructions: [
    \(formattedInstructionBlock)
    ] as [UInt64])
    """
  }

  throw CustomError.message("Unable to extract lowered program instructions.")
}

private func lowerRegexHelper<T: RegexComponent>(_ regexComponent: T) throws -> String {
  let regex = regexComponent.regex

  if let bytes: [UInt8] = try? regex.encodeLoweredProgram() {
    let strideLength = 8
    let formattedBytesBlock = stride(from: 0, to: bytes.count, by: strideLength).map { strideStart in
      let strideEnd = Swift.min(strideStart + strideLength, bytes.count)

      return bytes[strideStart..<strideEnd].map { byte in
        let hexcode = String(byte, radix: 16, uppercase: true)
        let padding = String(repeating: "0", count: byte.bitWidth / 4 - hexcode.count)

        return "0x\(padding)\(hexcode),"
      }.joined(separator: " ")
    }.map { line in "  \(line)" }.joined(separator: "\n")

    return """
    Regex<Substring>(code: [
    \(formattedBytesBlock)
    ])
    """
  }

  throw CustomError.message("Unable to extract lowered program instructions.")
}

// TODO: check why this function leads to a compilation error when part of macro implementation as `private static func`
private func buildPartialBlockHelper<T: RegexComponent>(_ regexComponent: T) -> Regex<T.RegexOutput> {
  RegexComponentBuilder.buildPartialBlock(first: regexComponent)
}

enum MatchError: Error, CustomStringConvertible {
  case unspecified

  var description: String {
    "<unspecified match error>"
  }
}
