import os
from dotenv import load_dotenv
from google.adk.agents import LlmAgent
from .chat_instructions import chat_instruction
from google.adk.tools.agent_tool import AgentTool

import sys
parent_dir_path = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
if parent_dir_path not in sys.path:
    sys.path.append(parent_dir_path)

from corrector_agent.agent import root_agent as corrector_agent

from google.adk.models.google_llm import Gemini
from google.genai import types

load_dotenv(override=True)

root_agent = LlmAgent(
    model=Gemini(
        model="gemini-live-2.5-flash-native-audio",
        speech_config=types.SpeechConfig(
            voice_config=types.VoiceConfig(
                prebuilt_voice_config=types.PrebuiltVoiceConfig(voice_name="Kore")
            )
        )
    ),
    name="QuizPresenter",
    description="Presents comprehension questions to users and evaluates their understanding",
    instruction=chat_instruction,
    output_key="quiz_result",
    tools=[AgentTool(corrector_agent)]
)




