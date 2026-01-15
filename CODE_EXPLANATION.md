# 📚 Engineer_GYM System Practice 전체 코드 설명

**목표**: 아키텍처 설계 문제 → 자동 채점 → 그래프 분석 → 피드백 제공

---

## 🗺️ 전체 흐름도

```
┌─────────────────────────────────────────────────────────────────────┐
│                    ENGINEER_GYM SYSTEM PRACTICE                      │
│                         (자동 채점 + 분석)                           │
└─────────────────────────────────────────────────────────────────────┘

    📊 DB 설계 (db_01)
         ↓
    🌱 시나리오 Seed (db_02)
         ↓
    👤 사용자 제출 → 자동 채점 (db_03)
         ↓
    🔴 SPOF/병목 탐지 + 대안 + 질문 (Python)
         ↓
    ✅ 최종 피드백 (system_results)
```

---

## 1️⃣ **db_01_schema.sql** - 데이터 구조 정의

### 핵심: 3개 테이블의 관계

```sql
system_scenarios (시나리오/문제)
    ↓ 1:N
system_submissions (사용자 제출)
    ↓ 1:1
system_results (자동채점 결과 + 분석)
```

### 테이블 상세

#### **system_scenarios** (문제 테이블)
```sql
CREATE TABLE system_scenarios (
  id VARCHAR(64) PRIMARY KEY,           -- 'SYS-RAG-ONPREM-001'
  track VARCHAR(32),                    -- 'system_practice'
  title VARCHAR(255),                   -- '온프렘 사내 문서 검색 RAG 챗봇'
  difficulty VARCHAR(16),               -- 'medium' / 'hard'
  tags JSON,                            -- ["RAG", "On-Prem", "ACL", "Observability"]
  
  -- 📝 시나리오 상세 정보 (JSON)
  context_json,                         -- {background, goal, environment}
  requirements_json,                    -- ["요구사항1", "요구사항2", ...]
  constraints_json,                     -- ["제약1", "제약2", ...]
  traffic_json,                         -- {users_total, qps_peak, sla_p95_latency_ms}
  
  -- 📋 채점 기준
  submission_format_json,               -- {required_artifacts, submit_fields}
  checklist_template_json,              -- {scoring.weights, items}
  admin_notes_json,                     -- 채점자용 가이드
  
  created_at TIMESTAMP
);

📌 인덱스:
- idx_system_scenarios_track           → 트랙별 조회 빠름
- idx_system_scenarios_difficulty      → 난이도별 필터링 빠름
```

**용도**:
- 학생이 문제를 읽을 때 조회
- 채점 기준으로 사용

**예시 데이터**:
```json
{
  "id": "SYS-RAG-ONPREM-001",
  "title": "온프렘 사내 문서 검색 RAG 챗봇",
  "difficulty": "medium",
  "context_json": {
    "background": "사내 문서가 온프렘 저장소에 분산...",
    "goal": "권한 규칙을 준수하면서도 의미론적 검색을...",
    "environment": "온프렘 환경. 외부 네트워크 접근 제약..."
  },
  "requirements_json": ["근거 첨부", "ACL 준수", "감사로그 저장"],
  "traffic_json": {
    "users_total": 2000,
    "qps_peak": 20,
    "sla_p95_latency_ms": 2500
  }
}
```

---

#### **system_submissions** (제출 테이블)
```sql
CREATE TABLE system_submissions (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  scenario_id VARCHAR(64),                      -- FK → system_scenarios
  user_id VARCHAR(64),                          -- 'user-001'
  
  -- 📐 사용자가 제출한 내용
  mermaid_text LONGTEXT,                        -- "graph TD; U[User]-->G[...]"
  components_text TEXT,                         -- "Gateway는 인증을..."
  tradeoffs_json JSON,                          -- [{"topic":"ACL", "pros":"...", "cons":"..."}]
  submission_payload_json JSON,                 -- {failure_mode, observability, ...}
  
  status VARCHAR(16) DEFAULT 'submitted',       -- 'submitted' / 'scored' / 'reviewed'
  created_at TIMESTAMP
);

📌 인덱스:
- idx_system_submissions_scenario_id   → 문제별 제출 조회
- idx_system_submissions_status         → 상태별 필터링
- idx_system_submissions_created_at     → 최신순 정렬
```

**용도**:
- 사용자 제출 저장
- 채점 스크립트가 읽음

**예시 데이터**:
```json
{
  "id": 1,
  "scenario_id": "SYS-RAG-ONPREM-001",
  "user_id": "user-001",
  "mermaid_text": "graph TD; U[User]-->G[Gateway]; G-->R[Retriever];",
  "tradeoffs_json": [
    {
      "topic": "ACL",
      "pros": "권한 유출 방지",
      "cons": "복잡도 증가"
    },
    {
      "topic": "Cache",
      "pros": "지연 감소/비용 절감",
      "cons": "불일치 위험"
    }
  ]
}
```

---

#### **system_results** (결과 테이블)
```sql
CREATE TABLE system_results (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  submission_id BIGINT UNIQUE,                  -- FK → system_submissions
  
  -- 📊 점수
  score_total INT,                              -- 85 (최종 점수)
  score_breakdown_json JSON,                    -- {meta, items} 상세 채점
  risk_flags_json JSON,                         -- ["SPOF_DETECTED", "INSUFFICIENT_TRADEOFFS"]
  
  -- 💡 피드백 (v3 신기능)
  alternative_mermaid_text LONGTEXT,            -- 대안 아키텍처 제시
  questions_json JSON,                          -- [질문1, 질문2, ...]
  coach_summary TEXT,                           -- 종합 피드백
  
  created_at TIMESTAMP
);

📌 제약:
- submission_id는 UNIQUE          → 1개 제출 = 1개 결과
- ON DELETE CASCADE              → 제출 삭제 시 결과도 삭제
```

