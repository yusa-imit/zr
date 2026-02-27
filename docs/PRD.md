# zr — Product Requirements Document

> **zr (zig-runner) — 개발자 플랫폼: 태스크 러닝 + 툴체인 관리 + 모노/멀티레포 인텔리전스**
>
> Version: 3.0 Draft
> Author: Yusa × Claude
> Date: 2026-02-27

### Version History

| 버전 | 날짜 | 범위 | 요약 |
|------|------|------|------|
| **v1.0** | 2026-02-16 | Phase 1–4 | 태스크 러너 & 워크플로우 매니저 (MVP → 플러그인) |
| **v2.0** | 2026-02-20 | Phase 5–8 | 개발자 플랫폼 확장 (모노레포·툴체인·멀티레포·엔터프라이즈) |
| **v3.0** | 2026-02-27 | Phase 9–13 | v1.0 릴리스 (AI 통합·LSP·DX·성능·언어 확장성) |

**v3.0에서 추가/변경된 항목**:
- Section 1: Executive Summary에 AI 통합·LSP·DX 축 추가
- Section 3: Persona G (AI-Native Developer) `v3.0`
- Section 5: 5.11 LanguageProvider, 5.12 MCP Server, 5.13 LSP Server, 5.14 자연어 인터페이스, 5.15 DX 개선 `v3.0`
- Section 9: Phase 9–13 `v3.0`
- Section 10: 10.3 Phase 9–13 성공 지표 `v3.0`
- Section 11: AI/LSP 관련 리스크 추가 `v3.0`
- Section 12: MCP/LSP 기능 비교 반영 `v3.0`
- Appendix B: Phase 9+ CLI 예시 `v3.0`

**v2.0에서 추가/변경된 항목**:
- Section 1: Executive Summary 확장 (Run/Manage/Scale 3축, 점진적 확장 포지셔닝)
- Section 2: 2.2 도구 분산 문제, 2.3 멀티레포 사각지대, 2.5 추가 도구 비교 `v2.0`
- Section 3: Persona D·E·F `v2.0`
- Section 5: 5.7 모노레포 인텔리전스, 5.8 툴체인 관리, 5.9 멀티레포 오케스트레이션, 5.10 엔터프라이즈 `v2.0`
- Section 9: Phase 5–8 `v2.0`
- Section 10: 10.2 Phase 5–8 성공 지표 `v2.0`
- Section 12: 포지셔닝 맵·비교표·차별점 전면 개편 `v2.0`

---

## 1. Executive Summary

**zr**은 Zig로 작성된 **개발자 플랫폼(Developer Platform)** 이다. nvm/pyenv/asdf 같은 툴체인 매니저, make/just/task 같은 태스크 러너, Nx/Turborepo 같은 모노레포 도구를 **단일 바이너리** 하나로 대체한다.

네 개의 핵심 축으로 구성된다:

- **Run** — 태스크 정의, 의존성 그래프 기반 병렬 실행, 워크플로우 파이프라인
- **Manage** — 프로젝트별 툴체인 버전 관리, 환경 변수 레이어링, 원커맨드 프로젝트 셋업
- **Scale** — 모노레포 affected 감지, 콘텐츠 해시 캐싱, 멀티레포 오케스트레이션, 아키텍처 거버넌스
- **Integrate** `v3.0` — MCP Server로 AI 에이전트 연동, LSP Server로 에디터 통합, 자연어 인터페이스

레포지토리 구조(모노레포, 멀티레포, 단일 프로젝트)에 구애받지 않고, 어떤 언어·빌드 시스템·스크립트 환경에서든 동작하며, 개인 프로젝트의 간단한 태스크 러너에서 엔터프라이즈 모노레포의 빌드 시스템까지 **점진적으로 확장(progressive unlock)** 되는 도구를 지향한다. 이름 자체가 2글자로, 타이핑 최소화를 통한 빠른 CLI 사용을 지향한다.

### 1.1 핵심 가치

- **언어·생태계 무관**: JS, Python, Go, Rust, Docker, shell script 등 어떤 명령이든 태스크로 등록 가능
- **단일 바이너리**: Zig의 크로스 컴파일로 macOS, Linux, Windows를 하나의 릴리스 파이프라인으로 커버. nvm + make + nx를 하나의 ~3MB 바이너리로 대체
- **극한 성능**: C급 속도의 태스크 스케줄링, 그래프 해석, 프로세스 관리. ~0ms 콜드 스타트
- **유저 친화적 CLI**: 컬러풀한 출력, 프로그레스 표시, 인터랙티브 모드, 에러 메시지의 가독성
- **점진적 확장**: 개인 프로젝트에서 `zr run build` 한 줄로 시작 → 팀이 커지면 캐싱·affected·툴체인 관리를 하나씩 활성화. 설정 복잡도가 프로젝트 규모에 비례
- **벤더 락인 없음**: 자체 호스팅 원격 캐시(S3/GCS/HTTP), 오픈 설정 포맷(TOML), 플러그인 확장
- **AI 네이티브** `v3.0`: MCP Server로 Claude Code/Cursor에서 직접 태스크 실행, LSP Server로 zr.toml 실시간 자동완성·에러 진단
- **언어 확장성** `v3.0`: LanguageProvider 인터페이스로 새 프로그래밍 언어 추가가 단일 파일 작성으로 완료

---

## 2. Problem Statement

### 2.1 기존 도구의 한계

| 도구 | 주요 한계 |
|------|-----------|
| **Make** | 탭 문법 강제, 복잡한 워크플로우 표현 어려움, 병렬 실행 제어 미흡, 에러 메시지 불친절 |
| **Turborepo** | JS/TS 생태계 종속, 범용 태스크 러너로 부적합 |
| **Nx** | 설정 복잡, 학습 곡선 높음, Node.js 런타임 필요 |
| **Just** | 단순 명령 러너에 가까움, 의존성 그래프·병렬 실행 미지원 |
| **Task (go-task)** | YAML 기반으로 복잡한 워크플로우 정의 시 가독성 저하, 플러그인 시스템 부재 |
| **moon** | Rust 기반으로 빠르지만 특정 생태계(JS/TS) 편향, 범용성 부족 |

### 2.2 도구 분산 문제 (Tool Sprawl) `v2.0`

현대 개발 환경에서 하나의 프로젝트를 셋업하기 위해 필요한 도구:

| 영역 | 일반적인 도구 | 문제 |
|------|-------------|------|
| 언어 버전 관리 | nvm, pyenv, rbenv, asdf, mise | 도구마다 다른 설정 파일 (`.nvmrc`, `.python-version`, `.tool-versions`) |
| 태스크 실행 | make, just, task, npm scripts | 프로젝트마다 다른 러너, 통일된 인터페이스 부재 |
| 모노레포 관리 | Nx, Turborepo, Lerna, Rush | JS/TS 생태계 종속, Node.js 런타임 필수 |
| 환경 설정 | direnv, dotenv, docker-compose | 환경 변수 관리가 여러 곳에 분산 |
| CI/CD 로컬 실행 | act, dagger, earthly | CI와 로컬의 괴리 |

**결과**: 새 팀원이 프로젝트에 합류하면 README의 "Prerequisites" 섹션만 10줄이 넘고, 셋업에 수 시간이 소요된다.

### 2.3 멀티레포의 사각지대 `v2.0`

마이크로서비스·멀티레포 환경에서는 추가적인 문제가 발생한다:

- **크로스레포 의존성 파악 불가**: repo A가 repo B의 API에 의존하지만, 이를 추적하는 도구가 없음
- **중복 빌드**: 동일한 공유 라이브러리를 각 레포에서 개별 빌드
- **통합 뷰 부재**: 전체 시스템의 의존성 그래프를 보여주는 도구가 없음
- **캐시 낭비**: 팀이 같은 결과물을 반복 빌드 (공유 캐시 없음)

### 2.4 zr이 해결하는 핵심 문제

1. **런타임 의존성 제거**: Node.js, Python, Go 등 별도 런타임 설치 없이 단일 바이너리로 동작
2. **범용성**: 프로젝트 언어·구조와 무관하게 어디서든 사용 가능
3. **복잡한 워크플로우**: 단순 명령 실행을 넘어 의존성 그래프, 조건 분기, 파이프라인 체이닝, 에러 핸들링을 하나의 정의 파일에서 관리
4. **자원 관리**: CPU/메모리 제한, 동시 실행 수 제어, 타임아웃 등 프로덕션급 자원 관리
5. **확장성**: 플러그인으로 새로운 기능을 추가할 수 있는 아키텍처
6. **도구 통합**: 5개 이상의 개발 도구를 단일 바이너리로 대체 — 툴체인 매니저 + 태스크 러너 + 빌드 시스템 + 모노레포 도구
7. **원커맨드 온보딩**: `git clone → zr setup → done` — 새 팀원이 2분 이내에 개발 환경 구축 완료
8. **멀티레포 인텔리전스**: 분리된 레포를 논리적 워크스페이스로 통합, 크로스레포 의존성 추적 및 태스크 실행

### 2.5 기존 도구와의 추가 비교 `v2.0`

| 도구 | 카테고리 | zr 대비 한계 |
|------|---------|-------------|
| **mise** | 툴체인 매니저 | 태스크 러닝 기능이 기본적, 모노레포 미지원, 의존성 그래프 없음 |
| **Moon** | 빌드 시스템 | Rust 기반으로 빠르지만 툴체인 관리 기능 없음, 멀티레포 미지원 |
| **Bazel/Buck2** | 빌드 시스템 | 강력하지만 학습 곡선 극도로 높음, 설정 복잡도 비례하지 않음 |
| **Pants** | 빌드 시스템 | Python 생태계 편향, 런타임 의존성(Python) 필수 |
| **Earthly** | CI 러너 | Docker 의존, 로컬 개발 워크플로우로는 무거움 |

---

## 3. Target Users

### 3.1 Primary Users

- **개인 개발자**: 다양한 언어의 프로젝트를 관리하며, Makefile을 대체할 현대적 도구를 원하는 사용자
- **DevOps 엔지니어**: CI/CD 파이프라인의 로컬 실행, 인프라 스크립트 오케스트레이션이 필요한 사용자
- **풀스택/폴리글랏 팀**: 하나의 프로젝트에 여러 언어·도구가 혼재하는 환경에서 통합 태스크 관리가 필요한 팀

### 3.2 User Personas

**Persona A — "Solo Polyglot Dev"**
- 개인 프로젝트에서 Zig 백엔드 + React 프론트 + Python ML 스크립트를 함께 관리
- `make build` 하나로 전부 빌드하고 싶지만 Makefile이 점점 스파게티가 됨
- 원하는 것: 간단한 설정으로 복잡한 빌드 파이프라인 정의, 변경된 부분만 빌드

**Persona B — "Platform Engineer"**
- 20개 이상의 마이크로서비스를 관리하는 팀
- Docker 빌드, 테스트, 배포를 로컬에서도 CI와 동일하게 실행하고 싶음
- 원하는 것: 서비스 간 의존성 그래프, 병렬 빌드, 자원 제한, CI 연동

**Persona C — "Script Automator"**
- 반복적인 운영 작업(DB 마이그레이션, 로그 분석, 배포)을 자동화
- 여러 스크립트를 특정 순서로 실행하며, 실패 시 롤백 로직이 필요
- 원하는 것: 워크플로우 체이닝, 에러 핸들링, dry-run, 실행 이력

