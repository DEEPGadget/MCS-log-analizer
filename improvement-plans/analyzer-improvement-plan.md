# MCS Log Analyzer 개선 계획서

> **용도**: 이 파일을 Claude Code에 전달하여 CLAUDE.md 및 analyze.sh를 개선한다.
> **작업 원칙**: 기존 CLAUDE.md의 규칙(§1 스타일 유지, §10 리팩터링 금지)을 준수한다.
> **제출 형식**: 각 항목별 unified diff 패치. 변경이 큰 경우에만 전체 파일 제공.

---

## 작업 1: NVMe 드라이브 분석 기준 추가

**대상 파일**: `CLAUDE.md` (MCS Log Analyzer 쪽)

**배경**: 현재 SMART 분석 기준은 SATA/SAS 드라이브의 Attribute 테이블만 다룬다.
NVMe는 `smartctl -a` 출력 형식이 완전히 다르며 (SMART/Health Information 키-값 형식),
요즘 서버 대부분이 NVMe이므로 분석 커버리지에 구멍이 있다.

**수정 위치**: `## 우선순위 파일 목록 및 분석 기준` → `### 1순위` → `#### drives-and-storage/smartctl-*.txt` 섹션

**추가할 내용**: 기존 SATA 기준 아래에 NVMe 전용 판정 기준을 추가한다.

```markdown
#### NVMe 드라이브 (`smartctl-nvme*.txt` 또는 SMART/Health Information 섹션이 있는 파일)

NVMe 드라이브는 SATA와 출력 형식이 다르다. `SMART/Health Information` 섹션의 키-값을 기준으로 판정:

- `Critical Warning` 값이 `0x00`이 아니면 → **Critical**: NVMe 컨트롤러 경고 활성
- `Available Spare` < `Available Spare Threshold` → **Critical**: 예비 공간 임계치 이하
- `Available Spare` ≤ 20% → **Warning**: 예비 공간 부족 임박
- `Percentage Used` ≥ 100% → **Warning**: 설계 수명 도달 (즉시 고장은 아니나 교체 계획 필요)
- `Media and Data Integrity Errors` > 0 → **Critical**: 미디어 무결성 오류 발생
- `Error Information Log Entries` > 0 → **Warning**: 에러 로그 존재 (세부 내용 확인 필요)
- `Warning Composite Temperature Time` 값이 높으면 → **Info**: 과열 이력 존재

NVMe인지 SATA인지 구분법:
- 파일 내에 `SMART/Health Information` 헤더가 있으면 NVMe
- `SMART Attributes Data Structure` 헤더가 있으면 SATA
- 파일명에 `nvme`가 포함되어 있으면 NVMe
```

**검증**: 수정 후 CLAUDE.md의 기존 SATA 판정 기준이 그대로 유지되는지 확인.

---

## 작업 2: SMART 보고서에 RAW_VALUE 수치 노출 의무화

**대상 파일**: `CLAUDE.md` (MCS Log Analyzer 쪽)

**배경**: 현재 SMART 이슈는 "발생/미발생"만 보고한다.
같은 Critical이라도 `Reallocated_Sector_Ct = 3`과 `= 847`은 대응 긴급도가 다르므로,
수치를 보고서에 노출하여 읽는 사람이 판단할 수 있게 한다.

**수정 위치**: `#### drives-and-storage/smartctl-*.txt` 섹션 말미

**추가할 내용**:

```markdown
**SMART 보고 규칙**:
- SMART 이슈 보고 시 해당 속성의 RAW_VALUE를 반드시 함께 기록한다.
  (예: `Reallocated_Sector_Ct RAW_VALUE = 3`, `Current_Pending_Sector RAW_VALUE = 12`)
- NVMe의 경우 해당 키의 실제 값을 기록한다.
  (예: `Available Spare = 15%`, `Media and Data Integrity Errors = 2`)
- 값 자체에 대한 심각도 구간 판정은 하지 않는다. 0 vs non-zero로만 판정하고, 수치는 참고용으로 노출한다.
```

---

## 작업 3: 2-pass 분석 전략 도입

**대상 파일**: `CLAUDE.md` (MCS Log Analyzer 쪽)

**배경**: 현재는 1순위→4순위 순서로 파일을 읽으라고만 되어 있다.
대형 아카이브(journalctl 30일치 등)에서는 1순위 파일에서 컨텍스트 윈도우를 소진할 수 있다.
탐색과 실행을 분리하여 토큰을 효율적으로 사용한다.

**수정 위치**: `### Claude가 해야 할 일 (순서대로)` 섹션을 교체

