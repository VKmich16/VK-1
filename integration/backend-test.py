import importlib.util
import io
import json
import threading
import time
import unittest
import tempfile
from datetime import datetime, timezone, timedelta
import urllib.request
import urllib.error
from pathlib import Path
from unittest.mock import patch
spec = importlib.util.spec_from_file_location("vk1", Path(__file__).with_name("balance-server.py"))
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

class Response(io.BytesIO):
    def __enter__(self): return self
    def __exit__(self, *args): self.close()

def upstream(*args, **kwargs):
    return Response(json.dumps({"balance_infos":[{"currency":"CNY","total_balance":"12.34"}]}).encode())

class TestBalance(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server=mod.ThreadingHTTPServer(("127.0.0.1",0),mod.Handler)
        threading.Thread(target=cls.server.serve_forever,daemon=True).start()
        cls.base="http://127.0.0.1:"+str(cls.server.server_port)
    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown();cls.server.server_close()
    def setUp(self):
        mod.SESSIONS.clear();mod.RATE.clear();mod.BALANCE_FILE=""
    def req(self,path="balance",method="GET",data=None,cookie="",origin="https://dash.example.test"):
        headers={"Host":"dash.example.test","Origin":origin,"Content-Type":"application/json","Cookie":cookie}
        r=urllib.request.Request(self.base+"/vk-1/api/"+path,method=method,headers=headers,data=json.dumps(data).encode() if data is not None else None)
        try: response=urllib.request.urlopen(r)
        except urllib.error.HTTPError as e: response=e
        with response:
            return response.status,json.loads(response.read()),response.headers
    @patch.object(mod.urllib.request,"urlopen",side_effect=upstream)
    def test_cache_currency_and_stale(self,mock):
        s=mod.Session("test-key")
        self.assertEqual(mod.fetch_balance(s)["totalBalance"],12.34)
        mod.fetch_balance(s);self.assertEqual(mock.call_count,1)
        s.last-=9
        mock.side_effect=urllib.error.URLError("sensitive info")
        self.assertTrue(mod.fetch_balance(s)["stale"])
        s.last-=9;s.last_success-=301
        self.assertFalse(mod.fetch_balance(s)["ok"])
    @patch.object(mod.urllib.request,"urlopen")
    def test_reject_usd_nan_and_bad_shape(self,mock):
        for row in [{"currency":"USD","total_balance":"1"},{"currency":"CNY","total_balance":"nan"},{"currency":"CNY","total_balance":"-1"}]:
            mock.side_effect=lambda *a,**k:Response(json.dumps({"balance_infos":[row]}).encode())
            self.assertFalse(mod.fetch_balance(mod.Session("test-key"))["ok"])
    def test_session_isolation_csrf_and_delete(self):
        self.assertEqual(self.req()[1]["code"],"NO_KEY")
        real=mod.urllib.request.urlopen
        def routed(request,*args,**kwargs):
            if isinstance(request,urllib.request.Request) and request.full_url==mod.UPSTREAM:return upstream()
            return real(request,*args,**kwargs)
        with patch.object(mod.urllib.request,"urlopen",side_effect=routed):
            status,data,headers=self.req("session","POST",{"key":"sk-only-a-fake-test-key"});self.assertEqual(status,200)
            cookie=headers["Set-Cookie"].split(";")[0]
            for flag in ["HttpOnly","Secure","SameSite=Strict"]:self.assertIn(flag,headers["Set-Cookie"])
            self.assertNotIn("fake-test",json.dumps(data))
            self.assertEqual(self.req(cookie=cookie)[1]["totalBalance"],12.34)
            self.assertEqual(self.req()[1]["code"],"NO_KEY")
            self.assertEqual(self.req("session","DELETE",cookie=cookie,origin="https://evil.example")[0],403)
            self.assertEqual(self.req("session","DELETE",cookie=cookie)[0],200)
            self.assertEqual(self.req(cookie=cookie)[1]["code"],"NO_KEY")
            self.assertEqual(self.req("session","POST",{"key":"sk-only-a-fake-test-key"},origin="https://evil.example")[0],403)
    def test_expiry_and_invalid_key(self):
        s=mod.Session("test-key");s.expires=time.monotonic()-1;mod.SESSIONS["test"]=s;mod.prune()
        self.assertFalse(mod.SESSIONS);self.assertEqual(s.key,"")
        self.assertEqual(self.req("session","POST",{"key":"bad"})[0],400)

class TestSharedBalance(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.old_file = mod.BALANCE_FILE
        mod.BALANCE_FILE = str(Path(self.temp.name) / "balance.json")
    def tearDown(self):
        mod.BALANCE_FILE = self.old_file
        self.temp.cleanup()
    def write(self, age=0, **fields):
        data = {"ok": True, "totalBalance": 12.34, "currency": "CNY", "updatedAt": (datetime.now(timezone.utc)-timedelta(seconds=age)).isoformat()}
        data.update(fields)
        Path(mod.BALANCE_FILE).write_text(json.dumps(data))
    def test_default_is_opt_in_and_missing_is_disconnected(self):
        self.assertEqual(mod.shared_balance()["code"], "NO_KEY")
        mod.BALANCE_FILE = ""
        self.assertEqual(mod.shared_balance()["code"], "NO_KEY")
    def test_shared_response_filters_extra_fields(self):
        self.write(key="sensitive-test-value", arbitrary="private")
        data = mod.shared_balance()
        self.assertEqual(data["totalBalance"], 12.34)
        self.assertEqual(set(data), {"ok", "totalBalance", "currency", "updatedAt"})
    def test_stale_and_expired_are_explicit(self):
        self.write(age=70)
        self.assertTrue(mod.shared_balance()["stale"])
        self.write(age=301)
        self.assertEqual(mod.shared_balance()["code"], "EXPIRED")
        self.write(age=-60)
        self.assertEqual(mod.shared_balance()["code"], "EXPIRED")
    def test_invalid_data_is_not_forwarded(self):
        for fields in [{"currency":"USD"},{"totalBalance":float("nan")},{"totalBalance":True},{"totalBalance":-1},{"updatedAt":"bad"}]:
            self.write(**fields)
            self.assertEqual(mod.shared_balance()["code"], "SOURCE")
        Path(mod.BALANCE_FILE).write_text("x"*65537)
        self.assertEqual(mod.shared_balance()["code"], "SOURCE")

class TestProtectedEgress(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        spec = importlib.util.spec_from_file_location("vk1_sync", Path(__file__).with_name("balance-sync.py"))
        cls.worker = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(cls.worker)
    def test_lowercase_proxy_does_not_override_protected_proxy(self):
        protected = "http://127.0.0.1:43210"
        with patch.dict(self.worker.os.environ, {"HTTPS_PROXY": protected, "https_proxy": "http://127.0.0.1:7890"}, clear=True):
            with patch.object(urllib.request, "install_opener") as install:
                self.worker.configure_egress("oc-sent-v2.test.end")
                handlers = install.call_args.args[0].handlers
                proxy = next(h for h in handlers if isinstance(h, urllib.request.ProxyHandler))
                self.assertEqual(proxy.proxies, {"https": protected})
    def test_missing_protected_proxy_fails_closed(self):
        with patch.dict(self.worker.os.environ, {"https_proxy": "http://127.0.0.1:7890"}, clear=True):
            with self.assertRaises(RuntimeError):
                self.worker.configure_egress("oc-sent-v2.test.end")

if __name__=="__main__":unittest.main()
