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

## 개발 실행

프로젝트 루트에서 다음 명령을 실행합니다.

```bash
apps/macos/AegisDesktop/Scripts/run-app.sh
```

스크립트는 debug executable을 빌드하고
`apps/macos/AegisDesktop/.build/AegisDesktop.app`을 조립한 다음 ad-hoc 서명해
`open`으로 실행합니다. 현재 비활성화된 음성 기능을 다시 활성화하기 전까지는
마이크나 음성 인식 권한을 요청하지 않습니다.

release 번들을 만들거나 실행하려면 다음을 사용합니다.

```bash
apps/macos/AegisDesktop/Scripts/build-app.sh release
apps/macos/AegisDesktop/Scripts/run-app.sh release
```

실행 전 `ollama serve`가 필요합니다. 현재는 macOS 시스템 음성으로 답합니다.

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
