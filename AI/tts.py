from google import genai
from google.genai import types
import wave
import os

PROJECT_ID = os.getenv("GOOGLE_CLOUD_PROJECT", "your-gcp-project-id")
LOCATION = os.getenv("GOOGLE_CLOUD_LOCATION", "us-central1")

# Set up the wave file to save the output:
def wave_file(filename, pcm, channels=1, rate=24000, sample_width=2):
  with wave.open(filename, "wb") as wf:
      wf.setnchannels(channels)
      wf.setsampwidth(sample_width)
      wf.setframerate(rate)
      wf.writeframes(pcm)

client = genai.Client(vertexai=True, project=PROJECT_ID, location=LOCATION)

response = client.models.generate_content(
  model="gemini-2.5-flash-tts",
  contents="Say the following in a curious way: OK, so... tell me about this [uhm] AI thing.",
  config=types.GenerateContentConfig(
      speech_config=types.SpeechConfig(
        language_code="en-in",
        voice_config=types.VoiceConfig(
            prebuilt_voice_config=types.PrebuiltVoiceConfig(
              voice_name='Kore',
            )
        )
      ),
  )
)

data = response.candidates[0].content.parts[0].inline_data.data

file_name='output_speech.wav'
wave_file(file_name, data) # Saves the file to current directory
