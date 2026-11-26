from google.adk.agents import SequentialAgent
from google.adk.apps import App
from .story_agent import story_writer, story_analyzer_agent, scenario_writer

root_agent = SequentialAgent(
    name="StoryGeneratorSystem",
    description="A multi-agent system for generating creative stories with structured elements",
    sub_agents=[
        scenario_writer,
        story_writer,
        story_analyzer_agent 
    ]
)

app = App(root_agent=root_agent, name="story_agent")

