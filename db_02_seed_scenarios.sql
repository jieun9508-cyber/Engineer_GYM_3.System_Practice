-- =========================================================
-- 02_seed_scenarios.sql (Expanded)
-- 시나리오 3개 seed
--   1) 온프렘 RAG 문서검색(ACL/근거/감사로그)
--   2) 주문/결제 이벤트 처리(피크 트래픽, 중복/정합성)
--   3) 실시간 알림/채팅(웹소켓, fanout, backpressure)
-- =========================================================

USE Engineer_GYM;

-- ---------------------------------------------------------
-- 1) SYS-RAG-ONPREM-001 (기존)
-- ---------------------------------------------------------
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
  JSON_OBJECT(
    'background','사내 문서(규정/기술문서/회의록)를 검색+요약해주는 RAG 챗봇이 필요합니다.',
    'goal','권한(ACL)을 지키면서 근거(citation)와 감사로그(audit log)가 남는 검색/응답 시스템 설계',
    'environment','On-Prem(망분리), 민감정보 포함 가능'
  ),
  JSON_ARRAY(
    '근거(출처) 첨부',
    'ACL(권한) 준수',
    '감사로그 저장',
    '관측성(메트릭/트레이싱/알림) 정의'
  ),
  JSON_ARRAY(
    '온프렘',
    '민감정보(PII) 가능',
    'SLA 존재',
    '권한 변경이 발생할 수 있음'
  ),
  JSON_OBJECT('users_total',2000,'qps_peak',20,'sla_p95_latency_ms',2500),
  JSON_OBJECT('required_artifacts', JSON_ARRAY('Mermaid','Tradeoffs','FailureMode','Observability')),
  JSON_OBJECT(
    'scoring', JSON_OBJECT(
      'weights', JSON_OBJECT(
        'tradeoffs', 15,
        'acl', 25,
        'audit_log', 20,
        'citations', 20,
        'observability', 20,
        'failure_mode', 15
      ),
      'notes','MVP에서는 키워드/룰 기반, 향후 Mermaid 그래프 파싱으로 SPOF/병목 확장'
    )
  ),
  JSON_OBJECT(
    'recommended_min_components', JSON_ARRAY('Gateway/Auth','Retriever','VectorDB','AuditLog','Indexer'),
    'mermaid_hint', JSON_ARRAY('%% entry: U', '%% exit: Answer', '%% redundant: V')
  )
);

-- ---------------------------------------------------------
-- 2) SYS-ORDER-EVENT-001 (신규)
-- ---------------------------------------------------------
INSERT IGNORE INTO system_scenarios (
  id, track, title, difficulty, tags, version,
  context_json, requirements_json, constraints_json, traffic_json,
  submission_format_json, checklist_template_json, admin_notes_json
) VALUES (
  'SYS-ORDER-EVENT-001',
  'system_practice',
  '주문/결제 이벤트 처리(피크 트래픽, 정합성, 재처리)',
  'medium',
  JSON_ARRAY('Event-Driven','Payments','Idempotency','DLQ','Outbox'),
  '1.0.0',
  JSON_OBJECT(
    'background','프로모션 시간에 주문/결제가 급증합니다. 이벤트 기반으로 주문/결제/정산을 처리합니다.',
    'goal','중복결제/중복처리 방지 + 장애/재시도 시에도 정합성을 지키는 아키텍처 설계',
    'environment','MSA, 메시지 브로커(Kafka/Rabbit) 사용 가능'
  ),
  JSON_ARRAY(
    'Idempotency(중복 처리 방지) 전략',
    '재시도/백오프 + DLQ(Dead Letter Queue) 처리',
    'Outbox/CDC 또는 Saga/보상 트랜잭션 중 1개 이상',
    '데이터 정합성(결제 성공/실패 상태 전이) 명확화',
    '관측성(지표/알람) 정의'
  ),
  JSON_ARRAY(
    '피크 트래픽(이벤트 폭증)',
    '외부 PG 연동(지연/실패 가능)',
    '정산/주문 상태는 감사 가능해야 함',
    '중복 이벤트/순서 뒤바뀜(out-of-order) 발생 가능'
  ),
  JSON_OBJECT('users_total',500000,'qps_peak',200,'sla_p95_latency_ms',1500,'event_rate_peak_per_sec',800),
  JSON_OBJECT('required_artifacts', JSON_ARRAY('Mermaid','Tradeoffs','FailureMode','Observability')),
  JSON_OBJECT(
    'scoring', JSON_OBJECT(
      'weights', JSON_OBJECT(
        'tradeoffs', 15,
        'idempotency', 25,
        'dlq_retry', 20,
        'outbox_saga', 20,
        'consistency_model', 10,
        'observability', 15,
        'failure_mode', 10
      ),
      'keyword_hints', JSON_OBJECT(
        'idempotency','idempot|dedup|중복',
        'dlq_retry','dlq|dead letter|retry|backoff|재시도',
        'outbox_saga','outbox|cdc|saga|compens|보상',
        'consistency','state|전이|정합|exactly once|at least once'
      )
    )
  ),
  JSON_OBJECT(
    'recommended_min_components', JSON_ARRAY('API/Gateway','Order Service','Payment Service','Message Broker','DLQ','Outbox(or Saga)','Audit Log'),
    'mermaid_hint', JSON_ARRAY('%% entry: Client', '%% exit: Settlement', '%% redundant: Broker')
  )
);

