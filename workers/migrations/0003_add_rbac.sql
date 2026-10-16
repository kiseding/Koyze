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

-- Grant the admin role to every existing administrator.
--
-- These two seeds must be written as INSERT ... SELECT FROM users rather than
-- literal VALUES rows. On a brand-new database `users` is still empty at
-- migration time — the first admin is created later at runtime from
-- ADMIN_USERNAME / ADMIN_PASSWORD by seedAdminUser — and a literal
-- `VALUES (1, 'admin', ...)` would then fail with SQLITE_CONSTRAINT_FOREIGNKEY
-- ("FOREIGN KEY constraint failed"). `INSERT OR IGNORE` does NOT rescue it:
-- SQLite's ON CONFLICT clause does not apply to foreign key constraints.
INSERT OR IGNORE INTO user_roles (user_id, role, granted_at, granted_by)
SELECT id, 'admin', CAST(strftime('%s', 'now') AS INTEGER) * 1000, NULL
FROM users
WHERE role = 'admin';

-- Grant the baseline user role to every existing user (default for all users).
INSERT OR IGNORE INTO user_roles (user_id, role, granted_at, granted_by)
SELECT id, 'user', CAST(strftime('%s', 'now') AS INTEGER) * 1000, NULL
FROM users;
