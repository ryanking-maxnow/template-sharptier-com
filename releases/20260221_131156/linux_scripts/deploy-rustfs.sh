#!/bin/bash

# ==============================================================================
# RustFS Deployment Script (Phase 2 - amazon/aws-cli Method)
#
# This script automates the deployment of RustFS (S3-compatible storage) using
# Docker Compose and initializes the default bucket with amazon/aws-cli container.
#
# Method: Uses amazon/aws-cli Docker container (no node_modules dependency)
# Backup: Node.js method (setup-rustfs-bucket.mjs) preserved as fallback
# ==============================================================================

# Text colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

WORKDIR="/home/sharptier-cms"
COMPOSE_FILE="docker-compose.yml"
SHARED_DIR="$WORKDIR/shared"

echo -e "${GREEN}==> Starting RustFS Deployment (amazon/aws-cli method)...${NC}"

# 1. Check if Docker Compose file exists
if [ ! -f "$WORKDIR/$COMPOSE_FILE" ]; then
    echo -e "${RED}Error: Compose file $WORKDIR/$COMPOSE_FILE not found!${NC}"
    exit 1
fi

# 2. Start RustFS Container
echo -e "\n${YELLOW}1. Starting RustFS Container...${NC}"
cd "$WORKDIR" || exit 1
docker compose -f "$COMPOSE_FILE" --profile storage up -d rustfs

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✔ RustFS container started successfully.${NC}"
else
    echo -e "${RED}✘ Failed to start RustFS container.${NC}"
    exit 1
fi

# 3. Wait for RustFS to be ready (improved: direct curl test)
echo -e "\n${YELLOW}2. Waiting for RustFS to be ready...${NC}"
attempt=0
max_attempts=30
while [ $attempt -lt $max_attempts ]; do
    if curl -s http://localhost:9000 >/dev/null 2>&1; then
        echo -e "${GREEN}✔ RustFS is ready!${NC}"
        break
    fi
    echo -n "."
    sleep 1
    attempt=$((attempt+1))
done

if [ $attempt -eq $max_attempts ]; then
    echo -e "\n${RED}✘ Timeout waiting for RustFS to become ready.${NC}"
    echo -e "${YELLOW}Continuing anyway, but bucket initialization may fail...${NC}"
fi

# 4. Load configuration from deploy.env
echo -e "\n${YELLOW}3. Loading configuration...${NC}"
if [ ! -f "$SHARED_DIR/deploy.env" ]; then
    echo -e "${RED}✘ Configuration file not found: $SHARED_DIR/deploy.env${NC}"
    echo -e "${YELLOW}Hint: Run deploy-app-local.sh first or create deploy.env manually${NC}"
    exit 1
fi

source "$SHARED_DIR/deploy.env"

# Validate required variables
if [ -z "$S3_BUCKET" ] || [ -z "$S3_ACCESS_KEY_ID" ] || [ -z "$S3_SECRET_ACCESS_KEY" ]; then
    echo -e "${RED}✘ Missing S3 configuration in deploy.env${NC}"
    echo -e "${YELLOW}Required: S3_BUCKET, S3_ACCESS_KEY_ID, S3_SECRET_ACCESS_KEY${NC}"
    exit 1
fi

echo -e "${GREEN}✔ Configuration loaded (Bucket: $S3_BUCKET)${NC}"

# 5. Initialize Bucket using amazon/aws-cli Docker container
echo -e "\n${YELLOW}4. Initializing bucket '${S3_BUCKET}'...${NC}"

# Method: amazon/aws-cli (recommended - no host dependencies)
echo -e "${YELLOW}   Using amazon/aws-cli Docker container...${NC}"

# Create bucket (with idempotency handling)
CREATE_OUTPUT=$(docker run --rm \
  --network host \
  -e AWS_ACCESS_KEY_ID="${S3_ACCESS_KEY_ID}" \
  -e AWS_SECRET_ACCESS_KEY="${S3_SECRET_ACCESS_KEY}" \
  -e AWS_REGION=us-east-1 \
  amazon/aws-cli \
  s3 mb "s3://${S3_BUCKET}" --endpoint-url http://localhost:9000 2>&1)

# Check result
if echo "$CREATE_OUTPUT" | grep -q "make_bucket:"; then
    echo -e "${GREEN}✔ Bucket '${S3_BUCKET}' created successfully${NC}"
elif echo "$CREATE_OUTPUT" | grep -q "BucketAlreadyOwnedByYou"; then
    echo -e "${GREEN}✔ Bucket '${S3_BUCKET}' already exists (idempotent)${NC}"
else
    echo -e "${RED}✘ Bucket creation failed or unexpected response${NC}"
    echo -e "${YELLOW}Output: $CREATE_OUTPUT${NC}"
    # Don't exit - continue to verification
fi

# 6. Verify bucket exists
echo -e "\n${YELLOW}5. Verifying bucket...${NC}"
if docker run --rm \
  --network host \
  -e AWS_ACCESS_KEY_ID="${S3_ACCESS_KEY_ID}" \
  -e AWS_SECRET_ACCESS_KEY="${S3_SECRET_ACCESS_KEY}" \
  -e AWS_REGION=us-east-1 \
  amazon/aws-cli \
  s3 ls "s3://${S3_BUCKET}" --endpoint-url http://localhost:9000 >/dev/null 2>&1; then
    echo -e "${GREEN}✔ Bucket '${S3_BUCKET}' is accessible${NC}"
else
    echo -e "${RED}✘ Bucket verification failed${NC}"
    echo -e "${YELLOW}Hint: Check S3 credentials or try the Node.js fallback method${NC}"
    exit 1
fi

# 7. Summary
echo -e "\n${GREEN}==========================================${NC}"
echo -e "${GREEN}   RustFS Deployed Successfully!          ${NC}"
echo -e "${GREEN}==========================================${NC}"
echo -e "S3 API Endpoint:  http://localhost:9000"
echo -e "Web Console:      http://localhost:9001/rustfs/console/index.html"
echo -e "Bucket:           ${S3_BUCKET}"
echo -e "Credentials:"
echo -e "  Access Key: ${S3_ACCESS_KEY_ID}"
echo -e "  Secret Key: ${S3_SECRET_ACCESS_KEY:0:10}...(masked)"
echo -e "\nMethod Used: amazon/aws-cli Docker container"
echo -e "Backup Method: Node.js script (scripts/setup-rustfs-bucket.mjs) - preserved for fallback"

# ==============================================================================
# FALLBACK METHOD (commented out - use if Docker method fails)
# ==============================================================================
# To use Node.js fallback method:
# 1. Ensure current/node_modules exists (run deploy-app-local.sh)
# 2. Uncomment and run:
#
# if [ -d "$WORKDIR/current/node_modules" ]; then
#     cd "$WORKDIR/current"
#     node "$WORKDIR/scripts/setup-rustfs-bucket.mjs"
# fi
# ==============================================================================
