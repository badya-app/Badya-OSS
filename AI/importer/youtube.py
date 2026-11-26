"""
YouTube transcript and metadata extraction.

Extracted from the original ImportManager YouTube-related methods into
standalone functions.
"""

import os
import re
import json
import logging
from typing import Optional, List, Dict, Any

from import_models import ImportItem
from .exceptions import ExtractionFailedError, VideoIdExtractionError

logger = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# Cookie / proxy helpers
# ---------------------------------------------------------------------------


def get_youtube_cookie_file() -> Optional[str]:
    """Locate the YouTube cookies file in Cloud Run or local dev paths."""
    env_file = os.environ.get("YT_COOKIE_FILE")
    if env_file and os.path.exists(env_file):
        return env_file

    paths_to_check = [
        "/secrets/youtube-cookies/cookies.txt",
        "/secrets/youtube-cookies/youtube-cookies",
        "/secrets/youtube-cookies/latest",
        os.path.abspath(
            os.path.join(os.path.dirname(__file__), "../../../yt_cookies_slim.txt")
        ),
        os.path.abspath(
            os.path.join(os.path.dirname(__file__), "../../yt_cookies_slim.txt")
        ),
        os.path.abspath(
            os.path.join(os.path.dirname(__file__), "../yt_cookies_slim.txt")
        ),
        "yt_cookies_slim.txt",
    ]
    for path in paths_to_check:
        if os.path.exists(path):
            return path
    return None


def fetch_transcript_list(video_id: str):
    """Fetch the transcript list using youtube_transcript_api."""
    from youtube_transcript_api import YouTubeTranscriptApi

    try:
        from youtube_transcript_api.proxies import GenericProxyConfig

        has_proxies_module = True
    except ImportError:
        has_proxies_module = False

    yt_proxy = os.environ.get("YT_PROXY")
    cookie_file = get_youtube_cookie_file()

    session = None
    proxy_config = None
    if yt_proxy and has_proxies_module:
        try:
            proxy_config = GenericProxyConfig(
                http_url=yt_proxy, https_url=yt_proxy
            )
        except Exception as pe:
            logger.warning(f"Could not build GenericProxyConfig: {pe}")

    if not hasattr(YouTubeTranscriptApi, "list_transcripts"):
        import requests
        from http.cookiejar import MozillaCookieJar
        from requests.adapters import HTTPAdapter
        from urllib3.util.retry import Retry

        session = requests.Session()
        if cookie_file:
            try:
                cj = MozillaCookieJar(cookie_file)
                cj.load(ignore_discard=True, ignore_expires=True)
                session.cookies = cj
            except Exception as e:
                logger.warning(f"Could not load cookies into requests session: {e}")

        if yt_proxy:
            session.proxies = {"http": yt_proxy, "https": yt_proxy}
        else:
            retry_strategy = Retry(
                total=3,
                backoff_factor=2,
                status_forcelist=[429, 502, 503, 504],
                allowed_methods=["GET", "POST"],
            )
            adapter = HTTPAdapter(max_retries=retry_strategy)
            session.mount("http://", adapter)
            session.mount("https://", adapter)

        api_kwargs = {"http_client": session}
        if proxy_config:
            api_kwargs["proxy_config"] = proxy_config
        return YouTubeTranscriptApi(**api_kwargs).list(video_id)

    kwargs = {}
    if cookie_file:
        kwargs["cookies"] = cookie_file
    if yt_proxy:
        kwargs["proxies"] = {"http": yt_proxy, "https": yt_proxy}
    return YouTubeTranscriptApi.list_transcripts(video_id, **kwargs)


# ---------------------------------------------------------------------------
# Language helpers
# ---------------------------------------------------------------------------


def clean_lang(lang_code: Optional[str]) -> Optional[str]:
    """Normalize a language code, filtering out known glitches."""
    if not lang_code:
        return None
    code = lang_code.lower().split("-")[0]
    return None if code == "ab" else code


