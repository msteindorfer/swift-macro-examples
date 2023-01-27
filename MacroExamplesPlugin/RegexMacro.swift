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
    guard node.argumentList.count == 1, let argumentExpr = node.argumentList.first?.expression else {
      fatalError("compiler bug: the macro does not have exactly one argument")
    }

    guard argumentExpr.is(FunctionCallExprSyntax.self) || argumentExpr.is(RegexLiteralExprSyntax.self) else {
      fatalError("compiler bug: argument is neither of type `Regex`, nor a regex literal")
    }

    // TODO: build up `RegexComponent.regex` instead of `RegexComponent`?
    guard let argument = argumentExpr.as(FunctionCallExprSyntax.self),
          let regexComponent = try? matchAndEvaluateRegex(argument) else {
      return "\(argumentExpr.withoutTrivia())"
    }

    guard let transformedRegexSourceCodeLiteral = try? _openExistential(regexComponent, do: lowerRegexHelper) else {
      return "\(argumentExpr.withoutTrivia())"
    }

    return "\(transformedRegexSourceCodeLiteral)"
  }

  // TODO: how to apply `_openExistential` when needing to concatenate two existential values like in `RegexComponentBuilder.buildPartialBlock(accumulated:next:)`
  static func matchAndEvaluateRegex(_ node: FunctionCallExprSyntax) throws -> any RegexComponent {

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

private func lowerRegexHelper<T: RegexComponent>(_ regexComponent: T) throws -> String {
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
