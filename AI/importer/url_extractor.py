"""
Web article URL extraction with professional fallback chain.
"""

import logging
from typing import List, Optional, Tuple

from import_models import ImportItem
from firebase.storage import upload_to_firebase_imports
from .exceptions import ExtractionFailedError
from .file_extractor import format_size

logger = logging.getLogger(__name__)


def _extract_and_embed_images(html: str, url: str, item: ImportItem, text: str) -> str:
    """Download article images, upload to Firebase Storage, embed markdown.

    Image downloads and Firebase uploads are parallelised using
    ``concurrent.futures.ThreadPoolExecutor`` (up to 10 concurrent workers)
    to avoid blocking the entire import on sequential HTTP requests.
    """
    try:
        from bs4 import BeautifulSoup
        from urllib.parse import urljoin
        import requests as req_lib
        from concurrent.futures import ThreadPoolExecutor, as_completed
    except Exception:
        return text

    try:
        img_soup = BeautifulSoup(html, "lxml")
        content_container = None
        for sel in [
            "article",
            "main",
            '[role="main"]',
            ".post-content",
            ".article-body",
            ".entry-content",
            ".content",
        ]:
            content_container = img_soup.select_one(sel)
            if content_container:
                break
        if not content_container:
            content_container = img_soup.body or img_soup

        # ── Phase 1: Collect image references (lightweight, no network) ──
        image_tasks: List[Tuple[str, str, str]] = []  # (full_url, alt, anchor_text)
        last_text_block = ""
        seen_urls = set()

        for child in content_container.descendants:
            if child.name in (
                "p",
                "div",
                "span",
                "h1",
                "h2",
                "h3",
                "h4",
                "h5",
                "h6",
                "li",
                "blockquote",
            ):
                txt = child.get_text(strip=True)
                if txt:
                    last_text_block = txt
            elif child.name == "img" and child.get("src"):
                src = child.get("src", "")
                if not src or src.startswith("data:"):
                    continue
                full_url = urljoin(url, src)
                if ".svg" in full_url.lower() or full_url in seen_urls:
                    continue
                seen_urls.add(full_url)
                if not last_text_block or full_url in text:
                    continue
                alt = child.get("alt", "")
                image_tasks.append((full_url, alt, last_text_block))

        if not image_tasks:
            return text

        # ── Phase 2: Download & upload images in parallel ──────────────
        def _download_and_upload(full_url: str, alt: str, idx: int):
            """Download a single image and upload it to Firebase Storage."""
            try:
                img_resp = req_lib.get(full_url, timeout=10, stream=True)
                if img_resp.status_code != 200:
                    return None
                ct = img_resp.headers.get("content-type", "")
                if "svg" in ct:
                    return None
                ext = ".jpg"
                if "png" in ct:
                    ext = ".png"
                elif "gif" in ct:
                    ext = ".gif"
                elif "webp" in ct:
                    ext = ".webp"
                filename = f"{item.id}_img_{idx}{ext}"
                image_url = upload_to_firebase_imports(
                    filename,
                    img_resp.content,
                    ct or "image/jpeg",
                )
                if image_url is None:
                    return None
                return (alt, image_url)
            except Exception:
                return None

        images_to_insert: List[Tuple[str, str]] = []
        with ThreadPoolExecutor(max_workers=10) as executor:
            futures = {
                executor.submit(_download_and_upload, url_, alt, i + 1): anchor
                for i, (url_, alt, anchor) in enumerate(image_tasks)
            }
            for future in as_completed(futures):
                result = future.result()
                if result is not None:
                    alt_text, image_url = result
                    anchor = futures[future]
                    images_to_insert.append((anchor, f"![{alt_text}]({image_url})"))

        if not images_to_insert:
            return text

        if images_to_insert:
            lines = text.split("\n")
            result = []
            remaining = list(images_to_insert)
            for line in lines:
                result.append(line)
                still_remaining = []
                for anchor, md in remaining:
                    if anchor and (
                        line.strip().startswith(anchor[:80])
                        or anchor[:60] in line.strip()
                    ):
                        result.append("")
                        result.append(md)
                    else:
                        still_remaining.append((anchor, md))
                remaining = still_remaining
            for anchor, md in remaining:
                for pos in range(len(lines) - 1, -1, -1):
                    stripped = lines[pos].strip()
                    if anchor and (
                        stripped.startswith(anchor[:80]) or anchor[:60] in stripped
                    ):
                        idx = result.index(lines[pos])
                        result.insert(idx + 1, "")
                        result.insert(idx + 2, md)
                        break
                else:
                    result.append("")
                    result.append(md)
            text = "\n".join(result)
        return text
    except Exception:
        return text


