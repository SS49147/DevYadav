FROM python:3.8-slim
WORKDIR /app
COPY app.py test_app.py /app/
RUN pip install --no-cache-dir flask
CMD ["python", "app.py"]
