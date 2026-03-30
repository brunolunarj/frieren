#!/bin/sh

# Constantes do projeto
BASE_URL="https://raw.githubusercontent.com/xchwarze/frieren-release/master/packages/openwrt"
PACKAGE_NAME="frieren"
TMP_IPK="/tmp/package.ipk"

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

# Obtém a URL do pacote baseado na versão do OpenWrt
get_package_url() {
    local version="$(awk -F"'" '/DISTRIB_RELEASE/{print $2}' /etc/openwrt_release | cut -d'.' -f1)"
    
    if [ "$version" -ge 21 ]; then
        echo "${BASE_URL}/latest/${PACKAGE_NAME}_latest.ipk"
    elif [ "$version" -ge 20 ]; then
        echo "${BASE_URL}/20/${PACKAGE_NAME}_latest.ipk"
    else
        echo "${BASE_URL}/19/${PACKAGE_NAME}_latest.ipk"
    fi
}

# Remove versão antiga se existir
uninstall_old_package() {
    if opkg list-installed | grep -q "^${PACKAGE_NAME}"; then
        log "Removendo pacote antigo: $PACKAGE_NAME..." "INFO"
        opkg remove "$PACKAGE_NAME" || handle_error 1 "Falha ao remover pacote via opkg remove"
    fi
}

# Instalação principal
install_package() {
    local package_url="$(get_package_url)"
    
    if [ -z "$package_url" ]; then
        handle_error 1 "Não foi possível determinar a URL do pacote."
    fi

    log "Atualizando índices do opkg..." "INFO"
    opkg update || handle_error 1 "Falha no opkg update"

    log "Baixando e instalando pacote..." "INFO"
    wget -qO "$TMP_IPK" "$package_url" || handle_error 1 "Falha no download via wget"

    log "Instalando pacote via opkg..." "INFO"
    
    if [ "$FORCE_INSTALL" = "-f" ]; then
        opkg install --force-overwrite "$TMP_IPK" || handle_error 1 "Falha na instalação forçada"
    else
        opkg install "$TMP_IPK" || handle_error 1 "Falha na instalação padrão"
    fi

    log "Instalação concluída com sucesso via opkg" "SUCCESS"
    rm -f "$TMP_IPK"
}

# Reinicia serviços necessários
restart_services() {
    log "Reiniciando serviços..." "INFO"
    
    if [ -x "/etc/init.d/nginx" ]; then
        /etc/init.d/nginx restart || log "Aviso: Falha ao reiniciar nginx" "WARN"
    fi
    
    if [ -x "/etc/init.d/php8-fpm" ]; then
        /etc/init.d/php8-fpm restart || log "Aviso: Falha ao reiniciar php8-fpm" "WARN"
    elif [ -x "/etc/init.d/php7-fpm" ]; then
        /etc/init.d/php7-fpm restart || log "Aviso: Falha ao reiniciar php7-fpm" "WARN"
    fi
}

display_access_url() {
    local ip_address="$(ip -4 addr show br-lan 2>/dev/null | awk '/inet/ {print $2}' | cut -d'/' -f1)"
    
    if [ -z "$ip_address" ]; then
        ip_address="$(ip -4 addr show 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '^127' | head -n1)"
    fi
    
    if [ -n "$ip_address" ]; then
        log "Acesse a interface em: http://$ip_address:5000/" "INFO"
    else
        log "Não foi possível determinar o endereço IP. Acesse a interface manualmente." "WARN"
    fi
}

# Execução principal
main() {
    if [ ! -f "/etc/openwrt_release" ]; then
        log "Este sistema não parece ser OpenWrt." "ERROR"
        exit 1
    fi
    
    uninstall_old_package
    install_package
    restart_services
    display_access_url
}

# Inicia execução
main
