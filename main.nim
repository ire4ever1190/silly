import pkg/[casserole, nort]

import libdump/types

import std/[tables, strutils, sequtils, sugar, parseopt, strformat, parseutils, options]

#[
 ahead of time:
   - name
   - help
   - type
   - required

]#

type ArgParser[T] = proc (input: string, result: out T) {.nimcall.}

type
  Flag[T] = object
    name, help: string
    kind: ArgType
    parser: ArgParser[T]

  ArgType = enum
    NamedFlag ## --flag
    Option ## -o
    Argument ## Just anything positional

  InputField = object
    ## Parsed CLI input
    case kind: ArgType
    of NamedFlag:
      flag: string
    of Option:
      opt: char
    of Argument: discard
    value: string

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
      let value = if Some(value) ?== matched.value: value
                  else: args[i + 1] # TODO: Index check

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

  var currentArg = 0

  for input in inputs:
    # Go through each input, and for each input go through each parser
    var parserArg = 0 # Track which argument parser we are currently looking it
    var argConsumed = false # Only one positional parser should consume each Argument input
    for k1, expected in fieldPairs(parsers):
      for k2, res in fieldPairs(result):
        when k1 == k2: # Match when field names are the same
          let parser: ArgParser[expected.T] = expected.parser
          case input.kind
          of NamedFlag:
            # Still need a guard that
            if input.flag == expected.name:
              parser(input.value, res)
          of Option:
            if input.opt == expected.name[0]:
              parser(input.value, res)
          of Argument:
            if expected.kind == Argument and currentArg == parserArg and not argConsumed:
              parser(input.value, res)
              argConsumed = true
          if expected.kind == Argument:
            parserArg += 1
    if argConsumed:
      currentArg += 1 # Next positional input goes to the next argument parser

proc parse*[T: tuple](argv: openArray[string], parsers: T): transformFields(T, inp.T) =
  argv.parseCli().parse(parsers)
