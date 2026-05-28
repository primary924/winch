# Winch — Mac 윈도우 드래그 유틸리티 설계

## 배경

macOS에서 윈도우 창을 옮기려면 항상 상단 타이틀바로 포인터를 이동시켜 클릭한 채 드래그해야 한다. 자주 발생하는 동작이지만 매번 타이틀바를 조준해야 하는 점이 불편하다. **Winch**는 사전에 지정한 수정키 조합을 누른 상태에서 포인터를 움직이면 활성 창이 함께 이동하도록 하여 이 마찰을 제거한다. X11/Linux의 Alt+드래그 패턴을 macOS에 가져온다.

## 요구사항 요약

| 항목 | 결정 |
|---|---|
| 이동 대상 창 | 현재 포커스된 활성 창 (포인터 아래 창 아님) |
| 트리거 | 사용자가 지정한 수정키 조합 (Cmd/Option/Ctrl/Shift/Fn 중 1개 이상) |
| 기본값 | Ctrl + Option |
| 조합 매칭 | 정확 매칭 (Ctrl+Option 설정 시 Ctrl+Option+Shift는 트리거 안 함) |
| UI 진입점 | 메뉴바 상주 (Dock 미표시) |
| 부가 기능 | 없음 (이동만; 리사이즈/스냅/타일링 제외) |
| 기술 스택 | Swift + AppKit + SwiftUI + Accessibility API + CGEventTap |
| 배포 | Developer ID 서명·공증 DMG |

## 아키텍처 개요

`LSUIElement = YES`인 메뉴바 상주 Swift 앱. 도메인 로직(상태 머신, 설정)과 OS 어댑터(EventTap, AXUIElement)를 분리하여 도메인은 단위 테스트 가능, 어댑터는 얇은 위임 계층으로 유지한다.

### 컴포넌트

| 컴포넌트 | 책임 |
|---|---|
| `AppDelegate` | 앱 부트스트랩, 의존성 와이어링, 라이프사이클 |
| `PermissionManager` | Accessibility 권한 상태 확인, 사용자 안내 |
| `HotkeyConfig` | 사용자 지정 수정키 조합 저장/로드 (UserDefaults) |
| `EventTap` | `CGEventTap`으로 글로벌 키/마우스 이벤트 수신 → 콜백 |
| `DragController` | `Idle`/`Tracking` 상태 머신, 조합 매칭 판단, 마우스 델타 → 새 위치 계산 |
| `WindowController` | `AXUIElement`로 활성 창 위치 읽기/쓰기 |
| `MenuBarController` | 메뉴바 아이콘 + 메뉴 |
| `PreferencesView` | SwiftUI 환경설정 창 |

### 모듈 경계 원칙

- `DragController`는 `WindowControlling`, `CursorLocating` 같은 프로토콜에만 의존 → 순수 로직 단위 테스트 가능
- `WindowController`는 `AXUIElement` 디테일 캡슐화 → 추후 비공개 API로 교체 가능
- `EventTap`은 이벤트 수신만 담당하고 로직을 모름 (콜백 주입)

## 데이터 흐름

### 부트스트랩

1. 앱 실행 → `AppDelegate` → `PermissionManager.check()`
2. 권한 없음: 안내 다이얼로그 + "시스템 설정 열기" → 권한 부여까지 1초 주기 폴링
3. 권한 OK: `EventTap` 등록 (`flagsChanged` + `mouseMoved` 마스크), `MenuBarController` 메뉴바 진입

### 상태 머신 (DragController)

```
[Idle] --flagsChanged 정확 일치--> [Tracking] --flagsChanged 불일치--> [Idle]
                                       |  ^
                                       |  | mouseMoved (창 위치 업데이트)
                                       +--+
```

### Tracking 진입 시 스냅샷

- `originWindow` ← `WindowController.frontmostWindow()` — **현재 포커스된 앱의 main window**에 해당하는 `AXUIElement` (`NSWorkspace.shared.frontmostApplication`의 `kAXFocusedWindowAttribute`). `AXUIElement` 핸들 캐싱.
- `originCursor` ← `NSEvent.mouseLocation`
- `originWindowOrigin` ← `WindowController.position(originWindow)`
- 활성 창 없음 / 시스템 창(Dock, 메뉴바 자체) / 전체화면 창 / 이동 불가 창(`kAXMovableAttribute = false`) → 무동작, Idle 유지

### 마우스 이동 시

- `delta = currentCursor - originCursor`
- `WindowController.setPosition(originWindow, originWindowOrigin + delta)`
- **시작점 기준 절대 오프셋**으로 계산 (누적 델타 미사용) → 드리프트 없음

### 이벤트 통과 정책

EventTap은 이벤트를 **소비하지 않고 passthrough**. 커서는 정상 이동하고 다른 앱들도 키 이벤트를 정상 수신. Winch는 옆에서 창만 따라 움직인다.

