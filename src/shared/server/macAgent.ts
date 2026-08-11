interface MacAgentError {
  error?: string;
}

export async function callMacAgent<T>(path: string, body: object = {}): Promise<T> {
  const token = process.env.MAC_AGENT_TOKEN;
  if (!token) throw new Error("MAC_AGENT_TOKEN이 설정되지 않았습니다.");

  const baseUrl = process.env.MAC_AGENT_URL ?? "http://127.0.0.1:4318";
  const response = await fetch(`${baseUrl}${path}`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
    cache: "no-store",
  });
  const data = await response.json() as T & MacAgentError;
  if (!response.ok) throw new Error(data.error ?? "Mac Agent 요청에 실패했습니다.");
  return data;
}
