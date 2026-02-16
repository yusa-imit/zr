# zr — Product Requirements Document

> **zr (zig-runner) — 범용 태스크 러너 & 워크플로우 매니저 CLI**
> 
> Version: 1.0 Draft
> Author: Yusa × Claude
> Date: 2026-02-16

---

## 1. Executive Summary

**zr**은 Zig로 작성된 범용 커맨드라인 태스크 러너이자 워크플로우 매니저이다. 레포지토리 구조(모노레포, 멀티레포, 단일 프로젝트)에 구애받지 않고, 어떤 언어·빌드 시스템·스크립트 환경에서든 태스크를 정의하고 의존성 그래프 기반으로 병렬·순차 실행할 수 있는 도구를 목표로 한다. 이름 자체가 2글자로, 타이핑 최소화를 통한 빠른 CLI 사용을 지향한다.

### 1.1 핵심 가치

- **언어·생태계 무관**: JS, Python, Go, Rust, Docker, shell script 등 어떤 명령이든 태스크로 등록 가능
- **단일 바이너리**: Zig의 크로스 컴파일로 macOS, Linux, Windows를 하나의 릴리스 파이프라인으로 커버
- **극한 성능**: C급 속도의 태스크 스케줄링, 그래프 해석, 프로세스 관리
- **유저 친화적 CLI**: 컬러풀한 출력, 프로그레스 표시, 인터랙티브 모드, 에러 메시지의 가독성

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

### 2.2 zr이 해결하는 핵심 문제

1. **런타임 의존성 제거**: Node.js, Python, Go 등 별도 런타임 설치 없이 단일 바이너리로 동작
2. **범용성**: 프로젝트 언어·구조와 무관하게 어디서든 사용 가능
3. **복잡한 워크플로우**: 단순 명령 실행을 넘어 의존성 그래프, 조건 분기, 파이프라인 체이닝, 에러 핸들링을 하나의 정의 파일에서 관리
4. **자원 관리**: CPU/메모리 제한, 동시 실행 수 제어, 타임아웃 등 프로덕션급 자원 관리
5. **확장성**: 플러그인으로 새로운 기능을 추가할 수 있는 아키텍처

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
  graph <task>          의존성 그래프 시각화
  watch <task...>       파일 변경 감지 → 자동 재실행
  init                  설정 파일 초기화
  validate              설정 파일 검증
  history               실행 이력 조회
  plugin                플러그인 관리
  completion            셸 자동완성 설치

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
└── util/
    ├── glob.zig            # Glob 패턴 매칭
    ├── duration.zig        # 시간 파싱 ("5m", "30s")
    ├── semver.zig          # 시맨틱 버전 파싱
    └── hash.zig            # 파일 해시
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

---

## 10. Success Metrics

| 지표 | Phase 1 | Phase 2 | Phase 4 |
|------|---------|---------|---------|
| GitHub Stars | 100+ | 500+ | 2000+ |
| 설정 파일 스키마 커버리지 | 기본 태스크 | 워크플로우 + 표현식 | 플러그인 포함 전체 |
| 크로스 플랫폼 빌드 | 6 타겟 | 6 타겟 | 6 타겟 |
| 빌트인 플러그인 | 0 | 0 | 5+ |
| 문서 페이지 | Quick Start | Full Guide | Plugin Dev Guide |
| 벤치마크 vs Just/Task | 동등 | 1.5x 빠름 | 2x+ 빠름 |

---

## 11. Risks & Mitigations

| 리스크 | 영향 | 완화 전략 |
|--------|------|-----------|
| Zig 생태계 미성숙 (라이브러리 부족) | 개발 속도 저하 | 핵심 모듈 자체 구현, 외부 의존성 최소화 |
| WASM 플러그인 성능 오버헤드 | 플러그인 사용 시 체감 성능 저하 | 네이티브 플러그인 병행 지원, WASM은 보안 필요 시에만 |
| 크로스 플랫폼 자원 제한 API 차이 | OS별 코드 분기 증가 | 추상화 레이어 설계, Linux 우선 개발 → macOS/Windows 순차 지원 |
| 표현식 엔진 복잡도 | 버그 증가, 유지보수 부담 | 문법 최소화, 단계적 확장, 퍼징 테스트 |
| 기존 도구 대비 낮은 인지도 | 채택 어려움 | 킬러 UX (에러 메시지, TUI)로 차별화, 벤치마크 공개 |

---

## 12. Competitive Positioning

```
                    범용성
                     ▲
                     │
          zr ● │
                     │          ● moon
          Task ●     │
                     │     ● Nx
          Just ●     │
                     │          ● Turborepo
     ─────────────────┼──────────────────► 기능 풍부
          Make ●      │
                      │
                      │
```

zr의 포지셔닝은 **"Make의 범용성 + Turborepo의 실행 엔진 + Just의 사용 편의성"** 을 하나의 바이너리에 담는 것이다.

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
```
