#!/bin/bash

set -e

LAMBDA_DIR="../modules/iot/lambda_history"
BUILD_DIR="../modules/iot/lambda_history_build"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

pip install -r "$LAMBDA_DIR/requirements.txt" -t "$BUILD_DIR"

cp "$LAMBDA_DIR/handler.py" "$BUILD_DIR/handler.py"

echo "Lambda history build listo"