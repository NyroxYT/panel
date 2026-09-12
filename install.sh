#!/usr/bin/env bash
set -Eeuo pipefail

IS_CODESPACES="${CODESPACES:-false}"
if [[ "$IS_CODESPACES" == "true" ]]; then
  BASE="${NXDACTYL_BASE:-$PWD/.nxdactyl}"
else
  BASE="${NXDACTYL_BASE:-/var/www/nxdactyl}"
fi
PANEL="$BASE/panel"
WINGS="$BASE/wings"
EGGS="$BASE/game-eggs"
PANEL_REPO=https://github.com/NyroxYT/panel.git
WINGS_REPO=https://github.com/NyroxYT/wings.git
EGGS_REPO=https://github.com/NyroxYT/game-eggs.git

log(){ printf '\n\033[1;36m[NxDactyl]\033[0m %s\n' "$*"; }
die(){ printf '\n\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2; exit 1; }
trap 'die "Installation failed on line $LINENO."' ERR

if [[ "$IS_CODESPACES" != "true" ]]; then
  [[ $EUID -eq 0 ]] || die 'Run as root.'
  . /etc/os-release
  [[ "$ID" == ubuntu || "$ID" == debian ]] || die 'Supported OS: Ubuntu/Debian.'
fi

HOST="${NXDACTYL_HOST:-localhost}"
TZ="${NXDACTYL_TIMEZONE:-UTC}"
if [[ -t 0 ]]; then
  read -r -p "Panel domain or IP [$HOST]: " input_host || true
  HOST="${input_host:-$HOST}"
  read -r -p "Timezone [$TZ]: " input_tz || true
  TZ="${input_tz:-$TZ}"
fi

if [[ "$IS_CODESPACES" == "true" ]]; then
  log 'GitHub Codespaces detected: running install/test mode (no systemd, Nginx, Docker daemon or apt changes).'
else
  log 'Installing PHP, Nginx, Redis, SQLite, Git, Node and Docker...'
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y ca-certificates curl git unzip nginx redis-server sqlite3 \
    php php-cli php-fpm php-curl php-gd php-mbstring php-xml php-zip php-bcmath php-sqlite3 php-mysql
  if ! command -v composer >/dev/null 2>&1; then
    curl -fsSL https://getcomposer.org/installer -o /tmp/composer.php
    php /tmp/composer.php --install-dir=/usr/local/bin --filename=composer
    rm -f /tmp/composer.php
  fi
  if ! command -v node >/dev/null 2>&1 || [[ "$(node -p 'parseInt(process.versions.node)')" -lt 22 ]]; then
    curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
    apt-get install -y nodejs
  fi
  if ! command -v yarn >/dev/null 2>&1; then
    npm install -g yarn@1.22.22 --force
  else
    log "Yarn already available: $(yarn --version)"
  fi
  command -v yarn >/dev/null 2>&1 || die 'Yarn installation failed.'
  command -v docker >/dev/null 2>&1 || curl -fsSL https://get.docker.com | sh
  systemctl enable --now docker redis-server nginx
fi

for cmd in git php composer node yarn; do
  command -v "$cmd" >/dev/null 2>&1 || die "Required command not found: $cmd"
done
php -m | grep -qi '^pdo_sqlite$' || die 'PHP SQLite PDO extension is missing.'

log "Creating $BASE/{panel,wings,game-eggs}..."
mkdir -p "$BASE"
clone(){
  local u=$1 d=$2 b=$3
  if [[ -d "$d/.git" ]]; then
    git -C "$d" fetch --depth=1 origin "$b"
    git -C "$d" reset --hard -q "origin/$b"
    git -C "$d" clean -fdx -q
  else
    git clone --depth=1 --branch "$b" "$u" "$d"
  fi
}
clone "$PANEL_REPO" "$PANEL" 1.0-develop
clone "$WINGS_REPO" "$WINGS" develop
clone "$EGGS_REPO" "$EGGS" main

cd "$PANEL"
log 'Configuring SQLite environment...'
[[ -f .env ]] || cp .env.example .env
mkdir -p database storage/framework/{cache,sessions,views} storage/logs bootstrap/cache
touch database/database.sqlite
sed -i -E "s|^APP_ENV=.*|APP_ENV=production|; s|^APP_DEBUG=.*|APP_DEBUG=false|; s|^APP_URL=.*|APP_URL=http://$HOST|; s|^APP_TIMEZONE=.*|APP_TIMEZONE=$TZ|; s|^DB_CONNECTION=.*|DB_CONNECTION=sqlite|; s|^DB_DATABASE=.*|DB_DATABASE=$PANEL/database/database.sqlite|; s|^CACHE_DRIVER=.*|CACHE_DRIVER=file|; s|^QUEUE_CONNECTION=.*|QUEUE_CONNECTION=redis|; s|^SESSION_DRIVER=.*|SESSION_DRIVER=file|" .env

log 'Checking Composer lockfile...'
if ! composer validate --no-check-publish --no-interaction >/tmp/nxdactyl-composer-validate.log 2>&1; then
  log 'composer.lock is not synchronized with composer.json; refreshing the lockfile...'
  if [[ "$IS_CODESPACES" == "true" ]]; then
    composer update --no-dev --with-all-dependencies --no-interaction \
      --ignore-platform-req=ext-zip \
      --ignore-platform-req=ext-pdo_mysql \
      --ignore-platform-req=ext-sodium \
      --ignore-platform-req=ext-bcmath
  else
    composer update --no-dev --with-all-dependencies --no-interaction
  fi
fi

log 'Installing PHP dependencies and migrating database...'
if [[ "$IS_CODESPACES" == "true" ]]; then
  composer install --no-dev --optimize-autoloader --no-interaction \
    --ignore-platform-req=ext-zip \
    --ignore-platform-req=ext-pdo_mysql \
    --ignore-platform-req=ext-sodium \
    --ignore-platform-req=ext-bcmath
else
  composer install --no-dev --optimize-autoloader --no-interaction
fi
php artisan key:generate --force
php artisan config:clear
php artisan migrate --force

log 'Building frontend...'
yarn install --frozen-lockfile --non-interactive
yarn run build:production
php artisan storage:link || true

if [[ "$IS_CODESPACES" == "true" ]]; then
  log 'Codespaces test complete: Panel dependencies, SQLite migrations and frontend build passed.'
  printf '\nPanel source: %s\nWings source: %s\nEggs source:  %s\nSQLite:       %s\n\n' "$PANEL" "$WINGS" "$EGGS" "$PANEL/database/database.sqlite"
  exit 0
fi

log 'Create the first Nx Panel administrator now.'
php artisan p:user:make --admin

SOCK=$(find /run/php -maxdepth 1 -type s -name 'php*-fpm.sock' | sort -V | tail -1)
[[ -n "$SOCK" ]] || die 'PHP-FPM socket not found.'
cat >/etc/nginx/sites-available/nxdactyl.conf <<NGINX
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
NGINX
ln -sfn /etc/nginx/sites-available/nxdactyl.conf /etc/nginx/sites-enabled/nxdactyl.conf
rm -f /etc/nginx/sites-enabled/default
nginx -t && systemctl reload nginx

log 'Building Wings with Go 1.24.1...'
ARCH=$(dpkg --print-architecture)
[[ "$ARCH" == amd64 || "$ARCH" == arm64 ]] || die "Unsupported architecture: $ARCH"
GOARCH=$([[ "$ARCH" == amd64 ]] && echo amd64 || echo arm64)
mkdir -p "$WINGS/build"
if command -v go >/dev/null 2>&1; then
  (cd "$WINGS" && GOOS=linux GOARCH="$GOARCH" go build -ldflags='-s -w' -o "build/wings_linux_$GOARCH" wings.go)
else
  docker run --rm --platform "linux/$GOARCH" -v "$WINGS:/src" -w /src golang:1.24.1 sh -c "GOOS=linux GOARCH=$GOARCH go build -ldflags='-s -w' -o build/wings_linux_$GOARCH wings.go"
fi
install -m 0755 "$WINGS/build/wings_linux_$GOARCH" /usr/local/bin/wings
mkdir -p /etc/pterodactyl
cat >/etc/systemd/system/wings.service <<SERVICE
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
SERVICE
systemctl daemon-reload
systemctl enable wings

chown -R www-data:www-data "$PANEL/storage" "$PANEL/bootstrap/cache" "$PANEL/database/database.sqlite"
chmod 664 "$PANEL/database/database.sqlite"

log 'INSTALL COMPLETE'
printf '\nPanel: http://%s\nPanel: %s\nWings: %s\nEggs:  %s\nSQLite: %s\n\nCreate a Node in Nx Panel, generate its Wings config, save it to /etc/pterodactyl/config.yml, then run: systemctl start wings\n' "$HOST" "$PANEL" "$WINGS" "$EGGS" "$PANEL/database/database.sqlite"
