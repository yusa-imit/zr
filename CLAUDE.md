# zr — Claude Code Orchestrator

> **zr** (zig-runner): Zig로 작성된 범용 태스크 러너 & 워크플로우 매니저 CLI
> **v1.0.0 Released** (2026-02-28) — Phase 1-13 COMPLETE, post-release development

---

## Project Overview

- **Language**: Zig 0.15.2
- **Config Format**: TOML + 내장 표현식 엔진
- **Build**: `zig build` / `zig build test`
- **PRD**: `docs/PRD.md` (전체 요구사항 참조)
- **Branch Strategy**: `main` (development)

## Repository Structure

```
zr/
├── CLAUDE.md                    # THIS FILE — orchestrator
├── docs/PRD.md                  # Product Requirements Document
├── .gitignore                   # Git ignore rules
├── .claude/
│   ├── agents/                  # Custom subagent definitions (6 agents)
│   │   ├── zig-developer.md     #   model: sonnet — Zig 구현
│   │   ├── code-reviewer.md     #   model: sonnet — 코드 리뷰
│   │   ├── test-writer.md       #   model: sonnet — 테스트 작성
│   │   ├── architect.md         #   model: opus   — 아키텍처 설계
│   │   ├── git-manager.md       #   model: haiku  — Git 운영
│   │   └── ci-cd.md             #   model: haiku  — CI/CD 관리
│   ├── commands/                # Slash commands (skills)
│   ├── memory/                  # Persistent agent memory
│   └── settings.json            # Claude Code permissions
├── .github/workflows/           # CI/CD pipelines
│   ├── ci.yml                   #   Build, test, cross-compile
│   └── release.yml              #   Release pipeline
├── tests/                       # Integration tests
│   └── integration.zig          #   Black-box CLI integration tests
├── examples/                    # Language-specific example projects (15 examples)
├── docs/                        # Documentation
│   ├── PRD.md                   #   Product Requirements Document
│   └── guides/                  #   User guides (6 guides)
└── src/                         # Source code (~34 modules)
    ├── main.zig                 #   엔트리포인트 + dispatcher (~550 lines)
    ├── cli/                     #   CLI interface (34 modules)
    ├── config/                  #   TOML parser, schema, expression engine
    ├── graph/                   #   DAG, topological sort, cycle detection
    ├── exec/                    #   Scheduler, worker pool, process manager
    ├── plugin/                  #   Plugin system (native + WASM)
    ├── watch/                   #   Native file watcher (inotify/kqueue/ReadDirectoryChangesW)
    ├── output/                  #   Terminal rendering, colors, progress
    ├── history/                 #   Execution history
    ├── toolchain/               #   Toolchain management (8 languages)
    ├── cache/                   #   Local + remote cache (S3/GCS/Azure/HTTP)
    ├── multirepo/               #   Multi-repo orchestration
    └── util/                    #   Glob, duration, semver, hash, platform
```

---

## Development Workflow

### Autonomous Development Protocol

Claude Code는 이 프로젝트에서 **완전 자율 개발**을 수행한다. 다음 프로토콜을 따른다:

1. **작업 수신** → PRD 또는 사용자 지시를 분석
2. **계획 수립** → 대화형 세션: `EnterPlanMode`로 사용자 승인; 자율 세션(`claude -p`): 내부적으로 계획 후 즉시 구현 진행 (plan mode 도구 사용 금지)
3. **팀 구성** → 작업 복잡도에 따라 동적으로 팀/서브에이전트 생성
4. **구현** → 코딩, 테스트, 리뷰를 병렬 수행
5. **검증** → `zig build test`로 전체 테스트 통과 확인
6. **커밋** → 변경사항 커밋 (사용자 요청 시)
7. **메모리 갱신** → 학습된 내용을 `.claude/memory/`에 기록

### Team Orchestration

복잡한 작업 시 다음 패턴으로 팀을 구성한다:

```
Leader (orchestrator)
├── zig-developer   — 구현 담당
├── code-reviewer   — 코드 리뷰 & 품질 보증
├── test-writer     — 테스트 작성
└── architect       — 설계 검토 (필요 시)
```

**팀 생성 기준**:
- 3개 이상 파일 수정이 필요한 작업 → 팀 구성
- 단일 파일 수정 → 직접 수행
- 아키텍처 변경 → architect 포함

