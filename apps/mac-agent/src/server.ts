import { createServer, type IncomingMessage, type ServerResponse } from "node:http";
import { loadConfig } from "./config.ts";
import { captureCurrentScreen, getActiveApplication, openApplication } from "./macTools.ts";

const config = loadConfig();

function send(response: ServerResponse, status: number, body: object) {
  response.writeHead(status, { "Content-Type": "application/json" });
  response.end(JSON.stringify(body));
}

async function readBody(request: IncomingMessage) {
  const chunks: Buffer[] = [];
  for await (const chunk of request) {
    chunks.push(Buffer.from(chunk));
    if (Buffer.concat(chunks).length > 10_000) throw new Error("요청 본문이 너무 큽니다.");
  }
  return JSON.parse(Buffer.concat(chunks).toString() || "{}") as { application?: unknown };
}

function isAuthorized(request: IncomingMessage) {
  return request.headers.authorization === `Bearer ${config.token}`;
}

const server = createServer(async (request, response) => {
  if (request.method !== "POST" || !isAuthorized(request)) {
    return send(response, request.method === "POST" ? 401 : 405, { error: "허용되지 않은 요청입니다." });
  }

  try {
    const body = await readBody(request);
    if (request.url === "/v1/tools/active-app") {
      return send(response, 200, { application: await getActiveApplication() });
    }
    if (request.url === "/v1/tools/capture-screen") {
      return send(response, 200, await captureCurrentScreen());
    }
    if (request.url === "/v1/tools/open-app" && typeof body.application === "string") {
      return send(response, 200, {
        output: await openApplication(body.application, config.allowedApps, config.allowAllApps),
      });
    }
    return send(response, 404, { error: "알 수 없는 도구 요청입니다." });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Mac Agent 실행 실패";
    return send(response, 400, { error: message });
  }
});

server.listen(config.port, "127.0.0.1", () => {
  console.log(`Aegis Mac Agent listening on 127.0.0.1:${config.port}`);
});
