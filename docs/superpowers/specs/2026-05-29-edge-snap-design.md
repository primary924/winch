# Winch 화면 가장자리 스냅 설계

## 배경

현재 Winch는 `Ctrl+Option`을 누른 채 커서를 움직이면 활성 창이 자유롭게 따라온다. 사용자가 창을 화면 절반/풀스크린으로 빠르게 배치하고 싶을 때는 매번 손으로 가장자리에 맞춰야 한다.

본 문서는 **이동 제스처 중 커서가 화면 가장자리에 닿으면 해당 영역으로 스냅**하는 기능을 정의한다. Windows Aero Snap, macOS Stage Manager 류의 익숙한 패턴을 가져온다.

이번 v1 스냅은 **3-zone** (왼쪽 절반 / 오른쪽 절반 / 풀스크린)만 지원한다. 4분할(모서리), 아래 절반, 리사이즈는 명시적 제외.

## 요구사항 요약

| 항목 | 결정 |
|---|---|
| 트리거 제스처 | 이동(`Ctrl+Option` 드래그) 도중에만 활성 |
| 지원 영역 | 위(풀스크린) / 왼쪽(절반) / 오른쪽(절반) — 3-zone |
| 확정 시점 | 모디파이어 해제 순간 (커서가 영역 안에 있으면 commit) |
| 미리보기 | 반투명 NSWindow 오버레이 — 영역 진입 즉시 표시, 이탈 시 숨김 |
| 멀티 모니터 | 커서가 현재 위치한 화면 기준 |
| 스냅 후 재드래그 | 자동 복원 — 첫 유의미한 이동에 원래 크기로 돌아가 커서 따라옴 |
| 기본 활성 여부 | 기본 ON, 환경설정에서 OFF 가능 |

## 아키텍처 개요

핵심 변경: `DragController` 상태 머신 확장 + 새 컴포넌트 4개 추가. Domain은 OS 독립 유지, Platform/UI는 얇은 어댑터.

### 새 Domain 타입 (`Sources/WinchDomain/`)

| 파일 | 책임 |
|---|---|
| `SnapTarget.swift` | `enum SnapZone { case left, right, top }`, `struct SnapTarget { zone, frame }` |
| `SnapZoneCalculator.swift` | 순수 함수 `zone(forCursor:in:)`, `target(for:in:)` — 단위 테스트 대상 |
| `Protocols.swift` 추가 | `ScreenInfoProviding` (visible frame 조회), `SnapPreviewing` (오버레이 제어) |
| `DragController.swift` 수정 | 상태 머신 확장 + 스냅 콜백 + 사전 frame 보관 |

### 새 Platform 어댑터 (`Sources/Winch/Platform/`)

| 파일 | 책임 |
|---|---|
| `ScreenInfoProvider.swift` | `NSScreen.screens` 중 커서 위치 포함 화면의 `visibleFrame` (메뉴바/Dock 제외) 반환, AppKit→Quartz Y축 변환 |
| `WindowController.swift` 수정 | `position(of:)`을 `frame(of:)`로 교체 + `setFrame(of:to:)` 추가 |

### 새 UI 컴포넌트 (`Sources/Winch/UI/`)

| 파일 | 책임 |
|---|---|
| `SnapPreviewWindow.swift` | 반투명 NSWindow + 커스텀 NSView — `SnapPreviewing` 구현 |

### 설정 확장

- `SettingsStore`: 새 키 `snap.enabled` (Bool, 기본값 `true`)
- `PreferencesModel` + `PreferencesView`: 새 토글 "Enable edge snap"

## DragController 상태 머신 확장

### 상태 enum

```swift
private enum State {
    case idle
    case tracking(
        window: WindowHandle,
        originCursor: CGPoint,
        originWindow: CGPoint,
        currentSnapZone: SnapZone?
    )
}
```

### 새 프로퍼티

- `private let screenInfoProvider: ScreenInfoProviding` — 생성자 주입
- `public var isSnapEnabled: Bool = true`
- `public var onSnapZoneChanged: ((SnapTarget?) -> Void)?` — AppDelegate가 PreviewOverlay 제어
- `private var preSnapFrames: [ObjectIdentifier: CGRect] = [:]` — 스냅 직전 frame 보관
- `private static let restoreThreshold: CGFloat = 5` — 복원 트리거 최소 커서 이동

### 핵심 흐름

**Tracking 진입** (조합 매칭):
- `originWindow = frame.origin`, `currentSnapZone: nil`로 시작
- 복원은 여기서 하지 않음 (실수 모디파이어 누름 보호 — 사용자가 실제로 움직여야 의도 확인됨)

**mouseMoved 처리**:
1. **복원 단계** — `preSnapFrames[id]` 존재하고 커서 델타가 `restoreThreshold` 초과 시:
   - `restoredFrame.origin.x = cursor.x - preSnapFrame.width / 2`
   - `restoredFrame.origin.y = cursor.y - 14` (타이틀바 부근)
   - `setFrame(restoredFrame)`, `preSnapFrames`에서 제거
   - **`originCursor`/`originWindow` 새 값으로 리셋** → 이후 델타 계산이 자연스럽게 이어짐
