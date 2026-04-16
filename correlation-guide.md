# 시간 상관관계 분석 가이드

보고서의 `⏱ 시간 상관관계 분석` 섹션 작성 방법.
출력 형식은 `report-template.md`의 해당 섹션을 참조한다.

## 분석 방법

1. Critical/Warning 이슈에서 타임스탬프를 추출할 수 있는 것들을 모은다
2. 같은 10분 윈도우 안에 2개 이상의 소스에서 이벤트가 발견되면 "이벤트 묶음"으로 구성한다
3. **이벤트 묶음 구성 시 반드시 여러 소스를 교차 확인한다** (Pass 1에서 읽은 전처리 파일 내에서 대조):
   - `journalctl-errors.txt` / `journalctl-lifecycle.txt`에서 이벤트를 발견했으면, 같은 시각을 `dmesg-crash-context.txt`, `dmesg-full-errors.txt`, `ipmi-elist.txt`에서도 확인
   - 커널 Oops/BUG가 발견됐으면 `dmesg-crash-context.txt`에서 스택 트레이스 및 추가 컨텍스트 확인
   - `ipmi-elist.txt`에서 이벤트를 발견했으면 해당 시각의 `journalctl-errors.txt`, `dmesg-full-errors.txt`에서 시스템 측 반응 확인
   - 단일 소스만으로 구성된 이벤트 묶음은 작성하지 않는다 — 교차 확인 후 다른 소스에서 관련 이벤트가 없으면 해당 이슈는 Critical/Warning 섹션에만 기록하고 이 섹션에서는 제외
4. 이벤트 묶음 내 이벤트의 시간 순서를 기록하고, 가능하면 인과관계를 추론한다

## 주요 상관 패턴 (참고용)

- GPU ECC 에러 → OOM kill → 서비스 재시작: GPU 하드웨어 문제로 인한 연쇄 장애 가능성
- 디스크 I/O 에러 → 서비스 crash → 파일시스템 에러: 스토리지 장애 연쇄
- 온도 급등 → GPU/CPU 스로틀링 → 성능 저하: 냉각 문제
- 네트워크 링크 다운 → NFS/Lustre 에러 → 서비스 실패: 네트워크 스토리지 의존성 문제

## 주의

- 타임스탬프를 추출할 수 없는 이벤트는 이 분석에서 제외한다
- 이벤트 묶음이 없으면 "시간적으로 연관된 이벤트 묶음이 발견되지 않았습니다"로 표기한다