**Persona D — "Monorepo Architect"** `v2.0`
- 50개 이상의 패키지가 있는 모노레포를 관리하는 시니어 엔지니어
- PR마다 전체 빌드가 돌아가면 CI가 30분 이상 걸림 → affected 감지 필요
- 패키지 간 의존성 규칙(A는 B에 의존하면 안 됨) 강제 필요
- 현재 Nx를 쓰지만 Node.js 런타임 의존과 JS 생태계 락인에 불만
- 원하는 것: 폴리글랏 모노레포에서 affected 감지, 콘텐츠 해시 캐싱, 아키텍처 거버넌스, CODEOWNERS 자동 생성

**Persona E — "Multi-repo Orchestrator"** `v2.0`
- 10개 이상의 마이크로서비스 레포를 관리하는 플랫폼 팀
- 서비스 간 API 의존성이 있지만 이를 추적할 통합 도구가 없음
- 공유 라이브러리 변경 시 영향받는 모든 서비스를 수동으로 파악
- 현재 커스텀 쉘 스크립트 + Jenkins로 크로스레포 빌드 오케스트레이션
- 원하는 것: 크로스레포 의존성 그래프, 통합 태스크 실행, 공유 원격 캐시

**Persona F — "Team Lead / Onboarding Manager"** `v2.0`
- 분기마다 2-3명의 신규 입사자를 온보딩하는 팀 리더
- 신규 멤버 셋업에 평균 반나절 소요 (Node 버전, Python 버전, 환경 변수, DB 마이그레이션...)
- README의 "Getting Started"가 항상 outdated
- 현재 mise/asdf + make + .env.example 조합으로 관리
- 원하는 것: `git clone && zr setup` 한 줄로 전체 개발 환경 구축, 버전 불일치 자동 감지

**Persona G — "AI-Native Developer"** `v3.0`
- Claude Code, Cursor 등 AI 코딩 도구를 일상적으로 사용하는 개발자
- AI 에이전트가 빌드·테스트·배포를 직접 실행하길 원하지만, 현재 도구는 CLI 파싱이 필요
- 새 프로젝트마다 zr.toml을 처음부터 작성하는 것이 번거로움
- VS Code에서 zr.toml 편집 시 자동완성이나 에러 표시가 없어 오타를 발견하기 어려움
- 원하는 것: MCP Server로 AI가 직접 태스크 호출, `zr init --detect`로 프로젝트 자동 감지 → 설정 생성, LSP로 에디터 내 실시간 피드백

---

## 4. 워크플로우 정의 방식

### 4.1 결정: TOML + 내장 표현식 엔진

zr은 **TOML 기반 설정 파일에 내장 표현식 엔진을 결합**하는 방식을 채택한다. 이 결정의 배경으로, 검토한 대안들과의 비교를 아래에 정리한다.

### 4.2 검토한 대안들

#### Option A: TOML 기반 설정 파일

```toml
# zr.toml

[tasks.build-frontend]
cmd = "npm run build"
cwd = "./frontend"
deps = ["install-deps"]
env = { NODE_ENV = "production" }
timeout = "5m"

[tasks.build-backend]
cmd = "zig build -Doptimize=ReleaseFast"
cwd = "./backend"
deps = ["generate-proto"]

[tasks.build]
deps = ["build-frontend", "build-backend"]
description = "Build all targets"

[tasks.deploy]
pipeline = ["build", "test", "docker-push"]
on_failure = "rollback"
```

| 장점 | 단점 |
|------|------|
| 학습 곡선 거의 없음 | 복잡한 조건 분기 표현이 제한적 |
| 기존 도구 사용자에게 친숙 | 반복·루프 같은 프로그래밍 패턴 불가 |
| 정적 분석·자동완성 쉬움 | 대규모 설정 시 파일이 비대해짐 |
| Git diff 가독성 우수 | 동적 태스크 생성 불가 |

#### Option B: Zig DSL (Zig 코드로 워크플로우 정의)

```zig
// zr.zig
const zf = @import("zr");

pub fn build(ctx: *zf.Context) !void {
    const frontend = ctx.task("build-frontend", .{
        .cmd = &.{ "npm", "run", "build" },
        .cwd = "./frontend",
        .env = .{ .NODE_ENV = "production" },
        .timeout = zf.duration.minutes(5),
    });

    const backend = ctx.task("build-backend", .{
        .cmd = &.{ "zig", "build", "-Doptimize=ReleaseFast" },
        .cwd = "./backend",
        .deps = &.{ctx.task("generate-proto", .{})},
    });

    ctx.pipeline("build", &.{ frontend, backend });
}
```

| 장점 | 단점 |
|------|------|
| Zig의 comptime으로 정적 검증 가능 | Zig를 알아야 사용 가능 → 범용성 저하 |
| 조건 분기, 루프, 함수 재사용 자유로움 | 비개발자/타 언어 유저 진입장벽 높음 |
| 타입 안전성 | 빌드 스텝이 필요 (설정 파일 → 실행 파일) |
| IDE 자동완성·컴파일 에러 | Git diff 가독성 떨어질 수 있음 |

#### Option C: TOML + 스크립트 하이브리드

```toml
# zr.toml — 선언적 태스크 정의

[tasks.build-frontend]
cmd = "npm run build"
cwd = "./frontend"
deps = ["install-deps"]

[tasks.deploy]
pipeline = ["build", "test", "docker-push"]
```

```bash
# scripts/custom-deploy.sh — 복잡한 로직은 외부 스크립트
#!/bin/bash
zr run build --parallel
if [ $? -eq 0 ]; then
    zr run docker-push
fi
```

| 장점 | 단점 |
|------|------|
| 단순한 건 TOML, 복잡한 건 스크립트로 분리 | 정의가 두 곳에 분산 |
| 각각의 장점을 취사선택 가능 | 스크립트 부분은 zr이 관리 불가 |
| 점진적 도입 용이 | 의존성 그래프에서 스크립트 내부를 추적 불가 |

#### Option D: TOML + 내장 표현식 엔진

```toml
# zr.toml

[tasks.build-frontend]
cmd = "npm run build"
cwd = "./frontend"
deps = ["install-deps"]
condition = "env.CI == 'true' || file.changed('frontend/**')"
timeout = "5m"

[tasks.deploy]
pipeline = ["build", "test", "docker-push"]
on_failure = "notify"
retry = { max = 3, delay = "10s", backoff = "exponential" }
matrix = { target = ["staging", "production"], region = ["us", "eu"] }

[workflows.release]
steps = [
  { run = "build", parallel = true },
  { run = "test", condition = "steps.build.success" },
  { run = "deploy", for_each = "matrix.target", condition = "branch == 'main'" },
]
```

| 장점 | 단점 |
|------|------|
| TOML의 가독성 + 동적 표현력 | 표현식 엔진 자체 구현 필요 |
| 조건 분기, 매트릭스, 재시도 등 선언적 표현 | 표현식 문법이 또 다른 학습 대상 |
| 정적 분석 가능 (표현식도 파싱 가능) | 복잡해지면 결국 DSL과 비슷해질 수 있음 |
| 비개발자도 접근 가능 | 표현식의 한계를 만나면 확장이 어려움 |

### 4.3 채택 근거

**Option D (TOML + 내장 표현식 엔진)** 를 채택한다.

1. **범용 도구**라는 포지셔닝에서 Zig DSL(Option B)은 사용자층을 제한한다.
2. 단순 TOML(Option A)은 실무에서 금방 한계에 부딪힌다.
3. 하이브리드(Option C)는 관리 포인트가 분산된다.
4. **Option D**는 TOML의 가독성을 유지하면서, 내장 표현식으로 조건 분기·매트릭스·재시도 같은 실무 패턴을 선언적으로 커버한다.

플러그인 시스템의 정의 파일은 Zig 코드로 작성하여, 고급 사용자가 Zig의 comptime 검증과 타입 안전성을 누릴 수 있도록 한다.

---

## 5. Core Features — 상세 설계

### 5.1 태스크 정의 & 의존성 그래프

#### 5.1.1 태스크 스키마

```toml
[tasks.task-name]
# 기본
cmd = "string | [array, of, args]"         # 실행 명령
shell = "bash"                              # 셸 지정 (기본: sh)
cwd = "./relative/path"                     # 작업 디렉토리
description = "Human-readable description"  # 도움말 표시

# 의존성
deps = ["task-a", "task-b"]                 # 선행 태스크 (병렬 실행)
deps_serial = ["task-c", "task-d"]          # 선행 태스크 (순차 실행)

# 환경
env = { KEY = "value", FROM = "$OTHER_VAR" }
env_file = ".env.production"
dotenv = true                               # .env 자동 로드

# 실행 제어
condition = "표현식"                         # 실행 조건
timeout = "5m"                              # 타임아웃
retry = { max = 3, delay = "5s", backoff = "exponential" }
allow_failure = false                       # 실패 허용 여부
interactive = false                         # stdin 연결 여부

# 자원 제한
[tasks.task-name.resources]
max_cpu = 4                                 # 최대 CPU 코어
max_memory = "2GB"                          # 최대 메모리
max_concurrent = 2                          # 이 태스크의 최대 동시 실행 수

# 입출력
[tasks.task-name.io]
stdin = "file:input.txt"                    # stdin 소스
stdout = "file:output.log"                  # stdout 대상
stderr = "file:error.log"                   # stderr 대상
```

#### 5.1.2 의존성 그래프 엔진

의존성 그래프는 DAG(Directed Acyclic Graph)로 모델링하며, 다음을 보장한다.

- **순환 감지**: 설정 로드 시점에 Kahn's Algorithm으로 순환 의존성 감지, 즉시 에러 보고
- **토폴로지 정렬**: 실행 순서를 결정하는 기반
- **최대 병렬화**: 의존성이 해소된 태스크는 즉시 워커 풀에 투입
- **Critical Path 계산**: 어떤 태스크가 전체 실행 시간의 병목인지 표시

```
zr graph build --format=dot    # Graphviz DOT 출력
zr graph build --format=ascii  # 터미널 ASCII 트리
zr graph build --format=json   # 프로그래밍용 JSON
```

시각화 예시 (ASCII):

```
build
├── build-frontend
│   └── install-deps
├── build-backend
│   └── generate-proto
└── lint (parallel)
```

### 5.2 실행 엔진

#### 5.2.1 병렬 실행 모델

Zig의 `std.Thread` 기반 워커 풀을 사용하며, 기본 워커 수는 논리 CPU 코어 수와 동일하다.

```
Global Config:
  max_workers = 8        # 전체 최대 동시 실행 태스크
  
Per-Task:
  max_concurrent = 2     # 특정 태스크 동시 실행 제한 (matrix 사용 시)
```

스케줄링 흐름:

```
1. DAG 토폴로지 정렬
2. Ready Queue에 의존성 없는 태스크 투입
3. Worker Pool에서 태스크 꺼내 실행
4. 태스크 완료 → 의존 태스크의 카운터 감소
5. 카운터 0이 된 태스크를 Ready Queue에 추가
6. 반복
```

#### 5.2.2 순차 실행

```toml
[tasks.migrate]
deps_serial = ["backup-db", "run-migration", "verify-migration"]
```

`deps_serial`은 배열 순서대로 하나씩 실행하며, 하나라도 실패하면 이후 태스크를 건너뛴다.

#### 5.2.3 파이프라인 / 워크플로우 체이닝