**용도**:
- 채점 결과 저장
- 사용자 피드백 제공

**예시 데이터**:
```json
{
  "id": 1,
  "submission_id": 1,
  "score_total": 73,  // 85 - 12(SPOF 감점) = 73
  "score_breakdown_json": {
    "meta": {
      "raw_total": 85,
      "cap_by_tradeoffs": 85,
      "graph_penalty": {
        "spof_count": 1,
        "spof_penalty": 12,
        "bottleneck_count": 0,
        "bottleneck_penalty": 0,
        "total_penalty": 12
      }
    },
    "items": {
      "tradeoffs": {"score": 8, "status": "PARTIAL"},
      "acl": {"score": 25, "status": "OK"},
      "observability": {"score": 25, "status": "OK"},
      "graph_analysis": {
        "spof_candidates": ["Retriever"],
        "bottleneck_candidates": []
      }
    }
  },
  "risk_flags_json": ["SPOF_DETECTED", "INSUFFICIENT_TRADEOFFS"],
  "alternative_mermaid_text": "✓ [Retriever 이중화] 최소 2개 인스턴스로...",
  "questions_json": ["질문1", "질문2", ...]
}
```

---

## 2️⃣ **db_02_seed_scenarios.sql** - 3개 시나리오 데이터

### 목적
3개의 실전 시나리오를 미리 만들어서 학생들이 선택할 수 있도록 함

### 시나리오 1: SYS-RAG-ONPREM-001 (중급)

```sql
INSERT INTO system_scenarios (
  id, track, title, difficulty,
  context_json,              -- 배경 설정
  requirements_json,         -- 해야 할 것들 (필수 구현)
  constraints_json,          -- 제약사항 (어려움)
  traffic_json,              -- 트래픽 + SLA 스펙
  submission_format_json,    -- 뭘 제출해야 하는지
  checklist_template_json,   -- 점수표
  admin_notes_json           -- 채점 팁
) VALUES (
  'SYS-RAG-ONPREM-001',
  'system_practice',
  '온프렘 사내 문서 검색 RAG 챗봇(권한/근거/감사로그)',
  'medium',
  
  -- 🎯 시나리오 배경
  JSON_OBJECT(
    'background',
      '사내 문서(정책/가이드/코드)가 온프렘 저장소에 분산되어 있습니다. '
      '직원들이 RAG 챗봇으로 검색하기를 원하지만, 권한별로 접근 범위가 달라야 합니다.',
    'goal',
      '권한 규칙(ACL)을 준수하면서도 의미론적 검색(Semantic Search)을 '
      '지원하는 RAG 아키텍처를 설계합니다.',
    'environment',
      '온프렘(On-Premise) 환경. 외부 네트워크 접근 제약. '
      'LLM은 내부 LLMOps 또는 오픈소스 모델(Llama 등) 사용.'
  ),
  
  -- ✅ 필수 요구사항
  JSON_ARRAY(
    '근거 첨부 (Retrieval Augmented Generation)',
    'ACL 준수 (사용자별 접근 범위 제어)',
    '감사로그 저장 (누가 뭘 조회했는지 기록)'
  ),
  
  -- ⚠️ 제약 (어려움)
  JSON_ARRAY(
    '온프렘/에어갭 환경에서 작동 (외부 LLM API 호출 불가)',
    '민감정보 처리 (PII/소스코드 탈취 방지)',
    '문서/사용자별 ACL 규칙이 다양 (부서/직급별)',
    'SLA 존재 (p95 지연, 가용성)',
    '벡터DB 및 임베딩 모델 선택 트레이드오프'
  ),
  
  -- 📊 트래픽 + SLA
  JSON_OBJECT(
    'users_total', 2000,
    'qps_peak', 20,
    'sla_p95_latency_ms', 2500
  ),
  
  -- 📋 제출 포맷
  JSON_OBJECT(
    'required_artifacts', JSON_ARRAY(
      'Mermaid 다이어그램',
      'Tradeoff 3개',
      'Failure Mode',
      'Observability'
    )
  ),
  
  -- 🎓 점수표 (가중치)
  JSON_OBJECT(
    'scoring', JSON_OBJECT(
      'weights', JSON_OBJECT(
        'security_acl', 25,      -- ACL이 얼마나 잘 설계됐나
        'audit_log', 20,         -- 감사로그가 충분한가
        'observability', 20,     -- 모니터링 전략이 있는가
        'failure_mode', 15,      -- 장애 시 대응이 있는가
        'tradeoff', 20           -- Tradeoff가 충분한가
      )
    )
  ),
  
  -- 💡 채점자 가이드
  JSON_OBJECT(
    'recommended_min_components', JSON_ARRAY(
      'API Gateway (인증/레이트리밋)',
      'Retriever (ACL 필터링)',
      'Vector DB (의미론적 검색)',
      'LLM (프롬프트)',
      'Audit Log Storage',
      'Observability Stack'
    ),
    'admin_notes', JSON_ARRAY(
      'Mermaid에 "Fallback" 표기가 있으면 failure_mode 가산점',
      'Prompt injection 방어 언급 시 security 가산점',
      'Trace ID 전파(게이트웨이→서비스→DB) 언급 시 observability 가산점'
    )
  )
);
```

