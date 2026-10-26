# 도파민 — 뚜껑을 닫아도 맥이 안 잠드는 메뉴바 토글

메뉴바 💊 아이콘을 **누르면 켜지고, 다시 누르면 꺼짐**. 켜져 있는 동안은 **뚜껑을 닫아도** 맥이 잠들지 않음. 터미널에 긴 작업(예: claude)을 걸어 두고 맥북을 접어도 계속 돌아감.

## 동작
- **왼클릭**: 토글. 켜짐 = 채워진 알약(💊 fill), 꺼짐 = 빈 알약(outline).
- **오른클릭(또는 ⌃클릭)**: 상태 · 켜기/끄기 · **1시간만/3시간만 켜기**(끝나면 자동 꺼짐) · **로그인하면 자동 켜기(허브용)** · 종료.
- **로그인하면 자동 켜기 (허브용)**: 체크하면 바로 켜지고, 이후 로그인할 때마다(재시동 포함) 암호 없이 자동으로 켜짐. 맥마다 따로 저장(`defaults read com.akf0526.dopamine autoOnAtLogin`) — 집에 늘 켜 두는 맥 같은 허브용 맥에서만 체크. 체크 해제는 다음 로그인부터 적용(지금 상태는 그대로, 끄기는 클릭). 재시동 후 로그인 화면에서 멈춰 있으면 로그인 전까지 앱이 안 뜨므로, 그때는 뚜껑 열고 로그인 1회.
- **켜짐** = ① `pmset -a disablesleep 1` — 뚜껑을 닫아도 시스템이 안 잠듦(root 필요) + ② `caffeinate -dis` — 뚜껑 열어 둔 동안 화면·유휴 잠자기 방지.
- **전원 무관**: 충전기 없이 **배터리로도 그대로 유지**. `SleepDisabled`는 시스템 전역 플래그라서(충전기가 필요한 건 애플 공식 closed-display 모드 쪽). 배터리는 계속 줄고, 잔량이 바닥나면 그때는 잠듦.
- **터미널에서**: `pkill -USR1 -x Dopamine` = 토글, `pkill -USR2 -x Dopamine` = 1시간만 켜기.

## 안전장치 (💊 채워짐일 때만 뚜껑 닫아도 안 잠듦, 그 외엔 평소 정책)
- 끄기·종료·시간 만료 때 `disablesleep 0`으로 원복. `launchctl bootout`·로그아웃의 SIGTERM도 잡아서 원복.
- 크래시 등으로 `disablesleep 1`이 남아 있으면 **다음 실행(로그인) 때 자동 청소**. 앱은 항상 꺼진 상태로 시작(‘로그인하면 자동 켜기’를 체크한 맥만 예외 — 켜진 채로 시작).
- caffeinate는 `-w <앱 pid>`로 앱과 운명 공동체 — 앱이 죽으면 같이 종료.
- 켜기에 실패하면(암호 취소 등) 어중간한 상태 없이 완전히 꺼진 상태 유지.
- ⚠️ **켠 채로 가방에 넣지 말 것** (발열·배터리). 충전기는 필수가 아니고 배터리 절약용 권장.

## 권한 (sudoers)
`pmset disablesleep`은 root가 필요해서, 설치 때 관리자 암호 **1회**로 `/etc/sudoers.d/dopamine`을 설치. 내용은 `bundle/dopamine.sudoers`(설치하는 계정 이름이 채워짐)이고, **정확히 `pmset -a disablesleep 1`·`0` 두 명령만** 암호 없이 허용. 덕분에 토글이 조용히 동작하고 시간 예약 자동 꺼짐도 무인으로 됨. 규칙이 없으면 켜고 끌 때마다 암호 창이 뜸.

## 요구 사항
- macOS 13 이상
- Xcode 명령어 라인 도구(`xcode-select --install`)
- 관리자 계정(최초 설치 때 암호 1회)

## 설치 (업데이트도 동일)
```sh
git clone https://github.com/h6dr-git/dopamine
cd dopamine
./install.sh
```
설치물: `~/Applications/도파민.app` + `~/Library/LaunchAgents/com.akf0526.dopamine.plist`(로그인 때 자동 시작, 꺼진 상태로) + `/etc/sudoers.d/dopamine`(최초 1회). 업데이트는 `git pull` 후 `./install.sh` 다시 실행. `swift build`가 안 되는 맥에서는 `swiftc`로 직접 빌드하는 대체 경로를 자동으로 시도.

## 구조
- `Sources/Dopamine/` — 메뉴바 앱(AppKit, 서드파티 의존성 0). `main`/`AppController`/`Awake`(caffeinate)/`LidMode`(pmset).
- `bundle/` — 앱 Info.plist + LaunchAgent plist + sudoers 템플릿.
- 메뉴바 구조는 [claude-pace](https://github.com/h6dr-git/claude-pace)에서 재사용.

## 제거
```sh
launchctl bootout "gui/$(id -u)/com.akf0526.dopamine"
rm -rf "$HOME/Applications/도파민.app" ~/Library/LaunchAgents/com.akf0526.dopamine.plist
sudo rm -f /etc/sudoers.d/dopamine
sudo pmset -a disablesleep 0   # 켜진 채였다면 원복
```

## 만든 방식
기능·안전장치 결정과 실사용 검증은 직접, 코드는 AI 코딩 도구(Claude Code)로 작성.

## 라이선스
[MIT](LICENSE)
