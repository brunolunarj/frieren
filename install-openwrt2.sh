#!/bin/sh

# Constantes do projeto
BASE_URL="https://raw.githubusercontent.com/xchwarze/frieren-release/master/packages/openwrt"
PACKAGE_NAME="frieren"
TMP_APK="/tmp/package.apk"

# Opção de instalação forçada (ex: -f)
FORCE_INSTALL=$1

# Logger com timestamp
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$2] $1"
}

# Tratamento de erros
handle_error() {
    log "Erro: $2 (Código: $1)" "ERROR"
    [ "$1" -eq 1 ] && [ -z "$FORCE_INSTALL" ] && \
        log "Dica: Execute com '-f' para forçar a instalação (ignore-conffiles)." "INFO"
    exit "$1"
}

# Obtém a URL do pacote baseado na versão (OpenWrt 25.x usa o path 'latest')
get_package_url() {
    local version="$(awk -F"'" '/DISTRIB_RELEASE/{print $2}' /etc/openwrt_release | cut -d'.' -f1)"
    
    # Para a versão 25.12.2, o fallback é o diretório 'latest'
    if [ "$version" -ge 20 ]; then
        echo "${BASE_URL}/latest/${PACKAGE_NAME}_latest.ipk"
    else
        echo "${BASE_URL}/19/${PACKAGE_NAME}_latest.ipk"
    fi
}

# Remove versão antiga se existir (Sintaxe APK)
uninstall_old_package() {
    if apk info "$PACKAGE_NAME" >/dev/null 2>&1; then
        log "Removendo pacote antigo: $PACKAGE_NAME..." "INFO"
        apk del "$PACKAGE_NAME" || handle_error 1 "Falha ao remover pacote via apk del"
    fi
}

# Instalação principal
install_package() {
    local package_url=$(get_package_url)
    
    [ -z "$package_url" ] && handle_error 1 "Não foi possível determinar a URL do pacote."

    log "Atualizando índices do APK..." "INFO"
    apk update || handle_error 1 "Falha no apk update"

    log "Baixando e instalando pacote..." "INFO"
    wget -qO "$TMP_APK" "$package_url" || handle_error 1 "Falha no download via wget"

    # No APK, instalamos o arquivo local. 
    # --allow-untrusted é essencial para arquivos .ipk/.apk externos (não assinados pelo repo oficial)
    local apk_cmd="apk add --allow-untrusted"
    
    if [ "$FORCE_INSTALL" = "-f" ]; then
        # --force-overwrite no apk substitui arquivos conflitantes
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
    
    # Checa PHP 8 (padrão em versões novas) ou fallback 7
    if [ -x "/etc/init.d/php8-fpm" ]; then
        /etc/init.d/php8-fpm restart
    elif [ -x "/etc/init.d/php7-fpm" ]; then
        /etc/init.d/php7-fpm restart
    fi
}

display_access_url() {
    local ip_address=$(ip -4 addr show br-lan | awk '/inet/ {print $2}' | cut -d'/' -f1)
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
