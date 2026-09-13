#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================
# NX DACTYL NEW HOSTING INSTALLER
# Made By Nyrox | Author Nyrox
# ============================================================

IS_CODESPACES="${CODESPACES:-false}"
if [[ "$IS_CODESPACES" == "true" ]]; then
    BASE="${NXDACTYL_BASE:-$PWD/.nxdactyl}"
else
    BASE="${NXDACTYL_BASE:-/var/www/nxdactyl}"
fi

PANEL="$BASE/panel"
WINGS="$BASE/wings"
EGGS="$BASE/game-eggs"
PANEL_REPO="https://github.com/NyroxYT/panel.git"
WINGS_REPO="https://github.com/NyroxYT/wings.git"
EGGS_REPO="https://github.com/NyroxYT/game-eggs.git"
CLOUDFLARE_INSTALLER="https://raw.githubusercontent.com/NyroxYT/NyroxHub/refs/heads/main/toolbox/cloudflare.sh"

CYAN='\033[1;36m'
BLUE='\033[1;34m'
PURPLE='\033[1;35m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
WHITE='\033[1;37m'
RESET='\033[0m'

clear_screen() { clear 2>/dev/null || true; }

banner() {
    clear_screen
    printf "%b\n" "${PURPLE}╔══════════════════════════════════════════════════════════╗${RESET}"
    printf "%b\n" "${PURPLE}║${WHITE}                 NX DACTYL NEW HOSTING                 ${PURPLE}║${RESET}"
    printf "%b\n" "${PURPLE}║${CYAN}              Made By Nyrox | Author Nyrox              ${PURPLE}║${RESET}"
    printf "%b\n" "${PURPLE}╚══════════════════════════════════════════════════════════╝${RESET}"
    printf '\n'
}

panel_wings_banner() {
    clear_screen
    printf "%b\n" "${BLUE}╔══════════════════════════════════════════════════════════╗${RESET}"
    printf "%b\n" "${BLUE}║${WHITE}            NX WINGS & NX PANEL INSTALL                ${BLUE}║${RESET}"
    printf "%b\n" "${BLUE}╚══════════════════════════════════════════════════════════╝${RESET}"
    printf '\n'
}

cloudflare_banner() {
    clear_screen
    printf "%b\n" "${CYAN}╔══════════════════════════════════════════════════════════╗${RESET}"
    printf "%b\n" "${CYAN}║${WHITE}          NX DACTYL CLOUDFLARE INSTALLER              ${CYAN}║${RESET}"
    printf "%b\n" "${CYAN}╚══════════════════════════════════════════════════════════╝${RESET}"
    printf '\n'
}

info_banner() {
    clear_screen
    printf "%b\n" "${GREEN}╔══════════════════════════════════════════════════════════╗${RESET}"
    printf "%b\n" "${GREEN}║${WHITE}              NX PANEL & WINGS INFORMATION             ${GREEN}║${RESET}"
    printf "%b\n" "${GREEN}╚══════════════════════════════════════════════════════════╝${RESET}"
    printf '\n'
}

log() { printf '\n%b[NxDactyl]%b %s\n' "$CYAN" "$RESET" "$*"; }
success() { printf '%b✓%b %s\n' "$GREEN" "$RESET" "$*"; }
warn() { printf '%b!%b %s\n' "$YELLOW" "$RESET" "$*"; }
die() { printf '\n%b[ERROR]%b %s\n' "$RED" "$RESET" "$*" >&2; exit 1; }

trap 'printf "\n%b[ERROR]%b Installer failed on line %s.\n" "$RED" "$RESET" "$LINENO" >&2' ERR

pause_menu() {
    printf '\n%bPress Enter to continue...%b' "$YELLOW" "$RESET"
    read -r _ || true
}

require_root() {
    if [[ "$IS_CODESPACES" != "true" && $EUID -ne 0 ]]; then
        warn 'This action requires root. Run the installer with sudo/root.'
        return 1
    fi
    return 0
}

check_os() {
    [[ "$IS_CODESPACES" == "true" ]] && return 0
    [[ $EUID -eq 0 ]] || die 'Run as root.'
    [[ -f /etc/os-release ]] || die 'Cannot detect operating system.'
    . /etc/os-release
    [[ "$ID" == "ubuntu" || "$ID" == "debian" ]] || die 'Supported OS: Ubuntu/Debian.'
}

