-- =========================================================
-- 03_demo_submission_result.sql (Tradeoff 상한 적용 버전)
-- 목적: 제출 1건 저장 → (룰 기반 자동채점) → 결과 저장 → JOIN으로 확인
-- 핵심: tradeoffs 3개 미만이면 총점 상한(cap)을 적용
--   - 3개 이상: cap 100
--   - 2개: cap 85   ✅ (요청사항)
--   - 1개: cap 70
--   - 0개: cap 60
-- =========================================================

USE Engineer_GYM;

-- ---------------------------------------------------------
-- 0) 사전 테스트: 전제 조건 확인
-- ---------------------------------------------------------
SHOW TABLES;

SELECT id, title, difficulty
FROM system_scenarios
WHERE id = 'SYS-RAG-ONPREM-001';

SELECT
  (SELECT COUNT(*) FROM system_scenarios)    AS scenarios_cnt,
  (SELECT COUNT(*) FROM system_submissions)  AS submissions_cnt,
  (SELECT COUNT(*) FROM system_results)      AS results_cnt;

-- ---------------------------------------------------------
-- 1) 제출 insert (샘플)
-- ---------------------------------------------------------
INSERT INTO system_submissions (
  scenario_id,
  user_id,
  mermaid_text,
  components_text,
  tradeoffs_json,
  submission_payload_json,
  status
) VALUES (
  'SYS-RAG-ONPREM-001',
  'user-001',
  'graph TD; U[User]-->G[Gateway]; G-->R[Retriever]; R-->V[VectorDB]; R-->A[AuditLog];',
  'Gateway는 인증/레이트리밋을 담당하고 Retriever는 ACL 필터를 적용합니다.',
  JSON_ARRAY(
    JSON_OBJECT('topic','ACL',   'pros','권한 유출 방지',     'cons','복잡도 증가'),
    JSON_OBJECT('topic','Cache', 'pros','지연 감소/비용 절감', 'cons','불일치 위험')
    -- 일부러 2개만 넣어: "cap 85"가 실제로 적용되는지 확인
  ),
  JSON_OBJECT(
    'failure_mode','VectorDB 장애 시 fallback',
    'observability','p95 latency, error rate, trace id'
  ),
  'submitted'
);

-- ---------------------------------------------------------
-- 2) 마지막 제출 id 가져오기
-- ---------------------------------------------------------
SET @sid := (SELECT id FROM system_submissions ORDER BY id DESC LIMIT 1);

-- ---------------------------------------------------------
-- 3) 룰 기반 자동채점(키워드 매칭)
-- ---------------------------------------------------------
SET @mermaid := LOWER((SELECT mermaid_text FROM system_submissions WHERE id=@sid));
SET @comp    := LOWER((SELECT components_text FROM system_submissions WHERE id=@sid));
SET @payload := (SELECT submission_payload_json FROM system_submissions WHERE id=@sid);

-- tradeoffs 개수
SET @tradeoffs := (SELECT tradeoffs_json FROM system_submissions WHERE id=@sid);
SET @tradeoff_cnt := IFNULL(JSON_LENGTH(@tradeoffs), 0);

-- Tradeoffs 점수: 3개 이상 15점 / 2개 8점 / 1개 3점 / 0개 0점
SET @score_tradeoffs :=
  CASE
    WHEN @tradeoff_cnt >= 3 THEN 15
    WHEN @tradeoff_cnt = 2 THEN 8
    WHEN @tradeoff_cnt = 1 THEN 3
    ELSE 0
  END;

-- ACL/권한: 포함 시 +25
SET @score_acl :=
  IF(@mermaid REGEXP 'acl|auth|role|permission' OR @comp REGEXP 'acl|auth|role|permission', 25, 0);

-- Audit/Log: 포함 시 +20
SET @score_audit :=
  IF(@mermaid REGEXP 'audit|log' OR @comp REGEXP 'audit|log', 20, 0);

-- Observability: 키워드 2개 이상이면 +25, 1개면 +10
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

-- Failure mode: 장애/대체경로 있으면 +20
SET @fm_text := LOWER(JSON_UNQUOTE(JSON_EXTRACT(@payload, '$.failure_mode')));
SET @score_fm := IF(@fm_text REGEXP 'down|fail|fallback|degrad|장애', 20, 0);

-- ✅ raw_total / cap / 최종 점수(상한 적용)
SET @raw_total := 10 + @score_acl + @score_audit + @score_obs + @score_fm + @score_tradeoffs;

