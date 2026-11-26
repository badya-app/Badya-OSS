import asyncio
import os
import sys

# Add the parent directory to sys.path to allow importing modules from the project root
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "../../")))

from google.adk.runners import Runner
from google.adk.sessions import InMemorySessionService
from google.genai import types

from AI.analyze_agent.agent import root_agent

APP_NAME = "analyze_agent_test"
USER_ID = "test_user"
SESSION_ID = "test_session_1"


async def test_analyze_agent():
    mock_chat = """
    Bot: Read the story about the cat on the mat.
    User: The cat sat on the mat. It was happy.
    Bot: What color was the cat?
    User: It was black.
    Bot: Good! What did the cat do?
    User: It sit on mat.
    """

    # Build the message ADK expects
    message = types.Content(
        role="user",
        parts=[types.Part.from_text(text=mock_chat)],
    )

    session_service = InMemorySessionService()
    await session_service.create_session(
        app_name=APP_NAME, user_id=USER_ID, session_id=SESSION_ID
    )

    runner = Runner(
        agent=root_agent,
        app_name=APP_NAME,
        session_service=session_service,
    )

    print("Running Analyze Agent...")
    final_text = ""
    async for event in runner.run_async(
        user_id=USER_ID,
        session_id=SESSION_ID,
        new_message=message,
    ):
        if event.is_final_response() and event.content and event.content.parts:
            final_text = event.content.parts[0].text or ""

    print("\nRaw Agent Response:")
    print(final_text)

    # Retrieve the structured output stored in session state
    session = await session_service.get_session(
        app_name=APP_NAME, user_id=USER_ID, session_id=SESSION_ID
    )
    analysis_data = session.state.get("analysis_result") if session else None

    if analysis_data:
        print("\nStructured Data Verification:")
        print(f"Summary: {analysis_data.get('user_performance_summary', analysis_data)}")
        print(f"Understanding: {analysis_data.get('understanding_percentage')}")
        print(f"Expression:    {analysis_data.get('expression_percentage')}")
        print(f"Communication: {analysis_data.get('communication_percentage')}")
        print(f"Word Scores:   {analysis_data.get('word_scores')}")
    else:
        print("No analysis_result found in session state.")


if __name__ == "__main__":
    asyncio.run(test_analyze_agent())
