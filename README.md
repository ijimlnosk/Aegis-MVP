# Aegis MVP

사용자 승인 아래 개발 프로젝트를 확인하고 명령을 실행하는 개인 음성 에이전트입니다.

## 현재 가능한 것

- 환경 설정된 Ollama 기반 AI 대화와 도구 호출
- F5-TTS 기반 개인 참조 음성 응답 재생
- registry에 설정된 여러 프로젝트의 `git status` 조회
- 승인 후 `npm run typecheck` 실행
- 브라우저에 실행 기록과 승인 카드 표시
- API 키와 프로젝트 경로를 서버에서만 관리
- 별도 로컬 Mac Agent를 통한 활성 앱 확인·승인 후 앱 실행·승인 후 화면 캡처

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
command bridge, Tailscale이 모두 실행 중일 때만 사용할 수 있습니다. 초기 버전은
정규화된 텍스트만 반환하며 원본 스크린샷은 전송하지 않습니다.

개인 음성 응답을 사용하려면 `.aegis/voices/aegis-reference.wav`와 같은 경로의
참조 음성 및 `.aegis/voices/reference.txt`의 정확한 대본, 그리고 F5-TTS 전용
가상환경이 필요합니다.

## 안전 경계

- registry에 등록된 프로젝트 경로만 접근합니다.
- 모델이 임의 셸 명령을 만들 수 없습니다.
- 쓰기 가능성이 있는 명령은 명시적인 승인을 요구합니다.
- 삭제, 파일 수정, 외부 전송 도구는 아직 제공하지 않습니다.

## 다음 단계

1. Push-to-Talk용 로컬 STT/TTS 추가
2. 대화 및 승인 기록을 SQLite에 저장
3. 프로젝트별 허용 목록과 명령 정책 추가
4. Mac 메뉴바 앱으로 패키징
5. React Native 리모컨 앱 연결
