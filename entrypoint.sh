#!/bin/bash
set -e

echo "Starting Ting Tong Action..."
echo "Rules input: $1"
echo "Inline rules: $2"
echo "Rules file: $3"

RULES_INPUT="$1"
INLINE_RULES="$2"
RULES_FILE="${3:-custom-rule.yaml}"

# Determine the rules directory in the GitHub Actions workspace
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
echo "Standardizing permissions for rules directory: $RULES_DIR"
chown -R root:root "$RULES_DIR" 2>/dev/null || true
chmod -R 755 "$RULES_DIR" 2>/dev/null || true
chmod 644 "$RULES_DIR"/*.yaml 2>/dev/null || true
chmod 644 "$RULES_DIR"/*.yml 2>/dev/null || true

echo "Final consolidated rules list:"
ls -lR "$RULES_DIR"

# Verify YAML files
YAML_COUNT=$(find "$RULES_DIR" -name "*.yaml" -o -name "*.yml" | wc -l)
echo "Found $YAML_COUNT YAML files in $RULES_DIR"

# Debug: Show content of each YAML file
echo "=== DEBUG: Contents of YAML files ==="
for file in "$RULES_DIR"/*.yaml "$RULES_DIR"/*.yml; do
    if [ -f "$file" ]; then
        echo "--- File: $file ---"
        cat "$file"
        echo ""
    fi
done
echo "==================================="

if [ "$YAML_COUNT" -eq 0 ]; then
    echo "ERROR: No YAML rule files found in $RULES_DIR"
    exit 1
fi

# CRITICAL FIX: Convert container path to host path for Docker-in-Docker
# The GitHub Actions runner mounts the workspace at a specific location on the host
# We need to figure out that host path to pass to the inner Docker container

# The workspace is typically mounted from the host at:
# /home/runner/work/<repo>/<repo> -> /github/workspace (inside this container)
# We need to construct the host path based on environment variables

if [ -n "$GITHUB_REPOSITORY" ]; then
    # Extract repo name from GITHUB_REPOSITORY (format: owner/repo)
    REPO_NAME=$(echo "$GITHUB_REPOSITORY" | cut -d'/' -f2)
    # Construct the host path
    HOST_WORKSPACE="/home/runner/work/$REPO_NAME/$REPO_NAME"
    HOST_RULES_DIR="$HOST_WORKSPACE/${RULES_DIR#/github/workspace/}"
else
    # Fallback: try to use the workspace as-is (may not work in DinD)
    HOST_RULES_DIR="$RULES_DIR"
fi

echo "Computed host rules directory: $HOST_RULES_DIR"
echo "Running ting-tong-test container, mounting $HOST_RULES_DIR to /rules"

# Run the ting-tong-test container with the host path
docker run --rm -d --name ting-tong-test \
  --privileged \
  --pid=host \
  --net=host \
  -v /sys/fs/bpf:/sys/fs/bpf \
  -v /sys/kernel/debug:/sys/kernel/debug \
  -v "$HOST_RULES_DIR:/rules:ro" \
  hanshal785/ting-tong-test:dev

echo "Ting Tong Action completed."
