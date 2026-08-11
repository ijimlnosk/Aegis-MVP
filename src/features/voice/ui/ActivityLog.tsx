import type { ActivityItem } from "@/entities/session/model/types";

export function ActivityLog({ items }: { items: ActivityItem[] }) {
  if (!items.length) {
    return <p className="hint">“프로젝트 상태 확인해줘”라고 말해보세요.</p>;
  }

  return (
    <ul className="log">
      {items.map((item) => (
        <li className="log__item" key={item.id}>
          <time className="log__time">{item.time}</time>
          <span>{item.message}</span>
        </li>
      ))}
    </ul>
  );
}
