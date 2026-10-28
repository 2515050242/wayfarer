// Learn more about moon.mod configuration:
// https://docs.moonbitlang.com/en/latest/toolchain/moon/module.html
//
// To add a dependency, run this command in your terminal:
//   moon add moonbitlang/x
//
// Or manually declare it in `import`, for example:
// import {
//   "moonbitlang/x@0.4.6",
// }

name = "2515050242/wayfarer"

version = "0.1.0"

readme = "README.md"

repository = "https://github.com/2515050242/wayfarer"

license = "Apache-2.0"

keywords = [
  "csv",
  "data-quality",
  "dataset-profile",
  "gtfs",
  "json-profile",
  "validation",
]

preferred_target = "wasm"

description = "A MoonBit CSV dataset-contract toolkit with JSON profiles and bounded GTFS Schedule checks."

import {
  "moonbitlang/x@0.5.6",
}
