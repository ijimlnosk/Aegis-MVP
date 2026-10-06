export const MAX_RECENT_REQUESTS = 6;
export const DEFAULT_QUICK_REQUESTS = ["/status", "PTFriends 상태 보여줘", "sol-server 상태 보여줘", "PTFriends 어디까지 했지?"];

/** Most recent first, without duplicates; slash commands stay in the palette instead. */
export function rememberRequest(recent: readonly string[], text: string): string[] {
  const value = text.trim();
  if (!value || value.startsWith("/")) return [...recent];
  return [value, ...recent.filter(item => item !== value)].slice(0, MAX_RECENT_REQUESTS);
}

export function quickRequests(recent: readonly string[]): string[] {
  return recent.length > 0 ? [...recent] : DEFAULT_QUICK_REQUESTS;
}

export function parseRecentRequests(raw: string | undefined): string[] {
  try {
    const value: unknown = raw ? JSON.parse(raw) : [];
    return Array.isArray(value) ? value.filter((item): item is string => typeof item === "string").slice(0, MAX_RECENT_REQUESTS) : [];
  } catch { return []; }
}