**학생이 읽는 순서**:
```
1. context_json.background → "아 사내 문서를 RAG로 검색하는 거구나"
2. context_json.goal → "권한을 지키면서 검색해야 하는군"
3. requirements_json → "근거, ACL, 감사로그 3가지는 필수!"
4. constraints_json → "온프렘이라 외부 API 못 쓰네..."
5. traffic_json → "2000명, QPS 20, P95 2.5초"
6. checklist_template_json.weights → "ACL이 제일 중요하네(25점)"
```

### 시나리오 2: SYS-ORDER-EVENT-001 (어려움)

**핵심 이슈**:
- 중복 결제 방지 (Idempotency)
- 이벤트 일관성 (Outbox 패턴)
- 실패 격리 (DLQ)
- 감사로그

### 시나리오 3: SYS-REALTIME-NOTIFY-001 (중급)

**핵심 이슈**:
- WebSocket 팬아웃
- 메시지 유실 방지
- 백프레셔 처리
- SPOF 최소화

---

## 3️⃣ **db_03_demo_submission_result.sql** - 자동채점 엔진

### 목적
사용자 제출을 받아서 **룰 기반으로 자동 채점**

### 동작 흐름

```
Step 1: 제출 INSERT
    └─ system_submissions에 사용자 Mermaid, Tradeoff, 설명 저장

Step 2: 변수 수집
    ├─ @mermaid := mermaid_text (소문자)
    ├─ @comp := components_text (소문자)
    ├─ @payload := submission_payload_json
    └─ @tradeoffs := tradeoffs_json

Step 3: 룰 기반 채점
    ├─ ACL 키워드 검색 (REGEXP 'acl|auth|role|permission')
    │   └─ 있으면 +25점, 없으면 0점
    ├─ Audit 키워드 검색 (REGEXP 'audit|log')
    │   └─ 있으면 +20점, 없으면 0점
    ├─ Observability 키워드 검색 (REGEXP 'p95|error|trace|metric|alert')
    │   └─ 3개 이상 +25점, 1~2개 +10점, 없으면 0점
    ├─ Failure Mode 키워드 검색 (REGEXP 'down|fail|fallback|degrad')
    │   └─ 있으면 +20점, 없으면 0점
    └─ Tradeoff 개수에 따른 점수
        ├─ 3개 이상: 15점
        ├─ 2개: 8점
        ├─ 1개: 3점
        └─ 0개: 0점

Step 4: 상한선(Cap) 적용 ✨
    ├─ Raw Total = 기본(10) + 각 항목 점수
    ├─ Tradeoff 개수로 Cap 결정
    │   ├─ 3개 이상: Cap 100
    │   ├─ 2개: Cap 85 ← ⚠️ 핵심!
    │   ├─ 1개: Cap 70
    │   └─ 0개: Cap 60
    └─ Final Score = MIN(Raw Total, Cap)

Step 5: Risk Flags 생성
    ├─ Tradeoff < 3개 → "INSUFFICIENT_TRADEOFFS"
    ├─ Observability 점수 = 0 → "NO_OBSERVABILITY"
    ├─ Failure Mode 점수 = 0 → "NO_FAILURE_MODE"
    └─ Raw > Cap → "CAP_APPLIED_BY_TRADEOFFS"

Step 6: 결과 저장
    └─ system_results에 점수, 상세 분석, 플래그 저장
```

### 코드 상세

