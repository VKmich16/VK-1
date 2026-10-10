# backend-test.py

余额适配的隔离回归测试：mock 固定官方请求，验证缓存/CNY/异常/stale、会话隔离、CSRF、Secure cookie、断开、过期及无效Key。临时端口仅loopback，不用真实凭据，不改变生产服务。用法 `python3 integration/backend-test.py`。