install_system_dependencies() {
    require_root || return 1
    if [[ "$IS_CODESPACES" == "true" ]]; then
        log 'GitHub Codespaces detected: skipping system package/service setup.'
        return 0
    fi

    log 'Installing PHP, Nginx, Redis, SQLite, Git, Node and Docker...'
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y ca-certificates curl git unzip nginx redis-server sqlite3 \
        php php-cli php-fpm php-curl php-gd php-mbstring php-xml php-zip php-bcmath php-sqlite3

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
    fi

    command -v docker >/dev/null 2>&1 || curl -fsSL https://get.docker.com | sh
    systemctl enable --now docker redis-server nginx
}

check_commands() {
    local cmd
    for cmd in git curl php composer node yarn; do
        command -v "$cmd" >/dev/null 2>&1 || die "Required command not found: $cmd"
    done
    php -m | grep -qi '^pdo_sqlite$' || die 'PHP SQLite PDO extension is missing.'
}

clone_or_update() {
    local repo_url="$1" directory="$2" branch="$3"
    if [[ -d "$directory/.git" ]]; then
        log "Updating $directory..."
        git -C "$directory" fetch --depth=1 origin "$branch"
        git -C "$directory" reset --hard -q "origin/$branch"
        git -C "$directory" clean -fdx -q
    else
        mkdir -p "$(dirname "$directory")"
        log "Cloning $repo_url..."
        git clone --depth=1 --branch "$branch" "$repo_url" "$directory"
    fi
}

configure_panel_environment() {
    local host="${NXDACTYL_HOST:-localhost}" timezone="${NXDACTYL_TIMEZONE:-UTC}"
    if [[ -t 0 ]]; then
        read -r -p "Panel domain or IP [$host]: " input_host || true
        host="${input_host:-$host}"
        read -r -p "Timezone [$timezone]: " input_tz || true
        timezone="${input_tz:-$timezone}"
    fi

    cd "$PANEL"
    [[ -f .env ]] || cp .env.example .env
    mkdir -p database storage/framework/{cache,sessions,views} storage/logs bootstrap/cache
    touch database/database.sqlite
    sed -i -E \
        "s|^APP_ENV=.*|APP_ENV=production|; \
         s|^APP_DEBUG=.*|APP_DEBUG=false|; \
         s|^APP_URL=.*|APP_URL=http://$host|; \
         s|^APP_TIMEZONE=.*|APP_TIMEZONE=$timezone|; \
         s|^DB_CONNECTION=.*|DB_CONNECTION=sqlite|; \
         s|^DB_DATABASE=.*|DB_DATABASE=$PANEL/database/database.sqlite|; \
         s|^CACHE_DRIVER=.*|CACHE_DRIVER=file|; \
         s|^QUEUE_CONNECTION=.*|QUEUE_CONNECTION=redis|; \
         s|^SESSION_DRIVER=.*|SESSION_DRIVER=file|" .env
}

