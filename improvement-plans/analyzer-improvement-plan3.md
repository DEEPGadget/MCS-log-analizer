# MCS Log Analyzer 개선 계획서

> **용도**: 이 파일을 Claude Code에 전달하여 `analyze.sh`와 `CLAUDE.md`를 개선한다.
> **작업 원칙**: 기존 CLAUDE.md의 규칙(§1 스타일 유지, §10 리팩터링 금지)을 준수한다.
> **제출 형식**: 각 항목별 unified diff 패치. 변경이 큰 경우에만 전체 파일 제공.

---

## 설계 원칙: 토큰 절약 아키텍처

이 개선의 핵심 원칙은 **"bash로 할 수 있는 건 bash에서, Claude에게는 판단만 시킨다"**이다.

```
analyze.sh 실행 흐름:

  tar 압축 해제        (bash — 토큰 0)
  ↓
  전처리: grep/awk     (bash — 토큰 0)  ← 백만 줄 → 천 줄로 축소
  ↓
  파일 매니페스트 생성  (bash — 토큰 0)
  ↓
  환경 감지            (bash — 토큰 0)
  ↓
  claude 호출          (여기서부터 토큰 사용)
  ↓
  Claude는 정제된 파일만 읽고 "판단"에 집중
```

반면 전처리 없이 Claude가 직접 Grep하면:
- Grep 호출마다 입출력 모두 토큰 소모
- 패턴 10개 × 대형 파일 3개 = 30번 도구 호출
- 결과가 수천 줄이면 컨텍스트 윈도우 압박

**따라서 작업 1~3(analyze.sh 전처리)을 먼저 구현하고, 작업 4~9(CLAUDE.md)를 이에 맞춰 수정한다.**

---

## 작업 1: analyze.sh에 로그 전처리 단계 추가

**대상 파일**: `analyze.sh`

**수정 위치**: `# ── 압축 해제 ──` 블록과 `# ── Claude 프롬프트 구성 ──` 블록 사이에 새 섹션 삽입

**배경**: journalctl.txt(30일치 수십만~백만 줄), syslog, kern.log 등 대형 로그를
Claude가 직접 Grep하면 도구 호출마다 토큰을 소모한다.
bash grep/awk는 토큰 0이므로 전처리로 정제한 파일만 Claude에게 넘긴다.

**추가할 코드**:

