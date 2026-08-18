import { resolve } from "node:path";
import type { AegisProject } from "./types";

type Environment = Record<string, string | undefined>;

export function createProjectRegistry(env: Environment = process.env) {
  const projects: AegisProject[] = [
    { id: "ptfriends", name: "PTFriends", location: "mac", path: env.PTFRIENDS_PROJECT_ROOT ?? "" },
    { id: "soolsool", name: "SoolSool", location: "mac", path: env.SOOLSOOL_PROJECT_ROOT ?? "" },
    { id: "sol-server", name: "sol-server", location: "server", path: env.SOL_SERVER_PROJECT_ROOT ?? "" },
  ];

  return {
    getProject(id: string) {
      const project = projects.find((item) => item.id === id);
      if (!project?.path) throw new Error(`프로젝트 설정을 찾을 수 없습니다: ${id}`);
      return { ...project, path: resolve(project.path) };
    },
    getProjects() {
      return projects.filter((project) => project.path).map((project) => ({ ...project }));
    },
  };
}

export const { getProject, getProjects } = createProjectRegistry();
