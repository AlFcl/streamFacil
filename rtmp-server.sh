#!/bin/bash
#
# ╔═══════════════════════════════════════════════════════════════╗
# ║  RTMP Stream Server - Easy Setup                              ║
# ║  Servidor de streaming local con reproductor web              ║
# ║  Compatible con: macOS, Linux                                 ║
# ╚═══════════════════════════════════════════════════════════════╝
#

# ═══════════════════════════════════════════════════════════════
# CONFIGURACIÓN - Modifica estos valores según tus necesidades
# ═══════════════════════════════════════════════════════════════

RTMP_PORT=1935          # Puerto RTMP (OBS se conecta aquí)
HTTP_PORT=8080          # Puerto HTTP (para ver en navegador)
STREAM_APP="live"       # Nombre de la aplicación RTMP
STREAM_KEY="stream"     # Clave del stream (puedes cambiarla)
HLS_FRAGMENT=3          # Duración de cada segmento en segundos
HLS_PLAYLIST=60         # Duración del playlist en segundos

# ═══════════════════════════════════════════════════════════════
# NO MODIFICAR DEBAJO DE ESTA LÍNEA (a menos que sepas lo que haces)
# ═══════════════════════════════════════════════════════════════

# Directorio del script (todo se guarda aquí)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WWW_DIR="${SCRIPT_DIR}/www"
HLS_DIR="${SCRIPT_DIR}/hls"

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ═══════════════════════════════════════════════════════════════
# FUNCIONES AUXILIARES
# ═══════════════════════════════════════════════════════════════

print_banner() {
    echo -e "${BLUE}"
    echo "╔═══════════════════════════════════════╗"
    echo "║      RTMP STREAM SERVER v2.0          ║"
    echo "╚═══════════════════════════════════════╝"
    echo -e "${NC}"
}

get_local_ip() {
    case "$(uname -s)" in
        Darwin)
            ipconfig getifaddr en0 2>/dev/null || \
            ipconfig getifaddr en1 2>/dev/null || \
            echo "localhost"
            ;;
        Linux)
            hostname -I 2>/dev/null | awk '{print $1}' || \
            ip route get 1 2>/dev/null | awk '{print $7;exit}' || \
            echo "localhost"
            ;;
        *)
            echo "localhost"
            ;;
    esac
}

detect_os() {
    case "$(uname -s)" in
        Darwin) echo "macos" ;;
        Linux)  echo "linux" ;;
        *)      echo "unknown" ;;
    esac
}

get_nginx_conf_path() {
    local os=$(detect_os)
    case "$os" in
        macos)
            if [ -d "/opt/homebrew/etc/nginx" ]; then
                echo "/opt/homebrew/etc/nginx/nginx.conf"
            else
                echo "/usr/local/etc/nginx/nginx.conf"
            fi
            ;;
        linux)
            echo "/etc/nginx/nginx.conf"
            ;;
    esac
}

# ═══════════════════════════════════════════════════════════════
# INSTALACIÓN
# ═══════════════════════════════════════════════════════════════

install_nginx() {
    local os=$(detect_os)

    echo -e "${YELLOW}Verificando nginx...${NC}"

    if command -v nginx &> /dev/null; then
        echo -e "${GREEN}nginx ya está instalado${NC}"
        return 0
    fi

    echo -e "${YELLOW}Instalando nginx con módulo RTMP...${NC}"

    case "$os" in
        macos)
            if ! command -v brew &> /dev/null; then
                echo -e "${RED}Homebrew no está instalado.${NC}"
                echo "Instálalo desde: https://brew.sh"
                exit 1
            fi
            brew tap denji/nginx 2>/dev/null || true
            brew install nginx-full --with-rtmp-module
            ;;
        linux)
            if command -v apt-get &> /dev/null; then
                sudo apt-get update
                sudo apt-get install -y nginx libnginx-mod-rtmp
            elif command -v dnf &> /dev/null; then
                sudo dnf install -y nginx nginx-mod-rtmp
            elif command -v yum &> /dev/null; then
                sudo yum install -y epel-release
                sudo yum install -y nginx nginx-mod-rtmp
            else
                echo -e "${RED}Distribución no soportada${NC}"
                exit 1
            fi
            ;;
        *)
            echo -e "${RED}Sistema operativo no soportado${NC}"
            exit 1
            ;;
    esac

    echo -e "${GREEN}nginx instalado correctamente${NC}"
}

