"""
Custom exceptions raised during import processing.

Each exception carries an optional ``code`` attribute that can be returned
in structured API error responses for consistent client-side handling.

Exception hierarchy::

    ImportProcessingError          (code: "import_error")
    ├── UnsupportedSourceError     (code: "unsupported_source")
    ├── FileNotFoundImportError    (code: "file_not_found")
    ├── ExtractionFailedError      (code: "extraction_failed")
    └── VideoIdExtractionError     (code: "video_id_extraction_failed")
"""


class ImportProcessingError(Exception):
    """Base exception for import processing errors."""

    code: str = "import_error"

    def __init__(self, message: str = "", code: str = ""):
        super().__init__(message)
        if code:
            self.code = code


class UnsupportedSourceError(ImportProcessingError):
    """Raised when the source type is not supported."""
    code: str = "unsupported_source"


class FileNotFoundImportError(ImportProcessingError):
    """Raised when the import file cannot be found."""
    code: str = "file_not_found"


class ExtractionFailedError(ImportProcessingError):
    """Raised when content extraction fails."""
    code: str = "extraction_failed"


class VideoIdExtractionError(ImportProcessingError):
    """Raised when a video ID cannot be extracted from a URL."""
    code: str = "video_id_extraction_failed"
