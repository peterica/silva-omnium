# Tailscale + Funnel 설정 가이드

`install-mac-mini.sh` 가 brew 로 tailscale 을 설치한 뒤 이 단계를 수동으로 한다.

## 1. 가입 + 머신 등록

```bash
# 트레이 GUI 로 로그인 (Google / GitHub / 이메일)
open -a Tailscale

# CLI 로 머신 등록 (브라우저 열림 → 승인)
sudo tailscale up
```

확인:

```bash
tailscale status
# 머신 이름과 100.x.x.x IP 가 출력되면 OK
```

## 2. Funnel 활성화 (필요 시 admin 콘솔에서 권한 켜기)

기본은 비활성. https://login.tailscale.com/admin/dns 의 "Funnel" 섹션에서 본인 tailnet 활성화.

## 3. Caddy(:80) 를 Funnel(:443) 로 노출

```bash
sudo tailscale serve --bg --https=443 --set-path / http://localhost:80
```

출력에 다음과 같은 URL 표시:

```
Available within your tailnet:
  https://<host>.<tailnet>.ts.net/

Available on the public internet:
  https://<host>.<tailnet>.ts.net/    (Funnel)
```

## 4. 검증

- 같은 머신 브라우저: `http://localhost/` → wiki 보임
- 같은 머신 브라우저: `http://localhost/edit/` → code-server 로그인 화면
- 다른 디바이스(Tailscale 안): 위 ts.net URL 로 동일 결과
- 회사 노트북(Tailscale 없음): 위 ts.net URL → public Funnel 통해 접근 → code-server 비밀번호 필요

## 5. 끄기 / 변경

```bash
sudo tailscale serve status            # 현재 노출 상태
sudo tailscale serve reset             # 전체 해제
sudo tailscale funnel --bg off         # Funnel 만 끄기 (사설 접근은 유지)
```

## 트러블슈팅

- **502 Bad Gateway**: Caddy 가 :80 에 안 떠 있다. `launchctl list | grep silva-omnium` 으로 확인. `tail -f /var/log/silva-omnium/caddy.err`
- **/edit 만 안 됨**: code-server 가 :8080 에 안 떠 있다. `tail -f /var/log/silva-omnium/code-server.err`
- **로그인 후 흰 화면**: code-server base path. Caddy 의 reverse_proxy 가 `/edit/*` 의 prefix 를 그대로 전달하는지 확인. 필요 시 Caddyfile 에 `handle_path /edit/*` 로 변경 (prefix 제거).
- **Funnel URL 응답이 느린 첫 접속**: Tailscale 자체 엣지를 통과 — 첫 번째 접속만 약간 느릴 수 있음, 이후 캐시.
