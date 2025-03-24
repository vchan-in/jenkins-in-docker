# Use the official Jenkins inbound-agent image as the base
FROM jenkins/inbound-agent:latest

# Switch to root to install the certificate
USER root

# Copy your self-signed certificate into the container's trusted certificates folder.
COPY ./config/nginx/certs/self-signed.crt /tmp/jenkins.crt

# (Optional) Install ca-certificates if not already present.
RUN apt-get update && apt-get install -y ca-certificates

# Copy certificate to system trust store and update it.
RUN cp /tmp/jenkins.crt /usr/local/share/ca-certificates/jenkins.crt && update-ca-certificates

# Adjust the keystore path if needed; common paths include:
#   /etc/ssl/certs/java/cacerts  or
#   /usr/lib/jvm/java-11-openjdk-amd64/lib/security/cacerts
# Import the certificate into Java's truststore using JAVA_HOME
RUN keytool -importcert -noprompt -trustcacerts \
    -alias jenkins-cert \
    -file /tmp/jenkins.crt \
    -keystore ${JAVA_HOME}/lib/security/cacerts \
    -storepass changeit

# Switch back to the Jenkins user for security.
USER jenkins

