"""
Convert SMaLL-100 (alirezamsh/small100) to CoreML format.
Encoder and Decoder are exported separately for autoregressive inference.
"""

import torch
import numpy as np
import coremltools as ct
from transformers import AutoTokenizer, AutoModelForSeq2SeqLM
import os
import json
import shutil

MODEL_NAME = "alirezamsh/small100"
OUTPUT_DIR = os.path.dirname(os.path.abspath(__file__))
MAX_SEQ_LEN = 128  # Max input tokens
MAX_GEN_LEN = 64   # Max output tokens

print(f"[1/6] Loading model: {MODEL_NAME}")
tokenizer = AutoTokenizer.from_pretrained(MODEL_NAME)
model = AutoModelForSeq2SeqLM.from_pretrained(MODEL_NAME, torchscript=False)
model.eval()

# Save tokenizer files for Swift
print(f"[2/6] Saving tokenizer files...")
tokenizer.save_pretrained(os.path.join(OUTPUT_DIR, "tokenizer"))

# ============================================================
# Export Encoder
# ============================================================
print(f"[3/6] Tracing encoder...")

class EncoderWrapper(torch.nn.Module):
    def __init__(self, encoder):
        super().__init__()
        self.encoder = encoder

    def forward(self, input_ids, attention_mask):
        out = self.encoder(input_ids=input_ids, attention_mask=attention_mask)
        return out.last_hidden_state

encoder_wrapper = EncoderWrapper(model.get_encoder())
encoder_wrapper.eval()

# Dummy inputs
dummy_input_ids = torch.randint(0, 1000, (1, MAX_SEQ_LEN), dtype=torch.int32)
dummy_attention_mask = torch.ones(1, MAX_SEQ_LEN, dtype=torch.int32)

with torch.no_grad():
    traced_encoder = torch.jit.trace(encoder_wrapper, (dummy_input_ids, dummy_attention_mask))

print(f"[4/6] Converting encoder to CoreML...")
encoder_mlmodel = ct.convert(
    traced_encoder,
    inputs=[
        ct.TensorType(name="input_ids", shape=(1, MAX_SEQ_LEN), dtype=np.int32),
        ct.TensorType(name="attention_mask", shape=(1, MAX_SEQ_LEN), dtype=np.int32),
    ],
    outputs=[
        ct.TensorType(name="encoder_hidden_states"),
    ],
    compute_precision=ct.precision.FLOAT16,
    minimum_deployment_target=ct.target.iOS16,
)

encoder_path = os.path.join(OUTPUT_DIR, "SMaLL100Encoder.mlpackage")
encoder_mlmodel.save(encoder_path)
print(f"  Encoder saved: {encoder_path}")

# ============================================================
# Export Decoder (single step for autoregressive generation)
# ============================================================
print(f"[5/6] Tracing decoder (single-step)...")

class DecoderWrapper(torch.nn.Module):
    """Single-step decoder: takes decoder_input_ids + encoder_hidden_states, returns logits."""
    def __init__(self, model):
        super().__init__()
        self.model = model

    def forward(self, decoder_input_ids, encoder_hidden_states, encoder_attention_mask):
        out = self.model(
            decoder_input_ids=decoder_input_ids,
            encoder_outputs=(encoder_hidden_states,),
            attention_mask=encoder_attention_mask,
        )
        return out.logits

decoder_wrapper = DecoderWrapper(model)
decoder_wrapper.eval()

# Decoder inputs: variable-length decoder sequence (use max gen len)
dummy_decoder_ids = torch.randint(0, 1000, (1, MAX_GEN_LEN), dtype=torch.int32)
dummy_encoder_hidden = torch.randn(1, MAX_SEQ_LEN, model.config.d_model)
dummy_enc_mask = torch.ones(1, MAX_SEQ_LEN, dtype=torch.int32)

with torch.no_grad():
    traced_decoder = torch.jit.trace(
        decoder_wrapper,
        (dummy_decoder_ids, dummy_encoder_hidden, dummy_enc_mask)
    )

print(f"[6/6] Converting decoder to CoreML...")

# Use flexible shapes for decoder_input_ids (1..MAX_GEN_LEN)
decoder_shape = ct.Shape(
    shape=(1, ct.RangeDim(lower_bound=1, upper_bound=MAX_GEN_LEN, default=1))
)

decoder_mlmodel = ct.convert(
    traced_decoder,
    inputs=[
        ct.TensorType(name="decoder_input_ids", shape=decoder_shape, dtype=np.int32),
        ct.TensorType(name="encoder_hidden_states", shape=(1, MAX_SEQ_LEN, model.config.d_model)),
        ct.TensorType(name="encoder_attention_mask", shape=(1, MAX_SEQ_LEN), dtype=np.int32),
    ],
    outputs=[
        ct.TensorType(name="logits"),
    ],
    compute_precision=ct.precision.FLOAT16,
    minimum_deployment_target=ct.target.iOS16,
)

decoder_path = os.path.join(OUTPUT_DIR, "SMaLL100Decoder.mlpackage")
decoder_mlmodel.save(decoder_path)
print(f"  Decoder saved: {decoder_path}")

# ============================================================
# Save config for Swift
# ============================================================
config = {
    "vocab_size": model.config.vocab_size,
    "d_model": model.config.d_model,
    "max_seq_len": MAX_SEQ_LEN,
    "max_gen_len": MAX_GEN_LEN,
    "eos_token_id": model.config.eos_token_id,
    "decoder_start_token_id": model.config.decoder_start_token_id,
    "pad_token_id": model.config.pad_token_id,
}
config_path = os.path.join(OUTPUT_DIR, "config.json")
with open(config_path, "w") as f:
    json.dump(config, f, indent=2)
print(f"  Config saved: {config_path}")

# Print size info
def get_dir_size(path):
    total = 0
    for dirpath, dirnames, filenames in os.walk(path):
        for f in filenames:
            fp = os.path.join(dirpath, f)
            total += os.path.getsize(fp)
    return total

enc_size = get_dir_size(encoder_path) / 1024 / 1024
dec_size = get_dir_size(decoder_path) / 1024 / 1024
print(f"\n=== Summary ===")
print(f"Encoder: {enc_size:.1f} MB")
print(f"Decoder: {dec_size:.1f} MB")
print(f"Total:   {enc_size + dec_size:.1f} MB")
print(f"Config:  {config_path}")
print(f"Done!")
