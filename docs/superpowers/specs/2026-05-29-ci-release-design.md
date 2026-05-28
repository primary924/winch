# Winch CI & 자동 릴리즈 설계

## 배경

Winch v0.1.0은 수동 작업으로 빌드/릴리즈했다. 코드를 push할 때 깨진 빌드를 즉시 감지할 방법이 없고, 릴리즈를 발행하려면 매번 `make app`, `make dmg`, `gh release create`를 수동으로 실행해야 한다.

GitHub Actions로 다음 두 가지를 자동화한다:
1. **CI**: `main`에 push되거나 PR이 만들어질 때 빌드와 테스트가 자동 검증
2. **자동 릴리즈**: `v*` 패턴 태그를 push하면 DMG 빌드부터 GitHub Release 발행까지 자동 처리

## 요구사항 요약

| 항목 | 결정 |
|---|---|
| CI 트리거 | `main` push + `main`을 향한 PR (생성/업데이트) |
| CI 검증 항목 | `swift build` + `swift test` (린트/포맷 미적용) |
| 릴리즈 트리거 | `v*` 패턴 태그 push (예: `v0.2.0`) |
| 릴리즈 노트 | `gh release create --generate-notes`로 커밋 메시지 기반 자동 생성 |
| 워크플로 파일 구조 | 두 파일 분리 (`ci.yml` + `release.yml`) |
| 러너 | `macos-latest` (현재 `macos-14`, Apple Silicon) |

## CI 워크플로 (`ci.yml`)

### 트리거

```yaml
on:
  push:
    branches: [main]
  pull_request:
    branches: [main]
```

### 잡 구조

단일 잡 `test`:
- 러너: `macos-latest`
- 스텝:
  1. `actions/checkout@v4`
  2. `swift build`
  3. `swift test`

### Concurrency

```yaml
concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true
```

같은 브랜치/PR에 새 커밋이 들어오면 진행 중인 워크플로를 취소하여 러너 분을 절약하고 항상 마지막 커밋만 검증한다.

### 권한

`contents: read` (기본값으로 충분).

## 릴리즈 워크플로 (`release.yml`)

### 트리거

```yaml
on:
  push:
    tags: ['v*']
```

### 잡 구조

단일 잡 `release`:
- 러너: `macos-latest`
- 스텝:
  1. **Checkout** — `actions/checkout@v4`
  2. **버전 정합성 검증** — 태그 이름에서 `v` 접두사를 제거한 값과 `Resources/Info.plist`의 `CFBundleShortVersionString`이 일치하는지 확인. 불일치 시 워크플로 실패.
     ```bash
     TAG_VERSION="${GITHUB_REF_NAME#v}"
     PLIST_VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
     if [[ "$TAG_VERSION" != "$PLIST_VERSION" ]]; then
       echo "Tag version ($TAG_VERSION) does not match Info.plist ($PLIST_VERSION)" >&2
       exit 1
     fi
     ```
  3. **Test** — `swift test`로 깨진 코드가 릴리즈되지 않도록 안전망
  4. **Build app** — `make app`
  5. **Build DMG** — `make dmg`
  6. **Create release** — `gh release create` 호출:
     ```bash
     gh release create "$GITHUB_REF_NAME" \
       ".build/release/Winch-${PLIST_VERSION}.dmg" \
       --title "Winch ${PLIST_VERSION}" \
       --generate-notes
     ```

### 권한

`contents: write` (Release 발행 권한).

### Concurrency

미설정. 릴리즈는 일회성이라 취소되면 안 된다. 동일 태그 두 번 push 시나리오는 GitHub가 거부한다 (이미 존재하는 태그에 대해 push 자체가 차단됨).

## 사용자 워크플로

### 일상적 개발

```bash
git checkout -b feature/x
# ...작업...
git commit -am "feat: ..."
git push
# PR 생성 → CI 자동 실행 → 통과 시 머지
```

### 릴리즈 발행

```bash
# Resources/Info.plist 편집: CFBundleShortVersionString 0.1.0 → 0.2.0
git commit -am "chore: bump version to 0.2.0"
git tag v0.2.0
git push && git push --tags
# → GitHub Actions가 자동으로:
#   1. 태그/plist 버전 정합성 확인
#   2. swift test
#   3. make app + make dmg
#   4. GitHub Release 발행 + 노트 자동 생성
```

## 예외 처리

| 상황 | 동작 |
|---|---|
| CI에서 `swift build` 또는 `swift test` 실패 | 워크플로 실패. PR이면 머지 차단(Branch protection 설정 시) |
| 같은 브랜치에 새 커밋 push | 진행 중인 CI 자동 취소, 최신 커밋만 재실행 |
| 릴리즈 워크플로에서 태그/plist 버전 불일치 | 즉시 실패. 릴리즈 발행 안 됨. 사용자가 plist 또는 태그 수정 후 재시도 |
| 릴리즈 워크플로의 테스트 실패 | 즉시 실패. DMG 빌드 단계로 진행 안 함 |
| 동일 태그 재push 시도 | GitHub가 차단 (이미 존재하는 태그에 대한 push는 거부됨) |

## v1 범위 외 (명시적 제외)

- **SwiftLint / SwiftFormat 린트** — 코드베이스가 작아 효용 낮음. 추후 도입 검토
- **`.build/` 캐싱** — SPM 외부 의존성이 없어 캐시 효용이 미미
- **여러 Swift 버전 매트릭스 테스트** — SPM이 단일 Swift 버전에 묶여 있음
- **코드 커버리지 리포팅** — v1 우선순위 외
- **코드 서명/공증 자동화** — 미서명 빌드 배포 정책 유지 (B 경로). Apple Developer Program 가입 후 별도 의사결정
- **Branch protection 규칙 설정** — GitHub UI에서 설정해야 하며 코드 외 작업. 별도 안내 문서

## 추후 검토

- v0.2 이후 코드 커지면 SwiftLint 도입
- Apple Developer Program 가입 시 코드 서명 + 공증 + 스테이플 단계 추가
- Release 워크플로에서 SHA-256 체크섬 자동 첨부