```bash
# ── 로그 전처리 (토큰 절약) ─────────────────────────────────────────────
# Claude 호출 전에 bash로 대형 로그를 정제한다.
# 이 단계는 토큰을 소모하지 않는다.
PREPROCESS_DIR="$EXTRACTED_DIR/_preprocessed"
mkdir -p "$PREPROCESS_DIR"

info "로그 전처리 중..."

# --- journalctl.txt 전처리 (가장 큰 파일, 3단계로 분해) ---
JOURNALCTL="$EXTRACTED_DIR/system-logs/journalctl.txt"
if [ -f "$JOURNALCTL" ]; then
    JCTL_LINES=$(wc -l < "$JOURNALCTL")
    info "  journalctl.txt: ${JCTL_LINES} 줄 → 전처리 시작"

    # 1) 키워드 필터: 알려진 문제 패턴
    grep -inE 'fail|error|oom|panic|segfault|critical|watchdog|killed|warning.*:' \
        "$JOURNALCTL" > "$PREPROCESS_DIR/journalctl-errors.txt" 2>/dev/null || true

    # 2) 구조적 이벤트: 키워드로 못 잡는 시스템 상태 변화
    grep -inE 'Reached target.*(Power-Off|Reboot|Shutdown|Multi-User)|logind.*(Power key|Lid|Suspend)|Started.*Shutdown|Stopping|Started.*Reboot|shutdown\[|reboot\[|Power-Off' \
        "$JOURNALCTL" > "$PREPROCESS_DIR/journalctl-lifecycle.txt" 2>/dev/null || true

    # 3) 시간대별 로그 밀도 (분 단위, 상위 50개 — 비정상 폭주 구간 탐지)
    #    특정 분에 로그가 수천 줄 몰리면 그 시간대에 사건 발생
    awk '{ ts=substr($0,1,15); print ts }' "$JOURNALCTL" \
        | sort | uniq -c | sort -rn | head -50 \
        > "$PREPROCESS_DIR/journalctl-density.txt" 2>/dev/null || true

    FILTERED_LINES=$(wc -l < "$PREPROCESS_DIR/journalctl-errors.txt" 2>/dev/null || echo 0)
    info "  journalctl.txt: ${JCTL_LINES} 줄 → errors ${FILTERED_LINES} 줄로 축소"
fi

# --- syslog 전처리 ---
SYSLOG="$EXTRACTED_DIR/system-logs/syslog"
if [ -f "$SYSLOG" ]; then
    grep -inE 'error|fatal|fail|oom|panic|authentication failure|Failed password|disk I/O|read error|CRON.*ERROR' \
        "$SYSLOG" > "$PREPROCESS_DIR/syslog-errors.txt" 2>/dev/null || true
    info "  syslog: $(wc -l < "$SYSLOG") 줄 → errors $(wc -l < "$PREPROCESS_DIR/syslog-errors.txt") 줄"
fi

# --- kern.log 전처리 ---
KERNLOG="$EXTRACTED_DIR/system-logs/kern.log"
if [ -f "$KERNLOG" ]; then
    grep -inE 'error|warning|fail|EXT4-fs error|XFS error|link is not ready|Link is Down|I/O error|oom|panic|MCE|EDAC' \
        "$KERNLOG" > "$PREPROCESS_DIR/kern-errors.txt" 2>/dev/null || true
    info "  kern.log: $(wc -l < "$KERNLOG") 줄 → errors $(wc -l < "$PREPROCESS_DIR/kern-errors.txt") 줄"
fi

# --- dmesg-errors.txt 전처리 (보통 작지만 큰 경우 대비) ---
DMESG="$EXTRACTED_DIR/system-logs/dmesg-errors.txt"
if [ -f "$DMESG" ]; then
    DMESG_LINES=$(wc -l < "$DMESG")
    if [ "$DMESG_LINES" -gt 500 ]; then
        grep -inE 'panic|Oops|BUG:|Out of memory|oom|I/O error|blk_update_request|SCSI error|Hardware Error|EDAC|MCE|Machine Check|RAID|md:|mdadm|NFS|Lustre|filesystem error' \
            "$DMESG" > "$PREPROCESS_DIR/dmesg-critical.txt" 2>/dev/null || true
        info "  dmesg-errors.txt: ${DMESG_LINES} 줄 (대형) → critical $(wc -l < "$PREPROCESS_DIR/dmesg-critical.txt") 줄"
    else
        info "  dmesg-errors.txt: ${DMESG_LINES} 줄 (소형, 전처리 불필요)"
    fi
fi

# --- 에러 빈도 집계 (전체 소스 통합) ---
# 반복되는 동일 에러 메시지를 집약하여 Claude가 "N회 반복"으로 처리하도록 돕는다
for src in "$PREPROCESS_DIR"/journalctl-errors.txt "$PREPROCESS_DIR"/syslog-errors.txt "$PREPROCESS_DIR"/kern-errors.txt; do
    if [ -f "$src" ]; then
        basename_src="$(basename "$src" .txt)"
        # 타임스탬프 제거 후 메시지 본문만으로 빈도 집계
        sed -E 's/^[0-9]+[:-].{0,20}//' "$src" \
            | sort | uniq -c | sort -rn | head -100 \
            > "$PREPROCESS_DIR/${basename_src}-frequency.txt" 2>/dev/null || true
    fi
done

info "로그 전처리 완료 → $PREPROCESS_DIR/"
```

