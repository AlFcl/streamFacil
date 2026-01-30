# RTMP Stream Server

Servidor de streaming local con reproductor web integrado. Funciona sin Internet una vez configurado.

## Características

- Servidor RTMP para recibir streams de OBS, Streamlabs, etc.
- Reproductor web HLS (funciona en cualquier navegador)
- Monitor en tiempo real desde terminal
- Funciona sin conexión a Internet
- Compatible con macOS y Linux

## Instalación rápida

```bash
# Clonar o descargar
git clone https://github.com/tu-usuario/rtmp-stream-server.git
cd rtmp-stream-server

# Dar permisos y ejecutar
chmod +x rtmp-server.sh
./rtmp-server.sh
```

El script instalará nginx con RTMP automáticamente si no está instalado.

## Uso

### Iniciar servidor
```bash
./rtmp-server.sh
```

### Comandos disponibles
```bash
./rtmp-server.sh start     # Iniciar servidor
./rtmp-server.sh stop      # Detener servidor
./rtmp-server.sh restart   # Reiniciar servidor
./rtmp-server.sh status    # Ver estado
./rtmp-server.sh monitor   # Monitor en tiempo real
./rtmp-server.sh config    # Ver configuración
./rtmp-server.sh info      # Ver URLs de conexión
./rtmp-server.sh help      # Ayuda
```

## Configuración OBS

1. Abre OBS → Ajustes → Emisión
2. Servicio: **Personalizado**
3. Servidor: `rtmp://TU_IP/live`
4. Clave de retransmisión: `stream`

## Ver el stream

### En navegador (recomendado)
```
http://TU_IP:8080
```

### En VLC
```
rtmp://TU_IP/live/stream
```

## Configuración

Edita las variables al inicio de `rtmp-server.sh`:

```bash
RTMP_PORT=1935          # Puerto RTMP
HTTP_PORT=8080          # Puerto web
STREAM_APP="live"       # Nombre de la app
STREAM_KEY="stream"     # Clave del stream
HLS_FRAGMENT=3          # Segundos por segmento
```

## Estructura de archivos

```
rtmp-stream-server/
├── rtmp-server.sh      # Script principal
├── hls.min.js          # Librería HLS (backup offline)
├── www/                # Archivos web
│   ├── index.html      # Reproductor
│   └── hls.min.js      # Librería HLS
├── hls/                # Segmentos de video (temporal)
├── README.md
└── .gitignore
```

## Requisitos

- macOS o Linux
- Homebrew (macOS) o apt/dnf/yum (Linux)
- nginx con módulo RTMP (se instala automáticamente)

## Uso sin Internet

El servidor funciona completamente offline. Solo necesitas Internet la primera vez para:
1. Instalar nginx
2. Descargar `hls.min.js`

Después de eso, todo funciona en red local sin conexión a Internet.

## Licencia

MIT