```sql
-- (1) 제출 INSERT
INSERT INTO system_submissions (
  scenario_id, user_id, mermaid_text, components_text,
  tradeoffs_json, submission_payload_json, status
) VALUES (
  'SYS-RAG-ONPREM-001',
  'user-001',
  'graph TD; U[User]-->G[Gateway]; G-->R[Retriever]; ...',
  'Gateway는 인증/레이트리밋을 담당하고...',
  JSON_ARRAY(
    JSON_OBJECT('topic','ACL', 'pros','권한 유출 방지', 'cons','복잡도 증가'),
    JSON_OBJECT('topic','Cache', 'pros','지연 감소', 'cons','불일치 위험')
  ),  -- 일부러 2개만 넣어서 cap 85 적용 테스트
  JSON_OBJECT(
    'failure_mode','VectorDB 장애 시 fallback',
    'observability','p95 latency, error rate, trace id'
  ),
  'submitted'
);

-- (2) 마지막 제출 ID 가져오기
SET @sid := (SELECT id FROM system_submissions ORDER BY id DESC LIMIT 1);

-- (3) 키워드 매칭으로 점수 계산
SET @mermaid := LOWER((SELECT mermaid_text FROM system_submissions WHERE id=@sid));
SET @comp := LOWER((SELECT components_text FROM system_submissions WHERE id=@sid));
SET @payload := (SELECT submission_payload_json FROM system_submissions WHERE id=@sid);

-- Tradeoff 개수
SET @tradeoff_cnt := IFNULL(JSON_LENGTH(
  (SELECT tradeoffs_json FROM system_submissions WHERE id=@sid)
), 0);

-- Tradeoff 점수
SET @score_tradeoffs :=
  CASE
    WHEN @tradeoff_cnt >= 3 THEN 15
    WHEN @tradeoff_cnt = 2 THEN 8
    WHEN @tradeoff_cnt = 1 THEN 3
    ELSE 0
  END;

-- ACL 점수 (REGEXP로 정규식 매칭)
SET @score_acl :=
  IF(@mermaid REGEXP 'acl|auth|role|permission' 
     OR @comp REGEXP 'acl|auth|role|permission', 25, 0);

-- Audit 점수
SET @score_audit :=
  IF(@mermaid REGEXP 'audit|log' 
     OR @comp REGEXP 'audit|log', 20, 0);

-- Observability 점수 (여러 키워드 합산)
SET @obs_text := LOWER(JSON_UNQUOTE(JSON_EXTRACT(@payload, '$.observability')));
SET @obs_hits :=
  (CASE WHEN @obs_text REGEXP 'p95|latency' THEN 1 ELSE 0 END) +
  (CASE WHEN @obs_text REGEXP 'error' THEN 1 ELSE 0 END) +
  (CASE WHEN @obs_text REGEXP 'trace' THEN 1 ELSE 0 END) +
  (CASE WHEN @obs_text REGEXP 'metric|prometheus|grafana' THEN 1 ELSE 0 END) +
  (CASE WHEN @obs_text REGEXP 'alert' THEN 1 ELSE 0 END);
SET @score_obs :=
  CASE
    WHEN @obs_hits >= 2 THEN 25
    WHEN @obs_hits = 1 THEN 10
    ELSE 0
  END;

-- Failure Mode 점수
SET @fm_text := LOWER(JSON_UNQUOTE(JSON_EXTRACT(@payload, '$.failure_mode')));
SET @score_fm := IF(@fm_text REGEXP 'down|fail|fallback|degrad|장애', 20, 0);

-- (4) 상한선 적용 ⚠️
SET @raw_total := 10 + @score_acl + @score_audit + @score_obs + @score_fm + @score_tradeoffs;

SET @cap :=
  CASE
    WHEN @tradeoff_cnt >= 3 THEN 100  -- 3개 이상: 만점 가능
    WHEN @tradeoff_cnt = 2 THEN 85    -- 2개: 85점 상한
    WHEN @tradeoff_cnt = 1 THEN 70    -- 1개: 70점 상한
    ELSE 60                            -- 0개: 60점 상한
  END;

SET @score_total := LEAST(@cap, LEAST(100, @raw_total));

-- (5) Risk Flags 생성
SET @risk_flags := JSON_ARRAY();
SET @risk_flags := IF(@tradeoff_cnt < 3, 
  JSON_ARRAY_APPEND(@risk_flags, '$', 'INSUFFICIENT_TRADEOFFS'), 
  @risk_flags);
SET @risk_flags := IF(@score_obs = 0, 
  JSON_ARRAY_APPEND(@risk_flags, '$', 'NO_OBSERVABILITY'), 
  @risk_flags);
SET @risk_flags := IF(@raw_total > @cap, 
  JSON_ARRAY_APPEND(@risk_flags, '$', 'CAP_APPLIED_BY_TRADEOFFS'), 
  @risk_flags);

-- (6) 결과 저장
INSERT INTO system_results (
  submission_id, score_total, score_breakdown_json, risk_flags_json,
  questions_json, coach_summary
) VALUES (
  @sid,
  @score_total,
  JSON_OBJECT(
    'meta', JSON_OBJECT(
      'raw_total', @raw_total,
      'cap_by_tradeoffs', @cap
    ),
    'items', JSON_OBJECT(
      'tradeoffs', JSON_OBJECT('score', @score_tradeoffs, 'max', 15, 'count', @tradeoff_cnt),
      'acl', JSON_OBJECT('score', @score_acl, 'max', 25),
      'audit_log', JSON_OBJECT('score', @score_audit, 'max', 20),
      'observability', JSON_OBJECT('score', @score_obs, 'max', 25),
      'failure_mode', JSON_OBJECT('score', @score_fm, 'max', 20)
    )
  ),
  @risk_flags,
  JSON_ARRAY(
    '트레이드오프 3가지를 각각 "장점/단점/대안" 형태로 설명할 수 있나요?',
    'ACL 검증은 어디에서 적용되나요?',
    '장애 시 어떤 기능을 우선 유지하나요?'
  ),
  CONCAT(
    '총점: ', @score_total,
    ' (raw=', @raw_total, ', cap=', @cap, '). ',
    'tradeoffs=', @tradeoff_cnt,
    ' → tradeoffs가 3개 미만이면 만점 상한(cap)을 적용하는 MVP 룰입니다.'
  )
);
```

### 예시 계산

```
Mermaid:      "graph TD; ... acl ... audit ... observability ..."
Components:   "Gateway는 권한을... Audit Log는..."
Tradeoff:     2개 (ACL, Cache)
Observability: "p95 latency, error rate, trace id" → 3개 키워드 ✅

계산:
  기본: 10점
  ACL: 25점 (✅ 'acl' 키워드 찾음)
  Audit: 20점 (✅ 'audit' 키워드 찾음)
  Observability: 25점 (✅ 3개 이상 키워드)
  Failure Mode: 0점 (❌ 키워드 없음)
  Tradeoff: 8점 (2개이므로)
  
  Raw Total = 10 + 25 + 20 + 25 + 0 + 8 = 88점
  
  Cap = 85 (Tradeoff 2개)
  
  Final Score = MIN(88, 85) = 85점 ← ⚠️ Cap 적용됨!
  
  Risk Flags:
    - "INSUFFICIENT_TRADEOFFS" (2개 < 3개)
    - "CAP_APPLIED_BY_TRADEOFFS" (88 > 85)
```

---