```toml
[workflows.release]
description = "Full release pipeline"

[[workflows.release.stages]]
name = "준비"
tasks = ["clean", "install-deps"]
parallel = true

[[workflows.release.stages]]
name = "빌드"
tasks = ["build-frontend", "build-backend"]
parallel = true
condition = "stages['준비'].success"

[[workflows.release.stages]]
name = "검증"
tasks = ["test", "lint", "type-check"]
parallel = true
fail_fast = true                    # 하나라도 실패 시 전체 중단

[[workflows.release.stages]]
name = "배포"
tasks = ["deploy"]
condition = "env.BRANCH == 'main'"
approval = true                     # 수동 승인 대기 (인터랙티브 모드)

[workflows.release.on_failure]
run = "notify-slack"
always = true                       # 성공/실패 무관 실행
```

```bash
zr workflow release              # 전체 파이프라인 실행
zr workflow release --from=빌드   # 특정 스테이지부터
zr workflow release --dry-run    # 실행 계획만 표시
```

### 5.3 유저 친화적 CLI

#### 5.3.1 CLI 커맨드 체계

```
zr <command> [subcommand] [options] [args]

Commands:
  run <task...>         하나 이상의 태스크 실행
  workflow <name>       워크플로우 실행
  list                  등록된 태스크/워크플로우 목록
  graph [task]          의존성 그래프 시각화
  watch <task...>       파일 변경 감지 → 자동 재실행
  init                  설정 파일 초기화
  validate              설정 파일 검증
  history               실행 이력 조회
  plugin                플러그인 관리
  completion            셸 자동완성 설치

  # Phase 5+
  affected <task>       변경된 패키지 + 의존자에만 태스크 실행
  cache                 캐시 관리 (status, clean)
  lint                  아키텍처 제약 조건 검증
  codeowners            CODEOWNERS 파일 관리

  # Phase 6
  setup                 프로젝트 원커맨드 셋업
  doctor                환경 진단 (도구, 설정, 연결)
  tools                 툴체인 관리 (list, install, outdated)
  env                   환경 변수 표시 및 디버그

  # Phase 7
  repo                  멀티레포 관리 (sync, status, run)

  # Phase 8
  analytics             빌드 분석 리포트
  version               버전 범프 (인터랙티브)
  publish               패키지 퍼블리싱
  context               AI 친화적 프로젝트 메타데이터 출력

Global Options:
  -j, --jobs <N>        최대 병렬 수 (기본: CPU 코어 수)
  -v, --verbose         상세 출력
  -q, --quiet           최소 출력
  --no-color            컬러 비활성화
  --dry-run             실행하지 않고 계획만 표시
  --log-file <path>     로그 파일 출력
  --config <path>       설정 파일 경로 (기본: zr.toml)
  --timeout <duration>  전역 타임아웃
```

#### 5.3.2 출력 UX

**실행 중 표시**:

```
 zr run build

 ● build-frontend    ████████████░░░░ 75%  12.3s
 ● build-backend     ████████████████ done  8.1s
 ○ deploy            waiting (deps: build-frontend)
 ✗ lint              failed (exit: 1)       2.4s

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 3/4 tasks completed │ 1 failed │ 22.8s elapsed
```

**에러 표시**:

```
 ✗ Task 'lint' failed

  Command:  npx eslint src/
  Exit:     1
  Duration: 2.4s
  CWD:      ./frontend

  ┌─ stdout ─────────────────────────────
  │ /src/App.tsx:14:5
  │   error: 'foo' is defined but never used
  │
  └──────────────────────────────────────

  Hint: Run with --verbose for full output
        Run 'zr run lint --interactive' to debug
```

**완료 요약**:

```
 ✓ Workflow 'release' completed

  Stage       Tasks   Time     Status
  ─────────   ─────   ──────   ──────
  준비         2/2     3.2s     ✓
  빌드         2/2     14.1s    ✓
  검증         3/3     8.7s     ✓
  배포         1/1     22.0s    ✓

  Total: 8 tasks │ 48.0s │ Speedup: 2.4x (vs sequential)
```

#### 5.3.3 인터랙티브 모드

```bash
zr interactive          # TUI 모드 진입
zr run build -i         # 실패 시 인터랙티브 디버그
```

TUI에서 제공하는 기능:

- 태스크 목록 탐색 및 실행
- 실행 중 태스크의 실시간 로그 스트리밍
- 태스크 취소/재시도
- 의존성 그래프 ASCII 시각화

### 5.4 자원 사용량 제한

#### 5.4.1 글로벌 리소스 설정

```toml
[global.resources]
max_workers = 8                    # 최대 동시 태스크 수
max_total_memory = "8GB"           # 전체 메모리 상한
max_cpu_percent = 80               # 전체 CPU 사용률 상한
```

#### 5.4.2 자원 관리 전략

| 기능 | 설명 |
|------|------|
| **CPU 제한** | Linux: cgroups v2, macOS: nice/cpulimit 래핑, Windows: Job Objects |
| **메모리 제한** | Linux: cgroups v2 memory.max, macOS/Windows: 주기적 RSS 모니터링 + OOM 시 SIGKILL |
| **동시성 제어** | 워커 풀 크기 조절 + 태스크별 세마포어 |
| **타임아웃** | 태스크별·스테이지별·전역 3단계 타임아웃, 초과 시 SIGTERM → grace period → SIGKILL |
| **디스크** | 출력 로그 크기 제한, 자동 로테이션 |

#### 5.4.3 자원 모니터링

```bash
zr run build --monitor       # 실행 중 자원 사용량 실시간 표시

 ● build-frontend  CPU: 145%  MEM: 312MB  IO: 2.1MB/s
 ● build-backend   CPU:  89%  MEM: 128MB  IO: 0.3MB/s
 ─────────────────────────────────────────────────────
 Total:            CPU: 234%  MEM: 440MB / 8GB
```

### 5.5 플러그인 시스템

#### 5.5.1 플러그인 아키텍처

플러그인은 **공유 라이브러리(.so/.dylib/.dll)** 형태로 로드되며, Zig의 `@import("std").DynLib` 를 통해 동적 링킹한다. 대안으로 **WASM 기반 샌드박스 플러그인**도 지원하여 안전한 서드파티 플러그인 실행을 가능하게 한다.

```
~/.zr/plugins/
├── docker/
│   ├── plugin.wasm          # WASM 플러그인
│   └── plugin.toml          # 플러그인 메타데이터
├── notify-slack/
│   ├── plugin.so            # 네이티브 플러그인
│   └── plugin.toml
```

#### 5.5.2 플러그인 인터페이스

```zig
// Plugin API (Zig interface)
pub const PluginInterface = struct {
    name: []const u8,
    version: []const u8,
    
    // Lifecycle hooks
    on_init: ?*const fn (*PluginContext) anyerror!void,
    on_before_task: ?*const fn (*TaskContext) anyerror!void,
    on_after_task: ?*const fn (*TaskContext, TaskResult) anyerror!void,
    on_workflow_complete: ?*const fn (*WorkflowContext, WorkflowResult) anyerror!void,
    
    // Custom task types
    task_handlers: []const TaskHandler,
    
    // Custom CLI commands
    commands: []const CliCommand,
};
```

#### 5.5.3 플러그인 설정

```toml
# zr.toml

[plugins.docker]
source = "registry:zr/docker@1.2.0"    # 레지스트리
config = { default_registry = "ghcr.io" }

[plugins.slack-notify]
source = "local:./plugins/slack-notify"       # 로컬 경로
config = { webhook_url = "$SLACK_WEBHOOK" }

[plugins.custom]
source = "git:https://github.com/user/plugin" # Git 저장소
```

#### 5.5.4 빌트인 플러그인 (v1.0 번들)

| 플러그인 | 기능 |
|----------|------|
| `docker` | Docker build/push 태스크 타입, 레이어 캐시 최적화 |
| `git` | 변경 파일 감지, 브랜치 조건, 커밋 메시지 파싱 |
| `env` | 환경 변수 관리, .env 파일 로드, vault 연동 |
| `notify` | Slack/Discord/Teams 웹훅 알림 |
| `cache` | 태스크 출력 캐싱 (로컬 파일시스템) |

### 5.6 내장 표현식 엔진

#### 5.6.1 표현식 문법

```
// 비교 & 논리
condition = "env.CI == 'true' && branch != 'main'"
condition = "exit_code == 0 || allow_failure"

// 파일 시스템
condition = "file.exists('dist/bundle.js')"
condition = "file.changed('src/**/*.ts')"
condition = "file.newer('dist/', 'src/')"

// 환경
condition = "env.NODE_ENV == 'production'"
condition = "platform == 'linux' && arch == 'x86_64'"

// 이전 스테이지 참조
condition = "stages['빌드'].success"
condition = "tasks['test'].duration < 60"

// 매트릭스
matrix = { os = ["linux", "macos"], arch = ["x64", "arm64"] }
condition = "matrix.os != 'macos' || matrix.arch != 'arm64'"
```

#### 5.6.2 내장 함수

| 함수 | 설명 | 예시 |
|------|------|------|
| `file.exists(path)` | 파일 존재 여부 | `file.exists('.env')` |
| `file.changed(glob)` | Git diff 기반 변경 감지 | `file.changed('src/**')` |
| `file.hash(path)` | 파일 해시 | `file.hash('package-lock.json')` |
| `env.get(key, default)` | 환경 변수 | `env.get('CI', 'false')` |
| `shell(cmd)` | 셸 명령 결과 | `shell('git rev-parse HEAD')` |
| `semver.gte(a, b)` | 버전 비교 | `semver.gte(env.NODE_VERSION, '18.0.0')` |

### 5.7 모노레포 인텔리전스 `v2.0`

#### 5.7.1 Affected 감지

Git 기반 변경 감지와 의존성 그래프 순회를 결합하여, 변경된 패키지와 그 의존자(dependents)만 식별하여 태스크를 실행한다.

```bash
# 변경된 패키지 + 의존자에만 빌드 실행
zr affected build

# main 브랜치 대비 변경 감지
zr affected build --base=main

# 의존자만 포함 (변경된 패키지 자체는 제외)
zr affected build --include-dependents --exclude-self

# 의존성(upstream)도 포함
zr affected build --include-dependencies

# 변경된 패키지 목록만 출력 (태스크 실행 없이)
zr affected --list
```

**감지 알고리즘**:

1. `git diff --name-only <base>..HEAD`로 변경된 파일 목록 획득
2. 변경된 파일 → 소속 패키지 매핑 (워크스페이스 멤버 경로 기반)
3. 프로젝트 의존성 그래프에서 해당 패키지의 의존자(dependents) 탐색
4. 결과 패키지 집합에 대해서만 태스크 실행

**해시 기반**: 타임스탬프가 아닌 소스 파일의 콘텐츠 해시를 사용하여 결정론적(deterministic) 결과를 보장한다.

#### 5.7.2 콘텐츠 해시 캐싱 (강화)

기존 Phase 4의 단순 태스크명 해시 캐싱을 **진정한 콘텐츠 기반 캐싱**으로 업그레이드한다.

**캐시 키 구성**:

```
cache_key = hash(
    source_files_content,     # 입력 파일의 콘텐츠 해시
    command,                  # 실행 명령어
    env_vars,                 # 관련 환경 변수
    deps_output_hashes,       # 의존 태스크들의 출력 해시
    tool_versions,            # 사용된 툴체인 버전
)
```

**캐시 설정**:

```toml
[tasks.build]
cmd = "npm run build"
cache = true                                    # 캐싱 활성화
inputs = ["src/**/*.ts", "package.json"]        # 입력 파일 glob
outputs = ["dist/**"]                           # 출력 디렉토리
env_inputs = ["NODE_ENV"]                       # 캐시 키에 포함할 환경 변수
```

**캐시 관리**:

```bash
zr cache status                # 캐시 히트율, 크기, 항목 수 표시
zr cache clean                 # 로컬 캐시 전체 삭제
zr cache clean --older=7d      # 7일 이상 된 캐시만 삭제
```

