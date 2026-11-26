from google.genai import types
from dotenv import load_dotenv
from google.adk.agents import LlmAgent
from .story_instructions import (
    scenario_instruction,
    story_instruction,
    questions_instruction,
)
import os

import sys

parent_dir_path = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
if parent_dir_path not in sys.path:
    sys.path.append(parent_dir_path)

from generators.image_generator import generate_image_tool

load_dotenv()


########## Agents ##########

scenario_writer = LlmAgent(
    name="ScenarioWriter",
    model="gemini-2.5-flash",
    description="Generates a summary and scenarios for a story subject",
    instruction=scenario_instruction,
    output_key="scenario",
    generate_content_config=types.GenerateContentConfig(
        temperature=1.8,
    ),
)

story_writer = LlmAgent(
    name="StoryWriter",
    model="gemini-2.5-flash",
    description="Generates compelling stories with exciting plots and powerful endings",
    instruction=story_instruction,
    output_key="story",
    tools=[generate_image_tool],
)

story_analyzer_agent = LlmAgent(
    model="gemini-2.5-flash",
    name="StoryAnalyzer",
    description="Analyzes stories and generates comprehension questions to test understanding",
    instruction=questions_instruction,
    output_key="analysis_result",
)
