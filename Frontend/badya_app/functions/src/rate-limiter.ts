/**
 * Simple in-memory sliding-window rate limiter for Cloud Functions.
 *
 * This rate limiter is **per-instance**: each Cloud Function instance
 * maintains its own window. Combined with a conservative `maxInstances`
 * setting, this provides adequate protection without the cost/latency
 * of an external store (Firestore, Redis, etc.).
 *
 * Usage:
 * ```ts
 * const limiter = createRateLimiter(10, 60_000); // 10 requests per 60s
 *
 * // In your function:
 * if (limiter.isRateLimited(userId)) {
 *   throw new HttpsError("resource-exhausted", "Too many requests");
 * }
 * limiter.record(userId);
 * ```
 */

interface RateLimitEntry {
  /** Timestamps of recent requests (milliseconds). */
  timestamps: number[];
}

/**
 * Create a rate limiter with the given limits.
 *
 * @param maxRequests  Maximum number of requests allowed within the window.
 * @param windowMs     Window duration in milliseconds.
 * @returns  An object with `isRateLimited(userId)` and `record(userId)` methods.
 */
export function createRateLimiter(maxRequests: number, windowMs: number) {
  const store = new Map<string, RateLimitEntry>();

  // Periodic cleanup to prevent memory leaks (runs every `windowMs`)
  const cleanupInterval = setInterval(() => {
    const cutoff = Date.now() - windowMs;
    for (const [key, entry] of store) {
      // Remove expired timestamps
      entry.timestamps = entry.timestamps.filter((t) => t > cutoff);
      if (entry.timestamps.length === 0) {
        store.delete(key);
      }
    }
  }, windowMs);

  // Allow the Node.js process to exit even if the interval is still running
  if (cleanupInterval.unref) {
    cleanupInterval.unref();
  }

  return {
    /**
     * Check if the user has exceeded the rate limit.
     * Does NOT record the request — call `record()` separately.
     */
    isRateLimited(userId: string): boolean {
      const cutoff = Date.now() - windowMs;
      const entry = store.get(userId);
      if (!entry) return false;

      // Prune expired timestamps on read
      entry.timestamps = entry.timestamps.filter((t) => t > cutoff);
      if (entry.timestamps.length === 0) {
        store.delete(userId);
        return false;
      }

      return entry.timestamps.length >= maxRequests;
    },

    /**
     * Record a request for the given user.
     */
    record(userId: string): void {
      const entry = store.get(userId) ?? { timestamps: [] };
      entry.timestamps.push(Date.now());
      store.set(userId, entry);
    },

    /**
     * Combined check-and-record in one call.
     * Returns `true` if the request is allowed, `false` if rate-limited.
     */
    allow(userId: string): boolean {
      if (this.isRateLimited(userId)) return false;
      this.record(userId);
      return true;
    },

    /**
     * Clear all stored data (useful for testing).
     */
    clear(): void {
      store.clear();
    },
  };
}
