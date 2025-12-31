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
# Change to workspace to handle relative user paths
cd /github/workspace

mkdir -p "$CONTAINER_RULES_DIR"

# Determine destination directory based on input type
if [ -n "$RULES_INPUT" ]; then
    if [ -f "$RULES_INPUT" ] || [ -d "$RULES_INPUT" ]; then
        # If input is a file or directory, use its parent directory or the directory itself
        if [ -f "$RULES_INPUT" ]; then
            DEST_RULES_DIR=$(dirname "$RULES_INPUT")
        else
            DEST_RULES_DIR="$RULES_INPUT"
        fi
    else
        # If input doesn't exist, treat it as a directory path to create
        DEST_RULES_DIR="$RULES_INPUT"
        mkdir -p "$DEST_RULES_DIR"
    fi
else
    # Default destination if no input provided
    DEST_RULES_DIR="rules"
    mkdir -p "$DEST_RULES_DIR"
fi

echo "Consolidating all rules into: $DEST_RULES_DIR"

# Copy built-in rules (assuming they are in /app/built-in-rules in action container)
if [ -d "/app/built-in-rules" ] && [ "$(ls -A /app/built-in-rules)" ]; then
    echo "Copying built-in rules..."
    cp -r /app/built-in-rules/* "$CONTAINER_RULES_DIR/"
    # Also copy to destination directory
    mkdir -p "$DEST_RULES_DIR"
    cp -r /app/built-in-rules/* "$DEST_RULES_DIR/" 2>/dev/null || true
fi

# Copy user-provided rules
if [ -n "$RULES_INPUT" ]; then
    if [ -f "$RULES_INPUT" ]; then
        echo "Copying rules from file: $RULES_INPUT"
        mkdir -p "$DEST_RULES_DIR"
        cp "$RULES_INPUT" "$CONTAINER_RULES_DIR/"
        cp "$RULES_INPUT" "$DEST_RULES_DIR/"
    elif [ -d "$RULES_INPUT" ]; then
        echo "Copying rules from directory: $RULES_INPUT"
        mkdir -p "$CONTAINER_RULES_DIR"
        cp -r "$RULES_INPUT"/* "$CONTAINER_RULES_DIR/" 2>/dev/null || true
        cp -r "$RULES_INPUT"/* "$DEST_RULES_DIR/" 2>/dev/null || true
    else
        echo "Warning: '$RULES_INPUT' is not a valid file or directory. Creating directory."
        mkdir -p "$RULES_INPUT"
        DEST_RULES_DIR="$RULES_INPUT"
    fi
fi

# Handle inline rules (if provided)
if [ -n "$INLINE_RULES" ]; then
    echo "Adding inline rules..."
    mkdir -p "$DEST_RULES_DIR"
    echo "$INLINE_RULES" > "$DEST_RULES_DIR/$RULES_FILE"
    # Also add to container rules directory
    echo "$INLINE_RULES" > "$CONTAINER_RULES_DIR/$RULES_FILE"
fi

echo "Final consolidated rules list in $CONTAINER_RULES_DIR:"
ls -lR "$CONTAINER_RULES_DIR" 2>/dev/null || echo "No rules in container directory"

# Standardize ownership and permissions to avoid issues inside the test container
echo "Standardizing permissions for rules directory: $DEST_RULES_DIR"
chown -R root:root "$DEST_RULES_DIR" 2>/dev/null || true
chmod -R a+r "$DEST_RULES_DIR" 2>/dev/null || true

# The host path is the workspace path combined with the user's relative path
HOST_RULES_DIR="$GITHUB_WORKSPACE/$DEST_RULES_DIR"

echo "Final consolidated rules list in $DEST_RULES_DIR:"
ls -lR "$DEST_RULES_DIR" 2>/dev/null || echo "No rules in destination directory"

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
