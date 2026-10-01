from pathlib import Path

import torch
from transformers import AutoModelForTokenClassification, AutoTokenizer


LABELS = ["O", "B-COURSE", "I-COURSE"]
MAX_TOKENS = 256


def align_labels(offsets, entities):
    labels = []
    previous_entity = None
    for start, end in offsets:
        if start == end:
            labels.append(-100)
            previous_entity = None
            continue
        entity_index = next(
            (i for i, entity in enumerate(entities)
             if entity["start"] <= start and end <= entity["end"]),
            None,
        )
        if entity_index is None:
            labels.append(0)
        else:
            labels.append(2 if entity_index == previous_entity else 1)
        previous_entity = entity_index
    return labels


def decode_spans(text, offsets, label_ids):
    spans = []
    active = None
    for (start, end), label_id in zip(offsets, label_ids):
        if start == end:
            continue
        if label_id == 1 or (label_id == 2 and active is None):
            if active is not None:
                spans.append(active)
            active = [start, end]
        elif label_id == 2:
            active[1] = end
        elif active is not None:
            spans.append(active)
            active = None
    if active is not None:
        spans.append(active)
    names = []
    for start, end in spans:
        name = text[start:end].strip()
        if name and name not in names:
            names.append(name)
    return names


class CourseExtractor:
    def __init__(self, model_dir):
        model_dir = Path(model_dir)
        if not (model_dir / "config.json").is_file():
            raise FileNotFoundError(f"Trained model missing in {model_dir}. Run train.py first.")
        self.tokenizer = AutoTokenizer.from_pretrained(model_dir, local_files_only=True)
        self.model = AutoModelForTokenClassification.from_pretrained(
            model_dir, local_files_only=True,
        ).eval()
        if self.model.config.id2label != dict(enumerate(LABELS)):
            raise ValueError("The checkpoint must use O, B-COURSE and I-COURSE labels.")

    def extract(self, text):
        encoded = self.tokenizer(text, return_offsets_mapping=True, return_tensors="pt")
        if encoded["input_ids"].shape[1] > MAX_TOKENS:
            raise ValueError(f"Text exceeds the {MAX_TOKENS}-token limit.")
        offsets = encoded.pop("offset_mapping")[0].tolist()
        with torch.inference_mode():
            predicted = self.model(**encoded).logits.argmax(dim=-1)[0].tolist()
        return decode_spans(text, offsets, predicted)
