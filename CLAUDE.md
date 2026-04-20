# MCS Log Analyzer — Claude Harness

## 권한 정책

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
   - `_preprocessed/_hw-summary.txt` — shell이 hw-list.txt에서 미리 추출한 메인보드/CPU/메모리 요약. **이 파일을 Read하면 hw-list.txt 직접 Grep 불필요**
   - `_preprocessed/_nvidia-summary.txt` — shell이 미리 추출한 GPU 요약 (모델·드라이버/CUDA·ECC 모드). **nvidia-smi.txt 직접 Read 불필요**
   - `gpu-serials.txt` — GPU 시리얼 + Bus ID (있는 경우)
   - `drives-and-storage/lsblk.txt` — 스토리지 장치 목록
   - `ibstat.txt` — InfiniBand 상태 (없으면 "없음")
4. **작은 파일 Read** (대부분 수십 줄 이하):
   - `_preprocessed/_ecc-summary.txt` — shell이 gpu-memory-errors/ 3개 파일을 합산한 GPU ECC/리매핑 요약
   - `_preprocessed/_smart-summary.txt` — 모든 스토리지 장치의 핵심 SMART 속성 요약. 드라이브 타입은 `[NVMe]` / `[SATA]` 태그로 표시됨. Pass 2에서 Critical SMART 이슈 발견 시에만 해당 드라이브 원본 `smartctl-*.txt`를 Read한다
   - `drives-and-storage/df.txt`
   - `drives-and-storage/mdstat.txt`
   - `sensors.txt`
   - `uptime.txt`
   - `_preprocessed/_systemctl-summary.txt` — failed 서비스 + 서버 운영 관련 서비스(unattended-upgrades, sleep/suspend/hibernate target) masked 여부 요약
   - `bmc-info/ipmi-elist.txt`
5. **전처리 파일 Read** (`_preprocessed/` 디렉터리):
   - `journalctl-boots.txt` — `-- Boot` 마커 목록 (재부팅 시점 + 줄번호)
   - `journalctl-boot-context.txt` — 각 Boot 경계 직전 40줄/직후 10줄 (종료 원인·복구 문맥, 최근 ~10회 분)
   - `journalctl-critical.txt` — 유형별로 dedup·크기 제한된 크리티컬 이벤트 요약. soft lockup은 첫 발생/최대값+총 횟수, MCE/EDAC는 dedup 빈도표, Call Trace는 함수 경로만 (Modules linked in 제거). 시간 상관관계 분석에 이 파일의 타임스탬프를 사용한다
   - `journalctl-errors.txt` — 광범위 패턴(fail/error/warning 등) 빈도표. 형식: `  횟수 process: 메시지` (타임스탬프 없음, 최대 200행). 패턴 파악용이며 시간 정보는 journalctl-critical.txt 또는 density.txt를 참조
   - `journalctl-service-loops.txt` — 재시작 루프 서비스 요약 (restart counter 최고값 상위 10개 + 대표 에러 메시지). **이 파일이 존재하면 반드시 Read하고, counter가 1000 이상인 서비스가 있으면 soft lockup/OOM 등 CPU 이슈와 인과관계를 검토한다**
   - `journalctl-lifecycle.txt` — 시스템 종료/재부팅 등 구조적 이벤트
   - `journalctl-density.txt` — 시간대별 로그 밀도 (비정상 폭주 구간)
   - `syslog-errors.txt` — syslog 에러 필터
   - `kern-errors.txt` — kern.log 에러 필터
   - `syslog-errors-frequency.txt` / `kern-errors-frequency.txt` — 에러 메시지별 빈도 집계
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
   - **soft lockup 발견 시**: `journalctl-service-loops.txt`에서 높은 restart counter 서비스를 확인하고,
     해당 서비스의 PID와 lockup 직전(~5분) 타임라인을 원본 `journalctl.txt`에서 Grep하여
     서비스 재시작 루프가 lockup에 기여했는지 인과관계를 명확히 기록한다
   - SMART Critical이면 해당 드라이브의 전체 smartctl 출력을 정밀 검토
   - GPU 에러 발견 시 `nvidia-bug-report.log`에서 관련 섹션 Grep (파일이 존재하는 경우)
