"""
TTS generator module using Gemini 2.5 Flash with fallback to Google Cloud Text-to-Speech.
Provides text-to-speech generation for video agent.
"""

import io
import os
import wave
import base64
import asyncio
import logging
from typing import Any
import httpx
from google import genai
from google.genai import types
from dotenv import load_dotenv

load_dotenv()

# Configure logging (TASK-10/05)
logger = logging.getLogger(__name__)

# Language to BCP-47 Code Mapping (TASK-06)
LANGUAGE_TO_BCP47 = {
    "English": "en-US", "French": "fr-FR", "German": "de-DE",
    "Italian": "it-IT", "Japanese": "ja-JP", "Russian": "ru-RU",
    "Arabic": "ar-XA", "Portuguese": "pt-PT", "Spanish": "es-ES",
    "Korean": "ko-KR", "Dutch": "nl-NL", "Polish": "pl-PL",
    "Vietnamese": "vi-VN", "Thai": "th-TH", "Hindi": "hi-IN",
    "Greek": "el-GR", "Swedish": "sv-SE", "Danish": "da-DK",
    "Finnish": "fi-FI", "Hebrew": "iw-IL", "Indonesian": "id-ID",
    "Czech": "cs-CZ", "Romanian": "ro-RO", "Hungarian": "hu-HU",
    "Ukrainian": "uk-UA", "Turkish": "tr-TR", "Filipino": "fil-PH",
    "Bangla": "bn-IN", "Gujarati": "gu-IN", "Kannada": "kn-IN",
    "Malayalam": "ml-IN", "Marathi": "mr-IN", "Punjabi": "pa-IN",
    "Tamil": "ta-IN", "Telugu": "te-IN", "Urdu": "ur-IN",
    "Chinese, Mandarin": "cmn-CN", "Malay": "ms-MY",
    "Croatian": "hr-HR", "Slovak": "sk-SK", "Bulgarian": "bg-BG",
    "Serbian": "sr-RS", "Catalan": "ca-ES", "Latvian": "lv-LV",
    "Lithuanian": "lt-LT", "Estonian": "et-EE", "Swahili": "sw-KE",
    "Icelandic": "is-IS", "Georgian": "ka-GE", "Armenian": "hy-AM",
    "Azerbaijani": "az-AZ", "Slovenian": "sl-SI", "Albanian": "sq-AL",
    "Macedonian": "mk-MK", "Mongolian": "mn-MN", "Nepali": "ne-NP",
    "Sinhala": "si-LK", "Burmese": "my-MM", "Persian": "fa-IR",
    "Lao": "lo-LA", "Khmer": "km-KH", "Amharic": "am-ET",
}

def resolve_language_code(language: str) -> str:
    """Resolve a display language name to a BCP-47 code for Cloud TTS."""
    return LANGUAGE_TO_BCP47.get(language, "en-US")  # fallback to English

def _wrap_wav(
    pcm: bytes, channels: int = 1, rate: int = 24000, sample_width: int = 2
) -> bytes:
    buf = io.BytesIO()
    with wave.open(buf, "wb") as wf:
        wf.setnchannels(channels)
        wf.setsampwidth(sample_width)
        wf.setframerate(rate)
        wf.writeframes(pcm)
    return buf.getvalue()


async def generate_tts_via_api(text: str, language_code: str = "en-US") -> bytes:
    """
    Fallback method that calls Google Cloud Text-to-Speech REST API.
    Does not require native Gemini audio allowlisting. (TASK-06)
    """
    url = "https://texttospeech.googleapis.com/v1/text:synthesize"
    headers = {"Content-Type": "application/json"}

    if not os.getenv("GOOGLE_APPLICATION_CREDENTIALS"):
        from pathlib import Path

        # Cloud Run: mounted as Secret Manager volume (TASK-11)
        sa_path = Path("/secrets/sa-key/key.json")
        # Local dev: fallback to project root
        if not sa_path.exists():
            sa_path = Path(__file__).parent.parent / "serviceAccountKey.json"
        if sa_path.exists():
            os.environ["GOOGLE_APPLICATION_CREDENTIALS"] = str(sa_path)

    import google.auth
    from google.auth.transport.requests import Request

    credentials, project = google.auth.default(
        scopes=["https://www.googleapis.com/auth/cloud-platform"]
    )
    credentials.refresh(Request())
    headers["Authorization"] = f"Bearer {credentials.token}"

    payload = {
        "input": {"text": text},
        "voice": {"languageCode": language_code, "ssmlGender": "FEMALE"},
        "audioConfig": {"audioEncoding": "LINEAR16"},
    }

    async with httpx.AsyncClient() as client:
        response = await client.post(url, json=payload, headers=headers)
        response.raise_for_status()
        data = response.json()
        return _wrap_wav(base64.b64decode(data["audioContent"]))


