#!/bin/bash
set -e

# Build the container
docker build --no-cache -f Dockerfile.local -t aipress-wordpress-runtime:local .

# Run with debug flags and keep standard in open to avoid container exit
echo "Starting container in debug mode..."
docker run --rm -p 8080:8080 \
  --name wp-debug \
  aipress-wordpress-runtime:local
