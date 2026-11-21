#!/bin/bash
# Refresh the SwiftPM target from an immutable snnote-lib revision.
set -euo pipefail
[[ $# == 1 ]] || { echo "usage: $0 <snnote-lib checkout>" >&2; exit 2; }
src=$(cd "$1" && pwd -P)
root=$(cd "$(dirname "$0")/.." && pwd -P)
state=$(git --no-optional-locks -C "$src" status --porcelain --untracked-files=all)
[[ -z "$state" ]] || { echo "refusing dirty snnote-lib checkout" >&2; exit 1; }
commit=$(git -C "$src" rev-parse HEAD)
version=$(git -C "$src" describe --tags --always "$commit")
tree=$(mktemp -d "$root/Sources/.CSNNote.XXXXXX")
trap 'rm -rf "$tree"' EXIT
git -C "$src" archive "$commit" src include LICENSE COPYRIGHT | tar -x -C "$tree"
test -s "$tree/include/snnote/snnote.h"
test -s "$tree/src/sn_parser.c"
echo "$version" > "$tree/VERSION"
echo "$commit" > "$tree/COMMIT"
# Swift's Clang importer can read modules in C17 mode. The C objects
# themselves always compile with C23 semantics.
cat > "$tree/include/CSNNote.h" <<'HEADER'
#if !defined(__cplusplus) && __STDC_VERSION__ < 202311L
#include <stdbool.h>
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wc23-extensions"
#include <assert.h>
#define constexpr static const
#include "snnote/snnote.h"
#undef constexpr
#pragma clang diagnostic pop
#else
#include "snnote/snnote.h"
#endif
HEADER
cat > "$tree/include/module.modulemap" <<'MAP'
module CSNNote {
    header "CSNNote.h"
    export *
}
MAP
# macOS renameatx_np exchanges two directory names in one filesystem operation.
python3 - "$tree" "$root/Sources/CSNNote" <<'PY'
import ctypes
import os
import sys

source, dest = map(os.fsencode, sys.argv[1:])
if os.path.exists(dest):
    libc = ctypes.CDLL(None, use_errno=True)
    if libc.renamex_np(source, dest, 2):
        raise OSError(ctypes.get_errno(), "cannot exchange vendored directories")
else:
    os.rename(source, dest)
PY
echo "vendored snnote-lib $version at $commit"