### 수정키 정확 매칭 정책

- `event.flags & 의미있는마스크 == HotkeyConfig.modifierFlags`일 때만 Tracking 진입
- Caps Lock, NumLock 등 토글 키는 마스크에서 제외
- 이유: 사용자가 Ctrl+Option로 지정했을 때 Ctrl+Option+Shift 같은 상위 조합으로 우연히 트리거되는 것을 방지하여 다른 단축키와의 충돌을 최소화

## 환경설정

### UserDefaults 키

| 키 | 타입 | 기본값 |
|---|---|---|
| `hotkey.modifierFlags` | `UInt` (CGEventFlags 비트마스크) | `.maskControl \| .maskAlternate` |
| `app.paused` | `Bool` | `false` |
| `app.launchAtLogin` | `Bool` | `false` |

### PreferencesView (SwiftUI)

- 수정키 5개 토글 체크박스: Cmd / Option / Ctrl / Shift / Fn (최소 1개 강제 — 모두 해제 시 저장 비활성)
- 로그인 시 시작 토글: `SMAppService.mainApp.register()` / `unregister()`
- 권한 상태 배너 (권한 없으면 빨간색 + "권한 부여" 버튼, 시스템 설정 직링크)
- 현재 단축키 미리보기 ("현재: ⌃⌥" 형태)

### 메뉴바 메뉴

- 상태 표시 (활성 ● / 일시정지 ⏸ / 권한 필요 ⚠️)
- 일시정지/재개 토글
- 환경설정…
- 로그인 시 시작 (체크박스 메뉴 항목)
- Winch 정보
- 종료

## 예외 처리

| 상황 | 처리 |
|---|---|
| 활성 창 없음 / 시스템 창 / 전체화면 창 | Tracking 진입 시 무동작, Idle 유지 |
| 드래그 중 활성 앱 전환 | 캐싱한 `AXUIElement` 계속 사용 (처음 잡은 창만 끝까지 이동) |
| 드래그 중 창이 닫히거나 `AXUIElement` 무효화 | `setPosition` 호출이 실패하면 조용히 무시하고 Tracking 유지 (수정키 해제 시 자연스럽게 Idle 복귀) |
| 창이 화면 밖으로 나감 | 막지 않음 (멀티모니터 가로지르기 허용) |
| `CGEventTap`이 OS에 의해 비활성화 (슬립 등) | `eventTapEnabledByTimeout` 콜백에서 `CGEvent.tapEnable(_:enable:true)` 자동 재활성화 |
| 권한 회수 (사용자가 시스템 설정에서 해제) | 폴러가 감지 → 메뉴바 ⚠️ + 안내 |
| 일시정지 상태 | EventTap 유지, `DragController`가 이벤트 무시 (재등록 비용 회피) |

## 테스트 전략

| 계층 | 방식 | 검증 대상 |
|---|---|---|
| **Domain** | XCTest 단위 테스트 | `DragController` 상태 전이, 마우스 델타 → 새 위치 계산, `HotkeyConfig` 정확 매칭 (일치/초과/부분), 마스크 인/디코딩 |
| **Platform** | 테스트 안 함 (얇은 어댑터) | OS API 호출 위임만 |
| **수동 QA** | 빌드별 체크리스트 | 권한 부여/회수 흐름, 멀티모니터, 일시정지, 자동 시작, 슬립 복귀 후 EventTap 재활성화, 전체화면/Mission Control 진입 중 동작 |

`DragController`는 `WindowControlling`, `CursorLocating` 프로토콜에만 의존하여 fake 주입으로 순수 함수처럼 검증한다.

## 프로젝트 구조

```
Winch/
  Winch.xcodeproj
  Sources/
    App/                AppDelegate, Main
    Domain/             DragController, HotkeyConfig
    Platform/           EventTap, WindowController, PermissionManager
    UI/                 MenuBarController, PreferencesView
  Tests/
    DomainTests/        DragController, HotkeyConfig 테스트
  Resources/            Assets.xcassets, Info.plist
```

## 배포

- Developer ID 서명 + 공증(notarize) + stapling
- DMG 직접 배포
- 외부 의존성 없음 (표준 라이브러리만 사용)
- Swift 5.9+ / Xcode 15+ / macOS 13 Ventura+ 최소 지원 (`SMAppService` 요구사항)

## v1 범위 외 (명시적 제외)

- 창 크기 조절 / 화면 가장자리 스냅 / 타일링
- 단축키로 즉시 이동 (Win+화살표 패턴)
- 자동 업데이트 (Sparkle은 v2 이후)
- 다국어 지원
- App Store 배포 (Accessibility 심사 별도 검토)
- 크래시 리포트

## 추후 검토

- 메뉴바 아이콘 / 앱 아이콘 디자인
- 다른 수정키 조합 사용자별 통계 기반 기본값 재검토
- 비공개 API 도입 시 성능 차이 측정