8. 4순위 보조 정보 파일들을 확인한다 (`apt-history.log` 등)
9. 발견한 모든 문제를 심각도별로 분류하여 기록한다
10. **시간 상관관계 분석**: 아래 "보고서 형식" 섹션의 상관관계 방법론을 따라 이벤트 묶음을 구성한다

### 보고서 저장

보고서를 Write하기 전에 다음을 확인한다:

1. **심각도 일관성**: 같은 유형의 이슈가 다른 심각도로 분류되어 있지 않은지 확인한다.
2. **보고서 구조 검증**: 보고서가 모든 필수 섹션을 포함하는지 확인한다:
   - 메타데이터 (분석 대상, 일시, 호스트명, 업타임, 환경)
   - 요약 테이블
   - Critical / Warning / Info 섹션
   - 시간 상관관계 분석
   - 분석 제외 항목
   - 환경 특이사항
3. **보고서 형식**: 아래 "보고서 형식" 섹션의 구조를 따라 `Write` 도구로 지정된 경로에 저장한다
4. stdout에 1~3줄 요약을 출력한다

---

## 우선순위 파일 목록 및 분석 기준

### 1순위 — 즉각 확인 필요 (Critical 가능성)

#### `system-logs/dmesg-errors.txt`
- `kernel panic` / `Oops` / `BUG:` → **Critical**: 커널 패닉/크래시
- `Out of memory` / `oom-kill` / `oom_score` → **Critical**: OOM 킬 발생
- `I/O error` / `blk_update_request` / `SCSI error` → **Critical**: 디스크 I/O 오류
- `Hardware Error` / `EDAC` / `MCE` / `Machine Check` → **Critical**: 하드웨어 오류
- `RAID` 관련 오류 (`md:`, `mdadm`) → **Critical**: RAID 이상
- `NFS` / `Lustre` / `filesystem error` → **Warning**: 파일시스템 오류
- WSL/VM 환경 특유 오류(`dxg`, `PCI: Fatal`)는 노이즈로 분류 — 보고서에 별도 섹션으로 표기

#### `_preprocessed/_ecc-summary.txt` (gpu-memory-errors/ 3개 파일 통합)

**uncorrected-ecc_errors 항목**:
- 값이 0보다 크면 → **Critical**: GPU 메모리 uncorrected ECC 오류 발생 — 재부팅 후에도 값이 증가하면 GPU 교체 검토

**remapped-memory 항목**:
- `remapped_rows.failure` > 0 → **Critical**: GPU 메모리 리매핑 실패 (예비 셀 소진 또는 교체 불가)
- `remapped_rows.uncorrectable` > 0 → **Warning**: uncorrectable ECC 오류로 인한 행 리매핑 완료 — 하드웨어 열화 징후
- `remapped_rows.pending` > 0 → **Warning**: GPU 메모리 행 리매핑 대기 중 — 재부팅 후 resolved 여부 확인
- `remapped_rows.correctable` > 0 → **Info**: 수정 가능 오류로 인한 예방적 행 리매핑 — 증가 추이 확인 권장

#### `_preprocessed/_smart-summary.txt` (모든 드라이브 핵심 속성 요약)
- `SMART overall-health self-assessment test result: FAILED` → **Critical**: 디스크 건강 불량
- `Reallocated_Sector_Ct` RAW_VALUE > 0 → **Critical**: 불량 섹터 재할당 발생
- `Current_Pending_Sector` RAW_VALUE > 0 → **Critical**: 불량 섹터 대기 중
- `Offline_Uncorrectable` RAW_VALUE > 0 → **Critical**: 수정 불가 섹터
- `Reallocated_Event_Count` RAW_VALUE > 0 → **Warning**: 재할당 이벤트
- SCSI 장치의 경우 `Elements in grown defect list` > 0 → **Critical**
- `Terminate command early due to bad response` → 정보: SMART 지원 안 됨(가상 디스크 등)으로 기록

#### NVMe 드라이브 (`smartctl-nvme*.txt` 또는 SMART/Health Information 섹션이 있는 파일)

NVMe 드라이브는 SATA와 출력 형식이 다르다. `SMART/Health Information` 섹션의 키-값을 기준으로 판정:

