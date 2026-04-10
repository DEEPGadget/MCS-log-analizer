# MCS Log Analyzer — Claude Harness

## 하네스 구조 (Harness Engineering)

> **Harness Engineering**: 어떤 환경과 규칙 안에서 일하게 할지 정하는 일

이 프로젝트는 3개 레이어로 구성된 하네스다:

| 레이어 | 파일 | 역할 |
|--------|------|------|
| **지식 레이어** | `CLAUDE.md` (이 파일) | Claude가 읽는 규칙과 분석 기준 |
| **도구 레이어** | `Read`, `Grep`, `Write` | 로그 파일 읽기 및 보고서 저장 |
| **통제 레이어** | `.claude/settings.json` | Hook으로 자동 개입 규칙 정의 |

### 권한 정책

- **허용**: `Read` (압축 해제 경로 전체), `Grep` (패턴 검색), `Write` (`reports/` 경로만)
- **Approval 필요**: 기존 보고서 파일 덮어쓰기 (같은 이름의 `.md`가 이미 존재하는 경우)
- **금지**: `reports/` 외부 경로에 파일 쓰기, 시스템 명령 실행

### Plan Mode 사용 기준

아카이브 안에 파일이 200개를 초과하거나(`--detail` 모드 수집본) `var-log-archived/` 디렉터리가 존재하면,
분석을 바로 시작하지 말고 **Plan Mode로 먼저 탐색 범위를 확정**한 뒤 실행한다.

### AskUserQuestion 사용 기준

다음 상황에서는 분석을 멈추고 사용자에게 질문한다:
- 압축 해제 경로에 아카이브 루트 디렉터리가 2개 이상 존재하는 경우 (어느 것을 분석할지)
- 보고서 저장 경로에 동일한 파일이 이미 존재하는 경우 (덮어쓸지 여부)

---

## 프로젝트 목적

Manycore 고객사 서버에서 `deepgadget-log-grabber.sh`로 수집된 진단 아카이브(`.tar.gz`)를 분석하여
잠재적 문제를 탐지하고 한국어 보고서를 생성하는 시스템이다.

`analyze.sh`가 아카이브를 압축 해제한 후 Claude를 자동 실행한다.
Claude는 이 파일의 지침에 따라 로그를 읽고 `reports/` 디렉터리에 보고서를 작성해야 한다.

---

## 분석 실행 방법

`analyze.sh`가 다음 형식으로 Claude를 호출한다:
```
압축 해제 경로: /tmp/mcs-log-XXXXX/Manycore-bug-report
보고서 저장 경로: /home/deepgadget/MCS-log-analizer/reports/<이름>.md
```

### Claude가 해야 할 일 (2-pass 전략)

#### Pass 1 — Triage (빠른 탐색)

1. `_manifest.txt`를 Read하여 아카이브 전체 파일 구조와 크기를 파악한다
2. `_env-hints.txt`를 Read하여 환경 정보(WSL/VM/베어메탈, 호스트명)를 확인한다
3. **인벤토리 소스 먼저 Read** (이후 분석의 컨텍스트가 되므로 우선 파악):
   - `hw-list.txt` — CPU/메모리/슬롯 정보 (보통 수백 줄)
   - `nvidia-smi.txt` — GPU 목록, 드라이버 버전, 최대 지원 CUDA 버전 (표시되는 CUDA 버전은 해당 드라이버가 지원하는 최대 버전이며, 실제 설치된 CUDA Toolkit 버전과 다를 수 있음 — 실제 버전은 `nvcc -V` 결과인 `cuda-version.txt` 등으로 확인)
   - `gpu-serials.txt` — GPU 시리얼 + Bus ID (있는 경우)
   - `drives-and-storage/lsblk.txt` — 스토리지 장치 목록
   - `ibstat.txt` — InfiniBand 상태 (없으면 "없음")
4. **작은 파일 우선 Read** (대부분 수십 줄 이하):
   - `gpu-memory-errors/uncorrected-ecc_errors.txt`
   - `gpu-memory-errors/remapped-memory.txt`
   - `gpu-memory-errors/ecc-errors.txt`
   - `drives-and-storage/df.txt`
   - `drives-and-storage/mdstat.txt`
   - `sensors.txt`
   - `uptime.txt`
   - `systemctl-services.txt`
   - `bmc-info/ipmi-elist.txt`
   - `drives-and-storage/smartctl-*.txt` 파일들을 각각 Read한다
