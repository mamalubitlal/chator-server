#!/bin/bash
# Zapret Auto-Detect Best Strategy Script
# Run this on your server to find the best DPI bypass strategy
#
# Usage: ./detect_best_strategy.sh

set -e

ZAPRET_DIR="/opt/zapret"
CONFIG_DIR="$ZAPRET_DIR/config"
LISTS_DIR="$ZAPRET_DIR/list"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}=== Zapret Auto-Detect Best Strategy ===${NC}"
echo "This will test different strategies to find the best one for your ISP."
echo ""

# Test URLs
TEST_URLS=(
  "https://matrix.org"
  "https://element.io"
  "https://google.com"
  "https://www.recaptcha.net/recaptcha/api/siteverify"
)

# Strategies to test
STRATEGIES=(
  "FAKE_TLS_AUTO:strategy_fake_tls_auto.conf"
  "FAKE_TLS_AUTO_ALT:strategy_fake_tls_auto_alt.conf"
  "SIMPLE_FAKE:strategy_simple_fake.conf"
  "ALT:strategy_alt.conf"
)

# Function to test a strategy
test_strategy() {
  local strategy_name=$1
  local config_file=$2

  echo -e "${YELLOW}Testing strategy: $strategy_name${NC}"

  # Stop any running zapret
  $ZAPRET_DIR/init.d/sysv/zapret stop 2>/dev/null || true
  sleep 2

  # Apply strategy config
  if [ -f "$CONFIG_DIR/$config_file" ]; then
    cp "$CONFIG_DIR/$config_file" "$CONFIG_DIR/strategy.conf"
  else
    echo -e "${RED}Config file not found: $config_file${NC}"
    return 1
  fi

  # Start zapret
  $ZAPRET_DIR/init.d/sysv/zapret start
  sleep 3

  # Check if running
  if ! pgrep -x "nfqws" > /dev/null && ! pgrep -x "tpws" > /dev/null; then
    echo -e "${RED}  Failed to start${NC}"
    return 1
  fi

  # Test URLs
  local success=0
  for url in "${TEST_URLS[@]}"; do
    if curl -s --max-time 10 -o /dev/null -w "%{http_code}" "$url" | grep -q "200\|301\|302"; then
      ((success++))
    fi
  done

  # Stop zapret
  $ZAPRET_DIR/init.d/sysv/zapret stop 2>/dev/null || true
  sleep 1

  echo -e "${GREEN}  Success: $success/${#TEST_URLS[@]} URLs accessible${NC}"
  return $((success == 0 ? 1 : 0))
}

# Check if zapret is installed
if [ ! -d "$ZAPRET_DIR" ]; then
  echo -e "${RED}Zapret not installed. Install it first:${NC}"
  echo "  git clone https://github.com/bol-van/zapret.git /opt/zapret"
  echo "  cd /opt/zapret"
  echo "  ./install.sh"
  exit 1
fi

# Check for blockcheck script
if [ -f "$ZAPRET_DIR/blockcheck.sh" ]; then
  echo -e "${YELLOW}Running official blockcheck script first...${NC}"
  echo "This will determine the best parameters for your ISP."
  echo ""
  read -p "Run blockcheck.sh? (y/n): " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    cd "$ZAPRET_DIR"
    ./blockcheck.sh
  fi
fi

# Test each strategy
echo ""
echo -e "${GREEN}=== Testing Strategies ===${NC}"

best_strategy=""
best_score=0

for strategy in "${STRATEGIES[@]}"; do
  IFS=':' read -r name config <<< "$strategy"

  if test_strategy "$name" "$config"; then
    echo -e "${GREEN}Strategy $name works!${NC}"
    if [ $? -eq 0 ]; then
      best_strategy="$name"
      break
    fi
  else
    echo -e "${RED}Strategy $name failed${NC}"
  fi
done

if [ -n "$best_strategy" ]; then
  echo ""
  echo -e "${GREEN}=== Best Strategy: $best_strategy ===${NC}"
  echo "$best_strategy" > "$CONFIG_DIR/strategy"
  echo "Saved to $CONFIG_DIR/strategy"

  # Start with best strategy
  echo "Starting zapret with best strategy..."
  cd "$ZAPRET_DIR"
  ./init.d/sysv/zapret start
else
  echo ""
  echo -e "${RED}=== No strategy worked! ===${NC}"
  echo "Try running blockcheck.sh manually for custom parameters."
  echo "Or check: https://github.com/bol-van/zapret/issues"
fi

echo ""
echo "Done!"