- `Critical Warning` 값이 `0x00`이 아니면 → **Critical**: NVMe 컨트롤러 경고 활성
- `Available Spare` < `Available Spare Threshold` → **Critical**: 예비 공간 임계치 이하
- `Available Spare` ≤ 20% → **Warning**: 예비 공간 부족 임박
- `Percentage Used` ≥ 100% → **Warning**: 설계 수명 도달 (즉시 고장은 아니나 교체 계획 필요)
- `Media and Data Integrity Errors` > 0 → **Critical**: 미디어 무결성 오류 발생
- `Error Information Log Entries` > 0 → **Warning**: 에러 로그 존재 (세부 내용 확인 필요)
- `Warning  Comp. Temperature Time` > 0 → **Warning**: NVMe가 Warning 온도 이상에서 운영된 이력 있음
  - 반드시 파일 상단의 `Warning  Comp. Temp. Threshold` 값과 함께 기록 (예: "87°C 이상에서 8분 운영")
- `Critical Comp. Temperature Time` > 0 → **Warning**: NVMe가 Critical 온도 이상에서 운영된 이력 있음
  - 반드시 파일 상단의 `Critical Comp. Temp. Threshold` 값과 함께 기록 (예: "89°C 이상에서 N분 운영")
- `Thermal Temp. 1 Transition Count` > 0 또는 `Thermal Temp. 2 Transition Count` > 0 → **Warning**: NVMe 써멀 스로틀링 발생 이력 (성능 저하 구간 존재)
  - `Thermal Temp. 1/2 Total Time` 값(분 단위)도 함께 기록하여 누적 스로틀링 시간을 노출한다

`_smart-summary.txt`에서 드라이브 타입은 `[NVMe]` 또는 `[SATA]` 태그로 이미 표시되어 있다.

**SMART 보고 규칙**:
- SMART 이슈 보고 시 해당 속성의 RAW_VALUE를 반드시 함께 기록한다.
  (예: `Reallocated_Sector_Ct RAW_VALUE = 3`, `Current_Pending_Sector RAW_VALUE = 12`)
- NVMe의 경우 해당 키의 실제 값을 기록한다.
  (예: `Available Spare = 15%`, `Media and Data Integrity Errors = 2`)
- 값 자체에 대한 심각도 구간 판정은 하지 않는다. 0 vs non-zero로만 판정하고, 수치는 참고용으로 노출한다.

### 2순위 — 주요 시스템 로그

#### `_preprocessed/journalctl-critical.txt` / `_preprocessed/journalctl-errors.txt` / `_preprocessed/journalctl-lifecycle.txt`

Pass 1 step 5에서 이미 Read한 전처리 파일을 기반으로 분석한다. 원본 `journalctl.txt`는 Grep하지 않는다.

**journalctl-critical.txt** (유형별 dedup된 크리티컬 이벤트 요약):
- `BUG:` / `Oops:` / `kernel panic` → **Critical**: 커널 버그/크래시
- `oom-kill` / `Out of memory:` → **Critical**: OOM 킬
- `segfault` → **Critical**: 프로세스 크래시
- `I/O error` / `blk_update_request` → **Critical**: 디스크 I/O 오류
- `EDAC` / `Machine Check` / `MCE` → **Critical**: 하드웨어 오류 (dedup 빈도표로 표시)
- soft lockup 총 횟수 주석 (`# (총 N줄 반복)`) — 실제 발생 시각은 첫/마지막 줄에서 확인
- Call Trace 함수 경로 — lockup/crash 유발 함수 특정에 사용

**journalctl-errors.txt** (광범위 패턴 빈도표 — 타임스탬프 없음, 형식: `  횟수 process: 메시지`):
- `Failed to start` / `failed with result` → **Critical/Warning**: 서비스 시작 실패
- `start request repeated too quickly` → **Critical**: 서비스 재시작 루프
- `watchdog` timeout → **Warning**: 서비스 응답 없음
- `FAILED` → **Warning**: 일반 실패
- 횟수가 높은 항목부터 우선 확인. 이 파일에 타임스탬프가 없으므로 시간 상관관계는 journalctl-critical.txt를 사용할 것

