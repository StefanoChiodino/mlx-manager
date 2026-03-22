#!/usr/bin/env bash
# Optimal mlx_vlm.server for vision-language models on M2 Ultra 64GB
# Findings: best single-user agentic config, thinking OFF, no spec decoding
#
# Cache findings (2026-03-17):
#   --max-kv-size = max number of KV cache entries for vision-language models
#   "N seq" in logs = N distinct cached prefixes, NOT concurrent users
#   At 36k tokens, each cache entry is ~0.77 GB; 4 slots = ~3 GB max, well within 64 GB budget
#   RAM spikes (65%->80%) are from prefill activations on large contexts (24k+ tokens), not the cache
#   Memory returns to baseline after generation; MLX does release unified memory between requests
#   4 slots chosen over default 10 to be conservative, covers concurrent requests and context switches
#
# Note: MLX-VLM does not support speculative decoding (--draft-model).
# For optimal vision model performance, keep thinking disabled for most use cases.

set -e  # Exit on error

# Use the Python environment from the presets.yaml
PYTHON_PATH="${PYTHON_PATH:-~/.mlx-manager/venv/bin/python}"

MODEL="mlx-community/Qwen3.5-35B-A3B-4bit"
PORT="${1:-8080}"
MAX_KV_SIZE="${2:-40960}"

# Expand tilde in PYTHON_PATH
PYTHON_PATH=$(eval echo "$PYTHON_PATH")

# Error handling functions
error_exit() {
    echo "ERROR: $1" >&2
    exit 1
}

# Validate Python path exists
if [[ ! -x "$PYTHON_PATH" ]]; then
    error_exit "Python not found at: $PYTHON_PATH"
fi

# Validate Logs directory exists
LOGS_DIR="$(dirname "$0")/Logs"
mkdir -p "$LOGS_DIR" || error_exit "Failed to create Logs directory: $LOGS_DIR"

# Validate mlx_vlm.server module is available
if ! "$PYTHON_PATH" -m mlx_vlm.server --help >/dev/null 2>&1; then
    error_exit "mlx_vlm.server module not found. Install with: uv pip install mlx-vlm"
fi

# Start the server
echo "Starting MLX-VLM server on port $PORT with max-kv-size $MAX_KV_SIZE..."
echo "Model: $MODEL"
echo "Python: $PYTHON_PATH"
echo "Log file: $LOGS_DIR/server-vision.log"
echo "----------------------------------------"

"$PYTHON_PATH" -m mlx_vlm.server \
  --model "$MODEL" \
  --port "$PORT" \
  --prefill-step-size 4096 \
  --max-kv-size "$MAX_KV_SIZE" \
  --trust-remote-code \
  2>&1 | tee "$LOGS_DIR/server-vision.log"
