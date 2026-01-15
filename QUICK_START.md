# 🚀 Quick Start Guide - 팀원용

**목표**: 5분 안에 플랫폼 이해하고 테스트하기

---

## 📌 이 프로젝트가 뭔가요?

**Engineer_GYM - 아키텍처 설계 자동채점 플랫폼**

```
학생 → Mermaid 다이어그램 + Tradeoff 작성
  ↓
시스템 → 자동채점 (3 Stage) + 그래프분석
  ↓
학생 ← 점수 + 대안 + 5개 질문 (자동생성)
```

---

## 🎯 핵심 3가지

### 1️⃣ **자동채점** (3 Stage)

| Stage | 담당 | 내용 |
|-------|------|------|
| Stage 1 | db_03 | 키워드 검색 → 점수 부여 |
| Stage 2 | db_03 | Tradeoff Cap 적용 (3개 미만이면 상한선) |
| Stage 3 | Python | SPOF/병목 탐지 → 감점 |

**예시**:
```
Raw 88점 + Tradeoff 2개
→ Cap 85점 적용
→ Final 85점
→ SPOF 1개 발견 (-12점 감점)
→ 최종 73점
```

### 2️⃣ **3개 시나리오**

| ID | 제목 | 핵심 | 규모 |
|----|------|------|------|
| SYS-RAG-ONPREM | 문서 검색 | 권한 + 근거 + 감사로그 | 사용자 2K, QPS 20 |
| SYS-ORDER-EVENT | 주문/결제 | 멱등성 + 정합성 | 사용자 500K, QPS 200 |
| SYS-REALTIME-NOTIFY | 실시간 채팅 | WebSocket + Fanout | 동시접속 50K |

### 3️⃣ **4개 문서**

| 문서 | 대상 | 읽는 시간 |
|------|------|----------|
| **README.md** | 모두 | 10분 |
| **SEED_SCENARIOS_DETAILED.md** | 팀원 | 15분 |
| **CODE_EXPLANATION.md** | 개발자 | 30분 |
| **이 파일** | 팀원 | 5분 |

---

## 🔧 환경 설정 (2분)

### 1. Python 패키지

```bash
pip install mysql-connector-python networkx python-dotenv
```

### 2. 환경변수

```bash
cp .env.example .env
```

편집기에서 `.env` 열기:
```ini
DB_HOST=localhost
DB_USER=root
DB_PASSWORD=YOUR_MYSQL_PASSWORD  # ← 여기만 수정
```

### 3. 테스트

```bash
# MySQL 연결 확인
mysql -u root -p -e "SELECT 1;"
```

---

## 🎮 3분 데모

### Step 1: 스키마 생성 (30초)

```bash
mysql -u root -p < db_01_schema.sql
```

출력:
```
mysql> CREATE DATABASE ...
mysql> CREATE TABLE ...
mysql> SHOW TABLES;
+-------------------+
| Tables_in_Engineer_GYM |
+-------------------+
| system_scenarios  |
| system_submissions|
| system_results    |
+-------------------+
```

### Step 2: 시나리오 로드 (30초)

```bash
mysql -u root -p Engineer_GYM < db_02_seed_scenarios.sql
```

확인:
```bash
mysql -u root -p Engineer_GYM -e "SELECT id, title FROM system_scenarios;"
```

출력:
```
+------------------+-------------------------------------------+
| id               | title                                     |
+------------------+-------------------------------------------+
| SYS-RAG-ONPREM-001         | 온프렘 사내 문서 검색 RAG 챗봇            |
| SYS-ORDER-EVENT-001        | 주문/결제 이벤트 처리                     |
| SYS-REALTIME-NOTIFY-001    | 실시간 알림/채팅                          |
+------------------+-------------------------------------------+
```

### Step 3: 자동채점 실행 (1분)

```bash
mysql -u root -p Engineer_GYM < db_03_demo_submission_result.sql
```

확인:
```bash
mysql -u root -p Engineer_GYM -e "SELECT score_total, risk_flags_json FROM system_results LIMIT 1;"
```

출력:
```
+-------------+----------------------------------------------------------------------+
| score_total | risk_flags_json                                                     |
+-------------+----------------------------------------------------------------------+
| 73          | ["INSUFFICIENT_TRADEOFFS", "SPOF_DETECTED", ...]                    |
+-------------+----------------------------------------------------------------------+
```

