ARG BUILD_FROM
FROM ${BUILD_FROM}

# Install dependencies
# jq is included in HA base images but we ensure it's present
RUN apk add --no-cache nodejs npm curl bash jq

# Install OpenClaw globally
RUN npm install -g openclaw@latest

# Copy run script
COPY run.sh /
RUN chmod +x /run.sh

CMD [ "/run.sh" ]
