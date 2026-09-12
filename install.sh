#!/usr/bin/env bash
set -Eeuo pipefail

# Nx Panel production installer
# Installs the Panel, SQLite database, Redis queue backend, Nginx/PHP-FPM,
# NxDactyl Wings source/binary, and Nx Game Eggs under /var/www/nxdactyl.

BASE=/var/www/nxdactyl
PANEL_DIR="$BASE/panel"
WINGS_DIR="$BASE/wings"
EGGS_DIR="$BASE/game-eggs"
REPO_PANEL="https://github.com/NyroxYT/panel.git"
REPO_WINGS="https://github.com/NyroxYT/wings.git"
REPO_EGGS="https://github.com/NyroxYT/game-eggs.git"

log() { printf '\n\033[1;36m[NxDactyl]\033[0m %s\n' "$*"; }
fail() { printf '\n\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2; exit 1; }
trap 'fail "Installation failed on line $LINENO."' ERR

[[ $EUID -eq 0 ]] || fail "Run this installer as root."

. /etc/os-release
case "${ID:-}" in
    ubuntu|debian) ;;
    *) fail "Supported operating systems: Ubuntu or Debian." ;;
esac

ARCH="$(dpkg --print-architecture)"
case "$ARCH" in
    amd64) GOARCH=amd64 ;;
    arm64) GOARCH=arm64 ;;
    *) fail "Unsupported CPU architecture: $ARCH" ;;
esac

read -r -p "Panel domain (example: panel.example.com, or server IP): " PANEL_HOST
PANEL_HOST="${PANEL_HOST:-localhost}"
read -r -p "Timezone [UTC]: " APP_TZ
APP_TZ="${APP_TZ:-UTC}"

log "Installing OS dependencies..."
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y ca-certificates curl git unzip nginx redis-server sqlite3 \
    php php-cli php-fpm php-curl php-gd php-mbstring php-xml php-zip php-bcmath \
    php-sqlite3 php-tokenizer

log "Installing Composer..."
if ! command -v composer >/dev/null 2>&1; then
    curl -fsSL https://getcomposer.org/installer -o /tmp/composer-setup.php
    php /tmp/composer-setup.php --install-dir=/usr/local/bin --filename=composer
    rm -f /tmp/composer-setup.php
fi

log "Installing Node.js 22 and Yarn 1..."
if ! command -v node >/dev/null 2>&1 || [[ "$(node -p 'parseInt(process.versions.node)')" -lt 22 ]]; then
    curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
    apt-get install -y nodejs
fi
npm install -g yarn@1.22.22

log "Installing Docker..."
if ! command -v docker >/dev/null 2>&1; then
    curl -fsSL https://get.docker.com | sh
fi
systemctl enable --now docker redis-server nginx

log "Creating NxDactyl directory layout..."
mkdir -p "$BASE"

clone_or_update() {
    local url="$1" dir="$2" branch="$3"
    if [[ -d "$dir/.git" ]]; then
        git -C "$dir" fetch --depth=1 origin "$branch"
        git -C "$dir" checkout -q "$branch"
        git -C "$dir" reset --hard -q "origin/$branch"
    else
        git clone --depth=1 --branch "$branch" "$url" "$dir"
    fi
}

log "Fetching Nx Panel..."
clone_or_update "$REPO_PANEL" "$PANEL_DIR" "1.0-develop"

log "Fetching NxDactyl Wings..."
clone_or_update "$REPO_WINGS" "$WINGS_DIR" "develop"

log "Fetching Nx Game Eggs..."
clone_or_update "$REPO_EGGS" "$EGGS_DIR" "main"

cd "$PANEL_DIR"

log "Preparing environment..."
[[ -f .env ]] || cp .env.example .env
mkdir -p database storage/framework/{cache,sessions,views} storage/logs bootstrap/cache
DB_FILE="$PANEL_DIR/database/database.sqlite"
touch "$DB_FILE"

php -r '
$path = $argv[1];
$env = file_get_contents(".env");
$replace = [
    "/^APP_ENV=.*/m" => "APP_ENV=production",
    "/^APP_DEBUG=.*/m" => "APP_DEBUG=false",
    "/^APP_URL=.*/m" => "APP_URL=" . rtrim(getenv("NX_APP_URL"), "/"),
    "/^APP_TIMEZONE=.*/m" => "APP_TIMEZONE=" . getenv("NX_APP_TZ"),
    "/^DB_CONNECTION=.*/m" => "DB_CONNECTION=sqlite",
    "/^DB_DATABASE=.*/m" => "DB_DATABASE=" . $path,
    "/^CACHE_DRIVER=.*/m" => "CACHE_DRIVER=file",
    "/^QUEUE_CONNECTION=.*/m" => "QUEUE_CONNECTION=redis",
    "/^SESSION_DRIVER=.*/m" => "SESSION_DRIVER=file",
];
foreach ($replace as $pattern => $value) {
    $env = preg_replace($pattern, $value, $env);
}
file_put_contents(".env", $env);
' "$DB_FILE" NX_APP_URL="http://$PANEL_HOST" NX_APP_TZ="$APP_TZ"

