FROM python:3.12-slim

# Basic hardening + smaller image
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY qbit_force_seed.py /app/qbit_force_seed.py
RUN chmod +x /app/qbit_force_seed.py

CMD ["/app/qbit_force_seed.py"]