2. **일반 이동** — `newPos = originWindow + (cursor - originCursor)` → `setPosition`
3. **스냅 영역 갱신** — `screenInfoProvider.visibleFrame(containing: cursor)` 호출 → `SnapZoneCalculator.zone(...)` → 이전 zone과 다르면 state 업데이트 + `onSnapZoneChanged?(target)` 호출

**Tracking 종료** (조합 비매칭):
- `currentSnapZone` 있고 `isSnapEnabled=true`이면:
  - `windowController.frame(of: window)` 호출해 현재 frame을 `preSnapFrames[id]`에 저장
  - `target = SnapZoneCalculator.target(for: zone, in: visibleFrame)`
  - `setFrame(window, target)` — 즉시 적용 (애니메이션 없음)
- `onSnapZoneChanged?(nil)` — 미리보기 숨김
- `state = .idle`

## SnapZoneCalculator

순수 정적 함수. visible frame (메뉴바/Dock 제외) 기준, threshold = 8pt.

```swift
public enum SnapZoneCalculator {
    public static let edgeThreshold: CGFloat = 8

    public static func zone(forCursor cursor: CGPoint, in visibleFrame: CGRect) -> SnapZone? {
        let inTop = cursor.y < visibleFrame.minY + edgeThreshold
        if inTop { return .top }
        let inLeft = cursor.x < visibleFrame.minX + edgeThreshold
        if inLeft { return .left }
        let inRight = cursor.x > visibleFrame.maxX - edgeThreshold
        if inRight { return .right }
        return nil
    }

    public static func target(for zone: SnapZone, in visibleFrame: CGRect) -> CGRect {
        switch zone {
        case .top:
            return visibleFrame
        case .left:
            return CGRect(x: visibleFrame.minX, y: visibleFrame.minY,
                          width: visibleFrame.width / 2, height: visibleFrame.height)
        case .right:
            return CGRect(x: visibleFrame.minX + visibleFrame.width / 2, y: visibleFrame.minY,
                          width: visibleFrame.width / 2, height: visibleFrame.height)
        }
    }
}
```

상단 모서리는 top zone이 소유 (좌/우는 `inTop` 검사를 먼저 통과해야 도달).

## WindowControlling 프로토콜 변경

```swift
public protocol WindowControlling {
    func frontmostWindow() -> WindowHandle?
    func frame(of window: WindowHandle) -> CGRect?              // 신규 (position 대체)
    func setPosition(of window: WindowHandle, to point: CGPoint) // 유지
    func setFrame(of window: WindowHandle, to frame: CGRect)     // 신규
}
```

- `position(of:)` 삭제, `frame(of:)`으로 교체 — 크기 정보가 필요해짐 (스냅 시 frame 저장용)
- `setPosition`은 일반 드래그에서 유지 (빠른 위치 업데이트)
- `setFrame`은 스냅 commit과 복원에서 사용

기존 호출처(`DragController.tryEnterTracking`)는 `frame(of:).origin`을 사용.

## SnapPreviewWindow

```swift
final class SnapPreviewWindow: SnapPreviewing {
    private let window: NSWindow
    private let contentView: SnapPreviewView

    init() {
        window = NSWindow(contentRect: .zero,
                          styleMask: .borderless,
                          backing: .buffered,
                          defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        window.hasShadow = false
        contentView = SnapPreviewView()
        window.contentView = contentView
    }

    func show(at frame: CGRect) {
        // AX 좌표(top-left origin) → AppKit 좌표(bottom-left origin) 변환
        let appKitFrame = convertToAppKit(frame)
        window.setFrame(appKitFrame, display: true)
        window.orderFront(nil)
    }

    func hide() {
        window.orderOut(nil)
    }
}

final class SnapPreviewView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2),
                                xRadius: 8, yRadius: 8)
        NSColor.controlAccentColor.withAlphaComponent(0.25).setFill()
        path.fill()
        NSColor.controlAccentColor.withAlphaComponent(0.6).setStroke()
        path.lineWidth = 2
        path.stroke()
    }
}
```

애니메이션 없음 — 즉시 표시/숨김으로 예측 가능성 우선.

## 설정 확장

### `SettingsStore`

```swift
private enum Key {
    // ...기존...
    static let snapEnabled = "snap.enabled"
}

var isSnapEnabled: Bool {
    get {
        if defaults.object(forKey: Key.snapEnabled) == nil { return true } // 기본 ON
        return defaults.bool(forKey: Key.snapEnabled)
    }
    set { defaults.set(newValue, forKey: Key.snapEnabled) }
}
```

### `PreferencesView` + `PreferencesModel`

- 새 Form 섹션 "Edge Snap"
- 토글 "Enable edge snap"
- `PreferencesModel`에 `@Published var snapEnabled: Bool` (didSet으로 콜백 발화)
- AppDelegate가 콜백을 받아 `settings.isSnapEnabled` 업데이트 + `dragController.isSnapEnabled` 반영

## AppDelegate 와이어링

`applicationDidFinishLaunching`에 추가:

