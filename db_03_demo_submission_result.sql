-- =========================================================
-- 03_demo_submission_result.sql
-- 제출 1건 + 결과 1건 저장 + join 확인
-- =========================================================

USE Engineer_GYM;

-- 제출 insert (샘플)
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
    JSON_OBJECT('topic','ACL 필터링', 'pros','권한 유출 방지', 'cons','복잡도 증가'),
    JSON_OBJECT('topic','캐시', 'pros','지연 감소/비용 절감', 'cons','불일치 위험'),
    JSON_OBJECT('topic','인덱싱', 'pros','최신성 유지', 'cons','운영 비용')
  ),
  JSON_OBJECT(
    'failure_mode','VectorDB 장애 시 키워드 검색으로 degrade',
    'observability','p95 latency, error rate, citation rate, trace id',
    'notes','MVP 가정: 문서 30만건'
  ),
  'submitted'
);

-- 마지막 제출 id 가져오기
SET @last_submission_id := (SELECT id FROM system_submissions ORDER BY id DESC LIMIT 1);

-- 결과 저장(샘플)
INSERT INTO system_results (
  submission_id,
  score_total,
  score_breakdown_json,
  risk_flags_json,
  alternative_mermaid_text,
  questions_json,
  coach_summary
) VALUES (
  @last_submission_id,
  70,
  JSON_OBJECT(
    'total_score', 70,
    'items', JSON_OBJECT(
      'security_acl', JSON_OBJECT('status','PARTIAL','score',15,'max',25,'notes','생성 단계 post-check 불명확'),
      'performance_bottleneck', JSON_OBJECT('status','OK','score',15,'max',15,'notes','캐시/비동기 인덱싱 언급'),
      'observability', JSON_OBJECT('status','PARTIAL','score',5,'max',15,'notes','trace 기반 상관관계 부족')
    )
  ),
  JSON_ARRAY('NO_TRACE_CORRELATION'),
  'graph TD; U-->G; G-->R; R-->V; R-->K[KeywordSearchFallback]; R-->A[AuditLog];',
  JSON_ARRAY(
    '권한 변경이 잦을 때 캐시/인덱스 권한을 어떻게 동기화하나요?',
    'p95 2.5초 SLA를 깨는 병목은 어디가 될 수 있나요?',
    '근거 부족 시 UX는 어떻게 처리하나요?',
    '감사로그 1년 보관 시 비용/검색 성능은 어떻게 확보하나요?',
    'VectorDB 장애 시 어떤 기능을 우선 유지하나요?'
  ),
  '전체적으로 구조는 좋으나, 생성 단계에서 근거 재검증 및 trace 기반 관측성이 보강되면 더 안전합니다.'
);

-- 결과 루프 확인 (join)
SELECT
  s.id AS submission_id,
  sc.title AS scenario_title,
  r.score_total,
  r.created_at
FROM system_results r
JOIN system_submissions s ON s.id = r.submission_id
JOIN system_scenarios sc ON sc.id = s.scenario_id
ORDER BY r.id DESC
LIMIT 1;
