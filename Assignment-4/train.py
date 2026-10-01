import argparse
import json
import os
from pathlib import Path

import numpy as np
import pandas as pd
import torch
from datasets import Dataset
from seqeval.metrics import accuracy_score, f1_score, precision_score, recall_score
from transformers import (
    AutoModelForTokenClassification, AutoTokenizer, DataCollatorForTokenClassification,
    Trainer, TrainingArguments, set_seed,
)

from course_ner import LABELS, align_labels
from prepare_data import ROOT, build_splits


def tokenize_dataset(examples, tokenizer):
    dataset = Dataset.from_pandas(pd.DataFrame(examples), preserve_index=False)

    def tokenize(batch):
        encoded = tokenizer(batch["text"], truncation=True, max_length=128, return_offsets_mapping=True)
        encoded["labels"] = [align_labels(offsets, entities)
                             for offsets, entities in zip(encoded.pop("offset_mapping"), batch["entities"])]
        return encoded

    return dataset.map(tokenize, batched=True, remove_columns=dataset.column_names)


def compute_metrics(prediction):
    predicted = np.argmax(prediction.predictions, axis=2)
    references = [[LABELS[label] for label in row if label != -100] for row in prediction.label_ids]
    predictions = [[LABELS[value] for value, label in zip(row, labels) if label != -100]
                   for row, labels in zip(predicted, prediction.label_ids)]
    return {
        "precision": precision_score(references, predictions, zero_division=0),
        "recall": recall_score(references, predictions, zero_division=0),
        "f1": f1_score(references, predictions, zero_division=0),
        "token_accuracy": accuracy_score(references, predictions),
    }


def main():
    parser = argparse.ArgumentParser(description="Fine-tune a course-name token classifier")
    parser.add_argument("--base-model", default="prajjwal1/bert-mini")
    parser.add_argument("--base-revision", default=None)
    parser.add_argument("--epochs", type=int, default=3)
    parser.add_argument("--learning-rate", type=float, default=3e-4)
    parser.add_argument("--model-dir", type=Path, default=ROOT / "model" / "course-ner")
    parser.add_argument("--report", type=Path, default=ROOT / "evidence" / "training-metrics.json")
    args = parser.parse_args()
    set_seed(42)
    torch.set_num_threads(int(os.getenv("TORCH_NUM_THREADS", "4")))
    splits = build_splits()
    revision = args.base_revision
    if revision is None and args.base_model == "prajjwal1/bert-mini":
        revision = "5e123abc2480f0c4b4cac186d3b3f09299c258fc"
    tokenizer = AutoTokenizer.from_pretrained(args.base_model, revision=revision, use_fast=True)
    model = AutoModelForTokenClassification.from_pretrained(
        args.base_model, num_labels=len(LABELS), id2label=dict(enumerate(LABELS)),
        label2id={label: i for i, label in enumerate(LABELS)}, ignore_mismatched_sizes=True,
        revision=revision,
    )
    training = tokenize_dataset(splits["train"], tokenizer)
    validation = tokenize_dataset(splits["validation"], tokenizer)
    arguments = TrainingArguments(
        output_dir=str(ROOT / "training-output"), eval_strategy="epoch", save_strategy="epoch",
        learning_rate=args.learning_rate, per_device_train_batch_size=8,
        per_device_eval_batch_size=16, num_train_epochs=args.epochs, weight_decay=0.01,
        warmup_ratio=0.1, load_best_model_at_end=True, metric_for_best_model="f1",
        save_total_limit=1, report_to="none", logging_steps=25, seed=42, use_cpu=True,
    )
    trainer = Trainer(
        model=model, args=arguments, train_dataset=training, eval_dataset=validation,
        processing_class=tokenizer, data_collator=DataCollatorForTokenClassification(tokenizer),
        compute_metrics=compute_metrics,
    )
    baseline_metrics = trainer.evaluate()
    result = trainer.train()
    validation_metrics = trainer.evaluate()
    trainer.save_model(args.model_dir)
    tokenizer.save_pretrained(args.model_dir)
    report = {
        "base_model": args.base_model, "base_revision": model.config._commit_hash,
        "seed": 42, "epochs": args.epochs, "learning_rate": args.learning_rate,
        "batch_size": 8, "device": "cpu", "parameters": sum(p.numel() for p in model.parameters()),
        "split_sizes": {key: len(value) for key, value in splits.items()},
        "train": result.metrics, "baseline_validation": baseline_metrics, "validation": validation_metrics,
        "best_checkpoint": Path(trainer.state.best_model_checkpoint).name,
    }
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
