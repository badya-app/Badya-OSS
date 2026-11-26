from google.adk.agents import SequentialAgent
from .video_story_agent import video_story_agent, story_analyzer_agent, scenario_writer


root_agent = SequentialAgent(
    name="VideoStoryGeneratorSystem",
    description="A multi-agent system for generating cinematic and emotional story videos",
    sub_agents=[
        scenario_writer,
        video_story_agent,
        story_analyzer_agent 
    ]
)
