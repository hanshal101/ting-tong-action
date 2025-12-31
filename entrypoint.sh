#!/bin/bash
set -e

echo "Starting Ting Tong Action..."
echo "Rules input: $1"
echo "Inline rules: $2"
echo "Rules file: $3"

RULES_INPUT="$1"
INLINE_RULES="$2"
RULES_FILE="${3:-custom-rule.yaml}"

# Change to workspace to handle relative user paths
cd /github/workspace

# Use the user's provided directory as the destination for all rules
DEST_RULES_DIR="$RULES_INPUT"
echo "Consolidating all rules into: $DEST_RULES_DIR"

# Copy built-in rules into the user's rule directory
if [ -d "/app/built-in-rules" ] && [ "$(ls -A /app/built-in-rules)" ]; then
    echo "Copying built-in rules..."
    cp -r /app/built-in-rules/* "$DEST_RULES_DIR/"
fi

# Handle inline rules (if provided)
if [ -n "$INLINE_RULES" ]; then
    echo "Adding inline rules..."
    echo "$INLINE_RULES" > "$DEST_RULES_DIR/$RULES_FILE"
fi

# The host path is the workspace path combined with the user's relative path
HOST_RULES_DIR="$GITHUB_WORKSPACE/$DEST_RULES_DIR"

echo "Final consolidated rules list in $DEST_RULES_DIR:"
ls -lR "$DEST_RULES_DIR"

echo "Running ting-tong-test container, mounting $HOST_RULES_DIR to /rules"

# Run the ting-tong-test container
docker run --rm --name ting-tong-test \
  --privileged \
  --pid=host \
  --net=host \
  -v /sys/fs/bpf:/sys/fs/bpf \
  -v /sys/kernel/debug:/sys/kernel/debug \
  -v "$HOST_RULES_DIR:/rules" \
  hanshal785/ting-tong-test:dev

echo "Ting Tong Action completed."
