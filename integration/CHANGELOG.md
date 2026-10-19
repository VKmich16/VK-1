# Standalone web integration changelog

## Standalone integration v0.1.0 - 2026-10-10

### Added
- Independent audited dashboard host patches, pinned-source builder and browser/backend tests.
- Mouse/touch menus, persistent iframe-safe drag, transparent hit testing and lifecycle cleanup.
- Same-origin ephemeral balance sessions and opt-in sanitized shared-account snapshots.
- Portable HTTPS deployment/rollback examples and credential-free OpenClaw refresh payload example.

### Notes
- `dsh-plugin/` remains unchanged at 1.0.2; standalone integration versioning is separate.
- All generated assets preserve MIT attribution. No deployment credentials/logs are included.

## Standalone integration v0.1.1 - 2026-10-10

### Fixed
- Select the protected Gateway HTTPS proxy explicitly when synchronizing a shared balance; inherited lowercase proxy variables no longer bypass credential substitution.
- Add proxy-precedence and fail-closed regression checks. The original DSH plugin remains at its unchanged version.
