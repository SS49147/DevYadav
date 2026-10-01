import json
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parent
TEMPLATES = {
    "train": [
        "{a}", "The college offers {a}.", "I enrolled in {a} this semester.",
        "Students can choose {a} or {b}.", "Courses available: {a}, {b}.",
        "The syllabus includes {a} and {b}.", "Registration for {a} closes on Friday.",
        "She completed {a} before taking {b}.", "Is {a} offered this year?",
        "The brochure lists {a}; students also study {b}.",
        "Please add {a} to my timetable.", "We teach {a} in the morning and {b} in the afternoon.",
    ],
    "validation": [
        "Applications are open for {a}.", "Available electives include {a} and {b}.",
        "My department introduced {a} this year.", "I want to study {a} after finishing {b}.",
    ],
    "test": [
        "The college now teaches {a}.", "Next term I plan to take {a} and {b}.",
        "Our new course list contains {a}, followed by {b}.", "Can I register for {a} this semester?",
    ],
}
NEGATIVE_TEXTS = [
    "The library closes at five in the evening.", "Admissions open next Monday.",
    "The college offers hostel accommodation.", "Bring your student ID to the office.",
    "The cafeteria serves lunch at noon.", "The annual festival takes place in October.",
    "Students attended the orientation meeting.", "The examination hall is on the second floor.",
    "Please pay the semester fees before Friday.", "There are no classes tomorrow.",
    "The principal welcomed the visitors.", "I borrowed two books from the library.",
    "The buses leave the campus at four.", "A new sports centre opened this year.",
    "The department office is closed on Sunday.", "We discussed the weather after lunch.",
    "She met her friends near the auditorium.", "The notice board has been replaced.",
    "Campus maintenance starts this weekend.", "The students arranged chairs for the event.",
    "Please submit the application at the reception desk.", "The hostel gates close at nine.",
    "I walked to the station this morning.", "Staff members attended a planning meeting.",
    "Parking is available behind the main building.", "We visited the campus on Tuesday.",
    "The bookstore sells notebooks and pencils.", "The office will send a confirmation email.",
    "The auditorium has two hundred seats.", "A notice was posted about the holiday.",
]


def make_example(template, a, b):
    text = template.format(a=a, b=b)
    entities = []
    for name in (a, b):
        for match in re.finditer(re.escape(name), text):
            entity = {"start": match.start(), "end": match.end(), "label": "COURSE"}
            if entity not in entities:
                entities.append(entity)
    return {"text": text, "entities": sorted(entities, key=lambda item: item["start"])}


def build_splits():
    catalog = json.loads((ROOT / "data" / "courses.json").read_text(encoding="utf-8"))
    splits = {}
    for split_index, (split, templates) in enumerate(TEMPLATES.items()):
        courses = catalog[split]
        examples = [
            make_example(template, course, courses[(index + 3) % len(courses)])
            for index, course in enumerate(courses)
            for template in templates
        ]
        examples.extend({"text": text, "entities": []}
                        for text in NEGATIVE_TEXTS[split_index * 10:(split_index + 1) * 10])
        splits[split] = examples
    return splits


def main():
    for split, examples in build_splits().items():
        path = ROOT / "data" / f"{split}.jsonl"
        path.write_text("".join(json.dumps(example) + "\n" for example in examples), encoding="utf-8")
        print(f"{split}: {len(examples)} examples -> {path.name}")


if __name__ == "__main__":
    main()
