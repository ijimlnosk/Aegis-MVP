let sequence = 0;
export function createId(cryptoAPI = globalThis.crypto) {
  if (typeof cryptoAPI?.randomUUID === "function") return cryptoAPI.randomUUID();
  if (typeof cryptoAPI?.getRandomValues === "function") {
    const bytes = new Uint8Array(16); cryptoAPI.getRandomValues(bytes);
    return [...bytes].map(value => value.toString(16).padStart(2, "0")).join("");
  }
  sequence += 1;
  return `mobile-${Date.now().toString(36)}-${sequence.toString(36)}`;
}
