CREATE TABLE users (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL CHECK(length(trim(name)) BETWEEN 1 AND 80),
  role TEXT NOT NULL CHECK(role IN ('bendahara','ketua','guruWali','siswa')),
  active INTEGER NOT NULL DEFAULT 1 CHECK(active IN (0,1))
);
-- @statement
CREATE TABLE monthly_reports (
  period TEXT PRIMARY KEY CHECK(length(period)=7 AND substr(period,6,2) BETWEEN '01' AND '12'),
  approved_by TEXT REFERENCES users(id),
  approved_at TEXT,
  verified_by TEXT REFERENCES users(id),
  verified_at TEXT,
  CHECK((approved_by IS NULL) = (approved_at IS NULL)),
  CHECK((verified_by IS NULL) = (verified_at IS NULL)),
  CHECK(verified_by IS NULL OR approved_by IS NOT NULL)
);
-- @statement
CREATE TABLE monthly_total_targets (
  period TEXT PRIMARY KEY CHECK(length(period)=7 AND substr(period,6,2) BETWEEN '01' AND '12'),
  amount INTEGER NOT NULL CHECK(typeof(amount)='integer' AND amount BETWEEN 0 AND 1000000000000)
);
-- @statement
CREATE TABLE transactions (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  amount INTEGER NOT NULL CHECK(typeof(amount)='integer' AND amount BETWEEN 1 AND 1000000000000),
  type TEXT NOT NULL CHECK(type IN ('IN','OUT')),
  category TEXT NOT NULL CHECK(length(trim(category)) BETWEEN 1 AND 80),
  contributor_id TEXT REFERENCES users(id),
  tx_date TEXT NOT NULL CHECK(length(tx_date)=10 AND date(tx_date,'+0 days') IS NOT NULL AND date(tx_date,'+0 days')=tx_date),
  description TEXT NOT NULL CHECK(length(trim(description)) BETWEEN 1 AND 1000),
  created_by TEXT NOT NULL REFERENCES users(id),
  created_at TEXT NOT NULL,
  fingerprint TEXT NOT NULL,
  submission_id TEXT NOT NULL UNIQUE
);
-- @statement
CREATE INDEX idx_tx_date ON transactions(tx_date DESC,id DESC);
-- @statement
CREATE INDEX idx_tx_category ON transactions(category,tx_date);
-- @statement
CREATE INDEX idx_tx_contributor_date ON transactions(contributor_id,tx_date);
-- @statement
CREATE INDEX idx_tx_fingerprint ON transactions(fingerprint);
-- @statement
CREATE TABLE audit_log (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  actor TEXT NOT NULL REFERENCES users(id),
  action TEXT NOT NULL,
  target TEXT NOT NULL,
  at TEXT NOT NULL
);
-- @statement
CREATE TRIGGER tx_insert_role BEFORE INSERT ON transactions
WHEN NOT EXISTS (SELECT 1 FROM users WHERE id=NEW.created_by AND active=1 AND role='bendahara')
BEGIN SELECT RAISE(ABORT,'ERR_RBAC_DENIED'); END;
-- @statement
CREATE TRIGGER tx_insert_locked BEFORE INSERT ON transactions
WHEN EXISTS (SELECT 1 FROM monthly_reports WHERE period=substr(NEW.tx_date,1,7) AND approved_by IS NOT NULL)
BEGIN SELECT RAISE(ABORT,'ERR_PERIOD_LOCKED'); END;
-- @statement
CREATE TRIGGER tx_delete_locked BEFORE DELETE ON transactions
WHEN EXISTS (SELECT 1 FROM monthly_reports WHERE period=substr(OLD.tx_date,1,7) AND approved_by IS NOT NULL)
BEGIN SELECT RAISE(ABORT,'ERR_PERIOD_LOCKED'); END;
-- @statement
CREATE TRIGGER tx_no_update BEFORE UPDATE ON transactions
BEGIN SELECT RAISE(ABORT,'ERR_IMMUTABLE_TRANSACTION'); END;
-- @statement
CREATE TRIGGER report_insert_role BEFORE INSERT ON monthly_reports
WHEN NEW.approved_by IS NOT NULL AND NOT EXISTS (SELECT 1 FROM users WHERE id=NEW.approved_by AND role='ketua' AND active=1)
BEGIN SELECT RAISE(ABORT,'ERR_RBAC_DENIED'); END;
-- @statement
CREATE TRIGGER report_approval_role BEFORE UPDATE OF approved_by ON monthly_reports
WHEN NEW.approved_by IS NOT NULL AND NOT EXISTS (SELECT 1 FROM users WHERE id=NEW.approved_by AND role='ketua' AND active=1)
BEGIN SELECT RAISE(ABORT,'ERR_RBAC_DENIED'); END;
-- @statement
CREATE TRIGGER report_verification_role BEFORE UPDATE OF verified_by ON monthly_reports
WHEN NEW.verified_by IS NOT NULL AND NOT EXISTS (SELECT 1 FROM users WHERE id=NEW.verified_by AND role='guruWali' AND active=1)
BEGIN SELECT RAISE(ABORT,'ERR_RBAC_DENIED'); END;
-- @statement
CREATE TRIGGER report_no_unlock BEFORE UPDATE ON monthly_reports
WHEN OLD.approved_by IS NOT NULL AND (NEW.approved_by IS NOT OLD.approved_by OR NEW.approved_at IS NOT OLD.approved_at)
BEGIN SELECT RAISE(ABORT,'ERR_PERIOD_LOCKED'); END;
-- @statement
CREATE TRIGGER report_no_delete BEFORE DELETE ON monthly_reports
WHEN OLD.approved_by IS NOT NULL
BEGIN SELECT RAISE(ABORT,'ERR_PERIOD_LOCKED'); END;
-- @statement
CREATE TRIGGER report_no_reverify BEFORE UPDATE ON monthly_reports
WHEN OLD.verified_by IS NOT NULL
BEGIN SELECT RAISE(ABORT,'ERR_REPORT_VERIFIED'); END;