async def generate_tts(text: str, language: str = "English", max_retries: int = 3) -> bytes:
    """
    Generates speech audio from text using Gemini 2.5 Flash TTS with REST API fallback.

    Args:
        text: The text to convert to speech.
        language: The target narration language.
        max_retries: Maximum retry attempts on failure.

    Returns:
        bytes: Raw audio data in WAV format.

    Raises:
        Exception: If all retry attempts fail.
    """
    os.environ.pop("GOOGLE_API_KEY", None)

    if not os.getenv("GOOGLE_APPLICATION_CREDENTIALS"):
        from pathlib import Path

        # Cloud Run: mounted as Secret Manager volume (TASK-11)
        sa_path = Path("/secrets/sa-key/key.json")
        # Local dev: fallback to project root
        if not sa_path.exists():
            sa_path = Path(__file__).parent.parent / "serviceAccountKey.json"
        if sa_path.exists():
            os.environ["GOOGLE_APPLICATION_CREDENTIALS"] = str(sa_path)

    client = genai.Client(
        vertexai=True,
        project=os.getenv("GOOGLE_CLOUD_PROJECT"),
        location=os.getenv("GOOGLE_CLOUD_LOCATION", "us-central1"),
    )
    model_id = "gemini-2.5-flash-tts"
    language_code = resolve_language_code(language)

    print(f"[TTS] Synthesizing speech ({len(text)} chars, language={language}, code={language_code})...", flush=True)

    for attempt in range(max_retries):
        try:
            print(f"[TTS] Attempt {attempt + 1}/{max_retries} with Gemini TTS ({model_id})...", flush=True)
            response = await client.aio.models.generate_content(
                model=model_id,
                contents=f"You are a storyteller. Read the following in an engaging way: {text}",
                config=types.GenerateContentConfig(
                    response_modalities=["AUDIO"],
                    speech_config=types.SpeechConfig(
                        voice_config=types.VoiceConfig(
                            prebuilt_voice_config=types.PrebuiltVoiceConfig(
                                voice_name="Algenib",
                            )
                        )
                    ),
                ),
            )

            # Extract audio bytes from the response
            audio_part = next(
                part
                for part in response.candidates[0].content.parts
                if part.inline_data
            )
            wav_bytes = _wrap_wav(audio_part.inline_data.data)
            print(f"[TTS] Gemini TTS succeeded ({len(wav_bytes)} WAV bytes).", flush=True)
            return wav_bytes

        except Exception as e:
            err_msg = str(e).lower()
            print(f"[TTS] Gemini TTS attempt {attempt + 1} error: {e}", flush=True)
            is_rate_limit    = any(k in err_msg for k in ["429", "resource_exhausted", "quota"])
            is_allowlist_err = any(k in err_msg for k in ["allowlisted", "allowlist"])

            # Trigger fallback immediately on allowlist; on rate-limit after last retry (TASK-05)
            if is_allowlist_err or (is_rate_limit and attempt == max_retries - 1):
                print(f"[TTS] Falling back to Google Cloud Text-to-Speech API (language={language_code})...", flush=True)
                logger.warning(f"Falling back to Google Cloud TTS API for language {language_code}...")
                try:
                    wav_bytes = await generate_tts_via_api(text, language_code=language_code)
                    print(f"[TTS] Fallback Google Cloud TTS succeeded ({len(wav_bytes)} WAV bytes).", flush=True)
                    return wav_bytes
                except Exception as api_err:
                    print(f"[TTS] Fallback Google Cloud TTS failed: {api_err}", flush=True)
                    logger.error(f"Fallback Google Cloud TTS API failed: {api_err}")
                    raise e

            if attempt == max_retries - 1:
                raise e

            # Exponential backoff before next retry (TASK-05)
            sleep_time = 2 ** (attempt + 1)   # 2s, 4s, 8s
            logger.warning(f"TTS attempt {attempt + 1} failed, retrying in {sleep_time}s — {e}")
            await asyncio.sleep(sleep_time)
