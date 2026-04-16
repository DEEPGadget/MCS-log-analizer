# 작업 11: 보고서 최상단에 하드웨어 인벤토리 섹션 추가

> **배경**: 장애 분석에 집중하다가 기본적인 하드웨어 인식 누락을 놓친 사례가 있었다.
> (예: SSD 10개 장착 서버에서 lsblk에 5개만 잡히는 것을 보고서에서 확인 불가)
> 보고서 최상단에 하드웨어 인벤토리를 요약하여, 읽는 사람이 "장착된 만큼 정상 인식되는지"를
> 눈으로 빠르게 확인할 수 있게 한다.

---

## 대상 파일: `CLAUDE.md`

## 수정 1: 보고서 형식 — 메타데이터와 요약 사이에 인벤토리 섹션 추가

**수정 위치**: `## 보고서 형식` 섹션 내, `**환경:**` 줄 아래 ~ `## 요약` 위 사이

**추가할 내용**:

```markdown
---

## 하드웨어 인벤토리

> 이 섹션은 장착된 부품이 OS에 정상 인식되는지 **사람이 확인**하기 위한 요약이다.
> 분석기는 값을 추출하여 나열만 하고, 수량이 맞는지 여부는 판정하지 않는다.

### CPU
| 항목 | 값 |
|------|-----|
| 모델명 | [예: AMD EPYC 7543 32-Core Processor] |
| 소켓 수 | [예: 2] |
| 총 코어 수 | [예: 64 (32 per socket)] |
| 총 스레드 수 | [예: 128] |

**데이터 소스**: `hw-list.txt`에서 `*-cpu` 섹션, 또는 `nvidia-bug-report.log` 내 `lscpu` 출력

### GPU
| # | 모델 | PCI Bus ID | 메모리 | 시리얼 |
|---|------|------------|--------|--------|
| 0 | [예: A100-PCIE-80GB] | [00:01.0] | [80GB] | [예: 1234...] |
| 1 | ... | ... | ... | ... |

- **총 GPU 수**: N개
- **드라이버 버전**: [예: 535.129.03]
- **CUDA 버전**: [예: 12.2]

**데이터 소스**: `nvidia-smi.txt`, `gpu-serials.txt`

### 메모리
| 항목 | 값 |
|------|-----|
| 총 용량 | [예: 512 GiB] |
| 슬롯 수 / 장착 수 | [예: 16 슬롯 / 16 장착] (hw-list.txt에서 확인 가능한 경우) |

**데이터 소스**: `hw-list.txt`에서 `*-memory` 섹션

### 스토리지
| # | 장치명 | 종류 | 모델 | 용량 | 마운트 |
|---|--------|------|------|------|--------|
| 1 | nvme0n1 | NVMe SSD | [Samsung 980 PRO 2TB] | 1.8T | / |
| 2 | sda | RAID (HW) | [AVAGO MR9361-8i] | 96T | /mnt/md0 |
| ... | | | | | |

- **NVMe SSD**: N개, 총 X TB
- **SATA SSD**: N개, 총 X TB
- **HDD**: N개, 총 X TB (있는 경우)
- **HW RAID 논리 디스크**: N개 (있는 경우)

**데이터 소스**: `drives-and-storage/lsblk.txt`, `smartctl-*.txt` (모델명/종류 확인)

### InfiniBand
| 항목 | 값 |
|------|-----|
| 유무 | [있음 / 없음] |
| 포트 수 | [예: 2] |
| 상태 | [예: Active / Down] |
| 속도 | [예: 200 Gb/sec (4X HDR)] |

**데이터 소스**: `ibstat.txt`. "No InfiniBand data available"이면 "없음"으로 기록

### PCIe Link Speed
| 장치 | 종류 | 기대 속도 | 현재 속도 | 상태 |
|------|------|-----------|-----------|------|
| 0000:01:00.0 | GPU (A100) | 16GT/s (Gen4) | 16GT/s | ✅ OK |
| 0000:23:00.0 | GPU (A100) | 16GT/s (Gen4) | 8GT/s | ⚠️ Downgraded |
| 0000:b1:00.0 | IB (ConnectX-6) | 16GT/s (Gen4) | 16GT/s | ✅ OK |
| 0000:c1:00.0 | NVMe SSD | 8GT/s (Gen3) | 8GT/s | ✅ OK |

- `LnkCap`(기대) vs `LnkSta`(현재)를 비교
- 현재 속도 < 기대 속도이면 `⚠️ Downgraded`로 표기
- **Downgraded 항목이 있으면 → Warning 이슈로도 등록**

**데이터 소스**: `nvidia-bug-report.log` 내 `lspci -vvv` 출력.
파일이 없으면(`--short` 모드 수집) "nvidia-bug-report.log 없음 — PCIe Link Speed 확인 불가"로 기록.

**장치 종류 구분 방법**:
- lspci 출력에서 `NVIDIA`/`3D controller`/`VGA compatible` → GPU
- `Mellanox`/`InfiniBand` → IB
- `Non-Volatile memory controller`/`NVMe` → NVMe SSD
- 그 외 `SATA controller`, `RAID` 등은 스킵 (Link Speed 의미 낮음)
```