def detect_audio_language(
    all_trans, video_lang: Optional[str], yt_auto_caps: List[str]
) -> str:
    """Determine the video's audio language from transcript/metadata signals."""
    cl = clean_lang
    manual_langs = [t.language_code for t in all_trans if not t.is_generated]
    gen_langs = [t.language_code for t in all_trans if t.is_generated]

    non_en_manuals = [l for l in manual_langs if cl(l) != "en" and cl(l)]
    non_en_gens = [l for l in gen_langs if cl(l) != "en" and cl(l)]
    meta_lang = cl(video_lang)
    yt_signals = [cl(l) for l in (yt_auto_caps or []) if cl(l)]

    audio_lang = "en"
    if non_en_manuals:
        audio_lang = cl(non_en_manuals[0])
    elif non_en_gens:
        audio_lang = cl(non_en_gens[0])
    elif meta_lang and meta_lang != "en":
        audio_lang = meta_lang
    elif yt_signals and any(l != "en" for l in yt_signals):
        audio_lang = next(l for l in yt_signals if l != "en")
    elif manual_langs:
        audio_lang = "en"

    logger.info(
        f"Discovery: AudioLang={audio_lang}, Manuals={manual_langs}, "
        f"Gens={gen_langs}, Meta={meta_lang}"
    )
    return audio_lang


# ---------------------------------------------------------------------------
# Transcript selection
# ---------------------------------------------------------------------------


def select_best_transcript(
    all_trans, transcript_list_obj, audio_lang: str, target_lang: Optional[str] = None
):
    """Select the best transcript track based on detected audio language."""
    cl = clean_lang
    best_t = None
    target_lang = cl(target_lang) if target_lang else None
    audio_lang = cl(audio_lang) if audio_lang else None

    if target_lang:
        best_t = next(
            (
                t
                for t in all_trans
                if cl(t.language_code) == target_lang and not t.is_generated
            ),
            None,
        )
    if target_lang and not best_t:
        best_t = next(
            (t for t in all_trans if cl(t.language_code) == target_lang),
            None,
        )
    if not best_t and audio_lang:
        best_t = next(
            (
                t
                for t in all_trans
                if cl(t.language_code) == audio_lang and not t.is_generated
            ),
            None,
        )
    if not best_t and audio_lang and audio_lang != "en":
        non_en = [
            t for t in all_trans if not t.is_generated and cl(t.language_code) != "en"
        ]
        if non_en:
            best_t = non_en[0]
    if not best_t and audio_lang:
        best_t = next(
            (t for t in all_trans if cl(t.language_code) == audio_lang),
            None,
        )
    if not best_t:
        try:
            best_t = transcript_list_obj.find_transcript([])
        except Exception as e:
            logger.info(f"find_transcript fallback failed: {e}")
            if all_trans:
                best_t = all_trans[0]
    return best_t


# ---------------------------------------------------------------------------
# Transcript fetching & normalization
# ---------------------------------------------------------------------------


def fetch_transcript_entries(best_t) -> List[Dict]:
    """Fetch and normalize transcript entries from a transcript object."""
    logger.info(
        f"Final Selection: {best_t.language_code} (Manual: {not best_t.is_generated})"
    )
    tr_raw = best_t.fetch()

    def _normalize_text(value: str) -> str:
        return re.sub(r"\s+", " ", value or "").strip()

    transcript_list = []
    last_item = None
    for x in tr_raw:
        try:
            start = x["start"]
            duration_entry = x["duration"]
            text = x["text"]
        except (TypeError, KeyError):
            start = getattr(x, "start", 0)
            duration_entry = getattr(x, "duration", 0)
            text = getattr(x, "text", "")

        text = _normalize_text(text)
        if not text:
            continue

        item = {"start": start, "duration": duration_entry, "text": text}

        if last_item:
            last_text = _normalize_text(last_item["text"]).lower()
            item_text = text.lower()
            last_start = last_item["start"]
            last_end = last_start + last_item["duration"]
            item_end = start + duration_entry

            is_duplicate = (
                item_text == last_text
                or item_text in last_text
                or last_text in item_text
            )
            is_overlap = start <= last_end + 0.5

            if is_duplicate and is_overlap:
                last_item["duration"] = max(last_end, item_end) - last_start
                continue

        transcript_list.append(item)
        last_item = item

    return transcript_list


