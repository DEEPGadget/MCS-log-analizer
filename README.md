# MCS Log Analyzer

Manycore 고객사 서버에서 수집된 진단 아카이브(`.tar.gz`)를 Claude AI로 분석하여
잠재적 문제를 탐지하고 한국어 보고서를 자동 생성하는 도구입니다.

## 구조

```
MCS-log-analizer/
├── analyze.sh          # 진입점 — 아카이브 압축 해제 후 Claude 자동 실행
├── CLAUDE.md           # Claude 분석 지침 (분석 기준, 보고서 형식 정의)
├── reports/            # 생성된 보고서 저장 위치 (.gitignore 처리됨)
└── .claude/
    └── settings.json   # Claude Code 권한 및 Hook 설정
```

## 사용법

```bash
./analyze.sh <path-to-tar.gz> [report-name]
```

```bash
# 예시 1: 보고서 이름 자동 생성 (타임스탬프_아카이브명.md)
./analyze.sh /path/to/Manycore-bug-report.tar.gz

# 예시 2: 보고서 이름 직접 지정
./analyze.sh /path/to/Manycore-bug-report.tar.gz KIST-2025-04-29
```

보고서는 `reports/` 디렉터리에 마크다운 파일로 저장됩니다.

## 동작 방식

1. `analyze.sh`가 `.tar.gz` 아카이브를 임시 디렉터리에 압축 해제
2. bash로 대형 로그 파일을 전처리하여 `_preprocessed/` 디렉터리에 저장
   - journalctl → 에러 필터, 구조적 이벤트, 밀도 분석, 부팅 경계 추출
   - syslog / kern.log → 에러 필터
   - dmesg (전체) → 크래시 문맥(스택 트레이스 포함), 에러 필터
3. Claude Code(`-p` print 모드)를 비대화형으로 실행
4. Claude가 `CLAUDE.md`의 지침에 따라 전처리 파일 기반으로 분석 (2-pass 전략)
5. `reports/` 경로에 마크다운 보고서 저장 후 콘솔에 1~3줄 요약 출력

분석 대상 로그 아카이브는 `deepgadget-log-grabber.sh`로 수집된 것을 기준으로 합니다.

## 분석 항목

| 순위 | 항목 |
|------|------|
| 1순위 | dmesg 오류, GPU ECC/리매핑 오류, SMART (SATA·NVMe) |
| 2순위 | journalctl, syslog, kern.log |
| 3순위 | 디스크 사용량, 온도·센서, IPMI, RAID |
| 4순위 | nvidia-smi, apt 이력, 서비스 상태, 업타임 |

보고서에는 Critical / Warning / Info 심각도 분류와 시간 상관관계 분석이 포함됩니다.

## 요구 사항

- [Claude Code](https://claude.ai/code) CLI (`claude` 명령어가 PATH에 있어야 함)
- `bash`, `tar`

## 참고

- 분석 기준 및 보고서 형식 상세: [`CLAUDE.md`](CLAUDE.md)
- 보고서는 민감한 고객 정보를 포함할 수 있으므로 `reports/`는 `.gitignore` 처리되어 있습니다.
