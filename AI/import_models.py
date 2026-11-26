from dataclasses import dataclass, field, asdict
from typing import List, Optional
import datetime

@dataclass
class ImportItem:
    id: str
    user_id: str
    title: str
    source_type: str  # 'youtube', 'pdf', 'txt', 'text', 'url'
    source_url: Optional[str] = None
    file_path: Optional[str] = None
    raw_text: Optional[str] = None
    subject_id: Optional[str] = None
    status: str = 'pending'  # 'pending', 'processing', 'completed', 'failed'
    created_at: str = field(default_factory=lambda: datetime.datetime.now().isoformat())
    lessons: List = field(default_factory=list)  # Kept for backward compat — always empty in new flow
    metadata: dict = field(default_factory=dict)  # Store extra info like video duration, transcript_json, etc.

    def to_dict(self):
        data = asdict(self)
        data['lessons'] = []  # No lessons created — segmentation is client-side
        return data

    @staticmethod
    def from_dict(data):
        # Create a copy of data to modify
        init_data = data.copy()
        init_data['lessons'] = []  # Ignore any legacy lesson data
        return ImportItem(**init_data)
