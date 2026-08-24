import assert from "node:assert/strict";
import test from "node:test";
import { terminalCommandContent } from "./failureMessages";

test("completed with messages renders the real backend content", () => {
  assert.equal(terminalCommandContent({ status: "completed", messages: ["PTFriends 개발 상태\nBranch: main"] }),
    "PTFriends 개발 상태\nBranch: main");
});

test("completed with empty messages shows a neutral confirmation, not a failure", () => {
  assert.equal(terminalCommandContent({ status: "completed", messages: [] }), "작업이 완료되었습니다.");
});

test("failed with a typed failureCode shows the real reason, not a generic string", () => {
  assert.equal(terminalCommandContent({ status: "failed", messages: [], failureCode: "serverAgentUnavailable" }),
    "Server Agent가 응답하지 않습니다.");
  assert.equal(terminalCommandContent({ status: "failed", messages: [], failureCode: "desktopUnavailable" }),
    "Mac의 AegisDesktop에 연결할 수 없습니다.");
  assert.equal(terminalCommandContent({ status: "failed", messages: [], failureCode: "validationFailed" }),
    "검증이 실패했습니다.");
});

test("failed with real backend messages always wins over the failureCode fallback", () => {
  assert.equal(terminalCommandContent({ status: "failed", messages: ["오류: PTFriends 프로젝트를 찾을 수 없습니다."],
    failureCode: "projectUnavailable" }), "오류: PTFriends 프로젝트를 찾을 수 없습니다.");
});

test("cancelled with no messages and no code shows a neutral cancellation, not the generic failure text", () => {
  assert.equal(terminalCommandContent({ status: "cancelled", messages: [] }), "작업이 취소되었습니다.");
});

test("failed with no messages and no code falls back to the last-resort generic message only as a final resort", () => {
  assert.equal(terminalCommandContent({ status: "failed", messages: [] }), "작업을 완료하지 못했습니다.");
});