**팀 해산**: 작업 완료 후 반드시 `shutdown_request` → `TeamDelete`로 정리

### Automated Session Execution

자동화 세션(cron job 등)에서는 다음 프로토콜을 순서대로 실행한다.

**컨텍스트 복원** — 세션 시작 시 다음 파일을 읽어 프로젝트 상태 파악:
1. `.claude/memory/project-context.md` — 현재 phase, 체크리스트, 진행 상황
2. `.claude/memory/architecture.md` — 아키텍처 결정사항
3. `.claude/memory/decisions.md` — 기술 결정 로그
4. `.claude/memory/debugging.md` — 알려진 이슈와 해결법
5. `.claude/memory/patterns.md` — 검증된 코드 패턴
6. `.claude/memory/zig-0.15-migration.md` — Zig 0.15 breaking changes

**8단계 실행 사이클**:

| Phase | 내용 | 비고 |
|-------|------|------|
| 1. 상태 파악 | `/status` 실행, git log·빌드·테스트 상태 점검 | 체크리스트에서 다음 미완료 항목 식별 |
| 2. 계획 | 구현 전략을 내부적으로 수립 (텍스트 출력) | `EnterPlanMode`/`ExitPlanMode` 사용 금지 — 비대화형 세션에서 블로킹됨 |
| 3. 구현 → 검증 → 커밋 (반복) | 아래 **구현 루프** 참조 | 단위별로 즉시 커밋+푸시 |
| 4. 코드 리뷰 | `/review` — PRD 준수·메모리 안전성·테스트 커버리지 확인 | 이슈 발견 시 수정 후 재커밋 |
| 5. 메모리 갱신 | `.claude/memory/` 파일 업데이트 | 별도 커밋: `chore: update session memory` → push |
| 6. 세션 요약 | 구조화된 요약 출력 | 아래 템플릿 참조 |

**구현 루프** (Phase 3 상세):

작업을 작은 단위로 분할하고, 각 단위마다 다음을 반복한다:
1. 코드 작성 (하나의 모듈/파일 단위)
2. 테스트 작성 및 `zig build test && zig build integration-test` 통과 확인
3. 즉시 커밋 + `git push` — 다음 단위로 넘어가기 전에 반드시 수행
- 미커밋 변경사항을 여러 파일에 걸쳐 누적하지 않는다
- 한 사이클 내에 완료할 수 없는 작업은 동작하는 중간 상태로 커밋+푸시한다
- `git add -A` 금지 — 변경된 파일을 명시적으로 지정

**작업 선택 규칙**:
- `build.zig`가 없으면 프로젝트 부트스트랩부터 시작
- 이전 세션의 미커밋 변경사항이 있으면: 테스트 통과 시 커밋+푸시, 실패 시 폐기
- 테스트 실패 중이면 새 기능 추가 전에 수정
- 의존성 순서 준수: Config → Graph → Exec → CLI
- 사이클당 하나의 집중 작업만 수행
- 이전 세션의 미완료 작업이 있으면 먼저 완료

**v1.0.0 릴리스 프로토콜**:
- sailor#3 (Windows cross-compile) 해결됨 (sailor v0.5.1)
- 릴리즈 전 필수 작업:
  1. sailor 의존성 v0.5.1로 업데이트: `zig fetch --save git+https://github.com/yusa-imit/sailor`
  2. Windows cross-compile 검증: `zig build -Dtarget=x86_64-windows-msvc -Doptimize=ReleaseSafe`
  3. 전체 테스트 통과 확인
- 릴리즈 절차는 아래 **Release & Patch Policy** 참조

**폴리싱 작업**:
- README 개선: 오타, 불명확한 설명, 누락된 기능 문서화
- 코드 품질: 미사용 코드 제거, 일관성 개선, 에러 메시지 개선
- 테스트 커버리지: 미커버된 엣지 케이스 추가
- 문서: docs/guides/ 보강, 예제 추가
- 성능: 불필요한 할당 제거, 핫 패스 최적화

**세션 요약 템플릿**:

    ## Session Summary
    ### Completed
    - [이번 사이클에서 완료한 내용]
    ### Files Changed
    - [생성/수정된 파일 목록]
    ### Tests
    - [테스트 수, 통과/실패 상태]
    ### Next Priority
    - [다음 사이클에서 작업할 내용]
    ### Issues / Blockers
    - [발생한 문제 또는 미해결 이슈]

