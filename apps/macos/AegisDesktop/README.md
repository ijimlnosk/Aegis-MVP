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
스크립트만 안전 검증으로 자동 실행합니다. Plan은 명령어나 경로를 전달할 수 없습니다.

개발 세션은 같은 SQLite 파일의 `development_sessions` 테이블에 프로젝트, 시작/종료
시간, 시작/종료 Git snapshot, Aegis 작업, 요약을 저장합니다. 소스·diff·README·커밋
메시지는 항상 신뢰하지 않는 증거 텍스트로만 취급합니다.

배포 점검은 프로젝트의 실제 package scripts와 저장된 validation profile로 계획합니다.
검사 결과는 `passed`, `failed`, `warning`, `skipped`, `unsupported`로 구분하며 누락된
선택 스크립트는 실행 실패로 처리하지 않습니다. 필수 검사 실패만 배포를 차단하고,
도구 실행 자체를 평가하지 못한 경우는 `unknown`으로 보고합니다.

승인은 `ActionRisk`에 따라 결정됩니다. 고정 Git 조회는 `safeRead`, 검증된 package
script 실행은 `safeValidation`이므로 자동 실행합니다. 앱·클립보드 변경은
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
AEGIS_VISION_RESOURCE_PROFILE=balanced
AEGIS_VISION_MAX_LONG_EDGE=1280
AEGIS_VISION_MAX_PIXELS=1500000
AEGIS_VISION_JPEG_QUALITY=0.75
AEGIS_VISION_KEEP_ALIVE_SECONDS=60
AEGIS_VISION_MAX_WINDOWS=2
```

`열려 있는 창들 뭐 있어?`는 screenshot 없이 앱 이름, 창 제목, display, 활성 상태만
보여줍니다. 특정 창 분석은 exact 앱 이름, 명시적으로 설정한 alias, exact 창 제목,
현재 활성 창 순으로만 해석하며 fuzzy matching은 사용하지 않습니다. 추가 alias는
`AEGIS_WINDOW_ALIASES="code=Visual Studio Code"`처럼 설정할 수 있습니다. 여러 창은
기본 최대 2개까지 순차 분석하고 민감한 앱은 목록과 캡처에서 제외합니다.

## 개발 실행

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
