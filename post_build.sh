#!/bin/bash
set -e

BUILD_DIR="build/web"
TIMESTAMP=$(date +%Y%m%d%H%M%S)

# Option 1: append timestamp as query param
sed -i "s|main.dart.js|main.dart.js?v=${TIMESTAMP}|g" ${BUILD_DIR}/index.html

echo "✅ Added timestamp ?v=${TIMESTAMP} to main.dart.js in index.html"