#!/bin/bash
# Upload the plugin registry files to S3.
# Usage: ./packaging/upload.sh
#
# Required environment variables:
#   AWS_ACCESS_KEY_ID
#   AWS_SECRET_ACCESS_KEY
#   AWS_S3_ENDPOINT (e.g. https://minio.cli-assets--s9znv7kt5lt6.fs5pmkc8jx.code.run:443)
#
# Uploads to s3://gt-cli-assets/plugins/

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
DIST_DIR="$REPO_ROOT/dist"
REGISTRY_DIR="$DIST_DIR/registry"

# Validate
if [ ! -d "$REGISTRY_DIR/plugins" ]; then
  echo "Error: Registry not found at $REGISTRY_DIR/plugins"
  echo "Run ./packaging/generate-registry.sh first."
  exit 1
fi

if [ -z "${AWS_ACCESS_KEY_ID:-}" ] || [ -z "${AWS_SECRET_ACCESS_KEY:-}" ]; then
  echo "Error: AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY must be set."
  echo ""
  echo "Set these environment variables:"
  echo "  export AWS_ACCESS_KEY_ID=<your_access_key>"
  echo "  export AWS_SECRET_ACCESS_KEY=<your_secret_key>"
  echo "  export AWS_S3_ENDPOINT=<https://your-minio-endpoint>"
  exit 1
fi

ENDPOINT_FLAG=""
if [ -n "${AWS_S3_ENDPOINT:-}" ]; then
  ENDPOINT_FLAG="--endpoint-url ${AWS_S3_ENDPOINT}"
fi

BUCKET="gt-cli-assets"

echo "Uploading plugin registry to s3://$BUCKET/plugins/..."
echo ""

# Upload registry.json
echo "  plugins/registry.json"
aws s3 cp "$REGISTRY_DIR/plugins/registry.json" \
  "s3://$BUCKET/plugins/registry.json" \
  $ENDPOINT_FLAG \
  --content-type application/json \
  --no-progress

# Upload package files
for PACKAGE_DIR in "$REGISTRY_DIR/plugins/packages"/*/; do
  PACKAGE_NAME=$(basename "$PACKAGE_DIR")

  echo "  plugins/packages/$PACKAGE_NAME/metadata.json"
  aws s3 cp "$PACKAGE_DIR/metadata.json" \
    "s3://$BUCKET/plugins/packages/$PACKAGE_NAME/metadata.json" \
    $ENDPOINT_FLAG \
    --content-type application/json \
    --no-progress

  # Upload tarballs
  for TARBALL in "$PACKAGE_DIR"*.tar.gz; do
    if [ -f "$TARBALL" ]; then
      TARBALL_NAME=$(basename "$TARBALL")
      echo "  plugins/packages/$PACKAGE_NAME/$TARBALL_NAME"
      aws s3 cp "$TARBALL" \
        "s3://$BUCKET/plugins/packages/$PACKAGE_NAME/$TARBALL_NAME" \
        $ENDPOINT_FLAG \
        --content-type application/gzip \
        --no-progress
    fi
  done
done

echo ""
echo "Upload complete."
echo ""
echo "Plugin is now available at:"
echo "  https://cli-assets.gto.tech.gov.sg/plugins/registry.json"
echo "  https://cli-assets.gto.tech.gov.sg/plugins/packages/cdo-databricks/metadata.json"
echo ""
echo "Users can install with:"
echo "  gt claude skills install cdo-databricks"
