export type ProjectLocation = "mac" | "server";

export interface AegisProject {
  id: string;
  name: string;
  location: ProjectLocation;
  path: string;
}
