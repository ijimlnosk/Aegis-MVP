# Aegis Desktop

브라우저 없이 메뉴바에서 동작하는 macOS 네이티브 Aegis MVP입니다.
향후 사용할 마이크 권한 설명이 필요하므로 raw SwiftPM executable인 `swift run`이
아니라 `Info.plist`가 포함된 `.app` 번들로 실행합니다.

현재 단계에서는 음성 입력·STT·TTS가 런타임에서 모두 비활성화되어 있으며,
텍스트 채팅만 사용합니다. 대화와 도구 결과, 오류, 승인 요청은 앱 세션 동안
시간순으로 유지됩니다.

명시적으로 가르친 사실·선호·별칭·프로젝트와 실행된 도구 이력은
`~/Library/Application Support/Aegis/memory.sqlite`에 저장됩니다. 일반 대화는
자동으로 영구 기억하지 않으며, planning 전에는 현재 요청과 관련된 기억만 최대
8개까지 신뢰할 수 없는 참고 데이터로 전달됩니다.

한 요청에는 최대 5개의 순차 실행 단계를 만들 수 있습니다. 각 단계는 진행 상황을
채팅에 남기며, 위험 작업에서는 실행을 멈추고 개별 승인을 요청합니다. 승인 후 같은
단계부터 재개하고, 거절이나 실패 뒤에는 독립 조회만 계속하며 앞 단계 성공이 필요한
단계는 건너뜁니다.

학습된 개인 Skill도 같은 SQLite 파일의 별도 테이블에 저장됩니다. 동일한 성공
시퀀스가 기본 3회 반복되면 채팅에서 저장을 제안하며, 승인 전에는 저장하지 않습니다.
Skill은 기존 typed action을 최대 5개까지 조합할 수 있고 실행 전에 항상 다시
검증됩니다. 위험 단계의 승인은 Skill을 실행할 때마다 개별적으로 필요합니다.

Context observer는 기본 60초마다 Mac, 기억된 프로젝트, sol-server의 신뢰된
읽기 전용 상태를 수집하고 최근 snapshot 20개만 SQLite에 보관합니다. 임계치 교차와
상태 변화를 결정적으로 비교하며 같은 condition은 회복 또는 severity 상승 전까지
다시 알리지 않습니다. Docker 중지 시 마지막 50줄 로그만 고정 endpoint로 조사할
수 있으며 컨테이너를 자동으로 시작하거나 재시작하지 않습니다.

관찰 설정은 환경변수로 조절할 수 있습니다.

```bash
AEGIS_CONTEXT_OBSERVATION_ENABLED=false
AEGIS_OBSERVATION_INTERVAL_SECONDS=60
AEGIS_PROACTIVE_COOLDOWN_SECONDS=900
AEGIS_CLIPBOARD_METADATA_ENABLED=false
AEGIS_ALLOWED_CODE_EDITORS="Visual Studio Code,Cursor,Xcode"
```

Clipboard는 기본적으로 전혀 관찰하지 않습니다. 명시적으로 metadata 수집을 켜도
내용은 저장하지 않고 텍스트 존재 여부와 글자 수만 snapshot에 포함합니다.

프로젝트와 Docker 컨테이너는 별도 entity로 해석됩니다. 등록 프로젝트와 별칭은
Docker mutation보다 먼저 프로젝트 열기·상태 조회로 해석하며, 컨테이너 변경은
Server Agent의 최신 `docker ps -a` inventory와 대소문자까지 정확히 일치해야 합니다.
Inventory에 없는 이름이나 typo는 승인 UI를 띄우거나 mutation endpoint를 호출하지
않습니다. Learned Skill의 Docker 단계도 승인 전과 실제 실행 직전에 같은 검증을
다시 수행합니다.

프로젝트 열기는 별도 `open_project` action으로 처리합니다. Plan에는 프로젝트 이름과
허용된 에디터만 포함되고 경로는 포함되지 않습니다. 실행 시 registry 또는 project
memory에서 경로를 다시 조회해 실제 디렉터리인지 확인한 뒤 `/usr/bin/open`에
`["-a", editor, validatedPath]` 인자를 직접 전달합니다. 기본 에디터는 Visual Studio
Code이며 `default_code_editor` preference 또는 현재 요청의 Cursor/Xcode 지정이 이를
덮어씁니다.