# ═══════════════════════════════════════════════════════════════
# CONFIGURACIÓN
# ═══════════════════════════════════════════════════════════════

setup_directories() {
    echo -e "${YELLOW}Creando directorios...${NC}"
    mkdir -p "$WWW_DIR"
    mkdir -p "$HLS_DIR"
    echo -e "${GREEN}Directorios creados en: ${SCRIPT_DIR}${NC}"
}

setup_hlsjs() {
    local hls_file="${WWW_DIR}/hls.min.js"

    # Si ya existe, verificar que no esté vacío
    if [ -f "$hls_file" ] && [ -s "$hls_file" ]; then
        return 0
    fi

    # Intentar copiar desde el directorio del script (backup)
    if [ -f "${SCRIPT_DIR}/hls.min.js" ]; then
        cp "${SCRIPT_DIR}/hls.min.js" "$hls_file"
        echo -e "${GREEN}hls.min.js copiado (modo offline)${NC}"
        return 0
    fi

    # Intentar descargar
    echo -e "${YELLOW}Descargando hls.min.js...${NC}"
    if curl -s --max-time 15 "https://cdn.jsdelivr.net/npm/hls.js@latest/dist/hls.min.js" -o "$hls_file" 2>/dev/null; then
        if [ -s "$hls_file" ]; then
            echo -e "${GREEN}hls.min.js descargado${NC}"
            # Guardar backup
            cp "$hls_file" "${SCRIPT_DIR}/hls.min.js" 2>/dev/null || true
            return 0
        fi
    fi

    echo -e "${RED}No se pudo obtener hls.min.js${NC}"
    echo -e "${YELLOW}La web no funcionará sin este archivo${NC}"
    return 1
}

configure_nginx() {
    local nginx_conf=$(get_nginx_conf_path)
    local LOCAL_IP=$(get_local_ip)

    echo -e "${YELLOW}Configurando nginx...${NC}"

    cat > "$nginx_conf" << NGINXCONF
# Configuración generada por rtmp-server.sh
# No editar manualmente - usa las variables en el script

worker_processes auto;

events {
    worker_connections 1024;
}

http {
    include       mime.types;
    default_type  application/octet-stream;
    sendfile      on;
    keepalive_timeout 65;

    server {
        listen ${HTTP_PORT};
        server_name localhost;

        # Reproductor web
        location / {
            root   ${WWW_DIR};
            index  index.html;
        }

        # Segmentos HLS (con / para no capturar /hls.min.js)
        location /hls/ {
            types {
                application/vnd.apple.mpegurl m3u8;
                video/mp2t ts;
            }
            root ${SCRIPT_DIR};
            add_header Cache-Control no-cache;
            add_header Access-Control-Allow-Origin *;
        }
    }
}

rtmp {
    server {
        listen ${RTMP_PORT};
        chunk_size 4096;

        application ${STREAM_APP} {
            live on;
            record off;

            # HLS
            hls on;
            hls_path ${HLS_DIR};
            hls_fragment ${HLS_FRAGMENT};
            hls_playlist_length ${HLS_PLAYLIST};
            hls_cleanup on;
        }
    }
}
NGINXCONF

    echo -e "${GREEN}nginx configurado${NC}"
}

