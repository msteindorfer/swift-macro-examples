
import MacroExamplesLib
import RegexBuilder

let x = 1
let y = 2
let z = 3

// "Stringify" macro turns the expression into a string.
func testStringify() {
  print(#stringify(x + y))
}
// "AddBlocker" complains about addition operations. We emit a warning
// so it doesn't block compilation.
func blockAdd() {
  print(#addBlocker(x * y + z))
}

func produceWarning() {
  #myWarning("remember to pass a string literal here")
}
// Uncomment to get an error out of the macro.
//   let text = "oops"
//   #myWarning(text)


struct Font: ExpressibleByFontLiteral {
  init(fontLiteralName: String, size: Int, weight: MacroExamplesLib.FontWeight) {
  }
}

func testFontLiteral() {
  let font: Font = #fontLiteral(name: "Comic Sans", size: 14, weight: .thin)
}

testStringify()
blockAdd()
produceWarning()
testFontLiteral()

let (regex, auxiliary) = #embed(
  Regex {
    OneOrMore(.word)
  }
)
print(regex)
print(auxiliary)
print("abc".wholeMatch(of: regex)!.0)
