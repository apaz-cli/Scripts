#!/bin/sh
set -e

# Ensure we have required API keys
if [ -z "$ANTHROPIC_API_KEY" ] || [ -z "$DEEPSEEK_API_KEY" ]; then
    echo "Missing required API keys in environment variables"
    echo "Need: ANTHROPIC_API_KEY, DEEPSEEK_API_KEY"
    exit 1
fi

run_test() {
    name="$1"
    setup="$2"
    query="$3"
    verify="$4"

    echo "Running test: $name"

    # Create test directory
    test_dir="/tmp/aoe_test_${name}"
    rm -rf "$test_dir"
    mkdir -p "$test_dir"
    cd "$test_dir"

    # Run setup
    eval "$setup"

    # Run aoe
    aoe "$query"

    # Verify results
    if eval "$verify"; then
        echo "✓ Test passed: $name"
        return 0
    else
        echo "✗ Test failed: $name"
        return 1
    fi
}

# Test 1: Basic variable rename
run_test "basic_rename" '
    cat > test.py << EOF
x = 42
print(x)
y = x + 1
EOF
' \
"rename variable x to counter" \
'grep -q "counter = 42" test.py && grep -q "print(counter)" test.py'

# Test 2: Comment updates
run_test "comment_updates" '
    cat > main.py << EOF
# x is the main counter variable
x = 0
# increment x
x += 1
EOF
' \
"rename variable x to counter" \
'grep -q "# counter is the main counter variable" main.py && grep -q "# increment counter" main.py'

# Test 3: Multi-file consistency
run_test "multi_file" '
    cat > a.py << EOF
value = 42
EOF
    cat > b.py << EOF
from a import value
print(value)
EOF
' \
"rename variable value to result" \
'grep -q "result = 42" a.py && grep -q "from a import result" b.py'

# Test 4: Partial updates
run_test "partial_updates" '
    cat > test.py << EOF
# This is a test
x = 1
# This uses x
y = x + 1
# This is unrelated
z = 42
EOF
' \
"rename variable x to counter" \
'grep -q "counter = 1" test.py && grep -q "y = counter + 1" test.py && grep -q "z = 42" test.py'

# Test 5: Multiple file types
run_test "file_types" '
    cat > test.py << EOF
x = 42
EOF
    cat > test.js << EOF
let x = 42;
EOF
    cat > test.ts << EOF
let x: number = 42;
EOF
' \
"rename variable x to counter" \
'grep -q "counter = 42" test.py && grep -q "let counter = 42;" test.js && grep -q "let counter: number = 42;" test.ts'

# Test 6: Whitespace preservation
run_test "whitespace" '
    cat > test.py << EOF

def func():
    x = 42
    return x

EOF
' \
"rename variable x to counter" \
'diff -u <(echo -e "\ndef func():\n    counter = 42\n    return counter\n") test.py'

# Test 7: Empty/invalid files
run_test "empty_files" '
    touch empty.py
    echo "invalid python" > invalid.py
' \
"rename variable x to counter" \
'[ -f empty.py ] && [ -f invalid.py ]'

# Run all tests
echo "Running all tests..."
failed=0
for test in basic_rename comment_updates multi_file partial_updates file_types whitespace empty_files; do
    if ! run_test "$test" "$(eval "echo \$$test")" "$(eval "echo \$${test}_query")" "$(eval "echo \$${test}_verify")"; then
        failed=$((failed + 1))
    fi
done

if [ "$failed" -eq 0 ]; then
    echo "All tests passed!"
    exit 0
else
    echo "$failed test(s) failed"
    exit 1
fi
