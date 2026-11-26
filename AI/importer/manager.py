"""
ImportManager — slim orchestrator for import processing.

Dispatches to specialized modules based on source_type:

- youtube      → importer.youtube.process_youtube()
- url          → importer.url_extractor.process_url()
- pdf / txt    → importer.file_extractor.process_file()
- text         → handled inline (simple metadata extraction)
"""

import uuid
import logging
import json
import traceback
from typing import Optional, Any

from import_models import ImportItem
from .exceptions import UnsupportedSourceError, ExtractionFailedError
from .youtube import process_youtube, fetch_transcript_entries, clean_lang
from .url_extractor import process_url
from .file_extractor import process_file, cleanup_temp_file, format_size


class JsonFormatter(logging.Formatter):
    """Structured JSON log formatter for Cloud Run / production."""

    def format(self, record):
        log_obj = {
            "time": self.formatTime(record, self.datefmt),
            "level": record.levelname,
            "name": record.name,
            "message": record.getMessage(),
        }
        if hasattr(record, "item_id"):
            log_obj["item_id"] = record.item_id
        if hasattr(record, "error"):
            log_obj["error"] = record.error
        if hasattr(record, "traceback"):
            log_obj["traceback"] = record.traceback
        if record.exc_info:
            log_obj["exception"] = self.formatException(record.exc_info)
        return json.dumps(log_obj)


# Configure structured logging for production (Cloud Run captures stdout)
handler = logging.StreamHandler()
handler.setFormatter(JsonFormatter(datefmt="%Y-%m-%dT%H:%M:%S"))
logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)
logger.handlers = [handler]
logger.propagate = False


class ImportManager:
    """Orchestrator for content import processing."""

    def __init__(self):
        pass

    def process_import(
        self, user_id: str, import_data: dict[str, Any], item_id: str = None
    ) -> ImportItem:
        """
        Main entry point to process an import request.

        Returns raw content + metadata only. Flutter handles client-side
        segmentation.
        """
        if not item_id:
            item_id = str(uuid.uuid4())

        source_type = import_data.get("source_type")
        target_language = import_data.get("target_language")

        item = ImportItem(
            id=item_id,
            user_id=user_id,
            title=import_data.get("title", "Untitled Import"),
            source_type=source_type,
            source_url=import_data.get("source_url"),
            file_path=import_data.get("file_path"),
            raw_text=import_data.get("raw_text"),
            subject_id=import_data.get("subject_id"),
            status="processing",
        )
        if target_language:
            item.metadata["target_language"] = target_language

        try:
            logger.info(
                "Processing import",
                extra={
                    "item_id": item_id,
                    "source_type": source_type,
                    "file_path": item.file_path,
                },
            )

            if source_type == "youtube":
                process_youtube(item, target_language=target_language)
            elif source_type in ("pdf", "txt"):
                process_file(item)
            elif source_type == "text":
                self._process_text(item)
            elif source_type == "url":
                process_url(item)
            else:
                raise UnsupportedSourceError(f"Unsupported source type: {source_type}")

            item.status = "completed"

        except Exception as e:
            item.status = "failed"
            item.metadata["error"] = str(e)
            logger.error(
                f"Import failed: {str(e)}",
                extra={
                    "item_id": item_id,
                    "error": str(e),
                    "traceback": traceback.format_exc(),
                },
            )

        return item

    @staticmethod
    def _process_text(item: ImportItem):
        """Process a raw text import — store raw text with metadata."""
        if not item.raw_text:
            raise ExtractionFailedError("No raw text provided for text import")
        item.metadata["type"] = "text"
        item.metadata["char_count"] = len(item.raw_text)
        item.metadata["word_count"] = len(item.raw_text.split())
        size_bytes = len(item.raw_text.encode("utf-8"))
        item.metadata["file_size_bytes"] = size_bytes
        item.metadata["file_size"] = format_size(size_bytes)

    # --- Backward-compatible accessors used by server.py /transcript route ---

    @staticmethod
    def _clean_lang(lang_code: Optional[str]) -> Optional[str]:
        """Delegate to the standalone clean_lang function."""
        return clean_lang(lang_code)

    @staticmethod
    def _fetch_transcript_entries(best_t):
        """Delegate to the standalone fetch_transcript_entries function."""
        return fetch_transcript_entries(best_t)

    @staticmethod
    def _cleanup_temp_file(path: str):
        """Delegate to the standalone cleanup_temp_file function."""
        cleanup_temp_file(path)