### Available Custom Agents

| Agent | Model | File | Purpose |
|-------|-------|------|---------|
| zig-developer | sonnet | `.claude/agents/zig-developer.md` | Zig 코드 구현, 빌드 오류 해결 |
| code-reviewer | sonnet | `.claude/agents/code-reviewer.md` | 코드 리뷰, 품질/보안 검사 |
| test-writer | sonnet | `.claude/agents/test-writer.md` | 유닛/통합 테스트 작성 |
| architect | opus | `.claude/agents/architect.md` | 아키텍처 설계, 모듈 구조 결정 |
| git-manager | haiku | `.claude/agents/git-manager.md` | Git 운영, 브랜치/커밋 관리 |
| ci-cd | haiku | `.claude/agents/ci-cd.md` | GitHub Actions, CI/CD 파이프라인 |

### Available Slash Commands

| Command | File | Purpose |
|---------|------|---------|
| /build | `.claude/commands/build.md` | 프로젝트 빌드 |
| /test | `.claude/commands/test.md` | 테스트 실행 |
| /review | `.claude/commands/review.md` | 현재 변경사항 코드 리뷰 |
| /implement | `.claude/commands/implement.md` | 기능 구현 워크플로우 |
| /fix | `.claude/commands/fix.md` | 버그 수정 워크플로우 |
| /release | `.claude/commands/release.md` | 릴리스 워크플로우 |
| /status | `.claude/commands/status.md` | 프로젝트 상태 확인 |
| /validate | `.claude/commands/validate.md` | 설정 파일 검증 |

---

## Coding Standards

### Zig Conventions

- **Naming**: camelCase for functions/variables, PascalCase for types, SCREAMING_SNAKE for constants
- **Error handling**: Always use explicit error unions, never `catch unreachable` in production code
- **Memory**: Prefer arena allocators for request-scoped work, GPA for long-lived allocations
- **Testing**: Every public function must have corresponding tests in the same file
- **Comments**: Only where logic is non-obvious. No doc comments on self-explanatory functions
- **Imports**: Group stdlib, then project imports, then test imports

### File Organization

- One module per file. PRD Section 7.2의 구조는 초기 참고안이며, 실제 구현에 따라 변경 가능. 소스 코드가 기준
- Keep files under 500 lines; split into submodules if exceeded
- Public API at top of file, private helpers at bottom
- Tests at the bottom of each file within `test` block

### Error Messages

User-facing errors must follow this pattern:
```
✗ [Context]: [What happened]

  [Details with syntax highlighting]

  Hint: [Actionable suggestion]
```

---

## Git Workflow

### Branch Strategy

- `main` — primary development branch
- Feature branches: `feat/<name>`, `fix/<name>`, `refactor/<name>`

### Commit Convention

```
<type>: <subject>

<body>

Co-Authored-By: Claude <noreply@anthropic.com>
```

Types: `feat`, `fix`, `refactor`, `test`, `chore`, `docs`, `perf`, `ci`

### PR Convention

- Title: `<type>: <concise description>` (under 70 chars)
- Body: Summary bullets + Test plan
- Always target `main` unless specified otherwise

---

## Memory System

### Long-Term Memory Preservation

에이전트와 오케스트레이터는 `.claude/memory/` 디렉토리에 장기 기억을 보존한다.

**메모리 파일 구조**:
```
.claude/memory/
├── project-context.md    # 프로젝트 개요 (PRD 요약)
├── architecture.md       # 아키텍처 결정사항
├── decisions.md          # 주요 기술 결정 로그
├── debugging.md          # 디버깅 인사이트, 해결된 문제
├── patterns.md           # 검증된 코드 패턴
└── session-summaries/    # 세션별 요약 (압축된 기억)
```

**메모리 프로토콜**:
1. 세션 시작 시 `.claude/memory/` 파일들을 읽어 컨텍스트 복원
2. 중요한 결정/발견 시 즉시 해당 메모리 파일에 기록
3. 세션 종료 전 `session-summaries/`에 해당 세션의 핵심 내용 요약
4. 메모리 파일이 200줄을 초과하면 핵심만 남기고 압축

