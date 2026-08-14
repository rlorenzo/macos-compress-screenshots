#!/bin/bash
#
# update-formula.sh
# Point the Homebrew formula at a released tag and record its checksum.
#
# Usage: ./scripts/update-formula.sh v1.2.0
#
# The tag has to exist on GitHub first - the tarball this downloads is generated
# from it on demand. See HOMEBREW.md ("Cutting a release").
#

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

REPO="rlorenzo/macos-compress-screenshots"
FORMULA="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/Formula/macos-compress-screenshots.rb"

VERSION="${1:-}"
if [ -z "$VERSION" ]; then
    echo -e "${RED}Error: no version given${NC}"
    echo "Usage: $0 vX.Y.Z"
    exit 1
fi

# Accept "1.2.0" as readily as "v1.2.0"; the tag itself carries the v
VERSION="v${VERSION#v}"

if [ ! -f "$FORMULA" ]; then
    echo -e "${RED}Error: formula not found: $FORMULA${NC}"
    exit 1
fi

URL="https://github.com/${REPO}/archive/refs/tags/${VERSION}.tar.gz"

echo "Fetching $URL"
TARBALL=$(mktemp)
trap 'rm -f "$TARBALL"' EXIT

# --fail so a 404 from a tag that was never pushed stops here, rather than
# hashing GitHub's error page and writing a checksum nobody can reproduce
if ! curl --fail --silent --location --output "$TARBALL" "$URL"; then
    echo -e "${RED}Error: could not download $URL${NC}"
    echo "Check that the tag exists and has been pushed:"
    echo "  git tag $VERSION && git push origin $VERSION"
    exit 1
fi

SHA=$(shasum -a 256 "$TARBALL" | awk '{print $1}')
echo "sha256: $SHA"

# The url and sha256 lines are rewritten wholesale rather than patched in place,
# so re-running this is idempotent whatever the previous values were
python3 - "$FORMULA" "$URL" "$SHA" <<'PY'
import re
import sys

formula, url, sha = sys.argv[1], sys.argv[2], sys.argv[3]

with open(formula) as handle:
    text = handle.read()

text, url_count = re.subn(r'^(\s*)url\s+"[^"]*"$',
                          lambda m: f'{m.group(1)}url "{url}"',
                          text, count=1, flags=re.MULTILINE)
text, sha_count = re.subn(r'^(\s*)sha256\s+"[^"]*"$',
                          lambda m: f'{m.group(1)}sha256 "{sha}"',
                          text, count=1, flags=re.MULTILINE)

if url_count != 1 or sha_count != 1:
    sys.exit(f"Could not find a url and sha256 line to update in {formula}")

with open(formula, "w") as handle:
    handle.write(text)
PY

echo -e "${GREEN}✓ Formula updated to ${VERSION}${NC}"
echo
echo "Next:"
echo "  brew style $FORMULA"
echo "  git commit -am 'chore: update formula to ${VERSION}'"
echo
echo "To audit or install it, the formula has to be in a tap."
echo "See HOMEBREW.md (\"Testing the formula locally\")."
