FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
# Bake the Silero model into the image so a cold start does not download it.
RUN python -c "import torch; torch.hub.download_url_to_file('https://models.silero.ai/models/tts/ru/v5_5_ru.pt', '/app/v5_5_ru.pt')"
COPY app.py .
ENV MALLOC_ARENA_MAX=2
EXPOSE 10000
CMD ["sh", "-c", "uvicorn app:app --host 0.0.0.0 --port ${PORT:-10000} --workers 1"]