**메모리 압축 규칙**:
- 해결된 문제는 1-2줄 요약으로 압축
- 반복 확인된 패턴만 유지, 일회성 발견은 제거
- 최신 정보가 과거 정보보다 우선

---

## Completed Phases (v1.0.0)

All 13 phases from the PRD are **COMPLETE**:

| Phase | Name | Status |
|-------|------|--------|
| 1 | Foundation (MVP) | ✅ TOML parser, DAG, parallel execution, CLI |
| 2 | Workflow & Control | ✅ Workflows, expressions, watch, matrix, profiles |
| 3 | Resource & UX | ✅ TUI, resource limits, shell completion, dry-run |
| 4 | Extensibility | ✅ Plugins (native + WASM), remote cache, Docker |
| 5 | Toolchain Management | ✅ 8 languages, auto-install, PATH injection |
| 6 | Monorepo Intelligence | ✅ Affected detection, graph viz, constraints |
| 7 | Multi-repo & Remote Cache | ✅ S3/GCS/Azure/HTTP, cross-repo tasks |
| 8 | Enterprise & Community | ✅ CODEOWNERS, versioning, analytics, conformance |
| 9 | Infrastructure + DX | ✅ LanguageProvider, JSON-RPC, "Did you mean?" |
| 10 | MCP Server | ✅ 9 tools, `zr init --detect` |
| 11 | LSP Server | ✅ Diagnostics, completion, hover |
| 12 | Performance & Stability | ✅ Binary optimization, fuzz testing, benchmarks |
| 13 | v1.0 Release | ✅ Documentation, migration guides, README |

**Current stats**: 670/678 unit tests (8 skipped), 805/805 integration tests, 0 memory leaks, CI green

---

## Post-v1.0 Development Priorities

### Immediate: Sailor v1.0.2 Migration
- sailor v1.0.2 released (2026-02-28) — zr still uses v0.5.1
- Tasks: update dependency, apply API ref, adopt theme system, remove local TTY workaround
- See Sailor Migration section below for checklist

### Near-term: Quality & Community
- Expand example projects and migration guides
- Community feedback integration (GitHub issues/discussions)
- Performance optimization (hot path profiling)
- TOML parser improvements (stricter validation, better error messages)

### Future: PRD v2.0 Features (not yet scoped)
- Plugin registry index server (currently GitHub-only backend)
- Advanced TUI widgets (Tree, Chart, Dialog, Notification — via sailor v1.0)
- Additional language providers beyond the current 8
- Remote cache improvements (incremental sync, compression)

---

## Quick Reference

```bash
# Build (src/ 생성 후)
zig build

# Test
zig build test

# Integration Test (builds zr binary, then runs black-box CLI tests)
zig build integration-test

# Run (after build)
./zig-out/bin/zr

# Cross-compile (example)
zig build -Dtarget=x86_64-linux -Doptimize=ReleaseSafe

# Clean
rm -rf zig-out .zig-cache
```

---

## Rules for Claude Code

1. **Always read before writing** — 파일 수정 전 반드시 Read로 현재 내용 확인
2. **Test after every change** — 코드 변경 후 `zig build test` 실행
3. **Incremental commits** — 기능 단위로 작은 커밋
4. **Memory updates** — 중요한 발견/결정은 즉시 메모리에 기록
5. **No over-engineering** — 현재 phase에 필요한 것만 구현
6. **PRD is source of truth for requirements** — 기능 요구사항은 `docs/PRD.md` 참조. 단, 파일/폴더 구조(Section 7.2)는 참고안이며 실제 소스 코드가 기준
7. **Team cleanup** — 팀 작업 완료 후 반드시 해산
8. **Error messages matter** — 사용자 경험은 에러 메시지 품질로 결정됨
9. **Stop if stuck** — 동일 에러가 3회 시도 후에도 지속되면 `.claude/memory/debugging.md`에 기록하고 다음 작업으로 이동
10. **No scope creep** — 현재 Phase 체크리스트 범위를 벗어나는 작업 금지
11. **Respect CI** — CI 파이프라인이 존재하면 `ci.yml` 호환성 유지
12. **Never force push** — 파괴적 git 명령어 금지, `main` 브랜치 직접 수정 금지

---

## Release & Patch Policy

### 마이너 릴리즈 (v0.X.0 / v1.0.0)

phase의 모든 모듈이 완성되었을 때 자율적으로 릴리즈를 수행한다.