**journalctl-service-loops.txt** (서비스 재시작 루프 요약):
- restart counter 수천~수만인 서비스 → **Critical**: 서비스가 시스템 레벨에 잘못 설치되었거나 의존성 누락
- `Failed to determine user credentials` / `status=217/USER` → 서비스가 system 레벨로 실행되는데 사용자 계정 정보를 찾지 못함. 사용자 세션 서비스를 잘못 system.d로 설치한 것
  - **이 패턴은 단순 Warning이 아닌 CPU/IPC 부하의 근본 원인이 될 수 있다**: 수만 번의 fork/exec/exit 사이클이 커널 TLB shootdown IPI 폭주를 유발, 결국 CPU soft lockup으로 이어질 수 있음
- `start request repeated too quickly` → **Critical**: systemd가 재시작 속도 제한(rate limit)을 걸고 중단시킨 서비스

**journalctl-lifecycle.txt** (시스템 구조적 이벤트):
- `shutdown` / `reboot` / `Power-Off` / `Rebooting` → **Warning**: 시스템 종료·재부팅 이벤트
  - 종료를 요청한 주체(프로세스 또는 유닛)를 함께 기록한다
  - systemd 외의 프로세스(사용자 애플리케이션 등)가 종료를 요청한 경우 → **Critical**: 비정상 종료 유발 가능성
- `Reached target.*Power-Off` / `Reached target.*Reboot` → **Warning**: 종료 시퀀스 진입 확인
- `logind.*Power key` / `logind.*Suspend` → **Info**: 물리 전원 버튼 또는 절전 이벤트

#### `_preprocessed/syslog-errors.txt`

Pass 1 step 5에서 Read한 파일에서 다음 항목을 확인한다:
- `BUG:` / `Oops:` → **Critical**: 커널 버그 (syslog도 커널 메시지를 포함하며 dmesg 타임스탬프 형식으로 기록됨)
- `ERROR` / `FATAL` / `error` → **Warning** 이상
- `authentication failure` / `Failed password` → **Warning**: 인증 실패 반복 여부
- `disk I/O error` / `read error` → **Critical**
- `CRON.*ERROR` → **Info**: 크론 오류

#### `_preprocessed/kern-errors.txt`

Pass 1 step 5에서 Read한 파일에서 다음 항목을 확인한다:
- `error` / `warning` / `fail` 포함 라인
- `EXT4-fs error` / `XFS error` → **Critical**: 파일시스템 오류
- `link is not ready` / `Link is Down` → **Warning**: 네트워크 링크 단절

#### `_preprocessed/_ecc-summary.txt` 내 ecc-errors 항목 (Pass 1 step 4에서 이미 Read)
- `ecc.errors.corrected.volatile.dram` 값이 높으면 (100 초과) → **Warning**: GPU ECC 수정 오류 누적

### 3순위 — 리소스 및 하드웨어 상태

#### `drives-and-storage/df.txt`
- Use% ≥ 95% → **Critical**: 디스크 거의 가득 참
- Use% ≥ 85% → **Warning**: 디스크 용량 부족 임박
- 마운트 포인트별로 기록

#### `sensors.txt`
- CPU/GPU 온도 > 85°C → **Warning**: 과열 위험
- 온도 > 95°C → **Critical**: 긴급 과열
- 팬 속도 0 RPM (동작 중) → **Warning**: 팬 이상
  - **단, 수냉(수랭) 시스템은 CPU·GPU 팬이 없으므로 0 RPM이 정상이다.** 수냉 여부는 `sensors.txt`에 팬 항목 자체가 없거나 pump 관련 항목만 있는 경우로 판단한다. 수냉으로 판단되면 팬 0 RPM 경고를 내지 않는다.

#### `bmc-info/ipmi-elist.txt`
- `Critical` / `Assertion` 포함 이벤트 → **Critical**: BMC 하드웨어 경보
- `Warning` 이벤트 → **Warning**
- 이벤트 없으면: "IPMI 없음 또는 이벤트 없음" 으로 기록

#### `drives-and-storage/mdstat.txt`
- `[U_]` 또는 `_` 포함 (degraded 배열) → **Critical**: RAID 배열 손상
- `recovery` / `resync` → **Warning**: RAID 복구 중

#### PCIe Link Speed 저하 (`nvidia-bug-report.log` 내 `lspci -vvv`)
- GPU/IB/NVMe 장치의 `LnkSta` 속도가 `LnkCap` 속도보다 낮으면 → **Warning**: PCIe 링크 다운그레이드
  - 보고서 인벤토리 섹션의 PCIe Link Speed 테이블에도 표기
  - 주요 원인: PCIe 슬롯 접촉 불량, 케이블 문제, BIOS 설정, 써멀 스로틀링, 라이저 카드
