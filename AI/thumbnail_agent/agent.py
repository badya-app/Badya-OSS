import os
import sys
from dotenv import load_dotenv
from google.adk.agents import LlmAgent
from google.adk.apps import App


load_dotenv()

thumbnail_instruction = """You are a creative prompt engineering expert for image generation models like Stable Diffusion and Stability AI.
Your goal is to transform user-provided content titles and descriptions (in any language) into high-quality, detailed English image generation prompts for thumbnails.

Guidelines:
1. Analyze the core themes, objects, and emotions in the title and description.
2. Translate the essence into a descriptive English prompt.
3. Include relevant artistic style descriptors such as "cinematic lighting", "8k resolution", "digital art", "photorealistic", "vibrant colors", etc., based on the context.
4. The output must be ONLY the final English prompt string, ready to be sent to an image generation API.
5. If the input is ambiguous or too short, expand it creatively to ensure a visually appealing thumbnail.
6. Ensure the prompt is safe and avoids sensitive content.

Inputs:
- Title: {title}
- Description: {description}
"""

thumbnail_prompt_agent = LlmAgent(
    name="ThumbnailPromptAgent",
    model="gemini-2.5-flash",
    description="Transforms content titles and descriptions into high-quality image generation prompts",
    instruction=thumbnail_instruction,
    output_key="image_prompt",
)

root_agent = thumbnail_prompt_agent

app = App(
    root_agent=root_agent,
    name="thumbnail_agent",
)
