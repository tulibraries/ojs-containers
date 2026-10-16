# Security documentation

This directory records findings that cannot be safely removed while keeping the
application on the current OJS release, along with the checks required for
runtime content that is mounted outside the image.

## Current baseline

- OJS remains pinned to `3_4_0-9`; this cleanup does not run an OJS or database
  upgrade.
- The Alpine runtime runs `apk upgrade` before installing PHP and Apache
  packages.
- The build refreshes the Composer dependencies in `lib/pkp` and the PayPal
  plugin without changing the OJS release.
- A Trivy scan of `local/ojs:3_4_0-9` on 2026-10-16 reported one High, two
  Medium, two Low, and one Unknown finding. The High/Critical result was one
  High and zero Critical findings. The remaining findings are documented in
  [Laravel-GHSA-5vg9-5847-vvmq](Laravel-GHSA-5vg9-5847-vvmq) and
  [Firebase-CVE-2025-45769](Firebase-CVE-2025-45769).

## Runtime plugin volume

The Compose configuration mounts the persistent plugins directory at
`/var/www/html/ojs/plugins`. This is required because journal administrators
can install and maintain plugins through the OJS dashboard. A populated PVC or
host volume hides the image's copy of that directory, so an image scan does not
fully represent the code that runs in production.

Before deployment, and after plugins are added or changed, scan the mounted
plugins content or a backup/archive of it. Keep the plugins volume tied to the
OJS release and back it up before any OJS upgrade. Do not treat a clean image
scan as approval for arbitrary administrator-installed plugins.

## Build caveat

The dependency refresh is intentionally performed without changing the OJS
release. PKP Composer patches for older dependency versions may be skipped
when they no longer apply to the refreshed package. The application must be
smoke-tested after each dependency refresh, especially login, publishing,
email, scheduled tasks, and administrator plugin management.
