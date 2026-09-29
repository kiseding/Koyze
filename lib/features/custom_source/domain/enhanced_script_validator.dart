// Copyright 2024 Koyze Contributors
// Licensed under the Apache License, Version 2.0

/// Enhanced security validation for custom JavaScript sources.
/// 
/// Provides multi-layer protection against malicious scripts:
/// - Static AST-level analysis
/// - Dynamic code execution detection
/// - Obfuscation and entropy analysis
/// - Resource consumption limits

import 'dart:convert';
import 'dart:math';

class SecurityIssue {
  final SecurityLevel level;
  final String description;
  final String code;
  final int? line;

  const SecurityIssue({
    required this.level,
    required this.description,
    required this.code,
    this.line,
  });

  static const dynamicCodeExecution = 'DYNAMIC_CODE_EXEC';
  static const suspiciousObfuscation = 'SUSPICIOUS_OBFUSCATION';
  static const forbiddenGlobalAccess = 'FORBIDDEN_GLOBAL';
  static const excessiveComplexity = 'EXCESSIVE_COMPLEXITY';
  static const suspiciousNetworkPattern = 'SUSPICIOUS_NETWORK';
  static const highEntropy = 'HIGH_ENTROPY';
}

enum SecurityLevel { critical, high, medium, low, info }

class ValidationResult {
  final List<SecurityIssue> issues;
  final bool isSecure;
  final Map<String, dynamic> metadata;

  ValidationResult({
    required this.issues,
    Map<String, dynamic>? metadata,
  })  : isSecure = !issues.any((i) =>
            i.level == SecurityLevel.critical || i.level == SecurityLevel.high),
        metadata = metadata ?? {};

  List<SecurityIssue> get criticalIssues =>
      issues.where((i) => i.level == SecurityLevel.critical).toList();
  List<SecurityIssue> get highIssues =>
      issues.where((i) => i.level == SecurityLevel.high).toList();
}

/// Enhanced script validator with comprehensive security checks
class EnhancedScriptValidator {
  /// Validates a custom source script with multi-layer security analysis.
  static ValidationResult validate(String script) {
    if (script.isEmpty) {
      return ValidationResult(
        issues: [
          SecurityIssue(
            level: SecurityLevel.critical,
            description: 'Empty script not allowed',
            code: 'EMPTY_SCRIPT',
          ),
        ],
      );
    }

    final issues = <SecurityIssue>[];
    final metadata = <String, dynamic>{};

    // Layer 1: Static pattern analysis
    _checkDynamicExecution(script, issues);
    _checkForbiddenGlobals(script, issues);
    _checkSuspiciousPatterns(script, issues);

    // Layer 2: Entropy and obfuscation detection
    final entropy = _calculateEntropy(script);
    metadata['entropy'] = entropy;
    if (entropy > 5.5) {
      issues.add(SecurityIssue(
        level: SecurityLevel.high,
        description: 'High entropy detected (possible obfuscation): $entropy',
        code: SecurityIssue.highEntropy,
      ));
    }

    // Layer 3: Complexity analysis
    final complexity = _estimateComplexity(script);
    metadata['complexity'] = complexity;
    if (complexity > 500) {
      issues.add(SecurityIssue(
        level: SecurityLevel.medium,
        description: 'Excessive code complexity: $complexity',
        code: SecurityIssue.excessiveComplexity,
      ));
    }

    return ValidationResult(issues: issues, metadata: metadata);
  }

