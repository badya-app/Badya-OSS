FROM python:3.13-slim
WORKDIR /app

# Install system dependencies for PyAudio and Whisper
RUN apt-get update && apt-get install -y gcc portaudio19-dev ffmpeg nodejs && rm -rf /var/lib/apt/lists/*

# Install uv for significantly faster Python package installation
RUN pip install uv

COPY requirements.txt .
RUN uv pip install --system --no-cache -r requirements.txt

COPY . .

CMD ["python", "main.py"]
