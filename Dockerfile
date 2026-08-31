FROM ghcr.io/gitroomhq/postiz-app:latest

# Postiz hardcodes TikTok scopes including video.list / video.create.
# TikTok no longer offers those scopes, so OAuth fails with "scope".
COPY scripts/patch-tiktok-scopes.sh /tmp/patch-tiktok-scopes.sh
RUN node /tmp/patch-tiktok-scopes.sh
