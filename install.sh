#!/usr/bin/env bash
set -Eeuo pipefail

BASE=/var/www/nxdactyl
PANEL="$BASE/panel"
WINGS="$BASE/wings"
EGGS="$BASE/game-eggs"
PANEL_REPO=https://github.com/NyroxYT/panel.git
WINGS_REPO=https://github.com/NyroxYT/wings.git
EGGS_REPO=https://github.com/NyroxYT/game-eggs.git

log(){ printf '\n\033[1;36m[NxDactyl]\033[0m %s\n' "$*"; }
die(){ printf '\n\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2; exit 1; }
trap 'die "Installation failed on line $LINENO."' ERR
[[ $EUID -eq 0 ]] || die 'Run as root.'
. /etc/os-release
[[ "$ID" == ubuntu || "$ID" == debian ]] || die 'Supported OS: Ubuntu/Debian.'

read -r -p 'Panel domain or IP [localhost]: ' HOST
HOST=${HOST:-localhost}
read -r -p 'Timezone [UTC]: ' TZ
TZ=${TZ:-UTC}

log 'Installing PHP, Nginx, Redis, SQLite, Git, Node and Docker...'
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y ca-certificates curl git unzip nginx redis-server sqlite3 \
  php php-cli php-fpm php-curl php-gd php-mbstring php-xml php-zip php-bcmath php-sqlite3
if ! command -v composer >/dev/null; then
  curl -fsSL https://getcomposer.org/installer -o /tmp/composer.php
  php /tmp/composer.php --install-dir=/usr/local/bin --filename=composer
  rm -f /tmp/composer.php
fi
if ! command -v node >/dev/null || [[ "$(node -p 'parseInt(process.versions.node)')" -lt 22 ]]; then
  curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
  apt-get install -y nodejs
fi
npm install -g yarn@1.22.22
command -v docker >/dev/null || curl -fsSL https://get.docker.com | sh
systemctl enable --now docker redis-server nginx

log 'Creating /var/www/nxdactyl/{panel,wings,game-eggs}...'
mkdir -p "$BASE"
clone(){ local u=$1 d=$2 b=$3; if [[ -d "$d/.git" ]]; then git -C "$d" fetch --depth=1 origin "$b"; git -C "$d" reset --hard -q "origin/$b"; else git clone --depth=1 --branch "$b" "$u" "$d"; fi; }
clone "$PANEL_REPO" "$PANEL" 1.0-develop
clone "$WINGS_REPO" "$WINGS" develop
clone "$EGGS_REPO" "$EGGS" main

cd "$PANEL"
log 'Configuring SQLite environment...'
[[ -f .env ]] || cp .env.example .env
mkdir -p database storage/framework/{cache,sessions,views} storage/logs bootstrap/cache
touch database/database.sqlite
sed -i -E "s|^APP_ENV=.*|APP_ENV=production|; s|^APP_DEBUG=.*|APP_DEBUG=false|; s|^APP_URL=.*|APP_URL=http://$HOST|; s|^APP_TIMEZONE=.*|APP_TIMEZONE=$TZ|; s|^DB_CONNECTION=.*|DB_CONNECTION=sqlite|; s|^DB_DATABASE=.*|DB_DATABASE=$PANEL/database/database.sqlite|; s|^CACHE_DRIVER=.*|CACHE_DRIVER=file|; s|^QUEUE_CONNECTION=.*|QUEUE_CONNECTION=redis|; s|^SESSION_DRIVER=.*|SESSION_DRIVER=file|" .env

log 'Installing PHP dependencies and migrating database...'
composer install --no-dev --optimize-autoloader --no-interaction
php artisan key:generate --force
php artisan config:clear
php artisan migrate --force

log 'Building frontend...'
yarn install --frozen-lockfile --non-interactive
yarn run build:production
php artisan storage:link || true

log 'Create the first Nx Panel administrator now.'
php artisan p:user:make --admin

SOCK=$(find /run/php -maxdepth 1 -type s -name 'php*-fpm.sock' | sort -V | tail -1)
[[ -n "$SOCK" ]] || die 'PHP-FPM socket not found.'
cat >/etc/nginx/sites-available/nxdactyl.conf <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name $HOST;
    root $PANEL/public;
    index index.php;
    location / { try_files \$uri \$uri/ /index.php?\$query_string; }
    location ~ \.php$ { include snippets/fastcgi-php.conf; fastcgi_pass unix:$SOCK; }
    location ~ /\.(?!well-known).* { deny all; }
}
EOF
ln -sfn /etc/nginx/sites-available/nxdactyl.conf /etc/nginx/sites-enabled/nxdactyl.conf
rm -f /etc/nginx/sites-enabled/default
nginx -t && systemctl reload nginx

log 'Building Wings inside the Go 1.24.1 container...'
ARCH=$(dpkg --print-architecture); [[ "$ARCH" == amd64 || "$ARCH" == arm64 ]] || die "Unsupported architecture: $ARCH"
GOARCH=$([[ "$ARCH" == amd64 ]] && echo amd64 || echo arm64)
mkdir -p "$WINGS/build"
docker run --rm --platform "linux/$GOARCH" -v "$WINGS:/src" -w /src golang:1.24.1 \
  sh -c "GOOS=linux GOARCH=$GOARCH go build -ldflags='-s -w' -gcflags='all=-trimpath=/src' -o build/wings_linux_$GOARCH wings.go"
install -m 0755 "$WINGS/build/wings_linux_$GOARCH" /usr/local/bin/wings
mkdir -p /etc/pterodactyl
cat >/etc/systemd/system/wings.service <<EOF
[Unit]
Description=NxDactyl Wings Daemon
After=docker.service
Requires=docker.service
[Service]
User=root
WorkingDirectory=/etc/pterodactyl
ExecStart=/usr/local/bin/wings
Restart=on-failure
RestartSec=5
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable wings

chown -R www-data:www-data "$PANEL/storage" "$PANEL/bootstrap/cache" "$PANEL/database/database.sqlite"
chmod 664 "$PANEL/database/database.sqlite"

log 'INSTALL COMPLETE'
printf '\nPanel: http://%s\nPanel: %s\nWings: %s\nEggs:  %s\nSQLite: %s\n\nCreate a Node in Nx Panel, generate its Wings config, save it to /etc/pterodactyl/config.yml, then run: systemctl start wings\n' "$HOST" "$PANEL" "$WINGS" "$EGGS" "$PANEL/database/database.sqlite"
