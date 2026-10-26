#!/bin/zsh
# 도파민 빌드 + 설치 (재실행해도 안전 — 업데이트 겸용)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$HOME/Applications/도파민.app"
LABEL="com.akf0526.dopamine"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

# bundle/의 템플릿을 이 맥의 값으로 채운다: __USER__ → 설치하는 계정, __APP_BIN__ → 설치된 앱 실행 파일.
render() {
  local text
  text="$(<"$1")"
  text="${text//__USER__/$(id -un)}"
  text="${text//__APP_BIN__/$APP/Contents/MacOS/Dopamine}"
  printf '%s\n' "$text"
}

# 명령어 라인 도구가 꼬인 맥용 대체 빌드: swiftc로 직접 컴파일(단일 실행 타깃이라 결과물은 같다).
# 컴파일러와 기본 SDK 버전이 어긋나면("this SDK is not supported by the compiler")
# 설치된 다른 SDK를 최신순으로 시도한다. 그 밖의 오류(코드 오류 등)는 그대로 보여 주고 멈춘다.
build_with_swiftc() {
  local out="$ROOT/.build/release/Dopamine" log="$ROOT/.build/swiftc.log" sdk
  local -a sdks
  mkdir -p "$ROOT/.build/release"
  sdks=("$(xcrun --show-sdk-path 2>/dev/null || true)" /Library/Developer/CommandLineTools/SDKs/MacOSX*.sdk(NOn) /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX*.sdk(NOn))
  for sdk in "${sdks[@]}"; do
    [ -n "$sdk" ] && [ -d "$sdk" ] || continue
    echo "→ swiftc 빌드 시도: ${sdk:t}"
    if xcrun swiftc -O -module-name Dopamine -target "$(uname -m)-apple-macosx13.0" -sdk "$sdk" \
         -o "$out" "$ROOT"/Sources/Dopamine/*.swift 2>"$log"; then
      echo "   성공"
      return 0
    fi
    if ! grep -q "SDK is not supported by the compiler" "$log"; then
      cat "$log"
      return 1
    fi
    echo "   이 SDK는 컴파일러와 버전이 안 맞음 — 다음 SDK"
  done
  echo "❌ 맞는 SDK를 못 찾았어요. 명령어 라인 도구 설치가 끝났는지 확인 후 다시 실행하세요."
  return 1
}

# SwiftPM 빌드가 기본. swift-package 자체가 안 뜨는 맥(dyld: Symbol not found …)에선 대체 빌드.
if ! swift build -c release --package-path "$ROOT"; then
  echo "⚠️ swift build 실패 — swiftc로 직접 빌드합니다."
  build_with_swiftc
fi

mkdir -p "$APP/Contents/MacOS"
cp -f "$ROOT/bundle/Info.plist" "$APP/Contents/Info.plist"
cp -f "$ROOT/.build/release/Dopamine" "$APP/Contents/MacOS/Dopamine"
codesign --force -s - "$APP"

# 뚜껑 닫기 모드(pmset disablesleep)를 암호 없이 켜고 끄기 위한 sudoers 규칙.
# 최초 1회 관리자 암호 창이 뜬다. visudo 검증 통과본만 설치된다.
# 이게 없어도 앱은 동작하지만, 켤 때마다 암호를 묻고 시간 예약 자동 꺼짐이 무인으로 동작하지 못한다.
if [ ! -f /private/etc/sudoers.d/dopamine ]; then
  echo "뚜껑 닫기 모드 설정: 관리자 암호 창이 뜹니다 (최초 1회)."
  # 다운로드·문서·데스크탑 폴더는 macOS 개인정보 보호(TCC) 때문에 관리자 권한 셸도 못 읽는다
  # ("visudo: unable to open … Operation not permitted") → 임시 폴더로 복사해서 넘긴다.
  SUDOERS_SRC="$(mktemp -t dopamine-sudoers)"
  render "$ROOT/bundle/dopamine.sudoers" > "$SUDOERS_SRC"
  /usr/bin/osascript - "$SUDOERS_SRC" <<'APPLESCRIPT' || echo "⚠️ 건너뜀 — 뚜껑 닫기 모드를 켤 때마다 암호를 묻게 됩니다. 다시 시도: install.sh 재실행"
on run argv
  set src to quoted form of (item 1 of argv)
  do shell script "/bin/mkdir -p /private/etc/sudoers.d && /usr/sbin/visudo -cf " & src & " && /usr/bin/install -o root -g wheel -m 0440 " & src & " /private/etc/sudoers.d/dopamine" with administrator privileges with prompt "도파민이 '뚜껑 닫기 모드'용 잠자기 설정 권한을 준비합니다 (최초 1회)."
end run
APPLESCRIPT
  rm -f "$SUDOERS_SRC"
fi

mkdir -p "$HOME/Library/LaunchAgents"
render "$ROOT/bundle/$LABEL.plist" > "$PLIST"
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
for i in {1..25}; do   # 이전 인스턴스 정리가 끝나기 전에 bootstrap하면 EIO
  launchctl print "gui/$(id -u)/$LABEL" >/dev/null 2>&1 || break
  sleep 0.2
done
launchctl bootstrap "gui/$(id -u)" "$PLIST"

echo "OK — 메뉴바에 💊 아이콘이 떴는지 확인하세요."
