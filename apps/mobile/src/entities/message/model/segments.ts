export type MessageSegment = { kind: "text" | "code"; text: string };

/** Splits ``` fenced parts out of a reply; an unclosed fence (truncated reply) stays code. */
export function splitSegments(content: string): MessageSegment[] {
  const segments: MessageSegment[] = [];
  let buffer: string[] = [];
  let inCode = false;
  const flush = () => {
    const joined = buffer.join("\n"); buffer = [];
    if (inCode) segments.push({ kind: "code", text: joined });
    else if (joined.trim()) segments.push({ kind: "text", text: joined.replace(/^\n+|\n+$/g, "") });
  };
  for (const line of content.split("\n")) {
    if (line.trim().startsWith("```")) { flush(); inCode = !inCode; } else buffer.push(line);
  }
  flush();
  return segments;
}