### Step 4: 그래프 분석 (1분)

```bash
python review_SPOF_bottleneck.py
```

출력:
```
✅ system_results 업데이트 완료
submission_id = 1
🔴 SPOF 후보: 1개 → 감점 -12점
🟠 병목 후보: 0개 → 감점 0점

💡 대안 아키텍처:
✓ [Retriever 이중화] 최소 2개 인스턴스로 구성...
✓ [Gateway 캐싱] Redis/Memcached로 캐싱...

❓ Follow-up 질문:
1. 'Retriever' 컴포넌트가 장애 시, 어떻게 전체 서비스를 보호할 건가요?
2. ...
```

---

## 🎓 3가지 핵심 개념

### 1️⃣ Tradeoff Cap (완전성 강제)

```
Tradeoff가 많을수록 좋다 (최소 3개)

Tradeoff 3개 이상 → 만점 100 가능 ✅
Tradeoff 2개     → 최대 85점 (불완전)
Tradeoff 1개     → 최대 70점 (부족)
Tradeoff 0개     → 최대 60점 (거의 없음)

예) 88점이지만 Tradeoff 2개만
→ Cap 85점 적용 → 최종 85점
```

### 2️⃣ SPOF (아키텍처 약점)

```
SPOF = Single Point of Failure
= 하나만 터지면 전체가 터진다!

      User
       ↓
    Gateway (이게 터지면?)
       ↓           → 모든 요청 못 함 = SPOF!
    API Service
       ↓
    Database

해결: 이중화 (Gateway 2개 이상)
```

### 3️⃣ 병목 (성능 약점)

```
병목 = Bottleneck
= 모든 요청이 몰리는 지점

  Service1 ──┐
  Service2 ──┼→ Database  ← 모든 쓰기가 여기로!
  Service3 ──┘

점수 = Centrality(중앙성) + Fan-in(들어오는 연결)

해결: 캐싱, 샤딩, 파티셔닝 등
```

---

## 📊 점수 계산 쉬운 예시

```
제출: Mermaid + "gateway, retriever, auditlog, p95 latency, error rate, trace id"
     + Tradeoff 2개

자동채점:
  기본:           10점
  ACL:            25점 (gateway, retriever 키워드)
  Audit:          20점 (auditlog 키워드)
  Observability:  25점 (p95, error, trace 3개 키워드)
  Failure Mode:   0점 (없음)
  Tradeoff:       8점 (2개)
  ─────────────────────
  Raw Total:      88점

Cap 적용:
  Tradeoff 2개 → Cap 85
  Final = MIN(88, 85) = 85점 ✅

그래프분석:
  SPOF: Retriever 발견 (-12점)
  ─────────────────────
  최종: 85 - 12 = 73점 🎯
```

---

## 🔍 주요 파일 읽는 순서

### 👶 초급 (5분)
```
1. 이 파일 읽기
2. db_01_schema.sql 훑어보기
3. db_02_seed_scenarios.sql 구조 이해하기
```

### 👨 중급 (15분)
```
1. README.md 읽기 (점수 계산까지)
2. SEED_SCENARIOS_DETAILED.md 읽기
3. db_03_demo_submission_result.sql 흐름 이해하기
```

### 👨‍💻 고급 (30분)
```
1. CODE_EXPLANATION.md 정독
2. review_SPOF_bottleneck.py 코드 리뷰
3. 각 알고리즘 (SPOF, 병목, 대안, 질문) 이해하기
```

---

## ⚠️ 주의사항

### DO ✅

- ✅ `.env` 파일에 DB 비밀번호 입력
- ✅ Tradeoff는 최소 3개 작성
- ✅ Mermaid에 `%% entry:`, `%% exit:`, `%% redundant:` 주석 추가
- ✅ 모든 요구사항을 Mermaid에 포함시키기

### DON'T ❌

- ❌ `.env` 파일을 Git에 커밋하지 마세요!
- ❌ Tradeoff 1~2개로는 높은 점수 받을 수 없음
- ❌ Mermaid 문법을 무시하면 파싱 실패
- ❌ 키워드를 빠뜨리면 자동채점에서 점수 못 받음

---

## 🆘 문제가 발생했을 때

### "DB 연결 실패"
```
→ .env 파일에서 DB_PASSWORD 확인
→ MySQL 서버가 실행 중인지 확인
  
확인 방법:
mysql -u root -p -e "SELECT 1;"
```