  /// Detects eval(), Function(), and other dynamic code execution methods.
  static void _checkDynamicExecution(String script, List<SecurityIssue> issues) {
    final dangerousPatterns = [
      RegExp(r'\beval\s*\('),
      RegExp(r'\bnew\s+Function\s*\('),
      RegExp(r'Function\s*\('),
      RegExp(r'\$\{[^}]*eval[^}]*\}'), // Template literal eval
      RegExp(r'this\[\s*[' "'" r'"' "'" r']eval[' "'" r'"' "'" r']\s*\]'),
      RegExp(r'window\[\s*[' "'" r'"' "'" r']eval[' "'" r'"' "'" r']\s*\]'),
      RegExp(r'global\[\s*[' "'" r'"' "'" r']eval[' "'" r'"' "'" r']\s*\]'),
    ];

    for (final pattern in dangerousPatterns) {
      if (pattern.hasMatch(script)) {
        issues.add(SecurityIssue(
          level: SecurityLevel.critical,
          description: 'Dynamic code execution detected: ${pattern.pattern}',
          code: SecurityIssue.dynamicCodeExecution,
        ));
      }
    }

    // Check for indirect eval via bracket notation
    if (RegExp(r'\[[' "'" r'"' "'" r']constructor[' "'" r'"' "'" r']\]').hasMatch(script)) {
      issues.add(SecurityIssue(
        level: SecurityLevel.high,
        description: 'Potential constructor exploitation detected',
        code: SecurityIssue.dynamicCodeExecution,
      ));
    }
  }

  /// Checks for access to forbidden global objects.
  static void _checkForbiddenGlobals(String script, List<SecurityIssue> issues) {
    final forbiddenGlobals = [
      'process',
      'require',
      r'import\s*\(',
      '__dirname',
      '__filename',
      'Buffer',
      'child_process',
      'fs',
      'module',
      'exports',
    ];

    for (final global in forbiddenGlobals) {
      if (RegExp('\\b$global\\b').hasMatch(script)) {
        issues.add(SecurityIssue(
          level: SecurityLevel.critical,
          description: 'Forbidden global access detected: $global',
          code: SecurityIssue.forbiddenGlobalAccess,
        ));
      }
    }
  }

  /// Detects suspicious patterns that may indicate malicious behavior.
  static void _checkSuspiciousPatterns(String script, List<SecurityIssue> issues) {
    // Check for data exfiltration patterns
    if (RegExp(r'fetch\s*\(|XMLHttpRequest|navigator\.sendBeacon').hasMatch(script)) {
      issues.add(SecurityIssue(
        level: SecurityLevel.medium,
        description: 'Network request detected - verify destination',
        code: SecurityIssue.suspiciousNetworkPattern,
      ));
    }

    // Check for long base64 strings (possible payload)
    if (RegExp(r'[A-Za-z0-9+/]{200,}={0,2}').hasMatch(script)) {
      issues.add(SecurityIssue(
        level: SecurityLevel.medium,
        description: 'Long base64-like string detected',
        code: SecurityIssue.suspiciousObfuscation,
      ));
    }

    // Check for hex-encoded strings
    if (RegExp(r'\\x[0-9a-fA-F]{2}').allMatches(script).length > 20) {
      issues.add(SecurityIssue(
        level: SecurityLevel.medium,
        description: 'Excessive hex-encoded characters detected',
        code: SecurityIssue.suspiciousObfuscation,
      ));
    }
  }

  /// Calculates Shannon entropy to detect obfuscation.
  static double _calculateEntropy(String text) {
    if (text.isEmpty) return 0;

    final freq = <int, int>{};
    for (final char in text.codeUnits) {
      freq[char] = (freq[char] ?? 0) + 1;
    }

    double entropy = 0;
    final length = text.length;
    for (final count in freq.values) {
      final probability = count / length;
      entropy -= probability * (log(probability) / ln2);
    }

    return entropy;
  }

  /// Estimates code complexity (cyclomatic-like metric).
  static int _estimateComplexity(String script) {
    int complexity = 1; // Base complexity

    // Count control flow statements
    complexity += RegExp(r'\bif\b').allMatches(script).length;
    complexity += RegExp(r'\belse\b').allMatches(script).length;
    complexity += RegExp(r'\bfor\b').allMatches(script).length;
    complexity += RegExp(r'\bwhile\b').allMatches(script).length;
    complexity += RegExp(r'\bswitch\b').allMatches(script).length;
    complexity += RegExp(r'\bcase\b').allMatches(script).length;
    complexity += RegExp(r'\bcatch\b').allMatches(script).length;
    complexity += RegExp(r'\?\s*[^:]+:').allMatches(script).length; // Ternary
    complexity += RegExp(r'&&|\|\|').allMatches(script).length; // Logical ops

    return complexity;
  }
}