SET @cap :=
  CASE
    WHEN @tradeoff_cnt >= 3 THEN 100
    WHEN @tradeoff_cnt = 2 THEN 85   -- ✅ 요청사항: tradeoff 2개면 만점 불가
    WHEN @tradeoff_cnt = 1 THEN 70
    ELSE 60
  END;

SET @score_total := LEAST(@cap, LEAST(100, @raw_total));

-- risk_flags_json을 NULL 없이 깔끔하게 만들기
SET @risk_flags := JSON_ARRAY();

SET @risk_flags :=
  IF(@tradeoff_cnt < 3, JSON_ARRAY_APPEND(@risk_flags, '$', 'INSUFFICIENT_TRADEOFFS'), @risk_flags);

SET @risk_flags :=
  IF(@score_obs = 0, JSON_ARRAY_APPEND(@risk_flags, '$', 'NO_OBSERVABILITY'), @risk_flags);

SET @risk_flags :=
  IF(@score_fm = 0, JSON_ARRAY_APPEND(@risk_flags, '$', 'NO_FAILURE_MODE'), @risk_flags);

SET @risk_flags :=
  IF(@raw_total > @cap, JSON_ARRAY_APPEND(@risk_flags, '$', 'CAP_APPLIED_BY_TRADEOFFS'), @risk_flags);

-- 디버그(점수 확인용)
SELECT
  @sid AS submission_id,
  @tradeoff_cnt AS tradeoff_count,
  @raw_total AS raw_total,
  @cap AS cap_by_tradeoffs,
  @score_total AS score_total,
  @risk_flags AS risk_flags_json;

-- ---------------------------------------------------------
-- 4) 결과 저장 (중복 실행 대비: 같은 submission_id 결과가 이미 있으면 삭제 후 재삽입)
-- ---------------------------------------------------------
DELETE FROM system_results WHERE submission_id = @sid;

INSERT INTO system_results (
  submission_id,
  score_total,
  score_breakdown_json,
  risk_flags_json,
  alternative_mermaid_text,
  questions_json,
  coach_summary
) VALUES (
  @sid,
  @score_total,
  JSON_OBJECT(
    'meta', JSON_OBJECT(
      'raw_total', @raw_total,
      'cap_by_tradeoffs', @cap
    ),
    'items', JSON_OBJECT(
      'tradeoffs', JSON_OBJECT('score', @score_tradeoffs, 'max', 15, 'count', @tradeoff_cnt, 'status',
        CASE
          WHEN @tradeoff_cnt >= 3 THEN 'OK'
          WHEN @tradeoff_cnt = 2 THEN 'PARTIAL'
          WHEN @tradeoff_cnt = 1 THEN 'NG'
          ELSE 'NG'
        END
      ),
      'acl', JSON_OBJECT('score', @score_acl, 'max', 25, 'status', IF(@score_acl>0,'OK','NG')),
      'audit_log', JSON_OBJECT('score', @score_audit, 'max', 20, 'status', IF(@score_audit>0,'OK','NG')),
      'observability', JSON_OBJECT('score', @score_obs, 'max', 25, 'status',
        CASE WHEN @score_obs>=25 THEN 'OK' WHEN @score_obs>0 THEN 'PARTIAL' ELSE 'NG' END
      ),
      'failure_mode', JSON_OBJECT('score', @score_fm, 'max', 20, 'status', IF(@score_fm>0,'OK','NG'))
    )
  ),
  @risk_flags,
  NULL,
  JSON_ARRAY(
    '트레이드오프 3가지를 각각 “장점/단점/대안” 형태로 말할 수 있나요?',
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

-- ---------------------------------------------------------
-- 5) 결과 확인(JOIN) - 이걸로 데모 끝
-- ---------------------------------------------------------
SELECT
  s.id AS submission_id,
  s.user_id,
  sc.title AS scenario_title,
  r.score_total,
  JSON_EXTRACT(r.score_breakdown_json, '$.meta') AS meta,
  JSON_EXTRACT(r.score_breakdown_json, '$.items.tradeoffs') AS tradeoffs_breakdown,
  r.risk_flags_json,
  r.coach_summary,
  r.created_at
FROM system_results r
JOIN system_submissions s ON s.id = r.submission_id
JOIN system_scenarios sc ON sc.id = s.scenario_id
WHERE s.id = @sid;
