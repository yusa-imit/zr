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

**9단계 실행 사이클**:

| Phase | 내용 | 비고 |
|-------|------|------|
| 1. 상태 파악 | `/status` 실행, git log·빌드·테스트 상태 점검 | CLAUDE.md에서 다음 작업 식별 |
| 1.5. 이슈 확인 | `gh issue list --state open --limit 10` | 아래 **이슈 우선순위 프로토콜** 참조 |
| 2. 계획 | 구현 전략을 내부적으로 수립 (텍스트 출력) | `EnterPlanMode`/`ExitPlanMode` 사용 금지 — 비대화형 세션에서 블로킹됨 |
| 3. 구현 → 검증 → 커밋 (반복) | 아래 **구현 루프** 참조 | 단위별로 즉시 커밋+푸시 |
| 4. 코드 리뷰 | `/review` — PRD 준수·메모리 안전성·테스트 커버리지 확인 | 이슈 발견 시 수정 후 재커밋 |
| 5. 릴리즈 판단 | 릴리즈 조건 충족 시 **자동 릴리즈** | 아래 **Release & Patch Policy** 참조 |
| 6. 메모리 갱신 | `.claude/memory/` 파일 업데이트 | 별도 커밋: `chore: update session memory` → push |
| 7. 세션 요약 | 구조화된 요약 출력 | 아래 템플릿 참조 |

**구현 루프** (Phase 3 상세):

작업을 작은 단위로 분할하고, 각 단위마다 다음을 반복한다:
1. 코드 작성 (하나의 모듈/파일 단위)
2. 테스트 작성 및 `zig build test && zig build integration-test` 통과 확인
3. 즉시 커밋 + `git push` — 다음 단위로 넘어가기 전에 반드시 수행
- 미커밋 변경사항을 여러 파일에 걸쳐 누적하지 않는다
- 한 사이클 내에 완료할 수 없는 작업은 동작하는 중간 상태로 커밋+푸시한다
- `git add -A` 금지 — 변경된 파일을 명시적으로 지정

**작업 선택 규칙**:
- 이전 세션의 미커밋 변경사항이 있으면: 테스트 통과 시 커밋+푸시, 실패 시 폐기
- 테스트 실패 중이면 새 기능 추가 전에 수정
- 사이클당 하나의 집중 작업만 수행
- 이전 세션의 미완료 작업이 있으면 먼저 완료
- Post-v1.0 우선순위: Sailor Migration (READY) > Bug 이슈 > Post-v1.0 Priorities 항목

**이슈 우선순위 프로토콜** (Phase 1.5):

세션 시작 시 GitHub Issues를 확인하고 우선순위를 결정한다:

```bash
gh issue list --state open --limit 10 --json number,title,labels,createdAt
```

| 우선순위 | 조건 | 행동 |
|---------|------|------|
| 1 (최우선) | `bug` 라벨 | 다른 작업보다 **항상 우선** 처리 |
| 2 (높음) | `feature-request` + 현재 우선순위 범위 내 | 현재 작업과 **병행** |
| 3 (낮음) | `feature-request` + 미래 범위 | **적어두고 넘어감** |

- 이슈 처리 후: `gh issue close <number> --comment "Fixed in <commit-hash>"`
- 진행 상황 공유: `gh issue comment <number> --body "Working on this"`

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

**Current stats**: 716/724 unit tests (8 skipped), 837/837 integration tests, 0 memory leaks, CI green

---

## Post-v1.0 Milestones

마일스톤 하나가 완료되면 마이너 릴리즈를 발행한다. (Release & Patch Policy 참조)
마일스톤이 2개 이하로 남으면 **마일스톤 수립 프로세스**를 실행하여 보충한다.

