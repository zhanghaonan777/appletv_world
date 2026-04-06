"""
Convert Qwen3.5-0.8B to CoreML INT4 for on-device translation on tvOS.
Only exports the text model (no vision encoder needed for translation).
"""

import torch
import numpy as np
import coremltools as ct
from transformers import AutoTokenizer, AutoModelForCausalLM
import os
import json
import shutil

MODEL_NAME = "Qwen/Qwen3.5-0.8B"
OUTPUT_DIR = os.path.dirname(os.path.abspath(__file__))
MAX_SEQ_LEN = 256  # Combined prompt + generation length

print(f"[1/5] Downloading model: {MODEL_NAME}")
print("  This may take a few minutes...")

tokenizer = AutoTokenizer.from_pretrained(MODEL_NAME, trust_remote_code=True)
model = AutoModelForCausalLM.from_pretrained(
    MODEL_NAME,
    torch_dtype=torch.float32,
    trust_remote_code=True,
)
model.eval()

# Save tokenizer for Swift
print(f"[2/5] Saving tokenizer...")
tok_dir = os.path.join(OUTPUT_DIR, "tokenizer")
tokenizer.save_pretrained(tok_dir)

# Test translation prompt
test_prompt = tokenizer.apply_chat_template(
    [{"role": "user", "content": "Translate to Chinese: Hello, how are you?"}],
    tokenize=False,
    add_generation_prompt=True,
)
print(f"  Test prompt: {test_prompt[:100]}...")

# Quick inference test
print(f"[3/5] Testing inference...")
inputs = tokenizer(test_prompt, return_tensors="pt")
with torch.no_grad():
    out = model.generate(**inputs, max_new_tokens=30, do_sample=False)
result = tokenizer.decode(out[0][inputs.input_ids.shape[1]:], skip_special_tokens=True)
print(f"  Translation result: {result}")

# Trace model for CoreML
print(f"[4/5] Tracing model for CoreML export...")

class QwenForCoreML(torch.nn.Module):
    """Wrapper that takes input_ids and returns logits for next token prediction."""
    def __init__(self, model):
        super().__init__()
        self.model = model

    def forward(self, input_ids):
        outputs = self.model(input_ids=input_ids, use_cache=False)
        return outputs.logits

wrapper = QwenForCoreML(model)
wrapper.eval()

# Use fixed sequence length for tracing
dummy_ids = torch.randint(0, 1000, (1, MAX_SEQ_LEN), dtype=torch.int32)

with torch.no_grad():
    traced = torch.jit.trace(wrapper, dummy_ids)

print(f"[5/5] Converting to CoreML with INT4 quantization...")

# Convert to CoreML FP16 first
mlmodel = ct.convert(
    traced,
    inputs=[
        ct.TensorType(name="input_ids", shape=(1, MAX_SEQ_LEN), dtype=np.int32),
    ],
    outputs=[
        ct.TensorType(name="logits"),
    ],
    compute_precision=ct.precision.FLOAT16,
    minimum_deployment_target=ct.target.iOS16,
)

# Apply INT4 weight quantization
print("  Applying INT4 palettization...")
op_config = ct.optimize.coreml.OpPalettizerConfig(
    mode="kmeans",
    nbits=4,
)
config = ct.optimize.coreml.OptimizationConfig(global_config=op_config)
mlmodel_int4 = ct.optimize.coreml.palettize_weights(mlmodel, config)

# Save
model_path = os.path.join(OUTPUT_DIR, "Qwen35_0_8B_INT4.mlpackage")
mlmodel_int4.save(model_path)
print(f"  Saved: {model_path}")

# Save config
config_data = {
    "model_name": MODEL_NAME,
    "vocab_size": model.config.vocab_size,
    "hidden_size": model.config.hidden_size,
    "max_seq_len": MAX_SEQ_LEN,
    "eos_token_id": tokenizer.eos_token_id,
    "pad_token_id": tokenizer.pad_token_id if tokenizer.pad_token_id else tokenizer.eos_token_id,
}
config_path = os.path.join(OUTPUT_DIR, "config.json")
with open(config_path, "w") as f:
    json.dump(config_data, f, indent=2)

# Print sizes
def get_dir_size(path):
    total = 0
    for dirpath, _, filenames in os.walk(path):
        for fn in filenames:
            total += os.path.getsize(os.path.join(dirpath, fn))
    return total

model_size = get_dir_size(model_path) / 1024 / 1024
print(f"\n=== Summary ===")
print(f"Model: {model_size:.0f} MB (INT4)")
print(f"Config: {config_path}")
print(f"Tokenizer: {tok_dir}")
print("Done!")