## 4️⃣ **review_SPOF_bottleneck.py** - 그래프 분석 + 피드백 생성

### 목적
Mermaid 다이어그램을 그래프로 변환하여 **SPOF/병목 탐지** → **대안 제시** → **질문 생성**

### 전체 흐름

```python
# 1️⃣ 환경설정 & DB 연결
load_dotenv()                           # .env 파일 로드
conn = get_db_connection()              # MySQL 연결

# 2️⃣ 최근 제출 가져오기
sub = conn.query("SELECT ... FROM system_submissions ORDER BY id DESC LIMIT 1")
mermaid_text = sub["mermaid_text"]

# 3️⃣ Mermaid 파싱
redundant, entry_hint, exit_hint = parse_annotations(mermaid_text)
edges, labels = parse_mermaid_edges_and_labels(mermaid_text)
# 결과: edges = [(User, Gateway), (Gateway, API), ...], labels = {User: "사용자", Gateway: "게이트웨이"}

# 4️⃣ NetworkX 그래프 생성
G = nx.DiGraph()
G.add_edges_from(edges)

# 5️⃣ Entry/Exit 결정
entry, exits = choose_entry_exit(G, labels, entry_hint, exit_hint)
# 예: entry="User", exits=["DB"]

# 6️⃣ Core 서브그래프 추출 (노이즈 제거)
core = core_subgraph_nodes(G, entry, exits)

# 7️⃣ SPOF 탐지 ⚠️
spofs = compute_spof(G, entry, exits, core, redundant)
# 알고리즘: articulation_points (단절점) 찾기

# 8️⃣ 병목 탐지
bottlenecks = compute_bottlenecks(G, core, labels, topk=3)
# 알고리즘: betweenness_centrality + fan-in/out

# 9️⃣ 대안 아키텍처 생성 ✨
alternative_arch = generate_alternative_architecture(spofs, bottlenecks, labels, G)

# 🔟 동적 질문 생성 ✨
questions = generate_followup_questions(sub, graph_analysis, penalty_info)

# 1️⃣1️⃣ 감점 계산
penalty_info = calc_penalties(spofs, bottlenecks)
# spof_penalty = len(spofs) * 12 (최대 36)
# bottleneck_penalty = len(bottlenecks) * 6 (최대 18)

# 1️⃣2️⃣ system_results 업데이트
update_system_results(conn, submission_id, graph_analysis, penalty_info, alternative_arch, questions)
```

### 핵심 알고리즘

#### **1️⃣ Mermaid 파싱**

```python
def parse_mermaid_edges_and_labels(mermaid_text):
    """
    입력:
      graph TD
        User[사용자] --> Gateway[게이트웨이]
        Gateway --> API[API 서비스]
        API --> DB[(데이터베이스)]
        Gateway --> Cache[캐시]
    
    출력:
      edges = [(User, Gateway), (Gateway, API), (API, DB), (Gateway, Cache)]
      labels = {
        'User': '사용자',
        'Gateway': '게이트웨이',
        'API': 'API 서비스',
        'DB': '데이터베이스',
        'Cache': '캐시'
      }
    """
    
    # 정규식으로 라벨 추출
    LABEL_DEF_RE = re.compile(r"([A-Za-z0-9_]+)\s*(\[[^\]]*\]|\([^\)]*\)|\{[^\}]*\})")
    for m in LABEL_DEF_RE.finditer(mermaid_text):
        node_id = m.group(1)              # "User"
        raw_label = m.group(2).strip("[](){}") # "사용자"
        labels[node_id] = raw_label
    
    # 정규식으로 엣지 추출
    EDGE_LINE_RE = re.compile(r"^\s*([A-Za-z0-9_]+).*[-.]*>\s*(?:\|[^|]*\|\s*)?([A-Za-z0-9_]+)")
    for raw in mermaid_text.splitlines():
        m = EDGE_LINE_RE.match(raw)
        if m:
            a, b = m.group(1), m.group(2)  # "User", "Gateway"
            edges.append((a, b))
```

#### **2️⃣ SPOF 탐지 (단절점 알고리즘)**

```python
def compute_spof(G, entry, exits, core, redundant):
    """
    🎯 목표: Entry → Exit 경로를 끊는 노드 찾기
    
    알고리즘:
      1) 그래프를 무방향 그래프로 변환
      2) articulation_points (단절점) 계산
      3) Entry → 모든 Exit 도달 가능 여부 검증
    
    예시:
    
    ❌ SPOF O (단절점이 명확함)
    User → LB → API → DB → Response
                 ↑
              SPOF: API (제거하면 DB에 못 감)
    
    ✅ SPOF X (경로 다중화)
    User → LB1 ──→ API1 ──┐
            ↓               DB
            LB2 ──→ API2 ──┘
    
    코드:
    """
    H = G.subgraph(core).copy()           # core 서브그래프만
    UG = H.to_undirected()                # 무방향으로 변환
    
    candidates = set(nx.articulation_points(UG))  # 단절점 찾기
    candidates -= {entry}                 # entry는 제외
    candidates -= set(exits)              # exits는 제외
    candidates -= set(redundant)          # 이중화된 노드는 제외
    
    spofs = []
    for node in candidates:
        H2 = H.copy()
        H2.remove_node(node)              # 노드 제거 후
        
        # 실제로 exit에 못 가는지 확인
        for ex in exits:
            if not nx.has_path(H2, entry, ex):  # 경로 끊김!
                spofs.append(node)
                break
    
    return spofs
    
    # 예시 실행
    # G: User -> LB -> API -> DB
    # articulation_points(UG) = {LB, API}
    # LB 제거 → User에서 DB 못 가 → SPOF!
    # API 제거 → User에서 DB 못 가 → SPOF!
    # 결과: spofs = [LB, API]
    ```