#### 5.7.3 원격 캐시 (Remote Cache)

팀 전체가 빌드 결과물을 공유할 수 있는 원격 캐시. **벤더 락인 없이 자체 호스팅** 가능.

```toml
[cache]
enabled = true
local_dir = ".zr-cache"          # 로컬 캐시 경로

[cache.remote]
type = "s3"                      # s3 | gcs | azure | http
bucket = "my-team-zr-cache"
region = "ap-northeast-2"
prefix = "zr/"                   # 버킷 내 경로 프리픽스
# credentials: 환경 변수에서 자동 읽기 (AWS_ACCESS_KEY_ID 등)

# 또는 자체 HTTP 서버
# [cache.remote]
# type = "http"
# url = "https://cache.internal.company.com/zr"
# auth = "bearer:$CACHE_TOKEN"
```

**동작 방식**:

1. 태스크 실행 전 — 캐시 키로 원격 캐시 조회 (pull)
2. 캐시 히트 → 원격에서 결과물 다운로드, 로컬에도 저장
3. 캐시 미스 → 태스크 실행 후 결과물을 로컬 + 원격에 저장 (push)
4. 암호화 at-rest 지원, 팀/워크스페이스 스코프 접근 제어

**호환 스토리지**:
- AWS S3 / S3-호환 (MinIO, R2 등)
- Google Cloud Storage
- Azure Blob Storage
- 임의 HTTP 서버 (GET/PUT 인터페이스)

#### 5.7.4 프로젝트 그래프 & 시각화

프로젝트 간 의존성을 다양한 포맷으로 시각화한다.

```bash
zr graph                         # 전체 프로젝트 의존성 그래프 (기본: ASCII)
zr graph --format=dot            # Graphviz DOT 포맷
zr graph --format=json           # 프로그래밍용 JSON
zr graph --format=html           # 인터랙티브 HTML (브라우저에서 열림)
zr graph --affected              # 변경된 프로젝트 하이라이트
zr graph --focus=packages/core   # 특정 패키지 중심으로 필터
```

**HTML 시각화**: Nx의 프로젝트 그래프와 유사한 인터랙티브 웹 뷰. 노드 클릭으로 패키지 상세 확인, 의존성 경로 하이라이팅, 검색·필터.

#### 5.7.5 CODEOWNERS 생성

패키지별 소유자 정보를 기반으로 GitHub/GitLab CODEOWNERS 파일을 자동 생성한다.

```toml
# packages/core/zr.toml
[ownership]
owners = ["@team-core", "@user-alice"]
reviewers = ["@team-platform"]
```

```bash
zr codeowners generate              # CODEOWNERS 파일 생성/갱신
zr codeowners check                 # 모든 경로에 소유자가 지정되었는지 확인
```

프로젝트 구조가 변경될 때마다 CODEOWNERS를 최신 상태로 유지할 수 있다.

#### 5.7.6 아키텍처 거버넌스 / Conformance

모듈 간 의존성 규칙을 선언적으로 정의하고 자동으로 검증한다.

```toml
# zr.toml (워크스페이스 루트)
[[constraints]]
rule = "no-circular"                              # 순환 의존성 금지
scope = "all"

[[constraints]]
rule = "tag-based"
from = { tag = "app" }
to = { tag = "lib" }                              # app → lib 의존만 허용
allow = true

[[constraints]]
rule = "banned-dependency"
from = "packages/frontend"
to = "packages/internal-api"                      # frontend → internal-api 의존 금지
allow = false
message = "Frontend must use public API only"

[[constraints]]
rule = "tag-based"
from = { tag = "feature" }
to = { tag = "feature" }                          # feature → feature 직접 의존 금지
allow = false
```

```bash
zr lint                           # 모든 아키텍처 제약 조건 검증
zr lint --fix                     # 자동 수정 가능한 위반 수정
```

### 5.8 툴체인 관리 `v2.0`

#### 5.8.1 언어 버전 관리

`[tools]` 섹션으로 프로젝트에 필요한 도구와 버전을 선언한다. 최초 실행 시 자동으로 다운로드·설치된다.

```toml
[tools]
node = "20.11"          # Node.js 20.11.x (패치 버전은 최신)
python = "3.12"         # Python 3.12.x
zig = "0.15.2"          # Zig 0.15.2 (정확한 버전)
go = "1.22"             # Go 1.22.x
rust = "1.78"           # Rust 1.78.x
deno = "1.41"           # Deno 1.41.x
bun = "1.0"             # Bun 1.0.x
```

**동작 방식**:

1. `zr run <task>` 또는 `zr setup` 실행 시, `[tools]`에 선언된 버전이 설치되어 있는지 확인
2. 미설치 → 자동 다운로드 & 설치 (`~/.zr/toolchains/<tool>/<version>/`)
3. 실행 시 PATH 앞에 해당 버전 경로를 삽입하여 올바른 버전이 사용되도록 보장
4. 워크스페이스 레벨 `[tools]`와 패키지 레벨 `[tools]`가 있으면 패키지 레벨이 우선

**지원 범위**:
- 코어 지원: Node.js, Python, Go, Rust, Zig, Deno, Bun, Java (JDK)
- 플러그인 확장: 커뮤니티 플러그인으로 추가 도구 지원 가능

```bash
zr tools list                    # 현재 프로젝트의 도구 버전 목록
zr tools install                 # 선언된 도구 전부 설치
zr tools outdated                # 새 버전 확인
```

#### 5.8.2 환경 레이어링

환경 변수가 워크스페이스 → 프로젝트 → 태스크 순서로 계층적으로 적용된다.

```
Workspace .env        (base)
  ↓ merge
Project .env          (override)
  ↓ merge
Task-level env = {}   (override)
  ↓ merge
System env            (lowest priority, fallback)
```

```toml
# 워크스페이스 zr.toml
[env]
COMPANY = "acme"
LOG_LEVEL = "info"

# packages/api/zr.toml
[env]
SERVICE_NAME = "api"
LOG_LEVEL = "debug"          # 워크스페이스 값 오버라이드

# 태스크 레벨
[tasks.test]
env = { LOG_LEVEL = "warn" }  # 태스크에서 최종 오버라이드
```

```bash
zr env                          # 현재 컨텍스트의 최종 환경 변수 표시
zr env --resolve SERVICE_NAME   # 특정 변수의 해석 과정 추적
```

**시크릿 마스킹**: `*_SECRET`, `*_TOKEN`, `*_KEY`, `*_PASSWORD` 패턴에 매칭되는 환경 변수 값은 로그 출력에서 `****`로 마스킹된다.

#### 5.8.3 프로젝트 셋업 자동화

`zr setup`으로 원커맨드 프로젝트 온보딩을 실현한다.

```toml
[setup]
steps = [
    "tools",              # [tools]에 선언된 도구 설치
    "deps",               # 패키지 매니저 의존성 설치
    "env",                # .env.example → .env 복사 (없는 경우)
    "migrate",            # DB 마이그레이션
    "validate",           # 설정 검증
]

[setup.deps]
"packages/frontend" = "npm ci"
"packages/backend" = "pip install -r requirements.txt"
"packages/api" = "go mod download"

[setup.migrate]
cmd = "zr run db-migrate"
optional = true                 # 실패해도 셋업 계속 진행
```

```bash
zr setup                        # 전체 프로젝트 셋업 (1회성)
zr doctor                       # 환경 진단: 도구 버전, 설정 검증, 연결 상태
```

**`zr doctor` 출력 예시**:

```
 zr doctor

 ✓ Node.js       20.11.1   (required: 20.11)
 ✓ Python        3.12.2    (required: 3.12)
 ✗ Go            not found (required: 1.22)
 ✓ Docker        24.0.7    (running)
 ✓ PostgreSQL    connected (localhost:5432)
 ✗ Redis         not found

 2 issues found. Run 'zr setup' to fix.
```

### 5.9 멀티레포 오케스트레이션 `v2.0`

#### 5.9.1 레포 레지스트리

관련 레포지토리를 `zr-repos.toml`에 등록하여 통합 관리한다.

```toml
# zr-repos.toml (멀티레포 루트 또는 임의 디렉토리)

[workspace]
name = "acme-platform"

[repos.api]
url = "git@github.com:acme/api.git"
path = "../api"                          # 로컬 체크아웃 경로 (상대)
branch = "main"
tags = ["backend", "core"]

[repos.frontend]
url = "git@github.com:acme/frontend.git"
path = "../frontend"
branch = "main"
tags = ["frontend"]

[repos.shared-lib]
url = "git@github.com:acme/shared-lib.git"
path = "../shared-lib"
branch = "main"
tags = ["lib", "core"]

# 크로스레포 의존성 선언
[deps]
api = ["shared-lib"]                     # api는 shared-lib에 의존
frontend = ["shared-lib", "api"]         # frontend는 shared-lib과 api에 의존
```

```bash
zr repo sync                    # 모든 레포 clone/pull
zr repo sync --clone-missing    # 미클론 레포만 클론
zr repo status                  # 모든 레포의 git 상태 표시
```

#### 5.9.2 크로스레포 의존성 그래프

멀티레포 환경에서도 모노레포와 동일한 수준의 의존성 그래프를 제공한다.

- `zr-repos.toml`의 `[deps]`에 선언된 의존성으로 레포 간 그래프 구성
- 각 레포 내부의 패키지 그래프와 결합하여 전체 시스템 그래프 생성
- `zr affected`가 레포 경계를 넘어 동작

```bash
zr graph --all-repos             # 크로스레포 의존성 그래프
zr affected build --all-repos    # 변경된 레포 + 의존 레포에서 빌드
```

#### 5.9.3 크로스레포 태스크 실행

```bash
zr repo run build                # 모든 레포에서 build 태스크 실행
zr repo run test --affected      # 변경된 레포에서만 test 실행
zr repo run lint --repos=api,frontend  # 특정 레포만 대상
zr repo run deploy --tags=backend     # 태그 기반 필터
```

크로스레포 의존성 순서를 존중하여 실행한다. `shared-lib` → `api` → `frontend` 순서가 보장된다.

#### 5.9.4 합성 워크스페이스 (Synthetic Workspace)

멀티레포 환경을 마치 모노레포인 것처럼 다룰 수 있다.

```bash
zr workspace sync                # 합성 워크스페이스 구성
zr graph                         # 모든 레포의 프로젝트를 하나의 그래프로 표시
zr affected build                # 레포 경계 없이 affected 감지
```

**동작 원리**: `zr-repos.toml`에 등록된 모든 레포의 `zr.toml`을 읽어 하나의 통합 프로젝트 그래프를 구성한다. 각 레포는 워크스페이스의 최상위 패키지로 취급된다.

### 5.10 엔터프라이즈 기능 (Progressive Unlock) `v2.0`

프로젝트 규모가 커짐에 따라 점진적으로 활성화되는 고급 기능.

#### 5.10.1 빌드 분석 (Analytics)

```bash
zr analytics                     # 로컬 HTML 리포트 생성 후 브라우저에서 열기
zr analytics --json              # JSON 원본 데이터 출력
```

**리포트 내용**:
- 태스크별 실행 시간 추이 (시간 경과에 따른 변화)
- 캐시 히트율 (전체, 태스크별)
- 실패 패턴 분석 (어떤 태스크가 가장 자주 실패하는지)
- 크리티컬 패스 분석 (전체 빌드 시간의 병목이 되는 경로)
- 병렬화 효율 (실제 vs 이론적 최대 병렬화)

데이터는 로컬 실행 이력 DB에 저장되며, 외부 서비스 의존 없음.

