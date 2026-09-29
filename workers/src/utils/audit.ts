// Copyright 2024 Koyze Contributors
// Licensed under the Apache License, Version 2.0

/**
 * Audit logging service for tracking user actions
 */

import type { Env } from '../index';

export interface AuditEntry {
  userId: number;
  action: string;
  resourceType?: string;
  resourceId?: string;
  metadata?: Record<string, unknown>;
}

export async function logAudit(
  env: Env,
  entry: AuditEntry,
  request: Request,
): Promise<void> {
  const ip = request.headers.get('CF-Connecting-IP') || 'unknown';
  const userAgent = request.headers.get('User-Agent') || 'unknown';
  
  try {
    await env.DB.prepare(`
      INSERT INTO audit_logs (
        user_id, action, resource_type, resource_id,
        ip_address, user_agent, created_at, metadata
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    `).bind(
      entry.userId,
      entry.action,
      entry.resourceType || null,
      entry.resourceId || null,
      ip,
      userAgent.slice(0, 200),
      Date.now(),
      JSON.stringify(entry.metadata || {}),
    ).run();
  } catch (error) {
    console.error('Failed to log audit entry:', error);
    // Don't fail the request if audit logging fails
  }
}

export async function hasRole(
  env: Env,
  userId: number,
  role: 'admin' | 'user' | 'readonly',
): Promise<boolean> {
  const result = await env.DB.prepare(`
    SELECT 1 FROM user_roles
    WHERE user_id = ? AND role = ?
  `).bind(userId, role).first();
  
  return result !== null;
}

export async function getUserRoles(
  env: Env,
  userId: number,
): Promise<string[]> {
  const result = await env.DB.prepare(`
    SELECT role FROM user_roles
    WHERE user_id = ?
  `).bind(userId).all();
  
  return result.results.map((r: any) => r.role);
}

export async function grantRole(
  env: Env,
  userId: number,
  role: 'admin' | 'user' | 'readonly',
  grantedBy: number,
): Promise<void> {
  await env.DB.prepare(`
    INSERT OR IGNORE INTO user_roles (user_id, role, granted_at, granted_by)
    VALUES (?, ?, ?, ?)
  `).bind(userId, role, Date.now(), grantedBy).run();
}

export async function revokeRole(
  env: Env,
  userId: number,
  role: 'admin' | 'user' | 'readonly',
): Promise<void> {
  await env.DB.prepare(`
    DELETE FROM user_roles
    WHERE user_id = ? AND role = ?
  `).bind(userId, role).run();
}
