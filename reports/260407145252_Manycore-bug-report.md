# Manycore 서버 진단 보고서

**분석 대상:** Manycore-bug-report
**분석 일시:** 2026-04-07 14:52
**호스트명:** DESKTOP-0SPT3D1
**시스템 업타임:** up 1 hour, 7 minutes since 2026-04-07 09:59:16

---

## 요약

| 심각도 | 건수 |
|--------|------|
| 🔴 Critical | 0 |
| 🟡 Warning | 1 |
| 🔵 Info | 4 |

Critical 이슈 없음. 본 시스템은 WSL2 (Windows Subsystem for Linux 2) 환경으로, dmesg 및 커널 로그에 나타나는 대부분의 오류는 WSL 특유의 노이즈다. 유일한 실질적 경고는 AMD CPU의 SRSO(Speculative Return Stack Overflow) 보안 취약점으로, 마이크로코드 미적용 상태다.

---

## 🔴 Critical 이슈

Critical 이슈 없음

---

## 🟡 Warning 이슈

### SRSO 보안 취약점 — 마이크로코드 미적용

- **발견 위치:** `system-logs/kern.log:173`, `system-logs/journalctl.txt:169-170`
- **내용:**
  ```
  Speculative Return Stack Overflow: IBPB-extending microcode not applied!
  Speculative Return Stack Overflow: WARNING: See https://kernel.org/doc/html/latest/admin-guide/hw-vuln/srso.html for mitigation options.
  Speculative Return Stack Overflow: Vulnerable: Safe RET, no microcode
  ```
- **의미:** AMD Ryzen 5 5600X(Zen 3)에서 발생하는 SRSO(CVE-2023-20569) 완화 조치가 마이크로코드 없이 "Safe RET" 방식으로만 적용되어 있음. 완전한 완화를 위해서는 AMD 마이크로코드 업데이트가 필요하나, WSL2 환경에서는 호스트 Windows가 CPU 마이크로코드를 제어하므로 WSL 내부에서 직접 조치 불가.
- **권장 조치:** 호스트 Windows 시스템의 BIOS/UEFI 또는 Windows Update를 통해 AMD 마이크로코드(AGESA 업데이트)를 최신으로 갱신한다.

---

## 🔵 Info

### 1. 최근 재부팅 — 진단 수집 시점 기준 1시간 7분 경과

- 업타임이 1시간 7분으로 비교적 최근에 재부팅됨. 분석 수집 직전 재부팅이 있었을 가능성 있음.

### 2. 진단 도구 당일 신규 설치

- `apt-history.log` 기준, 2026-04-07 당일 `smartmontools`, `ipmitool`, `lm-sensors`, `sysstat`, `openssh-server`, `net-tools` 가 설치됨.
- SMART, IPMI, 센서 결과가 "데이터 없음"으로 나오는 것과 연관될 수 있음 (설치 직후 미초기화).

### 3. GPU 미탑재 (또는 nvidia-smi 미설치)

- `nvidia-smi` 명령을 찾을 수 없어 GPU ECC 오류, 리매핑, nvidia-smi 정보 수집 불가.
  ```
  ./deepgadget-log-grabber.sh: line 492: nvidia-smi: command not found
  ```
- GPU가 실제로 없는 환경이거나, NVIDIA 드라이버가 설치되지 않은 경우.

### 4. WSL localhost 릴레이 오류 (포트 포워딩)

- **발견 위치:** `system-logs/journalctl.txt:4845`
- **내용:**
  ```
  Apr 06 18:17:49 DESKTOP-0SPT3D1 unknown: WSL (254 - ) ERROR: RunPortTracker:499: Failed to start the guest side of the localhost relay
  ```
- WSL과 Windows 호스트 간 localhost 포트 포워딩 릴레이 초기화 실패. WSL 네트워크 설정 또는 Windows 방화벽에 의해 간헐적으로 발생할 수 있음. 반복적으로 발생할 경우 `wsl --shutdown` 후 재시작으로 해결 가능.

---

## 분석 제외 항목

| 항목 | 사유 |
|------|------|
| SMART (sda, sdb, sdc, sdd) | Msft Virtual Disk — 가상 디스크, SMART 미지원 (`Terminate command early due to bad response to IEC mode page`) |
| GPU ECC / 리매핑 / nvidia-smi | nvidia-smi 명령 없음 — GPU 미탑재 또는 드라이버 미설치 |
| sensors.txt | `No sensor data available. This machine may not have sensors.` |
| IPMI (ipmi-elist.txt) | `No IPMI ELIST data available. This machine may not have IPMI.` |
| mdstat.txt | 파일 비어 있음 — RAID 배열 없음 |

---

## 환경 특이사항

본 시스템은 **WSL2 (Windows Subsystem for Linux 2)** 환경이다.

- **커널:** `6.6.87.2-microsoft-standard-WSL2`
- **하이퍼바이저:** Microsoft Hyper-V (Host Build 10.0.26100.8036)
- **CPU:** AMD Ryzen 5 5600X 6-Core Processor (12 vCPU 할당)
- **OS:** Ubuntu 22.04 LTS

아래 오류들은 모두 WSL2 환경 특유의 노이즈이며 실제 하드웨어 문제가 아니다.

| 오류 패턴 | 분류 |
|-----------|------|
| `PCI: Fatal: No config space access function found` | WSL2 PCI 미지원 — 정상 |
| `misc dxg: dxgk: dxgkio_*: Ioctl failed` (약 20회 반복) | WSL DirectX GPU 가상화 초기화 실패 — WSL 부팅 시 정상적으로 발생 |
| `WSL (*) ERROR: CheckConnection: getaddrinfo() failed: -5` | WSL 네트워크 초기화 중 일시적 DNS 실패 — 정상 |
| `networkd-dispatcher ERROR: Unknown state for interface (lo, eth0)` | WSL에서 networkd가 lo/eth0를 unmanaged로 보는 것 — 정상 |
| `containerd: skip loading plugin aufs/btrfs/devmapper/zfs` | WSL ext4 환경에서 해당 스냅샷터 미지원 — 정상 |
| `dockerd: CDI setup error /var/run/cdi, /etc/cdi` | CDI 디렉토리 미생성 — Docker 기본 설정에서 정상 |
| `Failed to register legacy timer interrupt` | Hyper-V 환경 — 정상 |