def score_transcript_quality(
    transcript_list: List[Dict], is_auto: Optional[bool]
) -> str:
    """Classify transcript quality: 'manual' | 'auto' | 'none'."""
    if not transcript_list:
        return "none"
    if is_auto is False:
        return "manual"
    return "auto"


# ---------------------------------------------------------------------------
# Video ID & metadata
# ---------------------------------------------------------------------------


def extract_video_id(url: str) -> str:
    """Extract the video ID from a YouTube URL."""
    video_id = None
    if "youtube.com/watch?v=" in url:
        video_id = url.split("watch?v=")[1].split("&")[0]
    elif "youtu.be/" in url:
        video_id = url.split("youtu.be/")[1].split("?")[0]

    if not video_id:
        raise VideoIdExtractionError(f"Could not extract video ID from URL: {url}")
    return video_id


def parse_chapters_from_description(description: str, duration: int) -> List[Dict]:
    if not description:
        return []
    pattern = re.compile(r'(?:(\d{1,2}):)?(\d{1,2}):(\d{2})')
    lines = description.split('\n')
    parsed_chapters = []
    for line in lines:
        match = pattern.search(line)
        if match:
            # Found a timestamp
            hours = int(match.group(1)) if match.group(1) else 0
            minutes = int(match.group(2))
            seconds = int(match.group(3))
            start_time = hours * 3600 + minutes * 60 + seconds
            
            # Clean title
            title = line.replace(match.group(0), '').strip(' -:|[]()')
            if not title:
                title = f"Chapter at {match.group(0)}"
                
            parsed_chapters.append({
                "start_time": start_time,
                "title": title
            })
            
    if not parsed_chapters:
        return []
        
    # Sort by start time
    parsed_chapters.sort(key=lambda x: x["start_time"])
    
    # Filter/validate start times and calculate end_times
    valid_chapters = []
    for i, chap in enumerate(parsed_chapters):
        start = chap["start_time"]
        if start >= duration:
            continue
        # Calculate end_time
        end = duration
        if i + 1 < len(parsed_chapters):
            next_start = parsed_chapters[i+1]["start_time"]
            if next_start > start:
                end = next_start
        valid_chapters.append({
            "start_time": start,
            "end_time": end,
            "title": chap["title"]
        })
    return valid_chapters


def extract_video_metadata(info: Dict, item: ImportItem) -> int:
    """Populate item metadata from yt-dlp info dict. Returns duration in sec."""
    if item.title == "Untitled Import" or not item.title:
        item.title = info.get("title", "Unknown Video")
    duration = info.get("duration", 0)
    item.metadata["duration"] = duration
    video_id = info.get("id")
    item.metadata["thumbnail"] = info.get("thumbnail") or (
        f"https://img.youtube.com/vi/{video_id}/hqdefault.jpg" if video_id else None
    )
    item.metadata["uploader"] = info.get("uploader")
    
    description = info.get("description", "")
    item.metadata["description"] = description
    
    # Extract chapters
    chapters = info.get("chapters")
    if chapters:
        item.metadata["chapters"] = [
            {
                "start_time": float(c.get("start_time", 0.0)),
                "end_time": float(c.get("end_time", duration)),
                "title": c.get("title", f"Chapter {idx+1}"),
            }
            for idx, c in enumerate(chapters)
        ]
    else:
        # Try to parse from description
        parsed = parse_chapters_from_description(description, duration)
        if parsed:
            item.metadata["chapters"] = parsed
            
    return duration


