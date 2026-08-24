export function normalizeGatewayURL(raw: string) {
  const url = new URL(raw.trim());
  if (!["http:", "https:"].includes(url.protocol) || url.username || url.password) throw new Error("invalidGatewayURL");
  if (url.protocol === "http:" && !privateHost(url.hostname)) throw new Error("insecurePublicGateway");
  url.pathname = ""; url.search = ""; url.hash = "";
  return url.toString().replace(/\/$/, "");
}

function privateHost(host: string) {
  if (["localhost", "127.0.0.1", "::1"].includes(host)) return true;
  const parts = host.split(".").map(Number);
  if (parts.length !== 4 || parts.some(value => !Number.isInteger(value) || value < 0 || value > 255)) return false;
  return parts[0] === 10 || (parts[0] === 100 && parts[1]! >= 64 && parts[1]! <= 127) ||
    (parts[0] === 172 && parts[1]! >= 16 && parts[1]! <= 31) || (parts[0] === 192 && parts[1] === 168);
}
