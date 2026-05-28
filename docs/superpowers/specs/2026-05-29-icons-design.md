# Winch 아이콘 설계

## 배경

Winch v0.1.x는 메뉴바에 텍스트 `●W` / `⏸W` / `⚠W`를 표시하고, 앱 아이콘은 기본 macOS Swift 실행 파일 아이콘을 사용한다. 두 가지 문제:
- 메뉴바 텍스트는 macOS 메뉴바 유틸리티 관용에서 벗어남 (다른 앱들은 거의 다 아이콘)
- 기본 앱 아이콘은 Finder/시스템 설정/Spotlight에서 식별성이 떨어지고 "완성된 앱"의 인상이 약함

본 문서는 두 아이콘의 디자인과 자산 파이프라인을 정의한다.

## 요구사항 요약

| 항목 | 결정 |
|---|---|
| 메뉴바 아이콘 방식 | SF Symbol 런타임 로드 (`NSImage(systemSymbolName:)`) |
| 메뉴바 상태별 심볼 | active: `arrow.up.and.down.and.arrow.left.and.right` / paused: `pause.fill` / permissionMissing: `exclamationmark.triangle.fill` |
| 앱 아이콘 디자인 | 메뉴바와 동일한 4방향 화살표 + 블루 그라데이션 squircle 배경 |
| 앱 아이콘 자산 형식 | `.icns` (10개 크기 포함) |
| 자산 파이프라인 | 사전 생성된 `.icns`를 repo에 커밋, 재생성 스크립트 별도 제공 |

## 메뉴바 아이콘

### 파일 변경 범위

`Sources/Winch/UI/MenuBarController.swift`만 수정. 다른 컴포넌트 영향 없음.

### 상태 → SF Symbol 매핑

| 상태 | Symbol | 접근성 설명 |
|---|---|---|
| `.active` | `arrow.up.and.down.and.arrow.left.and.right` | "활성" |
| `.paused` | `pause.fill` | "일시정지" |
| `.permissionMissing` | `exclamationmark.triangle.fill` | "권한 필요" |

### 구현 핵심

- `updateAppearance()`에서 `button.title` 대신 `button.image = NSImage(systemSymbolName:..., accessibilityDescription:...)`를 설정
- `image.isTemplate = true` 적용 → 라이트/다크 모드 자동 색상 적응, 활성/하이라이트 시 자동 반전
- `button.title = ""`로 비워서 텍스트 잔재 제거

### 검증

시각적 변화는 단위 테스트가 어려움. `make app` → `open .build/release/Winch.app` → 메뉴바에서:
1. 권한 부여 전: 노란 삼각형 (`exclamationmark.triangle.fill`)
2. 권한 부여 후: 4방향 화살표 (`arrow.up.and.down.and.arrow.left.and.right`)
3. 메뉴 → Pause: 일시정지 심볼 (`pause.fill`)
4. 메뉴 → Resume: 다시 4방향 화살표

## 앱 아이콘

### 디자인

- **배경**: 둥근 사각형 (squircle, 1024 기준 모서리 반경 약 22.4%)
- **그라데이션**: 위 `#4F9EFF` → 아래 `#1A5CD9` (수직 그라데이션)
- **전경**: `arrow.up.and.down.and.arrow.left.and.right` 흰색, 캔버스 약 60% 크기, 중앙 정렬

### 파일 구조 변경

```
scripts/
  render-app-icon.swift     # 신규 — 1024×1024 PNG 렌더
  build-app-icon.sh         # 신규 — render + sips + iconutil 오케스트레이션
Resources/
  AppIcon.icns              # 신규 — 빌드된 아이콘 자산 (10개 크기 포함)
  Info.plist                # 수정 — CFBundleIconFile 키 추가
scripts/bundle-app.sh       # 수정 — AppIcon.icns 복사 한 줄 추가
Makefile                    # 수정 — `make icon` 타겟 추가
```

### 자산 생성 파이프라인

`make icon` 호출 시:

1. `swift scripts/render-app-icon.swift` → 1024×1024 PNG 생성 (블루 그라데이션 + 흰 화살표)
2. `sips`로 10개 크기 리사이즈:
   - `icon_16x16.png` (16), `icon_16x16@2x.png` (32)
   - `icon_32x32.png` (32), `icon_32x32@2x.png` (64)
   - `icon_128x128.png` (128), `icon_128x128@2x.png` (256)
   - `icon_256x256.png` (256), `icon_256x256@2x.png` (512)
   - `icon_512x512.png` (512), `icon_512x512@2x.png` (1024)
3. PNG들을 `.build/AppIcon.iconset/`에 표준 이름으로 배치
4. `iconutil --convert icns "$ICONSET" --output Resources/AppIcon.icns`
5. 중간 산출물(`.build/AppIcon.iconset`, 1024 PNG)은 `.build/` 내부에 남겨두어 `.gitignore`로 자동 제외

### Info.plist 변경

다음 키 추가:

```xml
<key>CFBundleIconFile</key>
<string>AppIcon</string>
```

확장자 없이 `AppIcon`만 적는 게 macOS 관용. 실제 파일은 `AppIcon.icns`.

### bundle-app.sh 변경

기존 `cp Resources/Info.plist ...` 라인 옆에 추가:

```bash
cp Resources/AppIcon.icns "$APP_DIR/Contents/Resources/AppIcon.icns"
```

### Makefile 변경

`icon` 타겟 추가:

```makefile
.PHONY: build test app dmg icon clean run

icon:
	./scripts/build-app-icon.sh
```

`app`/`dmg` 타겟은 `icon`에 의존하지 않음 (`AppIcon.icns`가 이미 커밋되어 있음). 디자인 변경 시에만 `make icon`을 명시적으로 실행하고 결과 커밋.

### 검증

`make app && open .build/release/Winch.app`:
1. Finder의 Applications에서 앱 아이콘이 블루 그라데이션 + 흰 화살표로 보이는지
2. 메뉴바 → "About Winch"에서 동일 아이콘이 표시되는지
3. 시스템 설정 → 개인정보 보호 → 손쉬운 사용 목록에서 Winch 옆 아이콘 확인

## 검증 체크리스트

QA 체크리스트(`docs/superpowers/qa/manual-checklist.md`)에 다음 항목 추가:

```markdown
## 아이콘 표시
- [ ] 메뉴바: 권한 부여 전 ⚠️ 삼각형, 부여 후 4방향 화살표
- [ ] 메뉴바: Pause 시 일시정지 심볼, Resume 시 다시 화살표
- [ ] Finder Applications: 블루 그라데이션 + 흰 화살표 앱 아이콘
- [ ] About Winch 패널: 동일 앱 아이콘
- [ ] 시스템 설정 손쉬운 사용 목록: 동일 앱 아이콘
```

## v1 범위 외 (명시적 제외)

- 다크 모드 전용 앱 아이콘 변형 (macOS는 단일 앱 아이콘 표준 사용)
- 동적/애니메이션 메뉴바 아이콘 (활성 시 펄스 등) — 산만함
- 커스텀 다국어별 메뉴바 아이콘 — SF Symbol은 글자가 없어 무관
- 알림/뱃지 카운트 표시 — Winch는 알림 없음

## 추후 검토

- 메뉴바 아이콘의 SF Symbol 별 시각 가독성 사용자 피드백 수렴 후 교체 검토
- 앱 아이콘에 미세한 입체감/그림자 추가 (예: 화살표 안쪽 음영) — 디자인 도구 도입 시 진행
- macOS 26+ 도입 시 새로운 아이콘 가이드라인 대응
