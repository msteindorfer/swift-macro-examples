import SwiftSyntax
import SwiftSyntaxBuilder
import _SwiftSyntaxMacros

import RegexBuilder         // potentially relevant @_spi(RegexBenchmark)
import _RegexParser
import _StringProcessing    // potentially relevant @_spi(RegexBuilder)

public struct RegexMacro: ExpressionMacro {
  public static func expansion(
    of node: MacroExpansionExprSyntax, in context: inout MacroExpansionContext
  ) -> ExprSyntax {
    guard let argument = node.argumentList.first?.expression.as(FunctionCallExprSyntax.self) else {
      fatalError("compiler bug: the macro does not have any arguments")
    }

    let regexComponent = buildRegex(argument)
    _openExistential(regexComponent, do: openExistentialHelper)
    _openExistential(regexComponent, do: openExistentialMatchHelper)

    return "(\(argument), \(literal: argument.description))"
  }

  static func buildRegex(_ node: FunctionCallExprSyntax) -> any RegexComponent {
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

func openExistentialHelper<T: RegexComponent>(_ regexComponent: T) {
  let regex = regexComponent.regex

  print(regex)
}

func openExistentialMatchHelper<T: RegexComponent>(_ regexComponent: T) {
  let regex = regexComponent.regex

  if let match = try? regex.wholeMatch(in: "Hello World") {
    print("Matched '\(match.output)'.")
  }
}

func buildPartialBlockHelper<T: RegexComponent>(_ regexComponent: T) -> Regex<T.RegexOutput> {
  RegexComponentBuilder.buildPartialBlock(first: regexComponent)
}