- [x] **v1.1.0 — Sailor v1.0.2 Migration** (DONE): 의존성 업데이트, API 리팩토링, 로컬 TTY workaround 유지, 테마 시스템 검토
- [x] **v1.2.0 — TOML Parser Improvements** (DONE): 엄격한 검증, malformed section 헤더 감지, 에러 메시지 개선
- [x] **v1.3.0 — TUI Graph Visualization** (DONE): Tree widget 기반 그래프 TUI 모드, sailor v1.0.3 마이그레이션
- [x] **v1.4.0 — Plugin Registry Client** (DONE, released 2026-03-02): HTTP client, 원격 검색 `--remote` 플래그, 우아한 폴백, 통합 테스트, API 문서
- [x] **v1.5.0 — Remote Cache v2** (DONE, released 2026-03-02): gzip 압축, 증분 동기화, 캐시 통계 대시보드
- [x] **v1.6.0 — Interactive Configuration** (DONE, released 2026-03-02): `zr add task/workflow/profile` 대화형 명령어, 스마트 stdin 처리, 통합 테스트 (6개), issue #11 해결
- [x] **v1.7.0 — Performance Enhancements** (DONE, released 2026-03-02): 문자열 인터닝 (StringPool), 객체 풀링 (ObjectPool), hyperfine 기반 자동화 벤치마크 스크립트, 30-50% 메모리 감소
- [x] **v1.8.0 — Toolchain Auto-Update** (DONE, released 2026-03-02): `zr tools upgrade --check-updates`, `--cleanup` 플래그로 버전 충돌 자동 해결
- [x] **v1.9.0 — Sailor v1.1.0 Accessibility** (DONE, released 2026-03-02): Unicode width 개선 (CJK/emoji), TUI 키보드 내비게이션, 접근성 기능 (위치 표시, 의미론적 레이블, 푸터 상태)
- [x] **v1.10.0 — Task Dependencies v2** (DONE, released 2026-03-02): 조건부 의존성 (`deps_if`), 선택적 의존성 (`deps_optional`), 표현식 엔진 통합, 16 unit tests + 5 integration tests
- [x] **v1.11.0 — Plugin Registry Index Server** (DONE): 독립 인덱스 서버 구축 (GitHub 의존성 제거), REST API, 플러그인 메타데이터, 검색 엔드포인트, `zr registry serve` 명령어, JSON 파일 기반 저장소, 2 integration tests
- [x] **v1.12.0 — TOML Parser v2** (DONE, released 2026-03-03): Auto-generate stage names for anonymous `[[workflows.name.stages]]`, 검증 경고 제거, 3 unit tests + 3 integration tests
- [x] **v1.13.0 — Parallel Execution Optimizations** (DONE): Work-stealing deque, NUMA topology detection, cross-platform CPU affinity, cpu_affinity/numa_node task fields, scheduler integration, documentation
- [x] **v1.14.0 — Enhanced Error Diagnostics**: Task execution timeline, failure replay mode (expression stack traces deferred to v1.15.0)
- [x] **v1.15.0 — Workspace Enhancements**: Workspace-wide cache invalidation, member-specific cache clearing, sailor v1.5.0 migration
- [x] **v1.16.0 — Task Execution Analytics**: DONE (2026-03-07) — Resource usage tracking (peak memory, avg CPU), enhanced analytics reports (HTML/JSON), 2 integration tests, documentation updated, all 875 tests pass
- [x] **v1.17.0 — Advanced Watch Mode** (RELEASED 2026-03-08): Debouncing for rapid file changes (configurable delay), pattern-based watch filters (glob patterns for file inclusion/exclusion), multi-pattern watch support (watch multiple paths per task), watch mode configuration in zr.toml ([tasks.*.watch] section), integration with existing native file watchers
  - ✅ WatchConfig struct (debounce_ms, patterns, exclude_patterns, mode) — 97779fd
  - ✅ TOML parser support for [tasks.*.watch] section — cabca59
  - ✅ Enhanced watcher with debouncing and pattern filtering — e7fb3cc
  - ✅ CLI integration (run.zig watch mode) — e7fb3cc
  - ✅ Unit tests: 3 new tests for pattern filtering — e7fb3cc
  - ✅ Integration tests: 9 tests (watch_test.zig) — 51f3da2
  - ✅ Documentation: Complete guide in configuration.md — 611669b
  - Tests: 746/754 unit (8 skipped, 0 leaks), 881/881 integration (100%)
- [x] **v1.18.0 — Conditional Task Execution** (RELEASED 2026-03-08): Extended expression engine with git predicates (git.branch, git.tag, git.dirty), task skip conditions (skip_if field), conditional outputs (output_if). Note: Comprehensive error diagnostics deferred to v1.20.0 (Expression Diagnostics Integration)
  - ✅ Git predicates: git.branch, git.tag, git.dirty with != operator — 8209382, 1fc6f16
  - ✅ skip_if evaluation in scheduler — ca2acf8
  - ✅ output_if evaluation in scheduler — ca2acf8
  - ✅ Parser fixes (state bleed, git predicate operators) — 1fc6f16
  - ✅ Integration tests (9 tests: 882-890) — 8209382
  - ✅ CI fix (git init default branch) — d81cd2d
  - Tests: 746/754 unit (8 skipped, 0 leaks), 890/890 integration (100%)
