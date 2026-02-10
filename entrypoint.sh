#!/bin/bash
set -e

echo "Starting Ting Tong Action..."
echo "Rules input: $1"
echo "Inline rules: $2"
echo "Rules file: $3"

RULES_INPUT="$1"
INLINE_RULES="$2"
RULES_FILE="${3:-custom-rule.yaml}"
IMAGE_NAME="public.ecr.aws/f9o7b7m0/kayo:latest"
CONTAINER_NAME="kayo-final-test"

# Determine the rules directory
if [ -n "$RULES_INPUT" ]; then
    NORMALIZED_INPUT="${RULES_INPUT#./}"
    RULES_DIR="/github/workspace/$NORMALIZED_INPUT"
else
    RULES_DIR="/github/workspace/rules"
fi

mkdir -p "$RULES_DIR"
echo "Using rules directory: $RULES_DIR"

# Copy built-in rules
if [ -d "/app/built-in-rules" ] && [ "$(ls -A /app/built-in-rules)" ]; then
    echo "Copying built-in rules..."
    cp -r /app/built-in-rules/* "$RULES_DIR/" 2>/dev/null || true
fi

# Copy user-provided rules if they exist
if [ -n "$RULES_INPUT" ]; then
    USER_RULES_PATH="/github/workspace/${RULES_INPUT#./}"
    if [ -f "$USER_RULES_PATH" ]; then
        echo "Copying rules from file: $USER_RULES_PATH"
        cp "$USER_RULES_PATH" "$RULES_DIR/"
    elif [ -d "$USER_RULES_PATH" ] && [ "$USER_RULES_PATH" != "$RULES_DIR" ]; then
        echo "Copying rules from directory: $USER_RULES_PATH"
        cp -r "$USER_RULES_PATH"/* "$RULES_DIR/" 2>/dev/null || true
    fi
fi

# Handle inline rules
if [ -n "$INLINE_RULES" ]; then
    echo "Adding inline rules..."
    echo "$INLINE_RULES" > "$RULES_DIR/$RULES_FILE"
fi

# Standardize permissions
chmod -R 755 "$RULES_DIR" 2>/dev/null || true
find "$RULES_DIR" -type f \( -name "*.yaml" -o -name "*.yml" \) -exec chmod 644 {} \; 2>/dev/null || true

echo "Final rules list:"
ls -lR "$RULES_DIR"

# Verify YAML files and prepare rules arguments for Kayo
YAML_FILES=$(find "$RULES_DIR" -type f \( -name "*.yaml" -o -name "*.yml" \))
if [ -z "$YAML_FILES" ]; then
    echo "ERROR: No YAML rule files found"
    exit 1
fi

RULES_ARGS=""
for f in $YAML_FILES; do
    relative_path=${f#"$RULES_DIR"/}
    RULES_ARGS="$RULES_ARGS --rules /rules/$relative_path"
done
YAML_COUNT=$(echo "$YAML_FILES" | wc -l)
echo "Found $YAML_COUNT YAML files"
echo "Kayo rules arguments: $RULES_ARGS"


# Debug output
echo "=== DEBUG: YAML Contents ==="
for file in "$RULES_DIR"/*.{yaml,yml}; do
    [ -f "$file" ] && echo "--- $(basename $file) ---" && cat "$file" && echo ""
done
echo "============================="

# CRITICAL: Compute the host path for the rules directory
# GitHub Actions mounts workspace at: /home/runner/work/<repo>/<repo>
if [ -n "$GITHUB_REPOSITORY" ]; then
    REPO_NAME=$(echo "$GITHUB_REPOSITORY" | cut -d'/' -f2)
    WORKSPACE_BASE="/home/runner/work/$REPO_NAME/$REPO_NAME"
    HOST_RULES_DIR="$WORKSPACE_BASE/${RULES_DIR#/github/workspace/}"

    echo "Repository: $GITHUB_REPOSITORY"
    echo "Workspace base: $WORKSPACE_BASE"
    echo "Host rules directory: $HOST_RULES_DIR"
else
    echo "WARNING: GITHUB_REPOSITORY not set, using container path"
    HOST_RULES_DIR="$RULES_DIR"
fi

echo ""
echo "Starting $CONTAINER_NAME container in background..."
echo "Mounting: $HOST_RULES_DIR -> /rules (inside container)"
echo ""

# Run the Kayo container in detached mode
CONTAINER_ID=$(docker run -d --rm --name "$CONTAINER_NAME" \
  --privileged \
  --pid=host \
  --net=host \
  -v /sys/fs/bpf:/sys/fs/bpf \
  -v /sys/kernel/debug:/sys/kernel/debug \
  -v "$HOST_RULES_DIR:/rules:ro" \
  "$IMAGE_NAME" \
  /app/kayo $RULES_ARGS --backend kayo --print)

if [ -z "$CONTAINER_ID" ]; then
    echo "✗ Failed to start $CONTAINER_NAME container"
    exit 1
fi

echo "✓ Kayo container started successfully"
echo "Container ID: $CONTAINER_ID"

# Wait a few seconds to ensure it's properly initialized
sleep 20

# Check if container is still running
if docker ps | grep -q "$CONTAINER_NAME"; then
    echo "✓ Kayo monitoring is active and will run throughout the workflow"
    echo ""
    echo "NOTE: The security monitoring will continue running in the background."
    echo "It will automatically detect and block suspicious activities."
    echo ""

    # Export container ID for potential cleanup in later steps
    echo "TING_TONG_CONTAINER_ID=$CONTAINER_ID" >> $GITHUB_ENV

    # Show initial logs
    echo "=== Initial Kayo Logs ==="
    docker logs "$CONTAINER_NAME" 2>&1 || true
    echo "==============================="
else
    echo "✗ Kayo container stopped unexpectedly"
    docker logs "$CONTAINER_NAME" 2>&1 || true
    exit 1
fi

exit 0
