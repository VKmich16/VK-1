# balance-sync.py

Runs in Gateway-hosted exec with the existing protected DEEPSEEK_API_KEY environment sentinel and its destination-bound proxy/CA. Only queries https://api.deepseek.com/user/balance; never prints or writes the key or sentinel. Writes an atomic mode-0600 JSON snapshot containing balance, currency and timestamp. Failure retains the previous snapshot; backend expires it after 5 minutes.

Usage: `python3 integration/balance-sync.py --output /path/to/private/balance.json`. Parent directory must already exist and be private to the service user. Do not override/print DEEPSEEK_API_KEY or disable proxy/TLS verification. This command requires Gateway exec, not native or node exec, when using the protected store. Schedule through a zero-model script task every 30 seconds.

Python urllib prefers inherited lowercase proxy variables. For oc-sent-v2 credentials, the worker explicitly selects Gateway HTTPS_PROXY and fails closed when it is absent; do not route sentinels through a normal proxy.
