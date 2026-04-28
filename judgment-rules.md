# 판정 기준 — MCS Log Analyzer

이 파일은 분석 시 심각도 판정에 사용한다. CLAUDE.md의 워크플로(2-pass)는 변경 없이 유지하되,
구체적인 임계값·키워드·환경 노이즈 패턴은 여기서 참조한다.

---

## 1순위 — 즉각 확인 필요 (Critical 가능성)

### `system-logs/dmesg-errors.txt`
- `kernel panic` / `Oops` / `BUG:` → **Critical**: 커널 패닉/크래시
- `Out of memory` / `oom-kill` / `oom_score` → **Critical**: OOM 킬 발생
- `I/O error` / `blk_update_request` / `SCSI error` → **Critical**: 디스크 I/O 오류
- `Hardware Error` / `EDAC` / `MCE` / `Machine Check` → **Critical**: 하드웨어 오류
- `RAID` 관련 오류 (`md:`, `mdadm`) → **Critical**: RAID 이상
- `NFS` / `Lustre` / `filesystem error` → **Warning**: 파일시스템 오류
- WSL/VM 환경 특유 오류(`dxg`, `PCI: Fatal`)는 노이즈로 분류 — 보고서에 별도 섹션으로 표기

### `_preprocessed/_ecc-summary.txt` (gpu-memory-errors/ 3개 파일 통합)

**uncorrected-ecc_errors 항목**:
- 값이 0보다 크면 → **Critical**: GPU 메모리 uncorrected ECC 오류 발생 — 재부팅 후에도 값이 증가하면 GPU 교체 검토

**remapped-memory 항목**:
- `remapped_rows.failure` > 0 → **Critical**: GPU 메모리 리매핑 실패 (예비 셀 소진 또는 교체 불가)
- `remapped_rows.uncorrectable` > 0 → **Warning**: uncorrectable ECC 오류로 인한 행 리매핑 완료 — 하드웨어 열화 징후
- `remapped_rows.pending` > 0 → **Warning**: GPU 메모리 행 리매핑 대기 중 — 재부팅 후 resolved 여부 확인
- `remapped_rows.correctable` > 0 → **Info**: 수정 가능 오류로 인한 예방적 행 리매핑 — 증가 추이 확인 권장

### `_preprocessed/_smart-summary.txt` (모든 드라이브 핵심 속성 요약)
- `SMART overall-health self-assessment test result: FAILED` → **Critical**: 디스크 건강 불량
- `Reallocated_Sector_Ct` RAW_VALUE > 0 → **Critical**: 불량 섹터 재할당 발생
- `Current_Pending_Sector` RAW_VALUE > 0 → **Critical**: 불량 섹터 대기 중
- `Offline_Uncorrectable` RAW_VALUE > 0 → **Critical**: 수정 불가 섹터
- `Reallocated_Event_Count` RAW_VALUE > 0 → **Warning**: 재할당 이벤트
- SCSI 장치의 경우 `Elements in grown defect list` > 0 → **Critical**
- `Terminate command early due to bad response` → 정보: SMART 지원 안 됨(가상 디스크 등)으로 기록

### NVMe 드라이브 (`smartctl-nvme*.txt` 또는 SMART/Health Information 섹션이 있는 파일)

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

---

## 2순위 — 주요 시스템 로그

### `_preprocessed/journalctl-critical.txt` (유형별 dedup된 크리티컬 이벤트 요약)
- `BUG:` / `Oops:` / `kernel panic` → **Critical**: 커널 버그/크래시
- `oom-kill` / `Out of memory:` → **Critical**: OOM 킬
- `segfault` → **Critical**: 프로세스 크래시
- `I/O error` / `blk_update_request` → **Critical**: 디스크 I/O 오류
- `EDAC` / `Machine Check` / `MCE` → **Critical**: 하드웨어 오류 (dedup 빈도표로 표시)
- soft lockup 총 횟수 주석 (`# (총 N줄 반복)`) — 실제 발생 시각은 첫/마지막 줄에서 확인
- Call Trace 함수 경로 — lockup/crash 유발 함수 특정에 사용

