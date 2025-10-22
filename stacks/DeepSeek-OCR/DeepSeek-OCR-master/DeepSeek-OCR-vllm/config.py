import os
from transformers import AutoTokenizer

# Mode defaults: 'tiny', 'small', 'base', 'large', 'gundam'
MODEL_MODE = os.getenv("MODEL_MODE", "gundam").lower()

# Default values (these are DeepSeek presets)
MODE_PRESETS = {
    "tiny":   {"BASE_SIZE": 512,  "IMAGE_SIZE": 512,  "CROP_MODE": False},
    "small":  {"BASE_SIZE": 640,  "IMAGE_SIZE": 640,  "CROP_MODE": False},
    "base":   {"BASE_SIZE": 1024, "IMAGE_SIZE": 1024, "CROP_MODE": False},
    "large":  {"BASE_SIZE": 1280, "IMAGE_SIZE": 1280, "CROP_MODE": False},
    "gundam": {"BASE_SIZE": 1024, "IMAGE_SIZE": 640,  "CROP_MODE": True},
}

# Apply selected mode
mode_cfg = MODE_PRESETS.get(MODEL_MODE, MODE_PRESETS["gundam"])
BASE_SIZE = mode_cfg["BASE_SIZE"]
IMAGE_SIZE = mode_cfg["IMAGE_SIZE"]
CROP_MODE = mode_cfg["CROP_MODE"]

# Other tunables
MIN_CROPS       = int(os.getenv("MIN_CROPS", 2))
MAX_CROPS       = int(os.getenv("MAX_CROPS", 6))
MAX_CONCURRENCY = int(os.getenv("MAX_CONCURRENCY", 100))
NUM_WORKERS     = int(os.getenv("NUM_WORKERS", 16))
PRINT_NUM_VIS_TOKENS = os.getenv("PRINT_NUM_VIS_TOKENS", "false").lower() == "true"
SKIP_REPEAT     = os.getenv("SKIP_REPEAT", "true").lower() == "true"

MODEL_PATH = os.getenv("MODEL_PATH", "deepseek-ai/DeepSeek-OCR")
INPUT_PATH = os.getenv("INPUT_PATH", "")
OUTPUT_PATH = os.getenv("OUTPUT_PATH", "")
PROMPT = os.getenv("PROMPT", "<image>\n<|grounding|>Convert the document to markdown.")

# Initialize tokenizer dynamically
TOKENIZER = AutoTokenizer.from_pretrained(MODEL_PATH, trust_remote_code=True)
