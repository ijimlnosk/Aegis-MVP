export interface ServerAgentConfig {
  host: string;
  port: number;
  token: string;
}

type Environment = Record<string, string | undefined>;

export function loadConfig(env: Environment = process.env): ServerAgentConfig {
  const token = env.SERVER_AGENT_TOKEN;
  if (!token) throw new Error("SERVER_AGENT_TOKEN이 설정되지 않았습니다.");
  const port = Number(env.SERVER_AGENT_PORT ?? "4319");
  if (!Number.isInteger(port) || port < 1024 || port > 65535) {
    throw new Error("SERVER_AGENT_PORT는 1024~65535 사이여야 합니다.");
  }
  return { host: env.SERVER_AGENT_HOST ?? "127.0.0.1", port, token };
}
