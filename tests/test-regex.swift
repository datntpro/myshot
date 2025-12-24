// Test script for SensitiveDataDetector regex patterns
import Foundation

// Sample data to test detection patterns
let testCases = [
    // Credit Cards
    ("4111111111111111", "Visa"),
    ("5500000000000004", "Mastercard"),
    ("340000000000009", "Amex"),
    ("6011000000000004", "Discover"),
    ("4111-1111-1111-1111", "Visa with dashes"),
    ("4111 1111 1111 1111", "Visa with spaces"),
    
    // API Keys
    ("FAKE_STRIPE_LIVE_KEY_0000000000000000", "Stripe Live Key"),
    ("FAKE_STRIPE_TEST_KEY_0000000000000000", "Stripe Test Key"),
    ("ghp_1234567890abcdefghijklmnopqrstuvwxyz", "GitHub Token"),
    ("sk-proj-1234567890abcdefghijklmnopqrstuvwxyzABCDEFGH", "OpenAI Key"),
    ("AKIAIOSFODNN7EXAMPLE", "AWS Access Key"),
    ("api_key: sk-1234567890abcdef12345678", "Generic API Key"),
    
    // Passwords
    ("password: mysecretpass123", "Password field"),
    ("pwd=supersecret!", "PWD field"),
    ("\"password\": \"hunter2\"", "JSON password"),
]

// Credit card regex patterns
let ccPatterns = [
    #"4[0-9]{12}(?:[0-9]{3})?"#,
    #"5[1-5][0-9]{14}"#,
    #"3[47][0-9]{13}"#,
    #"6(?:011|22[1-9]|[45][0-9]{2})[0-9]{12}"#,
    #"\b(?:\d{4}[-\s]?){3}\d{4}\b"#,
]

// API key patterns
let apiPatterns = [
    #"sk_live_[a-zA-Z0-9]{24,}"#,
    #"sk_test_[a-zA-Z0-9]{24,}"#,
    #"ghp_[a-zA-Z0-9]{36}"#,
    #"sk-proj-[a-zA-Z0-9]{48}"#,
    #"(?:A3T[A-Z0-9]|AKIA|AGPA|AIDA|AROA|AIPA|ANPA|ANVA|ASIA)[A-Z0-9]{16}"#,
    #"(?i)(api[_-]?key|apikey)['\"]?\s*[:=]\s*['\"]?[a-zA-Z0-9_\-]{20,}['\"]?"#,
]

// Password patterns
let pwdPatterns = [
    #"(?i)(password|passwd|pwd|pass)\s*[:=]\s*['\"]?[^\s'\",]{4,}['\"]?"#,
    #"(?i)['\"]password['\"]\s*:\s*['\"][^'\"]+['\"]"#,
]

func testPattern(_ pattern: String, against text: String) -> Bool {
    do {
        let regex = try NSRegularExpression(pattern: pattern, options: [])
        let range = NSRange(text.startIndex..., in: text)
        return regex.firstMatch(in: text, options: [], range: range) != nil
    } catch {
        return false
    }
}

// Luhn algorithm for credit card validation
func isValidLuhn(_ number: String) -> Bool {
    let digits = number.filter { $0.isNumber }
    guard digits.count >= 13 && digits.count <= 19 else { return false }
    
    var sum = 0
    let reversedDigits = digits.reversed().map { Int(String($0)) ?? 0 }
    
    for (index, digit) in reversedDigits.enumerated() {
        if index % 2 == 1 {
            let doubled = digit * 2
            sum += doubled > 9 ? doubled - 9 : doubled
        } else {
            sum += digit
        }
    }
    
    return sum % 10 == 0
}

print("🧪 Testing SensitiveDataDetector Patterns")
print("==========================================\n")

var passed = 0
var failed = 0

for (input, description) in testCases {
    var matched = false
    var matchType = ""
    
    // Test credit card patterns
    for pattern in ccPatterns {
        if testPattern(pattern, against: input) {
            matched = true
            matchType = "Credit Card"
            break
        }
    }
    
    // Test API key patterns
    if !matched {
        for pattern in apiPatterns {
            if testPattern(pattern, against: input) {
                matched = true
                matchType = "API Key"
                break
            }
        }
    }
    
    // Test password patterns
    if !matched {
        for pattern in pwdPatterns {
            if testPattern(pattern, against: input) {
                matched = true
                matchType = "Password"
                break
            }
        }
    }
    
    // Validate credit cards with Luhn
    let digitsOnly = input.filter { $0.isNumber }
    let luhnValid = digitsOnly.count >= 13 ? isValidLuhn(input) : true
    
    if matched && luhnValid {
        print("✅ PASS: \(description)")
        print("   Input: \(input)")
        print("   Detected as: \(matchType)\n")
        passed += 1
    } else {
        print("❌ FAIL: \(description)")
        print("   Input: \(input)")
        print("   Matched: \(matched), Luhn: \(luhnValid)\n")
        failed += 1
    }
}

print("==========================================")
print("Results: \(passed) passed, \(failed) failed")
print("==========================================")
