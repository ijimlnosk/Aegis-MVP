import { resolve } from "node:path";

export function getProjectRoot() {
  const configured = process.env.JARVIS_PROJECT_ROOT;
  if (!configured) {
    throw new Error("JARVIS_PROJECT_ROOT가 설정되지 않았습니다.");
  }
  return resolve(configured);
}
