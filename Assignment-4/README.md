# Assignment 4: Course Name Extraction

## Aim

Fine-tune a pretrained language model to identify course names in text, then deploy the trained model through FastAPI in Docker.

Reference: [SunagP's course-name extraction exercise](https://github.com/SunagP/DevOps-Lab/blob/main/Assignments/Docker-LLM-FineTune-Deploy-as-Docker.md). The source lists this as an unnumbered exercise after the three assignment PDFs. It is stored here as Assignment 4 for repository organization.

## Dataset and model

The dataset is a synthetic lab catalogue, not an official college course list. It includes sentences containing one or two course names and sentences containing no course names. The training, validation and test sets use different course names and sentence templates.

| Split | Examples | Course titles |
|---|---:|---:|
| Training | 442 | 36 |
| Validation | 42 | 8 |
| Test | 42 | 8 |

Each course name is recorded as a character span. Tokenization converts these spans into `B-COURSE`, `I-COURSE` and `O` labels. Special tokens receive `-100` so they are excluded from the training loss. Predictions are joined using tokenizer offsets to preserve the spelling in the original text.

The model is `dbmdz/bert-large-cased-finetuned-conll03-english`, the BERT-large checkpoint named in SunagP's exercise. Its original entity-classification head is replaced with the three course labels before fine-tuning. The base checkpoint revision is pinned in `train.py`.

## Train locally

Use Python 3.12. Run these commands from this folder:

```powershell
py -3.12 -m venv .venv
.\.venv\Scripts\python.exe -m pip install torch==2.6.0 --index-url https://download.pytorch.org/whl/cpu
.\.venv\Scripts\python.exe -m pip install -r requirements-training.txt -r requirements-test.txt
.\.venv\Scripts\python.exe prepare_data.py
.\.venv\Scripts\python.exe train.py
.\.venv\Scripts\python.exe evaluate_model.py
.\.venv\Scripts\python.exe -m pytest -q
```

Training uses Hugging Face `Dataset.from_pandas()`, `AutoTokenizer`, `AutoModelForTokenClassification` and `Trainer`. It uses three epochs, batch size 4 and learning rate `2e-5`, matching the reference's sample training settings. Seed 42 keeps the run reproducible. Validation F1 selects the checkpoint; evaluation then uses the separate test split.

The trained model and tokenizer are saved under `model/course-ner`. Generated weights and training checkpoints are excluded from Git; source data, scripts and recorded results are included. An internet connection is needed for the initial pretrained model and package downloads.

BERT-large training needs several gigabytes of available RAM and takes longer on CPU. Sentence batches use dynamic padding. Checkpoints save model weights without optimizer state to reduce disk use; those checkpoints are for evaluation, not resuming interrupted training.

## FastAPI

After local training:

```powershell
.\.venv\Scripts\python.exe -m uvicorn app:app --host 127.0.0.1 --port 8004
```

Send a request:

```powershell
$body = '{"text":"The college offers Machine Learning and Operating Systems."}'
Invoke-RestMethod -Method Post -Uri http://localhost:8004/extract-course-name/ -ContentType application/json -Body $body
```

The response has the format:

```json
{
  "extracted_course_names": ["Machine Learning", "Operating Systems"]
}
```

Swagger documentation is at [localhost:8004/docs](http://localhost:8004/docs). `GET /health` confirms the model has loaded. Text without courses returns an empty list; invalid input returns HTTP 422. Input is limited to 4,000 characters and 256 tokens so longer text is rejected rather than silently cut off.

## Docker deployment

```powershell
docker compose up --build -d
docker compose ps
.\.venv\Scripts\python.exe verify_api.py
```

The image build runs fine-tuning in a separate training stage and copies the saved checkpoint into the final image. This lets a fresh checkout build a working API without an existing local model. The first build downloads the dependencies and model; subsequent builds use Docker's cache. Inference runs from the packaged checkpoint without contacting Hugging Face.

The container listens on port 80, mapped to `127.0.0.1:8004` on the laptop. To build and run without Compose:

```powershell
docker build -t course-extraction-api .
docker run -d --name assignment4-course-api -p 127.0.0.1:8004:80 course-extraction-api
```

Use either Compose or the manual command, since both use the same container name and host port. Stop the Compose deployment with `docker compose down`.

## Results

[RESULTS.md](RESULTS.md) records training, test-set evaluation and the running API checks. Raw metrics and responses are in `evidence/`. GitHub Actions runs the API and label-processing tests without downloading a model; the locally trained checkpoint is tested separately during execution.

## Viva notes

- Fine-tuning updates the pretrained model weights for the course-labeling task. Inference uses those saved weights to predict labels for new text.
- `B-COURSE` begins a course span, `I-COURSE` continues it and `O` marks other text.
- Token offsets connect subword predictions to the original characters. Returning the whole input would not extract course names from a sentence.
- Validation selects a checkpoint. The separate test set measures extraction on course titles not used for training.
- The Docker training stage needs the dataset and training libraries. The final image only needs the API, inference libraries and saved checkpoint.
- These results describe a small synthetic dataset. They do not establish accuracy for arbitrary college brochures.