log "Installing PHP dependencies..."
composer install --no-dev --optimize-autoloader --no-interaction

log "Generating application key and migrating SQLite..."
php artisan key:generate --force --ansi
php artisan config:clear
php artisan migrate --force --ansi

log "Building frontend assets..."
yarn install --frozen-lockfile --non-interactive
yarn run build:production

log "Creating storage link..."
php artisan storage:link || true

log "Creating first administrator account..."
php artisan p:user:make --admin

log "Installing PHP-FPM/Nginx configuration..."
PHP_FPM_SOCK="$(find /run/php -maxdepth 1 -type s -name 'php*-fpm.sock' | sort -V | tail -1)"
[[ -n "$PHP_FPM_SOCK" ]] || fail "Could not find PHP-FPM socket."
cat > /etc/nginx/sites-available/nxdactyl.conf <<NGINX
server {
    listen 80;
    listen [::]:80;
    server_name $PANEL_HOST;
    root $PANEL_DIR/public;

    index index.php;
    charset utf-8;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location = /favicon.ico { access_log off; log_not_found off; }
    location = /robots.txt  { access_log off; log_not_found off; }

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:$PHP_FPM_SOCK;
    }

    location ~ /\.(?!well-known).* {
        deny all;
    }
}
NGINX
ln -sfn /etc/nginx/sites-available/nxdactyl.conf /etc/nginx/sites-enabled/nxdactyl.conf
rm -f /etc/nginx/sites-enabled/default
nginx -t
systemctl reload nginx

log "Installing scheduler service..."
cat > /etc/systemd/system/nxdactyl-schedule.service <<SERVICE
[Unit]
Description=Nx Panel Scheduler
After=network.target

[Service]
Type=oneshot
User=www-data
Group=www-data
WorkingDirectory=$PANEL_DIR
ExecStart=/usr/bin/php $PANEL_DIR/artisan schedule:run
SERVICE

cat > /etc/systemd/system/nxdactyl-schedule.timer <<TIMER
[Unit]
Description=Run Nx Panel Scheduler every minute

[Timer]
OnBootSec=1min
OnUnitActiveSec=1min
Unit=nxdactyl-schedule.service

[Install]
WantedBy=timers.target
TIMER

log "Installing queue worker service..."
cat > /etc/systemd/system/nxdactyl-queue.service <<SERVICE
[Unit]
Description=Nx Panel Queue Worker
After=redis-server.service

[Service]
Type=simple
User=www-data
Group=www-data
Restart=always
RestartSec=5
WorkingDirectory=$PANEL_DIR
ExecStart=/usr/bin/php $PANEL_DIR/artisan queue:work --queue=high,standard,low --sleep=3 --tries=3 --timeout=120

[Install]
WantedBy=multi-user.target
SERVICE

systemctl daemon-reload
systemctl enable --now nxdactyl-schedule.timer nxdactyl-queue.service

log "Building NxDactyl Wings ($GOARCH)..."
mkdir -p "$WINGS_DIR/build"
docker run --rm \
    --platform "linux/$GOARCH" \
    -v "$WINGS_DIR:/src" \
    -w /src \
    "golang:1.24.1" \
    sh -c "GOOS=linux GOARCH=$GOARCH go build -ldflags='-s -w' -gcflags='all=-trimpath=/src' -o build/wings_linux_$GOARCH -v wings.go"
install -m 0755 "$WINGS_DIR/build/wings_linux_$GOARCH" /usr/local/bin/wings
mkdir -p /etc/pterodactyl

cat > /etc/systemd/system/wings.service <<SERVICE
[Unit]
Description=NxDactyl Wings Daemon
After=docker.service
Requires=docker.service

[Service]
User=root
WorkingDirectory=/etc/pterodactyl
LimitNOFILE=4096
PIDFile=/run/wings/daemon.pid
ExecStart=/usr/local/bin/wings
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
SERVICE
systemctl daemon-reload
systemctl enable wings

log "Applying ownership and permissions..."
chown -R www-data:www-data "$PANEL_DIR/storage" "$PANEL_DIR/bootstrap/cache" "$DB_FILE"
chmod -R ug+rwX "$PANEL_DIR/storage" "$PANEL_DIR/bootstrap/cache"
chmod 664 "$DB_FILE"

log "NxDactyl installation completed."
printf '\nPanel:     http://%s\nPanel dir: %s\nWings dir: %s\nEggs dir:  %s\nSQLite:    %s\n\n' \
    "$PANEL_HOST" "$PANEL_DIR" "$WINGS_DIR" "$EGGS_DIR" "$DB_FILE"
printf 'Next: create a Node in Nx Panel, generate its Wings configuration, save it as /etc/pterodactyl/config.yml, then run: systemctl start wings\n'
