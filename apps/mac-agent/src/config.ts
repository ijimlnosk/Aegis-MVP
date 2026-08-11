export interface MacAgentConfig {
  allowedApps: Set<string>;
  allowAllApps: boolean;
  port: number;
  token: string;
}

type Environment = Record<string, string | undefined>;

export function loadConfig(env: Environment = process.env): MacAgentConfig {
  const token = env.MAC_AGENT_TOKEN;
  if (!token) throw new Error("MAC_AGENT_TOKEN이 설정되지 않았습니다.");

  const port = Number(env.MAC_AGENT_PORT ?? "4318");
  if (!Number.isInteger(port) || port < 1024 || port > 65535) {
    throw new Error("MAC_AGENT_PORT는 1024~65535 사이여야 합니다.");
  }

  const allowedApps = new Set(
    (env.MAC_AGENT_ALLOWED_APPS ?? "")
      .split(",")
      .map((name) => name.trim())
      .filter(Boolean),
  );
  return { allowedApps, allowAllApps: allowedApps.has("*"), port, token };
}
