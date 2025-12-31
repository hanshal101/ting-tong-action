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

# Process the input to determine the destination directory
if [ -n "$RULES_INPUT" ]; then
    # Normalize the input path by removing leading ./ and resolving to absolute path
    NORMALIZED_INPUT="${RULES_INPUT#./}"  # Remove leading ./
    DEST_RULES_DIR="/github/workspace/$NORMALIZED_INPUT"
    mkdir -p "$DEST_RULES_DIR"
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
    # Use the original input to reference files in the workspace
    USER_RULES_PATH="/github/workspace/${RULES_INPUT#./}"
    if [ -f "$USER_RULES_PATH" ]; then
        echo "Copying rules from file: $USER_RULES_PATH"
        cp "$USER_RULES_PATH" "$CONTAINER_RULES_DIR/"
        cp "$USER_RULES_PATH" "$DEST_RULES_DIR/"
    elif [ -d "$USER_RULES_PATH" ]; then
        echo "Copying rules from directory: $USER_RULES_PATH"
        cp -r "$USER_RULES_PATH"/* "$CONTAINER_RULES_DIR/" 2>/dev/null || true
        cp -r "$USER_RULES_PATH"/* "$DEST_RULES_DIR/" 2>/dev/null || true
    else
        echo "Warning: '$USER_RULES_PATH' is not a valid file or directory. Directory will be created."
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
ls -lR "$CONTAINER_RULES_DIR"
ls -lR "$CONTAINER_RULES_DIR" 2>/dev/null || echo "No rules in container directory"

# Standardize ownership and permissions
echo "Standardizing permissions for rules directory: $DEST_RULES_DIR"
chown -R root:root "$DEST_RULES_DIR" 2>/dev/null || true
chmod -R a+r "$DEST_RULES_DIR" 2>/dev/null || true

HOST_RULES_DIR="$DEST_RULES_DIR"

echo "Final consolidated rules list in $DEST_RULES_DIR:"
ls -lR "$DEST_RULES_DIR" 2>/dev/null || echo "No rules in destination directory"

# Verify that the directory contains YAML files before running the test
YAML_COUNT=$(find "$DEST_RULES_DIR" -name "*.yaml" -o -name "*.yml" | wc -l)
echo "Found $YAML_COUNT YAML files in $DEST_RULES_DIR"

# Debug: Show content of each YAML file
echo "=== DEBUG: Contents of YAML files ==="
for file in "$DEST_RULES_DIR"/*.yaml "$DEST_RULES_DIR"/*.yml; do
    if [ -f "$file" ]; then
        echo "--- File: $file ---"
        cat "$file"
        echo ""
        echo "--- Validating YAML syntax ---"
        # Try to parse with Python if available
        if command -v python3 &> /dev/null; then
            python3 -c "import yaml; yaml.safe_load(open('$file'))" && echo "✓ Valid YAML" || echo "✗ Invalid YAML"
        fi
        echo ""
    fi
done
echo "==================================="

if [ "$YAML_COUNT" -eq 0 ]; then
    echo "ERROR: No YAML rule files found in $DEST_RULES_DIR"
    exit 1
fi

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