### `_preprocessed/journalctl-errors.txt` (광범위 패턴 빈도표 — 타임스탬프 없음, 형식: `  횟수 process: 메시지`)
- `Failed to start` / `failed with result` → **Critical/Warning**: 서비스 시작 실패
- `start request repeated too quickly` → **Critical**: 서비스 재시작 루프
- `watchdog` timeout → **Warning**: 서비스 응답 없음
- `FAILED` → **Warning**: 일반 실패
- 횟수가 높은 항목부터 우선 확인. 이 파일에 타임스탬프가 없으므로 시간 상관관계는 journalctl-critical.txt를 사용할 것

### `_preprocessed/journalctl-service-loops.txt` (서비스 재시작 루프 요약)
- restart counter 수천~수만인 서비스 → **Critical**: 서비스가 시스템 레벨에 잘못 설치되었거나 의존성 누락
- `Failed to determine user credentials` / `status=217/USER` → 서비스가 system 레벨로 실행되는데 사용자 계정 정보를 찾지 못함. 사용자 세션 서비스를 잘못 system.d로 설치한 것
  - **이 패턴은 단순 Warning이 아닌 CPU/IPC 부하의 근본 원인이 될 수 있다**: 수만 번의 fork/exec/exit 사이클이 커널 TLB shootdown IPI 폭주를 유발, 결국 CPU soft lockup으로 이어질 수 있음
- `start request repeated too quickly` → **Critical**: systemd가 재시작 속도 제한(rate limit)을 걸고 중단시킨 서비스

### `_preprocessed/journalctl-lifecycle.txt` (시스템 구조적 이벤트)
- `shutdown` / `reboot` / `Power-Off` / `Rebooting` → **Warning**: 시스템 종료·재부팅 이벤트
  - 종료를 요청한 주체(프로세스 또는 유닛)를 함께 기록한다
  - systemd 외의 프로세스(사용자 애플리케이션 등)가 종료를 요청한 경우 → **Critical**: 비정상 종료 유발 가능성
- `Reached target.*Power-Off` / `Reached target.*Reboot` → **Warning**: 종료 시퀀스 진입 확인
- `logind.*Power key` / `logind.*Suspend` → **Info**: 물리 전원 버튼 또는 절전 이벤트

### `_preprocessed/syslog-errors.txt`
- `BUG:` / `Oops:` → **Critical**: 커널 버그 (syslog도 커널 메시지를 포함하며 dmesg 타임스탬프 형식으로 기록됨)
- `ERROR` / `FATAL` / `error` → **Warning** 이상
- `authentication failure` / `Failed password` → **Warning**: 인증 실패 반복 여부
- `disk I/O error` / `read error` → **Critical**
- `CRON.*ERROR` → **Info**: 크론 오류

### `_preprocessed/kern-errors.txt`
- `error` / `warning` / `fail` 포함 라인
- `EXT4-fs error` / `XFS error` → **Critical**: 파일시스템 오류
- `link is not ready` / `Link is Down` → **Warning**: 네트워크 링크 단절

### `_preprocessed/_ecc-summary.txt` 내 ecc-errors 항목
- `ecc.errors.corrected.volatile.dram` 값이 높으면 (100 초과) → **Warning**: GPU ECC 수정 오류 누적

---

## 3순위 — 리소스 및 하드웨어 상태

### `drives-and-storage/df.txt`
- Use% ≥ 95% → **Critical**: 디스크 거의 가득 참
- Use% ≥ 85% → **Warning**: 디스크 용량 부족 임박
- 마운트 포인트별로 기록

### `sensors.txt`
- CPU/GPU 온도 > 85°C → **Warning**: 과열 위험
- 온도 > 95°C → **Critical**: 긴급 과열
- 팬 속도 0 RPM (동작 중) → **Warning**: 팬 이상
  - **단, 수냉(수랭) 시스템은 CPU·GPU 팬이 없으므로 0 RPM이 정상이다.** 수냉 여부는 `sensors.txt`에 팬 항목 자체가 없거나 pump 관련 항목만 있는 경우로 판단한다. 수냉으로 판단되면 팬 0 RPM 경고를 내지 않는다.

### `bmc-info/ipmi-elist.txt`
- `Critical` / `Assertion` 포함 이벤트 → **Critical**: BMC 하드웨어 경보
- `Warning` 이벤트 → **Warning**
- 이벤트 없으면: "IPMI 없음 또는 이벤트 없음" 으로 기록

### `drives-and-storage/mdstat.txt`
- `[U_]` 또는 `_` 포함 (degraded 배열) → **Critical**: RAID 배열 손상
- `recovery` / `resync` → **Warning**: RAID 복구 중

