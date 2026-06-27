import pkg/[casserole, nort]

import libdump/types

import
  std/
    [tables, strutils, sequtils, sugar, parseopt, strformat, parseutils, options, sets, cmdline, terminal]

export sets

type ArgParser[T] = proc(input: string, result: out T) {.nimcall.}

type
  Flag[T] = object
    name, help: string
    kind: ArgType
    parser: ArgParser[T]

  ArgType = enum
    NamedFlag ## --flag
    Option ## -o
    Argument ## Just anything positional

  InputField = object ## Parsed CLI input
    case kind: ArgType
    of NamedFlag:
      flag: string
    of Option:
      opt: char
    of Argument: discard
    value: string

  CliError = object of CatchableError
  MissingFlag* = object of CliError
    flag: string

  CLIApp[T: tuple] = object
    ## TopLevel to keep track of app metadata.
    ## Also makes things like `--help` and `--version` work
    version: string
    name, description: string
    args: T

proc `$`*(input: InputField): string =
  case input.kind
  of NamedFlag:
    result = fmt"--{input.flag}={input.value}"
  of Option:
    result = fmt"-{input.opt} {input.value}"
  of Argument:
    result = input.value

proc `$`*(inputs: seq[InputField]): string =
  inputs.mapIt($it).join(" ")

let
  flagGram = -e("--") * dot().until(e'=')$key * (?(-e('=') * +dot()))$value
  optGram: Combinator[tuple[key: string, value: Option[string]]] = -e("-") * dot().map(it => $it)$key * (?(-e('=') * +dot()))$value
  combinedGram = flagGram | optGram

proc optional*[T](flag: Flag[T]): bool =
  T is options.Option

proc parseCli*(args: openArray[string]): seq[InputField] =
  ## Parses CLI args passed into the program into something structured.
  ## Currently supports very basic rules (Short and long form have `=` optional)
  ## - `-o=foo` Short form options
  ## - `--flag=bar` Long form flags
  ## - `buzz` Arguments
  var i = 0
  while i < args.len:
    let segment = args[i]
    if Some(matched) ?== combinedGram.match(segment):
      let value =
        if Some(value) ?== matched.value:
          value
        elif matched.key in ["version", "help"]: # TODO: Support flags that don't need values
          ""
        else:
          args[i + 1] # TODO: Index check

      if segment[1] == '-':
        result &= InputField(kind: NamedFlag, flag: matched.key, value: value)
      else:
        result &= InputField(kind: Option, opt: matched.key[0], value: value)

      if matched.value.isNone:
        # We need to skip a segment since we got the value from the next one
        i += 1
    else:
      result &= InputField(kind: Argument, value: segment)
    i += 1

proc parseCliValue*(input: string, result: out string) =
  ## Parses argument as a string
  result = input

proc parseCliValue*(input: string, result: out int) =
  ## Parses argument as an integer
  result = input.parseInt()

proc parseCliValue*[T](input: string, result: out Option[T]) =
  var val: T
  parseCliValue(input, val)
  result = some(val)

proc flag*[T](name, help: string, _: typedesc[T]): Flag[T] =
  Flag[T](name: name, help: help, parser: parseCliValue)

proc flag*(name, help: string): Flag[string] =
  flag(name, help, string)

proc argument*[T](name, help: string, _: typedesc[T]): Flag[T] =
  Flag[T](kind: Argument, name: name, help: help, parser: parseCliValue)

proc argument*(name, help: string): Flag[string] =
  argument(name, help, string)

proc parse*[T: tuple](inputs: seq[InputField], parsers: T): transformFields(T, inp.T) =
  ## Parses CLI inputs into actual data via parsers
  ## `parsers` is meant to be an anonymous tuple of fields to parse

  var
    currentArg = 0
    seen = initHashSet[string]()

  let expectToSee = block:
    var res = initHashSet[string]()
    for _, parser in fieldPairs(parsers):
      if not parser.optional:
        res.incl(parser.name)
    res

  for input in inputs:
    # Go through each input, and for each input go through each parser
    var parserArg = 0 # Track which argument parser we are currently looking it
    var argConsumed = false
      # Only one positional parser should consume each Argument input
    for k1, expected in fieldPairs(parsers):
      for k2, res in fieldPairs(result):
        when k1 == k2: # Match when field names are the same
          let parser: ArgParser[expected.T] = expected.parser
          var isRight = false
          case input.kind
          of NamedFlag:
            # Still need a guard that
            if input.flag == expected.name:
              isRight = true
          of Option:
            if input.opt == expected.name[0]:
              isRight = true
          of Argument:
            if expected.kind == Argument and currentArg == parserArg and not argConsumed:
              isRight = true
              argConsumed = true

          if isRight:
            parser(input.value, res)
            seen.incl(expected.name)

          if expected.kind == Argument:
            parserArg += 1
    if argConsumed:
      currentArg += 1 # Next positional input goes to the next argument parser

  # Check we didn't miss anything
  for missing in expectToSee - seen:
    raise (ref MissingFlag)(flag: missing)

proc parse*[T: tuple](argv: openArray[string], parsers: T): transformFields(T, inp.T) =
  try:
    return argv.parseCli().parse(parsers)
  except MissingFlag as e:
    stderr.writeline(fmt"Missing value for '{e.flag}'")
    quit(QuitFailure)

proc parse*[T: tuple](parsers: T): transformFields(T, inp.T) =
  commandLineParams().parse(parsers)

const NimblePkgVersion {.strdefine.} = "Unknown"

proc initApp*[T](name, description: string, args: T): CLIApp[T] =
  return CLIApp[T](
    name: name,
    version: NimblePkgVersion,
    description: description,
    args: args
  )

proc help(app: CLIApp): string =
  ## Returns the help string for an app
  result = fmt"{app.name} {app.version}"
  result &= "\n\n"
  result &= app.description
  result &= "\n"
  # Generate top level usage
  result &= fmt"Usage: {app.name}"
  for _, info in fieldPairs(app.args):
    result &= " "
    case info.kind
    of Argument:
      result &= "[" & info.name & "]"
    else: discard
    if info.optional:
      result &= "?"

  # Add documentation for each field
  for _, info in fieldPairs(app.args):
    result &= "\n  " & ansiStyleCode(styleBright) & info.name & ansiResetCode & " [" & ansiStyleCode(styleItalic) & $info.T & ansiResetCode & "]: " & info.help

proc parse*[T](app: CLIApp[T]): transformFields(T, inp.T) =
  # Do a first pass to see if the user wants help or the version
  let args = commandLineParams().parseCli()
  for arg in args:
    if arg.kind == NamedFlag and arg.flag == "version":
      echo app.version
      quit QuitSuccess
    if arg.kind == NamedFlag and arg.flag == "help":
      echo app.help
      quit QuitSuccess
  return app.args.parse()