- `nvidia-bug-report.log`가 없으면 이 항목은 "데이터 없음"으로 분석 제외
- **Pass 2에서** `nvidia-bug-report.log`를 `LnkSta`, `LnkCap` 키워드로 Grep하여 확인

### 4순위 — 보조 정보

#### `_preprocessed/_nvidia-summary.txt` (Pass 1 step 3에서 이미 Read)
- GPU 목록, 드라이버 버전, 메모리 사용량 확인
- 오류 상태 GPU 있으면 기록

#### `system-logs/apt-history.log`
- `Error` 포함 항목 → **Warning**: 패키지 설치/업데이트 실패
- 최근 설치된 패키지 목록을 Info로 기록

#### `uptime.txt`
- 업타임 1시간 미만이면 → **Info**: 최근 재부팅됨 (사고와 연관 가능)

#### `_preprocessed/_systemctl-summary.txt` (Pass 1 step 4에서 이미 Read)
- `failed` 상태 서비스 → **Warning/Critical**
- 다음 서비스/타깃이 **masked 되어 있지 않으면** → **Warning**: 서버 운영 환경에 부적합한 설정
  - `unattended-upgrades.service` — 자동 패키지 업데이트. 서버에서는 예고 없이 재시작 유발 가능
  - `sleep.target` / `suspend.target` / `hibernate.target` / `hybrid-sleep.target` — 절전/최대절전 모드. HPC 서버에서는 반드시 비활성화(masked)되어야 함
  - 판별 방법: 서비스 목록에서 `masked` 여부 확인. `disabled`는 부팅 시 미시작이지만 수동 실행 가능 — `masked`만 완전 차단임
  - `masked`이면 "정상 비활성화"로 분석 제외 항목에 기록, `disabled`이면 **Warning** (masked 권장), `enabled`이면 **Warning**
  - `(목록에 없음 — masked 가능)` 표시이면: 원본 `systemctl-services.txt`를 직접 확인하거나 masked로 간주

---

## 보고서 형식

### 섹션 순서

```
# Manycore 서버 진단 보고서

**분석 대상:** [아카이브 이름]
**분석 일시:** [analyze.sh가 전달한 분석 시작 시각]
**호스트명:** [_env-hints.txt의 HOSTNAME]
**시스템 업타임:** [uptime.txt 내용]
**환경:** [WSL2 / VM (QEMU) / 베어메탈]

---

## 하드웨어 인벤토리
```

하드웨어 인벤토리 섹션 서문: `> 이 섹션은 장착된 부품이 OS에 정상 인식되는지 **사람이 확인**하기 위한 요약이다.`

