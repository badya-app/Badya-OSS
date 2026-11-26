import os
import logging
from typing import Optional, List
from google.genai import types

logger = logging.getLogger(__name__)


class EmbeddingService:
    """
    Embedding service using multilingual-e5-small-maas via Vertex AI MaaS.
    Requires Vertex AI enabled (GOOGLE_GENAI_USE_VERTEXAI=True).
    """

    def __init__(self, model_name: str = "intfloat/multilingual-e5-small-maas", output_dim: int = 384):
        self.client = None
        self._output_dim = output_dim
        use_vertex = os.getenv("GOOGLE_GENAI_USE_VERTEXAI", "false").lower() == "true"

        if use_vertex:
            # Map shorthand to fully qualified publisher model path for Vertex AI Model Garden
            if model_name in ["intfloat/multilingual-e5-small-maas", "multilingual-e5-small-maas"]:
                model_name = "publishers/intfloat/models/multilingual-e5-small-maas"
            
            self._model_name = model_name
            logger.info(
                f"Initializing Vertex AI MaaS embedding service with model: {self._model_name}"
            )
            try:
                # Attempt to set Google Application Default Credentials if not already configured
                if not os.getenv("GOOGLE_APPLICATION_CREDENTIALS"):
                    from pathlib import Path
                    # Cloud Run: mounted as Secret Manager volume (TASK-11)
                    sa_path = Path("/secrets/sa-key/key.json")
                    # Local dev: fallback to project root
                    if not sa_path.exists():
                        sa_path = Path(__file__).parent / "serviceAccountKey.json"
                    if sa_path.exists():
                        os.environ["GOOGLE_APPLICATION_CREDENTIALS"] = str(sa_path)

                from google import genai
                project = os.getenv("GOOGLE_CLOUD_PROJECT")
                location = os.getenv("GOOGLE_CLOUD_LOCATION", "us-central1")
                self.client = genai.Client(
                    vertexai=True, project=project, location=location
                )
                logger.info("Vertex AI MaaS embedding service initialized successfully.")
            except Exception as e:
                logger.error(f"Failed to initialize Vertex AI embedding client: {e}")
        else:
            # Gemini Developer API fallback
            if "maas" in model_name:
                model_name = "text-embedding-004"
            self._model_name = model_name
            logger.info(
                f"Initializing Gemini API embedding service with model: {self._model_name}"
            )
            try:
                from google import genai
                self.client = genai.Client()
                logger.info("Gemini API embedding service initialized successfully.")
            except Exception as e:
                logger.error(f"Failed to initialize Gemini embedding client: {e}")

    def embed_text(self, text: str) -> List[float]:
        if not self.client:
            logger.error("google-genai client not initialized.")
            return [0.0] * self._output_dim
        try:
            response = self.client.models.embed_content(
                model=self._model_name,
                contents=text,
                config=types.EmbedContentConfig(
                    output_dimensionality=self._output_dim,
                ),
            )
            if response and response.embeddings:
                values = response.embeddings[0].values
                logger.debug(
                    f"Embedding dimension: {len(values)} (model: {self._model_name})"
                )
                return values
            else:
                logger.error("Empty embeddings returned from API.")
                return [0.0] * self._output_dim
        except Exception as e:
            logger.error(f"Embedding generation failed: {e}")
            return [0.0] * self._output_dim

    def embed_content(
        self, title: str, description: str, tags: List[str]
    ) -> List[float]:
        text = f"{title}. {description}. Tags: {', '.join(tags)}"
        return self.embed_text(text)

    def close(self):
        pass


# ---------------------------------------------------------------------------
# Module-level reference (explicitly managed)
# ---------------------------------------------------------------------------
_service: Optional[EmbeddingService] = None


def init_embedding_service(
    model_name: str = "intfloat/multilingual-e5-small-maas",
) -> EmbeddingService:
    """Initialize the embedding service once. Called during app startup."""
    global _service
    if _service is not None:
        logger.warning(
            "EmbeddingService already initialized; reusing existing instance."
        )
        return _service
    _service = EmbeddingService(model_name)
    return _service


def get_embedding_service() -> EmbeddingService:
    """Get the initialized service. Auto-initializes as a fallback if
    init_embedding_service() was not called (defensive against startup
    race conditions or lifecycle edge cases)."""
    if _service is None:
        logger.warning(
            "get_embedding_service: not initialized yet — initializing on demand. "
            "Ensure init_embedding_service() is called at startup for predictable behaviour."
        )
        return init_embedding_service()
    return _service


def shutdown_embedding_service():
    """Clean up the service. Called during app shutdown."""
    global _service
    if _service is not None:
        _service.close()
        _service = None
        logger.info("EmbeddingService shut down.")


async def get_embedding_service_dep() -> EmbeddingService:
    """FastAPI dependency that returns the initialized EmbeddingService."""
    return get_embedding_service()
