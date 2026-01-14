-- =========================================================
-- 01_schema.sql
-- DB 생성 + 테이블 생성
-- =========================================================

CREATE DATABASE IF NOT EXISTS Engineer_GYM
  DEFAULT CHARACTER SET utf8mb4
  DEFAULT COLLATE utf8mb4_0900_ai_ci;

USE Engineer_GYM;

-- 시나리오(문제)
CREATE TABLE IF NOT EXISTS system_scenarios (
  id VARCHAR(64) PRIMARY KEY,
  track VARCHAR(32) NOT NULL,
  title VARCHAR(255) NOT NULL,
  difficulty VARCHAR(16) NOT NULL,
  tags JSON NOT NULL,
  version VARCHAR(16) NOT NULL,

  context_json JSON NOT NULL,
  requirements_json JSON NOT NULL,
  constraints_json JSON NOT NULL,
  traffic_json JSON NOT NULL,
  submission_format_json JSON NOT NULL,
  checklist_template_json JSON NOT NULL,
  admin_notes_json JSON NULL,

  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE INDEX idx_system_scenarios_track ON system_scenarios(track);
CREATE INDEX idx_system_scenarios_difficulty ON system_scenarios(difficulty);

-- 제출(사용자 해답)
CREATE TABLE IF NOT EXISTS system_submissions (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  scenario_id VARCHAR(64) NOT NULL,
  user_id VARCHAR(64) NULL,

  mermaid_text LONGTEXT NOT NULL,
  components_text TEXT NULL,
  tradeoffs_json JSON NOT NULL,
  submission_payload_json JSON NOT NULL,

  status VARCHAR(16) NOT NULL DEFAULT 'submitted',
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT fk_system_submissions_scenario
    FOREIGN KEY (scenario_id) REFERENCES system_scenarios(id)
    ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE INDEX idx_system_submissions_scenario_id ON system_submissions(scenario_id);
CREATE INDEX idx_system_submissions_status ON system_submissions(status);
CREATE INDEX idx_system_submissions_created_at ON system_submissions(created_at);

-- 결과(채점/해설)
CREATE TABLE IF NOT EXISTS system_results (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  submission_id BIGINT NOT NULL,

  score_total INT NOT NULL,
  score_breakdown_json JSON NOT NULL,
  risk_flags_json JSON NOT NULL,

  alternative_mermaid_text LONGTEXT NULL,
  questions_json JSON NULL,
  coach_summary TEXT NULL,

  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT uq_system_results_submission UNIQUE (submission_id),
  CONSTRAINT fk_system_results_submission
    FOREIGN KEY (submission_id) REFERENCES system_submissions(id)
    ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE INDEX idx_system_results_created_at ON system_results(created_at);

-- 확인
SHOW TABLES;
