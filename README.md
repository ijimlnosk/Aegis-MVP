# Aegis MVP

사용자 승인 아래 개발 프로젝트를 확인하고 명령을 실행하는 개인 음성 에이전트입니다.

## 현재 가능한 것

웹 앱(`src`)과 별도로, 주 클라이언트는 macOS 메뉴바 앱
[AegisDesktop](apps/macos/AegisDesktop/README.md)입니다.

- Codex/Ollama 기반 행동 계획과 타입이 정해진 도구 호출 (요청당 최대 5단계)
- 등록 프로젝트 열기(승인 후), Git·package 상태 조회, typecheck/lint/test/build 검증 실행(허용 목록 외 승인 후)
- Codex 읽기 전용 코드 분석, 승인 후 프로젝트 범위 안의 코드 수정과 독립 검증
- 커밋 계획 → 승인 후 커밋 → 별도 승인 후 push
- 화면·창 분석, 접근성 API 기반 UI 제어, 승인 후 카카오톡 메시지 전송
- sol-server의 시스템·Docker·Git 상태 조회와 승인 후 컨테이너 시작·중지·재시작
- 기억·Skill·대화 기록·작업 이력을 `~/Library/Application Support/Aegis/memory.sqlite`에 저장
- `/help`, `/status`, `/projects`, `/perf` slash command
- Tailscale 원격 게이트웨이와 [React Native 리모컨 앱](apps/mobile/README.md)
- 웹 앱: 브라우저 실행 기록·승인 카드, 별도 로컬 Mac Agent, F5-TTS 참조 음성 응답

## 실행

Node.js 20.9 이상이 필요합니다.

```bash
npm install
cp .env.example .env.local
npm run dev
```

`.env.local`에 실제 값을 입력합니다.

```dotenv
OPENAI_API_KEY=sk-proj-...
AEGIS_MVP_PROJECT_ROOT=/Users/your-name/Aegis-MVP
PTFRIENDS_PROJECT_ROOT=/Users/your-name/ptfriendsapp
SOOLSOOL_PROJECT_ROOT=/Users/your-name/soolsool
SOL_SERVER_PROJECT_ROOT=/srv/sol-server
MAC_AGENT_TOKEN=긴_랜덤_문자열
MAC_AGENT_ALLOWED_APPS=Visual Studio Code,Finder,Google Chrome
SERVER_AGENT_TOKEN=별도의_긴_랜덤_문자열
SERVER_AGENT_URL=http://sol-server:4319
```

`ollama serve`와 `npm run mac-agent`를 실행한 다음, 브라우저에서
`http://localhost:3000`을 열고 마이크 권한을 허용합니다. Mac Agent는
`127.0.0.1`에서만 수신하며, 허용 목록에 있는 앱만 실행할 수 있습니다.
두 프로세스는 같은 `.env.local`의 `MAC_AGENT_TOKEN`을 사용해야 합니다.
모든 앱을 허용하려면 `MAC_AGENT_ALLOWED_APPS=*`로 설정할 수 있지만, 앱 실행
승인 절차는 계속 유지됩니다.

Ubuntu에서는 저장소와 환경 설정을 배치한 뒤 `npm run server-agent`를 실행합니다.
다른 호스트에서 접근할 경우 방화벽 또는 사설망으로 4319 포트를 제한하고
`SERVER_AGENT_HOST`를 필요한 인터페이스에만 지정하세요. 시스템·Docker·Git 상태와
로그 조회는 자동 실행되며, 컨테이너 시작·중지·재시작은 화면 승인을 거칩니다.

## Tailscale 원격 제어

원격 게이트웨이는 기본적으로 비활성화되어 있습니다. 32자 이상의 랜덤
`AEGIS_REMOTE_TOKEN`을 설정하고 `AEGIS_REMOTE_HOST`를 Mac의 Tailscale 주소로
명시한 뒤 `npm run remote-gateway`로 실행합니다. public/wildcard bind는 거부되며,
자연어 명령만 loopback AegisDesktop command bridge로 전달됩니다.

휴대폰에서는 `http://<TAILSCALE_IP>:8790/`을 열어 토큰으로 연결합니다. 토큰은 페이지
소스나 영구 브라우저 저장소에 넣지 않습니다. Mac이 깨어 있고 AegisDesktop,
command bridge, Tailscale이 모두 실행 중일 때만 사용할 수 있습니다. 원격 제어가 켜져 있으면
AegisDesktop이 실행되는 동안 Mac의 유휴 잠자기를 막습니다(`AEGIS_REMOTE_KEEP_AWAKE=false`로
끌 수 있음). 외부 모니터 없이 노트북 덮개를 닫으면 여전히 잠듭니다. 화면이 잠겨 있으면
화면 분석·UI 조작·카카오톡 전송은 승인 요청 전에 거절되고, 폰 상단에 "Mac 화면 잠김"이
표시됩니다. 초기 버전은
정규화된 텍스트만 반환하며 원본 스크린샷은 전송하지 않습니다.

폰 명령은 Mac 창과 같은 Aegis 대화로 실행되므로, Mac에서 하던 코딩 결과·커밋 계획 같은
진행 중인 맥락을 폰에서 이어서 요청할 수 있고 폰 대화도 Mac 창에 표시됩니다. Mac에서
작업이 진행 중이거나 승인을 기다리는 동안 들어온 폰 명령은 실행하지 않고 다시 요청하라고
안내합니다.

개인 음성 응답을 사용하려면 `.aegis/voices/aegis-reference.wav`와 같은 경로의
참조 음성 및 `.aegis/voices/reference.txt`의 정확한 대본, 그리고 F5-TTS 전용
가상환경이 필요합니다.

## 안전 경계

- registry 또는 project memory에 등록된 프로젝트 경로만 접근합니다.
- 모델이 임의 셸 명령, 파일 경로, Git refspec을 만들 수 없습니다.
- 읽기 전용 조회와 창 포커스·스크롤 같은 탐색은 자동 실행됩니다. typecheck/lint/test/build
  검증은 `AEGIS_AUTO_VALIDATION_PROJECTS`에 등록한 프로젝트만 자동 실행합니다. 앱 실행, UI 입력, 코드 수정, 커밋, push, 메시지 전송,
  컨테이너 변경은 단계마다 명시적인 승인을 요구합니다.
- 코드 수정은 승인 시점의 Git baseline과 변경 파일 수 상한 안에서만 진행되고,
  typecheck/lint/test/build로 다시 검증합니다.
- merge, rebase, force push, 브랜치 삭제, 배포, 파일 삭제 도구는 제공하지 않습니다.

## 다음 단계

1. Push-to-Talk용 로컬 STT/TTS를 AegisDesktop에서 다시 활성화
2. 프로젝트별 명령 정책을 검증 외 작업으로 확장
