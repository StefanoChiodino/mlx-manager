#!/usr/bin/env bash
# Tests for serve-vision.sh script validation

# Don't exit on test failures - we want to see all failures
# set -e

# The serve-vision.sh script is in the project root
TEST_SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/serve-vision.sh"

# Test 1: Script exists and is executable
test_script_exists() {
    if [[ -f "$TEST_SCRIPT" ]]; then
        echo "✓ Test passed: Script exists"
        return 0
    else
        echo "✗ Test failed: Script does not exist"
        return 1
    fi
}

# Test 2: Script should use python -m mlx_vlm.server (not mlx_vlm.server directly)
test_uses_python_module() {
    # Accept any python path (literal "python", env var, or expanded path) followed by -m mlx_vlm
    if grep -qE 'python.*-m.*mlx_vlm|PYTHON_PATH.*-m.*mlx_vlm' "$TEST_SCRIPT"; then
        echo "✓ Test passed: Script uses python -m mlx_vlm.server"
        return 0
    else
        echo "✗ Test failed: Script should use 'python -m mlx_vlm.server' (or \$PYTHON_PATH -m mlx_vlm.server)"
        return 1
    fi
}

# Test 3: Script should use --max-kv-size for MLX-VLM (not --max-tokens)
test_uses_max_kv_size() {
    if grep -q "\-\-max-kv-size" "$TEST_SCRIPT"; then
        echo "✓ Test passed: Script uses --max-kv-size"
        return 0
    else
        echo "✗ Test failed: Script should use --max-kv-size for MLX-VLM"
        return 1
    fi
}

# Test 4: Script should NOT use --chat-template-args (MLX-VLM doesn't use it)
test_no_chat_template_args() {
    if grep -q "\-\-chat-template-args" "$TEST_SCRIPT"; then
        echo "✗ Test failed: Script should NOT use --chat-template-args (MLX-VLM doesn't support it)"
        return 1
    else
        echo "✓ Test passed: Script does not use --chat-template-args"
        return 0
    fi
}

# Test 5: Script should NOT use --prompt-cache-size and --prompt-cache-bytes (MLX-LM flags)
test_no_mlxlm_cache_flags() {
    if grep -q "\-\-prompt-cache-size\|\-\-prompt-cache-bytes" "$TEST_SCRIPT"; then
        echo "✗ Test failed: Script should NOT use --prompt-cache-size or --prompt-cache-bytes (MLX-LM flags)"
        return 1
    else
        echo "✓ Test passed: Script does not use MLX-LM cache flags"
        return 0
    fi
}

# Test 6: Script should specify python path
test_uses_python_path() {
    if grep -q "pythonPath\|~/.mlx-manager" "$TEST_SCRIPT"; then
        echo "✓ Test passed: Script specifies python path"
        return 0
    else
        echo "✗ Test failed: Script should specify python path (e.g., ~/.mlx-manager/venv/bin/python)"
        return 1
    fi
}

# Test 7: Script should have proper model specification
test_has_model_specification() {
    if grep -q 'MODEL="mlx-community/' "$TEST_SCRIPT"; then
        echo "✓ Test passed: Script has model specification"
        return 0
    else
        echo "✗ Test failed: Script should specify model"
        return 1
    fi
}

# Run all tests
echo "Running serve-vision.sh validation tests..."
echo "============================================="

test_script_exists
test_uses_python_module
test_uses_max_kv_size
test_no_chat_template_args
test_no_mlxlm_cache_flags
test_uses_python_path
test_has_model_specification

echo "============================================="
echo "Tests complete"
