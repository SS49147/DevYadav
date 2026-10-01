# Execution Results

Run date: 1 October 2026.

## Fine-tuning

The Docker training stage fine-tuned `prajjwal1/bert-mini` on 442 synthetic examples for three epochs. It used CPU, batch size 8, learning rate `3e-4` and seed 42. The selected checkpoint was `checkpoint-168` from epoch 3. The test split was not used to select the checkpoint.

| Measurement | Result |
|---|---:|
| Validation entity F1 before fine-tuning | 4.47% |
| Validation entity F1 after fine-tuning | 97.96% |
| Test exact-course precision | 75.86% |
| Test exact-course recall | 91.67% |
| Test exact-course F1 | 83.02% |
| Test sentences with all names correct | 35 / 42 |

The test contained 48 course entities. The model returned 58 names, of which 44 were exact matches. Evaluation used the checkpoint copied from the built Docker image; the running API produced the same predictions for all 42 test sentences.

Raw records: [training metrics](evidence/training-metrics.json) and [all test predictions](evidence/test-metrics.json).

## Application and Docker checks

| Check | Result |
|---|---|
| Local pytest run, including the trained checkpoint | 16 passed, 0 skipped |
| Health endpoint and six POST requests | 7 checks passed |
| Docker Compose configuration | Valid |
| Container health | Healthy |
| Container user | `appuser` |
| Container / laptop ports | `80` / `8004` |

The POST checks covered the reference example, two names in a sentence, previously unseen course titles, text without a course, whitespace-only input and the token limit. The last two returned HTTP 422. The weights are packaged in the image and loaded locally during startup.

For the reference request:

```json
{"text": "Introduction to Artificial Intelligence"}
```

the API returned HTTP 200:

```json
{"extracted_course_names": ["Introduction to Artificial Intelligence"]}
```

[API responses](evidence/api-responses.json) · [pytest report](evidence/test-results.xml)

The following screenshot shows an executed Swagger request, not the example response schema:

![Swagger request and actual HTTP 200 response](evidence/swagger-extraction.png)

## Observations

The model still makes mistakes. Some test sentences split `Introduction to Artificial Intelligence` into two names, and the bookstore sentence incorrectly produced `notebooks` and `pencils`. These errors are retained in the test report. The dataset is small and synthetic, so the results should not be treated as accuracy on real college brochures.

The first container startup could not read the saved weights because the training stage created them with owner-only permissions. Giving the copied model files to `appuser` fixed the startup; the rebuilt container passed the health and extraction checks.

The implementation follows the exercise's dataset, Hugging Face training, FastAPI endpoint, Docker build/run and POST testing steps. It uses a smaller pretrained BERT and Python 3.12 instead of the example's BERT-large and Python 3.8. The container still serves on port 80; host port 8004 keeps this assignment separate from the earlier services.
