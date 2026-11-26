from typing import List
from pydantic import BaseModel, Field


class WordScore(BaseModel):
    word: str = Field(
        description="The specific word or sentence used or tested in the lesson."
    )
    score: int = Field(
        description="A score from 0-100 reflecting the student's mastery of this word.",
        ge=0,
        le=100,
    )


class AnalysisOutput(BaseModel):
    user_performance_summary: str = Field(
        description="A qualitative summary of the student's performance, highlighting strengths, weaknesses, and areas for improvement. This will be used to adapt future lessons and inform the language_level."
    )
    language_level: str = Field(
        description="A comprehensive assessment of the student's overall language level. Include estimated CEFR level (e.g., A1 Beginner, A2 Elementary, B1 Intermediate, B2 Upper Intermediate, C1 Advanced, C2 Proficient), specific strengths (e.g., vocabulary range, sentence formation), specific weaknesses (e.g., verb conjugation, prepositions), vocabulary range assessment, and grammar accuracy. This string is passed to other AI agents to adapt their teaching style, so it must be detailed and actionable."
    )
    understanding_percentage: int = Field(
        description="A score from 0-100 indicating the student's comprehension of the story/material.",
        ge=0,
        le=100,
    )
    expression_percentage: int = Field(
        description="A score from 0-100 indicating the quality of the student's language expression (grammar, vocabulary, fluency).",
        ge=0,
        le=100,
    )
    communication_percentage: int = Field(
        description="A score from 0-100 indicating the effectiveness of communication in a role-play scenario.",
        ge=0,
        le=100,
    )
    word_scores: List[WordScore] = Field(
        description="A list of objects, each with a 'word' (the word/sentence tested) and a 'score' (0-100) reflecting the student's mastery of that word.",
        default_factory=list,
    )