**주의사항**:
- 모든 grep에 `|| true`를 붙여서 매칭 0건이어도 `set -e`에 안 걸리게 한다
- `2>/dev/null`로 "파일 없음" 에러를 숨긴다
- 전처리 결과는 `_preprocessed/` 디렉터리에 넣어서 원본과 분리한다

---

## 작업 2: analyze.sh에 파일 매니페스트 생성 추가

**대상 파일**: `analyze.sh`

**수정 위치**: 작업 1 전처리 블록 바로 아래

**배경**: Claude가 `ls -R`부터 해야 하면 도구 호출 1회를 토큰으로 소비한다.
매니페스트를 미리 만들어두면 Claude는 Read 한 번으로 전체 파일 구조 + 크기를 파악할 수 있다.

**추가할 코드**:

```bash
# ── 파일 매니페스트 생성 ───────────────────────────────────────────────────
info "파일 매니페스트 생성 중..."
{
    echo "# 아카이브 파일 매니페스트"
    echo "# 생성 시각: $(date -Iseconds)"
    echo "# 형식: [크기(bytes)] [파일경로]"
    echo "---"
    find "$EXTRACTED_DIR" -type f -printf '%s %P\n' | sort -k2
} > "$EXTRACTED_DIR/_manifest.txt"

# 전처리 파일도 매니페스트에 추가
if [ -d "$PREPROCESS_DIR" ]; then
    echo "--- preprocessed ---" >> "$EXTRACTED_DIR/_manifest.txt"
    find "$PREPROCESS_DIR" -type f -printf '%s %P\n' | sort -k2 >> "$EXTRACTED_DIR/_manifest.txt"
fi

info "매니페스트 생성 완료: $(grep -c '' "$EXTRACTED_DIR/_manifest.txt") 항목"
```

---

## 작업 3: analyze.sh에 환경 감지 추가

**대상 파일**: `analyze.sh`

**수정 위치**: 작업 2 매니페스트 블록 바로 아래

**배경**: WSL/VM/베어메탈 판별을 Claude가 하면 여러 파일을 Read/Grep해야 한다.
bash로 미리 감지해두면 Claude는 결과만 읽으면 된다.

**추가할 코드**:

