// OpenClaw script payload: update non-secret paths before registration.
// Run every 30s, agent owner explicit, tools=exec, no delivery, timeout=25s.
const result = await exec({
  command: "python3 /path/to/project/integration/balance-sync.py --output /path/to/private/balance.json",
  timeoutSeconds: 20,
  yieldMs: 20000
});
if (!JSON.stringify(result).includes("VK1_BALANCE_SYNC_OK")) throw new Error("Balance sync failed");
return {};
