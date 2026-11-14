#!/bin/sh
# Prints CHANGELOG.md's entries for one version (every "## X.Y.Z (build N)"
# section), for the GitHub release, without the internal notes (which phone a
# build was installed on, which branch it came from). A -rc tag uses the version it leads to.
# usage: Tools/release_notes.sh v0.13.0[-rc.1]
set -e
VERSION=$(echo "${1#v}" | sed 's/-.*//')
awk -v v="$VERSION" '
  /^## / { on = index($0, "## " v " ") == 1 }
  on && /^## / { sub(/^## [^ ]+ \(build /, "### Build "); sub(/\),/, ","); print; next }
  on && !/Installed on the iPhone/ && !/^Branch / { print }
' "$(dirname "$0")/../CHANGELOG.md"
