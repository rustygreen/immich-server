FROM python:3.11-slim

WORKDIR /app

RUN pip install --no-cache-dir pyyaml requests

COPY watcher.py /app/

ENV CONFIG_PATH=/config/config.yaml

CMD ["python", "-u", "watcher.py"]
