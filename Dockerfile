FROM docker:dind

# Install necessary dependencies
RUN apk add --no-cache \
    bash \
    curl \
    wget \
    git \
    python3

# Create necessary directories
RUN mkdir -p /app /rules

# Copy built-in rules to the image
COPY rules/ /app/built-in-rules/

# Copy entrypoint script
COPY entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh

# Set working directory
WORKDIR /app

# Set entrypoint
ENTRYPOINT ["/app/entrypoint.sh"]