#### **3️⃣ 병목 탐지 (중앙성 + 팬인)**

```python
def compute_bottlenecks(G, core, labels, topk=3):
    """
    🎯 목표: 트래픽이 몰릴 가능성이 높은 노드 찾기
    
    점수 = Betweenness Centrality + Fan-in/out 가중치 + Stateful 보너스
    
    - Betweenness Centrality: 경로가 얼마나 많이 지나가는가
    - Fan-in: 들어오는 연결이 많은가 (요청 몰림)
    - Fan-out: 나가는 연결이 많은가 (응답 분산)
    - Stateful 보너스: DB/Redis/Queue는 병목 가능성 ↑
    
    예시:
    
    중앙성 높음:
    Client → Gateway ← Monitoring     (Gateway가 모든 요청 지남)
             ↓
            API
    
    Fan-in 높음:
    Service1 ──┐
    Service2 ──┼→ Database           (Database로 모든 요청 집중)
    Service3 ──┘
    
    코드:
    """
    H = G.subgraph(core).copy()
    bc = nx.betweenness_centrality(H.to_undirected(), normalized=True)
    
    stateful_keys = ["db", "database", "vector", "redis", "queue", "kafka"]
    scored = []
    
    for n in H.nodes:
        lab = labels.get(n, "").lower()
        fanin = H.in_degree(n)
        fanout = H.out_degree(n)
        
        bonus = 0.0
        if any(k in lab for k in stateful_keys):
            bonus += 0.20  # Stateful 컴포넌트는 병목 가능성 ↑
        
        # 종합 점수
        score = bc.get(n, 0.0) + 0.06 * fanin + 0.02 * fanout + bonus
        scored.append((n, score, fanin, fanout))
    
    scored.sort(key=lambda x: x[1], reverse=True)
    
    # 상위 3개만 반환
    return [
        {
            "node": n,
            "label": labels.get(n),
            "score": score,
            "fanin": fanin,
            "fanout": fanout
        }
        for n, score, fanin, fanout in scored[:topk]
    ]
    
    # 예시 실행
    # G: User → Gateway → API1, API2, API3 → DB
    #         → Monitoring
    # 
    # Gateway의 centrality: 높음 (모든 경로 지남)
    # Gateway의 fan-in: 1 (User에서만)
    # Gateway의 fan-out: 4 (API1,2,3,Monitoring)
    # 
    # DB의 centrality: 중간
    # DB의 fan-in: 3 (API1,2,3에서)  ← 높음!
    # DB의 fan-out: 0
    # bonus: +0.20 (stateful)
    #
    # 결과: 상위 2개 = [Gateway, DB]
    ```

#### **4️⃣ 대안 아키텍처 생성** ✨

```python
def generate_alternative_architecture(spofs, bottlenecks, labels, G):
    """
    SPOF/병목을 해결하는 구체적 방안을 텍스트로 제시
    
    로직:
      1) SPOF가 있으면 → 이중화/로드밸런싱 제안
      2) 병목이 있으면 → 캐싱/샤딩/비동기화 제안
      3) 컴포넌트 타입에 따라 다른 제안
    """
    suggestions = []
    
    # SPOF 해결
    for spof_node in spofs:
        label = labels.get(spof_node, spof_node)
        
        if any(k in label.lower() for k in ['gateway', 'lb', 'ingress']):
            suggestions.append(
                f"✓ [{spof_node} 이중화] {label} 앞에 로드밸런서 2대 이상 배치"
            )
        elif any(k in label.lower() for k in ['db', 'database']):
            suggestions.append(
                f"✓ [{spof_node} 레플리카] 마스터-슬레이브 구성 또는 클러스터"
            )
        elif any(k in label.lower() for k in ['broker', 'queue', 'kafka']):
            suggestions.append(
                f"✓ [{spof_node} 클러스터] 3개 이상 노드로 구성"
            )
    
    # 병목 해결
    for bn in bottlenecks[:2]:
        node = bn["node"]
        label = bn.get("label", node)
        fanin = bn.get("fanin", 0)
        
        if fanin >= 3:
            suggestions.append(
                f"✓ [{node} 캐싱] Redis/Memcached로 캐싱"
            )
        
        if any(k in label.lower() for k in ['db', 'database']):
            suggestions.append(
                f"✓ [{node} 샤딩] 핫 데이터 기준으로 샤딩"
            )
    
    return "\n".join(suggestions)
    
    # 예시 실행
    # SPOF: [API]
    # Bottleneck: [Gateway, DB]
    #
    # 출력:
    # ✓ [API 이중화] API 서비스 앞에 로드밸런서 2대 이상 배치
    # ✓ [Gateway 캐싱] Redis/Memcached로 캐싱
    # ✓ [DB 샤딩] 핫 데이터 기준으로 샤딩
    ```

#### **5️⃣ 동적 질문 생성** ✨

