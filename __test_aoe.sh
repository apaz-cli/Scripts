#!/bin/bash

# Function to handle errors
handle_error() {
    echo "ERROR: $1"
    cd /
    rm -rf "$TEST_DIR"
    exit 1
}

# Create temp test directory
TEST_DIR=$(mktemp -d) || handle_error "Failed to create temp directory"
cd "$TEST_DIR" || handle_error "Failed to change to temp directory"

echo "Using test directory: $TEST_DIR"

# Copy aoe scripts to test directory
cp ../aoe ../_aoe . || handle_error "Failed to copy aoe scripts"
chmod +x aoe _aoe || handle_error "Failed to make scripts executable"

# Create test files and directories
mkdir -p src/nested || handle_error "Failed to create test folders"

# Create a Python test file
cat > src/vector.py << 'EOF'
class Vector:
    def __init__(self, x, y):
        self.x = x
        self.y = y

    def add(self, other):
        return Vector(
            self.x + other.x,
            self.y + other.y
        )

    def scale(self, factor):
        return Vector(
            self.x * factor,
            self.y * factor
        )
EOF

# Create a JavaScript test file
cat > src/nested/math.js << 'EOF'
// Vector operations
function createVector(x, y) {
    return {x, y};
}

function addVectors(a, b) {
    return {
        x: a.x + b.x,
        y: a.y + b.y
    };
}

// Example usage:
// let v = createVector(3, 4);
EOF

# Create a file with show directives
cat > src/show_test.py << 'EOF'
--show--
def important_function():
    return 42

def helper():
    return 21
EOF

# Create a file with Unicode content
cat > src/unicode_test.py << 'EOF'
# 日本語コメント
def greet():
    return "こんにちは"
EOF

# Create read-only file
cat > src/readonly.py << 'EOF'
def constant():
    return 3.14159
EOF
chmod 444 src/readonly.py

# Create symlink
ln -s vector.py src/vector_link.py

# Create .aoe.json config
cat > .aoe.json << 'EOF'
{
    "path": "src"
}
EOF

echo
echo "=== Testing basic functionality ==="

echo "Testing installation..."
rm -rf /tmp/aoe || handle_error "Failed to remove existing aoe directory"
./aoe "test query" || handle_error "Failed basic aoe execution"

echo
echo "=== Testing model combinations ==="

echo "Testing with Deepseek picker and Claude editor..."
./aoe "convert vectors to use arrays instead of objects" "d" "c" || handle_error "Failed model combination test"

echo "Testing with Claude picker and Deepseek editor..."
./aoe "add type hints to Python functions" "c" "d" || handle_error "Failed reversed model combination test"

echo
echo "=== Testing configuration ==="

echo "Testing without config..."
mv .aoe.json .aoe.json.bak
./aoe "simple query" || handle_error "Failed no config test"
mv .aoe.json.bak .aoe.json

echo "Testing with invalid config..."
echo "{invalid json}" > .aoe.json
./aoe "simple query" || handle_error "Failed invalid config test"
echo '{"path": "src"}' > .aoe.json

echo
echo "=== Testing chunk processing ==="

echo "Testing empty file..."
touch src/empty.py
./aoe "modify empty file" || handle_error "Failed empty file test"

echo "Testing show directives..."
./aoe "modify only shown function" || handle_error "Failed show directive test"

echo "Testing different comment styles..."
echo "# Python comment" > src/comments.py
echo "// JavaScript comment" > src/comments.js
echo "-- Haskell comment" > src/comments.hs
./aoe "update comments" || handle_error "Failed comment style test"

echo
echo "=== Testing parallel vs sequential ==="

# Create many small files for parallel testing
for i in {1..10}; do
    echo "def func_${i}(): return ${i}" > "src/test_${i}.py"
done

echo "Testing parallel execution..."
export PARALLEL=true
./aoe "add docstrings" || handle_error "Failed parallel execution test"

echo "Testing sequential execution..."
export PARALLEL=false
./aoe "add docstrings" || handle_error "Failed sequential execution test"

echo
echo "=== Testing error handling ==="

echo "Testing invalid model selection..."
if ./aoe "test query" "invalid_model" 2>/dev/null; then
    handle_error "Should fail with invalid model"
fi

echo "Testing read-only file handling..."
./aoe "modify readonly file" || handle_error "Failed readonly file test"

echo "Testing non-existent directory..."
echo '{"path": "nonexistent"}' > .aoe.json
if ./aoe "test query" 2>/dev/null; then
    handle_error "Should fail with non-existent directory"
fi

echo "Testing missing API tokens..."
ANTHROPIC_BAK=$ANTHROPIC_API_KEY
unset ANTHROPIC_API_KEY
if ./aoe "test query" "c" 2>/dev/null; then
    handle_error "Should fail with missing API token"
fi
export ANTHROPIC_API_KEY=$ANTHROPIC_BAK

echo
echo "=== Testing file types ==="
echo "Testing Python file modification..."
./aoe "add type hints" || handle_error "Failed Python modification test"

echo "Testing JavaScript file modification..."
./aoe "convert to ES6 syntax" || handle_error "Failed JavaScript modification test"

echo "Testing symlinked file..."
./aoe "modify symlinked file" || handle_error "Failed symlink test"

echo "Testing Unicode content..."
./aoe "translate comments to English" || handle_error "Failed Unicode test"

echo
echo "=== All tests completed! ==="
cd /
rm -rf "$TEST_DIR"
