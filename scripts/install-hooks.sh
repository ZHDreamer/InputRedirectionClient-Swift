#!/bin/zsh
set -eu
cd "${0:A:h}/.."
git config --local core.hooksPath .githooks
echo "Installed pre-commit hook: staged Swift files will be formatted with swift-format."
