-- =========================================================
-- 02_seed_scenarios.sql
-- 시나리오 1개 seed
-- =========================================================

USE Engineer_GYM;

INSERT IGNORE INTO system_scenarios (
  id, track, title, difficulty, tags, version,
  context_json, requirements_json, constraints_json, traffic_json,
  submission_format_json, checklist_template_json, admin_notes_json
) VALUES (
  'SYS-RAG-ONPREM-001',
  'system_practice',
  '온프렘 사내 문서 검색 RAG 챗봇(권한/근거/감사로그)',
  'medium',
  JSON_ARRAY('RAG','On-Prem','ACL','Observability'),
  '1.0.0',
  JSON_OBJECT('background','...', 'goal','...', 'environment','...'),
  JSON_ARRAY('근거 첨부', 'ACL 준수', '감사로그 저장'),
  JSON_ARRAY('온프렘', '민감정보', 'SLA 존재'),
  JSON_OBJECT('users_total',2000,'qps_peak',20,'sla_p95_latency_ms',2500),
  JSON_OBJECT('required_artifacts', JSON_ARRAY('Mermaid','Tradeoffs','FailureMode','Observability')),
  JSON_OBJECT('scoring', JSON_OBJECT('weights', JSON_OBJECT('security_acl',25)), 'items', JSON_ARRAY()),
  JSON_OBJECT('recommended_min_components', JSON_ARRAY('Retriever','AuditLog','Indexer'))
);

-- 확인
SELECT id, title, difficulty, created_at
FROM system_scenarios;