def select_stream_url(formats: List[Dict], info: Dict) -> Optional[str]:
    """Select the best stream URL from available formats."""
    stream_url = None
    for f in formats:
        if (
            f.get("url")
            and f.get("vcodec") != "none"
            and f.get("acodec") != "none"
            and f.get("ext") == "mp4"
        ):
            stream_url = f.get("url")
    if not stream_url:
        stream_url = info.get("manifest_url")
    if not stream_url:
        stream_url = info.get("url")
    if not stream_url:
        for f in formats:
            if f.get("url"):
                stream_url = f.get("url")
                break
    return stream_url


def fetch_video_chapters_lightweight(video_id: str) -> List[Dict]:
    """
    Lightweight chapter extraction from a YouTube video.

    Uses yt-dlp in metadata-only mode (skip_download=True) to get
    chapter markers from the video. This is fast because no video
    data is downloaded — only the info dict is extracted.
    Returns empty list if no chapters are available or on failure.
    """
    import yt_dlp

    ydl_opts = {
        "quiet": True,
        "skip_download": True,
        "js_runtimes": {"node": {}},
        "extractor_args": {
            "youtube": {"player_client": ["android", "web", "web_embedded"]}
        },
        "ignoreerrors": True,
        "remote_components": ["ejs:github"],
    }
    yt_proxy = os.environ.get("YT_PROXY")
    if yt_proxy:
        ydl_opts["proxy"] = yt_proxy
    cookie_file = get_youtube_cookie_file()
    if cookie_file:
        ydl_opts["cookiefile"] = cookie_file

    try:
        url = f"https://www.youtube.com/watch?v={video_id}"
        with yt_dlp.YoutubeDL(ydl_opts) as ydl:
            info = ydl.extract_info(url, download=False)
            if not info:
                return []
            duration = info.get("duration", 0)
            chapters = info.get("chapters")
            if chapters:
                return [
                    {
                        "start_time": float(c.get("start_time", 0.0)),
                        "end_time": float(c.get("end_time", duration)),
                        "title": c.get("title", f"Chapter {idx+1}"),
                    }
                    for idx, c in enumerate(chapters)
                ]
            # Fall back to description parsing
            description = info.get("description", "")
            parsed = parse_chapters_from_description(description, duration)
            if parsed:
                return parsed
    except Exception as e:
        logger.info(f"[ChapterExtraction] yt-dlp chapter fetch failed: {e}")

    return []


def fetch_video_metadata_lightweight(item: ImportItem, video_id: str):
    """Lightweight metadata fetch via YouTube oEmbed API (~100ms)."""
    try:
        import requests

        url = (
            f"https://www.youtube.com/oembed"
            f"?url=https://www.youtube.com/watch?v={video_id}&format=json"
        )
        proxies = None
        yt_proxy = os.environ.get("YT_PROXY")
        if yt_proxy:
            proxies = {"http": yt_proxy, "https": yt_proxy}

        resp = requests.get(url, proxies=proxies, timeout=5)
        if resp.status_code == 200:
            data = resp.json()
            if item.title == "Untitled Import" or not item.title:
                item.title = data.get("title", "Unknown Video")
            item.metadata["thumbnail"] = (
                data.get("thumbnail_url")
                or f"https://img.youtube.com/vi/{video_id}/hqdefault.jpg"
            )
            item.metadata["uploader"] = data.get("author_name")
            logger.info(f"[LightweightMetadata] oEmbed success: {item.title}")
        else:
            logger.warning(
                f"[LightweightMetadata] oEmbed returned status {resp.status_code}"
            )
    except Exception as e:
        logger.info(f"[LightweightMetadata] oEmbed fetch failed: {e}")


# ---------------------------------------------------------------------------
# Transcript fetching strategies
# ---------------------------------------------------------------------------


