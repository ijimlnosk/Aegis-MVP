import { useCallback, useEffect, useState } from "react";
import { quickRequests, rememberRequest } from "@/entities/command/model/recentRequests";
import { recentRequestStore } from "@/shared/storage/recentRequestStore";

export function useRecentRequests() {
  const [recent, setRecent] = useState<string[]>([]);
  useEffect(() => { void recentRequestStore.load().then(setRecent).catch(() => undefined); }, []);
  const remember = useCallback((text: string) => setRecent(current => {
    const next = rememberRequest(current, text);
    void recentRequestStore.save(next).catch(() => undefined);
    return next;
  }), []);
  return { quick: quickRequests(recent), remember };
}
