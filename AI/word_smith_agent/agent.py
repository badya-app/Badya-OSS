from google.adk.agents import LlmAgent
from google.adk.tools import ToolContext
from .word_smith_instructions import word_smith_instruction

from google.adk.models.google_llm import Gemini
from google.genai import types
from dotenv import load_dotenv

from google.genai import types

load_dotenv(override=True)

root_agent = LlmAgent(
    name="WordSmithAgent",
    model=Gemini(
        model="gemini-live-2.5-flash-native-audio",
        speech_config=types.SpeechConfig(
            voice_config=types.VoiceConfig(
                prebuilt_voice_config=types.PrebuiltVoiceConfig(voice_name="Aoede")
            )
        ),
    ),
    description="Teaches new words, defines them, gives examples, and asks the user to use them in different contexts.",
    instruction=word_smith_instruction,

    generate_content_config=types.GenerateContentConfig(
        temperature=1.3,
    ),
)