```python
def generate_followup_questions(submission, graph_analysis, penalty_info):
    """
    SPOF/병목/Tradeoff에 따라 면접관 스타일 질문 5개 자동 생성
    """
    questions = []
    
    # SPOF 질문
    if graph_analysis.get("spof_candidates"):
        spofs = graph_analysis["spof_candidates"]
        questions.append(
            f"'{spofs[0]}' 컴포넌트가 장애 시, "
            f"어떻게 전체 서비스를 보호할 건가요?"
        )
    
    # 병목 질문
    if graph_analysis.get("bottleneck_candidates"):
        bn = graph_analysis["bottleneck_candidates"][0]["node"]
        questions.append(
            f"'{bn}' 노드의 처리량이 폭증하면?"
        )
    
    # Tradeoff 질문
    for tradeoff in submission.get("tradeoffs_json", [])[:2]:
        topic = tradeoff.get("topic", "선택")
        questions.append(
            f"'{topic}' 트레이드오프에서 "
            f"'{tradeoff.get('cons')}' 를 어떻게 완화할 건가요?"
        )
    
    # 일반 질문 (부족분 채우기)
    general_qs = [
        "이 설계에서 가장 취약한 부분은?",
        "트래픽이 10배 증가하면?",
        "팀 규모(SRE 몇 명)가 운영 가능할까?"
    ]
    
    for q in general_qs:
        if len(questions) < 5:
            questions.append(q)
    
    return questions[:5]
    
    # 예시 실행
    # SPOF: [API]
    # Bottleneck: [Gateway]
    # Tradeoff: [ACL, Cache]
    #
    # 출력:
    # 1. 'API' 컴포넌트가 장애 시, 어떻게 전체 서비스를 보호할 건가요?
    # 2. 'Gateway' 노드의 처리량이 폭증하면?
    # 3. 'ACL' 트레이드오프에서 '복잡도 증가'를 어떻게 완화할 건가요?
    # 4. 'Cache' 트레이드오프에서 '불일치 위험'을 어떻게 완화할 건가요?
    # 5. 이 설계에서 가장 취약한 부분은?
    ```

#### **6️⃣ DB 업데이트**

```python
def update_system_results(conn, submission_id, graph_analysis, penalty_info, 
                         alternative_arch, questions):
    """
    system_results에 모든 분석 결과 저장
    
    저장하는 것:
    1. score_breakdown_json.items.graph_analysis
       ├─ spof_candidates
       ├─ bottleneck_candidates
       └─ nodes_cnt, edges_cnt 등
    
    2. score_breakdown_json.meta.graph_penalty
       ├─ old_score_total
       ├─ spof_count, spof_penalty
       ├─ bottleneck_count, bottleneck_penalty
       └─ total_penalty
    
    3. risk_flags_json에 추가
       ├─ "SPOF_DETECTED" (spof_count > 0)
       ├─ "BOTTLENECK_CANDIDATES" (bottleneck_count > 0)
       └─ "GRAPH_PENALTY_APPLIED" (total_penalty > 0)
    
    4. alternative_mermaid_text
       └─ 대안 아키텍처 텍스트
    
    5. questions_json
       └─ 5개 질문 배열
    
    6. coach_summary
       └─ 대안 + 질문 종합 피드백
    """
    cur = conn.cursor(dictionary=True)
    
    # 기존 결과 조회
    cur.execute(
        "SELECT score_total, score_breakdown_json, risk_flags_json "
        "FROM system_results WHERE submission_id=%s",
        (submission_id,)
    )
    row = cur.fetchone()
    
    # 스코어 + 분석 업데이트
    new_score_total = row["score_total"] - penalty_info["total_penalty"]
    
    # graph_analysis, penalty 정보, 대안, 질문 모두 저장
    cur.execute(
        "UPDATE system_results "
        "SET score_total=%s, score_breakdown_json=%s, "
        "risk_flags_json=%s, alternative_mermaid_text=%s, "
        "questions_json=%s, coach_summary=%s "
        "WHERE submission_id=%s",
        (
            new_score_total,
            json.dumps({...}),    # graph_analysis + penalty
            json.dumps(new_flags),
            alternative_arch,
            json.dumps(questions),
            coach_summary,
            submission_id
        )
    )
    conn.commit()
```

---

## 5️⃣ **README.md** - 종합 가이드

(이미 작성됨 - 생략)

---

## 🔄 전체 실행 흐름도

```
┌─ 학생 관점 ──────────────────────────────────────────────────────────┐
│                                                                        │
│  1. README.md 읽기 (전체 이해)                                       │
│       ↓                                                               │
│  2. system_scenarios 조회 (문제 선택)                               │
│       ↓                                                               │
│  3. 아키텍처 설계 (Mermaid + Tradeoff 작성)                          │
│       ↓                                                               │
│  4. system_submissions에 제출                                        │
│                                                                        │
└────────────────────────────────────────────────────────────────────────┘

┌─ 채점 시스템 (자동) ──────────────────────────────────────────────────┐
│                                                                        │
│  db_03_demo_submission_result.sql 실행:                             │
│       ↓                                                               │
│  1. 키워드 매칭 (ACL, Audit, Observability, Failure Mode)          │
│  2. Tradeoff 개수에 따른 cap 적용                                   │
│  3. Risk Flags 생성                                                  │
│  4. system_results 저장 (점수 + 상세 분석)                          │
│                                                                        │
│  review_SPOF_bottleneck.py 실행:                                    │
│       ↓                                                               │
│  1. Mermaid 파싱 → 그래프 생성                                      │
│  2. SPOF 탐지 (단절점 알고리즘)                                      │
│  3. 병목 탐지 (중앙성 + 팬인)                                       │
│  4. 대안 아키텍처 생성 ✨                                           │
│  5. 동적 질문 생성 ✨                                               │
│  6. 감점 반영 → system_results 업데이트                             │
│                                                                        │
└────────────────────────────────────────────────────────────────────────┘

┌─ 피드백 제공 ──────────────────────────────────────────────────────────┐
│                                                                        │
│  system_results 조회:                                                │
│       ├─ score_total (최종 점수)                                     │
│       ├─ score_breakdown_json (항목별 점수 + SPOF/병목 분석)        │
│       ├─ risk_flags_json (경고 플래그)                              │
│       ├─ alternative_mermaid_text (대안 아키텍처) ✨               │
│       ├─ questions_json (5개 질문) ✨                               │
│       └─ coach_summary (종합 피드백)                                │
│            ↓                                                          │
│  학생이 피드백을 보고 다시 설계                                      │
│                                                                        │
└────────────────────────────────────────────────────────────────────────┘
```

