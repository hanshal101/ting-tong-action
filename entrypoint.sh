#!/bin/bash
set -e

echo "Starting Ting Tong Action..."
echo "Rules input: $1"
echo "Inline rules: $2"
echo "Rules file: $3"

RULES_INPUT="$1"
INLINE_RULES="$2"
RULES_FILE="${3:-custom-rule.yaml}"

# The consolidated rules directory will be created inside the workspace
# This is the path inside the action container
CONTAINER_RULES_DIR="/github/workspace/.ting-tong-rules"
# This is the corresponding path on the host, for the docker-in-docker mount
HOST_RULES_DIR="$GITHUB_WORKSPACE/.ting-tong-rules"

mkdir -p "$CONTAINER_RULES_DIR"

# Copy built-in rules (assuming they are in /app/rules in action container)
if [ -d "/app/rules" ] && [ "$(ls -A /app/rules)" ]; then
    echo "Copying built-in rules..."
    cp -r /app/rules/* "$CONTAINER_RULES_DIR/"
fi

# Change to workspace to handle relative user paths
cd /github/workspace

# Copy user-provided rules
if [ -n "$RULES_INPUT" ]; then
    if [ -f "$RULES_INPUT" ]; then
        echo "Copying rules from file: $RULES_INPUT"
        cp "$RULES_INPUT" "$CONTAINER_RULES_DIR/"
    elif [ -d "$RULES_INPUT" ]; then
        echo "Copying rules from directory: $RULES_INPUT"
        cp -r "$RULES_INPUT"/* "$CONTAINER_RULES_DIR/"
    else
        echo "Warning: '$RULES_INPUT' is not a valid file or directory."
    fi
fi

# Handle inline rules
if [ -n "$INLINE_RULES" ]; then
    echo "Adding inline rules..."
    echo "$INLINE_RULES" > "$CONTAINER_RULES_DIR/$RULES_FILE"
fi

echo "Final consolidated rules list in $CONTAINER_RULES_DIR:"
ls -lR "$CONTAINER_RULES_DIR"

echo "Running ting-tong-test container, mounting $HOST_RULES_DIR"

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