#### 5.10.2 퍼블리싱 & 버저닝

모노레포 패키지의 버전 관리와 레지스트리 퍼블리싱을 자동화한다.

```toml
[versioning]
mode = "independent"             # independent | fixed
convention = "conventional"      # conventional commits 기반 자동 버전 결정
```

```bash
zr version                       # 인터랙티브 버전 범프
zr version --bump=minor          # 전체 마이너 버전 업
zr publish                       # 변경된 패키지 빌드 → 버전 범프 → 체인지로그 → 퍼블리시
zr publish --dry-run             # 퍼블리시 대상 미리보기
```

**버저닝 모드**:
- `fixed`: 모든 패키지가 동일 버전 (예: Angular 스타일)
- `independent`: 패키지별 독립 버전 (예: Babel 스타일)

**체인지로그**: Conventional Commits 메시지를 파싱하여 `CHANGELOG.md` 자동 생성.

#### 5.10.3 AI 친화적 메타데이터

AI 코딩 에이전트(Claude Code, Cursor, GitHub Copilot Workspace 등)가 프로젝트 구조를 이해할 수 있도록 구조화된 메타데이터를 생성한다.

```bash
zr context                       # 프로젝트 맵 출력 (기본: JSON)
zr context --format=yaml         # YAML 포맷
zr context --scope=packages/api  # 특정 패키지 스코프
```

**출력 내용**:
- 프로젝트 그래프 (패키지 목록, 의존성)
- 태스크 카탈로그 (패키지별 사용 가능한 태스크)
- 파일 소유권 매핑 (CODEOWNERS 기반)
- 최근 변경 요약 (최근 N개 커밋의 변경 패키지)
- 툴체인 정보 (사용 중인 도구 및 버전)

AI 에이전트가 이 출력을 컨텍스트로 소비하여, 프로젝트 구조를 파악하고 적절한 파일을 수정할 수 있다.

### 5.11 LanguageProvider 인터페이스 `v3.0`

현재 8개 언어(Node/Python/Zig/Go/Rust/Deno/Bun/Java)가 `downloader.zig`, `registry.zig`, `path.zig`, `tools.zig` 등 6개 이상의 파일에 걸쳐 switch문으로 하드코딩되어 있다. 새 언어 추가 시 최소 6파일을 수정해야 하며, 누락 시 런타임 에러 발생.

**해결**: 각 언어를 단일 구조체(`LanguageProvider`)로 캡슐화하고, 레지스트리 패턴으로 컴파일타임에 등록한다.

```zig
pub const LanguageProvider = struct {
    name: []const u8,                          // "ruby"
    display_name: []const u8,                  // "Ruby"
    detect_files: []const []const u8,          // &.{"Gemfile", ".ruby-version"}

    // 툴체인
    resolveDownloadUrl: *const fn(version, platform, arch) DownloadSpec,
    fetchLatestVersion: *const fn(allocator) ?ToolVersion,
    getBinDir: *const fn(install_dir) []const u8,
    getEnvVars: *const fn(install_dir) []EnvVar,

    // 프로젝트 감지 & 태스크 추출
    detectProject: *const fn(dir) bool,
    extractTasks: *const fn(allocator, dir) []TaskTemplate,
    generateConfig: *const fn(allocator, dir) []const u8,
};
```

**결과**:
- 새 언어 추가 = `src/lang/<name>.zig` 1파일 작성 + `registry.zig`에 1줄 등록
- `detectProject()` + `extractTasks()` → `zr init --detect` 기능의 핵심 엔진
- `generateConfig()` → MCP `generate_config` 도구에서 재사용

### 5.12 MCP Server `v3.0`

