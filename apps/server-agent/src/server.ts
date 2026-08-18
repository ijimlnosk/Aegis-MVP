import { createServer, type IncomingMessage, type ServerResponse } from "node:http";
import { loadConfig } from "./config.ts";
import { changeContainerState, getContainers, getDockerLogs } from "./dockerTools.ts";
import { getProjectStatus } from "./projectTools.ts";
import { getDiskUsage, getMemoryUsage, getUptime } from "./systemTools.ts";

const config = loadConfig();

function send(response: ServerResponse, status: number, body: object) {
  response.writeHead(status, { "Content-Type": "application/json" });
  response.end(JSON.stringify(body));
}

async function readBody(request: IncomingMessage) {
  const chunks: Buffer[] = [];
  let size = 0;
  for await (const chunk of request) {
    size += chunk.length;
    if (size > 10_000) throw new Error("요청 본문이 너무 큽니다.");
    chunks.push(Buffer.from(chunk));
  }
  return JSON.parse(Buffer.concat(chunks).toString() || "{}") as Record<string, unknown>;
}

async function route(path: string, body: Record<string, unknown>) {
  if (path === "/v1/tools/system-status") {
    const [uptime, memory, disk, docker] = await Promise.all([
      getUptime(), getMemoryUsage(), getDiskUsage(), getContainers(),
    ]);
    return { server: "sol-server", uptime, memory, disk, docker };
  }
  if (path === "/v1/tools/docker-containers") return { output: await getContainers() };
  if (path === "/v1/tools/docker-logs") return { output: await getDockerLogs(body.container, body.lines) };
  if (path === "/v1/tools/project-status") return { output: await getProjectStatus(body.project) };
  const match = path.match(/^\/v1\/tools\/docker-(restart|stop|start)$/);
  if (match) return { output: await changeContainerState(match[1] as "restart" | "stop" | "start", body.container) };
  throw new Error("알 수 없는 도구 요청입니다.");
}

createServer(async (request, response) => {
  if (request.method !== "POST") return send(response, 405, { error: "POST 요청만 허용됩니다." });
  if (request.headers.authorization !== `Bearer ${config.token}`) {
    return send(response, 401, { error: "허용되지 않은 요청입니다." });
  }
  try {
    return send(response, 200, await route(request.url ?? "", await readBody(request)));
  } catch (error) {
    const message = error instanceof Error ? error.message : "Server Agent 실행 실패";
    return send(response, message === "알 수 없는 도구 요청입니다." ? 404 : 400, { error: message });
  }
}).listen(config.port, config.host, () => {
  console.log(`Aegis Server Agent listening on ${config.host}:${config.port}`);
});