**릴리즈 조건 (ALL must be true)**:
1. 현재 phase의 체크리스트 항목이 **모두 완료** (`[x]`)
2. `zig build test && zig build integration-test` — 전체 통과, 0 failures
3. 크로스 컴파일 타겟 빌드 성공
4. `bug` 라벨 이슈가 **0개** (open)

**릴리즈 절차**:
1. `build.zig.zon`의 version 업데이트
2. CLAUDE.md phase 체크리스트에 완료 표시
3. 커밋: `chore: bump version to v0.X.0`
4. 태그: `git tag -a v0.X.0 -m "Release v0.X.0: <phase 요약>"`
5. 푸시: `git push && git push origin v0.X.0`
6. GitHub Release: `gh release create v0.X.0 --title "v0.X.0: <phase 요약>" --notes "<릴리즈 노트>"`
7. 관련 이슈 닫기: `gh issue close <number> --comment "Resolved in v0.X.0"`
8. Discord 알림: `openclaw message send --channel discord --target user:264745080709971968 --message "[zr] Released v0.X.0 — <요약>"`

### 패치 릴리즈 (v0.X.Y)

버그 수정 시 패치 릴리즈를 즉시 발행한다.

**트리거 조건**:
- 사용자 보고 버그가 수정된 커밋이 존재하지만 릴리즈 태그가 없을 때
- 빌드/테스트 실패를 수정한 커밋
- 크로스 컴파일 깨짐을 수정한 커밋

**패치 vs 마이너 판단**:
- 버그 수정만 포함 → PATCH (v0.X.Y)
- 새 기능 포함 → MINOR (v0.X+1.0)

**버전 규칙**:
- PATCH 번호만 증가 (예: v0.1.0 → v0.1.1)
- `build.zig.zon` version 수정 불필요 — 태그만으로 충분
- 기능 커밋을 패치에 포함하지 않음

**패치 릴리즈 절차**:
1. 버그 수정 커밋 식별
2. `zig build test && zig build integration-test` 통과 확인
3. 태그: `git tag -a v0.X.Y <commit-hash> -m "Release v0.X.Y: <수정 요약>"`
4. 푸시: `git push origin v0.X.Y`
5. GitHub Release: `gh release create v0.X.Y --title "v0.X.Y: <요약>" --notes "<릴리즈 노트>"`
6. 관련 이슈에 릴리즈 코멘트 추가
7. Discord 알림

---

## Sailor Migration

