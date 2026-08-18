const containerPattern = /^[a-zA-Z0-9][a-zA-Z0-9_.-]{0,127}$/;

export function validateContainerName(value: unknown) {
  if (typeof value !== "string" || !containerPattern.test(value)) {
    throw new Error("올바른 Docker 컨테이너 이름이 필요합니다.");
  }
  return value;
}

export function validateLogLines(value: unknown) {
  if (value === undefined) return 100;
  if (!Number.isInteger(value) || Number(value) < 1 || Number(value) > 1_000) {
    throw new Error("로그 줄 수는 1~1000 사이의 정수여야 합니다.");
  }
  return Number(value);
}
