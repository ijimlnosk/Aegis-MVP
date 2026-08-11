import type { ApprovalView } from "@/entities/session/model/types";

interface Props {
  approval: ApprovalView;
  onApprove: () => void;
  onReject: () => void;
}

export function ApprovalCard({ approval, onApprove, onReject }: Props) {
  return (
    <article className="approval">
      <h2>{approval.title}</h2>
      <p>{approval.detail}</p>
      <div className="approval__actions">
        <button className="button" onClick={onReject}>거절</button>
        <button className="button button--primary" onClick={onApprove}>실행 승인</button>
      </div>
    </article>
  );
}