def fetch_transcript_via_api_lightweight(
    video_id: str,
    target_lang: Optional[str] = None,
) -> tuple:
    """Fast transcript fetch using only youtube_transcript_api (no yt-dlp)."""
    try:
        from youtube_transcript_api import YouTubeTranscriptApi
    except ImportError:
        return [], None, None, None, []

    try:
        transcript_list_obj = fetch_transcript_list(video_id)
        all_trans = list(transcript_list_obj)
        if not all_trans:
            return [], None, None, None, []

        available = [
            {
                "code": clean_lang(t.language_code) or t.language_code,
                "name": t.language,
                "auto": t.is_generated,
            }
            for t in all_trans
        ]

        audio_lang = detect_audio_language(all_trans, None, [])
        best_t = select_best_transcript(
            all_trans,
            transcript_list_obj,
            audio_lang,
            target_lang=target_lang,
        )
        if best_t:
            entries = fetch_transcript_entries(best_t)
            if entries:
                return (
                    entries,
                    audio_lang,
                    clean_lang(best_t.language_code) or best_t.language_code,
                    best_t.is_generated,
                    available,
                )
    except Exception as e:
        logger.info(f"Lightweight transcript API failed: {e}")

    return [], None, None, None, []


def fetch_transcript_via_api(
    video_id: str,
    info: Dict,
    target_lang: Optional[str] = None,
) -> tuple[List[Dict], Optional[str], Optional[str], Optional[bool], List[Dict]]:
    """Fetch transcript using youtube_transcript_api with full yt-dlp info."""
    try:
        from youtube_transcript_api import YouTubeTranscriptApi
    except ImportError:
        return [], None, None, None, []

    yt_auto_caps = list(info.get("automatic_captions", {}).keys())
    video_lang = info.get("language")

    try:
        transcript_list_obj = fetch_transcript_list(video_id)
        if not transcript_list_obj:
            return [], None, None, None, []

        all_trans = []
        try:
            all_trans = list(transcript_list_obj)
        except Exception as e:
            logger.info(f"Could not list transcripts: {e}")
            if hasattr(transcript_list_obj, "_manually_created_transcripts"):
                all_trans.extend(
                    transcript_list_obj._manually_created_transcripts.values()
                )
                all_trans.extend(transcript_list_obj._generated_transcripts.values())

        if not all_trans:
            return [], None, None, None, []

        audio_lang = detect_audio_language(all_trans, video_lang, yt_auto_caps)
        available = [
            {
                "code": clean_lang(t.language_code) or t.language_code,
                "name": t.language,
                "auto": t.is_generated,
            }
            for t in all_trans
        ]
        best_t = select_best_transcript(
            all_trans,
            transcript_list_obj,
            audio_lang,
            target_lang=target_lang,
        )

        if best_t:
            transcript_list = fetch_transcript_entries(best_t)
            if transcript_list:
                return (
                    transcript_list,
                    audio_lang,
                    clean_lang(best_t.language_code) or best_t.language_code,
                    best_t.is_generated,
                    available,
                )

        # Fallback
        candidates = (
            [t for t in all_trans if t is not None and t != best_t]
            if best_t is not None
            else list(all_trans)
        )
        candidates.sort(key=lambda t: t.is_generated)
        for candidate in candidates:
            transcript_list = fetch_transcript_entries(candidate)
            if transcript_list:
                return (
                    transcript_list,
                    audio_lang,
                    clean_lang(candidate.language_code) or candidate.language_code,
                    candidate.is_generated,
                    available,
                )

    except Exception as e:
        logger.error(f"Transcript API fetch failed: {e}", exc_info=True)

    return [], None, None, None, available if "available" in locals() else []


