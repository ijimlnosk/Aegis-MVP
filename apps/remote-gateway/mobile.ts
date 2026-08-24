export const mobileHTML = `<!doctype html>
<html lang="ko"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Aegis Remote</title><style>
:root{font-family:-apple-system,BlinkMacSystemFont,sans-serif;color:#eef2ff;background:#0b1020}body{margin:0}
main{max-width:720px;margin:auto;min-height:100vh;display:flex;flex-direction:column;padding:18px;box-sizing:border-box}
h1{font-size:20px}.card{background:#171f35;border:1px solid #2b385b;border-radius:14px;padding:14px;margin:8px 0}
#history{flex:1;overflow:auto}.mine{margin-left:12%}.aegis{margin-right:12%}input,button{font:inherit;border-radius:10px;padding:12px}
input{background:#0e1528;color:white;border:1px solid #3b4b73;min-width:0}button{border:0;background:#6574ff;color:white;font-weight:650}
.row{display:flex;gap:8px}.row input{flex:1}.muted{color:#aab3cb;font-size:13px}.danger{background:#b84c62}button:disabled{opacity:.55}
.progress-row{display:flex;align-items:center;gap:10px}.spinner{width:16px;height:16px;border:2px solid #596582;border-top-color:#aeb7ff;border-radius:50%;animation:spin .8s linear infinite;flex:none}
.progress-title{font-weight:700;margin-bottom:10px}.elapsed,.slow,.step{color:#aab3cb;font-size:13px;margin-top:8px}.slow{display:none}.progress-card button{min-height:44px;margin-top:12px}@keyframes spin{to{transform:rotate(360deg)}}
@media(prefers-reduced-motion:reduce){.spinner{animation:none;border-top-color:#596582;background:#aeb7ff}}
</style></head><body><main><h1>Aegis Remote</h1>
<section id="auth" class="card"><p>Master Remote Token은 최초 등록에만 사용되며 저장되지 않습니다.</p><div class="row"><input id="device-name" autocomplete="off" maxlength="64" placeholder="기기 이름 (예: Galaxy Fold)"></div><div class="row"><input id="token" type="password" autocomplete="off" placeholder="Remote token"><button id="connect">이 기기 등록</button></div></section>
<section id="device-status" class="muted" hidden>연결됨 · <span id="current-device">이 기기</span> <button id="disconnect" class="danger">이 기기 연결 해제</button></section>
<div id="state" class="muted">연결되지 않음</div><details class="muted"><summary>Remote UI 진단</summary><div>Gateway: 현재 페이지</div><div>인증: 위 상태 참조</div><div>마지막 오류: <span id="client-error">없음</span></div></details><section id="history"></section>
<form id="composer" class="row" hidden><input id="message" maxlength="4000" placeholder="Aegis에게 요청"><button id="send">전송</button></form>
</main><script type="module" src="/mobile-client.js"></script></body></html>`;
