#!/usr/bin/env bash
# MCS Log Analyzer — 진입점 스크립트
# 사용법: ./analyze.sh <path-to-tar.gz> [report-name]
#
# Claude Code harness engineering 예시:
#   - CLAUDE.md: 분석 지침 (Claude가 자동으로 읽음)
#   - --dangerously-skip-permissions: 자동화 실행 시 권한 승인 생략
#   - -p <prompt>: 비대화형 print 모드 (stdout에 결과 출력)

set -euo pipefail

# ── 색상 출력 ──────────────────────────────────────────────────────────────
RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'; NC='\033[0m'
info()  { echo -e "${GREEN}[*]${NC} $*"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*"; }
error() { echo -e "${RED}[✗]${NC} $*" >&2; }

# ── 인자 확인 ──────────────────────────────────────────────────────────────
if [ $# -lt 1 ]; then
    echo "사용법: $0 <path-to-tar.gz> [report-name]"
    echo ""
    echo "  예시: $0 /path/to/Manycore-bug-report.tar.gz"
    echo "       $0 /path/to/Manycore-bug-report.tar.gz customer-abc-2026-04-07"
    exit 1
fi

TARBALL="$(realpath "$1")"
if [ ! -f "$TARBALL" ]; then
    error "파일이 없습니다: $TARBALL"
    exit 1
fi

# ── 경로 설정 ──────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPORT_DIR="$SCRIPT_DIR/reports"
TIMESTAMP="$(date +%y%m%d%H%M%S)"
BASENAME="$(basename "$TARBALL" .tar.gz)"
REPORT_NAME="${2:-${TIMESTAMP}_${BASENAME}}"
REPORT_FILE="$REPORT_DIR/${REPORT_NAME}.md"

# 임시 디렉터리 (종료 시 자동 삭제)
WORKSPACE="$(mktemp -d -t mcs-log-XXXXXX)"
trap 'rm -rf "$WORKSPACE"' EXIT

# ── 압축 해제 ──────────────────────────────────────────────────────────────
info "압축 해제 중: $TARBALL"
tar -xzf "$TARBALL" -C "$WORKSPACE"

# 최상위 디렉터리 탐색 (아카이브 구조에 따라 다를 수 있음)
EXTRACTED_DIR="$(find "$WORKSPACE" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | head -1)"
if [ -z "$EXTRACTED_DIR" ]; then
    # 최상위 디렉터리 없이 파일이 바로 압축된 경우
    EXTRACTED_DIR="$WORKSPACE"
fi

info "압축 해제 완료: $EXTRACTED_DIR"
info "보고서 저장 경로: $REPORT_FILE"

mkdir -p "$REPORT_DIR"

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

# ── 파일 매니페스트 생성 ───────────────────────────────────────────────────
info "파일 매니페스트 생성 중..."
{
    echo "# 아카이브 파일 매니페스트"
    echo "# 생성 시각: $(date -Iseconds)"
    echo "# 형식: [크기(bytes)] [파일경로]"
    echo "---"
    find "$EXTRACTED_DIR" -type f -printf '%s %P\n' | sort -k2
} > "$EXTRACTED_DIR/_manifest.txt"

if [ -d "$PREPROCESS_DIR" ]; then
    echo "--- preprocessed ---" >> "$EXTRACTED_DIR/_manifest.txt"
    find "$PREPROCESS_DIR" -type f -printf '%s %P\n' | sort -k2 >> "$EXTRACTED_DIR/_manifest.txt"
fi

info "매니페스트 생성 완료: $(grep -c '' "$EXTRACTED_DIR/_manifest.txt") 항목"

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
    if [ "$ENV_TYPE" = "베어메탈" ]; then
        for vfile in "$EXTRACTED_DIR/system-logs/dmesg-errors.txt" \
                     "$EXTRACTED_DIR/system-logs/kern.log" \
                     "$EXTRACTED_DIR/hw-list.txt"; do
            if [ -f "$vfile" ] && grep -qiE 'QEMU|KVM|Xen|VMware|VirtualBox|Hyper-V' "$vfile" 2>/dev/null; then
                VM_VENDOR=$(grep -oiE 'QEMU|KVM|Xen|VMware|VirtualBox|Hyper-V' "$vfile" | head -1)
                ENV_TYPE="VM (${VM_VENDOR})"
                break
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

# ── Claude 프롬프트 구성 ───────────────────────────────────────────────────
# CLAUDE.md의 분석 지침을 참조하도록 안내
# Claude는 CLAUDE.md를 자동으로 읽으므로 간결하게 작성
PROMPT="로그 분석 작업을 시작합니다.

압축 해제된 진단 아카이브 경로: ${EXTRACTED_DIR}
보고서 저장 경로: ${REPORT_FILE}

전처리 결과: ${EXTRACTED_DIR}/_preprocessed/ 디렉터리에 정제된 로그 파일이 있습니다.
환경 정보: ${EXTRACTED_DIR}/_env-hints.txt
파일 매니페스트: ${EXTRACTED_DIR}/_manifest.txt

CLAUDE.md의 분석 가이드라인을 따라 위 경로의 로그 파일들을 분석하고,
지정된 보고서 저장 경로에 Write 도구로 보고서를 저장해 주세요."

# ── Claude 실행 ────────────────────────────────────────────────────────────
# --dangerously-skip-permissions : 자동화 실행 — 모든 도구 권한 자동 승인
# -p                             : print 모드 — 비대화형, 결과를 stdout으로 출력
# Claude는 CLAUDE.md를 읽고, 지정된 경로의 파일들을 Read/Grep으로 분석 후
# Write 도구로 보고서를 생성한다
echo ""
info "Claude 분석 시작..."
echo "────────────────────────────────────────────────────────────────"
claude --dangerously-skip-permissions -p "$PROMPT"
echo "────────────────────────────────────────────────────────────────"

# ── 결과 확인 ──────────────────────────────────────────────────────────────
if [ -f "$REPORT_FILE" ]; then
    echo ""
    info "분석 완료!"
    echo -e "  보고서: ${GREEN}${REPORT_FILE}${NC}"
    echo ""
    # 보고서 첫 30줄 미리보기
    echo "──── 보고서 미리보기 ────"
    head -30 "$REPORT_FILE"
    echo "..."
    echo "(전체 보고서: $REPORT_FILE)"
else
    warn "보고서 파일이 생성되지 않았습니다. Claude 출력을 확인하세요."
    warn "Claude가 Write 도구를 사용하지 않았을 수 있습니다."
fi