---

## 📊 점수 흐름 예시

```
user-001이 SYS-RAG-ONPREM-001 제출

제출 내용:
- Mermaid: User → Gateway → Retriever → VectorDB, AuditLog
- Components: "Gateway는 인증/ACL을 담당합니다."
- Tradeoff: 2개 (ACL, Cache)
- Observability: "p95 latency, error rate, trace id"

자동채점 (db_03):
  Raw Score = 10 + 25(ACL) + 20(Audit) + 25(Obs) + 0(FM) + 8(Tradeoff 2개)
            = 88점
  
  Cap = 85 (Tradeoff 2개)
  
  Final Score = MIN(88, 85) = 85점 ✅
  
  Risk Flags:
    - "INSUFFICIENT_TRADEOFFS" (2개 < 3개)
    - "CAP_APPLIED_BY_TRADEOFFS"

그래프 분석 (Python):
  Mermaid 파싱:
    nodes: User, Gateway, Retriever, VectorDB, AuditLog
    edges: (User→Gateway), (Gateway→Retriever), (Retriever→VectorDB), (Retriever→AuditLog)
  
  SPOF 탐지:
    - Retriever가 단절점 (모든 것이 Retriever를 지남)
    - SPOF: [Retriever] → 감점 -12점
  
  병목 탐지:
    - Gateway: 중앙성 높음 (모든 요청이 지남)
    - Retriever: fan-in 1, fan-out 2
    - Bottleneck: [Gateway] → 감점 -6점
  
  대안 아키텍처:
    ✓ [Retriever 이중화] Retriever 2개 이상 배치, 로드밸런싱
    ✓ [Gateway 캐싱] 자주 조회되는 데이터 Redis 캐싱
  
  질문 생성:
    1. 'Retriever' 컴포넌트가 장애 시, 어떻게 전체 서비스를 보호할 건가요?
    2. 'Gateway' 노드의 처리량이 폭증하면?
    3. 'ACL' 트레이드오프에서 '복잡도 증가'를 어떻게 완화할 건가요?
    4. 'Cache' 트레이드오프에서 '불일치 위험'을 어떻게 완화할 건가요?
    5. 이 설계에서 가장 취약한 부분은?

최종 결과:
  Score Total = 85 - 12(SPOF) - 6(병목) = 67점
  
  Risk Flags:
    - "SPOF_DETECTED"
    - "BOTTLENECK_CANDIDATES"
    - "SCORE_DEDUCTED_FOR_SPOF"
    - "SCORE_DEDUCTED_FOR_BOTTLENECKS"
    - "INSUFFICIENT_TRADEOFFS"
    - "CAP_APPLIED_BY_TRADEOFFS"
  
  Coach Summary:
    "대안 아키텍처:
     ✓ [Retriever 이중화] ...
     ✓ [Gateway 캐싱] ...
     
     코치 질문:
     1. ...
     2. ...
     ..."
```

---

## 🎯 핵심 개념 정리

| 개념 | 설명 | 영향 |
|------|------|------|
| **SPOF** (Single Point of Failure) | 단 하나의 노드 제거 = 전체 경로 단절 | 장애율 ↑ |
| **Bottleneck** | 모든 트래픽이 지나가는 노드 | 성능 ↓, 확장성 ↓ |
| **Articulation Points** | 그래프 이론의 단절점 (SPOF 탐지용) | 구조적 약점 |
| **Betweenness Centrality** | 경로 중앙성 (병목 탐지용) | 영향력 측정 |
| **Fan-in / Fan-out** | 입출력 연결 수 | 부하 집중도 |
| **Tradeoff Cap** | Tradeoff 개수에 따른 점수 상한 | 완전성 보장 |
| **Redundancy** | 이중화된 컴포넌트 | SPOF 제거 |

---

## 🔧 운영 팁

1. **시나리오 추가 (db_02)**
   ```sql
   INSERT INTO system_scenarios (id, title, ...) VALUES (...)
   ```

2. **감점 정책 조정 (Python)**
   ```python
   SPOF_PENALTY_PER = 12
   BOTTLENECK_PENALTY_PER = 6
   ```

3. **채점 규칙 수정 (db_03)**
   ```sql
   SET @cap :=
     CASE
       WHEN @tradeoff_cnt >= 3 THEN 100
       WHEN @tradeoff_cnt = 2 THEN 85
       ...
     END;
   ```

---

**완성도 평가**: ⭐⭐⭐⭐⭐ (5/5)

**다음 개선 예정**:
- [ ] AI Coach (LLM 기반 맞춤 피드백)
- [ ] 실시간 스코어링
- [ ] 게임화 (배지/리더보드)