5. **전처리 파일 Read** (`_preprocessed/` 디렉터리):
   - `journalctl-boots.txt` — `-- Boot` 마커 목록 (재부팅 시점 + 줄번호)
   - `journalctl-boot-context.txt` — 각 Boot 경계 직전 40줄/직후 10줄 (종료 원인·복구 문맥)
   - `journalctl-errors.txt` — 키워드 필터된 에러/경고
   - `journalctl-lifecycle.txt` — 시스템 종료/재부팅 등 구조적 이벤트
   - `journalctl-density.txt` — 시간대별 로그 밀도 (비정상 폭주 구간)
   - `syslog-errors.txt` — syslog 에러 필터
   - `kern-errors.txt` — kern.log 에러 필터
   - `*-frequency.txt` — 에러 메시지별 빈도 집계
   - `dmesg-critical.txt` — dmesg-errors.txt가 대형(500줄+)인 경우에만 존재
   - `dmesg-crash-context.txt` — 원본 dmesg에서 `BUG:` / `Oops` / `panic` / `Call Trace` / `RIP:` 포함 줄 + 전후 문맥 (스택 트레이스). 크래시가 없으면 빈 파일
   - `dmesg-full-errors.txt` — 원본 dmesg의 에러/경고 필터 (err 미만 레벨 포함, dmesg-errors.txt 보완)
6. `system-logs/dmesg-errors.txt`는 전처리 파일(`dmesg-critical.txt`)이 없으면 원본을 직접 Read한다 (보통 소형)
   `dmesg-crash-context.txt`가 비어있지 않으면 크래시가 발생한 것이므로 반드시 내용을 확인한다

**중요**: 원본 `journalctl.txt`, `syslog`, `kern.log`를 직접 Read하거나 전체 Grep하지 않는다.
전처리 파일로 충분하며, 원본은 Pass 2에서 특정 시간대만 조회할 때만 사용한다.

#### Pass 2 — Deep-dive (상세 분석)

7. Pass 1에서 Critical 또는 Warning이 발견된 영역에 대해서만 추가 조사:
   - `journalctl-density.txt`에서 비정상 밀도 구간이 발견되면,
     해당 시간대(예: `Apr 07 10:23`)를 원본 `journalctl.txt`에서 Grep하여 문맥 확인
   - SMART Critical이면 해당 드라이브의 전체 smartctl 출력을 정밀 검토
   - GPU 에러 발견 시 `nvidia-bug-report.log`에서 관련 섹션 Grep (파일이 존재하는 경우)
8. 4순위 보조 정보 파일들을 확인한다 (`apt-history.log` 등)
9. 발견한 모든 문제를 심각도별로 분류하여 기록한다

### 자기검증 (보고서 저장 직전)

보고서를 Write하기 전에 다음을 확인한다:

1. **Critical 근거 재확인**: 각 Critical 이슈에 대해 "발견 위치"로 적은 파일의 해당 내용이 실제로 존재하는지 Grep 또는 Read로 한 번 더 확인한다. 확인되지 않는 이슈는 제거하거나 Info로 강등한다.
2. **심각도 일관성**: 같은 유형의 이슈가 다른 심각도로 분류되어 있지 않은지 확인한다.
3. **보고서 구조 검증**: 보고서가 지정된 마크다운 형식의 모든 필수 섹션을 포함하는지 확인한다:
   - 메타데이터 (분석 대상, 일시, 호스트명, 업타임, 환경)
   - 요약 테이블
   - Critical / Warning / Info 섹션
   - 시간 상관관계 분석
   - 분석 제외 항목
   - 환경 특이사항

4. **보고서 형식**에 따라 마크다운 보고서를 `Write` 도구로 지정된 경로에 저장한다
5. stdout에 1~3줄 요약을 출력한다

---

@.claude/rules/analysis-criteria.md

@.claude/rules/report-format.md

@.claude/rules/analysis-notes.md
