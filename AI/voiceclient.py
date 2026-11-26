import asyncio
import pyaudio
import websockets
import json
import base64
import uuid
import os
import sys
from contextlib import contextmanager
import httpx  # Required for creating the session

# --- Configuration ---
import os
import sys

SERVER_HOST = os.getenv("VOICE_SERVER_HOST", "127.0.0.1")
SERVER_PORT = int(os.getenv("VOICE_SERVER_PORT", "8000"))
USER_ID = f"voice_client_{uuid.uuid4()}"
APP_NAME = "wordsmith"
HTTP_BASE_URL = f"http://{SERVER_HOST}:{SERVER_PORT}"
WEBSOCKET_URL_TEMPLATE = f"ws://{SERVER_HOST}:{SERVER_PORT}/ws/apps/{{app_name}}/users/{{user_id}}/sessions/{{session_id}}"
# ----------------------
# --- PyAudio Configuration ---
FORMAT = pyaudio.paInt16
CHANNELS = 1
SEND_SAMPLE_RATE = 16000  # Rate for microphone input
RECEIVE_SAMPLE_RATE = 24000 # Rate for speaker output (matches server)
CHUNK_SIZE = 1024

@contextmanager
def ignore_stderr():
    """Context manager to suppress stderr noise from libraries like ALSA/PyAudio."""
    devnull = os.open(os.devnull, os.O_WRONLY)
    old_stderr = os.dup(sys.stderr.fileno())
    os.dup2(devnull, sys.stderr.fileno())
    try:
        yield
    finally:
        os.dup2(old_stderr, sys.stderr.fileno())
        os.close(devnull)
        os.close(old_stderr)

with ignore_stderr():
    pya = pyaudio.PyAudio()

# Queues for audio data
audio_queue_output = asyncio.Queue()
audio_queue_mic = asyncio.Queue()

def safe_base64_decode(base64_string):
    """
    Decodes Google's URL-safe, unpadded Base64 strings.
    """
    pad_len = len(base64_string) % 4
    if pad_len > 0:
        base64_string += '=' * (4 - pad_len)
    return base64.urlsafe_b64decode(base64_string)

async def create_session(app_name: str, user_id: str) -> str | None:
    """Creates a session via HTTP POST by letting the server generate the ID."""
    url = f"{HTTP_BASE_URL}/apps/{app_name}/users/{user_id}/sessions"
    try:
        async with httpx.AsyncClient() as client:
            # Send an empty body; the server will generate and return the session ID.
            response = await client.post(url, json={})
            response.raise_for_status()
            session_data = response.json()
            session_id = session_data.get("id")
            if session_id:
                print(f"✅ Session created successfully: {session_id}")
                return session_id
            else:
                print(f"[ERROR] Server response did not contain a session_id. Response: {session_data}")
                return None
    except httpx.RequestError as e:
        print(f"[ERROR] HTTP request to create session failed: {e}")
        return None
    except httpx.HTTPStatusError as e:
        print(f"[ERROR] Failed to create session. Status {e.response.status_code}: {e.response.text}")
        return None

async def listen_audio_task():
    """Listens for audio from the microphone and puts it into the mic queue."""
    stream = None
    try:
        with ignore_stderr():
            stream = await asyncio.to_thread(
                pya.open,
                format=FORMAT,
                channels=CHANNELS,
                rate=SEND_SAMPLE_RATE,
                input=True,
                frames_per_buffer=CHUNK_SIZE,
            )
        print("🎤 Microphone is listening... Start speaking!")
        while True:
            data = await asyncio.to_thread(stream.read, CHUNK_SIZE, exception_on_overflow=False)
            await audio_queue_mic.put(data)
    except asyncio.CancelledError:
        pass
    except Exception as e:
        print(f"[ERROR] Microphone error: {e}")
    finally:
        if stream:
            with ignore_stderr():
                stream.stop_stream()
                stream.close()

async def send_audio_task(websocket):
    """Sends audio from the mic queue to the WebSocket as a LiveRequest blob."""
    try:
        while True:
            data = await audio_queue_mic.get()
            # Send audio as binary WebSocket frame (Production ready: ArrayBuffer equivalent)
            await websocket.send(data)
    except (asyncio.CancelledError, websockets.exceptions.ConnectionClosed):
        pass
    except Exception as e:
        print(f"[ERROR] Error sending audio: {e}")

