# Manycore 서버 진단 보고서

**분석 대상:** Manycore-bug-report
**분석 일시:** 2026-04-07 15:49
**호스트명:** DESKTOP-0SPT3D1
**시스템 업타임:** up 5 hours, 43 minutes since 2026-04-07 10:05:09

---

## 요약

| 심각도 | 건수 |
|--------|------|
| 🔴 Critical | 0 |
| 🟡 Warning | 1 |
| 🔵 Info | 4 |

WSL2(Windows Subsystem for Linux 2) 환경으로, 실제 하드웨어 장애는 발견되지 않았다.
CPU(AMD Ryzen 5 5600X)에서 SRSO 취약점 미완화 경고가 확인되나, VM/WSL2 환경에서는 호스트 OS가 마이크로코드를 관리하므로 실질적 위험은 낮다.
dmesg 및 journalctl에 나타나는 `dxg`, `PCI: Fatal`, `ACPI` 등의 오류는 WSL2 특성상 정상 노이즈이다.

---

## 🔴 Critical 이슈

Critical 이슈 없음

---

## 🟡 Warning 이슈

### CPU SRSO (Speculative Return Stack Overflow) 취약점 미완화
- **발견 위치:** `system-logs/kern.log:172-174`
- **내용:**
  ```
  Speculative Return Stack Overflow: IBPB-extending microcode not applied!
  Speculative Return Stack Overflow: WARNING: See https://kernel.org/doc/html/latest/admin-guide/hw-vuln/srso.html for mitigation options.
  Speculative Return Stack Overflow: Vulnerable: Safe RET, no microcode
  ```
- **의미:** AMD Ryzen 5 5600X CPU의 SRSO 취약점에 대한 완화 마이크로코드가 적용되지 않은 상태. `microcode=4294967295(0xFFFFFFFF)`는 VM/WSL2 환경에서 하이퍼바이저가 제공하는 가상 값으로, 호스트 Windows의 마이크로코드 업데이트 상태에 따라 실질적 위험이 결정된다.
- **권장 조치:** 호스트 Windows 시스템의 CPU 마이크로코드 및 보안 업데이트 적용 여부를 확인. 리눅스 Guest 내에서는 직접 마이크로코드를 적용할 수 없으므로, 호스트 OS 업데이트를 우선 검토한다.

---

## 🔵 Info

### 최근 설치된 주요 패키지 (2026-04-07)
당일 사용자(`deepgadget`)가 직접 또는 스크립트를 통해 다수 패키지를 설치함.

| 설치 시각 | 패키지 | 비고 |
|-----------|--------|------|
| 10:59 | `openssh-server` (8.9p1-3ubuntu0.14) | SSH 서버 신규 설치 |
| 10:59 | `net-tools` | ifconfig 등 네트워크 유틸리티 |
| 11:06 | `smartmontools` | 진단 도구 (log-grabber 사용) |
| 11:06 | `ipmitool` | 진단 도구 (log-grabber 사용) |
| 11:06 | `lm-sensors` | 진단 도구 (log-grabber 사용) |
| 11:06 | `sysstat` | 진단 도구 (log-grabber 사용) |
| 14:57 | `gh` (2.4.0) | GitHub CLI |

### WSL localhost relay 오류 (일시적)
- **발견 위치:** `system-logs/journalctl.txt:4843-4845`
- **내용:**
  ```
  Apr 06 18:17:49 WSL (254) ERROR: SendMessage:131: Failed to write message LxGnsMessagePortListenerRelayStop. Channel: localhost
  Apr 06 18:17:49 WSL (254) ERROR: RunPortTracker:499: Failed to start the guest side of the localhost relay
  ```
- **의미:** WSL2의 localhost 포트 포워딩 릴레이가 일시 중단됨. WSL 세션 종료 시 또는 네트워크 재구성 시 간헐적으로 발생하는 알려진 현상.

### Docker 및 컨테이너 런타임 운영 중
- containerd, docker.service가 정상 실행 중 (systemctl-services.txt 기준)
- Docker CDI 디렉터리(`/etc/cdi`, `/var/run/cdi`) 미설정 관련 경고는 CDI 미사용 시 정상