**변경할 내용**:

```markdown
### Claude가 해야 할 일 (2-pass 전략)

#### Pass 1 — Triage (빠른 탐색)

1. 압축 해제 디렉터리의 파일 목록을 확인한다 (`Glob` 또는 `Bash: ls -R`)
2. `_manifest.txt`가 있으면 이를 읽어 파일 크기를 파악한다
3. `_env-hints.txt`가 있으면 환경 정보(WSL/VM/베어메탈)를 확인한다
4. **작은 파일 우선**: 다음 파일들을 먼저 읽는다 (대부분 수십 줄 이하):
   - `gpu-memory-errors/uncorrected-ecc_errors.txt`
   - `gpu-memory-errors/remapped-memory.txt`
   - `gpu-memory-errors/ecc-errors.txt`
   - `drives-and-storage/df.txt`
   - `drives-and-storage/mdstat.txt`
   - `sensors.txt`
   - `uptime.txt`
   - `nvidia-smi.txt`
   - `systemctl-services.txt`
   - `bmc-info/ipmi-elist.txt`
5. `drives-and-storage/smartctl-*.txt` 파일들을 각각 읽는다
6. **대형 로그는 Grep으로 탐색**: 다음 파일들은 전체를 Read하지 말고 Grep으로 패턴 검색한다:
   - `system-logs/journalctl.txt` → 기존 분석 기준의 Grep 패턴 사용
   - `system-logs/syslog` → 기존 분석 기준의 Grep 패턴 사용
   - `system-logs/kern.log` → 기존 분석 기준의 Grep 패턴 사용
   - `system-logs/dmesg-errors.txt`는 크기가 작으면 Read, 크면 Grep
7. 필터된 파일(`*-filtered.txt`, `*-frequency.txt`)이 존재하면 원본 대신 이를 우선 읽는다

#### Pass 2 — Deep-dive (상세 분석)

8. Pass 1에서 Critical 또는 Warning이 발견된 영역에 대해서만 원본 파일의 관련 부분을 추가 조사한다
   - 예: Grep에서 OOM이 발견되면 해당 시간대 전후 문맥을 Read로 확인
   - 예: SMART Critical이면 해당 드라이브의 전체 smartctl 출력을 정밀 검토
9. 4순위 보조 정보 파일들을 확인한다 (`apt-history.log`, `nvidia-smi.txt` 상세 등)
10. 발견한 모든 문제를 심각도별로 분류하여 기록한다
11. **보고서 형식**에 따라 마크다운 보고서를 `Write` 도구로 지정된 경로에 저장한다
12. stdout에 1~3줄 요약을 출력한다
```

**주의**: 기존 "우선순위 파일 목록 및 분석 기준" 섹션의 판정 기준 자체는 변경하지 않는다.
변경하는 것은 "읽는 순서와 방법"뿐이다.

---

## 작업 4: 시간 상관관계 분석 지침 추가

**대상 파일**: `CLAUDE.md` (MCS Log Analyzer 쪽)

**배경**: 현재는 파일별로 독립적으로 이슈를 나열한다.
실제 장애는 여러 서브시스템에 걸쳐 연쇄적으로 발생하므로,
시간대가 겹치는 이벤트를 묶어서 보고하면 보고서의 진단 가치가 크게 올라간다.

**수정 위치**: `## 보고서 형식` 섹션의 `## 🔴 Critical 이슈` 와 `## 🟡 Warning 이슈` 사이에 새 섹션 추가

**추가할 내용**:

```markdown
## ⏱ 시간 상관관계 분석

이 섹션은 서로 다른 소스에서 발견된 이벤트가 시간적으로 겹치는 경우를 기록한다.
아래 규칙에 따라 분석한다:

### 분석 방법
1. Critical/Warning 이슈에서 타임스탬프를 추출할 수 있는 것들을 모은다
2. 같은 10분 윈도우 안에 2개 이상의 소스에서 이벤트가 발견되면 "상관 클러스터"로 묶는다
3. 클러스터 내 이벤트의 시간 순서를 기록하고, 가능하면 인과관계를 추론한다

### 주요 상관 패턴 (참고용)
- GPU ECC 에러 → OOM kill → 서비스 재시작: GPU 하드웨어 문제로 인한 연쇄 장애 가능성
- 디스크 I/O 에러 → 서비스 crash → 파일시스템 에러: 스토리지 장애 연쇄
- 온도 급등 → GPU/CPU 스로틀링 → 성능 저하: 냉각 문제
- 네트워크 링크 다운 → NFS/Lustre 에러 → 서비스 실패: 네트워크 스토리지 의존성 문제

### 보고 형식
각 클러스터를 아래 형식으로 기록:

    ### 클러스터: [시간대] — [추정 원인 한 줄]
    | 시각 | 출처 파일 | 이벤트 |
    |------|-----------|--------|
    | 10:23:01 | dmesg-errors.txt | I/O error on sda |
    | 10:23:15 | journalctl.txt | systemd: mysql.service failed |
    | 10:23:18 | journalctl.txt | OOM kill: mysqld |

    **추정 인과관계**: 디스크 I/O 오류로 MySQL 서비스가 비정상 종료 후 OOM 발생

타임스탬프를 추출할 수 없는 이벤트는 이 분석에서 제외한다.
상관 클러스터가 없으면 "시간적으로 연관된 이벤트 클러스터가 발견되지 않았습니다"로 표기한다.
```

