# Aegis Desktop

브라우저 없이 메뉴바에서 동작하는 macOS 네이티브 Aegis MVP입니다.

```bash
cd apps/macos/AegisDesktop
swift run
```

실행 전 `ollama serve`가 필요합니다. 현재는 macOS 시스템 음성으로 답하며,
다음 단계에서 F5-TTS 개인 보이스를 네이티브 오디오 재생으로 연결합니다.

호출어와 화자 확인 서버는 프로젝트 루트에서 다음과 같이 준비합니다.

```bash
/opt/homebrew/bin/python3.11 -m venv .aegis/f5-tts
.aegis/f5-tts/bin/python -m pip install -r scripts/requirements-voice.txt
```

앱은 읽기 전용 도구를 바로 실행하고, 앱·브라우저·클립보드를 변경하는
작업은 화면 또는 음성으로 사용자의 승인을 받은 뒤 실행합니다.
