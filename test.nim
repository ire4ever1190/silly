import ./main
import std/[unittest, options]


suite "CLI Parsing":
  test "Basic flag with `=`":
    check $parseCli(["--flag=foo"]) == "--flag=foo"

  test "Flag separated by space":
    check $parseCli(["--flag", "foo"]) == "--flag=foo"

  test "Option with `=`":
    check $parseCli(["-o=foo"]) == "-o foo"

  test "Option separated by space":
    check $parseCli(["-o", "foo"]) == "-o foo"

  test "Argument":
    check $parseCli(["foo"]) == "foo"

suite "Argument Parsing":
  template checkArgs(args: openArray[string], flags: tuple, expected: tuple) =
    check args.parse(flags) == expected

  test "Basic string flags":
    checkArgs(
      ["--foo", "bar"],
      (flag("foo", ""),),
      ("bar",)
    )

  test "Basic option":
    checkArgs(
      ["-o", "bar"],
      (flag("o", ""),),
      ("bar",)
    )

  test "Fields can be out of order":
    checkArgs(
      ["--foo=bar", "--fuzz=buzz"],
      (flag("fuzz", ""), flag("foo", "")),
      ("buzz", "bar")
    )

  test "Arguments are parsed":
    checkArgs(
      ["buzz"],
      (argument("something", ""),),
      ("buzz",)
    )

  test "Arguments are positional":
    checkArgs(
      ["--foo=bar", "arg1", "--fuzz=buzz", "arg2"],
      (argument("arg1", ""), flag("fuzz", ""), flag("foo", ""), argument("arg2", "")),
      ("arg1", "buzz", "bar", "arg2")
    )

  test "Throws error if non-optional flag is missing":
    expect MissingFlag:
      discard [].parseCli().parse((flag("foo", ""),))

  test "Doesn't throw if optional flag is missing":
    discard [].parseCli().parse((flag("foo", "", Option[string]),))
