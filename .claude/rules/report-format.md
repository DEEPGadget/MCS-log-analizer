## 보고서 형식

보고서 파일을 `Write` 도구로 지정된 경로에 저장한다. 형식:

```markdown
# Manycore 서버 진단 보고서

**분석 대상:** [아카이브 이름]
**분석 일시:** [현재 날짜/시간]
**호스트명:** [etc-hostname.txt 에서 추출, 없으면 "알 수 없음"]
**시스템 업타임:** [uptime.txt 내용]
**환경:** [WSL2 / VM (QEMU) / 베어메탈 중 해당하는 것]

---

## 하드웨어 인벤토리

> 이 섹션은 장착된 부품이 OS에 정상 인식되는지 **사람이 확인**하기 위한 요약이다.
> 분석기는 값을 추출하여 나열만 하고, 수량이 맞는지 여부는 판정하지 않는다.

### CPU
| 항목 | 값 |
|------|-----|
| 모델명 | [hw-list.txt에서 추출] |
| 소켓 수 | [예: 2] |
| 총 코어 수 | [예: 64 (32 per socket)] |
| 총 스레드 수 | [예: 128] |

**데이터 소스**: `hw-list.txt`의 `*-cpu` 섹션

### GPU
| # | 모델 | PCI Bus ID | 메모리 | 시리얼 |
|---|------|------------|--------|--------|
| 0 | [nvidia-smi.txt에서 추출] | [Bus ID] | [메모리] | [gpu-serials.txt, 없으면 N/A] |

- **총 GPU 수**: N개
- **드라이버 버전**: [nvidia-smi.txt에서 추출]
- **CUDA 버전 (최대 지원)**: [nvidia-smi.txt에서 추출 — 드라이버가 지원하는 최대 버전. 실제 설치된 CUDA Toolkit 버전과 다를 수 있음]

**데이터 소스**: `nvidia-smi.txt`, `gpu-serials.txt`

### 메모리
| 항목 | 값 |
|------|-----|
| 총 용량 | [hw-list.txt에서 추출] |
| 슬롯 수 / 장착 수 | [hw-list.txt에서 확인 가능한 경우] |

**데이터 소스**: `hw-list.txt`의 `*-memory` 섹션

### 스토리지
| # | 장치명 | 종류 | 모델 | 용량 | 마운트 |
|---|--------|------|------|------|--------|
| 1 | [lsblk.txt에서 추출] | [NVMe/SATA/HDD/HW RAID] | [smartctl에서 모델명] | [용량] | [마운트포인트] |

- **NVMe SSD**: N개, 총 X TB
- **SATA SSD**: N개, 총 X TB
- **HDD**: N개, 총 X TB (있는 경우)
- **HW RAID 논리 디스크**: N개 (있는 경우)

**데이터 소스**: `drives-and-storage/lsblk.txt`, `smartctl-*.txt`

### InfiniBand
| 항목 | 값 |
|------|-----|
| 유무 | [있음 / 없음] |
| 모델 | [예: ConnectX-7, ConnectX-6] |
| 포트 수 | [ibstat.txt에서 추출, 없으면 N/A] |
| 상태 | [Active / Down / N/A] |
| 속도 | [예: 200 Gb/sec (4X HDR)] |

**데이터 소스 및 판별 순서**:
1. `ibstat.txt`를 Read한다
   - 정상 출력이면 → 포트 수, 상태, 속도를 추출하여 표에 기록
   - `"No InfiniBand data available"` 문자열이면 → ibstat 미설치 또는 IB HCA 없음. 아래 2단계로 fallback
2. `ibstat.txt`가 비어있거나 "No InfiniBand data available"이면:
   - `hw-list.txt`에서 `Mellanox` 또는 `ConnectX` Grep
   - `nvidia-bug-report.log`가 있으면 `Mellanox` / `ConnectX` Grep (lspci -vvv 섹션 포함)
   - 발견되면 → "있음 (ibstat 미설치 — lspci 기반 감지)" + 모델명 기록 (예: `ConnectX-7`, `ConnectX-6 Dx`)
   - 발견되지 않으면 → "없음"으로 기록

### PCIe Link Speed
| 장치 | 종류 | 기대 속도 (LnkCap) | 현재 속도 (LnkSta) | 상태 |
|------|------|--------------------|--------------------|------|
| [Bus ID] | [GPU/IB/NVMe] | [예: 16GT/s Gen4] | [예: 8GT/s Gen3] | [✅ OK / ⚠️ Downgraded] |

- LnkSta < LnkCap 항목이 있으면 → Warning 이슈로도 등록
- 장치 종류 구분: `NVIDIA`/`3D controller` → GPU, `Mellanox`/`InfiniBand` → IB, `Non-Volatile memory controller` → NVMe
- **데이터 소스**: `nvidia-bug-report.log` 내 `lspci -vvv` 출력 (Pass 2에서 `LnkSta`/`LnkCap` Grep)
- 파일 없으면: "nvidia-bug-report.log 없음 — PCIe Link Speed 확인 불가"로 기록

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

## ⏱ 시간 상관관계 분석

이 섹션은 서로 다른 소스에서 발견된 이벤트가 시간적으로 겹치는 경우를 기록한다.

### 분석 방법
1. Critical/Warning 이슈에서 타임스탬프를 추출할 수 있는 것들을 모은다
2. 같은 10분 윈도우 안에 2개 이상의 소스에서 이벤트가 발견되면 "상관 클러스터"로 묶는다
3. 클러스터 내 이벤트의 시간 순서를 기록하고, 가능하면 인과관계를 추론한다

### 주요 상관 패턴 (참고용)
- GPU ECC 에러 → OOM kill → 서비스 재시작: GPU 하드웨어 문제로 인한 연쇄 장애 가능성
- 디스크 I/O 에러 → 서비스 crash → 파일시스템 에러: 스토리지 장애 연쇄
- 온도 급등 → GPU/CPU 스로틀링 → 성능 저하: 냉각 문제
- 네트워크 링크 다운 → NFS/Lustre 에러 → 서비스 실패: 네트워크 스토리지 의존성 문제

### 클러스터 보고 형식

    ### 클러스터: [시간대] — [추정 원인 한 줄]
    | 시각 | 출처 파일 | 이벤트 |
    |------|-----------|--------|
    | 10:23:01 | dmesg-errors.txt | I/O error on sda |
    | 10:23:15 | journalctl.txt | systemd: mysql.service failed |
    | 10:23:18 | journalctl.txt | OOM kill: mysqld |

    **추정 인과관계**: 디스크 I/O 오류로 MySQL 서비스가 비정상 종료 후 OOM 발생

타임스탬프를 추출할 수 없는 이벤트는 이 분석에서 제외한다.
상관 클러스터가 없으면 "시간적으로 연관된 이벤트 클러스터가 발견되지 않았습니다"로 표기한다.

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
