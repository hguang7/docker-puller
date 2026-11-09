#!/bin/sh
# Verify the exact PHP version, legacy module baseline and K8s ConfigMap mount behavior.
# Intended to run INSIDE the new image with these bind mounts:
#  /php-m-baseline.txt
#  /usr/local/etc/php/conf.d/99-custom.ini
#  /usr/local/etc/php-fpm.d/www.conf
set -eu

fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

[ -r /php-m-baseline.txt ] || fail 'Missing /php-m-baseline.txt mount'
[ -r /usr/local/etc/php/conf.d/99-custom.ini ] || fail 'Missing custom php.ini mount'
[ -r /usr/local/etc/php-fpm.d/www.conf ] || fail 'Missing FPM www.conf mount'

echo '===== PHP CLI version ====='
php -v
actual_version="$(php -r 'echo PHP_VERSION;')"
[ "$actual_version" = '8.4.27' ] || fail "Expected 8.4.27, got $actual_version"
php-fpm -v | grep '8.4.27' >/dev/null || fail 'PHP-FPM version is not 8.4.27'

# Match module names case-insensitively; ignore headings, the extra Zend
# section, duplicates and comment lines in the supplied legacy php -m dump.
extract_modules() {
    awk '
        /^\[PHP Modules\]$/ {inside=1; next}
        /^\[Zend Modules\]$/ {inside=0}
        inside && NF && $0 !~ /^#/ {print tolower($0)}
    ' "$1" | LC_ALL=C sort -u
}

php -m > /tmp/new-php-modules.txt
extract_modules /php-m-baseline.txt > /tmp/expected-modules.txt
extract_modules /tmp/new-php-modules.txt > /tmp/actual-modules.txt
comm -23 /tmp/expected-modules.txt /tmp/actual-modules.txt > /tmp/missing-modules.txt
comm -13 /tmp/expected-modules.txt /tmp/actual-modules.txt > /tmp/extra-modules.txt

echo '===== Compare legacy PHP modules ====='
printf 'Legacy modules: '; wc -l < /tmp/expected-modules.txt
printf 'New modules:    '; wc -l < /tmp/actual-modules.txt
if [ -s /tmp/missing-modules.txt ]; then
    cat /tmp/missing-modules.txt >&2
    fail 'Missing modules from original Bitnami PHP 8.4.10 image'
fi
if [ -s /tmp/extra-modules.txt ]; then
    echo 'Additional modules in the new image (informational):'
    cat /tmp/extra-modules.txt
fi

echo '===== Zend OPcache ====='
php -r 'if (!extension_loaded("Zend OPcache")) { fwrite(STDERR, "Missing Zend OPcache\n"); exit(1); } echo "Zend OPcache available\n";'

echo '===== ConfigMap mounted PHP settings ====='
php --ini
php -r '
$expected = [
    "memory_limit" => "5120M",
    "upload_max_filesize" => "1536M",
    "post_max_size" => "2048M",
    "max_execution_time" => "3600",
    "output_buffering" => "0",
    "error_log" => "/var/www/html/logs/php_error.log",
];
foreach ($expected as $key => $value) {
    $actual = ini_get($key);
    if ((string)$actual !== $value) {
        fwrite(STDERR, "$key: expected $value, got $actual\n");
        exit(1);
    }
    echo "$key=$actual\n";
}
'

echo '===== PHP-FPM config / daemon user ====='
id daemon
[ -d /var/www/html/logs ] || fail 'Missing /var/www/html/logs directory'
php-fpm -tt > /tmp/fpm-config-test.log 2>&1 || {
    cat /tmp/fpm-config-test.log >&2
    fail 'php-fpm -tt failed with the original ConfigMap'
}
# Compare against the original pool listen and user, not a guess from CLI.
grep -Eq 'listen[[:space:]]*=[[:space:]]*9000' /tmp/fpm-config-test.log || {
    cat /tmp/fpm-config-test.log >&2
    fail 'PHP-FPM does not listen on port 9000'
}
grep -Eq 'user[[:space:]]*=[[:space:]]*daemon' /tmp/fpm-config-test.log || {
    cat /tmp/fpm-config-test.log >&2
    fail 'PHP-FPM pool user is not daemon'
}
echo 'FPM config valid, TCP port 9000, worker user daemon'
echo 'PASS: image-level tests complete; application tests on Kubernetes are still required.'
