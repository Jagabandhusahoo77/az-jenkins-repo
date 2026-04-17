###############################################################################
# Jenkins Controller Image
#
# Based on official Jenkins LTS. Adds:
#   - Terraform (for running pipeline stages directly on controller for local dev)
#   - Azure CLI (for bootstrap scripts and Azure auth)
#   - tflint, checkov, tfsec (CI security/lint tools)
#
# In production, these tools live on a dedicated Jenkins agent node, not the
# controller. For local dev, running everything on the controller is fine.
###############################################################################
FROM jenkins/jenkins:lts-jdk17

USER root

# ── System dependencies ──────────────────────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    unzip \
    gnupg \
    lsb-release \
    software-properties-common \
    python3 \
    python3-pip \
    python3-venv \
    git \
    jq \
    && rm -rf /var/lib/apt/lists/*

# ── Terraform ────────────────────────────────────────────────────────────────
ARG TERRAFORM_VERSION=1.7.5
RUN curl -fsSL "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip" \
    -o /tmp/terraform.zip \
    && unzip /tmp/terraform.zip -d /usr/local/bin \
    && rm /tmp/terraform.zip \
    && terraform version

# ── TFLint ───────────────────────────────────────────────────────────────────
RUN curl -s https://raw.githubusercontent.com/terraform-linters/tflint/master/install_linux.sh | bash

# ── tfsec ────────────────────────────────────────────────────────────────────
RUN curl -s https://raw.githubusercontent.com/aquasecurity/tfsec/master/scripts/install_linux.sh | bash

# ── Checkov (isolated venv to avoid pip system conflicts) ────────────────────
RUN python3 -m venv /opt/checkov-venv \
    && /opt/checkov-venv/bin/pip install --upgrade pip checkov \
    && ln -s /opt/checkov-venv/bin/checkov /usr/local/bin/checkov

# ── Azure CLI ────────────────────────────────────────────────────────────────
RUN curl -sL https://aka.ms/InstallAzureCLIDeb | bash

# ── Verify all tools ─────────────────────────────────────────────────────────
RUN terraform version && tflint --version && checkov --version && az version | head -1

# ── Jenkins plugins (installed at build time for faster startup) ─────────────
USER jenkins
COPY plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt

# ── Skip setup wizard (config done via JCasC) ────────────────────────────────
ENV JAVA_OPTS="-Djenkins.install.runSetupWizard=false"
ENV CASC_JENKINS_CONFIG=/var/jenkins_home/casc

USER root
# Give jenkins user access to run docker (for future agent-in-docker use)
RUN groupadd -f docker && usermod -aG docker jenkins || true

USER jenkins