인벤토리 서브섹션: **메인보드** (제조사·모델), **CPU** (모델·소켓·코어·스레드), **GPU** (표: #·모델·PCI Bus ID·메모리·시리얼), **메모리** (표: 총 용량·슬롯 수·슬롯별 모델), **스토리지** (표: #·장치명·종류·모델·용량·마운트), **InfiniBand** (표: 유무·모델·포트 수·상태·속도), **PCIe Link Speed** (표: 장치·종류·LnkCap·LnkSta·상태 ✅/⚠️)

각 서브섹션 끝에 `**데이터 소스**: ...` 한 줄 기록.

```
## 요약
| 심각도 | 건수 |
|--------|------|
| 🔴 Critical | N |
| 🟡 Warning | N |
| 🔵 Info | N |

[1~3줄 요약 — 가장 중요한 문제 먼저]

---

## 🔴 Critical 이슈

### [이슈 제목]
- **발견 위치:** `파일명`
- **내용:** `실제 로그 또는 값`
- **의미:** 한 줄 설명
- **권장 조치:** 구체적 조치

[이슈 없으면 "Critical 이슈 없음"]

---

## ⏱ 시간 상관관계 분석

### 이벤트 묶음: [시간대] — [추정 원인 한 줄]
| 시각 | 출처 파일 | 이벤트 |
|------|-----------|--------|
| HH:MM:SS | [파일명] | [이벤트 내용] |

**추정 인과관계**: [...]

---

## 🟡 Warning 이슈

[Critical 이슈와 같은 형식]

---

## 🔵 Info

---

## 분석 제외 항목

[문제 없는 항목, 데이터 없어 분석 불가한 항목 간략 기록]

---

## 환경 특이사항

[WSL/VM/컨테이너 등 특수 환경 여부와 그로 인한 노이즈 설명]
```

### 시간 상관관계 분석 방법

1. Critical/Warning 이슈에서 타임스탬프를 추출할 수 있는 것들을 모은다
2. 같은 10분 윈도우 내 **2개 이상 소스**에서 이벤트 발견 → "이벤트 묶음" 구성
3. 반드시 여러 소스를 교차 확인 (단일 소스 묶음은 작성 금지):
   - journalctl 이벤트 → `dmesg-crash-context.txt`, `dmesg-full-errors.txt`, `ipmi-elist.txt` 교차 확인
   - ipmi 이벤트 → `journalctl-errors.txt`, `dmesg-full-errors.txt` 교차 확인
   - 커널 Oops/BUG → `dmesg-crash-context.txt`에서 스택 트레이스 확인
4. 이벤트 묶음: 시각/출처/이벤트 테이블 + 추정 인과관계
5. 묶음 없으면 "시간적으로 연관된 이벤트 묶음이 발견되지 않았습니다"

주요 패턴: GPU ECC→OOM→서비스재시작, 디스크I/O→서비스crash→FS에러, 온도급등→스로틀링→성능저하, 네트워크링크다운→NFS에러→서비스실패

---

## 분석 시 주의사항

1. **환경 감지 및 노이즈 구분**:
   분석 시작 전에 다음 방법으로 환경을 판별하고, 환경별 노이즈를 Critical/Warning에서 제외한다:

   **환경 판별**: `_env-hints.txt`의 `ENV_TYPE` 값을 사용한다.
   파일이 없는 경우에만 아래 수동 판별을 수행:
   - `deepgadget-log-grabber`로 수집된 아카이브는 **거의 항상 베어메탈**이다.
     가상화 증거가 명확히 발견되지 않으면 베어메탈로 간주하고 VM 노이즈 필터는 적용하지 않는다.
   - `dmesg-errors.txt` 또는 `kern.log`에서 커널 버전 확인:
     - `microsoft-standard-WSL2` → WSL
   - VM 판별 시 **게스트 전용 지표**만 사용:
     - DMI 정보에 가상 하드웨어 제조사 (`QEMU Virtual`, `VMware Virtual`, `VirtualBox` 등)
     - Xen: `Xen HVM` 문자열
     - ⚠ `kvm_amd`, `kvm_intel`, `KVM` 단어 자체는 베어메탈 KVM 호스트에서도 나타나므로 VM 판정 근거로 사용하지 않는다
   - `hw-list.txt`의 product/manufacturer 필드에서 가상 하드웨어 벤더 확인
   - 위 모두 해당 없으면 베어메탈로 간주

   **환경별 노이즈 패턴** (Critical/Warning이 아닌 "환경 특이사항"으로 분류):

   WSL:
   - `dxgkrnl`, `dxg` 관련 오류
   - `PCI: Fatal: No response from device`
   - `ACPI` 관련 경고
   - SMART 미지원 (가상 디스크)

   VM (QEMU/KVM/VMware):
   - `ACPI: Unable to ...` 계열
   - SMART 미지원 또는 가상 디스크 감지 불가
   - IPMI 없음
   - 센서 데이터 없음 또는 부분적

   컨테이너:
   - 대부분의 하드웨어 센서/IPMI/SMART 데이터 없음
   - dmesg 접근 불가 가능

   **판별 결과는 보고서 상단 메타데이터에 기록한다** (`**환경:** WSL2 / VM (QEMU) / 베어메탈`)
2. **중복 제거**: 같은 패턴이 반복되면 "N회 반복" 으로 집약하여 기록
3. **근거 제시**: 모든 이슈에 실제 로그 내용을 인용
4. **없는 파일**: 파일이 아카이브에 없으면 해당 항목은 "파일 없음" 으로 처리
5. **아카이브 구조**: 루트 디렉터리 이름은 아카이브마다 다를 수 있음 (예: `Manycore-bug-report/`, `customer-abc/`)