zr은 `sailor` 라이브러리(https://github.com/yusa-imit/sailor)를 점진적으로 도입한다.
각 버전이 READY 상태가 되면, 해당 세션에서 마이그레이션을 수행한다.

### 마이그레이션 프로토콜

1. 세션 시작 시 이 섹션을 확인한다
2. `status: READY`인 미완료 마이그레이션이 있으면, 현재 작업보다 **우선** 수행한다
3. 마이그레이션 완료 후 `status: DONE`으로 변경하고 커밋한다
4. `zig build test && zig build integration-test` 통과 확인 필수

### sailor 이슈 발행 프로토콜

sailor 라이브러리를 사용하는 중 버그를 발견하거나, 필요한 기능이 없을 때 GitHub Issue를 발행한다.

**버그 발행**:
```bash
gh issue create --repo yusa-imit/sailor \
  --title "bug: <간단한 설명>" \
  --label "bug,from:zr" \
  --body "## 증상
<어떤 문제가 발생했는지>

## 재현 방법
<코드 또는 단계>

## 기대 동작
<어떻게 동작해야 하는지>

## 환경
- sailor 버전: <version>
- Zig 버전: 0.15.2
- OS: <os>"
```

**기능 요청 발행**:
```bash
gh issue create --repo yusa-imit/sailor \
  --title "feat: <필요한 기능>" \
  --label "feature-request,from:zr" \
  --body "## 필요한 이유
<zr에서 왜 이 기능이 필요한지>

## 제안하는 API
<원하는 함수 시그니처나 사용 예시>

## 현재 워크어라운드
<없으면 '없음'>"
```

**발행 조건**:
- sailor의 기존 API로 해결할 수 없는 문제일 때만 발행
- 동일한 이슈가 이미 열려있는지 먼저 확인: `gh issue list --repo yusa-imit/sailor --state open --search "<keyword>"`
- 이슈 발행 후 현재 작업으로 복귀 (sailor 수정을 직접 하지 않음)

**로컬 워크어라운드 금지 (CRITICAL)**:
- sailor에 버그가 있으면 **절대로 로컬에서 자체 구현으로 우회하지 않는다**
- 반드시 sailor repo에 이슈를 발행하고, sailor 에이전트가 수정할 때까지 기다린다
- sailor 에이전트(cron job)가 `from:*` 라벨 이슈를 최우선으로 처리한다
- 수정이 릴리스되면 `zig fetch --save`로 sailor 의존성을 업데이트한다
- 해당 기능이 아직 안 되면 그 기능을 사용하는 코드를 작성하지 않고 다른 작업으로 넘어간다
- 예시: sailor.tui의 Style.apply()가 Zig 0.15.2에서 컴파일 안 됨 → 이슈 발행 (#5) → 수정될 때까지 Style.apply()를 사용하는 코드 작성하지 않음

### v0.1.0 — arg, color (status: DONE)

- [x] `build.zig.zon`에 sailor v0.4.0 의존성 추가 (`f09ea11`)
- [x] `build.zig`에서 sailor 모듈 import 설정 (`f09ea11`)
- [x] `src/main.zig`의 hand-rolled arg parsing → `sailor.arg` 교체 (`ac681a2`)
- [x] `src/output/color.zig` → `sailor.color` 래퍼로 전환 (`6200809`)
- [x] 기존 테스트 전체 통과 확인 (676 unit + 805 integration)

### v0.2.0 — progress (status: DONE)

- [x] `src/output/progress.zig` → `sailor.progress` 래퍼로 전환 (`4b9c8cf`)
- [x] 기존 테스트 전체 통과 확인

### v0.3.0 — fmt (status: DONE)

- [x] `--format json` 출력 로직 → `sailor.fmt.json` 활용 (`263ef3b`)
- [x] 기존 테스트 전체 통과 확인

### v0.4.0 — tui (status: DONE)

- [x] `src/cli/tui.zig` → `sailor.tui` 위젯 기반으로 재작성 (`280e26b`)
- [x] `src/cli/tui_runner.zig` → `sailor.tui` 레이아웃 + List/Block 위젯
- [x] 기존 테스트 전체 통과 확인
- **Note**: sailor.tui의 `Style.apply()` → Zig 0.15.2 `adaptToNewApi` 비호환. 해결: sailor Buffer로 compose, 렌더링은 `color.Code.*` ANSI 상수 사용

### v0.5.0 — advanced widgets (status: DEPENDENCY UPDATED, widgets deferred)

- [x] `build.zig.zon`에 sailor v0.5.1 의존성 업데이트 (`ab9441f`)
- [x] Windows cross-compile 검증 (sailor#3 해결)
- [x] 기존 테스트 전체 통과 확인 (670 unit, 792 integration)
- **Note**: Advanced widget features (Tree, Chart, Dialog, Notification) are optional enhancements beyond v1.0.0 scope. To be implemented in future versions when needed.
- Local TTY detection kept in color.zig (sailor.term.isatty() doesn't handle std.fs.File cross-compile)

### v1.0.0 — production ready (status: READY)

**sailor v1.0.2 released** (2026-02-28) — latest stable, includes cross-compile fix + example fixes

- **Major upgrade**: Full TUI framework, theme system, animations, comprehensive API
- [ ] `build.zig.zon`에 sailor v1.0.2 의존성 업데이트: `zig fetch --save git+https://github.com/yusa-imit/sailor#v1.0.2`
- [ ] [Getting Started Guide](https://github.com/yusa-imit/sailor/blob/v1.0.2/docs/GUIDE.md) 참조하여 모범 사례 적용
- [ ] [API Reference](https://github.com/yusa-imit/sailor/blob/v1.0.2/docs/API.md) 기반으로 기존 코드 리팩토링
- [ ] 로컬 TTY workaround 제거 (color.zig) — sailor v1.0.x에서 수정됨
- [ ] 테마 시스템 활용: 라이트/다크 모드 또는 커스텀 컬러 스킴
- [ ] 애니메이션 효과 추가 (선택사항): 프로그레스, 로딩 스피너
- [ ] 기존 테스트 전체 통과 확인
