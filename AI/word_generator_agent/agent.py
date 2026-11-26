from typing import List
from google.adk.agents import LlmAgent
from google.adk.tools import ToolContext
from .word_generator_instructions import word_generator_instruction
from pydantic import BaseModel, Field

class ContentList(BaseModel):
    content: List[str] = Field(description="List of words/sentences/ideoms/etc.")

root_agent = LlmAgent(
    name="WordGeneratorAgent",
    model="gemini-2.5-flash-lite",
    description="Generates words, sentences, and idioms for a given topic and language level, and stores them in the database.",
    instruction=word_generator_instruction,
    output_key="generated_content",
    output_schema=ContentList,
)