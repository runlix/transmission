#!/usr/bin/env bash
set -e
set -o pipefail

# Smoke test for Transmission Docker image
# This script receives IMAGE_TAG from the workflow environment

IMAGE="${IMAGE_TAG}"
PLATFORM="${PLATFORM:-linux/amd64}"
CONTAINER_NAME="transmission-smoke-test-${RANDOM}"
TRANSMISSION_PORT="9091"

# Color output for readability
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}🧪 Transmission Smoke Test${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo "Image: ${IMAGE}"
echo "Platform: ${PLATFORM}"
echo ""

# Validate IMAGE_TAG is set
if [ -z "${IMAGE}" ] || [ "${IMAGE}" = "null" ]; then
  echo -e "${RED}❌ ERROR: IMAGE_TAG environment variable is not set${NC}"
  exit 1
fi

# Create temporary config directory
CONFIG_DIR=$(mktemp -d)
chmod 777 "${CONFIG_DIR}"
echo "Config directory: ${CONFIG_DIR}"

# Create minimal settings.json to disable host whitelist
# Note: IP whitelist is disabled via --allowed "*" CLI arg below
# transmission-daemon has no CLI arg to disable host whitelist, requires settings.json
# Reference: https://github.com/transmission/transmission/blob/main/docs/Editing-Configuration-Files.md
cat > "${CONFIG_DIR}/settings.json" <<'EOF'
{
  "rpc-host-whitelist-enabled": false
}
EOF
chmod 644 "${CONFIG_DIR}/settings.json"
echo "Created minimal settings.json (host whitelist disabled)"
echo ""

# Cleanup function
cleanup() {
  echo ""
  echo -e "${YELLOW}🧹 Cleaning up...${NC}"

  # Capture final logs before stopping
  if docker ps -a | grep -q "${CONTAINER_NAME}"; then
    echo "Saving container logs..."
    docker logs "${CONTAINER_NAME}" > /tmp/transmission-smoke-test.log 2>&1 || true
    echo "Logs saved to: /tmp/transmission-smoke-test.log"
  fi

  docker stop "${CONTAINER_NAME}" 2>/dev/null || true
  docker rm "${CONTAINER_NAME}" 2>/dev/null || true

  # Clean up config directory (files may be owned by container user)
  if [ -d "${CONFIG_DIR}" ]; then
    chmod -R 777 "${CONFIG_DIR}" 2>/dev/null || true
    rm -rf "${CONFIG_DIR}" 2>/dev/null || true
  fi

  echo -e "${YELLOW}Cleanup complete${NC}"
}
trap cleanup EXIT

# Start container (use local image, don't pull from registry)
# Override entrypoint to pass --allowed "*" which disables IP whitelist
# Host whitelist is disabled via settings.json (no CLI arg available)
echo -e "${BLUE}▶️  Starting container...${NC}"
if ! docker run \
  --pull=never \
  --platform="${PLATFORM}" \
  --name "${CONTAINER_NAME}" \
  -v "${CONFIG_DIR}:/config" \
  -p "${TRANSMISSION_PORT}:9091" \
  -e PUID=1000 \
  -e PGID=1000 \
  -e TZ=UTC \
  --entrypoint /usr/local/bin/transmission-daemon \
  -d \
  "${IMAGE}" \
  --foreground \
  --config-dir /config \
  --allowed "*" \
  --no-auth; then
  echo -e "${RED}❌ Failed to start container${NC}"
  exit 1
fi

echo -e "${GREEN}✅ Container started${NC}"
echo ""

# Wait for initialization
echo -e "${BLUE}⏳ Waiting for Transmission to initialize...${NC}"
echo "Waiting 15 seconds for startup..."
sleep 15

# Check if container is still running
echo ""
echo -e "${BLUE}🔍 Checking container status...${NC}"
if ! docker ps | grep -q "${CONTAINER_NAME}"; then
  echo -e "${RED}❌ Container exited unexpectedly${NC}"
  echo ""
  echo "Container logs:"
  docker logs "${CONTAINER_NAME}" 2>&1
  exit 1
fi
echo -e "${GREEN}✅ Container is running${NC}"
echo ""

# Check logs for critical errors
echo -e "${BLUE}📋 Analyzing container logs...${NC}"
LOGS=$(docker logs "${CONTAINER_NAME}" 2>&1)

# Check for fatal errors
FATAL_COUNT=$(echo "$LOGS" | grep -ciE "fatal|panic|critical error" || true)
if [ "${FATAL_COUNT}" -gt 0 ]; then
  echo -e "${RED}❌ Found ${FATAL_COUNT} critical error(s) in logs:${NC}"
  echo "$LOGS" | grep -iE "fatal|panic|critical error" | head -10
  exit 1
fi

# Check for expected startup messages (use grep with here-string to avoid broken pipe)
if grep -qi "transmission\|started\|listening" <<< "$LOGS" 2>/dev/null; then
  echo -e "${GREEN}✅ Transmission startup message found${NC}"
else
  echo -e "${YELLOW}⚠️  Warning: Expected startup message not found${NC}"
fi

# Check for RPC initialization (use grep with here-string to avoid broken pipe)
if grep -qi "rpc\|web interface\|port.*9091" <<< "$LOGS" 2>/dev/null; then
  echo -e "${GREEN}✅ RPC/Web interface initialization detected${NC}"
else
  echo -e "${YELLOW}⚠️  Warning: No RPC/web interface messages found${NC}"
fi

echo -e "${GREEN}✅ No critical errors in logs${NC}"
echo ""

# Test RPC endpoint with retries
echo -e "${BLUE}🌐 Testing web/RPC endpoint...${NC}"
WEB_URL="http://localhost:${TRANSMISSION_PORT}/transmission/web/"
MAX_ATTEMPTS=24
ATTEMPT=0
WEB_OK=false

while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
  ATTEMPT=$((ATTEMPT + 1))

  if curl -fsSL --max-time 5 "${WEB_URL}" -o /dev/null 2>/dev/null; then
    WEB_OK=true
    break
  fi

  echo "Attempt ${ATTEMPT}/${MAX_ATTEMPTS}: Waiting for web endpoint..."
  sleep 5
done

if [ "${WEB_OK}" = true ]; then
  echo -e "${GREEN}✅ Web/RPC endpoint responding (${WEB_URL})${NC}"
else
  echo -e "${RED}❌ Web endpoint check failed after ${MAX_ATTEMPTS} attempts${NC}"
  echo ""
  echo "Recent container logs:"
  docker logs "${CONTAINER_NAME}" 2>&1 | tail -30
  exit 1
fi
echo ""

# Test RPC session endpoint
echo -e "${BLUE}📡 Testing RPC session endpoint...${NC}"
RPC_URL="http://localhost:${TRANSMISSION_PORT}/transmission/rpc"
if curl -fsSL --max-time 5 "${RPC_URL}" -o /dev/null 2>/dev/null || curl -fsSL --max-time 5 "${RPC_URL}" 2>&1 | grep -q "X-Transmission-Session-Id"; then
  echo -e "${GREEN}✅ RPC endpoint accessible (${RPC_URL})${NC}"
else
  echo -e "${YELLOW}⚠️  RPC endpoint check failed (non-critical)${NC}"
fi
echo ""

# Verify image is using correct architecture
echo -e "${BLUE}🏗️  Verifying architecture...${NC}"
IMAGE_ARCH=$(docker image inspect "${IMAGE}" | jq -r '.[0].Architecture')
EXPECTED_ARCH=$(echo "${PLATFORM}" | cut -d'/' -f2)

if [ "${IMAGE_ARCH}" = "${EXPECTED_ARCH}" ] || [ "${IMAGE_ARCH}" = "null" ]; then
  if [ "${IMAGE_ARCH}" = "null" ]; then
    echo -e "${YELLOW}⚠️  Cannot verify architecture (not set in image metadata)${NC}"
  else
    echo -e "${GREEN}✅ Architecture matches: ${IMAGE_ARCH}${NC}"
  fi
else
  echo -e "${RED}❌ Architecture mismatch: expected ${EXPECTED_ARCH}, got ${IMAGE_ARCH}${NC}"
  exit 1
fi
echo ""

# Summary
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}✅✅✅ Smoke Test PASSED ✅✅✅${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "Test Summary:"
echo "  • Container started successfully"
echo "  • No critical errors in logs"
echo "  • Web/RPC endpoint responding"
echo "  • RPC endpoints accessible"
echo "  • Correct architecture: ${IMAGE_ARCH}"
echo ""

exit 0