create_web_player() {
    local LOCAL_IP=$(get_local_ip)

    echo -e "${YELLOW}Creando reproductor web...${NC}"

    cat > "${WWW_DIR}/index.html" << 'HTMLEOF'
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Stream en Vivo</title>
    <script src="/hls.min.js"></script>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: linear-gradient(135deg, #1a1a2e 0%, #16213e 100%);
            min-height: 100vh;
            display: flex;
            flex-direction: column;
            align-items: center;
            justify-content: center;
            color: #fff;
            padding: 20px;
        }
        .container { width: 100%; max-width: 900px; }
        h1 {
            text-align: center;
            margin-bottom: 20px;
            font-weight: 300;
            font-size: 1.8rem;
        }
        .video-container {
            background: #000;
            border-radius: 12px;
            overflow: hidden;
            box-shadow: 0 20px 60px rgba(0,0,0,0.5);
            aspect-ratio: 16/9;
        }
        video {
            width: 100%;
            height: 100%;
            display: block;
        }
        .status {
            text-align: center;
            margin-top: 20px;
            padding: 15px;
            border-radius: 8px;
            background: rgba(255,255,255,0.1);
            display: flex;
            align-items: center;
            justify-content: center;
            gap: 10px;
        }
        .status.live { color: #6bcb77; }
        .status.offline { color: #ff6b6b; }
        .dot {
            width: 12px;
            height: 12px;
            border-radius: 50%;
            animation: pulse 1.5s infinite;
        }
        .live .dot { background: #6bcb77; }
        .offline .dot { background: #ff6b6b; }
        @keyframes pulse {
            0%, 100% { opacity: 1; transform: scale(1); }
            50% { opacity: 0.5; transform: scale(0.9); }
        }
        .info {
            margin-top: 30px;
            padding: 20px;
            background: rgba(255,255,255,0.05);
            border-radius: 8px;
            font-size: 0.9rem;
            line-height: 1.8;
        }
        .info p { margin: 5px 0; }
        .info strong { color: #6bcb77; }
        .info code {
            background: rgba(255,255,255,0.15);
            padding: 4px 10px;
            border-radius: 4px;
            font-family: 'SF Mono', Monaco, monospace;
            font-size: 0.85rem;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>Stream en Vivo</h1>
        <div class="video-container">
            <video id="video" controls autoplay muted playsinline></video>
        </div>
        <div id="status" class="status offline">
            <span class="dot"></span>
            <span id="statusText">Esperando stream...</span>
        </div>
        <div class="info" id="info"></div>
    </div>

    <script>
        const video = document.getElementById('video');
        const status = document.getElementById('status');
        const statusText = document.getElementById('statusText');
        const info = document.getElementById('info');
        const streamUrl = '/hls/STREAM_KEY.m3u8';

        // Mostrar info de conexión
        const serverIP = window.location.hostname;
        info.innerHTML = `
            <p><strong>Para transmitir desde OBS:</strong></p>
            <p>Servidor: <code>rtmp://${serverIP}/STREAM_APP</code></p>
            <p>Clave de stream: <code>STREAM_KEY</code></p>
        `;

        function updateStatus(isLive) {
            status.className = 'status ' + (isLive ? 'live' : 'offline');
            statusText.textContent = isLive ? 'EN VIVO' : 'Esperando stream...';
        }

        function initPlayer() {
            if (Hls.isSupported()) {
                const hls = new Hls({
                    liveDurationInfinity: true,
                    liveBackBufferLength: 0,
                    maxBufferLength: 10,
                    maxMaxBufferLength: 30
                });

                hls.loadSource(streamUrl);
                hls.attachMedia(video);

                hls.on(Hls.Events.MANIFEST_PARSED, () => {
                    updateStatus(true);
                    video.play().catch(() => {});
                });

                hls.on(Hls.Events.ERROR, (event, data) => {
                    if (data.fatal) {
                        updateStatus(false);
                        hls.destroy();
                        setTimeout(initPlayer, 3000);
                    }
                });

            } else if (video.canPlayType('application/vnd.apple.mpegurl')) {
                // Safari nativo
                video.src = streamUrl;
                video.addEventListener('loadedmetadata', () => {
                    updateStatus(true);
                    video.play().catch(() => {});
                });
                video.addEventListener('error', () => {
                    updateStatus(false);
                    setTimeout(initPlayer, 3000);
                });
            } else {
                statusText.textContent = 'Navegador no compatible';
            }
        }

        initPlayer();
    </script>
</body>
</html>
HTMLEOF

    # Reemplazar placeholders con valores reales
    sed -i.bak "s/STREAM_APP/${STREAM_APP}/g" "${WWW_DIR}/index.html"
    sed -i.bak "s/STREAM_KEY/${STREAM_KEY}/g" "${WWW_DIR}/index.html"
    rm -f "${WWW_DIR}/index.html.bak"

    echo -e "${GREEN}Reproductor web creado${NC}"
}

# ═══════════════════════════════════════════════════════════════
# CONTROL DEL SERVIDOR
# ═══════════════════════════════════════════════════════════════

start_server() {
    local os=$(detect_os)

    echo -e "${YELLOW}Iniciando servidor...${NC}"

    # Limpiar archivos HLS antiguos
    rm -f "${HLS_DIR}"/*.ts "${HLS_DIR}"/*.m3u8 2>/dev/null

    case "$os" in
        macos)
            nginx -s stop 2>/dev/null || true
            sleep 1
            nginx
            ;;
        linux)
            sudo systemctl restart nginx 2>/dev/null || \
            sudo nginx -s stop 2>/dev/null; sudo nginx
            ;;
    esac

    sleep 2

    # Verificar
    if lsof -i :${RTMP_PORT} &>/dev/null; then
        echo -e "${GREEN}Servidor iniciado correctamente${NC}"
        return 0
    else
        echo -e "${RED}Error al iniciar el servidor${NC}"
        return 1
    fi
}

stop_server() {
    echo -e "${YELLOW}Deteniendo servidor...${NC}"

    nginx -s stop 2>/dev/null && \
        echo -e "${GREEN}Servidor detenido${NC}" || \
        echo -e "${YELLOW}El servidor no estaba corriendo${NC}"

    # Limpiar archivos HLS
    rm -f "${HLS_DIR}"/*.ts "${HLS_DIR}"/*.m3u8 2>/dev/null
}

# ═══════════════════════════════════════════════════════════════
# INFORMACIÓN Y MONITOREO
# ═══════════════════════════════════════════════════════════════

show_info() {
    local LOCAL_IP=$(get_local_ip)

    echo ""
    echo -e "${GREEN}═══════════════════════════════════════${NC}"
    echo -e "${GREEN}         SERVIDOR ACTIVO${NC}"
    echo -e "${GREEN}═══════════════════════════════════════${NC}"
    echo ""
    echo -e "${BOLD}VER EN NAVEGADOR:${NC}"
    echo -e "  ${GREEN}http://${LOCAL_IP}:${HTTP_PORT}${NC}"
    echo ""
    echo -e "${BOLD}CONFIGURACIÓN OBS:${NC}"
    echo -e "  Servidor:  ${YELLOW}rtmp://${LOCAL_IP}/${STREAM_APP}${NC}"
    echo -e "  Clave:     ${YELLOW}${STREAM_KEY}${NC}"
    echo ""
    echo -e "${BOLD}VER EN VLC:${NC}"
    echo -e "  ${CYAN}rtmp://${LOCAL_IP}/${STREAM_APP}/${STREAM_KEY}${NC}"
    echo ""
    echo -e "${BOLD}COMANDOS:${NC}"
    echo -e "  ${CYAN}$0 monitor${NC}  - Ver estado en tiempo real"
    echo -e "  ${CYAN}$0 stop${NC}     - Detener servidor"
    echo ""
    echo -e "${GREEN}═══════════════════════════════════════${NC}"
}

show_status() {
    local LOCAL_IP=$(get_local_ip)
    local m3u8_file="${HLS_DIR}/${STREAM_KEY}.m3u8"
    local stream_active=false

    # Verificar stream activo
    if [ -f "$m3u8_file" ]; then
        local now=$(date +%s)
        local file_time=$(stat -f %m "$m3u8_file" 2>/dev/null || stat -c %Y "$m3u8_file" 2>/dev/null || echo "0")
        local diff=$((now - file_time))
        [ "$diff" -lt 15 ] && stream_active=true
    fi

    echo ""
    echo -e "${BOLD}ESTADO DEL SERVIDOR${NC}"
    echo -e "═══════════════════════════════════════"

    # RTMP
    if lsof -i :${RTMP_PORT} &>/dev/null; then
        echo -e "  RTMP (${RTMP_PORT}):  ${GREEN}● ACTIVO${NC}"
    else
        echo -e "  RTMP (${RTMP_PORT}):  ${RED}● INACTIVO${NC}"
    fi

    # HTTP
    if lsof -i :${HTTP_PORT} &>/dev/null; then
        echo -e "  HTTP (${HTTP_PORT}):  ${GREEN}● ACTIVO${NC}"
    else
        echo -e "  HTTP (${HTTP_PORT}):  ${RED}● INACTIVO${NC}"
    fi

    # Stream
    if [ "$stream_active" = true ]; then
        echo -e "  Stream:      ${GREEN}● EN VIVO${NC}"
    else
        echo -e "  Stream:      ${RED}● OFFLINE${NC}"
    fi

    # Conexiones
    local rtmp_conn=$(( $(lsof -i :${RTMP_PORT} 2>/dev/null | grep -c ESTABLISHED) / 2 ))
    local http_conn=$(( $(lsof -i :${HTTP_PORT} 2>/dev/null | grep -c ESTABLISHED) / 2 ))
    echo -e "  Conexiones:  RTMP: ${CYAN}${rtmp_conn}${NC} | HTTP: ${CYAN}${http_conn}${NC}"
    echo ""
}

monitor_streams() {
    local LOCAL_IP=$(get_local_ip)

    while true; do
        clear
        echo -e "${BLUE}╔═══════════════════════════════════════╗${NC}"
        echo -e "${BLUE}║        MONITOR DE STREAMING           ║${NC}"
        echo -e "${BLUE}╚═══════════════════════════════════════╝${NC}"
        echo ""

        # Estado del servidor
        echo -e "${BOLD}SERVIDOR${NC}"
        echo -e "─────────────────────────────────────────"

        if lsof -i :${RTMP_PORT} &>/dev/null; then
            echo -e "  RTMP (${RTMP_PORT}):  ${GREEN}● ACTIVO${NC}"
        else
            echo -e "  RTMP (${RTMP_PORT}):  ${RED}● INACTIVO${NC}"
        fi

        if lsof -i :${HTTP_PORT} &>/dev/null; then
            echo -e "  HTTP (${HTTP_PORT}):  ${GREEN}● ACTIVO${NC}"
        else
            echo -e "  HTTP (${HTTP_PORT}):  ${RED}● INACTIVO${NC}"
        fi
        echo ""

        # Estado del streaming
        echo -e "${BOLD}STREAMING${NC}"
        echo -e "─────────────────────────────────────────"

        local m3u8_file="${HLS_DIR}/${STREAM_KEY}.m3u8"
        local stream_active=false

        if [ -f "$m3u8_file" ]; then
            local now=$(date +%s)
            local file_time=$(stat -f %m "$m3u8_file" 2>/dev/null || stat -c %Y "$m3u8_file" 2>/dev/null || echo "0")
            local diff=$((now - file_time))
            [ "$diff" -lt 15 ] && stream_active=true
        fi

        if [ "$stream_active" = true ]; then
            echo -e "  Estado:     ${GREEN}● EN VIVO${NC}"

            # Contar segmentos
            local ts_count=$(ls -1 "${HLS_DIR}"/*.ts 2>/dev/null | wc -l | tr -d ' ')
            [ "$ts_count" -gt 0 ] && echo -e "  Segmentos:  ${CYAN}${ts_count}${NC}"

            # Estimar bitrate
            local last_ts=$(ls -t "${HLS_DIR}"/*.ts 2>/dev/null | head -1)
            if [ -n "$last_ts" ] && [ -f "$last_ts" ]; then
                local ts_size=$(stat -f %z "$last_ts" 2>/dev/null || stat -c %s "$last_ts" 2>/dev/null || echo "0")
                if [ "$ts_size" -gt 0 ]; then
                    local bitrate_kbps=$(( (ts_size * 8) / HLS_FRAGMENT / 1000 ))
                    echo -e "  Bitrate:    ${CYAN}~${bitrate_kbps} kbps${NC}"
                fi
            fi
        else
            echo -e "  Estado:     ${RED}● OFFLINE${NC}"
            echo -e "  ${YELLOW}Esperando conexión de OBS...${NC}"
        fi
        echo ""

        # Conexiones
        echo -e "${BOLD}CONEXIONES${NC}"
        echo -e "─────────────────────────────────────────"
        local rtmp_conn=$(( $(lsof -i :${RTMP_PORT} 2>/dev/null | grep -c ESTABLISHED) / 2 ))
        local http_conn=$(( $(lsof -i :${HTTP_PORT} 2>/dev/null | grep -c ESTABLISHED) / 2 ))
        echo -e "  RTMP:       ${CYAN}${rtmp_conn}${NC}"
        echo -e "  HTTP:       ${CYAN}${http_conn}${NC}"
        echo ""

        # URLs
        echo -e "${BOLD}URLs${NC}"
        echo -e "─────────────────────────────────────────"
        echo -e "  Web:  ${GREEN}http://${LOCAL_IP}:${HTTP_PORT}${NC}"
        echo -e "  OBS:  ${YELLOW}rtmp://${LOCAL_IP}/${STREAM_APP}${NC}"
        echo -e "  VLC:  ${CYAN}rtmp://${LOCAL_IP}/${STREAM_APP}/${STREAM_KEY}${NC}"
        echo ""

        echo -e "${BLUE}─────────────────────────────────────────${NC}"
        echo -e "  $(date '+%H:%M:%S') │ Ctrl+C para salir"

        sleep 2
    done
}

show_help() {
    echo "Uso: $0 [comando]"
    echo ""
    echo "Comandos:"
    echo "  (sin args)  - Configura e inicia el servidor"
    echo "  start       - Inicia el servidor"
    echo "  stop        - Detiene el servidor"
    echo "  restart     - Reinicia el servidor"
    echo "  status      - Muestra estado actual"
    echo "  monitor     - Monitor en tiempo real"
    echo "  config      - Muestra configuración actual"
    echo "  info        - Muestra URLs de conexión"
    echo "  install     - Instala dependencias"
    echo "  help        - Muestra esta ayuda"
    echo ""
    echo "Configuración en: $0 (editar variables al inicio)"
}

show_config() {
    echo ""
    echo -e "${BOLD}CONFIGURACIÓN ACTUAL${NC}"
    echo -e "═══════════════════════════════════════"
    echo -e "  Puerto RTMP:     ${CYAN}${RTMP_PORT}${NC}"
    echo -e "  Puerto HTTP:     ${CYAN}${HTTP_PORT}${NC}"
    echo -e "  Aplicación:      ${CYAN}${STREAM_APP}${NC}"
    echo -e "  Stream Key:      ${CYAN}${STREAM_KEY}${NC}"
    echo -e "  Fragmento HLS:   ${CYAN}${HLS_FRAGMENT}s${NC}"
    echo ""
    echo -e "  Directorio web:  ${YELLOW}${WWW_DIR}${NC}"
    echo -e "  Directorio HLS:  ${YELLOW}${HLS_DIR}${NC}"
    echo ""
}

# ═══════════════════════════════════════════════════════════════
# MAIN
# ═══════════════════════════════════════════════════════════════

print_banner

case "${1:-}" in
    install)
        install_nginx
        ;;
    start)
        start_server && show_info
        ;;
    stop)
        stop_server
        ;;
    restart)
        stop_server
        sleep 1
        start_server && show_info
        ;;
    status)
        show_status
        ;;
    monitor)
        monitor_streams
        ;;
    config)
        show_config
        ;;
    info)
        show_info
        ;;
    help|--help|-h)
        show_help
        ;;
    "")
        # Sin argumentos: configurar todo e iniciar
        install_nginx
        setup_directories
        setup_hlsjs
        configure_nginx
        create_web_player
        start_server && show_info
        ;;
    *)
        echo -e "${RED}Comando desconocido: $1${NC}"
        echo ""
        show_help
        exit 1
        ;;
esac
