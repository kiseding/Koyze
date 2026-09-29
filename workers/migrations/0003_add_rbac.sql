-- Migration 0003: Add RBAC and Audit Logging
-- Copyright 2024 Koyze Contributors
-- Licensed under the Apache License, Version 2.0

-- User roles table
CREATE TABLE IF NOT EXISTS user_roles (
  user_id INTEGER NOT NULL,
  role TEXT NOT NULL CHECK(role IN ('admin', 'user', 'readonly')),
  granted_at INTEGER NOT NULL,
  granted_by INTEGER,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  FOREIGN KEY (granted_by) REFERENCES users(id) ON DELETE SET NULL,
  PRIMARY KEY (user_id, role)
);

-- Audit logs table
CREATE TABLE IF NOT EXISTS audit_logs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL,
  action TEXT NOT NULL,
  resource_type TEXT,
  resource_id TEXT,
  ip_address TEXT,
  user_agent TEXT,
  created_at INTEGER NOT NULL,
  metadata TEXT,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

-- Indexes for audit logs
CREATE INDEX IF NOT EXISTS idx_audit_user ON audit_logs(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_action ON audit_logs(action, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_created_at ON audit_logs(created_at DESC);

-- Grant admin role to first user (user_id = 1)
INSERT OR IGNORE INTO user_roles (user_id, role, granted_at, granted_by)
VALUES (1, 'admin', strftime('%s', 'now') * 1000, NULL);

-- Grant user role to first user (default for all users)
INSERT OR IGNORE INTO user_roles (user_id, role, granted_at, granted_by)
VALUES (1, 'user', strftime('%s', 'now') * 1000, NULL);
