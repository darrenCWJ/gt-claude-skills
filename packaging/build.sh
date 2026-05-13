#!/bin/bash
# Build the cdo-databricks plugin tarball for the gt-cli plugin registry.
# Usage: ./packaging/build.sh [version]
# Output: dist/cdo-databricks-<version>.tar.gz

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
PACKAGE_NAME="cdo-databricks"
VERSION="${1:-1.0.0}"
DIST_DIR="$REPO_ROOT/dist"
STAGING_DIR="$DIST_DIR/staging/$PACKAGE_NAME"

echo "Building $PACKAGE_NAME@$VERSION..."

# Clean staging area
if [ -d "$DIST_DIR/staging" ]; then
  find "$DIST_DIR/staging" -delete
fi
mkdir -p "$STAGING_DIR"

# Copy plugin manifest
mkdir -p "$STAGING_DIR/.claude-plugin"
cp "$SCRIPT_DIR/plugin.json" "$STAGING_DIR/.claude-plugin/plugin.json"

# Copy skills (rename SKILL.md to descriptive names)
mkdir -p "$STAGING_DIR/skills"
cp "$REPO_ROOT/skills/databricks-lakebase-skill/SKILL.md" "$STAGING_DIR/skills/databricks-lakebase.md"
cp "$REPO_ROOT/skills/databricks-connector-install-skill/SKILL.md" "$STAGING_DIR/skills/databricks-connector-install.md"
cp "$REPO_ROOT/skills/database-migrations-skill/SKILL.md" "$STAGING_DIR/skills/database-migrations.md"

# Copy rules
mkdir -p "$STAGING_DIR/rules/databricks"
cp "$REPO_ROOT/rules/databricks/activation.md" "$STAGING_DIR/rules/databricks/activation.md"
cp "$REPO_ROOT/rules/databricks/patterns.md" "$STAGING_DIR/rules/databricks/patterns.md"
cp "$REPO_ROOT/rules/databricks/frontend-api.md" "$STAGING_DIR/rules/databricks/frontend-api.md"

# Copy hooks
mkdir -p "$STAGING_DIR/hooks"
cp "$REPO_ROOT/hooks/hooks.json" "$STAGING_DIR/hooks/hooks.json"
cp "$REPO_ROOT/hooks/databricks-keyword-hook.sh" "$STAGING_DIR/hooks/databricks-keyword-hook.sh"
cp "$REPO_ROOT/hooks/databricks-pretooluse-hook.sh" "$STAGING_DIR/hooks/databricks-pretooluse-hook.sh"

# Create tarball
mkdir -p "$DIST_DIR"
TARBALL="$DIST_DIR/$PACKAGE_NAME-$VERSION.tar.gz"
tar -czf "$TARBALL" -C "$DIST_DIR/staging" "$PACKAGE_NAME"

# Generate checksum
CHECKSUM=$(shasum -a 256 "$TARBALL" | awk '{print $1}')
SIZE=$(stat -f%z "$TARBALL" 2>/dev/null || stat -c%s "$TARBALL" 2>/dev/null)

echo ""
echo "Built: $TARBALL"
echo "Size: $SIZE bytes"
echo "SHA-256: $CHECKSUM"
echo ""

# Write build info for generate-registry.sh
printf '{\n  "name": "%s",\n  "version": "%s",\n  "tarball": "%s-%s.tar.gz",\n  "checksum": "sha256:%s",\n  "size": %s,\n  "published": "%s"\n}\n' \
  "$PACKAGE_NAME" "$VERSION" "$PACKAGE_NAME" "$VERSION" "$CHECKSUM" "$SIZE" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  > "$DIST_DIR/build-info.json"

echo "Build info: $DIST_DIR/build-info.json"

# Clean staging
find "$DIST_DIR/staging" -delete 2>/dev/null || true

echo ""
echo "Done. Next steps:"
echo "  1. Run: ./packaging/generate-registry.sh"
echo "  2. Run: ./packaging/upload.sh"
