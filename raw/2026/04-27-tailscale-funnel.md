# Tailscale Funnel 메모

silva-omnium 자체호스팅 셋업하면서 처음 사용해 본 기능. 정리해둠.

## 핵심

- Tailscale 의 사설 네트워크(tailnet) 안에서만 접근 가능한 서비스를 **공개 인터넷에 노출**할 수 있게 해줌
- 즉, "내 디바이스끼리만 보던 것"을 → "URL 만 알면 누구나 접근 가능"으로 전환
- 별도 도메인·포트포워딩·정적 IP 모두 불필요

## 동작 방식

1. tailscale 가입 + 머신 등록 (한 번)
2. admin 콘솔에서 Funnel 활성화 (한 번)
3. 머신에서 `tailscale funnel --bg <port>` 실행 → 자동 발급되는 `<host>.<tailnet>.ts.net` URL 반환
4. 외부에서 그 URL 접속 → Tailscale 엣지 → 머신 로컬 포트로 프록시

## 제약

- 노출 가능한 포트: 443, 8443, 10000 만 (HTTPS 기본은 443)
- 도메인 변경 불가 (`.ts.net` 서브도메인 고정)
- Tailscale 서비스가 죽으면 같이 죽음

## 보안 고려

- URL 자체는 공개 도메인이므로 추측·스캔 가능
- 서비스 자체에 인증층이 없으면 그대로 누구나 접근 — 반드시 별도 비밀번호·OAuth 같은 인증 필요
- code-server 의 password 인증 + Tailscale Funnel 조합이 흔한 패턴

## 대안

- **Cloudflare Tunnel + 본인 도메인**: 회사 도메인 EDR 회피·Cloudflare Access 연계 가능, 단 도메인 비용
- **VPN-only (Funnel 없이 Tailscale 만)**: 가장 안전, 단 Tailscale 클라이언트 설치 가능 디바이스만 접근

## 참고

- https://tailscale.com/kb/1223/funnel
- 무료 (개인 100 디바이스까지)
