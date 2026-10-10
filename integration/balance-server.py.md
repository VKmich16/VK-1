# balance-server.py

Python stdlib bridge on 127.0.0.1:18911. Browser keys stay only in temporary 12-hour server sessions, never disk/logs/browser storage. Optional VK1_BALANCE_FILE reads only a sanitized shared balance snapshot, not an API key. Shared data expires after 5 minutes, is marked stale after 60 seconds, and unknown fields are never forwarded. Browser-specific sessions override shared data. DELETE clears only the browser override and falls back to shared data if enabled.

VK1_ALLOWED_ORIGINS is a comma-separated exact HTTPS origin allowlist; default is example.test and must be configured before deployment. Origins are used for session writes; GET relies on the trusted fronting dashboard access control. Do not expose the bridge or balance route to untrusted users.

Usage: `python3 integration/balance-server.py [--port 18911]`. GET health/balance; same-origin JSON POST session; same-origin DELETE session. 8-second session cache, 12-second upstream timeout, CNY only, 100 sessions, 6 connections/minute/IP.
