# Aegis MVP

사용자 승인 아래 개발 프로젝트를 확인하고 명령을 실행하는 개인 음성 에이전트입니다.

## 현재 가능한 것

- Ollama 기반 로컬 AI 대화와 도구 호출
- F5-TTS 기반 개인 참조 음성 응답 재생
- 설정된 프로젝트의 `git status` 조회
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
JARVIS_PROJECT_ROOT=/Users/your-name/projects/soolsool
MAC_AGENT_TOKEN=긴_랜덤_문자열
MAC_AGENT_ALLOWED_APPS=Visual Studio Code,Finder,Google Chrome
```

`ollama serve`와 `npm run mac-agent`를 실행한 다음, 브라우저에서
`http://localhost:3000`을 열고 마이크 권한을 허용합니다. Mac Agent는
`127.0.0.1`에서만 수신하며, 허용 목록에 있는 앱만 실행할 수 있습니다.
두 프로세스는 같은 `.env.local`의 `MAC_AGENT_TOKEN`을 사용해야 합니다.
모든 앱을 허용하려면 `MAC_AGENT_ALLOWED_APPS=*`로 설정할 수 있지만, 앱 실행
승인 절차는 계속 유지됩니다.

개인 음성 응답을 사용하려면 `.aegis/voices/aegis-reference.wav`와 같은 경로의
참조 음성 및 `.aegis/voices/reference.txt`의 정확한 대본, 그리고 F5-TTS 전용
가상환경이 필요합니다.

## 안전 경계

- 사용자가 지정한 프로젝트 하나만 접근합니다.
- 모델이 임의 셸 명령을 만들 수 없습니다.
- 쓰기 가능성이 있는 명령은 명시적인 승인을 요구합니다.
- 삭제, 파일 수정, 외부 전송 도구는 아직 제공하지 않습니다.

## 다음 단계

1. Push-to-Talk용 로컬 STT/TTS 추가
2. 대화 및 승인 기록을 SQLite에 저장
3. 프로젝트별 허용 목록과 명령 정책 추가
4. Mac 메뉴바 앱으로 패키징
5. React Native 리모컨 앱 연결
