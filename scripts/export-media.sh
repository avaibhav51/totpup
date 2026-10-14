#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
swift build -c debug --product Totpup
media_binary_directory="$(swift build -c debug --show-bin-path)"
"$media_binary_directory/Totpup" --export-media "${PWD}/docs/media"
