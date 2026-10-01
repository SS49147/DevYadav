import argparse
import json
from pathlib import Path

from course_ner import CourseExtractor
from prepare_data import ROOT, build_splits


def main():
    parser = argparse.ArgumentParser(description="Evaluate exact course names on the held-out test split")
    parser.add_argument("--model-dir", type=Path, default=ROOT / "model" / "course-ner")
    args = parser.parse_args()
    extractor = CourseExtractor(args.model_dir)
    records = []
    true_positive = predicted_count = expected_count = exact_count = 0
    for example in build_splits()["test"]:
        text = example["text"]
        expected = [text[entity["start"]:entity["end"]] for entity in example["entities"]]
        predicted = extractor.extract(text)
        true_positive += len(set(expected) & set(predicted))
        predicted_count += len(set(predicted))
        expected_count += len(set(expected))
        exact_count += set(expected) == set(predicted)
        records.append({"text": text, "expected": expected, "predicted": predicted})
    precision = true_positive / predicted_count if predicted_count else 0
    recall = true_positive / expected_count if expected_count else 0
    report = {
        "base_model": extractor.model.config.course_base_model,
        "hidden_layers": extractor.model.config.num_hidden_layers,
        "hidden_size": extractor.model.config.hidden_size,
        "examples": len(records), "expected_entities": expected_count, "predicted_entities": predicted_count,
        "correct_entities": true_positive, "precision": precision, "recall": recall,
        "f1": 2 * precision * recall / (precision + recall) if precision + recall else 0,
        "exact_match_accuracy": exact_count / len(records), "predictions": records,
    }
    path = ROOT / "evidence" / "test-metrics.json"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({key: value for key, value in report.items() if key != "predictions"}, indent=2))


if __name__ == "__main__":
    main()
