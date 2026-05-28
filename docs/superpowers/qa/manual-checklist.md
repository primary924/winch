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