- [x] **v1.19.0 — Parser Enhancements v3** (DONE, released 2026-03-09): Inline workflow stages syntax (`stages = [{ name, tasks }]`, closes #19), dependency-only tasks without cmd field (closes #20), subsection ordering fix (allows [tasks.X.matrix/env/toolchain] before main section), unit tests (417, 420, 421 passing)
  - ✅ Inline workflow stages syntax — b7418c0
  - ✅ Cmd-less dependency tasks — b7418c0
  - ✅ Subsection ordering fix — 714341a
  - Tests: 750/758 unit (8 skipped, 0 leaks), 894/894 integration (100%)
- [x] **v1.20.0 — Expression Diagnostics Integration** (DONE, released 2026-03-09): Integrate expr_diagnostics.zig into expression evaluator, refactor 17 eval functions to accept DiagContext parameter, enhanced stack traces for expression failures, expression debugging documentation
  - ✅ Add diag parameter to ExprContext struct — 614fe90
  - ✅ New public API evalConditionWithDiag() accepting optional DiagContext — 614fe90
  - ✅ Push/pop stack tracking in all 17 eval functions — 614fe90
  - ✅ Expression Debugging guide in configuration.md — 30c2372
  - Tests: 750/758 unit (8 skipped, 0 leaks), 894/894 integration (100%)
- [x] **v1.21.0 — TUI Testing & Enhancements**: DONE (RELEASED 2026-03-09) — MockTerminal snapshot tests for all TUI modes (runner, graph, list), 19 new unit tests, documentation updated. Event bus and command pattern deferred to future versions as optional enhancements.
- [x] **v1.22.0 — Sailor v1.6.0 & v1.7.0 Migration**: DONE (RELEASED 2026-03-09) — Upgraded sailor from v1.5.0 to v1.7.0. New features: data visualization widgets (ScatterPlot, Histogram, TimeSeriesChart), advanced layout (FlexBox, viewport clipping, shadow effects, layout caching). All features are opt-in and non-breaking. Tests: 769/777 unit (8 skipped, 0 leaks), 894/894 integration (100%)
- [x] **v1.23.0 — Shell Auto-Completion v2**: DONE (2026-03-10) — Enhanced shell completion with context-aware suggestions (dynamic task names from zr.toml, profile name completion via `zr list --profiles`, workspace member completion via `zr list --members`), improved flag completion for --profile/-p with dynamic suggestions, support for bash/zsh/fish with helper functions, 2 new unit tests, all 771 unit tests + 894 integration tests pass
- [x] **v1.24.0 — Execution Hooks**: DONE (2026-03-11) — Pre/post task hooks (on_before, on_after, on_success, on_failure, on_timeout), complete TOML parser support, scheduler integration, memory leak fixes (GPA cleanup, test leaks fixed), Tests: 780/788 unit (8 skipped, 0 leaks), 905/906 integration (100%, 0 leaks)
- [x] **v1.25.0 — Interactive TUI Config Editor**: DONE (2026-03-11) — Interactive prompt-based config editor with `zr edit task/workflow/profile` commands, field validation (required/optional), context-sensitive help hints, live TOML preview, auto-append to zr.toml, Tests: 780/788 unit (8 skipped), 905/906 integration (100%). Note: Simple prompts implementation (full TUI widgets deferred until sailor provides Form API)
- [x] **v1.26.0 — Language Provider Expansion**: DONE (2026-03-11) — Added C# (.NET) and Ruby providers (Go, Rust, Java already existed). C# provider: dotnet SDK, NuGet, common tasks (build/test/restore/publish/watch). Ruby provider: Gemfile, Rake, RSpec, Rails detection. Both: auto-detection, version management, PATH injection. Example projects: csharp-dotnet/, ruby-rails/. Integration tests: 4 new tests (912-915). Documentation: examples/README.md updated. Tests: 786/794 unit (8 skipped), 914/915 integration (1 skipped). Commits: df9ffd7, b0fcf85, be40b3a
- [x] **v1.27.0 — Real-time Resource Monitoring**: DONE (2026-03-12) — Live TUI dashboard component (src/cli/monitor.zig) with ASCII bar charts for CPU/memory, task status table, bottleneck detection. Tests: 796/804 unit (8 skipped, 0 leaks), 919/920 integration (1 skipped). Commits: 5f558a0 (monitor TUI), 1ec1b33 (integration tests), 94dd2ea (infrastructure). Note: Remote monitoring server (WebSocket) deferred to v1.31.0
- [x] **v1.28.0 — Interactive TUI with Mouse Support**: COMPLETE (2026-03-12) — Leveraged sailor v1.10.0 mouse input features
  - ✅ src/cli/tui_mouse.zig — Mouse event parsing module (SGR protocol, InputEvent union, enable/disable tracking) — 42e70ac
  - ✅ Mouse click support for task selection in interactive picker (tui.zig) — 41e2a00
  - ✅ Clickable graph nodes in graph TUI (graph_tui.zig) with scroll support — 7f45b2c
  - ✅ Mouse click for task switching and scroll for logs in live execution TUI (tui_runner.zig) — 4857058
  - ✅ Unit tests: 5 tests in tui_mouse.zig, existing MockTerminal tests in graph_tui.zig
  - ✅ Documentation: Updated commands.md with navigation instructions for all TUI modes — a5672fc
  - Tests: 801/809 unit (8 skipped, 0 leaks), 919/920 integration (1 skipped, 0 leaks)
- [ ] **v1.29.0 — Task Template System**: Reusable task templates with parameter substitution (`template = "test-watch"`, `params = { port = 3000 }`), template inheritance (base templates + overrides), template validation (required params, type checking), built-in templates (test-watch, build-deploy, lint-fix, docker-compose), template registry (local + remote templates), `zr template list/show/apply` commands, integration tests, documentation
- [ ] **v1.30.0 — Enhanced Error Recovery**: Automatic retry with exponential backoff for network failures (configurable per-task retry policies, retry budget limits, circuit breaker pattern), checkpoint/resume for long-running tasks (save progress at configurable intervals, resume from last checkpoint on failure, checkpoint storage backends), rollback hooks for cleanup on failure (undo database migrations, cleanup temp files, restore state), integration tests, documentation

### 마일스톤 수립 프로세스

미완료 마일스톤이 **2개 이하**가 되면, 에이전트가 자율적으로 새 마일스톤을 수립한다.

**입력 소스** (우선순위 순):
1. `gh issue list --state open --label feature-request` — 사용자 요청 기능
2. `docs/PRD.md` — 아직 구현되지 않은 PRD 항목 (Phase 5-8의 미구현 세부사항)
3. 의존성 업데이트 — sailor, Zig 새 버전 등
4. 기술 부채 — Known Limitations, TODO, 성능 병목
5. 경쟁 도구 분석 — just, task, make 대비 누락된 기능

**수립 규칙**:
- 마일스톤 하나는 **단일 테마**로 구성 (여러 작은 기능을 하나의 주제로 묶음)
- 1-2주 내 완료 가능한 범위로 스코프 설정
- 버전 번호는 마지막 마일스톤의 다음 번호로 자동 부여
- 수립 후 이 섹션의 체크리스트에 추가하고 커밋: `chore: add milestone v1.X.0`

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

세션 사이클의 **Step 5 (릴리즈 판단)** 에서 아래 조건을 확인하고, 충족 시 자율적으로 릴리즈를 수행한다.

### 릴리즈 판단 기준 (Step 5에서 매 세션 확인)

**패치 릴리즈 (v1.0.X)** — 다음 중 하나라도 해당하면 즉시 발행:
- 사용자 보고 버그(`bug` 라벨 이슈)를 수정한 커밋이 마지막 릴리즈 태그 이후에 존재
- 빌드/테스트 실패 또는 크로스 컴파일 깨짐을 수정한 커밋
- 설치 스크립트, 문서의 치명적 오류 수정

**마이너 릴리즈 (v1.X.0)** — **마일스톤 완료** 시 발행. 다음 조건을 **모두** 충족:
1. 아래 **마일스톤 체크리스트**에서 하나의 항목이 **완료** 표시됨
2. 해당 마일스톤의 기능에 대한 **테스트가 작성**되어 있음
3. `zig build test && zig build integration-test` — 전체 통과, 0 failures
4. `bug` 라벨 이슈가 **0개** (open)

**메이저 릴리즈 (v2.0.0)** — 사용자 명시적 지시 시에만 (Breaking changes)

### 릴리즈 조건 확인 방법

```bash
# 마지막 릴리즈 태그 이후 커밋 확인
LAST_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "")
git log ${LAST_TAG}..HEAD --oneline

# 버그 이슈 확인
gh issue list --state open --label bug --limit 5
```

- 마지막 태그 이후 커밋이 없으면 → 릴리즈 불필요, 스킵
- `fix:` 커밋만 있으면 → PATCH 릴리즈
- 마일스톤 체크리스트 항목 완료 → MINOR 릴리즈 (bug 이슈 0개 확인 필수)

### 릴리즈 절차

**패치 (v1.0.X)**:
1. `zig build test && zig build integration-test` 통과 확인
2. 태그: `git tag -a v1.0.X -m "Release v1.0.X: <수정 요약>"`
3. 푸시: `git push origin v1.0.X`
4. GitHub Release: `gh release create v1.0.X --title "v1.0.X: <요약>" --notes "<릴리즈 노트>"`
5. 관련 이슈 닫기
6. Discord 알림

**마이너 (v1.X.0)**:
1. CLAUDE.md 마일스톤 체크리스트에서 해당 항목 `[x]` 완료 표시
2. `build.zig.zon`의 version 업데이트
3. CHANGELOG.md에 릴리즈 항목 추가
4. 커밋: `chore: bump version to v1.X.0`
5. `zig build test && zig build integration-test` 통과 확인
6. 태그: `git tag -a v1.X.0 -m "Release v1.X.0: <요약>"`
7. 푸시: `git push && git push origin v1.X.0`
8. GitHub Release: `gh release create v1.X.0 --title "v1.X.0: <요약>" --notes "<릴리즈 노트>"`
9. 관련 이슈 닫기
10. Discord 알림: `openclaw message send --channel discord --target user:264745080709971968 --message "[zr] Released v1.X.0 — <요약>"`
11. **마일스톤 보충**: 미완료 마일스톤이 2개 이하이면 **마일스톤 수립 프로세스** 실행

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

### v1.0.0 — production ready (status: DONE)

**sailor v1.0.2 released** (2026-02-28) — latest stable, includes cross-compile fix + example fixes

- **Major upgrade**: Full TUI framework, theme system, animations, comprehensive API
- [x] `build.zig.zon`에 sailor v1.0.2 의존성 업데이트 (`d16289b`)
- [x] [Getting Started Guide](https://github.com/yusa-imit/sailor/blob/v1.0.2/docs/GUIDE.md) 참조하여 모범 사례 적용 — 현재 zr 구현이 이미 모범 사례 준수
- [x] [API Reference](https://github.com/yusa-imit/sailor/blob/v1.0.2/docs/API.md) 기반으로 기존 코드 리팩토링 — API 호환성 확인 완료
- [x] 로컬 TTY workaround 유지 (color.zig) — sailor.term.isatty()는 posix.fd_t 사용, Windows VT 활성화는 여전히 zr에서 처리 필요
- [x] 테마 시스템 검토 — sailor.tui.theme 제공 (6개 내장 테마), zr CLI는 현재 구현으로 충분 (TUI 전용 기능)
- [x] 기존 테스트 전체 통과 확인 (670 unit, 805 integration)
- **Note**: Theme system and animations are part of `sailor.tui` (TUI apps), not applicable to zr's CLI output which uses `sailor.color` directly

### v1.0.3 — bug fix release (status: DONE)

**sailor v1.0.3 released** (2026-03-02) — Zig 0.15.2 compatibility patch

- **Bug fix**: Tree widget ArrayList API updated for Zig 0.15.2
- **Impact on zr**: None (zr doesn't use Tree widget yet)
- [x] `build.zig.zon`에 sailor v1.0.3 의존성 업데이트 (✓ complete, no breaking changes)
- [x] 기존 테스트 전체 통과 확인 (670/678 unit, 810/810 integration)

**Note**: Optional upgrade completed. Tree widget fix doesn't affect zr's current functionality, but unblocks future v1.3.0 TUI widgets milestone.

### v1.1.0 — Accessibility & Internationalization (status: DONE)

**sailor v1.1.0 released** (2026-03-02) — Accessibility and i18n features

- **New features**:
  - Accessibility module (screen reader hints, semantic labels)
  - Focus management system (tab order, focus ring)
  - Keyboard navigation protocol (custom key bindings)
  - Unicode width calculation (CJK, emoji proper sizing)
  - Bidirectional text support (RTL rendering for Arabic/Hebrew)
- **Impact on zr**: Low priority for CLI tool, but beneficial for future TUI features
  - Unicode width fixes improve CJK character display in TUI mode
  - Keyboard navigation useful for future interactive TUI widgets
- [x] `build.zig.zon`에 sailor v1.1.0 의존성 업데이트 (2026-03-02)
- [x] 기존 테스트 전체 통과 확인 (685 unit, 819 integration)
- [ ] (Optional) Consider keyboard bindings for TUI graph mode — deferred to future TUI enhancements

**Note**: Non-breaking upgrade. Accessibility features are opt-in. Unicode width improvements automatically benefit any CJK/emoji display.

### v1.2.0 — Layout & Composition (status: DONE)

**sailor v1.2.0 released** (2026-03-02) — Advanced layout and composition features

- **New features**:
  - Grid layout system (CSS Grid-inspired 2D constraint solver)
  - ScrollView widget (virtual scrolling for large content)
  - Overlay/z-index system (non-modal popups, tooltips, dropdown menus)
  - Widget composition helpers (split panes, resizable borders)
  - Responsive breakpoints (adaptive layouts based on terminal size)
- **Impact on zr**: Medium priority — enables advanced TUI layouts
  - Grid layout useful for complex dashboard layouts in TUI graph mode
  - ScrollView enables handling large task lists in TUI
  - Split panes for side-by-side views (graph + logs)
  - Responsive breakpoints for adaptive layouts on different terminal sizes
- [x] `build.zig.zon`에 sailor v1.2.0 의존성 업데이트 (2026-03-02)
- [ ] (Optional) Consider using Grid layout for TUI graph dashboard — deferred to future TUI enhancements
- [ ] (Optional) Add ScrollView for large task lists in TUI mode — deferred to future TUI enhancements
- [x] 기존 테스트 전체 통과 확인 (685 unit, 819 integration)

**Note**: Non-breaking upgrade. Layout features are opt-in. Current TUI implementation doesn't require immediate migration, but these features enable future enhancements.

### v1.3.0 — Performance & Developer Experience (status: DONE)

**sailor v1.3.0 released** (2026-03-02) — Performance optimization and debugging tools

- **New features**:
  - RenderBudget: Frame time tracking with automatic frame skip for 60fps
  - LazyBuffer: Dirty region tracking (only render changed cells)
  - EventBatcher: Coalesce rapid events (resize storms, key bursts)
  - DebugOverlay: Visual debugging (layout rects, FPS, event log)
  - ThemeWatcher: Hot-reload JSON themes without restart
- **Impact on zr**: Medium priority — improves TUI performance
  - Lazy rendering reduces overhead for large graphs (skip unchanged cells)
  - Event batching handles terminal resize gracefully
  - DebugOverlay useful for developing TUI features
  - ThemeWatcher enables live theme iteration
- [x] `build.zig.zon`에 sailor v1.3.0 의존성 업데이트 (2026-03-02)
- [x] 기존 테스트 전체 통과 확인 (716 unit, 837 integration)
- [ ] (Optional) Add DebugOverlay toggle for TUI development — deferred to future TUI enhancements

**Note**: Non-breaking upgrade. Performance features are opt-in. Current TUI implementation automatically benefits from event batching improvements without code changes.

**Note**: Non-breaking upgrade. Performance features are opt-in. Current CLI mode unaffected. TUI mode can benefit from lazy rendering when displaying large graphs.

### v1.4.0 — Advanced Input & Forms (status: DONE)

**sailor v1.4.0 released** (2026-03-03) — Form widgets and input validation

- **New features**:
  - Form widget: Field validation, submit/cancel handlers, error display
  - Select/Dropdown widget: Single/multi-select with keyboard navigation
  - Checkbox widget: Single and grouped checkboxes with state management
  - RadioGroup widget: Mutually exclusive selection
  - Validators module: Comprehensive input validation (email, URL, IPv4, numeric, patterns)
  - Input masks: SSN, phone, dates, credit card formatting
- **Impact on zr**: Low-Medium priority — enables interactive config editing
  - Form widget useful for interactive configuration editor TUI
  - Validators useful for validating task parameters in TUI mode
  - Checkbox/RadioGroup for task selection and filtering UI
  - Select widget for choosing targets, toolchains, cache backends
- [x] `build.zig.zon`에 sailor v1.4.0 의존성 업데이트 (2026-03-06, commit dc3d07d)
- [ ] (Optional) Add interactive config editor TUI using Form widget — deferred to future enhancements
- [ ] (Optional) Use Select widget for task picker in TUI mode — deferred to future enhancements
- [x] 기존 테스트 전체 통과 확인 (733 unit, 859 integration)

**Note**: Non-breaking upgrade. Form features are opt-in. Current CLI/TUI implementation works without changes. These features enable future interactive configuration and task selection UIs.

### v1.5.0 — State Management & Testing (status: DONE)

**sailor v1.5.0 released** (2026-03-07) — Testing utilities and state management

- **New features**:
  - Widget snapshot testing: assertSnapshot() method for pixel-perfect verification
  - Example test suite: 10 comprehensive integration test patterns
  - Previously released: Event bus, Command pattern, MockTerminal, EventSimulator
- **Impact on zr**: HIGH — Critical for TUI testing
  - MockTerminal available for future TUI unit tests (not yet integrated)
  - assertSnapshot() can verify exact rendering output
  - Example test patterns serve as reference for zr's TUI test expansion
  - Event bus useful for cross-component TUI communication (future)
  - Command pattern enables undo/redo in TUI (future interactive features)
- [x] `build.zig.zon`에 sailor v1.5.0 의존성 업데이트 (2026-03-07)
- [x] Review example test patterns for improving zr's TUI test suite
- [x] 기존 테스트 전체 통과 확인 (743 unit, 873 integration)

**Note**: Non-breaking upgrade. Testing utilities are opt-in. Current tests work without changes. This release provides better tools for TUI test coverage expansion.

### v1.6.0 — Data Visualization & Advanced Charts (status: READY)

**sailor v1.6.0 released** (2026-03-08) — Advanced data visualization widgets

- **New features**:
  - ScatterPlot: X-Y coordinate plotting with markers and multiple series
  - Histogram: Frequency distribution bars (vertical/horizontal)
  - TimeSeriesChart: Time-based line chart with Unix timestamp support
  - Heatmap & PieChart (previously released in v1.5.0)
- **Impact on zr**: LOW — Optional for future analytics
  - Histogram useful for task duration distributions
  - TimeSeriesChart for build time trends over time
  - ScatterPlot for cache hit rate vs. build time correlation
  - Not critical for current functionality
- [ ] `build.zig.zon`에 sailor v1.6.0 의존성 업데이트
- [ ] 기존 테스트 전체 통과 확인

**Note**: Non-breaking upgrade. All widgets are opt-in. No immediate action required.

### v1.7.0 — Advanced Layout & Rendering (status: READY)

**sailor v1.7.0 released** (2026-03-09) — Advanced layout and rendering features

- **New features**:
  - FlexBox layout: CSS flexbox-inspired with justify/align (16 tests)
  - Viewport clipping: Efficient rendering of large virtual buffers (14 tests)
  - Shadow & 3D border effects: Visual depth for widgets (15 tests)
  - Custom widget traits: Extensible widget protocol
  - Layout caching: LRU cache for constraint computation (13 tests)
- **Impact on zr**: MEDIUM — Layout improvements for future TUI enhancements
  - FlexBox useful for responsive task list layouts
  - Viewport clipping enables efficient log/output scrolling
  - Shadow effects add visual polish to TUI mode
  - Layout caching improves performance for complex dashboards
- [ ] `build.zig.zon`에 sailor v1.7.0 의존성 업데이트
- [ ] 기존 테스트 전체 통과 확인

**Note**: Non-breaking upgrade. All features are opt-in. No immediate action required.

### v1.8.0 — Network & Async Integration (status: READY)

**sailor v1.8.0 released** (2026-03-10) — Network and async widgets

- **New features**:
  - HttpClient widget: Download progress visualization with speed/stats (16 tests)
  - WebSocket widget: Live data feed with auto-scroll (16 tests)
  - AsyncEventLoop: Non-blocking I/O for network operations (8 tests)
  - TaskRunner widget: Parallel operation status indicator (20 tests)
  - LogViewer widget: Tail -f style with filtering and search (20 tests)
- **Impact on zr**: LOW — Network widgets not currently needed for local task runner
  - AsyncEventLoop useful for future remote task execution features
  - TaskRunner could replace custom progress tracking in parallel mode
  - LogViewer could display task output logs in TUI mode
- [ ] `build.zig.zon`에 sailor v1.8.0 의존성 업데이트
- [ ] 기존 테스트 전체 통과 확인

**Note**: Non-breaking upgrade. All features are opt-in. No immediate action required.

### v1.9.0 — Developer Tools & Ecosystem (status: DONE)

**sailor v1.9.0 released** (2026-03-11) — Developer tools and ecosystem improvements

- **New features**:
  - WidgetDebugger: Widget tree inspection with layout bounds visualization
  - PerformanceProfiler: Frame timing & memory profiling with histogram display
  - CompletionPopup: REPL tab completion popup (resolves repl.zig TODO)
  - ThemeEditor: Live theme customization with RGB editing and preview (18 tests)
  - Widget Gallery: Comprehensive catalog of 40+ widgets across 7 categories
- **Impact on zr**: MEDIUM — Debugging and profiling tools useful for TUI development
  - WidgetDebugger can help debug complex TUI layouts in graph/runner modes
  - PerformanceProfiler can identify rendering bottlenecks in large task lists
  - CompletionPopup enhances future interactive command modes
  - ThemeEditor allows customizing TUI appearance
- [x] `build.zig.zon`에 sailor v1.9.0 의존성 업데이트 (2026-03-11)
- [x] 기존 테스트 전체 통과 확인 (780 unit, 905 integration)

**Note**: Non-breaking upgrade. Developer tools are opt-in. Consider using WidgetDebugger when enhancing TUI features.

---

**sailor v1.6.1 patch released** (2026-03-08) — Critical bug fixes for v1.6.0 widgets

- **Bug fixes**:
  - PieChart: Fixed integer overflow in coordinate calculation (prevented panics)
  - Multiple widgets: Fixed API compilation errors (Color.rgb, buffer.set, u16 casts)
- **Impact on zr**: None (zr doesn't use v1.6.0 widgets yet)
- [ ] Optional: Update to v1.6.1 for stable data visualization widgets

**Note**: Patch release, no breaking changes. Safe to upgrade when/if data visualization widgets are needed.
---

## zuda Migration

zr은 현재 자체 구현한 자료구조/알고리즘을 `zuda` 라이브러리(https://github.com/yusa-imit/zuda)로 점진적으로 대체할 예정이다.
zuda의 해당 구현이 완료되면 `from:zuda` 라벨 이슈가 발행된다.

### 마이그레이션 대상

| 자체 구현 | 파일 | zuda 대체 | status |
|-----------|------|-----------|--------|
| DAG | `src/graph/dag.zig` | `zuda.containers.graphs.AdjacencyList` | PENDING |
| Topological Sort (Kahn's) | `src/graph/topo_sort.zig` | `zuda.algorithms.graph.topological_sort` | PENDING |
| Cycle Detection | `src/graph/cycle_detect.zig` | `zuda.algorithms.graph.cycle_detection` | PENDING |
| Work-Stealing Deque | `src/exec/workstealing.zig` | `zuda.containers.queues.StealingQueue` | PENDING |
| Levenshtein Distance | `src/util/levenshtein.zig` | `zuda.algorithms.dynamic_programming.edit_distance` | PENDING |
| Glob Pattern Matching | `src/util/glob.zig` | `zuda.algorithms.string.glob_match` | PENDING |

### 마이그레이션 제외 (domain-specific)

- `src/util/string_pool.zig` — zr 전용 문자열 인터닝
- `src/util/object_pool.zig` — zr 전용 객체 풀
- `src/graph/ascii.zig` — zr 전용 ASCII 그래프 렌더러

### 마이그레이션 프로토콜

1. zuda에서 `from:zuda` 라벨 이슈가 도착하면 해당 마이그레이션의 status를 `READY`로 변경
2. 마이그레이션 수행:
   - `build.zig.zon`에 zuda 의존성 추가 (`zig fetch --save <url>`)
   - `build.zig`에서 zuda 모듈 import 설정
   - 자체 구현 파일의 코드를 zuda import로 교체
   - 자체 구현 파일은 래퍼로 전환하거나 삭제
3. `zig build test && zig build integration-test` 전체 통과 확인
4. status를 `DONE`으로 변경하고 커밋

### zuda 이슈 발행 프로토콜

zuda 라이브러리를 사용하는 중 버그를 발견하거나, 필요한 기능이 없을 때:

```bash
gh issue create --repo yusa-imit/zuda \
  --title "bug: <간단한 설명>" \
  --label "bug,from:zr" \
  --body "## 증상
<어떤 문제가 발생했는지>

## 재현 방법
<코드 또는 단계>

## 환경
- zuda: <version>
- zig: $(zig version)
- OS: $(uname -s)"
```

- zuda의 기존 API로 해결할 수 없는 문제일 때만 발행
- 동일한 이슈가 이미 열려있는지 먼저 확인
- **로컬 워크어라운드 금지**: zuda에 버그가 있으면 자체 구현으로 우회하지 않고, 이슈 발행 후 수정 대기
- zuda 에이전트가 `from:*` 라벨 이슈를 최우선 처리한다

### v1.10.0 — Mouse & Gamepad Input (status: DONE)

**sailor v1.10.0 released** (2026-03-11) — Mouse, gamepad, and touch input support

- **New features**:
  - Mouse event handling: SGR protocol, click/drag/scroll/double-click (19 tests)
  - Widget mouse interaction: Clickable, Draggable, Scrollable, Hoverable traits (17 tests)
  - Gamepad/controller input: Buttons, analog sticks, triggers, multi-controller (13 tests)
  - Touch gesture recognition: Tap, swipe, pinch, multi-touch support (18 tests)
  - Input mapping: Remap mouse/gamepad/touch to keyboard events (16 tests)
- **Impact on zr**: HIGH — Enables interactive TUI features
  - Mouse click support for task selection in TUI mode
  - Gamepad navigation for console-style task runner
  - Touch gestures for future mobile terminal support
  - Input mapping for accessibility (map mouse to keyboard for keyboard-only users)
- [x] Update `build.zig.zon` to sailor v1.10.0 (2026-03-11)
- [ ] Consider adding mouse click support to task picker widget (future enhancement)
- [x] All tests passing after upgrade (786 unit, 914 integration)

**Priority**: MEDIUM — Optional upgrade, enables new interaction paradigms but not required for current functionality.

**Note**: Non-breaking upgrade. Mouse/gamepad/touch support is opt-in via event polling.

---


### v1.11.0 — Terminal Graphics & Effects
- **status**: READY
- **features**:
  - Particle effects system (confetti, sparkles for celebrations)
  - Blur/transparency effects
  - Sixel/Kitty graphics protocol support
  - Animated widget transitions
- **integration**:
  - Particle effects for task completion celebrations
  - Blur effects for background panels
  - Graphics protocol for inline images in task details
- **tests**: Verify particle/blur rendering in TUI mode
- **breaking**: None — all opt-in features

### v1.12.0 — Enterprise & Accessibility
- **status**: READY
- **features**:
  - Session recording & playback for debugging
  - Audit logging for compliance
  - High contrast WCAG AAA themes (4 themes: dark, light, amber, green)
  - Screen reader enhancements (OSC8, ARIA, JSON modes)
  - Keyboard-only navigation improvements (skip links, focus indicators)
- **integration**:
  - Audit log for task operations (create, update, delete, run)
  - High contrast themes for accessibility settings
  - Keyboard navigation hints for TUI mode
- **tests**: None required (all opt-in features, no breaking changes)
- **breaking**: None — all additive