```bash
# ── 환경 감지 ──────────────────────────────────────────────────────────────
info "환경 감지 중..."
ENV_HINTS="$EXTRACTED_DIR/_env-hints.txt"
{
    echo "# 환경 감지 결과"
    echo "# 생성 시각: $(date -Iseconds)"

    ENV_TYPE="베어메탈"

    # 커널 버전에서 WSL 감지
    for kfile in "$EXTRACTED_DIR/system-logs/dmesg-errors.txt" \
                 "$EXTRACTED_DIR/system-logs/kern.log" \
                 "$EXTRACTED_DIR/nvidia-bug-report.log"; do
        if [ -f "$kfile" ] && grep -qi 'microsoft-standard-WSL' "$kfile" 2>/dev/null; then
            ENV_TYPE="WSL2"
            break
        fi
    done

    # VM 감지 (WSL이 아닌 경우만)
    # ⚠ 주의: kvm_amd, kvm_intel 등 KVM 모듈 로딩 로그는 베어메탈 호스트에서도 나타남.
    #   "KVM"이라는 단어가 있다고 VM 게스트가 아님.
    #   반드시 **게스트 전용 지표**만 사용해야 한다:
    #   - DMI 정보에 가상 하드웨어 제조사 (QEMU Virtual, VMware Virtual, VirtualBox 등)
    #   - "Hypervisor detected" 커널 메시지 (단, nested virt 호스트에서도 나올 수 있어 DMI와 교차 확인)
    #   - /sys/class/dmi/id/product_name 또는 hw-list.txt의 product 필드
    #
    # 잘못된 예: grep -qiE 'QEMU|KVM|Xen|VMware' → KVM 호스트를 VM으로 오판
    # 올바른 예: DMI product/manufacturer에서 가상 하드웨어 벤더 확인

    if [ "$ENV_TYPE" = "베어메탈" ]; then
        for vfile in "$EXTRACTED_DIR/system-logs/dmesg-errors.txt" \
                     "$EXTRACTED_DIR/system-logs/kern.log" \
                     "$EXTRACTED_DIR/hw-list.txt"; do
            if [ ! -f "$vfile" ]; then continue; fi

            # 1) DMI 기반 감지 — 가장 신뢰도 높음 (게스트에서만 나타나는 가상 하드웨어)
            if grep -qiE 'DMI:.*QEMU|DMI:.*VirtualBox|DMI:.*VMware.*Virtual|DMI:.*Microsoft.*Virtual|product.*QEMU|QEMU Standard PC' "$vfile" 2>/dev/null; then
                VM_VENDOR=$(grep -oiE 'QEMU|VMware|VirtualBox|Hyper-V' "$vfile" | head -1)
                ENV_TYPE="VM (${VM_VENDOR:-unknown})"
                break
            fi

            # 2) Hypervisor detected 메시지 — 게스트 커널이 출력 (보조 지표)
            #    단독으로는 nested virt 호스트에서도 나올 수 있으므로,
            #    위 DMI에서 안 잡힌 경우 fallback으로만 사용
            if grep -qiE 'Hypervisor detected' "$vfile" 2>/dev/null; then
                # Xen은 DMI에 안 나올 수 있으므로 여기서 잡음
                if grep -qiE 'Xen HVM' "$vfile" 2>/dev/null; then
                    ENV_TYPE="VM (Xen)"
                    break
                fi
            fi
        done
    fi

    echo "ENV_TYPE=${ENV_TYPE}"

    # 호스트명 추출
    HOSTNAME_FILE="$EXTRACTED_DIR/networking/etc-hostname.txt"
    if [ -f "$HOSTNAME_FILE" ]; then
        echo "HOSTNAME=$(cat "$HOSTNAME_FILE" | tr -d '[:space:]')"
    elif [ -f "$EXTRACTED_DIR/etc-config/networking/etc-hostname.txt" ]; then
        echo "HOSTNAME=$(cat "$EXTRACTED_DIR/etc-config/networking/etc-hostname.txt" | tr -d '[:space:]')"
    else
        echo "HOSTNAME=알 수 없음"
    fi

    # 커널 버전 추출
    if [ -f "$EXTRACTED_DIR/grub/proc_cmdline.txt" ]; then
        KVER=$(grep -oE 'BOOT_IMAGE=[^ ]+' "$EXTRACTED_DIR/grub/proc_cmdline.txt" | head -1)
        echo "KERNEL_BOOT=${KVER}"
    fi

} > "$ENV_HINTS"

info "환경 감지 완료: $(grep 'ENV_TYPE' "$ENV_HINTS")"
```

---

## 작업 4: analyze.sh 프롬프트에 전처리 안내 추가

**대상 파일**: `analyze.sh`

**수정 위치**: `# ── Claude 프롬프트 구성 ──` 블록의 PROMPT 변수

**배경**: Claude가 전처리 파일의 존재와 용도를 알아야 올바르게 사용한다.

**변경할 내용**:

```bash
PROMPT="로그 분석 작업을 시작합니다.

압축 해제된 진단 아카이브 경로: ${EXTRACTED_DIR}
보고서 저장 경로: ${REPORT_FILE}

전처리 결과: ${EXTRACTED_DIR}/_preprocessed/ 디렉터리에 정제된 로그 파일이 있습니다.
환경 정보: ${EXTRACTED_DIR}/_env-hints.txt
파일 매니페스트: ${EXTRACTED_DIR}/_manifest.txt

CLAUDE.md의 분석 가이드라인을 따라 위 경로의 로그 파일들을 분석하고,
지정된 보고서 저장 경로에 Write 도구로 보고서를 저장해 주세요."
```

---

