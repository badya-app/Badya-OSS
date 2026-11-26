"""
File-based import extraction (PDF, TXT) and temporary file cleanup.
"""

import os
import math
import logging
from typing import Optional, List
from concurrent.futures import ThreadPoolExecutor, as_completed

from import_models import ImportItem
from firebase.storage import upload_to_firebase_imports
from .exceptions import ExtractionFailedError, FileNotFoundImportError

logger = logging.getLogger(__name__)


def format_size(size_bytes: int) -> str:
    """Human-readable file size (e.g. '1.5 MB')."""
    if size_bytes == 0:
        return "0 B"
    size_name = ("B", "KB", "MB", "GB", "TB")
    i = int(math.floor(math.log(size_bytes, 1024)))
    p = math.pow(1024, i)
    s = round(size_bytes / p, 1)
    return f"{s} {size_name[i]}"


def cleanup_temp_file(path: str):
    """Safely remove a temporary file and its parent dir if empty."""
    try:
        if os.path.exists(path):
            os.remove(path)
        parent = os.path.dirname(path)
        if parent and os.path.isdir(parent) and not os.listdir(parent):
            os.rmdir(parent)
    except OSError as e:
        logger.info(f"Cleanup warning: {e}")


def process_file(item: ImportItem):
    """Process a PDF or TXT file import — extract text, no segmentation."""
    if not item.file_path:
        raise FileNotFoundImportError("No file path provided for import")

    item.file_path = os.path.expanduser(item.file_path)

    if not os.path.exists(item.file_path):
        raise FileNotFoundImportError(
            f"File not found at: {item.file_path}. Path may be inaccessible or deleted."
        )

    try:
        size_bytes = os.path.getsize(item.file_path)
        item.metadata["file_size_bytes"] = size_bytes
        item.metadata["file_size"] = format_size(size_bytes)
    except OSError as e:
        logger.info(f"Could not get file size: {e}")

    text = ""
    if item.source_type == "pdf":
        try:
            import fitz
        except ImportError:
            raise ExtractionFailedError(
                "PDF extraction requires 'pymupdf' package. "
                "Please install it with 'pip install pymupdf'."
            )
        try:
            doc = fitz.open(item.file_path)
            
            # Extract Table of Contents (chapters) if available
            try:
                toc = doc.get_toc()
                if toc:
                    item.metadata["chapters"] = [
                        {
                            "level": t[0],
                            "title": t[1],
                            "page": t[2],
                        }
                        for t in toc
                    ]
            except Exception as toc_e:
                logger.info(f"Could not extract TOC from PDF: {toc_e}")

            # ── Phase 1: Extract text + collect image extraction tasks ──
            image_tasks: List[tuple] = []  # (page_num, bbox, img_idx)
            for page_num, page in enumerate(doc):
                text_blocks = page.get_text("blocks")
                image_info = page.get_image_info()
                combined = []
                for b in text_blocks:
                    combined.append({"type": "text", "bbox": b[:4], "content": b[4]})
                for img in image_info:
                    combined.append({"type": "image", "bbox": img["bbox"]})
                combined.sort(key=lambda x: (x["bbox"][1], x["bbox"][0]))
                for part in combined:
                    if part["type"] == "text":
                        text += part["content"] + "\n"
                    elif part["type"] == "image":
                        bbox = part["bbox"]
                        image_tasks.append((page_num, bbox, len(image_tasks) + 1))
                text += f"\n\n<!-- PAGE_BREAK_PAGE_{page_num+1} -->\n\n"

            # ── Phase 2: Extract & upload images in parallel ────────────
            def _extract_upload_image(page_num: int, bbox, img_idx: int):
                """Extract a single image from a PDF page and upload to Firebase."""
                try:
                    page = doc[page_num]
                    pix = page.get_pixmap(clip=bbox)
                    if pix.width < 10 or pix.height < 10:
                        return None
                    img_filename = f"{item.id}_p{page_num}_i{img_idx}.png"
                    image_url = upload_to_firebase_imports(
                        img_filename,
                        pix.tobytes("png"),
                        "image/png",
                    )
                    if image_url is None:
                        return None
                    return f"\n\n![Image]({image_url})\n\n"
                except Exception as img_e:
                    logger.info(f"Warning: Could not extract image at {bbox}: {img_e}")
                    return None

            image_markdowns = []
            with ThreadPoolExecutor(max_workers=10) as executor:
                futures = {
                    executor.submit(_extract_upload_image, pn, bb, idx): idx
                    for pn, bb, idx in image_tasks
                }
                for future in as_completed(futures):
                    result = future.result()
                    if result is not None:
                        image_markdowns.append(result)

            # Append all image markdowns to text (order doesn't matter for images)
            for md in image_markdowns:
                text += md

            doc.close()
            if not text.strip():
                item.metadata["needs_ocr"] = True
                logger.info(
                    f"Warning: No text extracted from {item.file_path}. "
                    f"Marking for OCR."
                )
        except ExtractionFailedError:
            raise
        except Exception as e:
            raise ExtractionFailedError(f"Failed to read PDF with PyMuPDF: {str(e)}")

    elif item.source_type == "txt":
        try:
            with open(item.file_path, "r", encoding="utf-8") as f:
                text = f.read()
        except UnicodeDecodeError:
            with open(item.file_path, "r", encoding="latin-1") as f:
                text = f.read()
        except Exception as e:
            raise ExtractionFailedError(f"Failed to read TXT: {str(e)}")

    if not text.strip():
        raise ExtractionFailedError("File is empty or contains no readable text.")

    item.raw_text = text
    item.metadata["word_count"] = len(text.split())
    item.metadata["char_count"] = len(text)
