#!/bin/bash
cd /tmp
mkdir -p lsp_test_$$
cd lsp_test_$$

cat > zr.toml << 'EOF'
[tasks.test]
cmd = "echo test"
EOF

# Send a single initialize request
(echo -ne "Content-Length: 121\r\n\r\n{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"processId\":null,\"rootUri\":null,\"capabilities\":{}}}" && sleep 0.1) | \
  /Users/fn/Desktop/codespace/zr/zig-out/bin/zr lsp &

PID=$!
sleep 1
kill $PID 2>/dev/null
wait $PID 2>/dev/null

cd /tmp
rm -rf lsp_test_$$
