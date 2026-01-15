-- =========================================================
-- 03_demo_submission_result.sql (Scenario별 weight 적용 + Tradeoff cap)
-- 목적: 제출 1건 저장 → (룰 기반 자동채점) → 결과 저장 → JOIN으로 확인
-- 핵심1: tradeoffs 3개 미만이면 총점 상한(cap) 적용
-- 핵심2: 점수 가중치(max)는 system_scenarios.checklist_template_json($.scoring.weights)에서 읽음
--       - 없으면 기본값(기존 03과 동일)으로 fallback
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
-- 2) 마지막 제출 id 가져오기 + 해당 시나리오의 룰(JSON) 가져오기
-- ---------------------------------------------------------
SET @sid := (SELECT id FROM system_submissions ORDER BY id DESC LIMIT 1);
SET @scenario_id := (SELECT scenario_id FROM system_submissions WHERE id=@sid);
SET @rules := (SELECT checklist_template_json FROM system_scenarios WHERE id=@scenario_id);

-- ---------------------------------------------------------
-- 3) 룰 기반 자동채점(키워드 매칭)
-- ---------------------------------------------------------
SET @mermaid := LOWER((SELECT mermaid_text FROM system_submissions WHERE id=@sid));
SET @comp    := LOWER(IFNULL((SELECT components_text FROM system_submissions WHERE id=@sid), ''));
SET @payload := (SELECT submission_payload_json FROM system_submissions WHERE id=@sid);

-- tradeoffs 개수
SET @tradeoffs := (SELECT tradeoffs_json FROM system_submissions WHERE id=@sid);
SET @tradeoff_cnt := IFNULL(JSON_LENGTH(@tradeoffs), 0);

-- ---------------------------------------------------------
-- 3-1) ✅ 시나리오별 가중치(weights) 읽기 (없으면 기존 기본값으로 fallback)
-- rules 예시:
-- checklist_template_json = {
--   "scoring": { "weights": { "acl":25, "audit_log":20, "observability":25, "failure_mode":20, "tradeoffs":15 } }
-- }
-- ---------------------------------------------------------
SET @w_acl :=
  CAST(IFNULL(JSON_UNQUOTE(JSON_EXTRACT(@rules, '$.scoring.weights.acl')), '25') AS UNSIGNED);
SET @w_audit :=
  CAST(IFNULL(JSON_UNQUOTE(JSON_EXTRACT(@rules, '$.scoring.weights.audit_log')), '20') AS UNSIGNED);
SET @w_obs :=
  CAST(IFNULL(JSON_UNQUOTE(JSON_EXTRACT(@rules, '$.scoring.weights.observability')), '25') AS UNSIGNED);
SET @w_fm :=
  CAST(IFNULL(JSON_UNQUOTE(JSON_EXTRACT(@rules, '$.scoring.weights.failure_mode')), '20') AS UNSIGNED);
SET @w_tradeoffs :=
  CAST(IFNULL(JSON_UNQUOTE(JSON_EXTRACT(@rules, '$.scoring.weights.tradeoffs')), '15') AS UNSIGNED);

-- ---------------------------------------------------------
-- 3-2) Tradeoffs 점수: 3개 이상 만점 / 2개 partial / 1개 낮게 / 0개 0
-- (max는 @w_tradeoffs)
-- ---------------------------------------------------------
SET @score_tradeoffs :=
  CASE
    WHEN @tradeoff_cnt >= 3 THEN @w_tradeoffs
    WHEN @tradeoff_cnt = 2 THEN FLOOR(@w_tradeoffs * 0.55)
    WHEN @tradeoff_cnt = 1 THEN FLOOR(@w_tradeoffs * 0.20)
    ELSE 0
  END;

-- ACL/권한: 포함 시 +@w_acl (시나리오에서 0으로 주면 자동으로 비활성화 가능)
SET @score_acl :=
  CASE
    WHEN @w_acl = 0 THEN 0
    WHEN @mermaid REGEXP 'acl|auth|role|permission|권한' OR @comp REGEXP 'acl|auth|role|permission|권한' THEN @w_acl
    ELSE 0
  END;

-- Audit/Log: 포함 시 +@w_audit
SET @score_audit :=
  CASE
    WHEN @w_audit = 0 THEN 0
    WHEN @mermaid REGEXP 'audit|log|감사' OR @comp REGEXP 'audit|log|감사' THEN @w_audit
    ELSE 0
  END;

-- Observability: 키워드 2개 이상이면 +@w_obs, 1개면 partial
SET @obs_text := LOWER(IFNULL(JSON_UNQUOTE(JSON_EXTRACT(@payload, '$.observability')), ''));