def fetch_transcript_via_vtt(
    info: Dict,
    audio_lang: Optional[str],
    target_lang: Optional[str] = None,
) -> tuple[List[Dict], Optional[str], Optional[bool], List[Dict]]:
    """Fallback: fetch transcript via yt-dlp VTT subtitles."""
    try:
        import urllib.request

        subs = info.get("subtitles") or {}
        auto_subs = info.get("automatic_captions") or {}
        selected_sub = None
        is_auto_caption = False
        video_lang = info.get("language")
        clean_target_lang = clean_lang(target_lang)
        target_lang = (
            clean_target_lang
            if clean_target_lang
            else (audio_lang if audio_lang else video_lang)
        )

        def _select_sub_for_lang(sub_map, lang_code):
            if not lang_code:
                return None
            if lang_code in sub_map:
                return sub_map[lang_code]
            for key, value in sub_map.items():
                if key.startswith(f"{lang_code}-"):
                    return value
            return None

        available = []
        for key, value in subs.items():
            available.append(
                {"code": clean_lang(key) or key, "name": key, "auto": False}
            )
        for key, value in auto_subs.items():
            available.append(
                {"code": clean_lang(key) or key, "name": key, "auto": True}
            )

        if target_lang:
            selected_sub = _select_sub_for_lang(subs, target_lang)
            if not selected_sub:
                selected_sub = _select_sub_for_lang(auto_subs, target_lang)
                if selected_sub:
                    is_auto_caption = True

        if not selected_sub and target_lang and target_lang != "en":
            non_en = {k: v for k, v in subs.items() if not k.startswith("en")}
            if non_en:
                selected_sub = list(non_en.values())[0]

        if not selected_sub:
            if subs:
                selected_sub = list(subs.values())[0]
            elif auto_subs:
                selected_sub = list(auto_subs.values())[0]
                is_auto_caption = True

        if not selected_sub:
            return [], None, None, []

        vtt_url = None
        for fmt in selected_sub:
            if fmt.get("ext") == "vtt":
                vtt_url = fmt.get("url")
                break
        if not vtt_url:
            vtt_url = selected_sub[0].get("url")

        if vtt_url:
            from .vtt_parser import parse_vtt

            logger.info(f"Fetching VTT from: {vtt_url}")
            with urllib.request.urlopen(vtt_url, timeout=10) as response:
                vtt_content = response.read().decode("utf-8")
                transcript = parse_vtt(vtt_content)
                return (transcript, target_lang, is_auto_caption, available)

    except Exception as e:
        logger.info(f"Could not fetch transcript via VTT: {e}")

    return [], None, None, []


# ---------------------------------------------------------------------------
# Main YouTube processing orchestrator
# ---------------------------------------------------------------------------


