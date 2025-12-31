#!/bin/bash
set -e

# This script will be run when the Docker container starts
# It will execute the ting-tong-test container with the specified parameters

echo "Starting Ting Tong Action..."
echo "Rules path: $1"
echo "Inline rules: $2"
echo "Rules file: $3"

# The rules path from input
RULES_PATH="${1:-/rules}"
INLINE_RULES="$2"
RULES_FILE="${3:-custom-rule.yaml}"

echo "Processing rules configuration..."

# Create a directory to consolidate all rules
CONSOLIDATED_RULES_DIR="/tmp/consolidated-rules"
mkdir -p "$CONSOLIDATED_RULES_DIR"

# Copy built-in rules to consolidated directory if they exist
if [ -d "/app/built-in-rules" ]; then
    echo "Copying built-in rules..."
    cp -r /app/built-in-rules/* "$CONSOLIDATED_RULES_DIR/" 2>/dev/null || echo "No built-in rules found or directory is empty"
fi

# If inline rules are provided, add them to the consolidated directory
if [ -n "$INLINE_RULES" ] && [ "$INLINE_RULES" != "" ]; then
    echo "Adding custom rules from inline rules..."
    echo "$INLINE_RULES" > "$CONSOLIDATED_RULES_DIR/$RULES_FILE"
fi

# If a user provides a rules path and it exists, copy those rules as well
if [ -n "$RULES_PATH" ] && [ "$RULES_PATH" != "" ] && [ -d "$RULES_PATH" ]; then
    echo "Adding user-provided rules from: $RULES_PATH"
    cp -r "$RULES_PATH"/* "$CONSOLIDATED_RULES_DIR/" 2>/dev/null || echo "User rules directory may be empty"
fi

USE_RULES_PATH="$CONSOLIDATED_RULES_DIR"

echo "Running ting-tong-test container with consolidated rules from: $USE_RULES_PATH"

# Run the ting-tong-test container with the required parameters
# Note: This requires a self-hosted runner with appropriate permissions
docker run --rm --name ting-tong-test \
  --privileged \
  --pid=host \
  --net=host \
  -v /sys/fs/bpf:/sys/fs/bpf \
  -v /sys/kernel/debug:/sys/kernel/debug \
  -v "$USE_RULES_PATH":"/rules" \
  hanshal785/ting-tong-test:dev

echo "Ting Tong Action completed."
