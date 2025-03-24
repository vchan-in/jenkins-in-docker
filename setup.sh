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
CRT_PATH="$CERT_DIR/${CERT_FILE%.*}.crt"

# Create a temporary OpenSSL config file with SAN
OPENSSL_CONFIG=$(mktemp)
cat > "$OPENSSL_CONFIG" <<EOF
[req]
distinguished_name = req_distinguished_name
x509_extensions = v3_req
prompt = no

[req_distinguished_name]
C = $CERT_COUNTRY
ST = $CERT_STATE
L = $CERT_LOCALITY
O = $CERT_ORGANIZATION
OU = $CERT_ORG_UNIT
CN = $CERT_COMMON_NAME

[v3_req]
basicConstraints = CA:FALSE
keyUsage = digitalSignature, keyEncipherment
subjectAltName = @alt_names

[alt_names]
DNS.1 = $CERT_COMMON_NAME
DNS.2 = localhost
IP.1 = $HOST_IP
IP.2 = 127.0.0.1
EOF

# Always recreate the self-signed certificate
echo "Generating self-signed SSL certificate with SAN..."
if ! openssl req -x509 -nodes -days "$CERT_DAYS" \
  -newkey rsa:2048 \
  -keyout "$KEY_PATH" \
  -out "$CERT_PATH" \
  -config "$OPENSSL_CONFIG" 2>/dev/null; then
  echo "ERROR: OpenSSL certificate generation failed!"
  rm -f "$OPENSSL_CONFIG"
  exit 1
fi
echo "Certificate generated at $CERT_PATH"
echo "Key generated at $KEY_PATH"

# Clean up the temporary config file
rm -f "$OPENSSL_CONFIG"

# Generate .crt file from the certificate
echo "Converting certificate to .crt format..."
if ! openssl x509 -outform der -in "$CERT_PATH" -out "$CRT_PATH" 2>/dev/null; then
  echo "ERROR: Failed to convert certificate to .crt format!"
  exit 1
fi
echo "CRT certificate generated at $CRT_PATH"

# Verify certificates were created properly
if [ ! -f "$CERT_PATH" ] || [ ! -f "$KEY_PATH" ] || [ ! -f "$CRT_PATH" ]; then
  echo "ERROR: Failed to generate SSL certificates!"
  exit 1
fi

# Copy the .crt file to the location expected by the Dockerfile
echo "Copying certificate for Docker image build..."
mkdir -p ./config/nginx/certs/
cp "$CRT_PATH" ./config/nginx/certs/self-signed.crt

# Check if the custom Jenkins agent image already exists
if ! docker image inspect jenkins-custom-agent:latest >/dev/null 2>&1; then
  # Build the custom Jenkins agent image
  echo "Building custom Jenkins agent Docker image..."
  docker build -t jenkins-agent:latest -f ./config/jenkins/agent/Dockerfile . --no-cache
  if [ $? -ne 0 ]; then
    echo "ERROR: Failed to build custom Jenkins agent Docker image!"
    exit 1
  fi
  echo "Custom Jenkins agent Docker image built successfully"
else
  echo "Custom Jenkins agent Docker image already exists, skipping build"
fi

# Make necessary scripts executable
chmod +x ./config/nginx/nginx-entrypoint.sh
chmod 644 ./config/jenkins/*

# Start Jenkins and Nginx
echo "Starting Jenkins..."
docker compose up -d

# Function to wait for Jenkins to be ready
wait_for_jenkins() {
  echo "Waiting for jenkins to be ready..."
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
AGENT1_NAME="agent1"
AGENT2_NAME="agent2"
ENV_FILE=".env"

echo "Retrieving Jenkins agent secret..."

# Fetch JNLP file securely
JNLP_RESPONSE_AGENT1=$(curl -s -k -u "${JENKINS_ADMIN_USER}:${JENKINS_ADMIN_TOKEN}" "$JENKINS_URL/computer/$AGENT1_NAME/jenkins-agent.jnlp")
JNLP_RESPONSE_AGENT2=$(curl -s -k -u "${JENKINS_ADMIN_USER}:${JENKINS_ADMIN_TOKEN}" "$JENKINS_URL/computer/$AGENT2_NAME/jenkins-agent.jnlp")

# Check if we received a valid response
if [[ -z "$JNLP_RESPONSE_AGENT1" ]] && [[ -z "$JNLP_RESPONSE_AGENT2" ]]; then
  echo "ERROR: No response received from Jenkins. Is it running?"
  exit 1
elif [[ "$JNLP_RESPONSE_AGENT1" == *"401"* || "$JNLP_RESPONSE_AGENT1" == *"403"* ]] && [[ "$JNLP_RESPONSE_AGENT2" == *"401"* || "$JNLP_RESPONSE_AGENT2" == *"403"* ]]; then
  echo "ERROR: Authentication failed. OR Agents are already connected."
  exit 1
fi

# Extract the agent secret (first <argument> tag contains the secret)
JENKINS_SECRET_AGENT1=$(echo "$JNLP_RESPONSE_AGENT1" | grep -oP '(?<=<argument>)[^<]+(?=</argument>)' | sed -n '1p')
JENKINS_SECRET_AGENT2=$(echo "$JNLP_RESPONSE_AGENT2" | grep -oP '(?<=<argument>)[^<]+(?=</argument>)' | sed -n '1p')

# Validate extraction
if [[ -z "$JENKINS_SECRET_AGENT1" ]]; then
  echo "ERROR: Failed to extract Jenkins agent secret!"
  echo "Raw JNLP response for debugging:"
  echo "$JENKINS_SECRET_AGENT1" | grep -o '<application-desc.*</application-desc>'
  exit 1
fi

if [[ -z "$JENKINS_SECRET_AGENT2" ]]; then
  echo "ERROR: Failed to extract Jenkins agent secret!"
  echo "Raw JNLP response for debugging:"
  echo "$JENKINS_SECRET_AGENT2" | grep -o '<application-desc.*</application-desc>'
  exit 1
fi

# Debug output (first 5 characters only for security)
echo "Retrieved secret for agent 1: ${JENKINS_SECRET_AGENT1:0:5}... (hidden for security)"
echo "Retrieved secret for agent 2: ${JENKINS_SECRET_AGENT2:0:5}... (hidden for security)"

# Store or update JENKINS_SECRET in .env
if grep -q "^JENKINS_SECRET_AGENT1=" "$ENV_FILE"; then
  sed -i.bak "s|^JENKINS_SECRET_AGENT1=.*|JENKINS_SECRET_AGENT1=$JENKINS_SECRET_AGENT1|" "$ENV_FILE"
else
  echo "JENKINS_SECRET_AGENT1=$JENKINS_SECRET_AGENT1" >> "$ENV_FILE"
fi

if grep -q "^JENKINS_SECRET_AGENT2=" "$ENV_FILE"; then
  sed -i.bak "s|^JENKINS_SECRET_AGENT2=.*|JENKINS_SECRET_AGENT2=$JENKINS_SECRET_AGENT2|" "$ENV_FILE"
else
  echo "JENKINS_SECRET_AGENT2=$JENKINS_SECRET_AGENT2" >> "$ENV_FILE"
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