개발 프로젝트 조회도 같은 registry/project memory 경계를 사용합니다. Git 조회는
고정된 `/usr/bin/git` 인자만 사용하고, package 검증은 lockfile로 npm/pnpm/yarn을
판별한 뒤 `package.json`에 실제로 존재하는 `typecheck`, `test`, `lint`, `build`
스크립트만 실행합니다. Plan은 명령어나 경로를 전달할 수 없습니다. 이 스크립트는
프로젝트 자체 코드이므로 `AEGIS_AUTO_VALIDATION_PROJECTS`(쉼표 구분, 대소문자 무시)에
등록한 프로젝트만 자동 실행하고, 나머지는 실행할 때마다 승인을 받습니다. 값은 앱 시작 시
한 번 읽으므로 바꾼 뒤에는 앱을 다시 시작해야 합니다.

개발 세션은 같은 SQLite 파일의 `development_sessions` 테이블에 프로젝트, 시작/종료
시간, 시작/종료 Git snapshot, Aegis 작업, 요약을 저장합니다. 소스·diff·README·커밋
메시지는 항상 신뢰하지 않는 증거 텍스트로만 취급합니다.

배포 점검은 프로젝트의 실제 package scripts와 저장된 validation profile로 계획합니다.
검사 결과는 `passed`, `failed`, `warning`, `skipped`, `unsupported`로 구분하며 누락된
선택 스크립트는 실행 실패로 처리하지 않습니다. 필수 검사 실패만 배포를 차단하고,
도구 실행 자체를 평가하지 못한 경우는 `unknown`으로 보고합니다.

승인은 `ActionRisk`에 따라 결정됩니다. 고정 Git 조회는 `safeRead`, 검증된 package
script 실행은 `safeValidation`이지만 허용 목록에 있는 프로젝트만 자동 실행합니다. 앱·클립보드 변경은
`localMutation`, Docker·메시지 작업은 `remoteMutation`으로 계속 명시적 승인을
요구합니다. 임의 명령, git push, 배포 action은 제공하지 않습니다.

화면 인식은 명시적인 채팅 요청에서만 ScreenCaptureKit으로 현재 창 또는 활성 모니터를
캡처합니다. 주기적인 screenshot은 없으며 PNG는 임시 디렉터리에 한 번만 생성되고
분석 직후 삭제됩니다. 화면 텍스트와 분석 결과는 Memory/Skill에 저장하지 않고 실행
이력에는 앱 이름 수준의 비민감 완료 정보만 남깁니다.

처음 사용할 때 시스템 설정 → 개인정보 보호 및 보안 → 화면 및 시스템 오디오 녹음에서
Aegis 권한을 켜야 합니다. 앱은 권한 요청을 반복하지 않으며 권한이 없으면 채팅에 상태를
알립니다. vision provider는 `AEGIS_VISION_MODEL`로 지정하며 기본값은
`qwen2.5vl:7b`입니다. 화면 속 명령·웹페이지·소스·터미널 텍스트는 모두
`<untrusted_screen_data>`로 취급되어 action을 생성하지 않습니다.

Vision 분석 timeout과 입력 이미지 예산은 필요할 때 조절할 수 있습니다. 기본
resource profile은 `balanced`이며 1280px longest edge, 150만 pixel, JPEG quality
0.75를 사용합니다. 작은 이미지는 확대하지 않습니다. memory pressure가 warning이면
자동으로 `lowMemory` profile을 사용하고 critical이면 로컬 Vision을 시작하지 않습니다.

```bash
AEGIS_VISION_TIMEOUT_SECONDS=120
AEGIS_OLLAMA_URL=http://<TAILSCALE_IP>:11434
AEGIS_VISION_OLLAMA_URL=http://<TAILSCALE_IP>:11434
AEGIS_VISION_LOCAL_FALLBACK=false
AEGIS_OLLAMA_REMOTE_TIMEOUT_SECONDS=300
AEGIS_VISION_REMOTE_TIMEOUT_SECONDS=300
AEGIS_VISION_RESOURCE_PROFILE=balanced
AEGIS_VISION_MAX_LONG_EDGE=1280
AEGIS_VISION_MAX_PIXELS=1500000
AEGIS_VISION_JPEG_QUALITY=0.75
AEGIS_VISION_KEEP_ALIVE_SECONDS=60
AEGIS_VISION_MAX_WINDOWS=2
```

### sol-server 원격 AI

일반 대화와 planner는 `AEGIS_OLLAMA_URL`, Screen Awareness는
`AEGIS_VISION_OLLAMA_URL`을 사용합니다. 두 URL은 독립적으로 설정하며 같은 서버를
가리킬 수 있습니다. 둘 다 설정하지 않으면 로컬 Ollama로 자동 fallback하지 않습니다.

```dotenv
AEGIS_OLLAMA_URL=http://<TAILSCALE_IP>:11434
AEGIS_VISION_OLLAMA_URL=http://<TAILSCALE_IP>:11434
OLLAMA_MODEL=qwen2.5vl:3b
AEGIS_VISION_MODEL=qwen2.5vl:3b
AEGIS_VISION_LOCAL_FALLBACK=false
AEGIS_OLLAMA_REMOTE_TIMEOUT_SECONDS=300
AEGIS_VISION_REMOTE_TIMEOUT_SECONDS=300
```