SET @obs_hits :=
  (CASE WHEN @obs_text REGEXP 'p95|latency' THEN 1 ELSE 0 END) +
  (CASE WHEN @obs_text REGEXP 'error' THEN 1 ELSE 0 END) +
  (CASE WHEN @obs_text REGEXP 'trace' THEN 1 ELSE 0 END) +
  (CASE WHEN @obs_text REGEXP 'metric|prometheus|grafana' THEN 1 ELSE 0 END) +
  (CASE WHEN @obs_text REGEXP 'alert' THEN 1 ELSE 0 END);

SET @score_obs :=
  CASE
    WHEN @w_obs = 0 THEN 0
    WHEN @obs_hits >= 2 THEN @w_obs
    WHEN @obs_hits = 1 THEN FLOOR(@w_obs * 0.40)
    ELSE 0
  END;

-- Failure mode: 장애/대체경로 있으면 +@w_fm
SET @fm_text := LOWER(IFNULL(JSON_UNQUOTE(JSON_EXTRACT(@payload, '$.failure_mode')), ''));
SET @score_fm :=
  CASE
    WHEN @w_fm = 0 THEN 0
    WHEN @fm_text REGEXP 'down|fail|fallback|degrad|장애|롤백|재시도' THEN @w_fm
    ELSE 0
  END;

-- ✅ raw_total / cap / 최종 점수(상한 적용)
SET @raw_total := 10 + @score_acl + @score_audit + @score_obs + @score_fm + @score_tradeoffs;

SET @cap :=
  CASE
    WHEN @tradeoff_cnt >= 3 THEN 100
    WHEN @tradeoff_cnt = 2 THEN 85
    WHEN @tradeoff_cnt = 1 THEN 70
    ELSE 60
  END;

SET @score_total := LEAST(@cap, LEAST(100, @raw_total));

-- risk_flags_json을 NULL 없이 깔끔하게 만들기
SET @risk_flags := JSON_ARRAY();

SET @risk_flags :=
  IF(@tradeoff_cnt < 3, JSON_ARRAY_APPEND(@risk_flags, '$', 'INSUFFICIENT_TRADEOFFS'), @risk_flags);

SET @risk_flags :=
  IF(@w_obs > 0 AND @score_obs = 0, JSON_ARRAY_APPEND(@risk_flags, '$', 'NO_OBSERVABILITY'), @risk_flags);

SET @risk_flags :=
  IF(@w_fm > 0 AND @score_fm = 0, JSON_ARRAY_APPEND(@risk_flags, '$', 'NO_FAILURE_MODE'), @risk_flags);

SET @risk_flags :=
  IF(@raw_total > @cap, JSON_ARRAY_APPEND(@risk_flags, '$', 'CAP_APPLIED_BY_TRADEOFFS'), @risk_flags);

-- 디버그(점수 확인용)
SELECT
  @sid AS submission_id,
  @scenario_id AS scenario_id,
  @tradeoff_cnt AS tradeoff_count,
  @raw_total AS raw_total,
  @cap AS cap_by_tradeoffs,
  @score_total AS score_total,
  JSON_OBJECT('w_acl',@w_acl,'w_audit',@w_audit,'w_obs',@w_obs,'w_fm',@w_fm,'w_tradeoffs',@w_tradeoffs) AS weights_used,
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
      'scenario_id', @scenario_id,
      'raw_total', @raw_total,
      'cap_by_tradeoffs', @cap
    ),
    'items', JSON_OBJECT(
      'tradeoffs', JSON_OBJECT('score', @score_tradeoffs, 'max', @w_tradeoffs, 'count', @tradeoff_cnt, 'status',
        CASE
          WHEN @tradeoff_cnt >= 3 THEN 'OK'
          WHEN @tradeoff_cnt = 2 THEN 'PARTIAL'
          WHEN @tradeoff_cnt = 1 THEN 'NG'
          ELSE 'NG'
        END
      ),
      'acl', JSON_OBJECT('score', @score_acl, 'max', @w_acl, 'status', IF(@score_acl>0,'OK','NG')),
      'audit_log', JSON_OBJECT('score', @score_audit, 'max', @w_audit, 'status', IF(@score_audit>0,'OK','NG')),
      'observability', JSON_OBJECT('score', @score_obs, 'max', @w_obs, 'hits', @obs_hits, 'status',
        CASE WHEN @score_obs=@w_obs AND @w_obs>0 THEN 'OK'
             WHEN @score_obs>0 THEN 'PARTIAL'
             ELSE 'NG' END
      ),
      'failure_mode', JSON_OBJECT('score', @score_fm, 'max', @w_fm, 'status', IF(@score_fm>0,'OK','NG'))
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
    'scenario=', @scenario_id,
    ' / tradeoffs=', @tradeoff_cnt,
    ' → tradeoffs 3개 미만이면 만점 상한(cap) 적용. ',
    '가중치(weights)는 system_scenarios.checklist_template_json에서 읽어 적용했습니다.'
  )
);

-- ---------------------------------------------------------
-- 5) 결과 확인(JOIN)
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
