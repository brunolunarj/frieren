#!/bin/sh

# Define constants
BASE_URL="https://raw.githubusercontent.com/xchwarze/frieren-release/master/packages/openwrt"
PACKAGE_NAME="frieren"

# Get force install option from command line
FORCE_INSTALL=$1

# Detect package manager
if command -v apk >/dev/null 2>&1; then
    PKG_MGR="apk"
elif command -v opkg >/dev/null 2>&1; then
    PKG_MGR="opkg"
else
    echo "Error: No package manager (apk or opkg) found."
    exit 1
fi

# Logger function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$2] $1"
}

# Error handler function
handle_error() {
    log "Error: $2 (Exit Code: $1)" "ERROR"
    if [ "$1" -eq 1 ] && [ -z "$FORCE_INSTALL" ]; then
        log "Tip: Run the script with '-f' to force the installation if you encounter file clashes." "INFO"
    fi
    exit "$1"
}

# Function to check OpenWRT version and return package URL
get_package_url() {
    local version="$1"
    local package_url=""

    # Se for versão 21 ou superior (incluindo a 25.x), usa o path 'latest'
    if [ "$version" = "19" ]; then
        package_url="${BASE_URL}/19/${PACKAGE_NAME}_latest.ipk"
    elif [ "$version" -ge 20 ]; then
        package_url="${BASE_URL}/latest/${PACKAGE_NAME}_latest.ipk"
    fi

    echo "$package_url"
}

# Function to uninstall old package
uninstall_old_package() {
    local installed=0
    
    if [ "$PKG_MGR" = "apk" ]; then
        apk info "$PACKAGE_NAME" >/dev/null 2>&1 && installed=1
    else
        opkg list-installed | grep -q "$PACKAGE_NAME" && installed=1
    fi

    if [ "$installed" -eq 1 ]; then
        log "Removing old package $PACKAGE_NAME using $PKG_MGR..." "INFO"
        if [ "$PKG_MGR" = "apk" ]; then
            apk del "$PACKAGE_NAME" || handle_error 1 "Failed to remove old package via apk"
        else
            opkg remove "$PACKAGE_NAME" || handle_error 1 "Failed to remove old package via opkg"
        fi
    fi
}

# Main installation function
install_package() {
    local version="$(awk -F"'" '/DISTRIB_RELEASE/{print $2}' /etc/openwrt_release | cut -d'.' -f1)"
    local package_url="$(get_package_url "$version")"

    if [ -z "$package_url" ]; then
        handle_error 1 "Failed to obtain package URL for version $version"
    fi

    log "Updating package lists using $PKG_MGR..." "INFO"
    $PKG_MGR update || handle_error 1 "Failed to update package lists"

    log "Downloading and installing package for OpenWRT $version..." "INFO"
    wget -qO /tmp/package.ipk "$package_url" && {
        if [ "$PKG_MGR" = "apk" ]; then
            # No apk, --allow-untrusted é comum para pacotes .ipk/local, 
            # e force-overwrite é simulado ou tratado pelo apk add
            local apk_args="add --allow-untrusted"
            [ "$FORCE_INSTALL" = "-f" ] && apk_args="$apk_args --force-overwrite"
            apk $apk_args /tmp/package.ipk || handle_error 1 "APK installation failed"
        else
            local opkg_args="install"
            [ "$FORCE_INSTALL" = "-f" ] && opkg_args="install --force-overwrite"
            opkg $opkg_args /tmp/package.ipk || handle_error 1 "OPKG installation failed"
        fi
    }

    log "Package installation completed successfully" "SUCCESS"
}

# ... rest of the functions (restart_services, display_access_url) remain the same ...

display_access_url() {
    local ip_address="$(ip -4 addr show br-lan | awk '/inet/ {print $2}' | cut -d'/' -f1)"
    log "To access the Frieren web interface: http://$ip_address:5000/" "INFO"
}

restart_services() {
    log "Restarting services..." "INFO"
    /etc/init.d/nginx restart
    if [ -f "/etc/php8-fpm.conf" ] || [ -d "/etc/php8" ]; then    
        /etc/init.d/php8-fpm restart
    else
        /etc/init.d/php7-fpm restart
    fi
}

if [ -f "/etc/openwrt_release" ]; then
    log "OpenWRT system detected ($PKG_MGR mode), proceeding..." "INFO"
    uninstall_old_package
    install_package
    restart_services
    display_access_url
else
    log "This script is only supported on OpenWRT systems." "ERROR"
    exit 1
fi