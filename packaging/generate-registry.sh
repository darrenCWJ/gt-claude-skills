#!/bin/bash
# Generate registry.json and metadata.json from build-info.json.
# Usage: ./packaging/generate-registry.sh
# Reads: dist/build-info.json
# Output: dist/registry/plugins/registry.json
#         dist/registry/plugins/packages/<name>/metadata.json

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
DIST_DIR="$REPO_ROOT/dist"
BUILD_INFO="$DIST_DIR/build-info.json"

if [ ! -f "$BUILD_INFO" ]; then
  echo "Error: $BUILD_INFO not found. Run ./packaging/build.sh first."
  exit 1
fi

# Read build info
PACKAGE_NAME=$(python3 -c "import json; print(json.load(open('$BUILD_INFO'))['name'])")
VERSION=$(python3 -c "import json; print(json.load(open('$BUILD_INFO'))['version'])")
TARBALL=$(python3 -c "import json; print(json.load(open('$BUILD_INFO'))['tarball'])")
CHECKSUM=$(python3 -c "import json; print(json.load(open('$BUILD_INFO'))['checksum'])")
SIZE=$(python3 -c "import json; print(json.load(open('$BUILD_INFO'))['size'])")
PUBLISHED=$(python3 -c "import json; print(json.load(open('$BUILD_INFO'))['published'])")

REGISTRY_DIR="$DIST_DIR/registry/plugins"
PACKAGE_DIR="$REGISTRY_DIR/packages/$PACKAGE_NAME"

mkdir -p "$REGISTRY_DIR"
mkdir -p "$PACKAGE_DIR"

# Read description from plugin.json
DESCRIPTION=$(python3 -c "import json; print(json.load(open('$SCRIPT_DIR/plugin.json'))['description'])")

# Generate registry.json
python3 << PYEOF
import json

registry = {
    "schemaVersion": 1,
    "generatedAt": "$PUBLISHED",
    "packages": [
        {
            "name": "$PACKAGE_NAME",
            "description": "$DESCRIPTION",
            "latest": "$VERSION",
            "published": "$PUBLISHED"
        }
    ]
}

with open("$REGISTRY_DIR/registry.json", "w") as f:
    json.dump(registry, f, indent=2)
    f.write("\n")
PYEOF

echo "Generated: $REGISTRY_DIR/registry.json"

# Generate metadata.json
python3 << PYEOF
import json

metadata = {
    "name": "$PACKAGE_NAME",
    "description": "$DESCRIPTION",
    "latest": "$VERSION",
    "versions": {
        "$VERSION": {
            "tarball": "$TARBALL",
            "published": "$PUBLISHED",
            "checksum": "$CHECKSUM",
            "size": $SIZE
        }
    }
}

with open("$PACKAGE_DIR/metadata.json", "w") as f:
    json.dump(metadata, f, indent=2)
    f.write("\n")
PYEOF

echo "Generated: $PACKAGE_DIR/metadata.json"

# Copy tarball to registry structure
cp "$DIST_DIR/$TARBALL" "$PACKAGE_DIR/$TARBALL"
echo "Copied:    $PACKAGE_DIR/$TARBALL"

echo ""
echo "Registry structure ready at: $DIST_DIR/registry/"
echo ""
echo "Upload structure:"
echo "  plugins/registry.json"
echo "  plugins/packages/$PACKAGE_NAME/metadata.json"
echo "  plugins/packages/$PACKAGE_NAME/$TARBALL"
echo ""
echo "Next: ./packaging/upload.sh"