install_panel() {
    panel_wings_banner
    printf '%b[1] INSTALL NX PANEL%b\n\n' "$GREEN" "$RESET"
    require_root || return 1
    install_system_dependencies || return 1
    check_commands

    log "Installing Nx Panel into $PANEL"
    mkdir -p "$BASE"
    clone_or_update "$PANEL_REPO" "$PANEL" "1.0-develop"
    configure_panel_environment

    log 'Checking Composer lockfile...'
    if ! composer validate --no-check-publish --no-interaction >/tmp/nxdactyl-composer-validate.log 2>&1; then
        log 'Refreshing Composer lockfile...'
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

    log 'Installing PHP dependencies and migrating SQLite database...'
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

    log 'Building Nx Panel frontend...'
    yarn install --frozen-lockfile --non-interactive
    yarn run build:production
    php artisan storage:link || true

    if [[ "$IS_CODESPACES" == "true" ]]; then
        success 'Nx Panel installation/test completed in Codespaces.'
        printf '\nPanel: %s\nSQLite: %s\n' "$PANEL" "$PANEL/database/database.sqlite"
        return 0
    fi

    log 'Create the first Nx Panel administrator now.'
    php artisan p:user:make --admin

    local sock
    sock=$(find /run/php -maxdepth 1 -type s -name 'php*-fpm.sock' | sort -V | tail -1)
    [[ -n "$sock" ]] || die 'PHP-FPM socket not found.'

    local host="${NXDACTYL_HOST:-localhost}"
    cat >/etc/nginx/sites-available/nxdactyl.conf <<NGINX
server {
    listen 80;
    listen [::]:80;
    server_name $host;
    root $PANEL/public;
    index index.php;
    location / { try_files \$uri \$uri/ /index.php?\$query_string; }
    location ~ \.php$ { include snippets/fastcgi-php.conf; fastcgi_pass unix:$sock; }
    location ~ /\.(?!well-known).* { deny all; }
}
NGINX

    ln -sfn /etc/nginx/sites-available/nxdactyl.conf /etc/nginx/sites-enabled/nxdactyl.conf
    rm -f /etc/nginx/sites-enabled/default
    nginx -t && systemctl reload nginx
    chown -R www-data:www-data "$PANEL/storage" "$PANEL/bootstrap/cache" "$PANEL/database/database.sqlite"
    chmod 664 "$PANEL/database/database.sqlite"
    success 'Nx Panel installed successfully.'
}

install_wings() {
    panel_wings_banner
    printf '%b[2] INSTALL NX WINGS%b\n\n' "$GREEN" "$RESET"
    require_root || return 1
    install_system_dependencies || return 1
    command -v git >/dev/null 2>&1 || die 'Git is required.'
    command -v docker >/dev/null 2>&1 || die 'Docker is required for Wings.'

    mkdir -p "$BASE"
    clone_or_update "$WINGS_REPO" "$WINGS" "develop"
    log 'Building Nx Wings...'

    local arch goarch
    arch=$(dpkg --print-architecture 2>/dev/null || uname -m)
    case "$arch" in
        amd64|x86_64) goarch='amd64' ;;
        arm64|aarch64) goarch='arm64' ;;
        *) die "Unsupported architecture: $arch" ;;
    esac

    mkdir -p "$WINGS/build"
    if command -v go >/dev/null 2>&1; then
        (cd "$WINGS" && GOOS=linux GOARCH="$goarch" go build -ldflags='-s -w' -o "build/wings_linux_$goarch" wings.go)
    else
        docker run --rm --platform "linux/$goarch" -v "$WINGS:/src" -w /src golang:1.24.1 \
            sh -c "GOOS=linux GOARCH=$goarch go build -ldflags='-s -w' -o build/wings_linux_$goarch wings.go"
    fi

    if [[ "$IS_CODESPACES" == "true" ]]; then
        success 'Nx Wings build completed in Codespaces.'
        printf 'Wings source: %s\n' "$WINGS"
        return 0
    fi

    install -m 0755 "$WINGS/build/wings_linux_$goarch" /usr/local/bin/wings
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
    success 'Nx Wings installed. Add the node configuration to /etc/pterodactyl/config.yml, then start with: systemctl start wings'
}

install_panel_and_wings() {
    while true; do
        panel_wings_banner
        printf '%b[1]%b install NX PANEL\n' "$GREEN" "$RESET"
        printf '%b[2]%b install NX WINGS\n' "$GREEN" "$RESET"
        printf '%b[3]%b create your own egg %b(soon)%b\n' "$GREEN" "$RESET" "$YELLOW" "$RESET"
        printf '%b[0]%b exit INSTALLER %b(back to main menu)%b\n\n' "$RED" "$RESET" "$YELLOW" "$RESET"
        read -r -p 'Select option: ' choice
        case "$choice" in
            1) install_panel; pause_menu ;;
            2) install_wings; pause_menu ;;
            3) panel_wings_banner; warn 'Create your own egg — SOON.'; pause_menu ;;
            0) return 0 ;;
            *) warn 'Invalid option.'; sleep 1 ;;
        esac
    done
}

install_cloudflare() {
    cloudflare_banner
    require_root || return 1
    command -v curl >/dev/null 2>&1 || die 'curl is required.'
    log 'Downloading Nx Dactyl Cloudflare installer...'
    local temp_script
    temp_script=$(mktemp)
    curl -fsSL "$CLOUDFLARE_INSTALLER" -o "$temp_script"
    chmod +x "$temp_script"
    log 'Starting Cloudflare installer...'
    bash "$temp_script"
    rm -f "$temp_script"
    success 'Cloudflare installer finished.'
}

