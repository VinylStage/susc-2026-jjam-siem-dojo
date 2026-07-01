#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

echo "Stopping and removing containers + volumes..."
docker compose --profile ollama down -v

echo "Removing toolkit clone and generated data..."
rm -rf toolkit ids.json

echo "Teardown complete."
