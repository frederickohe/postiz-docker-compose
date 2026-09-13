FROM ghcr.io/gitroomhq/postiz-app:latest

# Strip provider OAuth scopes that fail authorize or Google verification:
# TikTok video.list / video.create; YouTube extras beyond readonly + upload.
COPY scripts/patch-tiktok-scopes.sh /tmp/patch-tiktok-scopes.sh
RUN node /tmp/patch-tiktok-scopes.sh
