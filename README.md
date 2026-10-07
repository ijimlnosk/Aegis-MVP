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

### 폰 푸시 알림

`AEGIS_NOTIFY_SERVER`와 `AEGIS_NOTIFY_TOPIC`을 설정하면 AegisDesktop이 직접 운영하는
ntfy 서버로 알림을 보냅니다. 폰에서 보낸 작업이 승인을 기다릴 때, 폰 작업이
`AEGIS_NOTIFY_MIN_SECONDS`(기본 20초)보다 오래 걸려 끝났을 때, 서버·프로젝트 경고가
생겼을 때 알림이 갑니다. 알림에는 작업 이름과 프로젝트만 들어가며 요청 원문, 메시지
본문, 명령 출력, 근거는 넣지 않습니다. topic은 구독 비밀값 역할을 하므로 16자 이상의
랜덤 문자열을 쓰고, 공개 ntfy.sh 대신 Tailscale 안의 서버를 권장합니다.

sol-server 예시:

```bash
# 모든 인터페이스가 아니라 sol-server의 Tailscale 주소에만 bind합니다.
docker run -d --name ntfy --restart unless-stopped -p <TAILSCALE_IP>:8080:80 \
  -v ntfy-cache:/var/cache/ntfy binwiederhier/ntfy serve \
  --cache-file /var/cache/ntfy/cache.db --base-url http://<TAILSCALE_IP>:8080
```

폰에 ntfy 앱을 설치하고 서버 `http://<TAILSCALE_IP>:8080`에서 같은 topic을 구독합니다.
iOS 앱은 자체 서버 알림을 받으려면 서버에 `upstream-base-url` 설정이 추가로 필요합니다.

### 예약 작업

"매일 아침 9시에 PTFriends 상태 알려줘", "평일 18:30에 sol-server 상태 보여줘"처럼 말하면
매일(또는 평일) 그 시각에 AegisDesktop이 요청을 실행하고 결과를 폰 알림으로 보냅니다.
"예약 목록 보여줘", "예약 2번 삭제"로 관리합니다. 예약 실행은 승인이 필요한 단계를
하지 않고 거절하므로 자리를 비운 사이 커밋·전송·컨테이너 변경이 일어나지 않습니다. 예약
결과 알림은 요청한 결과를 전달하는 것이 목적이라 비밀값을 가린 결과 앞부분(최대 400자)을
포함합니다. Aegis가 바쁘거나 Mac이 잠들어 1시간 넘게 늦어지면 그날 실행은 건너뜁니다.

한 번만 필요한 알림은 "30분 뒤에 배포 확인하라고 알려줘"(메모를 알림으로 전달),
"오후 3시에 PTFriends 상태 알려줘"(그 시각에 한 번 실행하고 결과 전달)처럼 말합니다.
"…라고 알려줘"는 메모로, 그 밖의 내용은 실행할 요청으로 해석합니다. 메모 알림은 늦어져도
몇 분 늦었는지와 함께 전달하고, 요청 실행은 예약과 같이 승인 단계를 하지 않습니다.
"리마인더 목록 보여줘", "리마인더 1번 취소"로 관리합니다.
예약은 `~/Library/Application Support/Aegis/schedules.json`에 저장됩니다.

### 감시 알림

"PTFriends CI 끝나면 알려줘", "sol-server 복구되면 알려줘"라고 하면 AegisDesktop이 1분마다
읽기 전용으로 확인하다가 조건이 충족되면 폰 알림을 보냅니다. 요청할 때 이미 충족돼 있으면
바로 답하고, 6시간이 지나면 감시를 종료합니다. "감시 목록 보여줘", "감시 1번 취소"로
관리합니다. CI 감시에는 로그인된 GitHub CLI(`gh`)가 필요합니다.

### 코드 검색과 파일 보기

"PTFriends에서 login 찾아줘"는 등록 프로젝트에서 git이 추적하는 파일만 `git grep`으로 찾아
최대 30곳을 보여주고, "SoolSool README 보여줘"·"PTFriends src/app/page.tsx 보여줘"는 추적 중인
파일을 최대 200줄까지 보여줍니다. 이름이 여러 곳에 있으면 최상위 파일을 고르고, 그래도
애매하면 후보 경로를 보여줍니다. `.env*`, 키·인증서, `secret`·`credential`이 들어간 파일은
검색·조회에서 빠지며 결과의 비밀값처럼 보이는 문자열은 가려집니다. "개선할 부분 찾아줘"처럼
판단이 필요한 요청은 계속 Codex 분석으로 갑니다.

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
