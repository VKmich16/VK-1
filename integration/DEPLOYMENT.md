# Deployment and rollback

1. Build a new immutable release and run the checks in README. Keep it outside your dashboard content until verified.
2. Copy it to `/opt/vk1-dash/releases/RELEASE`, verify manifest SHA-256 values, then atomically switch `/opt/vk1-dash/current` using a new symlink and rename. Never overwrite a release.
3. Mount current at `/vk-1/` with the nginx example. Insert only the single loader tag into the existing dashboard; preserve other content and routing.
4. Install the Python bridge and optional `vk1-balance.service.example`; set your exact allowed HTTPS origins. `nginx -t` before reloading. Keep backup files outside nginx include directories.
5. Protect the dashboard and `/vk-1/api/` behind the same access control. Verify health, manifest/resources, desktop and touch input on the actual dashboard, especially embedded cross-origin iframes.
6. An optional shared balance file lives in a private service-owned directory; worker and service must be able to access it, but no static server should serve it. The worker writes only filtered balance data, no key. Explicitly verify protected credential egress before scheduling refreshes.
7. Static rollback: atomically switch current to the recorded previous release. Backend rollback: restore the version-matched backup and restart only the bridge. Never restore an entire older dashboard over someone else's later edits; remove only the loader tag if uninstalling. Disable any optional refresh automation on uninstall.

Default listener is loopback only, Python stdlib, no CORS wildcard, no arbitrary upstream URL. A shared operator balance is visible to everyone authorized to view the dashboard. Session disconnect clears the browser-specific key; an enabled shared balance remains visible. Real account, access-provider login and physical-device checks are deployment-specific, not implied by mock browser regression success.
