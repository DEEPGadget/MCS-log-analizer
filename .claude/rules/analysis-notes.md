## 분석 시 주의사항

1. **환경 감지 및 노이즈 구분**:
   분석 시작 전에 다음 방법으로 환경을 판별하고, 환경별 노이즈를 Critical/Warning에서 제외한다:

   **환경 판별**: `_env-hints.txt`의 `ENV_TYPE` 값을 사용한다.
   파일이 없는 경우에만 아래 수동 판별을 수행:
   - `deepgadget-log-grabber`로 수집된 아카이브는 **거의 항상 베어메탈**이다.
     가상화 증거가 명확히 발견되지 않으면 베어메탈로 간주하고 VM 노이즈 필터는 적용하지 않는다.
   - `dmesg-errors.txt` 또는 `kern.log`에서 커널 버전 확인:
     - `microsoft-standard-WSL2` → WSL
   - VM 판별 시 **게스트 전용 지표**만 사용:
     - DMI 정보에 가상 하드웨어 제조사 (`QEMU Virtual`, `VMware Virtual`, `VirtualBox` 등)
     - Xen: `Xen HVM` 문자열
     - ⚠ `kvm_amd`, `kvm_intel`, `KVM` 단어 자체는 베어메탈 KVM 호스트에서도 나타나므로 VM 판정 근거로 사용하지 않는다
   - `hw-list.txt`의 product/manufacturer 필드에서 가상 하드웨어 벤더 확인
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
2. **중복 제거**: 같은 패턴이 반복되면 "N회 반복" 으로 집약하여 기록
3. **근거 제시**: 모든 이슈에 실제 로그 내용을 인용
4. **없는 파일**: 파일이 아카이브에 없으면 해당 항목은 "파일 없음" 으로 처리
5. **아카이브 구조**: 루트 디렉터리 이름은 아카이브마다 다를 수 있음 (예: `Manycore-bug-report/`, `customer-abc/`)