uninstall_cloudflare() {
    cloudflare_banner
    require_root || return 1
    log 'Uninstalling Cloudflare Tunnel service...'
    if command -v cloudflared >/dev/null 2>&1; then
        cloudflared service uninstall || true
    fi
    if [[ "$IS_CODESPACES" != "true" ]] && command -v apt-get >/dev/null 2>&1; then
        export DEBIAN_FRONTEND=noninteractive
        apt-get remove -y cloudflared 2>/dev/null || true
        apt-get autoremove -y 2>/dev/null || true
    fi
    rm -f /usr/local/bin/cloudflared
    success 'Cloudflare has been uninstalled.'
}

cloudflare_menu() {
    while true; do
        cloudflare_banner
        printf '%b[1]%b install cloudflare\n' "$GREEN" "$RESET"
        printf '%b[2]%b uninstall cloudflare\n' "$RED" "$RESET"
        printf '%b[0]%b EXIT CLOUDFLARE INSTALLER %b(back to main menu)%b\n\n' "$YELLOW" "$RESET" "$YELLOW" "$RESET"
        read -r -p 'Select option: ' choice
        case "$choice" in
            1) install_cloudflare; pause_menu ;;
            2) uninstall_cloudflare; pause_menu ;;
            0) return 0 ;;
            *) warn 'Invalid option.'; sleep 1 ;;
        esac
    done
}

show_information() {
    info_banner
    local panel_status wings_status
    if [[ -d "$PANEL/.git" ]]; then panel_status="${GREEN}INSTALLED${RESET}"; else panel_status="${RED}NOT INSTALLED${RESET}"; fi
    if [[ -d "$WINGS/.git" || -x /usr/local/bin/wings ]]; then wings_status="${GREEN}INSTALLED${RESET}"; else wings_status="${RED}NOT INSTALLED${RESET}"; fi

    printf '%bPanel status:%b   %b\n' "$WHITE" "$RESET" "$panel_status"
    printf '%bPanel directory:%b %s\n\n' "$WHITE" "$RESET" "${PANEL:-—}"
    printf '%bWings status:%b   %b\n' "$WHITE" "$RESET" "$wings_status"
    printf '%bWings directory:%b %s\n\n' "$WHITE" "$RESET" "${WINGS:-—}"
    printf '%bBase directory:%b   %s\n' "$WHITE" "$RESET" "$BASE"
    printf '%bAuthor:%b          NyroxYT\n\n' "$WHITE" "$RESET"
    printf '%bSubscribe My YT Channel:%b\n' "$WHITE" "$RESET"
    printf 'https://youtube.com/@nyroxyt_official?feature=shared\n\n'
    pause_menu
}

push_egg_menu() {
    banner
    warn 'PUSH YOUR EGG — SOON'
    printf '\nThis feature will let users create their own egg from the installer and push it to their egg repository.\n'
    printf 'Coming soon...\n'
    pause_menu
}

main_menu() {
    check_os
    while true; do
        banner
        printf '%b[1]%b install panel and wings\n' "$GREEN" "$RESET"
        printf '%b[2]%b INSTALL CLOUDFLARE\n' "$GREEN" "$RESET"
        printf '%b[3]%b INFORMATION NX PANEL & WINGS\n' "$GREEN" "$RESET"
        printf '%b[4]%b push your egg %b[soon]%b\n' "$GREEN" "$RESET" "$YELLOW" "$RESET"
        printf '%b[0]%b EXIT NX DACTYL INSTALLER SCRIPT\n\n' "$RED" "$RESET"
        read -r -p 'Select option: ' choice
        case "$choice" in
            1) install_panel_and_wings ;;
            2) cloudflare_menu ;;
            3) show_information ;;
            4) push_egg_menu ;;
            0)
                clear_screen
                printf '\n%bTHANK YOU FOR USING NX DACTYL SCRIPT BYE..%b\n\n' "$CYAN" "$RESET"
                exit 0
                ;;
            *) warn 'Invalid option.'; sleep 1 ;;
        esac
    done
}

main_menu
