from google.adk.agents import LlmAgent
from .role_master_instructions import role_play_agent_instruction
from dotenv import load_dotenv
from google.adk.models.google_llm import Gemini
from google.genai import types

load_dotenv(override=True)

root_agent = LlmAgent(
    name="RolePlayConversationAgent",
    model=Gemini(
        model="gemini-live-2.5-flash-native-audio",
        speech_config=types.SpeechConfig(
            voice_config=types.VoiceConfig(
                prebuilt_voice_config=types.PrebuiltVoiceConfig(voice_name="Fenrir")
            )
        )
    ),
    description="Conducts the actual role-play conversation with the user.",
    instruction=role_play_agent_instruction,
    output_key="role_play_chat"
)