```swift
let preview = SnapPreviewWindow()
let screenInfo = ScreenInfoProvider()

dragController = DragController(
    hotkeyConfig: settings.hotkeyConfig,
    windowController: windowController,
    cursorLocator: cursorLocator,
    screenInfoProvider: screenInfo
)
dragController.isPaused = settings.isPaused
dragController.isSnapEnabled = settings.isSnapEnabled
dragController.onSnapZoneChanged = { [weak preview] target in
    if let t = target { preview?.show(at: t.frame) } else { preview?.hide() }
}
```

`openPreferences()`의 PreferencesModel 생성 + 콜백 와이어링에 snap 토글 추가.

## 예외 처리

| 상황 | 처리 |
|---|---|
| `isSnapEnabled=false` | 스냅 영역 판정/미리보기/복원 모두 skip — 기존 자유 이동만 |
| 커서가 모든 모니터 외부 | `visibleFrame(containing:)`이 nil 반환 → zone=nil, 미리보기 숨김 |
| AX `frame(of:)` 실패 | `preSnapFrames`에 저장 안 함 (복원 불가). 그래도 setFrame은 시도 |
| 복원 시 창 좌표가 화면 밖 | 허용 (기존 정책과 일치) |
| 권한 회수됨 | EventTap 비활성 → 스냅도 자동으로 동작 안 함 |
| 스냅된 창 닫힘 | `preSnapFrames` 잔존하나 다음 setFrame 시 AX 실패로 조용히 무시. v1에서는 정리 안 함 (메모리 영향 미미) |

## 테스트 전략

| 계층 | 방식 | 검증 |
|---|---|---|
| `SnapZoneCalculator` | XCTest 단위 테스트 | top/left/right zone 판정, 모서리 경합(top 우선), 영역 밖 nil, 각 zone의 target frame 계산 |
| `DragController` | XCTest + fake screenInfoProvider | 스냅 진입/이탈 시 콜백 발화, Tracking 종료 시 setFrame + preSnapFrames 저장, 복원 임계값 동작, `isSnapEnabled=false` 우회 |
| Platform (`ScreenInfoProvider`, `WindowController` 신규 메서드) | 얇은 어댑터 — 테스트 안 함 | OS API 호출만 |
| UI (`SnapPreviewWindow`, 환경설정 토글) | 수동 QA | 시각 외관, 토글 동작 |

수동 QA 체크리스트(`docs/superpowers/qa/manual-checklist.md`)에 추가:
- [ ] 이동 중 왼쪽/오른쪽/위 가장자리 진입 → 반투명 미리보기 표시
- [ ] 가장자리에서 벗어남 → 미리보기 사라짐
- [ ] 미리보기 표시 상태에서 모디파이어 해제 → 창이 해당 영역으로 스냅
- [ ] 스냅된 창을 다시 Ctrl+Option 드래그 → 원래 크기로 복원되어 커서 따라옴
- [ ] 멀티 모니터: 각 모니터의 가장자리에서 스냅 동작
- [ ] 환경설정 "Enable edge snap" OFF → 가장자리에 닿아도 스냅 안 됨, 미리보기도 안 보임

## 프로젝트 구조 (스냅 추가 후)

```
Winch/
  Sources/
    WinchDomain/
      HotkeyConfig.swift
      DragController.swift       ← 수정 (상태 확장 + 스냅 로직)
      Protocols.swift            ← 수정 (ScreenInfoProviding, SnapPreviewing 추가)
      SnapTarget.swift           ← 신규
      SnapZoneCalculator.swift   ← 신규
    Winch/
      App/
        AppDelegate.swift        ← 수정 (스냅 와이어링)
        main.swift
      Platform/
        EventTap.swift
        WindowController.swift   ← 수정 (frame/setFrame)
        SystemCursorLocator.swift
        PermissionManager.swift
        SettingsStore.swift      ← 수정 (snap.enabled)
        LoginItemManager.swift
        ScreenInfoProvider.swift ← 신규
      UI/
        MenuBarController.swift
        PreferencesView.swift    ← 수정 (Edge Snap 토글)
        PreferencesWindowController.swift
        SnapPreviewWindow.swift  ← 신규
  Tests/
    WinchDomainTests/
      HotkeyConfigTests.swift
      DragControllerTests.swift  ← 수정 (스냅 시나리오 추가)
      SnapZoneCalculatorTests.swift ← 신규
      Fakes.swift                ← 수정 (FakeScreenInfoProvider 추가)
```

## v1 범위 외 (명시적 제외)

- 4분할 (top-left/top-right/bottom-left/bottom-right quarter snap)
- 아래 가장자리 스냅 (`bottom`)
- 리사이즈 제스처 (별도 모디파이어 + 드래그)
- 스냅 애니메이션
- 사용자 정의 hot zone threshold
- 모니터별 독립 활성/비활성
- 스냅 사운드 / 햅틱 피드백
- 스냅된 창 메모리 영구화 (앱 재시작 시 preSnapFrames 복원 안 함)

## 추후 검토

- 4분할 추가 (사용자 피드백 후)
- macOS 26+ Stage Manager 통합 가능성
- 스냅 중인 창에 대해 hue 강조 등 보조 시각 효과
