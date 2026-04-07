# MCS Log Analyzer — Claude Harness

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
보고서 저장 경로: /home/deepgadget/MCS_log_analizer/reports/<이름>.md
```

### Claude가 해야 할 일 (순서대로)

1. 압축 해제 디렉터리의 파일 목록을 확인한다 (`Glob` 또는 `Bash: ls -R`)
2. 아래 **우선순위 파일 목록** 순서로 각 파일을 읽고 분석한다
3. 발견한 모든 문제를 **심각도별**로 분류하여 기록한다
4. **보고서 형식**에 따라 마크다운 보고서를 `Write` 도구로 지정된 경로에 저장한다
5. stdout에 1~3줄 요약을 출력한다

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

#### `gpu-memory-errors/uncorrected-ecc_errors.txt`
- 값이 0보다 크면 → **Critical**: GPU 메모리 하드웨어 불량 (GPU 교체 필요)
- CSV 형식: `timestamp, name, pci.bus_id, gpu_uuid, ecc.errors.uncorrected.aggregate.dram, ...`

#### `gpu-memory-errors/remapped-memory.txt`
- `remapped_rows.pending` 값이 0보다 크면 → **Critical**: GPU 메모리 행 리매핑 대기 중
- `remapped_rows.failure` 값이 0보다 크면 → **Critical**: GPU 메모리 리매핑 실패

#### `drives-and-storage/smartctl-*.txt` (파일마다 분석)
- `SMART overall-health self-assessment test result: FAILED` → **Critical**: 디스크 건강 불량
- `Reallocated_Sector_Ct` RAW_VALUE > 0 → **Critical**: 불량 섹터 재할당 발생
- `Current_Pending_Sector` RAW_VALUE > 0 → **Critical**: 불량 섹터 대기 중
- `Offline_Uncorrectable` RAW_VALUE > 0 → **Critical**: 수정 불가 섹터
- `Reallocated_Event_Count` RAW_VALUE > 0 → **Warning**: 재할당 이벤트
- SCSI 장치의 경우 `Elements in grown defect list` > 0 → **Critical**
- `Terminate command early due to bad response` → 정보: SMART 지원 안 됨(가상 디스크 등)으로 기록

### 2순위 — 주요 시스템 로그

#### `system-logs/journalctl.txt`
다음 패턴을 `Grep`으로 검색:
- `Failed to start` / `failed with result` → **Critical/Warning**: 서비스 시작 실패
- `segfault` / `core dumped` → **Critical**: 프로세스 크래시
- `start request repeated too quickly` → **Critical**: 서비스 재시작 루프
- `watchdog` timeout → **Warning**: 서비스 응답 없음
- `FAILED` (대소문자 무관) → **Warning**: 일반 실패
- `Out of memory` → **Critical**: OOM

#### `system-logs/syslog`
다음 패턴을 검색:
- `ERROR` / `FATAL` / `error` → **Warning** 이상
- `authentication failure` / `Failed password` → **Warning**: 인증 실패 반복 여부
- `disk I/O error` / `read error` → **Critical**
- `CRON.*ERROR` → **Info**: 크론 오류

#### `system-logs/kern.log`
- `error` / `warning` / `fail` 포함 라인 (대소문자 무관)
- `EXT4-fs error` / `XFS error` → **Critical**: 파일시스템 오류
- `link is not ready` / `Link is Down` → **Warning**: 네트워크 링크 단절

#### `gpu-memory-errors/ecc-errors.txt`
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

#### `bmc-info/ipmi-elist.txt`
- `Critical` / `Assertion` 포함 이벤트 → **Critical**: BMC 하드웨어 경보
- `Warning` 이벤트 → **Warning**
- 이벤트 없으면: "IPMI 없음 또는 이벤트 없음" 으로 기록

#### `drives-and-storage/mdstat.txt`
- `[U_]` 또는 `_` 포함 (degraded 배열) → **Critical**: RAID 배열 손상
- `recovery` / `resync` → **Warning**: RAID 복구 중

### 4순위 — 보조 정보

#### `nvidia-smi.txt`
- GPU 목록, 드라이버 버전, 메모리 사용량 확인
- 오류 상태 GPU 있으면 기록

#### `system-logs/apt-history.log`
- `Error` 포함 항목 → **Warning**: 패키지 설치/업데이트 실패
- 최근 설치된 패키지 목록을 Info로 기록

#### `uptime.txt`
- 업타임 1시간 미만이면 → **Info**: 최근 재부팅됨 (사고와 연관 가능)

#### `systemctl-services.txt`
- `failed` 상태 서비스 → **Warning/Critical**

---

## 보고서 형식

보고서 파일을 `Write` 도구로 지정된 경로에 저장한다. 형식:

```markdown
# Manycore 서버 진단 보고서

**분석 대상:** [아카이브 이름]
**분석 일시:** [현재 날짜/시간]
**호스트명:** [etc-hostname.txt 에서 추출, 없으면 "알 수 없음"]
**시스템 업타임:** [uptime.txt 내용]

---

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
- **발견 위치:** `파일명:라인번호` (라인 번호 모르면 파일명만)
- **내용:** 실제 로그 라인 또는 값 (코드 블록으로)
- **의미:** 한 줄 설명
- **권장 조치:** 구체적 조치

[이슈가 없으면 "Critical 이슈 없음" 으로 표기]

---

## 🟡 Warning 이슈

[같은 형식으로]

---

## 🔵 Info

[주목할 만한 정보 — 이슈는 아니지만 알아두어야 할 것들]

---

## 분석 제외 항목

분석했지만 문제 없는 항목, 또는 데이터가 없어 분석 불가한 항목을 간략히 기록.
(예: "SMART: sda — 가상 디스크, SMART 미지원", "IPMI: 해당 머신 없음")

---

## 환경 특이사항

WSL, 가상 머신, 컨테이너 등 특수 환경 여부와 그로 인한 노이즈를 설명.
```

---

## 분석 시 주의사항

1. **노이즈 구분**: WSL 환경(`microsoft-standard-WSL2`)의 `dxg`, `PCI: Fatal` 오류는 WSL 특성상 정상이므로 Critical이 아닌 "환경 특이사항"으로 분류
2. **중복 제거**: 같은 패턴이 반복되면 "N회 반복" 으로 집약하여 기록
3. **근거 제시**: 모든 이슈에 실제 로그 내용을 인용
4. **없는 파일**: 파일이 아카이브에 없으면 해당 항목은 "파일 없음" 으로 처리
5. **아카이브 구조**: 루트 디렉터리 이름은 아카이브마다 다를 수 있음 (예: `Manycore-bug-report/`, `customer-abc/`)
