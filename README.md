# MCS-log-analyzer

Manycore 고객사 서버에서 수집된 진단 아카이브(`.tar.gz`)를 Claude AI로 분석하여
잠재적 문제를 탐지하고 한국어 보고서를 자동 생성하는 도구입니다.

## 구조

```
MCS-log-analizer/
├── analyze.sh             # 진입점 — 아카이브 압축 해제, 전처리, Claude 자동 실행
├── CLAUDE.md              # Claude 분석 지침 (분석 기준, 하네스 규칙)
├── report-template.md     # 보고서 마크다운 형식 템플릿
├── correlation-guide.md   # 시간 상관관계 분석 방법론
├── reports/               # 생성된 보고서 저장 위치
└── .claude/
    └── settings.json      # Claude Code 권한 및 Hook 설정
```

## 사용법

```bash
./analyze.sh <path-to-tar.gz> [report-name]
```

```bash
# 예시 1: 보고서 이름 자동 생성 (타임스탬프_아카이브명.md)
./analyze.sh /path/to/Manycore-bug-report.tar.gz

# 예시 2: 보고서 이름 직접 지정
./analyze.sh /path/to/Manycore-bug-report.tar.gz Customer-2025-04-29
```

보고서는 `reports/` 디렉터리에 마크다운 파일로 저장됩니다.

## 동작 방식

1. `analyze.sh`가 `.tar.gz` 아카이브를 임시 디렉터리(`/tmp/mcs-log-XXXXX`)에 압축 해제
2. bash로 대형 로그 파일을 전처리하여 `_preprocessed/` 디렉터리에 저장 (토큰 비용 0):
   - `journalctl.txt` → 에러 필터, 구조적 이벤트(lifecycle), 분 단위 밀도, 부팅 경계(boots/context)
   - `syslog` / `kern.log` → 에러 패턴 필터
   - `dmesg` (원본) → 크래시 문맥(스택 트레이스 포함), 에러 필터
   - 에러 메시지 빈도 집계 (`*-frequency.txt`)
3. 파일 매니페스트(`_manifest.txt`) 및 환경 감지 결과(`_env-hints.txt`) 생성
4. Claude Code(`-p` print 모드)를 비대화형으로 실행
5. Claude가 `CLAUDE.md`의 지침에 따라 2-pass 전략으로 분석:
   - **Pass 1 (Triage)**: 전처리 파일과 인벤토리 파일 Read → 전체 이슈 파악
   - **Pass 2 (Deep-dive)**: Critical/Warning 발견 영역의 원본 파일을 Grep → 문맥·인과관계 확인
6. `reports/` 경로에 마크다운 보고서 저장 후 콘솔에 1~3줄 요약 출력

> **참고**: 아카이브에 파일이 200개를 초과하거나 `var-log-archived/` 디렉터리가 존재하면
> Claude는 분석 전 Plan Mode로 탐색 범위를 확정한 뒤 실행합니다.

분석 대상 로그 아카이브는 `deepgadget-log-grabber.sh`로 수집된 것을 기준으로 합니다.

## 분석 항목

| 순위 | 항목 |
|------|------|
| 1순위 | dmesg 오류, GPU ECC/리매핑 오류, SMART (SATA·NVMe, 온도 이력·써멀 스로틀링 포함) |
| 2순위 | journalctl, syslog, kern.log (커널 BUG:/Oops: 포함, 전처리 파일 기반 분석) |
| 3순위 | 디스크 사용량, 온도·센서, IPMI, RAID, PCIe Link Speed |
| 4순위 | nvidia-smi, apt 이력, 서비스 상태(unattended-upgrades·절전 설정 포함), 업타임 |

보고서에는 하드웨어 인벤토리(CPU/GPU/메모리/스토리지/IB/PCIe Link Speed), Critical / Warning / Info 심각도 분류, 시간 상관관계 분석이 포함됩니다.

## 요구 사항

- [Claude Code](https://claude.ai/code) CLI (`claude` 명령어가 PATH에 있어야 함)
- `bash`, `tar`
