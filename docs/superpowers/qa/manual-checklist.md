# Winch Manual QA Checklist

Run before each release. Build via `make app` and launch `.build/release/Winch.app`.

## Permission flow
- [ ] Fresh launch with no Accessibility permission → menu bar shows ⚠W, system prompt appears
- [ ] Grant permission → within ~1s, menu bar transitions to ●W, drag begins working
- [ ] Revoke permission in System Settings → within ~1s, menu bar transitions to ⚠W, drag stops working

## Basic drag
- [ ] Open Finder window, focus it, hold Ctrl+Option, move cursor → window follows
- [ ] Release modifiers mid-drag → window stops following, stays at last position
- [ ] Re-press modifiers without moving cursor → drag re-engages with new snapshot

## Hotkey configuration
- [ ] Open Preferences, toggle off Ctrl, on Cmd → new combo Cmd+Option becomes active immediately
- [ ] Uncheck all modifiers → red "At least one modifier is required" appears, drag stops
- [ ] Recheck modifiers → drag resumes

## Pause / resume
- [ ] Menu bar → "Pause" → status changes to ⏸W, modifier+drag does nothing
- [ ] Menu bar → "Resume" → status changes to ●W, drag works again
- [ ] Pause state persists across app restart

## Login item
- [ ] Toggle "Launch at login" on, restart Mac → Winch starts automatically
- [ ] Toggle off, restart Mac → Winch does not start

## Edge cases
- [ ] Hold hotkey over fullscreen window → no drag, no crash
- [ ] Hold hotkey over Dock / menu bar / desktop with no focused window → no crash
- [ ] Drag a window from primary display onto secondary display → crosses cleanly
- [ ] Drag window beyond screen edge → allowed, no clamping
- [ ] System sleep → wake → drag still works (EventTap re-enabled)
- [ ] Switch focused app mid-drag (e.g., Cmd+Tab while holding hotkey) → original window keeps moving until hotkey release

## Exit
- [ ] Menu bar → "Quit Winch" → app exits cleanly, menu bar item disappears

## 아이콘 표시
- [ ] 메뉴바: 권한 부여 전 ⚠️ 삼각형 (`exclamationmark.triangle.fill`)
- [ ] 메뉴바: 권한 부여 후 4방향 화살표 (`arrow.up.and.down.and.arrow.left.and.right`)
- [ ] 메뉴바: Pause 클릭 시 일시정지 심볼 (`pause.fill`)
- [ ] 메뉴바: Resume 클릭 시 다시 4방향 화살표
- [ ] Finder Applications: 블루 그라데이션 + 흰 화살표 앱 아이콘 (텍스트 "exec" 아이콘 아님)
- [ ] About Winch 패널: 동일 앱 아이콘 표시
- [ ] 시스템 설정 → 개인정보 보호 → 손쉬운 사용 목록: Winch 항목 옆 동일 아이콘

## 가장자리 스냅
- [ ] 이동 중 왼쪽 가장자리 진입 → 반투명 미리보기(왼쪽 절반)
- [ ] 이동 중 오른쪽 가장자리 진입 → 반투명 미리보기(오른쪽 절반)
- [ ] 이동 중 위 가장자리 진입 → 반투명 미리보기(풀스크린)
- [ ] 가장자리에서 벗어남 → 미리보기 사라짐
- [ ] 모디파이어 해제 (가장자리 안에서) → 창이 해당 영역으로 스냅
- [ ] 스냅된 창 다시 Ctrl+Option 드래그 → 원래 크기로 복원, 커서 따라옴
- [ ] 멀티 모니터: 보조 모니터 가장자리에서도 스냅 동작
- [ ] 환경설정 "Enable edge snap" OFF → 가장자리 닿아도 미리보기/스냅 없음
- [ ] OFF→ON 토글 시 즉시 반영 (앱 재시작 없이)
