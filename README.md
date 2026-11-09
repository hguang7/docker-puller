# qczdy PHP-FPM 8.4.27 build package

This package builds a production candidate image **without changing Kubernetes or application files**.

## Files

- `Dockerfile`: official PHP `8.4.27-fpm-bookworm` + modules required by the old Bitnami installation.
- `.github/workflows/build-php.yml`: manually-triggered GitHub Actions job; compiles, checks, smokes, exports and uploads.
- `verify-php.sh`: fails the workflow if the PHP version, old module baseline or mounted FPM configuration is incompatible.
- `php-m-baseline.txt`: unchanged `php -m` output from your Bitnami PHP 8.4.10 container.
- `config/php.ini` and `config/www.conf`: extracted from your original production `php-config` ConfigMap; used **only to test**, not baked into the final image.

## Steps

1. Copy all these files to the **root** of your existing GitHub repository, preserving `.github/workflows/build-php.yml`.
2. In GitHub open **Actions → Build qczdy PHP-FPM 8.4.27 → Run workflow**.
3. Wait for all checks to pass. If it fails, open the failing step logs and resolve before uploading any new image to the cloud-native platform.
4. Download the `qczdy-php-fpm-8.4.27-r1-amd64` workflow artifact ZIP. Extract its `.tar.gz` image and `.sha256` checksum.
5. Verify checksum locally with `sha256sum -c qczdy-php-fpm_8.4.27-r1_amd64.tar.gz.sha256` (or an equivalent hash checker).
6. Import the resulting **Docker save archive** into your cloud-native image registry. If the platform requires `.tar` rather than `.tar.gz`, decompress the `.tar.gz` file before upload.
7. Tag the imported image as a **new tag**, e.g. `registry.szlanyou.com/qczdy-prod/php-fpm-custom:8.4.27-r1`. Do not overwrite the old Bitnami image.
8. Only after that, prepare a separate Kubernetes test Deployment with the new image. Switch the old Bitnami mounts to:
    - `config/php.ini` ConfigMap key → `/usr/local/etc/php/conf.d/99-custom.ini` with `subPath: php.ini`
    - `config/www.conf` ConfigMap key → `/usr/local/etc/php-fpm.d/www.conf` with `subPath: www.conf`
   Do not attach the new Pod to the production `php-svc` selector until application tests are finished.

## Important limitations

- The workflow itself performs **image-level checks only**. It cannot validate the application, database, PVC permissions, label printing or request processing inside your cloud-native platform.
- The existing `php-config` sets `memory_limit=5120M`, but the Deployment memory limit is `4Gi`. This carries OOM risk and should be tuned separately; not changed during the version migration.
- The existing worker account is `daemon` on Debian. Kubernetes PVC permissions, log directory ownership, and any Bitnami-specific runtime assumptions must be tested in the real cluster.
- Compiled modules may exist but behave differently across systems (e.g. `gd` codecs, LDAP TLS trust). Business acceptance tests are still essential.
- The Actions runner must have access to Docker Hub, the extension-installer image, and Debian package repositories. A build failure is not equivalent to a successful migration.
- The output archive contains **the newly built image**, not the original base image ZIP you downloaded previously. There is no need to upload the earlier ZIP to GitHub.
