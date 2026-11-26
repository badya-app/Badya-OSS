from google.adk.agents import LlmAgent
from .video_story_instructions import (
    video_story_instruction,
    questions_instruction,
    scenario_instruction,
)
from google.adk.tools import ToolContext, BaseTool
from google.adk.models.llm_request import LlmRequest
from io import BytesIO
import cv2
import os
from dotenv import load_dotenv
import tempfile
import numpy as np
from google.genai import types
from moviepy import (
    ImageClip,
    AudioFileClip,
    CompositeVideoClip,
    concatenate_videoclips,
    VideoClip,
)
import wave
from PIL import Image, ImageFilter, ImageDraw
import random
import asyncio
from typing import List
import uuid
import os

import logging
import sys

parent_dir_path = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
if parent_dir_path not in sys.path:
    sys.path.append(parent_dir_path)

from generators.image_generator import generate_image
from generators.tts_generator import generate_tts

load_dotenv()

logger = logging.getLogger(__name__)

# Control the maximum number of parallel processes for segment generation
MAX_CONCURRENT_SEGMENTS = 3


def create_waveform_clip(audio_samples, framerate, duration, size, fps=30):
    w, h = int(size[0]), int(size[1])
    mid_y = h // 2

    # 1. Audio Setup (Same as before)
    max_val = np.max(np.abs(audio_samples))
    samples = audio_samples.astype(float) / (max_val if max_val > 0 else 1)

    window_secs = 0.1
    envelope_window = int(framerate * window_secs)
    if envelope_window % 2 == 0:
        envelope_window += 1
    kernel = np.ones(envelope_window) / envelope_window
    full_envelope = np.convolve(np.abs(samples), kernel, mode="same")

    # Pre-calculate X coordinates
    # OpenCV is fast, we don't need to skip pixels. Step = 1 is fine.
    x_vals = np.arange(0, w, 2)
    norm_x = (x_vals - w / 2) / (w / 2)
    edge_window = np.exp(-4.0 * norm_x**2)

    # Pre-allocate particle arrays for speed
    # Structure: [x, y, vx, vy, life, max_life, color_type]
    max_particles = 100
    particles = np.zeros((max_particles, 7), dtype=np.float32)

    def make_frame(t):
        # 1. Create a BLACK canvas (H, W, 4) - 4 channels for RGBA
        # Using uint8 is much faster for OpenCV
        img = np.zeros((h, w, 4), dtype=np.uint8)

        idx = int(t * framerate)
        vol = full_envelope[idx] if 0 <= idx < len(full_envelope) else 0

        # Physics modifiers
        amp_scale = vol * (h * 0.5)
        freq_mod = 1.0 + vol * 3.0

        # --- FAST WAVE DRAWING ---
        # We calculate points using Vectorized NumPy (no loops)

        # Wave 1: Cyan
        curr_freq = 0.015 * freq_mod
        phase = t * 5.0
        y_vals = (
            np.sin(curr_freq * x_vals * 50 + phase)
            * (amp_scale + h * 0.01)
            * edge_window
        )
        if vol > 0.1:
            y_vals += np.sin(x_vals * 0.1 + t * 25) * (vol * h * 0.05)

        # Stack X and Y into (N, 1, 2) array required by OpenCV polylines
        pts_y = (mid_y + y_vals).astype(np.int32)
        pts = np.column_stack((x_vals, pts_y)).reshape((-1, 1, 2))

        # DRAWING TRICK:
        # Instead of multiple transparent lines, we draw:
        # 1. Thick line (Glow)
        # 2. Thin line (Core)

        # Draw Glow (Cyan) - Thickness 8
        cv2.polylines(img, [pts], False, (255, 255, 0, 100), 8, cv2.LINE_AA)
        # Draw Core (White/Cyan) - Thickness 2
        cv2.polylines(img, [pts], False, (255, 255, 200, 255), 2, cv2.LINE_AA)

        # Wave 2: Gold (Offset)
        curr_freq_2 = -0.015 * freq_mod
        y_vals_2 = (
            np.sin(curr_freq_2 * x_vals * 45 + phase + 1.0)
            * (amp_scale / 2 + h * 0.01)
            * edge_window
        )
        pts_y_2 = (mid_y + y_vals_2).astype(np.int32)
        pts_2 = np.column_stack((x_vals, pts_y_2)).reshape((-1, 1, 2))

        # Draw Gold Glow
        cv2.polylines(img, [pts_2], False, (50, 180, 255, 100), 4, cv2.LINE_AA)
        # Draw Gold Core
        cv2.polylines(img, [pts_2], False, (100, 220, 255, 255), 1, cv2.LINE_AA)

        # --- FAST PARTICLES ---
        # Draw simple circles using OpenCV
        if vol > 0.1 and random.random() < 0.5:
            # Find an empty slot
            empty_slots = np.where(particles[:, 4] <= 0)[0]
            if len(empty_slots) > 0:
                i = empty_slots[0]
                particles[i] = [
                    random.randint(int(w * 0.2), int(w * 0.8)),  # x
                    mid_y + random.randint(-50, 50),  # y
                    (random.random() - 0.5) * 5,  # vx
                    -random.random() * 5 - (vol * 5),  # vy
                    random.randint(20, 40),  # life
                    40,  # max_life
                    random.randint(0, 1),  # color
                ]

        # Update physics (Vectorized!)
        active = particles[:, 4] > 0
        particles[active, 0] += particles[active, 2]  # x += vx
        particles[active, 1] += particles[active, 3]  # y += vy
        particles[active, 4] -= 1  # life -= 1

        # Draw active particles
        for p in particles[active]:
            color = (255, 255, 0, 255) if p[6] == 0 else (50, 180, 255, 255)
            # OpenCV Circle: img, center, radius, color, thickness (-1 = filled)
            cv2.circle(img, (int(p[0]), int(p[1])), int(2 + vol * 5), color, -1)

        # OpenCV uses BGR, MoviePy expects RGB.
        # However, since we defined colors manually as tuples above...
        # If the output looks blue/orange swapped, flip this.
        # But here is the catch: We created an RGBA buffer.

        return img

    return VideoClip(make_frame, duration=duration)


