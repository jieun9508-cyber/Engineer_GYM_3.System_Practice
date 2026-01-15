-- =========================================================
-- 02_seed_scenarios.sql
-- 시나리오 3개 seed
-- =========================================================


--1. SYS-RAG-ONPREM-001 : 온프렘 사내 문서 검색 RAG 챗봇(권한/근거/감사로그)

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
  JSON_OBJECT(
    'background', '사내 문서(정책/가이드/코드)가 온프렘 저장소에 분산되어 있습니다. 직원들이 RAG 챗봇으로 검색하기를 원하지만, 권한별로 접근 범위가 달라야 합니다.',
    'goal', '권한 규칙(ACL)을 준수하면서도 의미론적 검색(Semantic Search)을 지원하는 RAG 아키텍처를 설계합니다. 외부 클라우드 의존도를 최소화하고 감사로그(audit trail)를 유지합니다.',
    'environment', '온프렘(On-Premise) 환경. 외부 네트워크 접근 제약. LLM은 내부 LLMOps 또는 오픈소스 모델(Llama 등). 벡터DB는 선택(Milvus/Weaviate/Pinecone 고민). 민감정보(개인정보/소스코드 탈취) 방지 필수.'
  ),
  JSON_ARRAY('근거 첨부', 'ACL 준수', '감사로그 저장'),
  JSON_ARRAY(
    '온프렘/에어갭 환경에서 작동(외부 LLM API 호출 불가)',
    '민감정보 처리(PII/소스코드) 방지',
    '문서/사용자별 ACL 규칙이 다양(부서/직급별)',
    'SLA 존재(p95 지연, 가용성)',
    '벡터DB 및 임베딩 모델 선택 트레이드오프'
  ),
  JSON_OBJECT('users_total',2000,'qps_peak',20,'sla_p95_latency_ms',2500),
  JSON_OBJECT('required_artifacts', JSON_ARRAY('Mermaid','Tradeoffs','FailureMode','Observability')),
  JSON_OBJECT('scoring', JSON_OBJECT('weights', JSON_OBJECT('security_acl',25)), 'items', JSON_ARRAY()),
  JSON_OBJECT('recommended_min_components', JSON_ARRAY('Retriever','AuditLog','Indexer'))
);

-- 확인
SELECT id, title, difficulty, created_at
FROM system_scenarios;




--2. SYS-ORDER-EVENT-001 : 피크 트래픽 주문/결제 이벤트 처리(Outbox/Idempotency/DLQ/관측성)

USE Engineer_GYM;

INSERT IGNORE INTO system_scenarios (
  id, track, title, difficulty, tags, version,
  context_json, requirements_json, constraints_json, traffic_json,
  submission_format_json, checklist_template_json, admin_notes_json
) VALUES (
  'SYS-ORDER-EVENT-001',
  'system_practice',
  '피크 트래픽 주문/결제 이벤트 처리(Outbox/Idempotency/DLQ/관측성)',
  'hard',
  JSON_ARRAY('Event-Driven','Payment','Idempotency','DLQ','Observability','Audit'),
  '1.0.0',
  JSON_OBJECT(
    'background', '프로모션/라이브 커머스 등으로 짧은 시간 주문/결제가 폭증합니다. 결제/주문 상태 불일치와 중복 결제는 치명적입니다.',
    'goal', '피크 트래픽에서도 안정적으로 주문/결제 상태를 처리하고, 장애/재시도/중복에 안전한 아키텍처를 설계합니다.',
    'environment', '클라우드(AWS 등) 가능. 서비스 간 통신은 HTTP+비동기 메시징 혼합. 결제/주문은 감사 추적(Audit)이 필요.'
  ),
  JSON_ARRAY(
    '중복 결제/중복 주문 방지(Idempotency key 전략 포함)',
    '이벤트 재처리/재시도/실패 격리(DLQ 또는 실패 큐) 설계',
    '상태 일관성 전략(Outbox/사가/보상 트랜잭션 중 택1+이유)',
    '관측성(Trace/Metric/Alert)으로 장애 원인 추적 가능',
    '감사로그(Audit log)로 결제/정산 이력 추적'
  ),
  JSON_ARRAY(
    'SLA 존재(p95 지연, 오류율)',
    '외부 결제 PG는 간헐적 실패/지연이 발생',
    '메시지는 at-least-once(중복 전달 가능)로 가정',
    '개인정보/결제정보는 최소 저장 및 접근통제 필요'
  ),
  JSON_OBJECT(
    'users_total', 500000,
    'qps_peak', 300,
    'sla_p95_latency_ms', 800,
    'error_budget_monthly_pct', 0.1
  ),
  JSON_OBJECT(
    'required_artifacts', JSON_ARRAY('Mermaid','Tradeoffs','FailureMode','Observability'),
    'submit_fields', JSON_OBJECT(
      'mermaid', '서비스 구성요소와 이벤트 흐름이 드러나게 그리기',
      'components', '컴포넌트 역할 5~10줄',
      'tradeoffs', '최소 3개(장점/단점/대안)',
      'payload', 'failure_mode/observability/idempotency 전략 요약'
    )
  ),
  JSON_OBJECT(
    'scoring', JSON_OBJECT(
      'weights', JSON_OBJECT(
        'idempotency', 25,
        'failure_mode', 20,
        'observability', 20,
        'audit_log', 15,
        'data_consistency', 20
      )
    ),
    'items', JSON_ARRAY(
      JSON_OBJECT('key','idempotency','desc','idempotency key/중복 처리 전략이 명확한가'),
      JSON_OBJECT('key','failure_mode','desc','DLQ/재시도/보상 처리 등 장애 시 흐름이 있는가'),
      JSON_OBJECT('key','observability','desc','trace/metric/alert를 언급하고 상관관계가 가능한가'),
      JSON_OBJECT('key','audit_log','desc','결제/정산 감사로그가 설계에 포함되는가'),
      JSON_OBJECT('key','data_consistency','desc','Outbox/사가 등 일관성 확보 방식이 논리적인가')
    )
  ),
  JSON_OBJECT(
    'recommended_min_components', JSON_ARRAY(
      'API Gateway',
      'Order Service',
      'Payment Service',
      'Message Broker(Kafka/RabbitMQ)',
      'Outbox/CDC(or Transactional Outbox Table)',
      'DLQ/Failure Queue',
      'AuditLog Store',
      'Observability(Stack: metrics/logs/traces)'
    ),
    'admin_notes', JSON_ARRAY(
      'Idempotency 키 저장 위치(DB/Redis)와 만료 정책을 언급하면 가산점',
      'PG 장애 시(타임아웃/중복 콜) 처리 흐름을 Mermaid에 표현하면 좋음',
      'trace id 전파(게이트웨이→서비스→브로커/컨슈머) 언급 유도'
    )
  )
);




