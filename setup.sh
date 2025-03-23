#!/bin/bash
# setup.sh
# This script sets up the environment, generates SSL certificates, starts Docker Compose, and ensures Jenkins is fully running.

ENV_FILE=".env"

# Ensure the .env file exists
if [ ! -f "$ENV_FILE" ]; then
  echo ".env file not found! Please ensure .env is present with HOST_IP key."
  exit 1
fi

# Load environment variables from .env
set -a
source "$ENV_FILE"
set +a

# Ensure required variables are set
REQUIRED_VARS=("CERT_DIR" "CERT_FILE" "KEY_FILE" "CERT_DAYS" "CERT_COUNTRY" "CERT_STATE" "CERT_LOCALITY" "CERT_ORGANIZATION" "CERT_ORG_UNIT" "CERT_COMMON_NAME")
for var in "${REQUIRED_VARS[@]}"; do
  if [ -z "${!var}" ]; then
    echo "ERROR: Required environment variable $var is missing from .env!"
    exit 1
  fi
done

# Update HOST_IP if empty
if [ -z "$HOST_IP" ]; then
  HOST_IP=$(hostname -I | awk '{print $1}')
  echo "HOST_IP is empty. Detected HOST_IP: $HOST_IP. Updating .env..."
  if sed -i.bak "s/^HOST_IP=.*/HOST_IP=$HOST_IP/" "$ENV_FILE"; then
    echo "Updated .env with HOST_IP=$HOST_IP"
  else
    echo "ERROR: Failed to update .env with HOST_IP!"
    exit 1
  fi
else
  echo "HOST_IP is already set to: $HOST_IP"
fi

# Generate Jenkins admin token if empty
if [ -z "$JENKINS_ADMIN_TOKEN" ]; then
  echo "JENKINS_ADMIN_TOKEN is empty. Generating a new token..."
  JENKINS_ADMIN_TOKEN=$(openssl rand -hex 16)
  if sed -i.bak "s/^JENKINS_ADMIN_TOKEN=.*/JENKINS_ADMIN_TOKEN=$JENKINS_ADMIN_TOKEN/" "$ENV_FILE"; then
    echo "Updated .env with JENKINS_ADMIN_TOKEN"
  else
    echo "ERROR: Failed to update .env with JENKINS_ADMIN_TOKEN!"
    exit 1
  fi
else
  echo "JENKINS_ADMIN_TOKEN is already set"
fi

# Ensure the certificate directory exists
mkdir -p "$CERT_DIR"

# Define full paths for the certificate and key
CERT_PATH="$CERT_DIR/$CERT_FILE"
KEY_PATH="$CERT_DIR/$KEY_FILE"

# Always recreate the self-signed certificate
echo "Generating self-signed SSL certificate..."
if ! openssl req -x509 -nodes -days "$CERT_DAYS" \
  -newkey rsa:2048 \
  -subj "/C=$CERT_COUNTRY/ST=$CERT_STATE/L=$CERT_LOCALITY/O=$CERT_ORGANIZATION/OU=$CERT_ORG_UNIT/CN=$CERT_COMMON_NAME" \
  -keyout "$KEY_PATH" \
  -out "$CERT_PATH" 2>/dev/null; then
  echo "ERROR: OpenSSL certificate generation failed!"
  exit 1
fi
echo "Certificate generated at $CERT_PATH"
echo "Key generated at $KEY_PATH"

# Verify certificates were created properly
if [ ! -f "$CERT_PATH" ] || [ ! -f "$KEY_PATH" ]; then
  echo "ERROR: Failed to generate SSL certificates!"
  exit 1
fi

# Make necessary scripts executable
chmod +x ./config/nginx/nginx-entrypoint.sh
chmod 644 ./config/jenkins/disable-master.groovy

# Start Jenkins and Nginx
echo "Starting Jenkins..."
docker compose up -d jenkins

echo "Starting Nginx..."
docker compose up -d nginx

# Function to wait for Jenkins to be ready
wait_for_jenkins() {
  echo "Waiting for nginx to be ready..."
  while ! curl -s -k -f https://localhost/jenkins/ > /dev/null; do
    sleep 5
  done
  echo "Jenkins is ready!"
}

# Wait for Jenkins to be fully up
wait_for_jenkins

# Load environment variables
JENKINS_ADMIN_TOKEN=${JENKINS_ADMIN_TOKEN:-admin}
JENKINS_ADMIN_USER=${JENKINS_ADMIN_USER:-admin}
JENKINS_URL="https://localhost/jenkins"
AGENT_NAME="agent1"
ENV_FILE=".env"

echo "Retrieving Jenkins agent secret..."

# Fetch JNLP file securely
JNLP_RESPONSE=$(curl -s -k -u "${JENKINS_ADMIN_USER}:${JENKINS_ADMIN_TOKEN}" "$JENKINS_URL/computer/$AGENT_NAME/jenkins-agent.jnlp")

# Check if we received a valid response
if [[ -z "$JNLP_RESPONSE" ]]; then
  echo "ERROR: No response received from Jenkins. Is it running?"
  exit 1
elif [[ "$JNLP_RESPONSE" == *"401"* || "$JNLP_RESPONSE" == *"403"* ]]; then
  echo "ERROR: Authentication failed. Check your credentials."
  exit 1
fi

# Extract the agent secret (first <argument> tag contains the secret)
JENKINS_SECRET=$(echo "$JNLP_RESPONSE" | grep -oP '(?<=<argument>)[^<]+(?=</argument>)' | sed -n '1p')

# Validate extraction
if [[ -z "$JENKINS_SECRET" ]]; then
  echo "ERROR: Failed to extract Jenkins agent secret!"
  echo "Raw JNLP response for debugging:"
  echo "$JNLP_RESPONSE" | grep -o '<application-desc.*</application-desc>'
  exit 1
fi

# Debug output (first 5 characters only for security)
echo "Retrieved secret: ${JENKINS_SECRET:0:5}... (hidden for security)"

# Store or update JENKINS_SECRET in .env
if grep -q "^JENKINS_SECRET=" "$ENV_FILE"; then
  sed -i.bak "s|^JENKINS_SECRET=.*|JENKINS_SECRET=$JENKINS_SECRET|" "$ENV_FILE"
else
  echo "JENKINS_SECRET=$JENKINS_SECRET" >> "$ENV_FILE"
fi

echo "Jenkins agent secret successfully retrieved and stored in $ENV_FILE"

# Start remaining services
echo "Starting remaining Docker services..."
docker compose up -d --remove-orphans

# Function to check if a container is healthy
check_container_health() {
  local container=$1
  local health_status
  
  if ! health_status=$(docker inspect --format='{{.State.Health.Status}}' "$container" 2>/dev/null); then
    echo "ERROR: Could not inspect container $container!"
    return 1
  fi
  
  if [ "$health_status" = "healthy" ]; then
    return 0
  else
    return 1
  fi
}