export class RateLimiter {
  private readonly requests = new Map<string, number[]>();
  private readonly limit: number;
  private readonly windowMs: number;
  constructor(limit: number, windowMs = 60_000) { this.limit = limit; this.windowMs = windowMs; }

  accept(key: string, now = Date.now()) {
    const recent = (this.requests.get(key) ?? []).filter(value => value > now - this.windowMs);
    if (recent.length >= this.limit) { this.requests.set(key, recent); return false; }
    recent.push(now); this.requests.set(key, recent); return true;
  }
}