async def receive_messages_task(websocket):
    """Receives Event messages from WebSocket, queues audio for playback, and prints transcripts."""
    last_speaker = None
    try:
        async for message in websocket:
            if isinstance(message, bytes):
                # Binary frame: Audio PCM data (24kHz, 16-bit, mono)
                await audio_queue_output.put(message)
                continue

            try:
                # Text frame: Metadata JSON
                event = json.loads(message)
                
                # Optional: Log event for debugging
                with open("out.txt", "a") as f:
                    f.write(str(event) + "\n")

            except json.JSONDecodeError:
                print(f"\n[ERROR] Could not decode JSON message: {message}")
                continue

            # Process metadata (transcriptions, etc.)
            input_transcription = event.get("inputTranscription")
            if input_transcription and input_transcription.get("text"):
                if last_speaker != "user":
                    print("\n")
                    print("User", end=": ", flush=True)
                    last_speaker = "user"
                print(input_transcription['text'], end="", flush=True)

            output_transcription = event.get("outputTranscription")
            if output_transcription and output_transcription.get("text"):
                if last_speaker != "bot":
                    print("\n")
                    print("Assistant", end=": ", flush=True)
                    last_speaker = "bot"
                print(output_transcription['text'], end="", flush=True)

    except websockets.exceptions.ConnectionClosed as e:
        print(f"\n[INFO] Connection closed: {e.reason} (code: {e.code})")
    except asyncio.CancelledError:
        pass
    except Exception as e:
        print(f"\n[ERROR] Error processing message: {e}")

async def play_audio_task():
    """Continuously plays audio data from the output queue."""
    stream = None
    try:
        with ignore_stderr():
            stream = await asyncio.to_thread(
                pya.open, format=FORMAT, channels=CHANNELS, rate=RECEIVE_SAMPLE_RATE, output=True
            )
        
        while True:
            audio_data = await audio_queue_output.get()
            if audio_data is None: break
            await asyncio.to_thread(stream.write, audio_data)
    except asyncio.CancelledError:
        pass
    except Exception as e:
        print(f"[ERROR] Audio playback error: {e}")
    finally:
        if stream:
            with ignore_stderr():
                stream.stop_stream()
                stream.close()

async def main():
    """Main function to create a session, then connect and run the voice client."""
    print("Attempting to create a session...")
    session_id = await create_session(APP_NAME, USER_ID)
    
    if not session_id:
        print("[FATAL] Could not start the client without a session ID.")
        return

    websocket_url = WEBSOCKET_URL_TEMPLATE.format(app_name=APP_NAME, user_id=USER_ID, session_id=session_id)
    print(f"Connecting to WebSocket at {websocket_url}...")
    
    try:
        async with websockets.connect(websocket_url) as ws:
            print("🔗 Connected to WebSocket! Voice client is live.")
            
            all_tasks = {
                asyncio.create_task(listen_audio_task(), name="listen"),
                asyncio.create_task(send_audio_task(ws), name="send"),
                asyncio.create_task(receive_messages_task(ws), name="receive"),
                asyncio.create_task(play_audio_task(), name="play")
            }
            done, pending = await asyncio.wait(all_tasks, return_when=asyncio.FIRST_COMPLETED)

            for task in pending:
                task.cancel()
            await asyncio.gather(*pending, return_exceptions=True)

    except ConnectionRefusedError:
        print(f"[ERROR] Connection failed. Is the server running at {SERVER_HOST}:{SERVER_PORT}?")
    except websockets.exceptions.InvalidURI:
        print(f"[ERROR] Invalid WebSocket URI: {websocket_url}")
    except websockets.exceptions.ConnectionClosedError as e:
        print(f"[ERROR] Connection closed unexpectedly: {e.reason} (code: {e.code})")
    except Exception as e:
        print(f"[CRITICAL ERROR] An unexpected error occurred: {e}")

if __name__ == "__main__":
    try:
        # Remember to run `pip install httpx` if you haven't already
        asyncio.run(main())
    except KeyboardInterrupt:
        print("\n[INFO] Client stopped by user.")
    finally:
        with ignore_stderr():
            pya.terminate()
        print("[INFO] PyAudio resources released.")
