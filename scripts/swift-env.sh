#!/bin/bash
# Can be sourced by build scripts or used as a command wrapper.
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
    printf '%s\n' 'Mouse Light Off requires macOS.' >&2
    exit 1
fi

# Use full Xcode when available so XCTest can run with the same SDK.
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    if [[ $# -eq 0 ]]; then
        printf '%s\n' 'Usage: scripts/swift-env.sh <command> [arguments...]' >&2
        exit 1
    fi
    exec "$@"
fi