-- ---------------------------------------------------------
-- 3) SYS-REALTIME-NOTIFY-001 (신규)
-- ---------------------------------------------------------
INSERT IGNORE INTO system_scenarios (
  id, track, title, difficulty, tags, version,
  context_json, requirements_json, constraints_json, traffic_json,
  submission_format_json, checklist_template_json, admin_notes_json
) VALUES (
  'SYS-REALTIME-NOTIFY-001',
  'system_practice',
  '실시간 알림/채팅(웹소켓, Fanout, Backpressure)',
  'medium',
  JSON_ARRAY('Realtime','WebSocket','Fanout','PubSub','Backpressure'),
  '1.0.0',
  JSON_OBJECT(
    'background','사용자에게 실시간 알림/채팅을 제공합니다. 연결 수가 많고 특정 시간에 메시지 폭증이 발생합니다.',
    'goal','실시간 연결(WebSocket) + 메시지 fanout + 폭주(backpressure) 제어 + 유실 방지 설계',
    'environment','클라우드/온프렘 무관, Pub/Sub 가능'
  ),
  JSON_ARRAY(
    'WebSocket(또는 SSE) 게이트웨이 설계',
    'Fanout(브로커/채널) 설계',
    'Backpressure/Rate limit/Buffer 전략',
    'ACK/재전송/유실 방지(최소 1개) 언급',
    '관측성(연결수, 메시지 지연, 드롭률) 정의'
  ),
  JSON_ARRAY(
    '동시 접속자 수가 큼',
    '메시지 스파이크(폭증)',
    '모바일 환경(네트워크 불안정)',
    '비용(브로커/전송/저장) 고려'
  ),
  JSON_OBJECT('users_total',1000000,'concurrent_connections',50000,'msg_fanout_peak_per_sec',5000,'sla_p95_latency_ms',800),
  JSON_OBJECT('required_artifacts', JSON_ARRAY('Mermaid','Tradeoffs','FailureMode','Observability')),
  JSON_OBJECT(
    'scoring', JSON_OBJECT(
      'weights', JSON_OBJECT(
        'tradeoffs', 15,
        'websocket_gateway', 20,
        'fanout_broker', 20,
        'backpressure_ratelimit', 20,
        'ack_retry', 15,
        'observability', 15,
        'failure_mode', 10
      ),
      'keyword_hints', JSON_OBJECT(
        'websocket_gateway','websocket|ws|sse',
        'fanout_broker','fanout|broadcast|pubsub|broker|kafka|rabbit',
        'backpressure_ratelimit','backpressure|queue|buffer|rate limit|throttle',
        'ack_retry','ack|retry|resend|재전송|유실'
      )
    )
  ),
  JSON_OBJECT(
    'recommended_min_components', JSON_ARRAY('Realtime Gateway','Presence/Session Store','Broker(PubSub)','Fanout Worker','Push Provider(Optional)','Metrics/Tracing'),
    'mermaid_hint', JSON_ARRAY('%% entry: Producer', '%% exit: Client', '%% redundant: Broker')
  )
);

-- ---------------------------------------------------------
-- 확인
-- ---------------------------------------------------------
SELECT id, title, difficulty, created_at
FROM system_scenarios
ORDER BY created_at DESC;