zr을 [Model Context Protocol (MCP)](https://modelcontextprotocol.io/) 서버로 노출하여 Claude Code, Cursor 등 AI 에이전트에서 직접 태스크를 실행한다.

```bash
zr mcp serve                  # MCP 서버 시작 (JSON-RPC over stdio)
```

**MCP 도구 목록**:

| Tool | 매핑 대상 | 설명 |
|------|----------|------|
| `run_task` | `cmdRun()` | 태스크 실행 |
| `list_tasks` | `cmdList()` | 태스크 목록 조회 |
| `show_task` | `cmdShow()` | 태스크 상세 정보 |
| `validate_config` | `cmdValidate()` | 설정 파일 검증 |
| `show_graph` | `cmdGraph()` | 의존성 그래프 조회 |
| `run_workflow` | `cmdWorkflow()` | 워크플로우 실행 |
| `task_history` | `cmdHistory()` | 실행 이력 조회 |
| `estimate_duration` | `cmdEstimate()` | 소요시간 추정 |
| `generate_config` | LanguageProvider | zr.toml 자동생성 |

**핵심 설계**:
- 기존 CLI 함수들이 모두 `*std.Io.Writer`를 받으므로, MCP 핸들러는 in-memory writer를 전달하여 결과를 캡처. 비즈니스 로직 중복 없음
- JSON-RPC 2.0 over stdio 프로토콜 (LSP와 트랜스포트 레이어 공유)
- MCP capability 협상 (tools, resources)

**사용 예시** (Claude Code `claude_desktop_config.json`):
```json
{
  "mcpServers": {
    "zr": {
      "command": "zr",
      "args": ["mcp", "serve"]
    }
  }
}
```

### 5.13 LSP Server `v3.0`

zr.toml 편집을 위한 [Language Server Protocol](https://microsoft.github.io/language-server-protocol/) 서버. VS Code, Neovim 등에서 실시간 피드백을 제공한다.

```bash
zr lsp                        # LSP 서버 시작 (JSON-RPC over stdio, Content-Length 프레이밍)
```

**지원 기능**:

#### 5.13.1 실시간 진단 (Diagnostics)
- TOML 구문 에러 (줄/열 번호 포함)
- 알 수 없는 필드명 (+ "Did you mean?" 제안)
- 필수 필드 누락 (`cmd` 없는 태스크)
- 존재하지 않는 태스크 참조 (`deps`)
- 순환 의존성 감지 (`src/graph/cycle_detect.zig` 재사용)
- 잘못된 expression 구문 (`src/config/expr.zig` 재사용)

#### 5.13.2 자동완성 (Completion)
- `[tasks.` 뒤 → 기존 태스크 이름
- 태스크 섹션 내 → 필드명 (`cmd`, `deps`, `env`, `timeout` 등)
- `deps = ["` 뒤 → 설정 내 모든 태스크 이름
- `condition = "` 뒤 → 표현식 키워드
- `[tools]` 섹션 → LanguageProvider의 지원 언어 목록
- 불리언 필드 → `true` / `false`

#### 5.13.3 Hover 문서 + Go-to-Definition
- 필드에 마우스를 올리면 설명·타입·기본값 표시
- `deps` 내 태스크 이름 클릭 → 해당 태스크 정의로 이동

**핵심 설계**: JSON-RPC 트랜스포트는 MCP Server와 공유. Content-Length 프레이밍(LSP) + 줄바꿈 구분(MCP) 모두 지원하는 단일 트랜스포트.

### 5.14 자연어 인터페이스 `v3.0`

패턴 기반 자연어 → zr 명령어 매핑. LLM API 의존 없이 키워드 매칭으로 동작한다.

```bash
zr ai "빌드하고 테스트해줘"      # → zr run build && zr run test
zr ai "프론트엔드 배포"          # → zr run deploy-frontend
zr ai "어제 실패한 태스크"       # → zr history --status=failed --since=1d
```

MCP 환경에서는 Claude가 이미 자연어를 이해하므로, 이 기능은 주로 CLI 단독 사용 시 편의를 위한 것이다.

### 5.15 DX 개선 `v3.0`

#### 5.15.1 "Did you mean?" 제안
Levenshtein 편집 거리 기반으로 오타 시 가까운 명령어/태스크를 제안한다.

```bash
$ zr rn build
✗ Unknown command: rn

  Did you mean 'run'?

$ zr run biuld
✗ Unknown task: biuld

  Did you mean 'build'?

  Available tasks: build, build-frontend, build-backend
```

명령어와 태스크 이름 모두에 적용. 편집 거리 ≤ 3인 후보만 제안.

#### 5.15.2 에러 메시지 강화
- TOML 파싱 에러에 정확한 줄번호/열 번호 표시
- 존재하지 않는 `deps` 참조 시 가까운 태스크 이름 제안
- 설정 검증 에러에 수정 힌트 포함

```
✗ Task 'deploy': dependency 'biuld' not found (line 15, col 9)

  deps = ["biuld"]
          ^^^^^^^

  Did you mean 'build'?
```

#### 5.15.3 대화형 init

```bash
zr init --detect              # 프로젝트 자동 감지 → zr.toml 생성
```

LanguageProvider의 `detectProject()` + `extractTasks()` + `generateConfig()`를 활용하여 프로젝트의 언어·스크립트를 자동 감지하고 설정 파일을 생성한다.

```
$ zr init --detect
✓ Detected: Node.js (package.json)
  Found 5 npm scripts: build, test, lint, start, dev

  Generated zr.toml with 5 tasks

  Hint: Run 'zr list' to see your tasks
```

복수 언어 감지 지원: monorepo에서 Node + Python + Go 동시 감지 가능.

---

## 6. 설정 파일 전체 스키마

```toml
# zr.toml — Full Schema Reference

# ─── 글로벌 설정 ───
[global]
shell = "bash"                        # 기본 셸
dotenv = true                         # .env 자동 로드
log_level = "info"                    # trace|debug|info|warn|error
log_format = "pretty"                 # pretty|json|plain

[global.resources]
max_workers = 8
max_total_memory = "8GB"
max_cpu_percent = 80

# ─── 환경 변수 ───
[env]
GLOBAL_VAR = "value"
FROM_SHELL = "$(git rev-parse --short HEAD)"

# ─── 태스크 정의 ───
[tasks.example]
cmd = "echo hello"
# ... (5.1.1 태스크 스키마 참조)

# ─── 워크플로우 정의 ───
[workflows.release]
# ... (5.2.3 파이프라인 스키마 참조)

# ─── 워크스페이스 (모노레포 지원) ───
[workspace]
members = ["packages/*", "apps/*"]    # glob 패턴
ignore = ["**/node_modules"]

# ─── 파일 감시 ───
[watch]
debounce = "500ms"                    # 이벤트 디바운스
ignore = ["**/node_modules", "**/.git", "**/dist"]

[watch.rules]
"src/**/*.ts" = "build-frontend"      # glob → 태스크 매핑
"backend/**/*.zig" = "build-backend"

# ─── 플러그인 ───
[plugins.name]
source = "registry:org/name@version"
config = {}

# ─── 프로필 ───
[profiles.ci]
env = { CI = "true" }
resources = { max_workers = 4 }

[profiles.dev]
env = { NODE_ENV = "development" }
watch = true

# ─── 툴체인 (Phase 6) ───
[tools]
node = "20.11"
python = "3.12"

# ─── 캐시 (Phase 5, 7) ───
[cache]
enabled = true
local_dir = ".zr-cache"

[cache.remote]
type = "s3"                      # s3 | gcs | azure | http
bucket = "team-cache"
region = "ap-northeast-2"

# ─── 아키텍처 제약 (Phase 5) ───
[[constraints]]
rule = "tag-based"
from = { tag = "app" }
to = { tag = "lib" }
allow = true

# ─── 소유권 (Phase 8) ───
[ownership]
owners = ["@team-core"]

# ─── 프로젝트 셋업 (Phase 6) ───
[setup]
steps = ["tools", "deps", "env", "validate"]

# ─── 버저닝 (Phase 8) ───
[versioning]
mode = "independent"
convention = "conventional"
```

---

## 7. Architecture

### 7.1 시스템 아키텍처

```
┌─────────────────────────────────────────────────────┐
│                    CLI Interface                     │
│  (Argument Parser, Help, Completion, TUI)           │
└──────────────┬──────────────────────────────────────┘
               │
┌──────────────▼──────────────────────────────────────┐
│                  Config Engine                       │
│  (TOML Parser → Schema Validation → Expression      │
│   Engine → Profile Resolution → Env Interpolation)  │
└──────────────┬──────────────────────────────────────┘
               │
┌──────────────▼──────────────────────────────────────┐
│               Task Graph Engine                      │
│  (DAG Builder → Cycle Detection → Topological Sort  │
│   → Critical Path → Dependency Resolution)          │
└──────────────┬──────────────────────────────────────┘
               │
┌──────────────▼──────────────────────────────────────┐
│               Execution Engine                       │
│  ┌──────────┐ ┌───────────┐ ┌────────────────────┐  │
│  │ Scheduler│ │Worker Pool│ │ Resource Manager    │  │
│  │          │ │(N threads)│ │ (CPU/Mem/Timeout)   │  │
│  └──────────┘ └───────────┘ └────────────────────┘  │
│  ┌──────────┐ ┌───────────┐ ┌────────────────────┐  │
│  │  Process │ │   I/O     │ │  Signal Handler    │  │
│  │  Manager │ │  Manager  │ │  (SIGINT/SIGTERM)  │  │
│  └──────────┘ └───────────┘ └────────────────────┘  │
└──────────────┬──────────────────────────────────────┘
               │
┌──────────────▼──────────────────────────────────────┐
│                Plugin System                         │
│  (Native .so/.dylib + WASM Sandbox + Hook Registry) │
└─────────────────────────────────────────────────────┘
```

### 7.2 모듈 구조

> **참고**: 아래 파일/폴더 구조는 초기 설계 참고안이며, 구현이 진행됨에 따라 변경될 수 있다. 실제 구조는 소스 코드를 기준으로 한다.

```
src/
├── main.zig                # 엔트리포인트
├── cli/
│   ├── parser.zig          # 인자 파싱
│   ├── help.zig            # 도움말 생성
│   ├── completion.zig      # 셸 자동완성
│   └── tui.zig             # 인터랙티브 TUI
├── config/
│   ├── loader.zig          # TOML 로드 & 파싱
│   ├── schema.zig          # 스키마 정의 & 검증
│   ├── expression.zig      # 표현식 엔진 (lexer + parser + evaluator)
│   ├── interpolation.zig   # 환경 변수 보간
│   └── profile.zig         # 프로필 관리
├── graph/
│   ├── dag.zig             # DAG 구현
│   ├── topo_sort.zig       # 토폴로지 정렬
│   ├── cycle_detect.zig    # 순환 감지
│   └── visualize.zig       # 그래프 시각화
├── exec/
│   ├── scheduler.zig       # 태스크 스케줄러
│   ├── worker_pool.zig     # 워커 풀 (스레드 관리)
│   ├── process.zig         # 자식 프로세스 관리
│   ├── resource.zig        # 자원 관리 (CPU/메모리/타임아웃)
│   ├── io_manager.zig      # 출력 캡처 & 스트리밍
│   └── signal.zig          # 시그널 핸들링
├── plugin/
│   ├── loader.zig          # 플러그인 동적 로딩
│   ├── wasm_runtime.zig    # WASM 샌드박스
│   ├── registry.zig        # 플러그인 레지스트리
│   └── api.zig             # 플러그인 인터페이스 정의
├── watch/
│   ├── watcher.zig         # 파일시스템 감시 (inotify/kqueue/ReadDirectoryChanges)
│   └── debounce.zig        # 이벤트 디바운스
├── output/
│   ├── renderer.zig        # 터미널 출력 렌더링
│   ├── color.zig           # ANSI 컬러
│   ├── progress.zig        # 프로그레스 바
│   └── table.zig           # 테이블 포매터
├── history/
│   ├── store.zig           # 실행 이력 저장 (SQLite or 파일)
│   └── query.zig           # 이력 조회
├── lang/                      # LanguageProvider (Phase 9A) `v3.0`
│   ├── provider.zig           # LanguageProvider 인터페이스 정의
│   ├── registry.zig           # 컴파일타임 provider 등록
│   ├── node.zig               # Node.js provider
│   ├── python.zig             # Python provider
│   ├── zig_lang.zig           # Zig provider
│   ├── go.zig                 # Go provider
│   ├── rust.zig               # Rust provider
│   ├── deno.zig               # Deno provider
│   ├── bun.zig                # Bun provider
│   └── java.zig               # Java provider
├── jsonrpc/                   # JSON-RPC 공유 인프라 (Phase 9B) `v3.0`
│   ├── types.zig              # Request, Response, Notification, Error 타입
│   ├── parser.zig             # JSON-RPC 메시지 파싱
│   ├── writer.zig             # JSON-RPC 직렬화
│   ├── transport.zig          # Stdio 트랜스포트
│   └── json.zig               # JSON 빌더/파서 유틸리티
├── mcp/                       # MCP Server (Phase 10A) `v3.0`
│   ├── server.zig             # MCP 서버 메인 루프, capability 협상
│   ├── handlers.zig           # 도구 호출 핸들러
│   └── tools.zig              # 도구 정의 (이름, 설명, JSON Schema)
├── lsp/                       # LSP Server (Phase 11) `v3.0`
│   ├── server.zig             # LSP 서버 메인 루프
│   ├── handlers.zig           # LSP 메서드 핸들러
│   ├── document.zig           # 열린 문서 상태 관리
│   ├── diagnostics.zig        # 검증 에러 → LSP Diagnostic 변환
│   ├── completion.zig         # 컨텍스트별 자동완성
│   ├── hover.zig              # Hover 문서
│   ├── definition.zig         # Go-to-Definition
│   └── position.zig           # 줄/열 위치 추적
└── util/
    ├── glob.zig            # Glob 패턴 매칭
    ├── duration.zig        # 시간 파싱 ("5m", "30s")
    ├── semver.zig          # 시맨틱 버전 파싱
    ├── hash.zig            # 파일 해시
    └── levenshtein.zig     # 편집 거리 계산 (Phase 9C) `v3.0`
```

### 7.3 Zig 기술 선택 근거

| 영역 | 접근 방식 | 이유 |
|------|-----------|------|
| 동시성 | `std.Thread` + 워커 풀 | Zig의 async가 아직 실험적이므로 안정적인 OS 스레드 사용 |
| TOML 파싱 | 자체 구현 또는 `zig-toml` | 외부 의존성 최소화 |
| 프로세스 관리 | `std.process.Child` | 표준 라이브러리의 안정적인 API |
| 파일 감시 | OS별 syscall 래핑 (inotify/kqueue/IOCP) | 크로스 플랫폼 지원 |
| TUI | 자체 구현 (ANSI escape) | 의존성 없는 경량 구현 |
| 플러그인 | `std.DynLib` + WASM (wasmtime-zig) | 네이티브 성능 + 샌드박스 안전성 |

---

## 8. Non-Functional Requirements

### 8.1 성능 목표

| 지표 | 목표 | 비고 |
|------|------|------|
| 콜드 스타트 | < 10ms | 설정 파일 파싱 ~ 태스크 준비 완료 |
| 100개 태스크 그래프 해석 | < 5ms | DAG 구성 + 토폴로지 정렬 |
| 메모리 사용 (본체) | < 10MB | 실행되는 자식 프로세스 제외 |
| 바이너리 크기 | < 5MB | 릴리스 빌드, 스트립 후 |
| 크로스 컴파일 | 6 타겟 | linux-x86_64, linux-aarch64, macos-x86_64, macos-aarch64, windows-x86_64, windows-aarch64 |

### 8.2 안정성

- 모든 에러 경로에서 graceful shutdown (자식 프로세스 정리, 임시 파일 삭제)
- SIGINT/SIGTERM 수신 시 실행 중 태스크에 SIGTERM 전파 → grace period 후 SIGKILL
- 비정상 종료 시 lock 파일 자동 정리
- 실행 이력에 crash 로그 기록

### 8.3 테스트 전략

| 레벨 | 범위 | 도구 |
|------|------|------|
| Unit | 각 모듈의 순수 함수 | Zig 내장 `test` |
| Integration | 설정 파싱 → 그래프 구성 → 실행 E2E | 테스트 프로세스 + 임시 디렉토리 |
| CLI | 커맨드 파싱, 출력 포맷 | 스냅샷 테스트 |
| Cross-platform | 6개 타겟 빌드 & 기본 기능 검증 | CI matrix (GitHub Actions) |
| Stress | 1000개 태스크, 깊은 의존성 체인 | 벤치마크 스위트 |

### 8.4 보안

- 플러그인 WASM 샌드박스: 파일시스템·네트워크 접근 제한
- 환경 변수의 secret 마스킹 (로그 출력 시 `$SECRET_*` 패턴 마스킹)
- 설정 파일에서 `shell()` 표현식의 실행 범위 제한 (read-only 결과만 허용)

---

## 9. Development Phases

### Phase 1 — Foundation (MVP)
**목표: 기본적인 태스크 정의·실행이 동작하는 상태**

- TOML 설정 파일 파서
- 기본 태스크 정의 & 실행 (`cmd`, `cwd`, `env`)
- 의존성 그래프 (DAG) 구성 & 순환 감지
- 병렬 실행 엔진 (워커 풀)
- 기본 CLI (`run`, `list`, `graph`)
- 컬러 출력, 에러 포맷팅
- 크로스 컴파일 CI 파이프라인

### Phase 2 — Workflow & Control
**목표: 실무에서 쓸 수 있는 수준의 워크플로우 관리**

- 워크플로우/파이프라인 정의 & 실행
- 표현식 엔진 (조건 분기, 매트릭스)
- 타임아웃, 재시도, 실패 허용
- `deps_serial`, 스테이지 순차 실행
- 프로필 시스템
- `watch` 모드 (파일 감시 → 자동 재실행)
- 실행 이력 저장 & 조회

### Phase 3 — Resource & UX
**목표: 프로덕션급 자원 관리와 뛰어난 사용 경험**

- 자원 제한 (CPU, 메모리, 동시성)
- 자원 모니터링 실시간 표시
- 인터랙티브 TUI 모드
- 셸 자동완성 (bash, zsh, fish)
- `dry-run` 모드
- JSON/machine-readable 출력 포맷
- 워크스페이스 (모노레포) 지원

### Phase 4 — Extensibility
**목표: 커뮤니티가 확장할 수 있는 플랫폼**

- 플러그인 시스템 (네이티브 + WASM)
- 빌트인 플러그인 (docker, git, env, notify, cache)
- 플러그인 레지스트리
- 플러그인 개발 SDK & 문서
- Remote cache (선택적)

### Phase 5 — Monorepo Intelligence `v2.0`
**목표: 대규모 모노레포에서 효율적인 빌드·테스트**

- Affected 감지 (git diff + 의존성 그래프 순회)
- 콘텐츠 해시 캐싱 (소스 파일·명령어·환경 해시 기반)
- 프로젝트 그래프 시각화 (ASCII, DOT, JSON, HTML)
- 아키텍처 제약 조건 (`[constraints]`, `zr lint`)
- 모듈 경계 규칙 (태그 기반 의존성 제어)

### Phase 6 — Developer Environment `v2.0`
**목표: 원커맨드 프로젝트 온보딩**

- 툴체인 관리 (`[tools]` 섹션 — 도구 버전 자동 설치·전환)
- 환경 레이어링 (워크스페이스 → 프로젝트 → 태스크)
- `zr setup` — 전체 프로젝트 셋업 자동화
- `zr doctor` — 환경 진단 (도구 버전·연결 상태·설정 검증)
- 시크릿 마스킹 (`*_SECRET`, `*_TOKEN`, `*_KEY` 패턴)

### Phase 7 — Multi-repo & Remote Cache `v2.0`
**목표: 분리된 레포를 통합된 하나의 시스템으로**

- 레포 레지스트리 (`zr-repos.toml`)
- `zr repo sync` / `zr repo status` — 멀티레포 관리 명령
- 크로스레포 태스크 실행 & 의존성 그래프
- 합성 워크스페이스 모드 (멀티레포 → 논리적 모노레포)
- 원격 캐시 (S3/GCS/Azure/HTTP 호환, 자체 호스팅)

### Phase 8 — Enterprise & Community `v2.0`
**목표: 엔터프라이즈 환경에서의 거버넌스와 자동화**

- CODEOWNERS 자동 생성 (`zr codeowners generate`)
- 퍼블리싱 & 버저닝 자동화 (`zr publish`, `zr version`)
- 빌드 분석 리포트 (로컬 HTML — 실행 시간 추이, 캐시 히트율, 크리티컬 패스)
- AI 친화적 메타데이터 생성 (`zr context`)
- Conformance 규칙 엔진 (고급 아키텍처 거버넌스)

### Phase 9 — 기반 인프라 + DX 퀵윈 `v3.0`
**목표: v1.0 릴리스를 위한 기반 인프라 구축과 즉각적인 DX 개선**

- **9A LanguageProvider 인터페이스**: 8개 언어를 단일 구조체로 캡슐화, 레지스트리 패턴으로 등록. 새 언어 추가 = 파일 1개
- **9B JSON-RPC 공유 인프라**: MCP와 LSP가 공유하는 JSON-RPC 2.0 트랜스포트 레이어 (Content-Length + newline-delimited 모두 지원)
- **9C "Did you mean?" 제안**: Levenshtein 편집 거리 기반 명령어/태스크 이름 오타 제안
- **9D 에러 메시지 개선**: 파싱 에러에 줄/열 번호, 미존재 deps에 유사 이름 제안

**의존성**: 9A, 9B, 9C 병렬 개발 가능. 9D는 9C(Levenshtein)에 의존.

### Phase 10 — MCP Server + AI 통합 `v3.0`
**목표: AI 에이전트에서 zr을 직접 호출할 수 있는 MCP 서버**

- **10A MCP Server 코어**: JSON-RPC 기반 MCP 서버, 9개 도구 노출 (run_task, list_tasks, validate_config 등)
- **10B zr.toml 자동생성**: `zr init --detect` — LanguageProvider 기반 프로젝트 감지 및 설정 생성
- **10C 자연어 인터페이스**: `zr ai "빌드하고 테스트해줘"` — 키워드 패턴 매핑 (LLM API 의존 X)

**의존성**: 10A는 9B(JSON-RPC)에 의존. 10B는 9A(LanguageProvider)에 의존. 10A와 10B 병렬 가능.

### Phase 11 — Full LSP Server `v3.0`
**목표: VS Code/Neovim에서 zr.toml 편집 시 실시간 자동완성·에러 진단**

- **11A LSP 코어 + 진단**: LSP 서버 메인 루프, 열린 문서 관리, TOML 파싱 에러·스키마 검증 → Diagnostic 변환
- **11B 자동완성**: 컨텍스트별 완성 (태스크명, 필드명, deps, 표현식 키워드, 도구 목록)
- **11C Hover 문서 + Go-to-Definition**: 필드 hover 시 문서 표시, deps 내 태스크 → 정의로 이동

**의존성**: 11A는 9B(JSON-RPC)에 의존. 11B, 11C는 11A에 의존.

### Phase 12 — 성능 & 안정성 `v3.0`
**목표: v1.0 품질 기준 달성 — 바이너리 최적화, 퍼징, 벤치마크**

- **12A 바이너리 최적화**: `build.zig`에 ReleaseSmall + strip 옵션 추가 (~2.9MB → ~1.5-2MB)
- **12B Fuzz Testing**: TOML 파서, 표현식 엔진, JSON-RPC 파서 퍼징 (10분+ 크래시 없음)
- **12C 벤치마크 대시보드**: Make, Just, Task(go-task) 대비 성능 비교 스크립트 + 결과 문서

**의존성**: 12A, 12B, 12C 모두 독립 — 언제든 병렬 가능.

### Phase 13 — v1.0 릴리스 `v3.0`
**목표: 공식 v1.0 릴리스 — 문서, 마이그레이션, README 리뉴얼**

- **13A 문서 사이트**: getting-started, configuration, commands, mcp-integration, lsp-setup, adding-language 가이드
- **13B 마이그레이션 가이드 + 자동 변환**: `zr init --from-make`, `--from-just`, `--from-task` 자동 변환
- **13C README 리뉴얼 + v1.0 태그**: 전면 개편된 README, 릴리스 노트, 태그

**의존성**: Phase 9–12 완료 후.

**Phase 9-13 의존성 그래프**:
```
Phase 9 (기반):
  9A LanguageProvider ──┐
  9B JSON-RPC ─────┐   │
  9C Levenshtein ──┤   │
                   ▼   │
  9D 에러 개선 ←─(9C)  │
                       │
Phase 10 (AI):         │         Phase 11 (LSP):
  10A MCP ←── 9B       │          11A LSP Core ←── 9B
  10B 자동생성 ←── 9A ─┘          11B 자동완성 ←── 11A (+9A)
  10C 자연어 ←── 10A              11C Hover/Goto ←── 11A

Phase 12 (성능): 독립, 언제든 병렬 가능

Phase 13 (릴리스): Phase 9-12 완료 후
```

---

## 10. Success Metrics

### 10.1 Phase 1–4 (Task Runner)

| 지표 | Phase 1 | Phase 2 | Phase 4 |
|------|---------|---------|---------|
| GitHub Stars | 100+ | 500+ | 2000+ |
| 설정 파일 스키마 커버리지 | 기본 태스크 | 워크플로우 + 표현식 | 플러그인 포함 전체 |
| 크로스 플랫폼 빌드 | 6 타겟 | 6 타겟 | 6 타겟 |
| 빌트인 플러그인 | 0 | 0 | 5+ |
| 문서 페이지 | Quick Start | Full Guide | Plugin Dev Guide |
| 벤치마크 vs Just/Task | 동등 | 1.5x 빠름 | 2x+ 빠름 |

### 10.2 Phase 5–8 (Developer Platform) `v2.0`

| 지표 | Phase 5 | Phase 6 | Phase 7 | Phase 8 |
|------|---------|---------|---------|---------|
| CI 시간 단축 (affected) | 50%+ 감소 | — | 크로스레포도 50%+ | — |
| 캐시 히트율 (성숙 프로젝트) | 로컬 70%+ | — | 원격 포함 80%+ | — |
| 셋업 시간 (git clone → 개발 가능) | — | < 2분 | — | — |
| 지원 툴체인 수 | — | 코어 8+, 플러그인 확장 | — | — |
| 멀티레포 관리 가능 수 | — | — | 20+ 레포 | — |
| CODEOWNERS 자동화 | — | — | — | 100% 커버리지 |
| AI 에이전트 연동 | — | — | — | Claude Code, Cursor |
| GitHub Stars | 3000+ | 5000+ | 7000+ | 10000+ |

### 10.3 Phase 9–13 (v1.0 Release) `v3.0`

| 지표 | Phase 9 | Phase 10 | Phase 11 | Phase 12 | Phase 13 |
|------|---------|----------|----------|----------|----------|
| 새 언어 추가 소요 파일 수 | 1파일 | — | — | — | — |
| MCP 도구 수 | — | 9+ 도구 | — | — | — |
| MCP 연동 검증 | — | Claude Code, Cursor | — | — | — |
| `zr init --detect` 지원 언어 | — | 8+ 언어 | — | — | — |
| LSP 진단 항목 수 | — | — | 6+ 종류 | — | — |
| LSP 자동완성 컨텍스트 | — | — | 6+ 유형 | — | — |
| VS Code 연동 검증 | — | — | 실시간 에러·완성 | — | — |
| 바이너리 크기 | — | — | — | ≤ 2MB | — |
| 퍼징 (크래시 없음) | — | — | — | 10분+ | — |
| 벤치마크 vs Make/Just/Task | — | — | — | 문서화 | — |
| 문서 사이트 페이지 수 | — | — | — | — | 10+ |
| 마이그레이션 지원 도구 | — | — | — | — | Make, Just, Task |
| GitHub Stars | — | — | — | — | 15000+ |

---

## 11. Risks & Mitigations

| 리스크 | 영향 | 완화 전략 |
|--------|------|-----------|
| Zig 생태계 미성숙 (라이브러리 부족) | 개발 속도 저하 | 핵심 모듈 자체 구현, 외부 의존성 최소화 |
| WASM 플러그인 성능 오버헤드 | 플러그인 사용 시 체감 성능 저하 | 네이티브 플러그인 병행 지원, WASM은 보안 필요 시에만 |
| 크로스 플랫폼 자원 제한 API 차이 | OS별 코드 분기 증가 | 추상화 레이어 설계, Linux 우선 개발 → macOS/Windows 순차 지원 |
| 표현식 엔진 복잡도 | 버그 증가, 유지보수 부담 | 문법 최소화, 단계적 확장, 퍼징 테스트 |
| 기존 도구 대비 낮은 인지도 | 채택 어려움 | 킬러 UX (에러 메시지, TUI)로 차별화, 벤치마크 공개 |
| 범위 확장에 의한 복잡도 증가 | 코드 품질 저하, 릴리스 지연 | Phase별 명확한 경계, 각 Phase가 독립적으로 가치를 제공하도록 설계 |
| 툴체인 관리의 OS별 차이 | macOS/Linux/Windows 각각 다른 설치 경로·바이너리 포맷 | mise의 검증된 패턴 참고, 코어 툴체인 먼저 안정화 후 확장 |
| 원격 캐시 보안·신뢰성 | 캐시 오염(poisoning), 네트워크 장애 시 빌드 실패 | 캐시 무결성 검증(해시 비교), 원격 캐시 실패 시 로컬 폴백 |
| 멀티레포 환경의 복잡도 | 레포 간 버전 동기화, 인증 관리 등 예상 못한 엣지 케이스 | 점진적 기능 공개, 모노레포 먼저 안정화 후 멀티레포 지원 |
| MCP/LSP 프로토콜 구현 복잡도 `v3.0` | JSON-RPC, 프로토콜 스펙 준수에 많은 엣지 케이스 | JSON-RPC 공유 인프라로 중복 최소화, MCP 먼저 구현 후 LSP 확장 |
| MCP 스펙 변경 `v3.0` | MCP가 아직 초기 단계라 스펙이 변경될 수 있음 | 최소 도구 세트부터 시작, 추상화 레이어로 스펙 변경 격리 |
| LSP 에디터 호환성 `v3.0` | VS Code, Neovim, Emacs 등 에디터마다 LSP 구현 차이 | VS Code 우선 개발 및 검증, 표준 LSP 스펙 엄격 준수 |
| LanguageProvider 리팩토링 범위 `v3.0` | 기존 6개+ 파일 수정 필요, 리그레션 위험 | 기존 테스트 활용, 점진적 마이그레이션 (하나의 언어씩) |
| 자연어 인터페이스 정확도 `v3.0` | 패턴 매칭 기반이라 복잡한 자연어 이해 불가 | 명확한 한계 문서화, MCP 환경에서는 LLM이 직접 처리하도록 안내 |

---

## 12. Competitive Positioning

### 12.1 포지셔닝 맵

```
                 워크스페이스 관리
                      ▲
                      │
           Nx ●       │        ● Bazel/Buck2
                      │
      Turborepo ●     │   ● Moon
                      │
              zr ◆────┼───────────────────
                      │   Developer Platform
           Rush ●     │   (태스크 러닝 + 툴체인
                      │    + 모노/멀티레포)
     ──────────────────┼──────────────────► 빌드 시스템
          Just ●       │
          Task ●       │       ● Pants
          Make ●       │       ● Earthly
                       │
          mise ●       │
         (툴체인만)     │
                단일 프로젝트
```

zr의 포지셔닝은 **"폴리글랏 개발자 플랫폼 — 벤더 락인 없이"** 이다. 기존 도구들이 하나의 축(태스크 러닝 OR 빌드 시스템 OR 툴체인 관리)에 특화된 반면, zr은 세 축을 하나의 바이너리에 통합한다.

### 12.2 기능 비교표

| 기능 | zr | Nx | Turborepo | Moon | mise | Bazel |
|------|:---:|:---:|:---------:|:----:|:----:|:-----:|
| **태스크 러너** | ✓ | ✓ | ✓ | ✓ | △ | ✓ |
| **의존성 그래프** | ✓ | ✓ | ✓ | ✓ | ✗ | ✓ |
| **Affected 감지** | ✓ | ✓ | ✓ | ✓ | ✗ | ✓ |
| **콘텐츠 해시 캐싱** | ✓ | ✓ | ✓ | ✓ | ✗ | ✓ |
| **원격 캐시** | ✓ (자체호스팅) | ✓ (Nx Cloud) | ✓ (Vercel) | ✓ | ✗ | ✓ |
| **툴체인 관리** | ✓ | ✗ | ✗ | △ | ✓ | ✗ |
| **환경 관리** | ✓ | ✗ | ✗ | △ | △ | ✗ |
| **멀티레포 지원** | ✓ | ✗ | ✗ | ✗ | ✗ | △ |
| **CODEOWNERS 생성** | ✓ | ✓ | ✗ | ✗ | ✗ | ✗ |
| **아키텍처 거버넌스** | ✓ | ✓ | ✗ | ✓ | ✗ | ✓ |
| **런타임 의존성** | 없음 | Node.js | Node.js | 없음 | 없음 | JVM |
| **폴리글랏** | ✓ | △ | △ | △ | ✓ | ✓ |
| **바이너리 크기** | ~3MB | ~200MB+ | ~50MB+ | ~15MB | ~20MB | ~100MB+ |
| **벤더 락인** | 없음 | Nx Cloud | Vercel | 없음 | 없음 | 없음 |
| **MCP Server** `v3.0` | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ |
| **LSP Server** `v3.0` | ✓ | △ | ✗ | ✗ | ✗ | △ |
| **프로젝트 자동 감지** `v3.0` | ✓ | ✓ | △ | ✓ | △ | ✗ |
| **설정 자동 생성** `v3.0` | ✓ | ✓ | ✗ | ✓ | ✗ | ✗ |
| **마이그레이션 도구** `v3.0` | ✓ (Make/Just/Task) | ✗ | ✗ | ✗ | ✗ | ✗ |

✓ = 완전 지원, △ = 부분 지원, ✗ = 미지원

### 12.3 zr의 차별점

1. **도구 통합**: 5개 이상의 도구(nvm + make + nx + direnv + ...)를 ~3MB 바이너리 하나로 대체
2. **모노 + 멀티 동일 지원**: 모노레포와 멀티레포를 동일한 수준의 1급 시민으로 다룸
3. **벤더 락인 없음**: 원격 캐시를 자체 S3/GCS/HTTP에 호스팅 — SaaS 종속 없음
4. **점진적 채택**: `zr init`으로 시작 → 필요할 때 캐싱·affected·툴체인 하나씩 활성화
5. **제로 런타임**: Node.js, Python, JVM 없이 단일 바이너리로 동작
6. **AI 네이티브** `v3.0`: MCP Server로 Claude Code/Cursor에서 직접 태스크 실행 — 빌드 도구 중 최초의 MCP 지원
7. **에디터 통합** `v3.0`: 전용 LSP Server로 zr.toml 실시간 자동완성·에러 진단 — VS Code 확장 불필요
8. **언어 확장성** `v3.0`: LanguageProvider 인터페이스로 새 언어 추가가 파일 1개 작성으로 완료

---

## Appendix A: 설정 파일 예시 (실전)

```toml
# zr.toml — Full-stack web app example

[global]
shell = "bash"
dotenv = true

[global.resources]
max_workers = 6

[env]
VERSION = "$(git describe --tags --always)"

# ─── 공통 태스크 ───

[tasks.clean]
cmd = "rm -rf dist/ build/ .cache/"
description = "Clean all build artifacts"

[tasks.install]
cmd = "npm ci"
cwd = "./frontend"

# ─── 프론트엔드 ───

[tasks.build-frontend]
cmd = "npm run build"
cwd = "./frontend"
deps = ["install"]
env = { NODE_ENV = "production", VITE_VERSION = "$VERSION" }
timeout = "3m"

[tasks.test-frontend]
cmd = "npm run test:ci"
cwd = "./frontend"
deps = ["install"]
timeout = "2m"

[tasks.lint-frontend]
cmd = "npx eslint src/ --max-warnings=0"
cwd = "./frontend"
deps = ["install"]

# ─── 백엔드 ───

[tasks.build-backend]
cmd = "zig build -Doptimize=ReleaseFast"
cwd = "./backend"
timeout = "5m"

[tasks.test-backend]
cmd = "zig build test"
cwd = "./backend"
timeout = "3m"

# ─── Docker ───

[tasks.docker-build]
cmd = ["docker", "build", "-t", "myapp:$VERSION", "."]
deps = ["build-frontend", "build-backend"]
timeout = "10m"

[tasks.docker-push]
cmd = ["docker", "push", "myapp:$VERSION"]
deps = ["docker-build"]
condition = "env.CI == 'true'"

# ─── 워크플로우 ───

[workflows.ci]
description = "CI pipeline"

[[workflows.ci.stages]]
name = "lint"
tasks = ["lint-frontend"]
parallel = true

[[workflows.ci.stages]]
name = "build"
tasks = ["build-frontend", "build-backend"]
parallel = true

[[workflows.ci.stages]]
name = "test"
tasks = ["test-frontend", "test-backend"]
parallel = true
fail_fast = true

[[workflows.ci.stages]]
name = "package"
tasks = ["docker-build", "docker-push"]
condition = "env.BRANCH == 'main'"

# ─── 개발 프로필 ───

[profiles.dev]
env = { NODE_ENV = "development" }
watch = true

[profiles.ci]
env = { CI = "true" }
resources = { max_workers = 4 }

# ─── 파일 감시 ───

[watch]
debounce = "300ms"

[watch.rules]
"frontend/src/**" = "build-frontend"
"backend/src/**" = "build-backend"
```

---

## Appendix B: CLI 사용 예시

```bash
# 초기화
zr init                              # zr.toml 생성

# 태스크 실행
zr run build-frontend                # 단일 태스크
zr run build-frontend build-backend  # 복수 태스크 (병렬)
zr run build-frontend -j4            # 최대 4 병렬
zr run build -- --verbose            # -- 이후 태스크에 인자 전달

# 워크플로우
zr workflow ci                       # CI 파이프라인 실행
zr workflow ci --from=test           # test 스테이지부터
zr workflow ci --dry-run             # 실행 계획만

# 탐색
zr list                              # 모든 태스크·워크플로우
zr list --json                       # JSON 출력
zr graph build-frontend              # 의존성 트리
zr graph build-frontend --dot | dot -Tpng -o graph.png

# 감시
zr watch build-frontend              # 파일 변경 시 자동 빌드
zr watch --all                       # watch.rules 전체 활성화

# 이력
zr history                           # 최근 실행 목록
zr history --task=build-frontend     # 특정 태스크 이력
zr history --last=10 --json          # 최근 10건 JSON

# 프로필
zr run build --profile=ci            # CI 프로필로 실행
zr run build --profile=dev           # 개발 프로필

# 기타
zr validate                          # 설정 파일 검증
zr completion bash >> ~/.bashrc      # 자동완성 설치
zr plugin list                       # 설치된 플러그인
zr plugin install docker             # 플러그인 설치

# ─── Phase 5+: 모노레포 인텔리전스 ───

# Affected 감지
zr affected build                    # 변경된 패키지 + 의존자만 빌드
zr affected test --base=main         # main 대비 변경 감지
zr affected --list                   # 변경된 패키지 목록만 출력

# 캐시 관리
zr cache status                      # 캐시 히트율, 크기 표시
zr cache clean --older=7d            # 오래된 캐시 삭제

# 프로젝트 그래프
zr graph --format=html               # 인터랙티브 HTML 그래프
zr graph --affected                  # 변경된 프로젝트 하이라이트

# 아키텍처 거버넌스
zr lint                              # 아키텍처 제약 조건 검증
zr codeowners generate               # CODEOWNERS 자동 생성

# ─── Phase 6: 개발 환경 ───

# 툴체인 관리
zr tools list                        # 현재 프로젝트 도구 버전
zr tools install                     # 선언된 도구 전부 설치
zr tools outdated                    # 새 버전 확인

# 프로젝트 셋업
zr setup                             # 원커맨드 프로젝트 온보딩
zr doctor                            # 환경 진단

# 환경 변수
zr env                               # 최종 환경 변수 표시
zr env --resolve SERVICE_NAME        # 변수 해석 과정 추적

# ─── Phase 7: 멀티레포 ───

# 레포 관리
zr repo sync                         # 모든 레포 clone/pull
zr repo status                       # 크로스레포 상태

# 크로스레포 실행
zr repo run build                    # 모든 레포에서 빌드
zr repo run test --affected          # 변경된 레포에서만 테스트
zr repo run lint --tags=backend      # 태그 기반 필터

# ─── Phase 8: 엔터프라이즈 ───

# 분석
zr analytics                         # 빌드 분석 HTML 리포트

# 퍼블리싱
zr version                           # 인터랙티브 버전 범프
zr publish --dry-run                 # 퍼블리시 대상 미리보기

# AI 메타데이터
zr context                           # 프로젝트 맵 JSON 출력
zr context --format=yaml             # YAML 포맷

# ─── Phase 9+: AI 통합 & DX ───

# MCP Server
zr mcp serve                         # MCP 서버 시작 (Claude Code/Cursor 연동)

# LSP Server
zr lsp                               # LSP 서버 시작 (VS Code/Neovim 연동)

# 자연어 인터페이스
zr ai "빌드하고 테스트해줘"             # → zr run build && zr run test
zr ai "프론트엔드 배포"                # → zr run deploy-frontend
zr ai "어제 실패한 태스크"              # → zr history --status=failed --since=1d

# 프로젝트 자동 감지 & 설정 생성
zr init --detect                     # 프로젝트 언어/스크립트 자동 감지 → zr.toml 생성

# 마이그레이션 (다른 도구에서 이전)
zr init --from-make                  # Makefile → zr.toml 변환
zr init --from-just                  # Justfile → zr.toml 변환
zr init --from-task                  # Taskfile.yml → zr.toml 변환
```
