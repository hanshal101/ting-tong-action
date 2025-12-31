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
CONTAINER_RULES_DIR="/github/workspace/.ting-tong-rules"
mkdir -p "$CONTAINER_RULES_DIR"

# Determine destination directory based on input type
if [ -n "$RULES_INPUT" ]; then
    if [ -f "$RULES_INPUT" ]; then
        # If input is a file, use its directory
        INPUT_DIR=$(dirname "$RULES_INPUT")
        DEST_RULES_DIR="/github/workspace/$INPUT_DIR"
    elif [ -d "$RULES_INPUT" ]; then
        # If input is a directory, use it directly
        DEST_RULES_DIR="/github/workspace/$RULES_INPUT"
    else
        # If input doesn't exist, create it relative to workspace
        DEST_RULES_DIR="/github/workspace/$RULES_INPUT"
        mkdir -p "$DEST_RULES_DIR"
    fi
else
    # Default destination if no input provided
    DEST_RULES_DIR="/github/workspace/rules"
    mkdir -p "$DEST_RULES_DIR"
fi

echo "Consolidating all rules into: $DEST_RULES_DIR"

# Copy built-in rules
if [ -d "/app/built-in-rules" ] && [ "$(ls -A /app/built-in-rules)" ]; then
    echo "Copying built-in rules..."
    cp -r /app/built-in-rules/* "$CONTAINER_RULES_DIR/" 2>/dev/null || true
    cp -r /app/built-in-rules/* "$DEST_RULES_DIR/" 2>/dev/null || true
fi

# Copy user-provided rules
if [ -n "$RULES_INPUT" ]; then
    USER_RULES_PATH="/github/workspace/$RULES_INPUT"
    if [ -f "$USER_RULES_PATH" ]; then
        echo "Copying rules from file: $USER_RULES_PATH"
        mkdir -p "$DEST_RULES_DIR"
        cp "$USER_RULES_PATH" "$CONTAINER_RULES_DIR/"
        cp "$USER_RULES_PATH" "$DEST_RULES_DIR/"
    elif [ -d "$USER_RULES_PATH" ]; then
        echo "Copying rules from directory: $USER_RULES_PATH"
        cp -r "$USER_RULES_PATH"/* "$CONTAINER_RULES_DIR/" 2>/dev/null || true
        cp -r "$USER_RULES_PATH"/* "$DEST_RULES_DIR/" 2>/dev/null || true
    else
        echo "Warning: '$USER_RULES_PATH' is not a valid file or directory."
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

# Standardize ownership and permissions
echo "Standardizing permissions for rules directory: $DEST_RULES_DIR"
chown -R root:root "$DEST_RULES_DIR" 2>/dev/null || true
chmod -R a+r "$DEST_RULES_DIR" 2>/dev/null || true

# The host path that will be mounted is the absolute path in the workspace
HOST_RULES_DIR="$DEST_RULES_DIR"

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
