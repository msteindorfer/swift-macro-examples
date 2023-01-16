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
    guard node.argumentList.count == 1, let argument = node.argumentList.first?.expression.as(FunctionCallExprSyntax.self) else {
      fatalError("compiler bug: the macro does not have exactly one argument")
    }

    guard let regexComponent = try? buildRegex(argument) else {
      return "\(argument.withoutTrivia())"
    }

    guard let transformedRegexSourceCodeLiteral = try? _openExistential(regexComponent, do: lowerRegexHelper) else {
      return "\(argument.withoutTrivia())"
    }

    return "\(transformedRegexSourceCodeLiteral)"
  }

  // TODO: how to apply `_openExistential` when needing to concatenate two existential values like in `RegexComponentBuilder.buildPartialBlock(accumulated:next:)`
  static func buildRegex(_ node: FunctionCallExprSyntax) throws -> any RegexComponent {

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

    let regexComponents = node.trailingClosure!.statements.map {
      let node = $0.item.as(FunctionCallExprSyntax.self)!
      return buildQuantification(node)
    }

    guard let firstRegexComponent = regexComponents.first else { return RegexComponentBuilder.buildBlock() }
    let remainingRegexComponents = regexComponents.dropFirst()

    let firstPartialBlock = _openExistential(firstRegexComponent, do: buildPartialBlockHelper) as any RegexComponent

    let buildNextPartialBlock = { (partialBlock: any RegexComponent, regexComponent: any RegexComponent) in
      RegexComponentBuilder.buildPartialBlock(accumulated: partialBlock, next: regexComponent)
    }
    return remainingRegexComponents.reduce(firstPartialBlock, buildNextPartialBlock)
  }

  static func buildQuantification(_ node: FunctionCallExprSyntax) -> any RegexComponent {
    let identifier = node.calledExpression.as(IdentifierExpr.self)!.identifier

    let memberAccessExpr = node.argumentList.first!.as(TupleExprElementSyntax.self)!.expression.as(MemberAccessExprSyntax.self)!
    let regexComponent: any RegexComponent = buildCharacterClass(memberAccessExpr)

    switch identifier.text {
    case "ZeroOrMore":
      return ZeroOrMore(regexComponent)
    case "OneOrMore":
      return OneOrMore(regexComponent)
    default:
      fatalError()
    }
  }

  static func buildCharacterClass(_ node: MemberAccessExprSyntax) -> any RegexComponent {
    switch node.name.text {
    case "any":
      return .any
    case "whitespace":
      return .whitespace
    case "word":
      return .word
    default:
      fatalError()
    }
  }
}

private func lowerRegexHelper<T: RegexComponent>(_ regexComponent: T) throws -> String {
  let regex = regexComponent.regex

  if let instructions: [UInt64] = try? regex.encodeLoweredProgramInstructions(),
     let descriptions: [String] = try? regex.encodeLoweredProgramInstructions() {

    let zipped = zip(instructions, descriptions)

    let formattedInstructionBlock = zipped.map { (instruction, description) in
      "  0x\(String(instruction, radix: 16, uppercase: true)), // > \(description)"
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