원격 Ollama는 Tailscale 또는 명시적으로 제한한 로컬 LAN에서만 접근하게 구성하세요.
향후 인증 reverse proxy를 의도적으로 추가할 수도 있습니다. 네트워크 경계 없이
공용 인터페이스의 `0.0.0.0:11434`를 인터넷에 노출하지 마세요. Aegis는 원격으로
보내기 전에 Mac에서 민감한 창을 차단하고 이미지를 축소해 JPEG 임시 파일로 만들며,
분석 뒤 삭제합니다. sol-server에 이미지 저장이나 base64 로깅을 요청하지 않습니다.

sol-server에서는 실제 주소를 저장소에 기록하지 말고 Ollama를 그 호스트의 Tailscale
주소에만 바인딩한 뒤 작은 Vision 모델을 준비합니다.

```bash
OLLAMA_HOST=<TAILSCALE_IP>:11434 ollama serve
ollama pull qwen2.5vl:3b
```

호스트 방화벽과 Tailscale ACL에서도 Mac만 11434 포트에 접근하도록 제한하세요.
기존 Aegis Server Agent의 포트, 인증 토큰, endpoint는 이 설정과 무관하며 변경하지
않습니다.

현재 개발 구성에서는 로컬 fallback을 끕니다. planner와 Vision 요청은 공유 coordinator가
직렬화하여 동시에 하나의 고비용 Ollama generation만 실행합니다.

`열려 있는 창들 뭐 있어?`는 screenshot 없이 앱 이름, 창 제목, display, 활성 상태만
보여줍니다. 특정 창 분석은 exact 앱 이름, 명시적으로 설정한 alias, exact 창 제목,
현재 활성 창 순으로만 해석하며 fuzzy matching은 사용하지 않습니다. 추가 alias는
`AEGIS_WINDOW_ALIASES="code=Visual Studio Code"`처럼 설정할 수 있습니다. 여러 창은
기본 최대 2개까지 순차 분석하고 민감한 앱은 목록과 캡처에서 제외합니다.

## 개발 실행

## Phase 8 UI 제어

UI 제어는 macOS Accessibility API로만 대상을 탐색하고 실행합니다. 좌표 클릭, 임의
키 코드, AppleScript, shell 실행은 capability로 제공하지 않습니다. 처음 사용할 때
시스템 설정 → 개인정보 보호 및 보안 → 손쉬운 사용에서 AegisDesktop을 허용하세요.
권한이 없거나 취소되면 앱은 계속 실행되고 deterministic 읽기 도구는 유지됩니다.

앱과 창은 `KnownApplicationRegistry`, bundle identifier, ScreenCaptureKit metadata로
다시 해석합니다. Accessibility tree는 최대 깊이 5, 요소 40개, 텍스트 160자로 제한하며
메모리에 저장하지 않습니다. 텍스트 입력, 버튼 실행, 메뉴 선택, 창 닫기는 승인을
요구합니다. 활성화, 창 focus, UI 목록, 고정된 navigation shortcut은 자동 실행됩니다.
암호·보안 필드와 generic UI 메시지 전송은 차단됩니다.

지원되는 VSCode workflow:

```text
PTFriends VSCode 창에서 build.gradle 열어줘
→ trusted window focus
→ allowlisted Quick Open
→ 텍스트 입력 승인
→ build.gradle 입력 및 confirm
→ trusted window title 검증
```

`UI 제어 상태 보여줘`는 Accessibility 권한, 활성 앱/창, coordinator 상태와 adapter
목록을 보여줍니다. `현재 VSCode 창에서 조작 가능한 UI 보여줘`는 bounded semantic
목록만 표시하며 raw Accessibility tree나 secure value를 출력하지 않습니다.

프로젝트 루트에서 다음 명령을 실행합니다.

```bash
apps/macos/AegisDesktop/Scripts/run-app.sh
```

스크립트는 debug executable을 빌드하고
`apps/macos/AegisDesktop/.build/AegisDesktop.app`을 조립한 다음 구성된 Apple
Development 인증서로 서명해 `open`으로 실행합니다. 개발 전에 인증서 SHA-1을
셸 환경에만 설정하세요.

```bash
export AEGIS_CODESIGN_IDENTITY=<certificate-sha1>
```