### "Python 패키지 없음"
```
→ pip install mysql-connector-python networkx python-dotenv
```

### "Mermaid 파싱 오류"
```
❌ 잘못된 예:
User -> API -> DB

✅ 올바른 예:
User[User] --> API[API] --> DB[(DB)]
```

### "점수가 예상과 다름"
```
1. score_breakdown_json 확인
2. Tradeoff 개수 확인 (Cap 적용됐나?)
3. graph_penalty 확인 (SPOF/병목 감점)
```

---

## 📞 팀원들이 자주 묻는 질문

### Q1. Tradeoff는 뭔가요?
```
A. 설계 선택의 "장점 vs 단점"

예: 
- "On-Prem LLM" (장점: 데이터 보안, 단점: 비용)
- "Cache 추가" (장점: 빠름, 단점: 불일치)
- "3개 필수!" ⚠️
```

### Q2. SPOF/병목이 뭔가요?
```
SPOF: 하나만 터져도 전체가 터진다
→ 이중화로 해결

병목: 모든 요청이 몰린다
→ 캐싱, 샤딩으로 해결
```

### Q3. 왜 자동으로 질문이 생기나요?
```
A. 대안과 질문이 함께 있어야 비로소 "피드백"이 됨
→ 따라서 SPOF/병목이 있는 설계에 대해
   자동으로 해결책 제시 + 심화 질문 생성
```

### Q4. 언제 Phase 2 나오나요?
```
A. Phase 1 완성 후 팀 평가 → Phase 2 시작
   예상: 2025년 1분기

Phase 2 계획:
- LLM 기반 AI Coach
- 실시간 스코어링
- 더 많은 시나리오
```

---

## 🎯 체크리스트 (팀 리뷰 전)

### 데이터 설정
- [ ] MySQL 설치됨
- [ ] db_01_schema.sql 실행 (테이블 생성)
- [ ] db_02_seed_scenarios.sql 실행 (시나리오 3개 로드)

### 자동채점 확인
- [ ] db_03_demo_submission_result.sql 실행
- [ ] system_results 조회 가능

### Python 분석 확인
- [ ] 패키지 설치 (mysql-connector, networkx, python-dotenv)
- [ ] .env 파일 작성
- [ ] review_SPOF_bottleneck.py 실행 성공

### 문서 확인
- [ ] README.md 읽음 (전체 흐름 이해)
- [ ] SEED_SCENARIOS_DETAILED.md 읽음 (시나리오 이해)
- [ ] CODE_EXPLANATION.md 훑어봄 (코드 구조 이해)

---

## 🚀 다음 스텝

### 1. 팀 온보딩 (1시간)
```
1. 이 가이드 함께 읽기 (15분)
2. 3분 데모 실행 (3분)
3. README.md로 깊이 있게 이해 (30분)
4. 질문 답변 (12분)
```

### 2. 첫 시나리오 풀어보기 (30분)
```
1. SYS-RAG-ONPREM-001 선택
2. Mermaid 그려보기 (15분)
3. Tradeoff 3개 작성 (10분)
4. 제출 및 자동채점 확인 (5분)
```

### 3. 피드백 받기 & 개선 (15분)
```
1. 점수 확인
2. Risk Flags 분석
3. 대안 아키텍처 학습
4. Follow-up 질문 답변해보기
```

---

## 📚 참고자료

| 자료 | 링크 | 설명 |
|------|------|------|
| 전체 가이드 | README.md | 모든 것이 담긴 완전 가이드 |
| 시나리오 분석 | SEED_SCENARIOS_DETAILED.md | 3개 시나리오 상세 설명 |
| 코드 해설 | CODE_EXPLANATION.md | 각 파일별 상세 코드 설명 |
| 빠른 시작 | 이 파일 | 5분 만에 이해하기 |

---

## 💬 피드백 & 개선 제안

이 프로젝트에 대한 피드백이 있으면:
1. GitHub Issues에 등록
2. 팀 Slack에서 논의
3. Pull Request로 개선안 제출

---

**🎓 Engineer_GYM - 아키텍처 설계 자동채점 플랫폼**

**Version**: v1.0 Phase 1 완료  
**Last Updated**: 2025-01-15  
**Status**: 팀원 리뷰 준비 완료 ✅

---

**5분 안에 이해했으면, 이제 README.md를 읽어보세요!**