### Windows 호스트 드라이브 용량
- **발견 위치:** `drives-and-storage/df.txt`
- **내용:**
  ```
  drivers  9p   238G  178G  60G  75%  /usr/lib/wsl/drivers
  C:\      9p   238G  178G  60G  75%  /mnt/c
  ```
- **의미:** Windows 호스트 C: 드라이브가 238GiB 중 178GiB(75%) 사용 중. 현재 임계치(85%) 미만이나, WSL2 가상 디스크(`/dev/sdd`, 1TiB) 사용율은 1%로 여유 충분.

---

## 분석 제외 항목

| 항목 | 파일 | 결과 |
|------|------|------|
| SMART: sda | `drives-and-storage/smartctl-sda.txt` | Msft Virtual Disk (388MiB), SMART 미지원 — "Terminate command early due to bad response" |
| SMART: sdb | `drives-and-storage/smartctl-sdb.txt` | Msft Virtual Disk (186MiB), SMART 미지원 |
| SMART: sdc | `drives-and-storage/smartctl-sdc.txt` | Msft Virtual Disk (4GiB, swap), SMART 미지원 |
| SMART: sdd | `drives-and-storage/smartctl-sdd.txt` | Msft Virtual Disk (1TiB, root), SMART 미지원 |
| GPU ECC (uncorrected) | `gpu-memory-errors/uncorrected-ecc_errors.txt` | `nvidia-smi: command not found` — NVIDIA GPU 없음 |
| GPU ECC (corrected) | `gpu-memory-errors/ecc-errors.txt` | `nvidia-smi: command not found` |
| GPU 리매핑 | `gpu-memory-errors/remapped-memory.txt` | `nvidia-smi: command not found` |
| nvidia-smi | `nvidia-smi.txt` | `nvidia-smi: command not found` |
| IPMI 이벤트 | `bmc-info/ipmi-elist.txt` | "No IPMI ELIST data available. This machine may not have IPMI." |
| 온도/팬 센서 | `sensors.txt` | "No sensor data available. This machine may not have sensors." |
| RAID 상태 | `drives-and-storage/mdstat.txt` | 데이터 없음 — RAID 없음 |

---

## 환경 특이사항

이 머신은 **WSL2 (Windows Subsystem for Linux 2)** 환경이다.

- **커널:** `6.6.87.2-microsoft-standard-WSL2`
- **호스트:** DESKTOP-0SPT3D1 (Windows)
- **CPU:** AMD Ryzen 5 5600X 6-Core (하이퍼바이저 환경 내 노출)
- **RAM:** 16GiB (WSL2 할당 분)
- **스토리지:** 모두 Microsoft Virtual Disk (SCSI 가상 디스크)
- **GPU:** dxgkrnl 드라이버 탑재(Microsoft Corporation 3D controller)이나 nvidia-smi 없음 — NVIDIA CUDA GPU는 없거나 드라이버 미설치 상태

### WSL2 환경 노이즈 목록 (정상 오류)

아래 오류들은 WSL2 특성으로 인해 매 부팅 시 발생하며, 실제 장애와 무관하다:

- `PCI: Fatal: No config space access function found` — WSL2의 가상 PCI 구현 한계
- `misc dxg: dxgkio_*: Ioctl failed` — WSL2 GPU 가상화 초기화 과정 (20+회 반복)
- `Failed to register legacy timer interrupt` — WSL2 타이머 가상화
- `ACPI: _OSC evaluation for CPUs failed, trying _PDC` — WSL2 ACPI 미지원
- `Failed to connect to bus: No such file or directory` — WSL2 부팅 초기 D-Bus 미준비 상태
- `snap auto-import --mount=/dev/sd* failed with exit code 1` — WSL2에서 snap 자동 임포트 불가 (정상)
- `dbus-org.freedesktop.network1.service not found` — systemd-networkd 미사용 환경
- `WSL (*) ERROR: CheckConnection: getaddrinfo() failed` — WSL2 네트워크 초기화 중 일시 오류
- `containerd: skip loading plugin ... aufs/btrfs/devmapper/zfs` — 해당 파일시스템 미지원 환경에서 정상 스킵
- `Failed unmounting /init` — WSL2 종료 시퀀스의 정상 동작
