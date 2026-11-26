"""
importer/ — Modular import processing package.

Extracted from the original monolithic import_manager.py (~1100 lines)
into focused single-responsibility modules:

    manager.py           ImportManager orchestrator
    youtube.py           YouTube transcript & metadata extraction
    url_extractor.py     Web article extraction
    file_extractor.py    PDF / TXT extraction + temp file cleanup
    vtt_parser.py        VTT caption file parsing
    exceptions.py        Custom exception classes
    models.py            ImportItem dataclass (re-exported from import_models)

Usage:
    from importer.manager import ImportManager
    from importer.youtube import fetch_transcript_list, clean_lang
    from importer import logger as import_logger
"""

from .manager import ImportManager, logger
from .youtube import fetch_transcript_list, clean_lang
from .exceptions import (
    ImportProcessingError,
    UnsupportedSourceError,
    FileNotFoundImportError,
    ExtractionFailedError,
    VideoIdExtractionError,
)

__all__ = [
    "ImportManager",
    "fetch_transcript_list",
    "clean_lang",
    "logger",
    "ImportProcessingError",
    "UnsupportedSourceError",
    "FileNotFoundImportError",
    "ExtractionFailedError",
    "VideoIdExtractionError",
]