---

## 작업 5: 환경 감지 및 노이즈 분류 강화

**대상 파일**: `CLAUDE.md` (MCS Log Analyzer 쪽)

**배경**: 현재 WSL 노이즈 분류가 주석 한 줄로만 되어 있다.
VM, 컨테이너, WSL 각각의 노이즈 패턴을 명시하면 오진이 줄어든다.

**수정 위치**: `## 분석 시 주의사항` → `1. 노이즈 구분` 항목을 확장

**변경할 내용**:

```markdown
1. **환경 감지 및 노이즈 구분**:
   분석 시작 전에 다음 방법으로 환경을 판별하고, 환경별 노이즈를 Critical/Warning에서 제외한다:

   **환경 판별 방법** (순서대로 시도):
   - `_env-hints.txt` 파일이 있으면 이를 참조
   - `dmesg-errors.txt` 또는 `kern.log`에서 커널 버전 확인:
     - `microsoft-standard-WSL2` → WSL
     - `QEMU`, `KVM`, `Xen`, `VMware`, `VirtualBox`, `Hyper-V` → VM
   - `hw-list.txt`에서 `QEMU`, `VMware` 등 가상화 벤더 확인
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
```

---

## 작업 6: 보고서 자기검증 지침 추가

**대상 파일**: `CLAUDE.md` (MCS Log Analyzer 쪽)

**배경**: 현재는 보고서 작성 후 검증 단계가 없다.
Critical로 분류한 이슈의 근거가 실제 로그에 존재하는지 재확인하면 오진을 줄일 수 있다.

**수정 위치**: `### Claude가 해야 할 일` 마지막 단계 (보고서 저장 직전)에 추가

**추가할 내용**:

```markdown
### 자기검증 (보고서 저장 직전)

보고서를 Write하기 전에 다음을 확인한다:

1. **Critical 근거 재확인**: 각 Critical 이슈에 대해 "발견 위치"로 적은 파일의 해당 내용이 실제로 존재하는지 Grep 또는 Read로 한 번 더 확인한다. 확인되지 않는 이슈는 제거하거나 Info로 강등한다.
2. **심각도 일관성**: 같은 유형의 이슈가 다른 심각도로 분류되어 있지 않은지 확인한다.
3. **보고서 구조 검증**: 보고서가 지정된 마크다운 형식의 모든 필수 섹션을 포함하는지 확인한다:
   - 메타데이터 (분석 대상, 일시, 호스트명, 업타임)
   - 요약 테이블
   - Critical / Warning / Info 섹션
   - 시간 상관관계 분석 (작업 4 적용 후)
   - 분석 제외 항목
   - 환경 특이사항
```

---

## 적용 순서

1. 작업 2 (SMART RAW_VALUE 노출) — 가장 작은 변경
2. 작업 1 (NVMe 기준 추가) — 섹션 추가
3. 작업 5 (환경 감지 강화) — 기존 항목 확장
4. 작업 3 (2-pass 전략) — 실행 흐름 변경
5. 작업 4 (시간 상관관계) — 새 보고서 섹션
6. 작업 6 (자기검증) — 마지막 단계 추가

각 작업은 독립적으로 적용 가능하다. 순서대로 하되 한 작업 완료 후 다음으로 넘어간다.

---

## 검증 방법

각 작업 적용 후:
1. CLAUDE.md가 문법적으로 올바른 마크다운인지 확인
2. 기존 분석 기준(SATA SMART, dmesg 패턴 등)이 삭제/변경되지 않았는지 확인
3. 가능하면 실제 아카이브로 `./analyze.sh` 테스트 실행
