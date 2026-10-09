FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY delivery_metrics.py test_metrics.py /app/
EXPOSE 8000
CMD ["python", "delivery_metrics.py"]
