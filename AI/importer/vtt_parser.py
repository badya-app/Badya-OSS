"""
VTT (WebVTT) caption file parsing.

Extracted from the original ImportManager._parse_vtt method.
"""
import re
from typing import List, Dict


def parse_vtt(vtt_content: str) -> List[Dict]:
    """
    Parse a WebVTT subtitle string into a list of caption dicts.

    Each dict has keys: start (float), duration (float), text (str).
    Consecutive captions with the same text and overlapping timing
    are merged into a single caption.
    """
    lines = vtt_content.splitlines()
    captions = []
    time_pattern = re.compile(
        r"(\d{2}:)?(\d{2}):(\d{2})\.(\d{3})\s-->\s(\d{2}:)?(\d{2}):(\d{2})\.(\d{3})"
    )
    current_caption = None
    last_text = None
    last_start = None
    last_end = None

    for line in lines:
        line = line.strip()
        if not line or line == "WEBVTT" or line.isdigit():
            continue

        match = time_pattern.search(line)
        if match:
            groups = match.groups()

            def to_seconds(h, m, s, ms):
                h = int(h[:-1]) if h else 0
                m = int(m)
                s = int(s)
                ms = int(ms)
                return h * 3600 + m * 60 + s + ms / 1000.0

            start = to_seconds(groups[0], groups[1], groups[2], groups[3])
            end = to_seconds(groups[4], groups[5], groups[6], groups[7])
            current_caption = {"start": start, "duration": end - start, "text": ""}
            captions.append(current_caption)

        elif current_caption:
            clean_line = re.sub(r"<[^>]+>", "", line).strip()
            if not clean_line:
                continue
            if current_caption["text"]:
                current_caption["text"] += " " + clean_line
            else:
                current_caption["text"] = clean_line

    # Deduplicate consecutive captions with same text
    deduped = []
    for cap in captions:
        text = re.sub(r"\s+", " ", cap.get("text", "")).strip()
        if not text:
            continue
        start = cap.get("start", 0)
        end = cap.get("start", 0) + cap.get("duration", 0)
        if last_text is not None:
            same_text = text.lower() == last_text.lower()
            overlaps = start <= (last_end or 0) + 0.5
            if same_text and overlaps:
                last_end = max(last_end, end)
                last_start = last_start if last_start is not None else start
                deduped[-1]["duration"] = last_end - last_start
                continue
        deduped.append({"start": start, "duration": end - start, "text": text})
        last_text = text
        last_start = start
        last_end = end
    return deduped