값이 없거나 keychain의 코드 서명 identity와 일치하지 않으면 ad-hoc 서명으로
대체하지 않고 명시적으로 실패합니다. 인증서와 private key는 저장소에 저장하지
않습니다. 현재 비활성화된 음성 기능을 다시 활성화하기 전까지는
마이크나 음성 인식 권한을 요청하지 않습니다.

release 번들을 만들거나 실행하려면 다음을 사용합니다.

```bash
apps/macos/AegisDesktop/Scripts/build-app.sh release
apps/macos/AegisDesktop/Scripts/run-app.sh release
```

실행 전 `ollama serve`가 필요합니다. 현재 응답은 텍스트 채팅에만 표시됩니다.

## Phase 9 Safe Coding Agent

등록된 프로젝트의 코드 리뷰는 Codex `read-only` sandbox에서 승인 없이 실행됩니다. 소스 수정은
`workspace-write`로 제한되고 Codex 실행 전에 Aegis 승인 카드가 표시됩니다. Aegis는 Git 전후
상태와 지원되는 typecheck/lint/test/build 결과를 독립적으로 확인하며 commit이나 push는 하지 않습니다.

```bash
AEGIS_CODING_TASK_TIMEOUT_SECONDS=900
AEGIS_AUTONOMOUS_MAX_CHANGED_FILES=5
AEGIS_AUTONOMOUS_MAX_TASKS_PER_REQUEST=1
AEGIS_AUTONOMOUS_REPAIR_ATTEMPTS=1

Phase 10 autonomous development is user-triggered only. It selects one small task in a
trusted project, presents the candidate without writing, and pauses for approval before
Codex workspace-write. Git attribution and configured validation determine success. A
related validation failure may trigger at most one repair within the same file limit;
commit, push, deploy, server mutation, and proactive coding remain disabled.
AEGIS_CODING_AGENT_PROVIDER=codex
AEGIS_CODING_AGENT_FALLBACK=none
AEGIS_CODING_MAX_CHANGED_FILES=20
```

기존 dirty 파일은 작업 변경으로 귀속하거나 자동 롤백하지 않습니다. 롤백은 기존 변경과 분리되고
작업 이후 상태가 바뀌지 않은 tracked 파일에만 허용됩니다.

## Phase 12 Safe Git Workflow

커밋 계획은 등록된 프로젝트의 Git snapshot과 bounded diff metadata만 읽어 논리 그룹을
제안합니다. 계획 단계에서는 stage하지 않습니다. 커밋 승인은 계획 ID, branch, 정확한 파일
집합에 묶이며 승인 뒤 snapshot이 달라지면 무효화됩니다. 실행은 그룹별 `git add -- <files>`와
고정된 commit 인자만 사용하고 기존 staged 변경, 민감 파일, 대용량/바이너리 파일을 자동으로
포함하지 않습니다.

push는 커밋과 별도의 remote-mutation 승인이 필요합니다. 현재 branch의 일반 push만 지원하며
force/tag/ref 삭제와 main/master/production/release 직접 push는 차단됩니다. CI와 PR은 설치된
GitHub CLI 인증을 이용한 읽기 전용 상태 조회만 지원하고 PR 생성·merge·deploy는 지원하지 않습니다.
Remote Gateway 요청도 같은 AegisDesktop 계획과 승인 상태를 사용합니다.

## Server Agent 설정

개발 번들은 프로젝트 루트 `.env.local`의 `SERVER_AGENT_URL`과
`SERVER_AGENT_TOKEN`을 읽습니다. 토큰은 앱 소스나 번들에 복사되지 않습니다.
설치된 앱에서는 환경변수 또는 `~/.config/aegis/server-agent.json`을 사용합니다.

```json
{
  "url": "http://100.74.88.48:8787",
  "token": "your-server-agent-token"
}
```

설정 파일에는 서버 토큰이 있으므로 `chmod 600` 권한을 권장합니다. 서버 상태,
Docker 목록·로그와 프로젝트 상태는 바로 조회합니다. 컨테이너 시작·중지·재시작은
기존 실행 승인 카드에서 승인된 뒤에만 고정된 Server Agent endpoint를 호출합니다.

호출어와 화자 확인 서버는 프로젝트 루트에서 다음과 같이 준비합니다.

```bash
/opt/homebrew/bin/python3.11 -m venv .aegis/f5-tts
.aegis/f5-tts/bin/python -m pip install -r scripts/requirements-voice.txt
```

앱은 읽기 전용 도구를 바로 실행하고, 앱·브라우저·클립보드를 변경하는 작업은
화면 또는 음성으로 사용자의 승인을 받은 뒤 실행합니다.

권한을 초기화해 최초 실행을 다시 시험하려면 다음 명령을 사용합니다.

```bash
tccutil reset Microphone com.aegis.local
tccutil reset SpeechRecognition com.aegis.local
```
