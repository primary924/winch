# Winch

[![CI](https://github.com/primary924/winch/actions/workflows/ci.yml/badge.svg)](https://github.com/primary924/winch/actions/workflows/ci.yml)

macOS에서 윈도우 창의 타이틀바를 일일이 잡지 않고도 창을 옮길 수 있게 해주는 메뉴바 유틸리티입니다. 사전에 지정한 수정키를 누른 상태에서 마우스를 움직이면 활성 창이 커서를 따라 이동합니다.

X11/Linux의 `Alt+드래그` 패턴을 macOS에 가져온 것입니다.

## 요구 사항

- macOS 13 Ventura 이상

## 다운로드 및 설치

[Releases 페이지](https://github.com/primary924/winch/releases)에서 `Winch-x.y.z.dmg`를 받습니다.

1. DMG를 더블클릭해 마운트
2. `Winch.app`을 `Applications` 폴더로 드래그

### 첫 실행 (미서명 빌드 안내)

Winch는 아직 Apple Developer Program에 등록되어 있지 않아 코드 서명이 없습니다. 처음 실행할 때 macOS Gatekeeper가 차단할 수 있습니다.

1. Finder에서 `Applications` → `Winch.app`을 **우클릭 → 열기** (더블클릭이 아니라 우클릭→열기)
2. "신원 미확인 개발자" 경고가 뜨면 **열기** 클릭
3. 한 번 허용한 뒤로는 더블클릭으로 정상 실행됩니다

대안 (터미널 한 줄로 해제):

```bash
xattr -dr com.apple.quarantine /Applications/Winch.app
```

### Accessibility 권한 부여

Winch가 창을 옮기려면 **손쉬운 사용(Accessibility) 권한**이 필요합니다. 처음 실행하면 시스템이 자동으로 권한을 요청합니다.

1. 시스템 설정 → 개인정보 보호 및 보안 → 손쉬운 사용
2. 목록에서 `Winch`를 켭니다
3. 메뉴바 아이콘이 `⚠W`(권한 필요) → `●W`(활성)으로 바뀌면 준비 완료

## 사용법

1. 옮기고 싶은 창을 클릭해 포커스
2. `Ctrl + Option`을 누른 상태로 마우스/트랙패드 이동
3. 활성 창이 커서를 따라 이동
4. 키에서 손을 떼면 멈춤

## 환경설정

메뉴바의 `●W` 아이콘을 클릭 → **Preferences…**

- **Trigger**: 사용할 수정키 조합 선택 (Cmd / Option / Ctrl / Shift / fn 중 하나 이상). 기본값은 `Ctrl + Option`.
- **Startup**: 로그인 시 자동 시작

메뉴바에서 바로 가능한 동작:

- **Pause / Resume**: 일시정지/재개 (메뉴바 아이콘 `⏸W`로 변경)
- **Launch at login**: 로그인 시 자동 시작 토글
- **About Winch**: 버전 정보
- **Quit Winch**: 종료

## 상태 아이콘

| 표시 | 의미 |
|---|---|
| `●W` | 활성 — 정상 동작 중 |
| `⏸W` | 일시정지 |
| `⚠W` | 손쉬운 사용 권한 필요 |

## 알려진 한계

- v1은 창 이동만 지원합니다 (리사이즈, 스냅, 타일링 없음)
- 전체화면 창, 시스템 UI(Dock, 메뉴바)는 이동 대상이 아닙니다
- 미서명 빌드라 Gatekeeper 첫 실행 우회가 필요합니다 (위 안내 참조)

## 소스에서 빌드 (개발자)

Xcode Command Line Tools 또는 Xcode (Swift 5.9+)가 필요합니다.

```bash
git clone https://github.com/primary924/winch.git
cd winch
make app          # .build/release/Winch.app 생성
make dmg          # .build/release/Winch-x.y.z.dmg 생성
make test         # 도메인 테스트 실행
```

프로젝트 구조와 설계는 `docs/superpowers/specs/`와 `docs/superpowers/plans/` 참고.

### 릴리즈 발행

`v*` 태그를 push하면 GitHub Actions가 자동으로 DMG를 빌드해 GitHub Release를 발행합니다.

```bash
# 1. Resources/Info.plist의 CFBundleShortVersionString을 새 버전으로 수정 (예: 0.2.0)
# 2. 변경사항 커밋
git commit -am "chore: bump version to 0.2.0"
# 3. 태그 생성 및 push
git tag v0.2.0
git push && git push --tags
```

태그 버전(`0.2.0`)과 Info.plist의 버전이 일치해야 합니다. 불일치 시 워크플로가 실패합니다.

릴리즈 노트는 이전 태그 이후의 커밋 메시지에서 자동 생성됩니다.

## 라이선스

[MIT License](LICENSE) © 2026 hyakoo
