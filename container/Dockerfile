FROM python:3.13-slim

# Supply reviewed versions and the helper URL/checksum for the target Linux
# architecture. No unverified binary or floating proxy version is downloaded.
ARG MCP_PROXY_VERSION
ARG SIGNING_HELPER_URL
ARG SIGNING_HELPER_SHA256

RUN test -n "$MCP_PROXY_VERSION" && test -n "$SIGNING_HELPER_URL" && test -n "$SIGNING_HELPER_SHA256" \
    && apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl \
    && curl --fail --show-error --location --proto '=https' --proto-redir '=https' \
       "$SIGNING_HELPER_URL" -o /usr/local/bin/aws_signing_helper \
    && printf '%s  /usr/local/bin/aws_signing_helper\n' "$SIGNING_HELPER_SHA256" | sha256sum -c - \
    && chmod 0755 /usr/local/bin/aws_signing_helper \
    && pip install --no-cache-dir "mcp-proxy-for-aws-cli==$MCP_PROXY_VERSION" \
    && rm -rf /var/lib/apt/lists/*

RUN useradd --create-home --uid 10001 appuser
COPY --chmod=0755 entrypoint.sh /app/entrypoint.sh
ENV PYTHONUNBUFFERED=1
USER 10001
ENTRYPOINT ["/app/entrypoint.sh"]
