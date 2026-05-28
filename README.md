# Winch

macOS에서 윈도우 창의 타이틀바를 일일이 잡지 않고도 창을 옮길 수 있게 해주는 메뉴바 유틸리티입니다. 사전에 지정한 수정키를 누른 상태에서 마우스를 움직이면 활성 창이 커서를 따라 이동합니다.

X11/Linux의 `Alt+드래그` 패턴을 macOS에 가져온 것입니다.

## 요구 사항

- macOS 13 Ventura 이상
- Xcode Command Line Tools 또는 Xcode (Swift 5.9+)

## 설치

현재는 소스 빌드만 지원합니다. (배포용 `.dmg`는 추후 제공 예정)

```bash
git clone https://github.com/primary924/winch.git
cd winch
make app
```

빌드가 끝나면 `.build/release/Winch.app`이 생성됩니다.

상시 사용하려면 앱을 `/Applications`로 옮깁니다:

```bash
cp -R .build/release/Winch.app /Applications/
```

## 첫 실행

```bash
open /Applications/Winch.app
```

처음 실행하면 macOS가 **손쉬운 사용(Accessibility) 권한**을 요청합니다. 이 권한이 없으면 Winch는 창을 옮길 수 없습니다.

1. 시스템 설정 → 개인정보 보호 및 보안 → 손쉬운 사용 으로 이동
2. 목록에서 `Winch`를 켭니다
3. 메뉴바 아이콘이 `⚠W`(권한 필요) → `●W`(활성)으로 바뀌면 준비 완료

> 앱을 다시 빌드하면 바이너리 해시가 바뀌어 권한이 초기화될 수 있습니다. 이 경우 시스템 설정에서 다시 켜주세요.

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
- 직접 빌드한 바이너리는 코드 서명이 되어 있지 않아 macOS Gatekeeper가 경고할 수 있습니다 (`마우스 우클릭 → 열기`로 우회)
- 전체화면 창, 시스템 UI(Dock, 메뉴바)는 이동 대상이 아닙니다

## 라이선스

(추후 추가)