-- 3. SYS-REALTIME-NOTIFY-001 : 실시간 알림/채팅(WebSocket, Fanout)

INSERT IGNORE INTO system_scenarios (
  id, track, title, difficulty, tags, version,
  context_json, requirements_json, constraints_json, traffic_json,
  submission_format_json, checklist_template_json, admin_notes_json
) VALUES (
  'SYS-REALTIME-NOTIFY-001',
  'system_practice',
  '실시간 알림/채팅(WebSocket/Fanout/Backpressure/재전송)',
  'medium',
  JSON_ARRAY('Realtime','WebSocket','Fanout','RateLimit','Observability','Fallback'),
  '1.0.0',
  JSON_OBJECT(
    'background', '서비스 내 알림/채팅 기능이 필요합니다. 동시 접속이 많고, 메시지 유실/지연이 사용자 경험에 직접 영향을 줍니다.',
    'goal', '대규모 동시 접속에서 실시간 전달을 안정적으로 제공하고, 장애 시에도 기능을 degrade할 수 있는 구조를 설계합니다.',
    'environment', 'WebSocket 기반. 모바일 네트워크 특성상 재연결이 잦고, 백프레셔(처리량 초과) 대응이 필요.'
  ),
  JSON_ARRAY(
    '인증/권한(채널 접근 제어, 사용자별 메시지 범위) 포함',
    '동시접속/팬아웃 고려(WebSocket gateway scale-out)',
    '메시지 유실 방지(ack/retry 또는 재전송 전략)',
    '관측성(p95 latency, error rate, trace id, dropped messages) 포함',
    '장애 시 fallback(폴링/푸시 큐잉 등) 전략 포함'
  ),
  JSON_ARRAY(
    '동시 접속 급증(피크)과 재연결이 빈번',
    '단일 컴포넌트 장애가 전체 중단으로 이어지지 않게(SPOF 최소화)',
    '비용 제약 존재(무한 스케일 불가)',
    '개인정보/메시지 접근 제어 필요'
  ),
  JSON_OBJECT(
    'users_total', 200000,
    'concurrent_connections_peak', 50000,
    'messages_per_sec_peak', 5000,
    'sla_p95_latency_ms', 300
  ),
  JSON_OBJECT(
    'required_artifacts', JSON_ARRAY('Mermaid','Tradeoffs','FailureMode','Observability'),
    'submit_fields', JSON_OBJECT(
      'mermaid', '접속/발송/저장/재전송 흐름이 보이게',
      'components', 'gateway/broker/storage 역할 요약',
      'tradeoffs', '최소 3개(장점/단점/대안)',
      'payload', 'failure_mode/observability/rate-limit/backpressure 요약'
    )
  ),
  JSON_OBJECT(
    'scoring', JSON_OBJECT(
      'weights', JSON_OBJECT(
        'auth_acl', 20,
        'bottleneck_spof', 25,
        'observability', 20,
        'failure_mode', 20,
        'rate_limit_backpressure', 15
      )
    ),
    'items', JSON_ARRAY(
      JSON_OBJECT('key','auth_acl','desc','인증/권한(ACL) 경계가 명확한가'),
      JSON_OBJECT('key','bottleneck_spof','desc','SPOF/병목 후보를 줄이는 설계 논리가 있는가'),
      JSON_OBJECT('key','observability','desc','지연/드랍/에러/trace를 측정 가능한가'),
      JSON_OBJECT('key','failure_mode','desc','브로커/게이트웨이 장애 시 대체 경로가 있는가'),
      JSON_OBJECT('key','rate_limit_backpressure','desc','레이트리밋/백프레셔 대응이 있는가')
    )
  ),
  JSON_OBJECT(
    'recommended_min_components', JSON_ARRAY(
      'API Gateway',
      'Auth Service',
      'WebSocket Gateway(Scale-out)',
      'Message Broker',
      'Notification/Chat Worker(Consumers)',
      'Message Store(DB)',
      'Cache/Presence Store(optional)',
      'Observability(Stack)'
    ),
    'admin_notes', JSON_ARRAY(
      'Mermaid에 단일 WebSocket Gateway만 있으면 SPOF 후보로 감점 가능(이중화/스케일아웃 표현 유도)',
      'Broker 단일/파티션 전략 언급 시 병목 논리 점수 부여',
      'fallback(폴링/큐잉/푸시 재시도) 키워드가 있으면 failure_mode 점수에 유리'
    )
  )
);

-- 확인
SELECT id, title, difficulty
FROM system_scenarios
ORDER BY created_at DESC;

