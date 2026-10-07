.PHONY: test spec-coverage clean

# The G1 tool lives in nimtype and takes the repository root as its argument.
SPEC_COVERAGE_SRC := ../nimtype/tests/tools/spec_coverage.nim

test:
	@mkdir -p bin/tests
	@set -e; for t in tests/external/test_*.nim; do \
	  echo "== $$t"; \
	  nim c -r --hints:off -o:bin/tests/$$(basename $$t .nim) $$t; \
	done

# Its stdout IS docs/quality/g1-spec-coverage.md. Exits non-zero on any
# uncovered or undeclared-but-tagged ID.
spec-coverage:
	@mkdir -p bin/tools
	nim c --hints:off -o:bin/tools/spec_coverage $(SPEC_COVERAGE_SRC)
	./bin/tools/spec_coverage . > docs/quality/g1-spec-coverage.md

clean:
	rm -rf bin nimcache