def process_url(item: ImportItem):
    """Process a web article import with professional fallback chain."""
    if not item.source_url:
        raise ExtractionFailedError("No URL provided for web import.")

    import requests as req_lib

    url = item.source_url.strip()
    logger.info(f"[ImportAgent] Fetching web article: {url}")

    headers = {
        "User-Agent": (
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
            "AppleWebKit/537.36 (KHTML, like Gecko) "
            "Chrome/120.0.0.0 Safari/537.36"
        ),
        "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        "Accept-Language": "en-US,en;q=0.5",
    }

    try:
        response = req_lib.get(
            url,
            headers=headers,
            timeout=15,
            allow_redirects=True,
        )
    except req_lib.exceptions.Timeout:
        raise ExtractionFailedError(
            "The website took too long to respond. Try a different URL "
            "or check your connection."
        )
    except req_lib.exceptions.ConnectionError:
        raise ExtractionFailedError(
            "Could not connect to the website. Please verify the URL and try again."
        )
    except req_lib.exceptions.InvalidURL:
        raise ExtractionFailedError(f"Invalid URL format: {url}")
    except Exception as e:
        raise ExtractionFailedError(f"Failed to download URL: {e}")

    status = response.status_code
    if status == 401:
        raise ExtractionFailedError(
            "This website requires a subscription (paywall) and returned "
            "HTTP 401 Unauthorized. Try a different source."
        )
    if status == 403:
        raise ExtractionFailedError(
            "This website blocked the request (HTTP 403 Forbidden). "
            "The site may be behind a paywall or use anti-bot protection."
        )
    if status == 404:
        raise ExtractionFailedError(
            "Page not found (HTTP 404). Please check the URL and try again."
        )
    if status >= 400:
        raise ExtractionFailedError(
            f"The website returned an error (HTTP {status}). "
            "The page may require authentication or be temporarily unavailable."
        )

    html = response.text
    if not html or not html.strip():
        raise ExtractionFailedError(
            "The website returned an empty page. Try a different URL."
        )

    # ── Extraction fallback chain ───────────────────────────────────────
    text = None
    meta_title = None
    meta_author = None
    meta_sitename = None

    try:
        import trafilatura

        text = trafilatura.extract(
            html,
            include_comments=False,
            include_tables=True,
            no_fallback=False,
        )
        meta = trafilatura.extract_metadata(html)
        if meta:
            meta_title = getattr(meta, "title", None) or meta_title
            meta_author = getattr(meta, "author", None) or meta_author
            meta_sitename = getattr(meta, "sitename", None) or meta_sitename
        if text and text.strip():
            logger.info("[ImportAgent] Extracted via trafilatura")
    except Exception:
        pass

    if not text or not text.strip():
        try:
            from readability import Document

            doc = Document(html)
            title = doc.title()
            summary_html = doc.summary()
            if summary_html:
                from bs4 import BeautifulSoup

                soup = BeautifulSoup(summary_html, "lxml")
                text = soup.get_text(separator="\n", strip=True)
                if title and not meta_title:
                    meta_title = title
                if text and text.strip():
                    logger.info("[ImportAgent] Extracted via readability-lxml")
        except Exception:
            pass

    if not text or not text.strip():
        try:
            from bs4 import BeautifulSoup

            soup = BeautifulSoup(html, "lxml")
            for tag in soup(
                [
                    "script",
                    "style",
                    "nav",
                    "header",
                    "footer",
                    "aside",
                    "noscript",
                    "iframe",
                    "form",
                ]
            ):
                tag.decompose()
            for selector in [
                "article",
                "main",
                '[role="main"]',
                ".post-content",
                ".article-body",
                ".entry-content",
                ".content",
            ]:
                container = soup.select_one(selector)
                if container:
                    text = container.get_text(separator="\n", strip=True)
                    break
            if not text or not text.strip():
                text = soup.get_text(separator="\n", strip=True)
            if text and text.strip():
                if not meta_title and soup.title:
                    meta_title = soup.title.get_text(strip=True)
                logger.info("[ImportAgent] Extracted via BeautifulSoup")
        except Exception:
            pass

    if not text or not text.strip():
        raise ExtractionFailedError(
            "Could not extract readable text from this page. "
            "The page may use JavaScript exclusively or require authentication."
        )

    text = text.strip()

    if meta_title and (not item.title or item.title == "Untitled Import"):
        item.title = meta_title
    item.metadata["author"] = meta_author
    item.metadata["sitename"] = meta_sitename
    item.metadata["type"] = "text"
    item.metadata["source_type"] = "url"
    item.metadata["url"] = item.source_url
    item.metadata["word_count"] = len(text.split())
    item.metadata["char_count"] = len(text)
    size_bytes = len(text.encode("utf-8"))
    item.metadata["file_size_bytes"] = size_bytes
    item.metadata["file_size"] = format_size(size_bytes)
    item.raw_text = text

    item.raw_text = _extract_and_embed_images(html, url, item, text)
