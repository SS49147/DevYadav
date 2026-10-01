import pytest

from course_ner import CourseExtractor, align_labels, decode_spans
from prepare_data import build_splits, ROOT


def test_span_labels_cover_subwords_and_ignore_special_tokens():
    offsets = [(0, 0), (0, 3), (4, 8), (8, 11), (12, 14), (0, 0)]
    assert align_labels(offsets, [{"start": 4, "end": 11}]) == [-100, 0, 1, 2, 0, -100]


def test_decode_preserves_original_spelling_and_separates_courses():
    text = "Study Machine Learning and DevOps."
    offsets = [(0, 0), (0, 5), (6, 13), (14, 22), (23, 26), (27, 30), (30, 33), (33, 34)]
    assert decode_spans(text, offsets, [0, 0, 1, 2, 0, 1, 2, 0]) == ["Machine Learning", "DevOps"]


def test_no_entities_returns_empty_list():
    assert decode_spans("The library is open.", [(0, 3), (4, 11)], [0, 0]) == []


def test_adjacent_begin_labels_create_separate_entities():
    assert decode_spans("Physics Chemistry", [(0, 7), (8, 17)], [1, 1]) == ["Physics", "Chemistry"]


def test_repeated_courses_are_returned_once():
    assert decode_spans("DevOps DevOps", [(0, 6), (7, 13)], [1, 1]) == ["DevOps"]


def test_training_validation_and_test_texts_do_not_overlap():
    splits = build_splits()
    texts = {key: {item["text"] for item in rows} for key, rows in splits.items()}
    assert not texts["train"] & texts["validation"]
    assert not texts["train"] & texts["test"]
    assert not texts["validation"] & texts["test"]
    for rows in splits.values():
        for row in rows:
            for entity in row["entities"]:
                assert 0 <= entity["start"] < entity["end"] <= len(row["text"])


def test_missing_checkpoint_fails_explicitly(tmp_path):
    with pytest.raises(FileNotFoundError, match="Run train.py first"):
        CourseExtractor(tmp_path)


@pytest.mark.skipif(not (ROOT / "model" / "course-ner" / "config.json").exists(), reason="Train the checkpoint first")
def test_trained_checkpoint_extracts_real_course_spans():
    extractor = CourseExtractor(ROOT / "model" / "course-ner")
    assert extractor.extract("The college offers Machine Learning and Operating Systems.") == [
        "Machine Learning", "Operating Systems",
    ]
    assert extractor.extract("The library closes at five.") == []
