import logging
import numpy as np
from datetime import datetime, timezone, timedelta
from typing import List, Dict, Any, Optional
from firebase_admin import firestore
import math

logger = logging.getLogger(__name__)


class RecommendationManager:
    def __init__(
        self,
        db: firestore.client,
        embedding_service: Optional["EmbeddingService"] = None,
    ):
        self.db = db
        self._embedding_dim = 384  # Standardized: both models now output 384-dim
        if embedding_service is not None:
            try:
                test_emb = embedding_service.embed_text("test")
                self._embedding_dim = len(test_emb)
            except Exception:
                logger.warning(
                    "Could not determine embedding dimension from service; using default 384"
                )

    def _cosine_similarity(self, v1: List[float], v2: List[float]) -> float:
        if not v1 or not v2:
            return 0.0
        # Handle dimension mismatch by truncating the longer vector.
        # This gives a reasonable approximation when comparing embeddings
        # from different models (e.g., 768-dim vs 384-dim during migration).
        if len(v1) != len(v2):
            min_dim = min(len(v1), len(v2))
            logger.debug(
                f"Embedding dimension mismatch: {len(v1)} vs {len(v2)}. "
                f"Truncating to {min_dim} for approximate similarity."
            )
            v1 = v1[:min_dim]
            v2 = v2[:min_dim]
        a = np.array(v1)
        b = np.array(v2)
        dot = np.dot(a, b)
        norm_a = np.linalg.norm(a)
        norm_b = np.linalg.norm(b)
        if norm_a == 0 or norm_b == 0:
            return 0.0
        return float(dot / (norm_a * norm_b))

    def _compute_user_embedding(self, user_content_docs: List) -> List[float]:
        """
        Compute time-weighted user interest vector from already-fetched docs.

        Accepts a list of Firestore document snapshots from the user's
        user_content collection so callers don't need to re-query.
        """
        now = datetime.now(timezone.utc)
        total_weight = 0.0
        # Collect (embedding, weight) pairs first, then aggregate using
        # the most common dimension so mixed-dimension stores still work.
        pairs: list[tuple[list[float], float]] = []

        for doc in user_content_docs:
            data = doc.to_dict()
            metadata = data.get("metadata", {}) or {}
            embedding = metadata.get("embedding")

            if not embedding:
                continue

            created_at = data.get("created_at")
            if isinstance(created_at, datetime):
                dt = created_at
            else:
                dt = (
                    created_at.replace(tzinfo=timezone.utc)
                    if created_at.tzinfo is None
                    else created_at
                )

            days_ago = (now - dt).days
            weight = math.exp(-days_ago / 30.0)  # 30-day half-life

            pairs.append((embedding, weight))

        if not pairs:
            return []

        # Use the target embedding dimension (most common among collected pairs)
        from collections import Counter

        dim_counts = Counter(len(e) for e, _ in pairs)
        target_dim = dim_counts.most_common(1)[0][0]

        sum_vector = np.zeros(target_dim)
        for embedding, weight in pairs:
            if len(embedding) == target_dim:
                sum_vector += np.array(embedding) * weight
                total_weight += weight
            elif len(embedding) > target_dim:
                # Truncate longer embeddings
                sum_vector += np.array(embedding[:target_dim]) * weight
                total_weight += weight
            # Skip shorter embeddings that can't be safely extended

        if total_weight == 0:
            return []

        return (sum_vector / total_weight).tolist()

    def _get_precomputed_cf_scores(self, user_id: str) -> Optional[Dict[str, float]]:
        """
        Read pre-computed collaborative filtering scores from user_similarity/{user_id}.

        The nightly Cloud Function computeUserSimilarity writes embedding-based
        user-user CF scores to this collection. This method reads them and
        validates freshness (48-hour TTL).

        Returns:
            Dict of canonical_content_id -> normalized_score [0, 1], or None if
            the data is unavailable or stale.
        """
        try:
            doc_ref = self.db.collection("user_similarity").document(user_id)
            doc = doc_ref.get()
            if not doc.exists:
                logger.debug(f"No pre-computed similarity data for user {user_id}")
                return None

            data = doc.to_dict()
            computed_at = data.get("computed_at")
            if not computed_at:
                return None

            # Ensure computed_at is timezone-aware
            # Note: Firestore Python Admin SDK returns datetime objects with UTC tzinfo.
            # The else branch is a safety net for unexpected types (e.g., protobuf Timestamp).
            if isinstance(computed_at, datetime):
                if computed_at.tzinfo is None:
                    computed_at = computed_at.replace(tzinfo=timezone.utc)
            else:
                try:
                    computed_at = computed_at.replace(tzinfo=timezone.utc)
                except AttributeError:
                    logger.warning(
                        f"Unexpected computed_at type for user {user_id}: "
                        f"{type(computed_at).__name__} — skipping staleness check"
                    )
                    return None

            # 48-hour freshness window (generous — runs nightly at 02:00 UTC)
            staleness_threshold = timedelta(hours=48)
            now = datetime.now(timezone.utc)
            if now - computed_at > staleness_threshold:
                logger.info(
                    f"Pre-computed similarity for user {user_id} is stale "
                    f"(computed_at={computed_at.isoformat()}, now={now.isoformat()})"
                )
                return None

            cf_scores = data.get("cf_scores")
            if not cf_scores or not isinstance(cf_scores, dict):
                return None

            # Convert all values to float (Firestore may store them as int or float).
            # Guard against non-numeric values just in case.
            result: Dict[str, float] = {}
            for k, v in cf_scores.items():
                if isinstance(v, (int, float)):
                    result[k] = float(v)
                else:
                    logger.warning(
                        f"Non-numeric CF score value for key {k}: {v!r} — skipping"
                    )
            return result

        except Exception as e:
            logger.warning(f"Failed to read pre-computed CF scores for {user_id}: {e}")
            return None

    def _get_fork_graph_scores(
        self, user_id: str, user_canonical_ids: set[str]
    ) -> Dict[str, float]:
        """
        Compute collaborative filtering scores based on the fork graph.

        Strategy: "Users who forked the same content as you also forked X."
        1. Accept pre-computed canonical content IDs the user has forked
        2. Find other users who forked the same canonical content
           (excludes the current [user_id] from forker set)
        3. Find what other canonical content those users also forked
        4. Count co-occurrences and normalize to [0, 1]

        This is the v1 fallback path. The v2 path uses pre-computed embedding-based
        user similarity scores from _get_precomputed_cf_scores().

        Returns a dict of: candidate_canonical_content_id -> normalized_score
        """
        if not user_canonical_ids:
            return {}

        # 2. For each canonical content the user has forked, find OTHER users
        #    who also forked it (up to 5 canonical items to limit queries)
        forker_user_ids: set[str] = set()
        for cid in list(user_canonical_ids)[:5]:
            forkers = (
                self.db.collection("user_content")
                .where("canonical_content_id", "==", cid)
                .limit(30)
                .stream()
            )
            for doc in forkers:
                forker_id = doc.to_dict().get("user_id")
                if forker_id and forker_id != user_id:
                    forker_user_ids.add(forker_id)

        if not forker_user_ids:
            return {}

        # 3. For those similar users, find what other canonical content they
        #    forked (up to 30 users to limit queries)
        co_occurrence: Dict[str, int] = {}
        for uid in list(forker_user_ids)[:30]:
            their_forks = (
                self.db.collection("user_content")
                .where("user_id", "==", uid)
                .limit(20)
                .stream()
            )
            for doc in their_forks:
                data = doc.to_dict()
                cid = data.get("canonical_content_id")
                # Exclude content the user already has a connection to
                if cid and cid not in user_canonical_ids:
                    co_occurrence[cid] = co_occurrence.get(cid, 0) + 1

        if not co_occurrence:
            return {}

        # 4. Normalize: score = count / max_count → [0, 1]
        max_count = max(co_occurrence.values())
        return {k: v / max_count for k, v in co_occurrence.items()}

    # def _log_impression(self, user_id: str, language: str, results: List[Dict[str, Any]], strategy: str, num_user_items: int) -> None:
    #     """Fire-and-forget impression logging to recommendation_logs."""
    #     try:
    #         recommended_ids = [r.get("id", "") for r in results]
    #         top_scores = [r.get("_score", 0.0) for r in results]
    #         self.db.collection("recommendation_logs").add({
    #             "user_id": user_id,
    #             "language": language,
    #             "date": firestore.SERVER_TIMESTAMP,
    #             "recommended_ids": recommended_ids,
    #             "top_scores": top_scores,
    #             "model_version": "hybrid_v2",
    #             "strategy": strategy,
    #             "num_user_items": num_user_items,
    #             "created_at": firestore.SERVER_TIMESTAMP,
    #         })
    #     except Exception:
    #         logger.warning("Failed to log impression (non-blocking)", exc_info=True)

    async def get_recommendations(
        self, user_id: str, language: str, limit: int = 20
    ) -> List[Dict[str, Any]]:
        try:
            # 1. Get user's own content IDs and build profile
            user_owned_ids = set()
            user_forked_from_ids = set()
            user_content_query = (
                self.db.collection("user_content")
                .where("user_id", "==", user_id)
                .stream()
            )
            user_content_list = list(user_content_query)
            num_user_items = len(user_content_list)

            # Early exit for cold-start users with no content
            if not user_content_list:
                # Return most popular public content in the requested language
                popular = (
                    self.db.collection("user_content")
                    .where("is_public", "==", True)
                    .where("assigned_languages", "array_contains", language)
                    .order_by("popularity_score", direction=firestore.Query.DESCENDING)
                    .limit(limit)
                    .stream()
                )
                results = []
                for doc in popular:
                    data = doc.to_dict()
                    data["id"] = doc.id
                    data["_score"] = data.get("popularity_score", 0.0) or 0.0
                    for key, value in data.items():
                        if isinstance(value, datetime):
                            data[key] = value.isoformat()
                    results.append(data)

                # # Log impression for cold start
                # self._log_impression(user_id, language, results, "cold_start", num_user_items)
                return results

            # Extract canonical IDs and owned IDs from the existing data
            user_canonical_ids: set[str] = set()
            for doc in user_content_list:
                data = doc.to_dict()
                user_owned_ids.add(doc.id)
                cid = data.get("canonical_content_id")
                if cid:
                    user_canonical_ids.add(cid)
                    user_forked_from_ids.add(cid)

            # 2. Build user profile (embedding) — reuses already-fetched docs
            user_embedding = self._compute_user_embedding(user_content_list)

            # 3. Try pre-computed v2 embedding-based CF scores first.
            #    Falls back to v1 fork-graph co-occurrence if unavailable.
            collab_scores = self._get_precomputed_cf_scores(user_id)
            if collab_scores is not None:
                strategy = "embedding_user_cf"
                logger.debug(
                    f"Using pre-computed embedding CF scores for user {user_id}"
                )
            else:
                collab_scores = self._get_fork_graph_scores(user_id, user_canonical_ids)
                if collab_scores:
                    strategy = "fork_graph_cf"
                elif user_embedding:
                    strategy = "content_based_only"
                else:
                    strategy = "popularity_fallback"

            # 4. Fetch candidates (public content in the same language)
            candidates_query = (
                self.db.collection("user_content")
                .where("is_public", "==", True)
                .where("assigned_languages", "array_contains", language)
                .limit(100)
                .stream()
            )

            scored_candidates = []
            for doc in candidates_query:
                candidate_id = doc.id
                if (
                    candidate_id in user_owned_ids
                    or candidate_id in user_forked_from_ids
                ):
                    continue

                data = doc.to_dict()
                if data.get("user_id") == user_id:
                    continue

                metadata = data.get("metadata", {}) or {}
                candidate_embedding = metadata.get("embedding")

                # --- Content-Based Score (Phase 2) ---
                cb_score = 0.0
                if user_embedding and candidate_embedding:
                    cb_score = self._cosine_similarity(
                        user_embedding, candidate_embedding
                    )

                # --- Collaborative Score (Phase 3) ---
                # collab_scores is keyed by canonical content ID; check both
                # the candidate's own ID and its canonical reference.
                cf_score = collab_scores.get(candidate_id, 0.0)
                if cf_score == 0.0:
                    candidate_canonical = data.get("canonical_content_id")
                    if candidate_canonical:
                        cf_score = collab_scores.get(candidate_canonical, 0.0)

                # --- Hybrid Score (Design spec: 0.6 CB + 0.4 CF) ---
                score = cb_score * 0.6 + cf_score * 0.4

                # --- Recency bonus (slight boost for newer content) ---
                created_at = data.get("created_at")
                if created_at:
                    if not isinstance(created_at, datetime):
                        created_at = (
                            created_at.replace(tzinfo=timezone.utc)
                            if created_at.tzinfo is None
                            else created_at
                        )

                    days_old = (datetime.now(timezone.utc) - created_at).days
                    recency_bonus = max(0, (30 - days_old) / 30.0) * 0.05
                    score += recency_bonus

                data["id"] = candidate_id
                data["_score"] = score
                scored_candidates.append(data)

            # Sort by score descending
            scored_candidates.sort(key=lambda x: x["_score"], reverse=True)

            # Convert to serializable format and limit results
            results = []
            for c in scored_candidates[:limit]:
                for key, value in c.items():
                    if isinstance(value, datetime):
                        c[key] = value.isoformat()
                results.append(c)

            # # Log impression (fire-and-forget)
            # self._log_impression(user_id, language, results, strategy, num_user_items)

            return results

        except Exception as e:
            logger.error(f"Error generating recommendations: {e}", exc_info=True)
            return []
