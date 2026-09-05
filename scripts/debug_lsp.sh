#!/bin/bash
# Debug script to test LSP server behavior

cd "$(mktemp -d)" || exit 1
trap 'cd /; rm -rf "$(pwd)"' EXIT

cat > zr.toml << 'EOF'
[tasks.test]
cmd = "echo test"
EOF

# Build zr if needed
if [ ! -f /Users/fn/Desktop/codespace/zr/zig-out/bin/zr ]; then
    echo "Building zr..."
    cd /Users/fn/Desktop/codespace/zr && zig build
    cd - > /dev/null
fi

echo "=== Test 1: Single initialize request ==="
echo -ne "Content-Length: 121\r\n\r\n{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"processId\":null,\"rootUri\":null,\"capabilities\":{}}}" | \
    /Users/fn/Desktop/codespace/zr/zig-out/bin/zr lsp 2>&1 | head -c 500
echo -e "\n"

echo "=== Test 2: Initialize + Shutdown + Exit ==="
echo -ne "Content-Length: 121\r\n\r\n{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"processId\":null,\"rootUri\":null,\"capabilities\":{}}}Content-Length: 64\r\n\r\n{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"shutdown\",\"params\":null}Content-Length: 56\r\n\r\n{\"jsonrpc\":\"2.0\",\"method\":\"exit\",\"params\":null}" | \
    /Users/fn/Desktop/codespace/zr/zig-out/bin/zr lsp 2>&1
echo "Exit code: $?"
