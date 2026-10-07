# Package
version       = "0.1.0"
author        = "jasagiri"
description   = "Property-based testing: values generated from a seed, counterexamples shrunk to the smallest that still fails"
license       = "Apache-2.0"
srcDir        = "src"

# Dependencies
requires "nim >= 2.0.0"

task test, "Run the test suite":
  exec "make test"
