#!/usr/bin/env bash
#
# Verifies that this patched Path of Building tree is usable as a headless
# calculation engine. Run from the repository root.
#
#   ./tools/verify.sh          parse sweep + headless boot
#   ./tools/verify.sh --tests  also run Path of Building's own busted suite
#
# Requires: luajit, and the lua-utf8 module. With --tests, also busted.

set -uo pipefail

cd "$(dirname "$0")/.."
ROOT=$(pwd)
LUA_PATH_ARG="../runtime/lua/?.lua;../runtime/lua/?/init.lua;./?.lua"
fail=0

step() { printf '\n\033[1m== %s\033[0m\n' "$1"; }

# ---------------------------------------------------------------------------
step "Parsing every Lua source"
# Every file must compile. Non-Lua syntax (compound assignment, ?? , ?. , bare
# `continue`) has reached upstream dev before and stops the program booting.
# spec/ is swept too: the same syntax reached a test file, where it surfaces as
# a spec that errors rather than as a parse failure at startup.
broken=0
while IFS= read -r f; do
	if ! err=$(luajit -bl "$f" /dev/null 2>&1 >/dev/null); then
		echo "  BROKEN  $f"
		echo "          ${err#luajit: }"
		broken=$((broken + 1))
	fi
done < <(find src spec -name '*.lua' | sort)

total=$(find src spec -name '*.lua' | wc -l)
if [ "$broken" -eq 0 ]; then
	echo "  ok      $total files parse"
else
	echo "  FAILED  $broken of $total files do not parse"
	fail=1
fi

# ---------------------------------------------------------------------------
step "Booting headless"
# HeadlessWrapper prints its error to stdout and exits 0 on a startup failure,
# so detect the failure banner rather than trusting the exit status.
boot=$(cd src && timeout 900 env LUA_PATH="$LUA_PATH_ARG" luajit HeadlessWrapper.lua 2>&1)
if printf '%s' "$boot" | grep -q 'Error loading main script\|PLoadModule() error'; then
	echo "  FAILED  startup error:"
	printf '%s\n' "$boot" | grep -A3 'Error' | head -8 | sed 's/^/          /'
	fail=1
elif printf '%s' "$boot" | grep -q 'Rares loaded'; then
	echo "  ok      data loaded, program reached idle"
else
	echo "  FAILED  did not reach a known-good state"
	printf '%s\n' "$boot" | tail -5 | sed 's/^/          /'
	fail=1
fi

# ---------------------------------------------------------------------------
step "Comparison proof of concept"
if [ -f poc/compare_poc.lua ]; then
	poc=$(cd src && timeout 900 env LUA_PATH="$LUA_PATH_ARG" luajit ../poc/compare_poc.lua 2>&1)
	changed=$(printf '%s' "$poc" | grep -oE '^[0-9]+ stats changed' | grep -oE '^[0-9]+')
	if [ -n "$changed" ] && [ "$changed" -gt 0 ]; then
		echo "  ok      item comparison returned $changed changed stats"
	else
		echo "  FAILED  comparison produced no stat differences"
		printf '%s\n' "$poc" | tail -5 | sed 's/^/          /'
		fail=1
	fi
else
	echo "  skip    poc/compare_poc.lua not present"
fi

# ---------------------------------------------------------------------------
if [ "${1:-}" = "--tests" ]; then
	step "Path of Building test suite"
	# .busted sets directory = "src", so busted chdirs there itself and specs
	# are addressed as ../spec/... Run from the repository root.
	specfail=0; specpass=0
	for spec in $(find spec/System -name '*_spec.lua' | sort); do
		summary=$(timeout 900 busted --lua=luajit "../$spec" 2>&1 | grep -E '[0-9]+ success' | tail -1)
		if printf '%s' "$summary" | grep -qE '0 failures / 0 errors'; then
			specpass=$((specpass + 1))
		else
			specfail=$((specfail + 1))
			printf '  FAILED  %-44s %s\n' "$(basename "$spec")" "${summary:-no summary}"
		fi
	done
	if [ "$specfail" -eq 0 ]; then
		echo "  ok      $specpass spec files passed"
	else
		echo "  FAILED  $specfail spec files failed, $specpass passed"
		fail=1
	fi
fi

# ---------------------------------------------------------------------------
if [ "$fail" -eq 0 ]; then
	printf '\n\033[32mVERIFY PASSED\033[0m — tree is usable as a headless engine\n'
else
	printf '\n\033[31mVERIFY FAILED\033[0m\n'
fi
exit "$fail"