def process_youtube(item: ImportItem, target_language: Optional[str] = None):
    """
    Process a YouTube video import — extraction only, no segmentation.
    Segmentation is handled client-side by Flutter's ContentSegmenter.
    """
    import yt_dlp

    if not item.source_url:
        raise ExtractionFailedError("No source URL provided for YouTube import")

    video_id = extract_video_id(item.source_url)
    clean_target = clean_lang(target_language) if target_language else None

    # ── Strategy 1: Transcript API only (FAST PATH) ──────────────────
    try:
        transcript_list, audio_lang, selected_lang, selected_is_auto, available = (
            fetch_transcript_via_api_lightweight(video_id, clean_target)
        )
        if transcript_list:
            fetch_video_metadata_lightweight(item, video_id)

            # Lightweight chapter extraction (uses yt-dlp metadata-only,
            # no video download, ~200-500ms extra).
            chapters = fetch_video_chapters_lightweight(video_id)
            if chapters:
                item.metadata["chapters"] = chapters

            last = transcript_list[-1]
            duration = int(last.get("start", 0) + last.get("duration", 0))
            item.metadata["duration"] = duration
            item.metadata["language"] = audio_lang
            item.metadata["transcript_language"] = selected_lang
            item.metadata["transcript_is_auto"] = selected_is_auto
            item.metadata["transcript_quality"] = score_transcript_quality(
                transcript_list, selected_is_auto
            )
            item.metadata["transcript_matches_target"] = (
                clean_target is not None
                and selected_lang is not None
                and clean_lang(selected_lang) == clean_target
            )
            if available:
                item.metadata["available_transcripts"] = available
            if not item.metadata.get("thumbnail"):
                item.metadata["thumbnail"] = (
                    f"https://img.youtube.com/vi/{video_id}/hqdefault.jpg"
                )
            item.metadata["transcript_json"] = json.dumps(transcript_list)
            item.metadata["word_count"] = sum(
                len(e.get("text", "").split()) for e in transcript_list
            )
            logger.info(
                f"[FastPath] Transcript API success: {video_id}, "
                f"lang={selected_lang}, ~{duration}s"
            )
            return
    except Exception as e:
        logger.info(f"[FastPath] Transcript API failed: {e}")

    # ── Strategy 2: yt-dlp ───────────────────────────────────────────
    subtitle_langs = ["en"]
    if clean_target and clean_target != "en":
        subtitle_langs = [clean_target, f"{clean_target}-*", "en"]

    ydl_opts = {
        "quiet": True,
        "skip_download": True,
        "js_runtimes": {"node": {}},
        "extractor_args": {
            "youtube": {"player_client": ["android", "web", "web_embedded"]}
        },
        "ignoreerrors": True,
        "writesubtitles": True,
        "writeautomaticsub": True,
        "subtitleslangs": subtitle_langs,
        "remote_components": ["ejs:github"],
    }
    yt_proxy = os.environ.get("YT_PROXY")
    if yt_proxy:
        ydl_opts["proxy"] = yt_proxy
    cookie_file = get_youtube_cookie_file()
    if cookie_file:
        ydl_opts["cookiefile"] = cookie_file

    yt_dlp_info = None
    yt_dlp_blocked = False

    try:
        with yt_dlp.YoutubeDL(ydl_opts) as ydl:
            yt_dlp_info = ydl.extract_info(item.source_url, download=False)
    except Exception as e:
        logger.warning(f"yt-dlp extraction exception: {e}")
        # If cookies failed (e.g. invalid/rotated cookies), try once without cookiefile
        if cookie_file and "cookie" in str(e).lower():
            logger.info(f"Retrying yt-dlp for {video_id} without cookies...")
            ydl_opts_no_cookie = dict(ydl_opts)
            ydl_opts_no_cookie.pop("cookiefile", None)
            try:
                with yt_dlp.YoutubeDL(ydl_opts_no_cookie) as ydl_retry:
                    yt_dlp_info = ydl_retry.extract_info(item.source_url, download=False)
            except Exception as retry_err:
                logger.warning(f"yt-dlp retry without cookies also failed: {retry_err}")
                yt_dlp_blocked = True
        else:
            yt_dlp_blocked = True

    if yt_dlp_info is None:
        if cookie_file and not yt_dlp_blocked:
            logger.info(f"yt-dlp returned None with cookies; retrying {video_id} without cookies...")
            ydl_opts_no_cookie = dict(ydl_opts)
            ydl_opts_no_cookie.pop("cookiefile", None)
            try:
                with yt_dlp.YoutubeDL(ydl_opts_no_cookie) as ydl_retry:
                    yt_dlp_info = ydl_retry.extract_info(item.source_url, download=False)
            except Exception as retry_err:
                logger.warning(f"yt-dlp retry without cookies also failed: {retry_err}")

        if yt_dlp_info is None:
            logger.warning(f"yt-dlp returned None for {video_id} — treating as IP-blocked.")
            yt_dlp_blocked = True

    if yt_dlp_blocked:
        logger.info(
            f"[CloudRunFallback] yt-dlp blocked — retrying transcript-api "
            f"via proxy for {video_id}"
        )
        try:
            transcript_list, audio_lang, selected_lang, selected_is_auto, available = (
                fetch_transcript_via_api_lightweight(video_id, clean_target)
            )
            if transcript_list:
                logger.info(
                    f"[CloudRunFallback] transcript-api succeeded via proxy "
                    f"for {video_id}"
                )
                fetch_video_metadata_lightweight(item, video_id)
                item.metadata["language"] = audio_lang
                item.metadata["transcript_language"] = selected_lang
                item.metadata["transcript_is_auto"] = selected_is_auto
                item.metadata["transcript_quality"] = score_transcript_quality(
                    transcript_list, selected_is_auto
                )
                item.metadata["transcript_matches_target"] = (
                    clean_target is not None
                    and selected_lang is not None
                    and clean_lang(selected_lang) == clean_target
                )
                if available:
                    item.metadata["available_transcripts"] = available
                if not item.metadata.get("thumbnail"):
                    item.metadata["thumbnail"] = (
                        f"https://img.youtube.com/vi/{video_id}/hqdefault.jpg"
                    )
                item.metadata["transcript_json"] = json.dumps(transcript_list)
                item.metadata["word_count"] = sum(
                    len(e.get("text", "").split()) for e in transcript_list
                )
                last = transcript_list[-1]
                duration = int(last.get("start", 0) + last.get("duration", 0))
                item.metadata["duration"] = duration
                return
        except Exception as transcript_err:
            logger.warning(
                f"[CloudRunFallback] transcript-api retry also failed: {transcript_err}"
            )

        logger.warning(
            f"[CloudRunFallback] All strategies failed for {video_id}. "
            f"Saving degraded import (no transcript)."
        )
        fetch_video_metadata_lightweight(item, video_id)
        item.metadata["needs_metadata"] = True
        item.metadata["youtube_blocked"] = True
        item.metadata["error"] = (
            "YouTube is blocking transcript extraction from this server's IP. "
            "The video was imported without a transcript. You can retry later."
        )
        if not item.metadata.get("thumbnail"):
            item.metadata["thumbnail"] = (
                f"https://img.youtube.com/vi/{video_id}/hqdefault.jpg"
            )
        return

    if not yt_dlp_info:
        raise ExtractionFailedError(
            "Could not extract video info. YouTube might be blocking the request "
            "or the video is unavailable."
        )

    formats = yt_dlp_info.get("formats", [])
    extract_video_metadata(yt_dlp_info, item)
    stream_url = select_stream_url(formats, yt_dlp_info)
    item.metadata["stream_url"] = stream_url
    logger.info(f"[yt-dlp] Stream URL for {video_id}: {str(stream_url)[:100]}...")

    transcript_list, audio_lang, selected_lang, selected_is_auto, available = (
        fetch_transcript_via_api(video_id, yt_dlp_info, target_lang=target_language)
    )
    if transcript_list:
        item.metadata["language"] = audio_lang
        item.metadata["transcript_language"] = selected_lang
        item.metadata["transcript_is_auto"] = selected_is_auto
        item.metadata["transcript_quality"] = score_transcript_quality(
            transcript_list, selected_is_auto
        )
        item.metadata["transcript_matches_target"] = (
            clean_target is not None
            and selected_lang is not None
            and clean_lang(selected_lang) == clean_target
        )
        if available:
            item.metadata["available_transcripts"] = available
        item.metadata["transcript_json"] = json.dumps(transcript_list)
        item.metadata["word_count"] = sum(
            len(e.get("text", "").split()) for e in transcript_list
        )
        return
    if available:
        item.metadata["available_transcripts"] = available

    transcript_list, selected_lang, selected_is_auto, available = (
        fetch_transcript_via_vtt(yt_dlp_info, audio_lang, target_lang=target_language)
    )
    if transcript_list:
        if audio_lang:
            item.metadata["language"] = audio_lang
        item.metadata["transcript_language"] = selected_lang
        item.metadata["transcript_is_auto"] = selected_is_auto
        item.metadata["transcript_quality"] = score_transcript_quality(
            transcript_list, selected_is_auto
        )
        item.metadata["transcript_matches_target"] = (
            clean_target is not None
            and selected_lang is not None
            and clean_lang(selected_lang) == clean_target
        )
        if available:
            item.metadata["available_transcripts"] = available
        item.metadata["transcript_json"] = json.dumps(transcript_list)
        item.metadata["word_count"] = sum(
            len(e.get("text", "").split()) for e in transcript_list
        )
        return
    if available:
        item.metadata["available_transcripts"] = available

    logger.info("No viable subtitles via API or VTT. Marking for ASR.")
    item.metadata["needs_transcription"] = True