## 작업 5: CLAUDE.md — NVMe 드라이브 분석 기준 추가

**대상 파일**: `CLAUDE.md` (MCS Log Analyzer 쪽)

**수정 위치**: `## 우선순위 파일 목록 및 분석 기준` → `### 1순위` → `#### drives-and-storage/smartctl-*.txt` 섹션 아래

**현재 상태 확인**: 이미 NVMe 섹션과 SMART 보고 규칙이 추가되어 있다면 이 작업은 건너뛴다.
없는 경우에만 아래 내용을 추가한다.

**추가할 내용**:

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

---

## 작업 6: CLAUDE.md — SMART 보고서에 RAW_VALUE 노출 의무화

**대상 파일**: `CLAUDE.md` (MCS Log Analyzer 쪽)

**수정 위치**: `#### drives-and-storage/smartctl-*.txt` 섹션 말미 (NVMe 섹션 아래)

**현재 상태 확인**: 이미 SMART 보고 규칙이 있으면 건너뛴다.

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

## 작업 7: CLAUDE.md — 2-pass 분석 전략을 전처리 기반으로 수정

**대상 파일**: `CLAUDE.md` (MCS Log Analyzer 쪽)

**수정 위치**: `### Claude가 해야 할 일 (2-pass 전략)` 섹션 전체 교체

**배경**: 전처리가 도입되었으므로 Claude의 분석 전략을 전처리 파일 기반으로 재작성한다.
핵심 변경: "대형 로그는 Grep으로 탐색" → "전처리 파일을 Read로 읽기"

**변경할 내용**:

```markdown
### Claude가 해야 할 일 (2-pass 전략)

#### Pass 1 — Triage (빠른 탐색)

1. `_manifest.txt`를 Read하여 아카이브 전체 파일 구조와 크기를 파악한다
2. `_env-hints.txt`를 Read하여 환경 정보(WSL/VM/베어메탈, 호스트명)를 확인한다
3. **작은 파일 우선 Read** (대부분 수십 줄 이하):
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
4. `drives-and-storage/smartctl-*.txt` 파일들을 각각 Read한다
5. **전처리 파일 Read** (`_preprocessed/` 디렉터리):
   - `journalctl-errors.txt` — 키워드 필터된 에러/경고
   - `journalctl-lifecycle.txt` — 시스템 종료/재부팅 등 구조적 이벤트
   - `journalctl-density.txt` — 시간대별 로그 밀도 (비정상 폭주 구간)
   - `syslog-errors.txt` — syslog 에러 필터
   - `kern-errors.txt` — kern.log 에러 필터
   - `*-frequency.txt` — 에러 메시지별 빈도 집계
   - `dmesg-critical.txt` — dmesg가 대형(500줄+)인 경우에만 존재
6. `system-logs/dmesg-errors.txt`는 전처리 파일(`dmesg-critical.txt`)이 없으면 원본을 직접 Read한다 (보통 소형)

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
```

---

## 작업 8: CLAUDE.md — 시간 상관관계 분석 지침 추가

**대상 파일**: `CLAUDE.md` (MCS Log Analyzer 쪽)

**수정 위치**: 보고서 형식 섹션 내, `## 🔴 Critical 이슈` 아래에 새 섹션

**현재 상태 확인**: 이미 `## ⏱ 시간 상관관계 분석` 섹션이 있으면 건너뛴다.

**추가할 내용**: (기존 plan의 작업 4 내용과 동일 — 이미 CLAUDE.md에 반영된 상태이면 skip)

---

## 작업 9: CLAUDE.md — 환경 감지 노이즈 분류 강화

**대상 파일**: `CLAUDE.md` (MCS Log Analyzer 쪽)

**수정 위치**: `## 분석 시 주의사항` → `1. 노이즈 구분` 항목

**현재 상태 확인**: 이미 환경 감지 섹션이 확장되어 있으면 건너뛴다.

