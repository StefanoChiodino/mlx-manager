# mlx-vlm 0.4.1 Patches

Two bugs in `mlx_vlm` 0.4.1 prevent vision (image) input from working with Qwen3.5 models via `mlx_vlm.server`. Both are patched manually in the venv at `~/.mlx-manager/venv/lib/python3.12/site-packages/mlx_vlm/`.

Re-apply these patches after any `mlx-vlm` upgrade.

---

## Bug 1 — Fast image processor rejects `return_tensors="mlx"`

**File:** `mlx_vlm/utils.py`, function `process_inputs_with_fallback`

**Error:** `Generation failed: Failed to process inputs with error: Only returning PyTorch tensors is currently supported.`

**Cause:** The function passes `return_tensors="mlx"` to the HuggingFace processor. Qwen3.5 uses a fast image processor (`BaseImageProcessorFast`) which only accepts `"pt"`.

**Upstream:** [Issue #847](https://github.com/Blaizzy/mlx-vlm/issues/847) — their suggested fix is `use_fast=False` in `AutoProcessor.from_pretrained`.

**Our fix:** In `process_inputs_with_fallback`, if the `"mlx"` call raises, retry with `return_tensors="pt"`. The existing downstream code already converts PyTorch tensors to MLX arrays via `mx.array()`.

```python
except Exception as e:
    if return_tensors != "pt":
        try:
            return process_inputs(..., return_tensors="pt", ...)
        except Exception:
            pass
    raise ValueError(f"Failed to process inputs with error: {e}")
```

---

## Bug 2 — Vision token inserted into wrong message in multi-turn conversations

**File:** `mlx_vlm/prompt_utils.py`, function `apply_chat_template`

**Error:** `ValueError: Image features and image tokens do not match: tokens: 0, features N`

**Cause:** When building the prompt from a list of messages, the vision token (`<|vision_start|><|image_pad|><|vision_end|>`) is inserted into the **first user message**. In a multi-turn conversation, the image is attached to the **last user message**, so the token ends up in the wrong place. The model sees image features but zero image tokens in the prompt.

**Upstream:** [Issue #833](https://github.com/Blaizzy/mlx-vlm/issues/833) — open, no fix merged yet.

**Our fix:** Before iterating messages, find the index of the last user message. Insert the vision token only into that message.

```python
last_user_idx = None
if num_images > 0 or num_audios > 0:
    for i, p in enumerate(prompt):
        role = "user" if isinstance(p, str) else (_get_role_content(p) or [None])[0]
        if role == "user":
            last_user_idx = i

# Then in the loop:
is_image_message = (i == last_user_idx) if last_user_idx is not None else <original logic>
```
