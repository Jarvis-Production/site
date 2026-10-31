FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
# Bake the Russian Piper voices into the image so a cold start downloads nothing.
RUN mkdir -p /app/voices && cd /app/voices && for v in dmitri denis ruslan irina; do \
      base=https://huggingface.co/rhasspy/piper-voices/resolve/main/ru/ru_RU/$v/medium/ru_RU-$v-medium; \
      python -c "import urllib.request,sys; [urllib.request.urlretrieve(sys.argv[1]+e, sys.argv[2]+e) for e in ('.onnx','.onnx.json')]" $base ru_RU-$v-medium; \
    done
COPY app.py .
ENV MALLOC_ARENA_MAX=2
EXPOSE 10000
CMD ["sh", "-c", "uvicorn app:app --host 0.0.0.0 --port ${PORT:-10000} --workers 1"]