def apply_glass_effect(base):
    """
    Applies a simulated glass effect to a specific region of an image.

    :param base: Path to the input background image.
    """
    # 1. Load the original image
    width, height = base.size

    # 2. Apply Blur
    # Increase the radius for a deeper "dreamy" look
    blurred = base.filter(ImageFilter.GaussianBlur(radius=2))

    # 3. Add Blue Darkness/Transparency Overlay
    # Create a solid dark blue image
    blue_overlay = Image.new("RGBA", (width, height), (15, 25, 50, 255))
    # Ensure blurred is also RGBA to allow blending
    blurred_rgba = blurred.convert("RGBA")
    # Blend the blurred image with the blue overlay (0.4 means 40% blue)
    tinted = Image.blend(blurred_rgba, blue_overlay, alpha=0.5)

    # 4. Create Vignette (Shadows at the edges)
    # Create a radial gradient mask
    mask = Image.new("L", (width, height), 0)
    draw = ImageDraw.Draw(mask)

    # Define the vignette area (larger than the image to keep the center clear)
    vignette_width = int(width * 1.1)
    vignette_height = int(height * 1.1)

    # Draw a white ellipse in the center of the mask
    left = (width - vignette_width) // 2
    top = (height - vignette_height) // 2
    draw.ellipse((left, top, left + vignette_width, top + vignette_height), fill=255)

    # Heavily blur the mask to create a soft transition
    mask = mask.filter(ImageFilter.GaussianBlur(radius=width // 4))

    # Create a solid black image for the shadows
    shadow = Image.new("RGBA", (width, height), (0, 0, 0, 255))

    # Apply the mask: the center remains clear, the edges get the shadow
    # We invert the mask because we want the edges to be dark
    vignette_final = Image.composite(tinted, shadow, mask).convert("RGB")

    return vignette_final


async def _generate_story_video(image_prompts, story_texts, tool_context: ToolContext, language: str = "English"):
    """
    Generates a video from images and story text using Gemini 2.5 Flash TTS for narration.

    Args:
        image_prompts (list(str)): List of prompts to generate images.
        story_texts (list(list(str))): List of story scenes, each scene is a list contain the scene sentences.
        language (str): Target language of narration.

    Returns:
        tuple: (CompositeVideoClip, List[Dict], str) - The final video object, the transcript, and the temp audio path.
    """
    if len(image_prompts) != len(story_texts):
        raise ValueError(
            "The number of images must match the number of story segments."
        )

    # 1. Merge all story texts into a single string for TTS (TASK-04)
    full_script = " ".join(" ".join(sentences) for sentences in story_texts)
    print(f"[Video Gen] [1/4] Starting TTS generation for full script ({len(full_script)} chars, language={language})...", flush=True)
    audio_data = await generate_tts(full_script, language=language)
    print(f"[Video Gen] [1/4] TTS audio generated successfully ({len(audio_data)} bytes).", flush=True)

    # 2. Save this single WAV to one temp file (TASK-04)
    fd, temp_audio_path = tempfile.mkstemp(suffix=".wav")
    os.close(fd)
    with open(temp_audio_path, "wb") as f:
        f.write(audio_data)

    # 3. Load the single audio clip and calculate durations (TASK-04)
    audio_clip = AudioFileClip(temp_audio_path)
    total_dur = audio_clip.duration
    total_chars = sum(len(" ".join(s)) for s in story_texts)
    print(f"[Video Gen] Total audio duration: {total_dur:.2f}s across {len(story_texts)} scenes.", flush=True)

    if total_chars == 0:
        scene_durations = [total_dur / len(story_texts)] * len(story_texts)
    else:
        scene_durations = [
            (len(" ".join(s)) / total_chars) * total_dur
            for s in story_texts
        ]

    # Convert audio data to numpy samples for waveform generation
    samples = np.frombuffer(audio_data, dtype=np.int16)

    semaphore = asyncio.Semaphore(MAX_CONCURRENT_SEGMENTS)

    async def process_segment(i, img_prompt, text_seg, duration, segment_samples):
        async with semaphore:
            print(f"[Video Gen] [2/4] Starting segment {i + 1}/{len(story_texts)} (duration={duration:.2f}s)...", flush=True)

            sentences = text_seg if isinstance(text_seg, list) else [text_seg]
            w_im, h_im = 1344, 768

            print(f"[Video Gen] [2/4] Calling image generation for segment {i + 1}/{len(story_texts)}: {img_prompt[:60]}...", flush=True)
            image = await generate_image(img_prompt, height=h_im, width=w_im)
            print(f"[Video Gen] [2/4] Image {i + 1}/{len(story_texts)} generated. Applying visual effects...", flush=True)

            # Background: Blur and Faded
            bg_img = apply_glass_effect(image)

            # Sentence-level timing: Calculate duration for each sentence based on characters
            scene_total_chars = sum(len(s) for s in sentences)
            segment_transcript = []
            if scene_total_chars > 0:
                for s in sentences:
                    s_duration = (len(s) / scene_total_chars) * duration
                    segment_transcript.append({"text": s, "duration": s_duration})
            else:
                for s in sentences:
                    segment_transcript.append({"text": s, "duration": duration / len(sentences)})

            # Waveform
            waveform_clip = create_waveform_clip(segment_samples, 24000, duration, (w_im, h_im))
            bg_clip = ImageClip(np.array(bg_img)).with_duration(duration)
            clips_to_compose = [bg_clip, waveform_clip]

            segment = CompositeVideoClip(clips_to_compose)
            print(f"[Video Gen] [2/4] Segment {i + 1}/{len(story_texts)} composited successfully.", flush=True)
            return segment, bg_clip, waveform_clip, segment_transcript

    # Process segments sequentially to minimize RAM usage and prevent OOM
    results = []
    for i, (prompt, text) in enumerate(zip(image_prompts, story_texts)):
        start_time = sum(scene_durations[:i])
        duration = scene_durations[i]
        start_sample = int(start_time * 24000)
        end_sample = int((start_time + duration) * 24000)
        segment_samples = samples[start_sample:end_sample]
        if len(segment_samples) == 0:
            segment_samples = np.zeros(100, dtype=np.int16)

        res = await process_segment(i, prompt, text, duration, segment_samples)
        results.append(res)

    video_clips = [r[0] for r in results]
    bg_clips = [r[1] for r in results]
    waveform_clips = [r[2] for r in results]
    raw_transcripts = [r[3] for r in results]

    # Concatenate all segments into final video
    print(f"[Video Gen] [3/4] Concatenating {len(video_clips)} segments into final video...", flush=True)
    final_video = concatenate_videoclips(video_clips, method="compose")
    # Attach the single audio_clip to the concatenated final_video (TASK-04)
    final_video = final_video.with_audio(audio_clip)

    # Track clips that need to be closed (TASK-03)
    clips_to_close = [audio_clip]
    for clip in video_clips:
        clips_to_close.append(clip)
    for clip in bg_clips:
        clips_to_close.append(clip)
    for clip in waveform_clips:
        clips_to_close.append(clip)
    final_video.clips_to_close = clips_to_close

    # Build Final Transcript with Global Timestamps
    final_transcript = []
    current_time = 0.0

    for segment_t in raw_transcripts:
        for item in segment_t:
            start_t = current_time
            end_t = current_time + item["duration"]
            final_transcript.append(
                {"text": item["text"], "start": start_t, "end": end_t}
            )
            current_time = end_t

    print(f"[Video Gen] [3/4] Composition complete. Final duration: {final_video.duration:.2f}s", flush=True)
    return final_video, final_transcript, temp_audio_path


async def video_tool(
    scenes: List[dict], tool_context: ToolContext
):
    """
    Tool for generating a story video.

    Args:
        scenes: A list of exactly 4 scene objects. Each object must contain:
                - image_prompt (str): Short English prompt for the scene image.
                - text (list[str]): 4-6 sentences of story narration for that scene.
    """
    temp_audio_path = None
    temp_video_path = None
    final_video_clip = None

    try:
        language = tool_context.state.get("language", "English")

        # Unpack scenes into the two parallel lists _generate_story_video expects.
        # This keeps the mismatch impossible — both lists always have the same length.
        image_prompts = [s.get("image_prompt", "") for s in scenes]
        story_texts   = [s.get("text", []) for s in scenes]

        # Ensure text entries are always list[str], never a bare string
        story_texts = [
            t if isinstance(t, list) else [t]
            for t in story_texts
        ]

        if len(image_prompts) != 4:
            print(f"[Video Gen] WARNING: received {len(image_prompts)} scenes instead of 4. Proceeding anyway.", flush=True)

        print(f"[Video Gen] >>> video_tool INVOKED! Generating video for {len(image_prompts)} scenes (language={language})...", flush=True)
        final_video_clip, transcript, temp_audio_path = await _generate_story_video(
            image_prompts, story_texts, language=language, tool_context=tool_context
        )
        video_name = f"video_{uuid.uuid4().hex[:8]}.mp4"

        # Write video to a temporary file first (moviepy requires a file path)
        with tempfile.NamedTemporaryFile(suffix=".mp4", delete=False) as temp_video:
            temp_video_path = temp_video.name

        # Write the video file off-thread (TASK-02)
        print(f"[Video Gen] [4/4] Encoding video off-thread with MoviePy (fps=24, libx264)...", flush=True)
        await asyncio.to_thread(
            final_video_clip.write_videofile,
            temp_video_path,
            codec="libx264",
            audio_codec="aac",
            fps=24,
            logger=None,
        )
        file_size = os.path.getsize(temp_video_path) if os.path.exists(temp_video_path) else 0
        print(f"[Video Gen] [4/4] Video encoded successfully ({file_size} bytes).", flush=True)

        # Read the video bytes from the temporary file
        with open(temp_video_path, "rb") as video_file:
            video_bytes = video_file.read()

        # Save to artifacts with raw bytes
        print(f"[Video Gen] Saving artifact: {video_name} ({len(video_bytes)} bytes)...", flush=True)
        version = await tool_context.save_artifact(
            video_name,
            types.Part.from_bytes(
                data=video_bytes,
                mime_type="video/mp4",
            ),
        )
        print(f"[Video Gen] Artifact {video_name} saved successfully (version: {version})!", flush=True)

        # Build public direct GCS URL if ADK_ARTIFACT_STORE is set to GCS (Option 3)
        artifact_uri = os.environ.get("ADK_ARTIFACT_STORE", "")
        video_url = None
        if artifact_uri.startswith("gs://"):
            bucket_name = artifact_uri[5:].rstrip("/")
            user_id = (
                getattr(tool_context, "user_id", None)
                or tool_context.state.get("user_id", "unknown")
            )
            session_id = (
                getattr(getattr(tool_context, "session", None), "id", None)
                or tool_context.state.get("session_id", "unknown")
            )
            # GcsArtifactService convention: {app_name}/{user_id}/{session_id}/{artifact_name}/{version}
            blob_path = f"video_agent/{user_id}/{session_id}/{video_name}/{version}"
            video_url = f"https://storage.googleapis.com/{bucket_name}/{blob_path}"
            print(f"[Video Gen] Public GCS video URL generated: {video_url}", flush=True)

        return {
            "status": "success",
            "video_url": video_url,
            "video_path": video_name,
            "transcript": transcript,
        }

    except Exception as e:
        print(f"[Video Gen] ERROR in video_tool: {e}", flush=True)
        logger.exception("Error in video_tool")
        return {"status": "failed", "error": str(e)}

    finally:
        # Resource cleanup (TASK-03)
        if final_video_clip:
            try:
                final_video_clip.close()
            except Exception:
                pass
            if hasattr(final_video_clip, "clips_to_close"):
                for clip in final_video_clip.clips_to_close:
                    try:
                        clip.close()
                    except Exception:
                        pass
        if temp_video_path and os.path.exists(temp_video_path):
            try:
                os.remove(temp_video_path)
            except Exception:
                pass
        if temp_audio_path and os.path.exists(temp_audio_path):
            try:
                os.remove(temp_audio_path)
            except Exception:
                pass


class MockPythonInterpreterTool(BaseTool):
    """
    Fallback tool that intercepts implicit/hallucinated 'google:python_interpreter' calls
    from Gemini models and guides the model back to calling video_tool directly.
    """
    def __init__(self):
        super().__init__(
            name="google:python_interpreter",
            description="Fallback handler for python interpreter invocations.",
        )

    async def process_llm_request(self, *, tool_context: ToolContext, llm_request: LlmRequest) -> None:
        llm_request.tools_dict[self.name] = self

    async def run_async(self, *, args: dict, tool_context: ToolContext):
        return {
            "error": "Code execution is disabled. Do not execute Python code; call video_tool directly."
        }


def handle_tool_error(tool: BaseTool, args: dict, tool_context: ToolContext, error: Exception):
    """
    Catches any tool execution errors or missing tool references and prevents the agent loop from crashing.
    """
    logger.warning(f"Intercepted tool error for '{getattr(tool, 'name', 'unknown')}': {error}")
    if "python_interpreter" in getattr(tool, "name", ""):
        return {
            "error": "Python interpreter is unavailable. Do not execute code; call video_tool directly."
        }
    return {"error": str(error)}


########## Agents ##########

scenario_writer = LlmAgent(
    name="ScenarioWriter",
    model="gemini-2.5-flash-lite",
    description="Generates a summary and scenarios for a story subject",
    instruction=scenario_instruction,
    output_key="scenario",
    generate_content_config=types.GenerateContentConfig(
        temperature=1.5,
    ),
    on_tool_error_callback=handle_tool_error,
)

video_story_agent = LlmAgent(
    name="VideoStoryAgent",
    model="gemini-2.5-flash",
    description="Generates cinematic, emotional, and dramatic stories immediately",
    instruction=video_story_instruction,
    output_key="video_story",
    tools=[video_tool, MockPythonInterpreterTool()],
    on_tool_error_callback=handle_tool_error,
)

story_analyzer_agent = LlmAgent(
    model="gemini-2.5-flash-lite",
    name="StoryAnalyzer",
    description="Analyzes stories and generates comprehension questions to test understanding",
    instruction=questions_instruction,
    output_key="analysis_result",
    on_tool_error_callback=handle_tool_error,
)

