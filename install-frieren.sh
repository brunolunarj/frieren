#!/bin/sh

# Constantes do projeto
BASE_URL="https://raw.githubusercontent.com/xchwarze/frieren-release/master/packages/openwrt"
PACKAGE_NAME="frieren"
TMP_APK="/tmp/package.apk"

# Opção de instalação forçada (ex: -f)
FORCE_INSTALL="$1"

# Logger com timestamp
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$2] $1"
}

# Tratamento de erros
handle_error() {
    log "Erro: $2 (Código: $1)" "ERROR"
    if [ "$1" -eq 1 ] && [ -z "$FORCE_INSTALL" ]; then
        log "Dica: Execute com '-f' para forçar a instalação." "INFO"
    fi
    exit "$1"
}

# Obtém a URL do pacote baseado na versão
get_package_url() {
    local version="$(awk -F"'" '/DISTRIB_RELEASE/{print $2}' /etc/openwrt_release | cut -d'.' -f1)"
    
    if [ "$version" -ge 20 ]; then
        echo "${BASE_URL}/latest/${PACKAGE_NAME}_latest.ipk"
    else
        echo "${BASE_URL}/19/${PACKAGE_NAME}_latest.ipk"
    fi
}

# Remove versão antiga se existir
uninstall_old_package() {
    if apk info "$PACKAGE_NAME" >/dev/null 2>&1; then
        log "Removendo pacote antigo: $PACKAGE_NAME..." "INFO"
        apk del "$PACKAGE_NAME" || handle_error 1 "Falha ao remover pacote via apk del"
    fi
}

# Instalação principal
install_package() {
    local package_url="$(get_package_url)"
    
    if [ -z "$package_url" ]; then
        handle_error 1 "Não foi possível determinar a URL do pacote."
    fi

    log "Atualizando índices do APK..." "INFO"
    apk update || handle_error 1 "Falha no apk update"

    log "Baixando e instalando pacote..." "INFO"
    wget -qO "$TMP_APK" "$package_url" || handle_error 1 "Falha no download via wget"

    local apk_cmd="apk add --allow-untrusted"
    
    if [ "$FORCE_INSTALL" = "-f" ]; then
        $apk_cmd --force-overwrite "$TMP_APK" || handle_error 1 "Falha na instalação forçada"
    else
        $apk_cmd "$TMP_APK" || handle_error 1 "Falha na instalação padrão"
    fi

    log "Instalação concluída com sucesso via APK" "SUCCESS"
    rm -f "$TMP_APK"
}

# Reinicia serviços necessários
restart_services() {
    log "Reiniciando serviços (Nginx/PHP)..." "INFO"
    /etc/init.d/nginx restart
    
    if [ -x "/etc/init.d/php8-fpm" ]; then
        /etc/init.d/php8-fpm restart
    elif [ -x "/etc/init.d/php7-fpm" ]; then
        /etc/init.d/php7-fpm restart
    fi
}

display_access_url() {
    local ip_address="$(ip -4 addr show br-lan | awk '/inet/ {print $2}' | cut -d'/' -f1)"
    log "Acesse a interface em: http://$ip_address:5000/" "INFO"
}

# Execução
if [ -f "/etc/openwrt_release" ]; then
    uninstall_old_package
    install_package
    restart_services
    display_access_url
else
    log "Este sistema não parece ser OpenWrt." "ERROR"
    exit 1
fi
