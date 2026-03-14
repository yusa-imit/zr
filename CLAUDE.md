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
7. `docs/milestones.md` — 활성 마일스톤, 차단 항목, 의존성 마이그레이션 상태

**9단계 실행 사이클**:

| Phase | 내용 | 비고 |
|-------|------|------|
| 1. 상태 파악 | `/status` 실행, git log·빌드·테스트 상태 점검 | `docs/milestones.md`에서 다음 작업 식별 |
| 1.5. 이슈 확인 | `gh issue list --state open --limit 10` | 아래 **이슈 우선순위 프로토콜** 참조 |
| 2. 계획 | 구현 전략을 내부적으로 수립 (텍스트 출력) | `EnterPlanMode`/`ExitPlanMode` 사용 금지 — 비대화형 세션에서 블로킹됨 |
| 3. 구현 → 검증 → 커밋 (반복) | 아래 **구현 루프** 참조 | 단위별로 즉시 커밋+푸시 |
| 4. 코드 리뷰 | `/review` — PRD 준수·메모리 안전성·테스트 커버리지 확인 | 이슈 발견 시 수정 후 재커밋 |
| 5. 릴리즈 판단 | 릴리즈 조건 충족 시 **자동 릴리즈** | 아래 **Release & Patch Policy** 참조 |
| 6. 메모리 갱신 | `.claude/memory/` + `docs/milestones.md` 업데이트 | 완료된 마일스톤 상태 갱신, 별도 커밋 |
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
- Post-v1.0 우선순위: Bug 이슈 > `migration` 라벨 이슈 (sailor/zuda) > Post-v1.0 Priorities 항목

**이슈 우선순위 프로토콜** (Phase 1.5):

세션 시작 시 GitHub Issues를 확인하고 우선순위를 결정한다:

```bash
gh issue list --state open --limit 10 --json number,title,labels,createdAt
```

| 우선순위 | 조건 | 행동 |
|---------|------|------|
| 1 (최우선) | `bug` 라벨 | 다른 작업보다 **항상 우선** 처리 |
| 2 (높음) | `migration` 라벨 (`from:sailor`, `from:zuda` 등) | 의존성 마이그레이션 — 현재 작업보다 **우선** 처리 |
| 3 (보통) | `feature-request` + 현재 우선순위 범위 내 | 현재 작업과 **병행** |
| 4 (낮음) | `feature-request` + 미래 범위 | **적어두고 넘어감** |

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

All 13 PRD phases complete (v1.0.0). See `docs/PRD.md` for details.

---

## Post-v1.0 Milestones

See `docs/milestones.md` for active milestones, completed releases, and roadmap.

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
13. **Agent activity logging** — Subagent/Team 호출 시 반드시 `.claude/logs/agent-activity.jsonl`에 로그 기록 (아래 Agent Activity Logging 섹션 참조)

---

## Agent Activity Logging

Subagent(Task 도구) 또는 Team(TeamCreate)을 호출할 때마다 `.claude/logs/agent-activity.jsonl`에 로그를 기록한다.

**로그 형식** (JSON Lines — 한 줄에 하나의 JSON 객체):
```json
{"timestamp":"2026-03-14T12:00:00Z","action":"subagent","agent_type":"zig-developer","task":"Fix build error in scheduler","project":"zr"}
{"timestamp":"2026-03-14T12:05:00Z","action":"team_create","team_name":"v1.35-impl","members":["zig-developer","test-writer"],"task":"Implement v1.35.0 zuda migration","project":"zr"}
{"timestamp":"2026-03-14T13:00:00Z","action":"team_delete","team_name":"v1.35-impl","project":"zr"}
```

**필드**:

| 필드 | 필수 | 설명 |
|------|------|------|
| `timestamp` | ✅ | ISO 8601 형식 (UTC) |
| `action` | ✅ | `subagent` \| `team_create` \| `team_delete` |
| `agent_type` | subagent 시 | 에이전트 타입 (`zig-developer`, `code-reviewer`, `Explore` 등) |
| `team_name` | team 시 | 팀 이름 |
| `members` | team_create 시 | 팀 멤버 이름 배열 |
| `task` | ✅ | 작업 설명 (Task 도구의 description 또는 prompt 요약) |
| `project` | ✅ | 프로젝트 이름 (`zr`) |

**규칙**:
1. `.claude/logs/` 디렉토리가 없으면 생성
2. 파일에 append (기존 로그 유지)
3. 로그는 git에 커밋+push 필수 — 커밋 메시지: `chore: update agent activity log`
4. 세션 종료 전 미커밋 로그가 있으면 반드시 커밋+push

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
1. `docs/milestones.md`에서 해당 마일스톤을 Completed 섹션으로 이동
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

## Sailor Library

- **Current**: v1.13.1 (all migrations through v1.13.1 complete)
- **Tracking**: See `docs/milestones.md` for version-by-version status

### Migration Protocol
1. 세션 시작 시 `status: READY`인 마이그레이션 확인
2. READY 상태이면 현재 작업보다 우선 수행
3. 완료 후 status → DONE, 커밋
4. `zig build test && zig build integration-test` 통과 필수

### Issue Filing (Bug)
```bash
gh issue create --repo yusa-imit/sailor \
  --title "bug: <description>" \
  --label "bug,from:zr" \
  --body "## 증상\n<issue>\n## 재현 방법\n<steps>\n## 기대 동작\n<expected>\n## 환경\n- sailor: <version>\n- Zig: 0.15.2"
```

### Issue Filing (Feature)
```bash
gh issue create --repo yusa-imit/sailor \
  --title "feat: <description>" \
  --label "feature-request,from:zr" \
  --body "## 필요한 이유\n<why>\n## 제안 API\n<api>\n## 워크어라운드\n<workaround>"
```

### No Local Workaround (CRITICAL)
- sailor 버그 시 **절대** 로컬 우회 금지 → 이슈 발행 후 수정 대기
- 수정 릴리스 후 `zig fetch --save`로 업데이트

---

## zuda Library

- **Current**: Not yet integrated (blocked on zuda releases)
- **Tracking**: See `docs/milestones.md` for migration targets

### Migration Protocol
1. `from:zuda` 라벨 이슈 도착 시 status → READY
2. `zig fetch --save`로 의존성 추가
3. 자체 구현 → zuda import로 교체 (래퍼 전환 또는 삭제)
4. `zig build test && zig build integration-test` 통과 확인

### No Local Workaround (CRITICAL)
- zuda 버그 시 자체 구현으로 우회 금지 → 이슈 발행 후 수정 대기