---

## 수정 2: 우선순위 파일 목록에 인벤토리 소스 추가

**수정 위치**: `### Claude가 해야 할 일 (2-pass 전략)` → `#### Pass 1 — Triage` →
단계 3 "작은 파일 우선 Read" 목록에 추가

**변경할 내용**: 기존 목록에 아래를 추가한다:

```markdown
   - `drives-and-storage/lsblk.txt` (스토리지 인벤토리)
   - `gpu-serials.txt` (GPU 시리얼 + Bus ID)
   - `ibstat.txt` (InfiniBand 상태)
```

`hw-list.txt`와 `nvidia-bug-report.log`는 크기가 클 수 있으므로:
- `hw-list.txt`: **Pass 1에서 Read** (보통 수백 줄, 인벤토리 전체 소스)
- `nvidia-bug-report.log`: **Pass 2에서 필요 섹션만 Grep**
  - PCIe Link Speed: `Grep 'LnkSta'` 또는 `Grep 'LnkCap'`
  - CPU 정보: `Grep 'lscpu'` 후 해당 블록 Read (nvidia-bug-report에 포함된 경우)

---

## 수정 3: PCIe Downgrade를 Warning 이슈로 등록

**수정 위치**: `## 우선순위 파일 목록 및 분석 기준` → `### 3순위` 섹션에 추가

**추가할 내용**:

```markdown
#### PCIe Link Speed 저하 (`nvidia-bug-report.log` 내 `lspci -vvv`)
- GPU/IB/NVMe 장치의 `LnkSta` 속도가 `LnkCap` 속도보다 낮으면 → **Warning**: PCIe 링크 다운그레이드
  - 보고서 인벤토리 섹션의 PCIe Link Speed 테이블에도 표기
  - 주요 원인: PCIe 슬롯 접촉 불량, 케이블 문제, BIOS 설정, 써멀 스로틀링
  - 라이저 카드 사용 환경에서 빈발
- `nvidia-bug-report.log`가 없으면 이 항목은 "데이터 없음"으로 분석 제외
```

---

## 수정 4: 인벤토리 분석 순서

인벤토리 데이터 추출은 **Pass 1 초반**에 수행한다.
이유: 인벤토리 정보가 이후 분석의 컨텍스트가 된다
(예: GPU 9개 서버인 줄 알아야 ECC 에러 파일에서 9개 GPU 분량이 있는지 확인 가능)

**Pass 1 순서를 다음으로 조정**:

```
1. _manifest.txt Read
2. _env-hints.txt Read
3. ★ 인벤토리 소스 Read: lsblk.txt, nvidia-smi.txt, gpu-serials.txt, ibstat.txt, hw-list.txt, sensors.txt
4. 나머지 작은 파일 Read (gpu-memory-errors, df.txt, mdstat.txt 등)
5. smartctl-*.txt Read
6. 전처리 파일 Read
```

---

## 검증 방법

적용 후 보고서를 생성하여 다음을 확인:
1. 보고서 최상단(메타데이터와 요약 사이)에 하드웨어 인벤토리 섹션이 존재하는가
2. GPU 수, 스토리지 목록이 `nvidia-smi.txt`, `lsblk.txt`와 일치하는가
3. `nvidia-bug-report.log`가 있는 아카이브에서 PCIe Link Speed 테이블이 출력되는가
4. `nvidia-bug-report.log`가 없는 아카이브(`--short` 모드)에서 "데이터 없음"으로 처리되는가
5. PCIe Downgrade가 발견되면 Warning 이슈 섹션에도 등록되는가
