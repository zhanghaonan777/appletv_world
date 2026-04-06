"""
Test Qwen3.5-0.8B translation quality using Python transformers.
This tests the model directly without needing Xcode/llama.cpp.
"""
import os
os.environ["TOKENIZERS_PARALLELISM"] = "false"

from transformers import AutoTokenizer, AutoModelForCausalLM
import torch
import time

MODEL_DIR = os.path.dirname(os.path.abspath(__file__))
GGUF_PATH = os.path.join(MODEL_DIR, "Qwen3.5-0.8B-Q4_K_M.gguf")

# Use the HuggingFace model directly for testing (not GGUF)
MODEL_NAME = "Qwen/Qwen3.5-0.8B"

print("Loading tokenizer...")
tokenizer = AutoTokenizer.from_pretrained(
    os.path.join(MODEL_DIR, "tokenizer"),
    trust_remote_code=True,
)

print("Loading model...")
model = AutoModelForCausalLM.from_pretrained(
    MODEL_NAME,
    torch_dtype=torch.float32,
    trust_remote_code=True,
)
model.eval()

test_sentences = [
    ("Hello, how are you?", "Chinese"),
    ("The weather is sunny today.", "Chinese"),
    ("Breaking news: the president announced a new policy.", "Chinese"),
    ("Scientists have discovered water on Mars.", "Chinese"),
    ("The stock market dropped significantly.", "Japanese"),
    ("Good morning, welcome to the show.", "Korean"),
]

print("\n=== Translation Tests ===\n")

for text, lang in test_sentences:
    prompt = f"/no_think\nTranslate to {lang}: {text}"

    messages = [{"role": "user", "content": prompt}]
    chat_text = tokenizer.apply_chat_template(messages, tokenize=False, add_generation_prompt=True)

    inputs = tokenizer(chat_text, return_tensors="pt")

    start = time.time()
    with torch.no_grad():
        out = model.generate(
            **inputs,
            max_new_tokens=64,
            do_sample=False,
            temperature=0.3,
            top_k=40,
            top_p=0.9,
        )
    elapsed = time.time() - start

    result = tokenizer.decode(out[0][inputs.input_ids.shape[1]:], skip_special_tokens=True)

    print(f"[{lang}] '{text}'")
    print(f"  → {result}")
    print(f"  ({elapsed:.2f}s)")
    print()

print("=== Done ===")