**핵심 변경**: 전처리에서 `_env-hints.txt`를 생성하므로, Claude의 환경 판별 로직을 단순화한다.

```markdown
1. **환경 감지 및 노이즈 구분**:

   **환경 판별**: `_env-hints.txt`의 `ENV_TYPE` 값을 사용한다.
   파일이 없는 경우에만 아래 수동 판별을 수행:
   - `deepgadget-log-grabber`로 수집된 아카이브는 **거의 항상 베어메탈**이다.
     가상화 증거가 명확히 발견되지 않으면 베어메탈로 간주한다.
   - `dmesg-errors.txt` 또는 `kern.log`에서 커널 버전 확인:
     - `microsoft-standard-WSL2` → WSL
   - VM 판별 시 **게스트 전용 지표**만 사용:
     - DMI 정보에 가상 하드웨어 제조사 (`QEMU Virtual`, `VMware Virtual`, `VirtualBox` 등)
     - ⚠ `kvm_amd`, `kvm_intel`, `KVM` 단어 자체는 베어메탈 KVM 호스트에서도 나타나므로 VM 판정 근거로 사용하지 않는다
   - `hw-list.txt`에서 product/manufacturer 필드에 가상 하드웨어 벤더 확인
   - 위 모두 해당 없으면 베어메탈로 간주

   [이하 환경별 노이즈 패턴은 기존과 동일하게 유지]
```

---

## 작업 10: CLAUDE.md — 자기검증 지침 추가

**대상 파일**: `CLAUDE.md` (MCS Log Analyzer 쪽)

**수정 위치**: 2-pass 전략 섹션 말미, 보고서 저장 직전

**현재 상태 확인**: 이미 자기검증 섹션이 있으면 건너뛴다.

**추가할 내용**:

```markdown
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
```

---

## 적용 순서

**Phase 1 — analyze.sh 전처리 (토큰 절약 인프라)**
1. 작업 1: 로그 전처리 (journalctl/syslog/kern.log/dmesg 필터링 + 밀도 분석 + 빈도 집계)
2. 작업 2: 파일 매니페스트 생성
3. 작업 3: 환경 감지
4. 작업 4: 프롬프트 업데이트

**Phase 2 — CLAUDE.md 분석 기준 보강**
5. 작업 5: NVMe 분석 기준 (이미 있으면 skip)
6. 작업 6: SMART RAW_VALUE 노출 (이미 있으면 skip)
7. 작업 7: 2-pass 전략을 전처리 기반으로 수정 ← 핵심 변경
8. 작업 8: 시간 상관관계 분석 (이미 있으면 skip)
9. 작업 9: 환경 감지를 `_env-hints.txt` 기반으로 단순화
10. 작업 10: 자기검증 지침 (이미 있으면 skip)

**각 작업은 독립적으로 적용 가능하되, 작업 7은 반드시 작업 1~4 이후에 적용한다.**

---

## 검증 방법

### Phase 1 (analyze.sh) 검증:
```bash
# 1) 전처리가 정상 동작하는지 확인 (Claude 호출 전에 Ctrl+C로 중단해도 됨)
./analyze.sh /path/to/test-archive.tar.gz test-run

# 2) 전처리 결과 확인
ls -la /tmp/mcs-log-*/Manycore-bug-report/_preprocessed/
cat /tmp/mcs-log-*/Manycore-bug-report/_manifest.txt | head -20
cat /tmp/mcs-log-*/Manycore-bug-report/_env-hints.txt
```

### Phase 2 (CLAUDE.md) 검증:
```bash
# 3) 실제 아카이브로 전체 파이프라인 테스트
./analyze.sh /path/to/test-archive.tar.gz full-test

# 4) 보고서가 올바른 구조인지 확인
grep -c '## 🔴\|## 🟡\|## 🔵\|## ⏱' reports/full-test.md
# 기대값: 4 (Critical, Warning, Info, 시간상관관계 각 1개씩)
```
