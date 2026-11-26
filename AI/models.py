from pydantic import BaseModel
from typing import List, Optional

class RecommendRequest(BaseModel):
    user_id: str
    language: str
    limit: int = 20

class EmbedRequest(BaseModel):
    title: str
    description: str
    tags: List[str]

class EmbedResponse(BaseModel):
    embedding: List[float]


class SearchRequest(BaseModel):
    query: str
    language: str
    limit: int = 50
    type_filter: Optional[List[str]] = None


class SearchResponse(BaseModel):
    items: List[dict]
    has_more: bool
