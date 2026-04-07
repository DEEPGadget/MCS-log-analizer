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

# ── Claude 프롬프트 구성 ───────────────────────────────────────────────────
# CLAUDE.md의 분석 지침을 참조하도록 안내
# Claude는 CLAUDE.md를 자동으로 읽으므로 간결하게 작성
PROMPT="로그 분석 작업을 시작합니다.

압축 해제된 진단 아카이브 경로: ${EXTRACTED_DIR}
보고서 저장 경로: ${REPORT_FILE}

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
