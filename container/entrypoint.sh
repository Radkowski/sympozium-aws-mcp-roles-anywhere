#!/bin/sh
set -eu

# Keep stdout exclusively for the MCP stdio protocol.
: "${AWS_CONFIG_FILE:?Set AWS_CONFIG_FILE to the mounted AWS config}"
: "${AWS_PROFILE:?Set AWS_PROFILE to the configured profile name}"
: "${MCP_ENDPOINT:?Set MCP_ENDPOINT to the SigV4 MCP HTTPS endpoint}"
: "${AWS_REGION:?Set AWS_REGION to the signing region}"

case "$MCP_ENDPOINT" in
  https://*) ;;
  *) echo 'MCP_ENDPOINT must use HTTPS' >&2; exit 1 ;;
esac
test -r "$AWS_CONFIG_FILE" || {
  echo 'AWS configuration is not readable' >&2
  exit 1
}

# Avoid silently overriding credential_process with injected static credentials.
if [ -n "${AWS_ACCESS_KEY_ID:-}" ] || [ -n "${AWS_SECRET_ACCESS_KEY:-}" ] || [ -n "${AWS_SESSION_TOKEN:-}" ]; then
  echo 'Remove static AWS credential environment variables; use Roles Anywhere' >&2
  exit 1
fi

set -- mcp-proxy-for-aws-cli "$MCP_ENDPOINT" --region "$AWS_REGION" "$@"
if [ -n "${MCP_SIGNING_SERVICE:-}" ]; then
  set -- "$@" --service "$MCP_SIGNING_SERVICE"
fi
if [ -n "${AWS_OPERATIONS_REGION:-}" ]; then
  set -- "$@" --metadata "AWS_REGION=$AWS_OPERATIONS_REGION"
fi
case "${MCP_READ_ONLY:-true}" in
  true) set -- "$@" --read-only ;;
  false) ;;
  *) echo 'MCP_READ_ONLY must be true or false' >&2; exit 1 ;;
esac
exec "$@"
