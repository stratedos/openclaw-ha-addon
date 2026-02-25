ARG BUILD_FROM
FROM ${BUILD_FROM}

# Debian Bookworm base — avoids musl/Alpine native module issues with OpenClaw

# Install Node.js 22 from NodeSource
RUN apt-get update && apt-get install -y --no-install-recommends \
    bash curl jq ca-certificates gnupg git \
    && mkdir -p /etc/apt/keyrings \
    && curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
       | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg \
    && echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_22.x nodistro main" \
       > /etc/apt/sources.list.d/nodesource.list \
    && apt-get update \
    && apt-get install -y nodejs \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Install OpenClaw globally
RUN npm install -g openclaw@latest

# Copy run script
COPY run.sh /
RUN chmod +x /run.sh

CMD [ "/run.sh" ]
