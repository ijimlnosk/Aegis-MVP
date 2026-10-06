export interface CollapsedMessage { preview: string; truncated: boolean }

/** Long replies (lint output, diffs) are cut to a preview so one answer can't bury the chat. */
export function collapseMessage(content: string, maxLines = 12, maxChars = 700): CollapsedMessage {
  const lines = content.split("\n");
  let preview = lines.length > maxLines ? lines.slice(0, maxLines).join("\n") : content;
  if (preview.length > maxChars) preview = preview.slice(0, maxChars);
  const truncated = preview.length < content.length;
  return { preview: truncated ? `${preview.trimEnd()}…` : content, truncated };
}
