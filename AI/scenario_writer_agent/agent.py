from google.adk.agents import LlmAgent
from .scenario_writer_instructions import scenario_writer_instruction

from google.genai import types
root_agent = LlmAgent(
    name="ScenarioWriter",
    model="gemini-2.5-flash",
    description="Generates immersive role-play scenarios based on topics and vocabulary.",
    instruction=scenario_writer_instruction,
    output_key="scenario",
    generate_content_config=types.GenerateContentConfig(
        temperature=1.8,
    ),
)
