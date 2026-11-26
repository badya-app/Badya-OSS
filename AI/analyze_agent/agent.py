import os
from dotenv import load_dotenv
from google.adk.agents import LlmAgent
from .analyze_instructions import analyze_instructions
from .schema import AnalysisOutput

load_dotenv()

root_agent = LlmAgent(
    name="Analyze_Agent",
    model="gemini-2.5-flash",
    description="Analyze user's level of language proficiency based on their mistakes and provide structured scoring.",
    instruction=analyze_instructions,
    output_key="analysis_result",
    output_schema=AnalysisOutput
)