### PCIe Link Speed 저하 (`nvidia-bug-report.log` 내 `lspci -vvv`)
- GPU/IB/NVMe 장치의 `LnkSta` 속도가 `LnkCap` 속도보다 낮으면 → **Warning**: PCIe 링크 다운그레이드
  - 보고서 인벤토리 섹션의 PCIe Link Speed 테이블에도 표기
  - 주요 원인: PCIe 슬롯 접촉 불량, 케이블 문제, BIOS 설정, 써멀 스로틀링, 라이저 카드
- `nvidia-bug-report.log`가 없으면 이 항목은 "데이터 없음"으로 분석 제외
- **Pass 2에서** `nvidia-bug-report.log`를 `LnkSta`, `LnkCap` 키워드로 Grep하여 확인

---

## 4순위 — 보조 정보

### `_preprocessed/_nvidia-summary.txt`
- GPU 목록, 드라이버 버전, 메모리 사용량 확인
- 오류 상태 GPU 있으면 기록

### `system-logs/apt-history.log`
- `Error` 포함 항목 → **Warning**: 패키지 설치/업데이트 실패
- 최근 설치된 패키지 목록을 Info로 기록

### `uptime.txt`
- 업타임 1시간 미만이면 → **Info**: 최근 재부팅됨 (사고와 연관 가능)

### `_preprocessed/_systemctl-summary.txt`
- `failed` 상태 서비스 → **Warning/Critical**
- 다음 서비스/타깃이 **masked 되어 있지 않으면** → **Warning**: 서버 운영 환경에 부적합한 설정
  - `unattended-upgrades.service` — 자동 패키지 업데이트. 서버에서는 예고 없이 재시작 유발 가능
  - `sleep.target` / `suspend.target` / `hibernate.target` / `hybrid-sleep.target` — 절전/최대절전 모드. HPC 서버에서는 반드시 비활성화(masked)되어야 함
  - 판별 방법: 서비스 목록에서 `masked` 여부 확인. `disabled`는 부팅 시 미시작이지만 수동 실행 가능 — `masked`만 완전 차단임
  - `masked`이면 "정상 비활성화"로 분석 제외 항목에 기록, `disabled`이면 **Warning** (masked 권장), `enabled`이면 **Warning**
  - `(목록에 없음 — masked 가능)` 표시이면: 원본 `systemctl-services.txt`를 직접 확인하거나 masked로 간주

---

## 환경 감지 및 노이즈 패턴

### 환경 판별
`_env-hints.txt`의 `ENV_TYPE` 값을 우선 사용한다. 파일이 없는 경우에만 아래 수동 판별을 수행:

- `deepgadget-log-grabber`로 수집된 아카이브는 **거의 항상 베어메탈**이다. 가상화 증거가 명확히 발견되지 않으면 베어메탈로 간주하고 VM 노이즈 필터는 적용하지 않는다.
- `dmesg-errors.txt` 또는 `kern.log`에서 커널 버전 확인:
  - `microsoft-standard-WSL2` → WSL
- VM 판별 시 **게스트 전용 지표**만 사용:
  - DMI 정보에 가상 하드웨어 제조사 (`QEMU Virtual`, `VMware Virtual`, `VirtualBox` 등)
  - Xen: `Xen HVM` 문자열
  - ⚠ `kvm_amd`, `kvm_intel`, `KVM` 단어 자체는 베어메탈 KVM 호스트에서도 나타나므로 VM 판정 근거로 사용하지 않는다
- `hw-list.txt`의 product/manufacturer 필드에서 가상 하드웨어 벤더 확인
- 위 모두 해당 없으면 베어메탈로 간주

### 환경별 노이즈 패턴 (Critical/Warning이 아닌 "환경 특이사항"으로 분류)

**WSL**:
- `dxgkrnl`, `dxg` 관련 오류
- `PCI: Fatal: No response from device`
- `ACPI` 관련 경고
- SMART 미지원 (가상 디스크)

**VM (QEMU/KVM/VMware)**:
- `ACPI: Unable to ...` 계열
- SMART 미지원 또는 가상 디스크 감지 불가
- IPMI 없음
- 센서 데이터 없음 또는 부분적

**컨테이너**:
- 대부분의 하드웨어 센서/IPMI/SMART 데이터 없음
- dmesg 접근 불가 가능

판별 결과는 보고서 상단 메타데이터에 기록한다 (`**환경:** WSL2 / VM (QEMU) / 베어메탈`).
