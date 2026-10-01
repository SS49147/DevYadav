FROM python:3.12-slim AS dependencies

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    TORCH_NUM_THREADS=2
WORKDIR /app
RUN pip install --no-cache-dir torch==2.6.0 --index-url https://download.pytorch.org/whl/cpu
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

FROM dependencies AS training
COPY requirements-training.txt .
RUN pip install --no-cache-dir -r requirements-training.txt
COPY data/courses.json data/courses.json
COPY course_ner.py prepare_data.py train.py ./
ARG BASE_MODEL=prajjwal1/bert-mini
ARG EPOCHS=3
RUN python train.py --base-model "$BASE_MODEL" --epochs "$EPOCHS"

FROM dependencies AS runtime
COPY --from=training --chown=10001:10001 /app/model/course-ner /app/model/course-ner
COPY --from=training --chown=10001:10001 /app/evidence/training-metrics.json /app/model/training-metrics.json
COPY app.py course_ner.py ./
RUN useradd --uid 10001 --create-home appuser
USER appuser
EXPOSE 80
HEALTHCHECK --interval=15s --timeout=5s --start-period=30s --retries=4 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:80/health')"
CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "80"]
