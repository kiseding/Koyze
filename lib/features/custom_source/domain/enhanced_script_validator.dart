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

class EnhancedSourceScriptValidator {
  static const int MAX_SCRIPT_SIZE = 2 * 1024 * 1024; // 2MB
  static const int MAX_LINES = 50000;
  static const double HIGH_ENTROPY_THRESHOLD = 4.5; // bits per byte
  static const int MAX_NESTING_DEPTH = 20;

  /// Validates a custom source script with comprehensive security checks.
  static ValidationResult validate(String script) {
    final issues = <SecurityIssue>[];
    final metadata = <String, dynamic>{};

    // 1. Basic size and format checks
    if (script.length > MAX_SCRIPT_SIZE) {
      issues.add(SecurityIssue(
        level: SecurityLevel.critical,
        description: 'Script exceeds maximum size of ${MAX_SCRIPT_SIZE ~/ 1024}KB',
        code: SecurityIssue.excessiveComplexity,
      ));
      return ValidationResult(issues: issues, metadata: metadata);
    }

    final lines = script.split('\n');
    if (lines.length > MAX_LINES) {
      issues.add(SecurityIssue(
        level: SecurityLevel.high,
        description: 'Script exceeds maximum line count of $MAX_LINES',
        code: SecurityIssue.excessiveComplexity,
      ));
    }

    metadata['size'] = script.length;
    metadata['lines'] = lines.length;

    // 2. Dynamic code execution detection
    _checkDynamicExecution(script, issues);

    // 3. Forbidden global access
    _checkForbiddenGlobals(script, issues);

    // 4. Obfuscation detection
    _checkObfuscation(script, issues, metadata);

    // 5. Entropy analysis (detect encrypted/packed code)
    final entropy = _calculateEntropy(script);
    metadata['entropy'] = entropy;
    if (entropy > HIGH_ENTROPY_THRESHOLD) {
      issues.add(SecurityIssue(
        level: SecurityLevel.high,
        description: 'High entropy ($entropy) suggests encrypted or packed code',
        code: SecurityIssue.highEntropy,
      ));
    }

    // 6. Suspicious network patterns
    _checkSuspiciousNetworkPatterns(script, issues);

    // 7. Complexity analysis
    final nestingDepth = _calculateMaxNestingDepth(script);
    metadata['maxNestingDepth'] = nestingDepth;
    if (nestingDepth > MAX_NESTING_DEPTH) {
      issues.add(SecurityIssue(
        level: SecurityLevel.medium,
        description: 'Excessive nesting depth ($nestingDepth) may indicate obfuscation',
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
      RegExp(r'this\[\s*["\']eval["\']\s*\]'),
      RegExp(r'window\[\s*["\']eval["\']\s*\]'),
      RegExp(r'global\[\s*["\']eval["\']\s*\]'),
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
    if (RegExp(r'\[["\']constructor["\']\]').hasMatch(script)) {
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
      'import\\s*\\(',
      '__dirname',
      '__filename',
      'Buffer',
      'child_process',
      'fs',
      'path',
      'os',
      'net',
      'http',
      'https',
      'dns',
    ];

    for (final global in forbiddenGlobals) {
      final pattern = RegExp('\\b$global\\b');
      if (pattern.hasMatch(script)) {
        issues.add(SecurityIssue(
          level: SecurityLevel.critical,
          description: 'Forbidden global access: $global',
          code: SecurityIssue.forbiddenGlobalAccess,
        ));
      }
    }
  }

  /// Detects code obfuscation patterns.
  static void _checkObfuscation(
    String script,
    List<SecurityIssue> issues,
    Map<String, dynamic> metadata,
  ) {
    // Pattern 1: Excessive unicode escapes
    final unicodeEscapes = RegExp(r'\\u[0-9a-fA-F]{4}').allMatches(script).length;
    metadata['unicodeEscapes'] = unicodeEscapes;
    if (unicodeEscapes > 50) {
      issues.add(SecurityIssue(
        level: SecurityLevel.medium,
        description: 'Excessive unicode escapes ($unicodeEscapes) may indicate obfuscation',
        code: SecurityIssue.suspiciousObfuscation,
      ));
    }

    // Pattern 2: Hex encoded strings
    final hexStrings = RegExp(r'\\x[0-9a-fA-F]{2}').allMatches(script).length;
    metadata['hexStrings'] = hexStrings;
    if (hexStrings > 50) {
      issues.add(SecurityIssue(
        level: SecurityLevel.medium,
        description: 'Excessive hex-encoded strings ($hexStrings)',
        code: SecurityIssue.suspiciousObfuscation,
      ));
    }

    // Pattern 3: Suspicious string splitting/joining
    if (RegExp(r'\.split\(["\']["\']?\)\.reverse\(\)\.join\(').hasMatch(script)) {
      issues.add(SecurityIssue(
        level: SecurityLevel.medium,
        description: 'String reversal pattern detected (common in obfuscation)',
        code: SecurityIssue.suspiciousObfuscation,
      ));
    }

    // Pattern 4: Excessive use of bracket notation
    final bracketNotation = RegExp(r'\[["\'][^"\']+["\']\]').allMatches(script).length;
    final identifiers = RegExp(r'\b[a-zA-Z_$][a-zA-Z0-9_$]*\b').allMatches(script).length;
    if (identifiers > 0 && bracketNotation / identifiers > 0.3) {
      issues.add(SecurityIssue(
        level: SecurityLevel.medium,
        description: 'Excessive bracket notation usage (${(bracketNotation / identifiers * 100).toStringAsFixed(1)}%)',
        code: SecurityIssue.suspiciousObfuscation,
      ));
    }

    // Pattern 5: Suspicious character sequences
    if (RegExp(r'[!+\[\]]{10,}').hasMatch(script)) {
      issues.add(SecurityIssue(
        level: SecurityLevel.high,
        description: 'JSFuck-style obfuscation detected',
        code: SecurityIssue.suspiciousObfuscation,
      ));
    }
  }

  /// Calculates Shannon entropy to detect encrypted/packed code.
  static double _calculateEntropy(String text) {
    if (text.isEmpty) return 0.0;

    final frequency = <int, int>{};
    for (var i = 0; i < text.length; i++) {
      final code = text.codeUnitAt(i);
      frequency[code] = (frequency[code] ?? 0) + 1;
    }

    double entropy = 0.0;
    final length = text.length;

    for (final count in frequency.values) {
      final probability = count / length;
      entropy -= probability * (log(probability) / ln2);
    }

    return entropy;
  }

  /// Detects suspicious network request patterns.
  static void _checkSuspiciousNetworkPatterns(
    String script,
    List<SecurityIssue> issues,
  ) {
    // Pattern 1: Base64 encoded URLs
    if (RegExp(r'atob\s*\(').hasMatch(script) &&
        RegExp(r'https?[:;]').hasMatch(script)) {
      issues.add(SecurityIssue(
        level: SecurityLevel.high,
        description: 'Base64 decoding near URL patterns (potential hidden endpoint)',
        code: SecurityIssue.suspiciousNetworkPattern,
      ));
    }

    // Pattern 2: IP address literals (non-standard for music APIs)
    if (RegExp(r'\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b').hasMatch(script)) {
      issues.add(SecurityIssue(
        level: SecurityLevel.medium,
        description: 'IP address literals detected',
        code: SecurityIssue.suspiciousNetworkPattern,
      ));
    }

    // Pattern 3: Suspicious TLDs
    final suspiciousTlds = ['.tk', '.ml', '.ga', '.cf', '.gq', '.xyz', '.top'];
    for (final tld in suspiciousTlds) {
      if (script.contains(tld)) {
        issues.add(SecurityIssue(
          level: SecurityLevel.medium,
          description: 'Suspicious TLD detected: $tld',
          code: SecurityIssue.suspiciousNetworkPattern,
        ));
      }
    }

    // Pattern 4: Data exfiltration patterns
    if (RegExp(r'new\s+Image\s*\(').hasMatch(script) &&
        RegExp(r'\.src\s*=').hasMatch(script)) {
      issues.add(SecurityIssue(
        level: SecurityLevel.high,
        description: 'Image beacon pattern (potential data exfiltration)',
        code: SecurityIssue.suspiciousNetworkPattern,
      ));
    }
  }

  /// Calculates maximum nesting depth (braces, brackets, parens).
  static int _calculateMaxNestingDepth(String script) {
    int maxDepth = 0;
    int currentDepth = 0;

    final openChars = {'{', '[', '('};
    final closeChars = {'}', ']', ')'};

    for (var i = 0; i < script.length; i++) {
      final char = script[i];
      if (openChars.contains(char)) {
        currentDepth++;
        if (currentDepth > maxDepth) {
          maxDepth = currentDepth;
        }
      } else if (closeChars.contains(char)) {
        currentDepth = max(0, currentDepth - 1);
      }
    }

    return maxDepth;
  }
}
