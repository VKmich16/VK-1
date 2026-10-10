#!/usr/bin/env python3
"""Run within protected Gateway exec; publish balance data, never credentials."""
import argparse
import importlib.util
import json
import os
import tempfile
import urllib.request
from pathlib import Path

def configure_egress(key):
    # urllib prefers lowercase proxy variables inherited from the host. For
    # protected credentials, use the Gateway proxy explicitly or fail closed.
    if key.startswith("oc-sent-v2"):
        protected_proxy = os.environ.get("HTTPS_PROXY", "")
        if not protected_proxy:
            raise RuntimeError("Protected credential egress is unavailable")
        opener = urllib.request.build_opener(
            urllib.request.ProxyHandler({"https": protected_proxy})
        )
        urllib.request.install_opener(opener)

def sync(output):
    key = os.environ.get("DEEPSEEK_API_KEY", "")
    if not key:
        raise RuntimeError("DS credential is unavailable in this execution context")
    spec = importlib.util.spec_from_file_location("vk1_balance", Path(__file__).with_name("balance-server.py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    configure_egress(key)
    data = module.fetch_balance(module.Session(key))
    key = ""
    if not data.get("ok") or data.get("stale"):
        raise RuntimeError("DS balance synchronization failed: " + str(data.get("code", "SOURCE")))
    target = Path(output)
    fd, temporary = tempfile.mkstemp(prefix=".balance-", dir=target.parent)
    try:
        with os.fdopen(fd, "w") as handle:
            json.dump(data, handle, allow_nan=False)
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, target)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)
    return {"ok": True, "currency": "CNY"}

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    try:
        result = sync(args.output)
    except Exception:
        raise SystemExit("DS balance synchronization failed; previous snapshot retained")
    print("VK1_BALANCE_SYNC_OK " + json.dumps(result))

if __name__ == "__main__":
    main()
