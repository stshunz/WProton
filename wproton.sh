#!/usr/bin/env bash
# ============================================================================
#  WProton - Lanzador portable de juegos Windows con soporte .wsquashfs
# ----------------------------------------------------------------------------
#  Filosofia:
#    * LANZAR  -> por linea de comandos:  ./wproton.sh juego.wsquashfs
#    * CONFIG  -> por menus zenity navegables CON MANDO (estilo PortProton)
#    * 1a VEZ  -> asistente: elegir runner (Proton/Wine) + config basica
#
#  El runner de cada juego vive en SU PERFIL (profiles/<id>.conf).
#  Cualquier fichero .ppdb dentro del wsquashfs se IGNORA por completo.
#
#  Binarios squashfuse y fuse-overlayfs: se usan PRIMERO los que esten en la
#  raiz de WProton (o en bin/), y si no existen, los del sistema.
#
#  Runners (carpetas dentro de runtime/proton/), descargables desde el menu:
#    * GE-Proton, Proton-CachyOS (tipo proton)  -> via umu-run
#    * Wine-GE, Kron4ek Wine (tipo wine)        -> via bin/wine directo
#
#  Uso CLI:
#     ./wproton.sh juego.wsquashfs         -> lanzar (asistente si es la 1a vez)
#     ./wproton.sh --exe juego.wsquashfs   -> lanzar eligiendo exe a mano
#     ./wproton.sh --setup                 -> descargar/actualizar umu + Proton
#     ./wproton.sh --kill                  -> desmontar todo y matar wine
#     ./wproton.sh --config [juego]        -> menu de configuracion
#     ./wproton.sh                         -> menu principal
# ============================================================================

set -u  # (NO set -e: la limpieza controlada es nuestra, leccion de update.sh)

# ----------------------------------------------------------------------------
# VERSION de WProton (nomenclatura: 0.5 -> 0.51 -> 0.52... salto grande -> 0.6)
# ----------------------------------------------------------------------------
WPROTON_VERSION="0.97"
# Repo de GitHub para las auto-actualizaciones (rellenar al subirlo):
#   formato "usuario/repo", p.ej. "dani/wproton". Las releases deben llevar
#   tag "v<version>" (v0.5, v0.51...) y el script como asset o en la rama main.
WPROTON_REPO="stshunz/WProton"

# ----------------------------------------------------------------------------
# 1. RUTAS PORTABLES (todo relativo al script)
# ----------------------------------------------------------------------------
SELF="$(readlink -f "$0")"
BASE_DIR="$(dirname "$SELF")"

RUNTIME_DIR="$BASE_DIR/runtime"          # umu + runners + steamrt sniper
RUNNERS_DIR="$RUNTIME_DIR/proton"        # un dir por runner (Proton o Wine)
DL_DIR="$RUNTIME_DIR/downloads"          # cache de descargas (dgVoodoo, etc.)
UMU_BIN="$RUNTIME_DIR/umu/umu-run"
WS_DIR="$BASE_DIR/wsquashfs"             # === estructura del PortProton antiguo ===
MOUNT_BASE="$WS_DIR/tmp_mount"           #   <n>_ro (squashfuse) + <n> (overlay)
OVERLAY_BASE="$WS_DIR/overlays"          #   <n>/upper (saves) + <n>/work
BUILD_BASE="$WS_DIR/build_ws"            #   extraccion/empaquetado temporal
PREFIX_DIR="$BASE_DIR/prefixes"          # prefijos wine (default = compartido)
PROFILE_DIR="$BASE_DIR/profiles"         # .conf por juego (estilo TeknoParrot)
CACHE_DIR="$BASE_DIR/cache"              # shaders dxvk/vkd3d/mesa/nvidia
LOG_DIR="$BASE_DIR/logs"
SETTINGS_FILE="$BASE_DIR/settings.conf"  # ajustes globales (carpeta de juegos)
LOG_FILE="$LOG_DIR/wproton_$(date +%Y%m%d_%H%M%S).log"

mkdir -p "$RUNTIME_DIR" "$RUNNERS_DIR" "$DL_DIR" "$MOUNT_BASE" "$OVERLAY_BASE" \
         "$BUILD_BASE" "$PREFIX_DIR" "$PROFILE_DIR" "$CACHE_DIR" "$LOG_DIR"

# --- Ajustes globales (settings.conf se crea con valores por defecto) ---
GAMES_PATH="$BASE_DIR/games"             # carpeta de juegos (configurable)
LAST_GAME=""                             # ultimo juego lanzado (ruta completa)
GAMES_VIEW="list"                        # lista | grid (rejilla con caratulas)
LAST_BROWSE=""                           # ultima carpeta visitada en el navegador
THEME="clasico"                          # aspecto de los menus: clasico | moderno | arcade
DIRECT_PLAY=0                            # 1 = arrancar directo en la lista de juegos
GRID_COLS=0                              # columnas de la rejilla (0 = automatico)
LANGUAGE=es                              # idioma de los menus: es | en
GAMES_SORT=nombre                        # nombre | recientes | jugados
PACK_FORMAT=wsquashfs                    # wsquashfs | dwarfs (mas compresion)
BACKUP_SYNC_DEST=""                      # destino rsync para backups/
SGDB_KEY=""                              # API key de steamgriddb.com (caratulas)
save_settings() {
    cat > "$SETTINGS_FILE" <<EOF
# ============================================
# Ajustes globales de WProton (editable a mano)
# ============================================
# Carpeta donde estan / se guardan los .wsquashfs:
GAMES_PATH="$GAMES_PATH"
# Ultimo juego lanzado (para "Jugar al ultimo" del menu):
LAST_GAME="$LAST_GAME"
# Vista del selector de juegos: list | grid
GAMES_VIEW="$GAMES_VIEW"
# Ultima carpeta usada en el navegador de ficheros:
LAST_BROWSE="$LAST_BROWSE"
# Aspecto de los menus: clasico | moderno
THEME="$THEME"
# API key de SteamGridDB (https://www.steamgriddb.com/profile/preferences/api):
SGDB_KEY="$SGDB_KEY"
# --------------------------------------------------------------------------
# MODO "SOLO JUGAR" (no aparece en los menus: se activa aqui a mano)
#   1 = al abrir WProton se va DIRECTO a la lista de juegos, y al salir de
#       esa lista se cierra el programa. Para quien solo quiere jugar.
#   Volver al menu completo: pon 0 aqui, o ejecuta  wproton.sh --menu
# --------------------------------------------------------------------------
DIRECT_PLAY=$DIRECT_PLAY
# Columnas de la rejilla de caratulas: 0 = automatico segun la pantalla
# (4 en portatiles tipo Steam Deck, 5 en Full HD, 6 en pantallas grandes).
# Ponlo a mano si prefieres caratulas mas pequenas y ver mas juegos a la vez.
GRID_COLS=$GRID_COLS
# Idioma de los menus: es (castellano) | en (english)
LANGUAGE="$LANGUAGE"
# Orden de la lista de juegos: nombre | recientes | jugados
# (los marcados como favoritos van siempre primero)
GAMES_SORT="$GAMES_SORT"
# Formato al empaquetar juegos: wsquashfs (compatible con Batocera) o
# dwarfs (comprime bastante mas y monta igual de rapido)
PACK_FORMAT="$PACK_FORMAT"
# Destino de rsync para sincronizar backups/ (carpeta, USB o usuario@equipo:/ruta)
BACKUP_SYNC_DEST="$BACKUP_SYNC_DEST"
# Nota: GAMES_PATH admite rutas RELATIVAS (se resuelven respecto a la carpeta
# de wproton.sh, no al directorio actual). Ej.: GAMES_PATH="ROMs/windows"
EOF
}
abs_path() {
    # Rutas relativas -> relativas a la CARPETA DE WPROTON (no al directorio
    # actual): asi funcionan aunque lance el script un frontend desde otro
    # sitio, y se puede mover la carpeta entera (o el pendrive) sin tocar nada.
    case "$1" in
        "")     printf '' ;;
        /*)     printf '%s' "$1" ;;
        "~/"*)  printf '%s/%s' "$HOME" "${1#*/}" ;;
        *)      printf '%s/%s' "$BASE_DIR" "$1" ;;
    esac
}

declare -A WP_TR
LANG_DIR="$BASE_DIR/lang"

lang_available() {
    # Idiomas disponibles: es (interno) + cada lang/<codigo>.json
    local f c
    printf 'es\n'
    for f in "$LANG_DIR"/*.json; do
        [ -f "$f" ] || continue
        c="$(basename "$f" .json)"
        [ "$c" = "es" ] || printf '%s\n' "$c"
    done 2>/dev/null
}

tr_init() {
    WP_TR=()
    local code="${LANGUAGE:-es}"
    [ "$code" = "es" ] && return 0        # castellano = cadenas del script
    local f="$LANG_DIR/$code.json"
    if [ ! -f "$f" ]; then
        say "AVISO: no existe lang/$code.json; se usara el castellano"
        LANGUAGE=es
        return 0
    fi
    # El JSON se lee con Python (el portable o el del sistema). Si no hay
    # ninguno, seguimos en castellano en vez de fallar.
    local py="${PY_BIN:-}"
    [ -x "$py" ] || py="$(command -v python3 2>/dev/null)"
    if [ -z "$py" ]; then
        say "AVISO: sin Python para leer lang/$code.json; se usara el castellano"
        LANGUAGE=es
        return 0
    fi
    local pairs
    pairs="$("$py" -c '
import json, sys
try:
    d = json.load(open(sys.argv[1], encoding="utf-8"))
except Exception as e:
    sys.stderr.write("json: %s\n" % e); sys.exit(1)
for k, v in d.items():
    if isinstance(v, str) and v:
        print("%s\t%s" % (k.replace("\t", " "), v.replace("\t", " ")))
' "$f" 2>>"$LOG_FILE")" || {
        say "AVISO: lang/$code.json no es JSON valido; se usara el castellano"
        LANGUAGE=es
        return 0
    }
    local k v n=0
    while IFS=$'\t' read -r k v; do
        [ -n "$k" ] && { WP_TR["$k"]="$v"; n=$((n+1)); }
    done <<EOFLANG
$pairs
EOFLANG
    say "[i] Idioma $code: $n cadenas cargadas de lang/$code.json"
    return 0
}

wp_tr() {
    # OJO: esta funcion NO puede llamarse "tr": machacaria el comando tr de
    # Unix, que el script usa para game_id, ordenaciones, etc. (fallo real
    # de la 0.92: dejaron de encontrarse perfiles y caratulas).
    # Traduce si hay traduccion; si no, devuelve el original. Para lineas
    # tipo "Etiqueta: valor" traduce solo la etiqueta.
    local txt="$1"
    [ "${LANGUAGE:-es}" != "es" ] || { printf '%s' "$txt"; return 0; }
    if [ -n "${WP_TR[$txt]:-}" ]; then
        printf '%s' "${WP_TR[$txt]}"; return 0
    fi
    case "$txt" in
        *": "*)
            local k="${txt%%: *}" v="${txt#*: }"
            if [ -n "${WP_TR[$k]:-}" ]; then
                printf '%s: %s' "${WP_TR[$k]}" "$(wp_tr "$v")"
                return 0
            fi ;;
    esac
    printf '%s' "$txt"
}

tr_args() {
    # Traduce cada argumento y los imprime uno por linea
    local a
    for a in "$@"; do
        printf '%s\n' "$(wp_tr "$a")"
    done
}

load_settings() {
    # shellcheck disable=SC1090
    [ -f "$SETTINGS_FILE" ] && . "$SETTINGS_FILE"
    [ -f "$SETTINGS_FILE" ] || save_settings   # crear el fichero la primera vez
    GAMES_PATH="$(abs_path "$GAMES_PATH")"
    LAST_GAME="$(abs_path "${LAST_GAME:-}")"
    LAST_BROWSE="$(abs_path "${LAST_BROWSE:-}")"
    mkdir -p "$GAMES_PATH" 2>/dev/null
    tr_init
}
load_settings

# ----------------------------------------------------------------------------
# 1b. PYTHON PORTABLE (python-build-standalone en runtime/python/, patron
#     libs_pyX.Y con pip --target: cero dependencia del python del sistema)
# ----------------------------------------------------------------------------
PY_DIR="$RUNTIME_DIR/python"
PY_BIN=""
SYS_PY="$(command -v python3 2>/dev/null || true)"
resolve_python() {
    if [ -x "$PY_DIR/bin/python3" ]; then
        PY_BIN="$PY_DIR/bin/python3"
    else
        PY_BIN="$SYS_PY"
    fi
}
resolve_python

py_libs_dir() {
    # Convencion DeckStation: libs_pyX.Y segun la version del propio python
    "$PY_BIN" -c 'import sys;print("libs_py%d.%d"%sys.version_info[:2])'
}

# ----------------------------------------------------------------------------
# 2. LOG SOLO A FICHERO (nunca contaminar stdout: leccion del wrapper ES-DE)
# ----------------------------------------------------------------------------
log() { printf '%s [%s] %s\n' "$(date '+%H:%M:%S')" "${2:-INFO}" "$1" >> "$LOG_FILE"; }
say() { printf '%s\n' "$1" >&2; log "$1"; }
die() { say "ERROR: $1"; ui_error "$1"; cleanup_mount; exit 1; }

HAS_ZENITY=0
command -v zenity >/dev/null 2>&1 && [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ] && HAS_ZENITY=1

# Modo Juego de SteamOS (o cualquier sesion gamescope): los menus deben ir a
# pantalla completa y hay que dar respiro al compositor al cerrar un juego.
IS_GAMESCOPE=0
if [ -n "${GAMESCOPE_WAYLAND_DISPLAY:-}" ] || [ "${XDG_CURRENT_DESKTOP:-}" = "gamescope" ] \
   || [ -n "${STEAM_GAMESCOPE_VIRTUAL_WHITELIST:-}" ]; then
    IS_GAMESCOPE=1
    export WP_MENU_FS=1
fi

# Batocera/Knulli: menus a pantalla completa y wines del sistema disponibles
IS_BATOCERA=0
BATOCERA_WINE_BIN=""
if [ -f /usr/share/batocera/batocera.version ] || [ -d /userdata/system ]; then
    IS_BATOCERA=1
    export WP_MENU_FS=1
    BATOCERA_WINE_BIN="$(command -v batocera-wine 2>/dev/null || true)"
    [ -z "$BATOCERA_WINE_BIN" ] && [ -x /usr/bin/batocera-wine ] && BATOCERA_WINE_BIN=/usr/bin/batocera-wine
fi

batocera_play() {
    # Delegar el lanzamiento en el lanzador nativo de Batocera: se encarga de
    # prefijos (/userdata/saves/windows), DXVK, mando, redistribuibles y de
    # montar el wsquashfs por si mismo. El runner se elige en EmulationStation.
    local target="$1"
    [ -n "${DISPLAY:-}" ] || export DISPLAY=:0.0
    pad_bridge_stop
    say "Lanzando via batocera-wine: $(basename "$target")"
    "$BATOCERA_WINE_BIN" windows play "$target" >> "$LOG_FILE" 2>&1
    local rc=$?
    [ $rc -ne 0 ] && ui_error "batocera-wine devolvio error (rc=$rc).
Ultimas lineas del log:
$(tail -n 8 "$LOG_FILE")"
    return $rc
}

ui_error() {
    log "ERROR-UI: $1"
    set -- "$(wp_tr "$1")"
    if [ "$HAS_ZENITY" = 1 ]; then
        zenity --error --title="WProton" --text="$1" 2>/dev/null
    elif pygame_available; then
        # shellcheck disable=SC2046
        (IFS=$'\n'; set -f; menu "ERROR" $1 "<< Aceptar") >/dev/null 2>&1 || true
    fi
}
ui_info()  {
    set -- "$(wp_tr "$1")"
    if [ "$HAS_ZENITY" = 1 ]; then
        pad_bridge_start
        zenity --info --title="WProton" --text="$1" 2>/dev/null
    elif pygame_available; then
        # shellcheck disable=SC2046
        (IFS=$'\n'; set -f; menu "INFO" $1 "<< Aceptar") >/dev/null 2>&1 || true
    else
        say "$1"
    fi
}
ui_ask()   { # pregunta si/no -> rc 0 = si
    if pygame_available; then
        local a; a="$(menu "$1" "Si" "No")" || return 1
        [ "$a" = "Si" ]
    elif [ "$HAS_ZENITY" = 1 ]; then
        pad_bridge_start
        zenity --question --title="WProton" --text="$1" 2>/dev/null
    else
        printf '%s [s/N]: ' "$1" >&2; read -r r; [ "$r" = "s" ] || [ "$r" = "S" ]
    fi
}

# ----------------------------------------------------------------------------
# 3. HERRAMIENTAS FUSE: primero las de la carpeta de WProton, luego el sistema
# ----------------------------------------------------------------------------
resolve_tool() {
    # $1 = nombre -> imprime ruta (los nuestros primero, luego el sistema)
    local p
    for p in "$RUNTIME_DIR/tools/$1" "$BASE_DIR/$1" "$BASE_DIR/bin/$1"; do
        if [ -f "$p" ]; then
            chmod +x "$p" 2>/dev/null
            printf '%s' "$p"; return 0
        fi
    done
    command -v "$1" 2>/dev/null
}
SQUASHFUSE_BIN="$(resolve_tool squashfuse)"
OVERLAYFS_BIN="$(resolve_tool fuse-overlayfs)"
FUSERMOUNT_BIN="$(command -v fusermount3 2>/dev/null || command -v fusermount 2>/dev/null)"

arch_tag() {
    case "$(uname -m)" in
        x86_64|amd64)   printf 'x86_64' ;;
        aarch64|arm64)  printf 'aarch64' ;;
        armv7*|armhf)   printf 'armv7l' ;;
        *)              uname -m ;;
    esac
}

try_static_tool() {
    # $1 = nombre del binario, resto = URLs candidatas. Descarga la primera
    # que EJECUTE de verdad en esta maquina (arquitectura correcta).
    local name="$1"; shift
    local tmp url rc
    mkdir -p "$RUNTIME_DIR/tools"
    tmp="$(mktemp -d)"
    for url in "$@"; do
        [ -n "$url" ] || continue
        say "[$name] probando $(basename "$url")..."
        dl "$url" "$tmp/$name" >/dev/null 2>&1 || continue
        chmod +x "$tmp/$name" 2>/dev/null
        "$tmp/$name" --help >/dev/null 2>&1
        rc=$?
        if [ "$rc" -lt 126 ]; then          # 126/127 = no ejecutable aqui
            cp -f "$tmp/$name" "$RUNTIME_DIR/tools/$name"
            chmod +x "$RUNTIME_DIR/tools/$name"
            rm -rf "$tmp"
            say "[$name] listo (portable en runtime/tools)"
            return 0
        fi
        say "[$name] ese binario no funciona aqui, probando otro"
    done
    rm -rf "$tmp"
    return 1
}

DWARFS_BIN=""
MKDWARFS_BIN=""

find_dwarfs_tools() {
    # Binarios propios primero (portables), luego los del sistema
    DWARFS_BIN=""; MKDWARFS_BIN=""
    local d="$RUNTIME_DIR/tools"
    [ -x "$d/dwarfs" ]    && DWARFS_BIN="$d/dwarfs"
    [ -x "$d/mkdwarfs" ]  && MKDWARFS_BIN="$d/mkdwarfs"
    [ -z "$DWARFS_BIN" ]   && DWARFS_BIN="$(command -v dwarfs 2>/dev/null)"
    [ -z "$MKDWARFS_BIN" ] && MKDWARFS_BIN="$(command -v mkdwarfs 2>/dev/null)"
    [ -n "$DWARFS_BIN" ] || [ -n "$MKDWARFS_BIN" ]
}

setup_dwarfs_tools() {
    # DwarFS publica un BINARIO UNIVERSAL estatico que contiene mkdwarfs,
    # dwarfs (driver FUSE), dwarfsck y dwarfsextract. Se elige la herramienta
    # con enlaces simbolicos con su nombre. Nada que compilar.
    find_dwarfs_tools && [ -x "$RUNTIME_DIR/tools/dwarfs" ] && return 0
    local a; a="$(arch_tag)"
    mkdir -p "$RUNTIME_DIR/tools"
    local urls url tmp
    say "[dwarfs] buscando el binario universal..."
    urls="$(curl -fsSL "https://api.github.com/repos/mhx/dwarfs/releases/latest" 2>/dev/null \
        | grep -o '"browser_download_url": *"[^"]*"' | cut -d'"' -f4 \
        | grep -i 'universal' | grep -i "linux" | grep -i "$a")"
    [ -z "$urls" ] && {
        ui_error "No se pudo localizar la descarga de DwarFS para $a.
Puedes instalarlo desde tu distribucion (paquete 'dwarfs') o dejar
los binarios mkdwarfs y dwarfs en runtime/tools/."
        return 1
    }
    tmp="$(mktemp -d)"
    while IFS= read -r url; do
        [ -n "$url" ] || continue
        say "[dwarfs] probando $(basename "$url")"
        dl "$url" "$tmp/dwarfs-universal" || continue
        chmod +x "$tmp/dwarfs-universal" 2>/dev/null
        if "$tmp/dwarfs-universal" --tool=mkdwarfs --help >/dev/null 2>&1; then
            cp -f "$tmp/dwarfs-universal" "$RUNTIME_DIR/tools/dwarfs-universal"
            chmod +x "$RUNTIME_DIR/tools/dwarfs-universal"
            # el binario universal elige herramienta segun el nombre del enlace
            local t
            for t in mkdwarfs dwarfs dwarfsck dwarfsextract; do
                ln -sf dwarfs-universal "$RUNTIME_DIR/tools/$t"
            done
            rm -rf "$tmp"
            find_dwarfs_tools
            say "[dwarfs] listo: $("$MKDWARFS_BIN" --help 2>&1 | head -n1)"
            return 0
        fi
        say "[dwarfs] ese binario no funciona aqui"
    done <<EOFDW
$urls
EOFDW
    rm -rf "$tmp"
    ui_error "El binario de DwarFS descargado no funciona en esta maquina."
    return 1
}

setup_fuse_tools() {
    # Descarga versiones PORTABLES de fuse-overlayfs y squashfuse. Solo
    # fusermount3 (paquete fuse3) sigue siendo del sistema: lo necesita el
    # kernel para montar como usuario y no puede ser portable.
    local a; a="$(arch_tag)"
    local ok=0
    if [ -z "$OVERLAYFS_BIN" ]; then
        # fuse-overlayfs publica binarios ESTATICOS oficiales por arquitectura
        local ovl_urls
        ovl_urls="$(curl -fsSL "https://api.github.com/repos/containers/fuse-overlayfs/releases/latest" 2>/dev/null \
            | grep -o '"browser_download_url": *"[^"]*"' | cut -d'"' -f4 | grep -i "$a")"
        # shellcheck disable=SC2086
        try_static_tool fuse-overlayfs $ovl_urls && ok=1
    fi
    if [ -z "$SQUASHFUSE_BIN" ]; then
        # squashfuse no publica binarios: probamos fuentes de builds estaticos
        local sq_urls="https://bin.pkgforge.dev/$a/squashfuse"
        sq_urls="$sq_urls
$(curl -fsSL "https://api.github.com/repos/Azathothas/Toolpacks/releases/latest" 2>/dev/null \
    | grep -o '"browser_download_url": *"[^"]*"' | cut -d'"' -f4 | grep -i 'squashfuse' | grep -i "$a")"
        sq_urls="$sq_urls
$(curl -fsSL "https://api.github.com/repos/vasi/squashfuse/releases/latest" 2>/dev/null \
    | grep -o '"browser_download_url": *"[^"]*"' | cut -d'"' -f4 | grep -iv 'tar\.\|zip\|sig' | grep -i "$a")"
        # shellcheck disable=SC2086
        try_static_tool squashfuse $(printf '%s\n' "$sq_urls" | awk 'NF') && ok=1
    fi
    SQUASHFUSE_BIN="$(resolve_tool squashfuse)"
    OVERLAYFS_BIN="$(resolve_tool fuse-overlayfs)"
    [ "$ok" = 1 ]
}

check_deps() {
    local missing=""
    for c in curl tar; do
        command -v "$c" >/dev/null 2>&1 || missing="$missing $c"
    done
    # squashfuse/fuse-overlayfs: si faltan, se descargan portables solos
    if [ -z "$SQUASHFUSE_BIN" ] || [ -z "$OVERLAYFS_BIN" ]; then
        if command -v curl >/dev/null 2>&1; then
            say "Faltan herramientas FUSE: descargando versiones portables..."
            setup_fuse_tools || true
        fi
    fi
    [ -z "$SQUASHFUSE_BIN" ]  && missing="$missing squashfuse"
    [ -z "$OVERLAYFS_BIN" ]   && missing="$missing fuse-overlayfs"
    [ -z "$FUSERMOUNT_BIN" ]  && missing="$missing fusermount3(fuse3)"
    [ -n "$missing" ] && die "Faltan dependencias:$missing
No se pudieron descargar automaticamente. Puedes dejar los binarios
squashfuse y fuse-overlayfs junto a wproton.sh (o en runtime/tools/).
fusermount3 (paquete fuse3) SI debe estar en el sistema: lo exige el kernel."
    log "Herramientas: squashfuse=$SQUASHFUSE_BIN | overlayfs=$OVERLAYFS_BIN | fusermount=$FUSERMOUNT_BIN"
}

# ----------------------------------------------------------------------------
# 4. PUENTE MANDO -> TECLADO (menus zenity navegables con gamepad)
#    Python puro sobre /dev/uinput y /dev/input (sin dependencias, sin evdev).
#    Dpad/stick izq = flechas | A = Enter | B = Esc | X = Espacio | Y/RB = Tab
# ----------------------------------------------------------------------------
PAD_BRIDGE_PID=""
PAD_BRIDGE_PY="$RUNTIME_DIR/pad_bridge.py"
PAD_WARNED=0

write_pad_bridge() {
    cat > "$PAD_BRIDGE_PY" <<'PYEOF'
#!/usr/bin/env python3
# Puente mando->teclado para los menus de WProton (python puro, sin evdev)
import os, struct, fcntl, select, time, sys

EV_SYN, EV_KEY, EV_ABS = 0, 1, 3
KEY = {'ESC':1,'TAB':15,'ENTER':28,'SPACE':57,'UP':103,'LEFT':105,'RIGHT':106,'DOWN':108}
# A=304 Enter | B=305 Esc | X=307 Espacio (checklists) | Y=308 Tab | RB=311 Tab | Start=315 Enter
BTN_MAP = {304:'ENTER', 305:'ESC', 307:'SPACE', 308:'TAB', 311:'TAB', 315:'ENTER'}
UI_SET_EVBIT, UI_SET_KEYBIT = 0x40045564, 0x40045565
UI_DEV_CREATE = 0x5501
IE = 'llHHi'   # struct input_event nativo (24 bytes en x86_64)
IE_SZ = struct.calcsize(IE)

def uinput_open():
    fd = os.open('/dev/uinput', os.O_WRONLY | os.O_NONBLOCK)
    fcntl.ioctl(fd, UI_SET_EVBIT, EV_KEY)
    for k in KEY.values():
        fcntl.ioctl(fd, UI_SET_KEYBIT, k)
    os.write(fd, struct.pack('80s4HI256i', b'WProton Pad Bridge', 3, 1, 1, 1, 0, *([0]*256)))
    fcntl.ioctl(fd, UI_DEV_CREATE)
    time.sleep(0.3)
    return fd

def find_pads():
    pads = []
    try:
        blocks = open('/proc/bus/input/devices').read().split('\n\n')
    except OSError:
        return pads
    for b in blocks:
        for line in b.split('\n'):
            if line.startswith('H:') and ' js' in line.replace('=', ' '):
                for tok in line.replace('=', ' ').split():
                    if tok.startswith('event'):
                        pads.append('/dev/input/' + tok)
    return pads

def emit(fd, t, c, v):
    os.write(fd, struct.pack(IE, 0, 0, t, c, v))

def tap(fd, name):
    k = KEY[name]
    emit(fd, EV_KEY, k, 1); emit(fd, EV_SYN, 0, 0)
    emit(fd, EV_KEY, k, 0); emit(fd, EV_SYN, 0, 0)

def main():
    try:
        ufd = uinput_open()
    except OSError as e:
        sys.stderr.write('pad_bridge: sin acceso a /dev/uinput (%s)\n' % e)
        return 1
    fds, held, ax = {}, {}, {}
    last_scan = 0.0
    REP_FIRST, REP_NEXT = 0.40, 0.15
    TH_ON, TH_OFF = 18000, 12000
    while True:
        now = time.time()
        if now - last_scan > 2:
            last_scan = now
            for p in find_pads():
                if p not in fds:
                    try: fds[p] = os.open(p, os.O_RDONLY | os.O_NONBLOCK)
                    except OSError: pass
        try:
            r, _, _ = select.select(list(fds.values()), [], [], 0.05 if held else 0.5)
        except OSError:
            r = []
        for fd in r:
            try:
                data = os.read(fd, IE_SZ * 64)
            except OSError:
                for p, f in list(fds.items()):
                    if f == fd:
                        try: os.close(f)
                        except OSError: pass
                        del fds[p]
                continue
            for off in range(0, len(data) - IE_SZ + 1, IE_SZ):
                _, _, t, c, v = struct.unpack_from(IE, data, off)
                if t == EV_KEY and c in BTN_MAP and v == 1:
                    tap(ufd, BTN_MAP[c])
                elif t == EV_ABS and c in (16, 17):
                    names = ('LEFT', 'RIGHT') if c == 16 else ('UP', 'DOWN')
                    for n in names: held.pop(n, None)
                    if v != 0:
                        n = names[1] if v > 0 else names[0]
                        tap(ufd, n); held[n] = time.time() + REP_FIRST
                elif t == EV_ABS and c in (0, 1):
                    st = ax.get((fd, c), 0)
                    new = st
                    if st == 0 and abs(v) > TH_ON: new = 1 if v > 0 else -1
                    elif st != 0 and abs(v) < TH_OFF: new = 0
                    if new != st:
                        ax[(fd, c)] = new
                        names = ('LEFT', 'RIGHT') if c == 0 else ('UP', 'DOWN')
                        for n in names: held.pop(n, None)
                        if new != 0:
                            n = names[1] if new > 0 else names[0]
                            tap(ufd, n); held[n] = time.time() + REP_FIRST
        now = time.time()
        for n, t_ in list(held.items()):
            if now >= t_:
                tap(ufd, n); held[n] = now + REP_NEXT

if __name__ == '__main__':
    sys.exit(main())
PYEOF
}

pad_bridge_start() {
    [ "$HAS_ZENITY" = 1 ] || return 0
    if [ -n "$PAD_BRIDGE_PID" ] && kill -0 "$PAD_BRIDGE_PID" 2>/dev/null; then return 0; fi
    write_pad_bridge
    if [ ! -w /dev/uinput ]; then
        if [ "$PAD_WARNED" = 0 ]; then
            PAD_WARNED=1
            log "Sin permiso de escritura en /dev/uinput: menus solo con teclado/raton" WARN
            log "Solucion: sudo usermod -aG input \$USER  +  regla udev para uinput" WARN
        fi
        return 0
    fi
    "$PY_BIN" "$PAD_BRIDGE_PY" >> "$LOG_FILE" 2>&1 &
    PAD_BRIDGE_PID=$!
    log "Puente mando->teclado activo (pid $PAD_BRIDGE_PID)"
}

pad_bridge_stop() {
    [ -n "$PAD_BRIDGE_PID" ] && kill "$PAD_BRIDGE_PID" 2>/dev/null
    PAD_BRIDGE_PID=""
    # zombis de sesiones anteriores (script matado sin pasar por el trap):
    # seguian traduciendo mando->teclado y provocaban MOVIMIENTOS DOBLES
    pkill -f "$PAD_BRIDGE_PY" 2>/dev/null
    return 0
}

# ----------------------------------------------------------------------------
# 4d. MAPEADOR .keys (fusionado de DeckStation): mando -> teclado por juego.
#     Si existe <juego>.keys junto al wsquashfs (o en profiles/), se engrana
#     al lanzar y se desengancha al salir. Necesita el modulo python 'evdev':
#     via pip (CachyOS) o dejando tu carpeta evmapy/ en la raiz de WProton.
# ----------------------------------------------------------------------------
STEAM_ADD_PY="$RUNTIME_DIR/steam_add.py"

write_steam_add() {
    grep -q "WPROTON_STEAMADD_V1" "$STEAM_ADD_PY" 2>/dev/null && return 0
    cat > "$STEAM_ADD_PY" <<'SAEOF'
#!/usr/bin/env python3
# WPROTON_STEAMADD_V1 - anade un acceso directo no-Steam a shortcuts.vdf
# uso: steam_add.py <shortcuts.vdf> <nombre> <exe> <startdir> <launchopts> <icono>
import sys, os, struct, zlib

VDF, NAME, EXE, STARTDIR, OPTS, ICON = sys.argv[1:7]

def parse(data):
    # parser minimo del VDF binario de shortcuts
    pos = [0]
    def u8():
        b = data[pos[0]]; pos[0] += 1; return b
    def cstr():
        end = data.index(b'\x00', pos[0])
        sres = data[pos[0]:end].decode('utf-8', 'replace')
        pos[0] = end + 1
        return sres
    def obj():
        out = {}
        while True:
            t = u8()
            if t == 0x08:
                return out
            k = cstr()
            if t == 0x00:
                out[k] = obj()
            elif t == 0x01:
                out[k] = cstr()
            elif t == 0x02:
                out[k] = struct.unpack('<I', data[pos[0]:pos[0]+4])[0]
                pos[0] += 4
            else:
                raise ValueError('tipo %d' % t)
    t = u8(); root_key = cstr()
    assert t == 0x00
    return {root_key: obj()}

def ser_obj(d):
    out = b''
    for k, v in d.items():
        kb = k.encode('utf-8') + b'\x00'
        if isinstance(v, dict):
            out += b'\x00' + kb + ser_obj(v) + b'\x08'
        elif isinstance(v, int):
            out += b'\x02' + kb + struct.pack('<I', v & 0xFFFFFFFF)
        else:
            out += b'\x01' + kb + str(v).encode('utf-8') + b'\x00'
    return out

def serialize(root):
    (k, v), = root.items()
    return b'\x00' + k.encode() + b'\x00' + ser_obj(v) + b'\x08\x08'

if os.path.isfile(VDF) and os.path.getsize(VDF) > 2:
    root = parse(open(VDF, 'rb').read())
else:
    root = {'shortcuts': {}}
key = 'shortcuts' if 'shortcuts' in root else list(root)[0]
sc = root[key]

# ya existe uno con el mismo LaunchOptions? -> actualizar en vez de duplicar
idx = None
for i, e in sc.items():
    if isinstance(e, dict) and e.get('LaunchOptions', '') == OPTS:
        idx = i
        break
if idx is None:
    nums = [int(i) for i in sc.keys() if i.isdigit()]
    idx = str(max(nums) + 1 if nums else 0)

appid = (zlib.crc32((EXE + NAME).encode()) | 0x80000000) & 0xFFFFFFFF
sc[idx] = {
    'appid': appid, 'AppName': NAME, 'Exe': '"%s"' % EXE,
    'StartDir': '"%s"' % STARTDIR, 'icon': ICON, 'ShortcutPath': '',
    'LaunchOptions': OPTS, 'IsHidden': 0, 'AllowDesktopConfig': 1,
    'AllowOverlay': 1, 'OpenVR': 0, 'Devkit': 0, 'DevkitGameID': '',
    'DevkitOverrideAppID': 0, 'LastPlayTime': 0, 'FlatpakAppID': '',
    'tags': {'0': 'WProton'},
}
open(VDF, 'wb').write(serialize(root))
print('OK idx=%s appid=%d' % (idx, appid))
SAEOF
}

find_steam_userdata_config() {
    # config/ del usuario de Steam mas reciente
    local base d best="" bestt=0 t
    for base in "$HOME/.steam/steam" "$HOME/.local/share/Steam" \
                "$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam"; do
        [ -d "$base/userdata" ] || continue
        for d in "$base"/userdata/*/config; do
            [ -d "$d" ] || continue
            t="$(stat -c %Y "$d" 2>/dev/null || echo 0)"
            [ "$t" -gt "$bestt" ] && { bestt=$t; best="$d"; }
        done
    done
    [ -n "$best" ] && printf '%s' "$best"
}

add_game_to_steam() {
    # $1 = ruta del juego (wsquashfs/exe/carpeta), $2 = gid
    local game="$1" gid="$2"
    local cfg; cfg="$(find_steam_userdata_config)"
    [ -z "$cfg" ] && { ui_error "No se encontro la carpeta userdata de Steam"; return 1; }
    if pgrep -x steam >/dev/null 2>&1; then
        ui_ask "Steam esta ABIERTO: sobreescribiria el acceso al cerrarse.
Cierra Steam primero. Continuar de todos modos?" || return 1
    fi
    write_steam_add
    local SELF; SELF="$(readlink -f "$0")"
    local vdf="$cfg/shortcuts.vdf"
    local name; name="$(basename "$game")"; name="${name%.*}"; name="$(printf '%s' "$name" | tr '_' ' ')"
    local icon=""; icon="$(cover_for "$gid")" || icon=""
    [ -f "$vdf" ] && cp -f "$vdf" "$vdf.wproton.bak"
    if "$PY_BIN" "$STEAM_ADD_PY" "$vdf" "$name" "$SELF" "$(dirname "$SELF")" \
        "\"$(readlink -f "$game")\"" "$icon" >> "$LOG_FILE" 2>&1; then
        ui_info "'$name' anadido a Steam como juego no-Steam.
Reinicia Steam para verlo (copia previa: shortcuts.vdf.wproton.bak).
En modo Gaming de la Deck aparecera en NO STEAM."
    else
        ui_error "Fallo escribiendo shortcuts.vdf (mira el log).
Se restauro la copia previa."
        [ -f "$vdf.wproton.bak" ] && cp -f "$vdf.wproton.bak" "$vdf"
        return 1
    fi
}

MAPEADOR_PY="$RUNTIME_DIR/mapeador.py"
MAPEADOR_PID=""

write_mapeador() {
    grep -q "WPROTON_MAPEADOR_V60" "$MAPEADOR_PY" 2>/dev/null && return 0
    cat > "$MAPEADOR_PY" <<'MAPEOF'
# WPROTON_MAPEADOR_V60 (fusionado desde mapeador-60.py de DeckStation)
# Rutas dinamicas: libs_pyX.Y del runtime de WProton + evmapy/ (raiz o runtime)
import sys, os
_RT = os.path.dirname(os.path.abspath(__file__))          # runtime/
_BASE_DIR = os.path.dirname(_RT)                          # raiz de WProton
sys.path.insert(0, os.path.join(_RT, 'libs_py%d.%d' % sys.version_info[:2]))
for _d in (os.path.join(_BASE_DIR, 'evmapy'), os.path.join(_RT, 'evmapy'),
           os.path.join(_BASE_DIR, 'libs_py%d.%d' % sys.version_info[:2])):
    if os.path.isdir(_d):
        sys.path.insert(0, _d)
import sys
import os


import evdev
from evdev import ecodes
import json
import select
import time

# Mapeos de ejes analógicos por defecto para mandos estándar
ABS_ESTANDAR = {
    ecodes.ABS_Y:     ("joystick1up",   "joystick1down"),
    ecodes.ABS_X:     ("joystick1left",  "joystick1right"),
    ecodes.ABS_RY:    ("joystick2up",   "joystick2down"),
    ecodes.ABS_RX:    ("joystick2left",  "joystick2right"),
    ecodes.ABS_HAT0Y: ("up",            "down"),
    ecodes.ABS_HAT0X: ("left",          "right"),
}

PERFILES = {
    "XBOX_360": {
        "match": ["microsoft", "xbox 360", "360", "x-box 360"],
        "ids": {
            "a": 304, "b": 305, "x": 307, "y": 308,
            "start": 315, "select": 314, "hotkey": 314,
            "pageup": 310, "pagedown": 311,
            "l2": 312, "r2": 313, "l3": 317, "r3": 318
        },
        "abs_map": ABS_ESTANDAR, "threshold": 16000, "center": 0
    },
    "XBOX_ONE": {
        "match": ["xbox one", "xbox wireless", "xbox gaming", "input joystick", "x-box one"],
        "ids": {
            "a": 304, "b": 305, "x": 307, "y": 308,
            "start": 315, "select": 314, "hotkey": 314,
            "pageup": 310, "pagedown": 311,
            "l2": 312, "r2": 313, "l3": 317, "r3": 318
        },
        "abs_map": ABS_ESTANDAR, "threshold": 16000, "center": 0
    },
    "8BITDO_ULTIMATE": {
        "match": ["ultimate", "ultimate 2c", "2c"],
        "ids": {
            "a": 304, "b": 305, "x": 307, "y": 308,
            "start": 315, "select": 314, "hotkey": 314,
            "pageup": 310, "pagedown": 311,
            "l2": 312, "r2": 313, "l3": 317, "r3": 318
        },
        "abs_map": ABS_ESTANDAR, "threshold": 40, "center": 127
    },
    "SONY_DS4": {
        "match": ["sony", "playstation", "wireless controller", "dualshock 4", "ps4"],
        "ids": {
            "a": 304, "b": 305, "x": 307, "y": 308,
            "start": 313, "select": 312, "hotkey": 312,
            "pageup": 310, "pagedown": 311,
            "l2": 316, "r2": 317, "l3": 318, "r3": 319
        },
        "abs_map": ABS_ESTANDAR, "threshold": 16000, "center": 0
    },
    "SONY_PS5": {
        "match": ["dualsense", "ps5"],
        "ids": {
            "a": 304, "b": 305, "x": 307, "y": 308,
            "start": 313, "select": 312, "hotkey": 312,
            "pageup": 310, "pagedown": 311,
            "l2": 314, "r2": 315, "l3": 317, "r3": 318
        },
        "abs_map": ABS_ESTANDAR, "threshold": 16000, "center": 0
    },
    "8BITDO": {
        "match": ["8bitdo", "8bitdo pro 2", "8bitdo sn30"],
        "ids": {
            "a": 304, "b": 305, "x": 307, "y": 308,
            "start": 315, "select": 314, "hotkey": 314,
            "pageup": 310, "pagedown": 311,
            "l2": 312, "r2": 313, "l3": 317, "r3": 318
        },
        "abs_map": ABS_ESTANDAR, "threshold": 16000, "center": 0
    },
    "NINTENDO_SWITCH": {
        "match": ["nintendo", "switch", "pro controller", "joy-con"],
        "ids": {
            "a": 305, "b": 304, "x": 309, "y": 308,
            "start": 313, "select": 312, "hotkey": 312,
            "pageup": 310, "pagedown": 311,
            "l2": 314, "r2": 315, "l3": 317, "r3": 318
        },
        "abs_map": ABS_ESTANDAR, "threshold": 16000, "center": 0
    },
    "GENERIC": {
        "match": [],
        "ids": {
            "a": 304, "b": 305, "x": 307, "y": 308,
            "start": 315, "select": 314, "hotkey": 314,
            "pageup": 310, "pagedown": 311,
            "l2": 312, "r2": 313, "l3": 317, "r3": 318
        },
        "abs_map": ABS_ESTANDAR, "threshold": 16000, "center": 0
    }
}

def get_perfil(dev_name):
    name = dev_name.lower()
    for p in PERFILES.values():
        if any(m in name for m in p["match"]):
            return p
    return PERFILES["GENERIC"]



def launch_teclado_virtual(device):
    try:
        import pygame
    except ImportError:
        print("[!] pygame no disponible"); return
    try:
        _run_teclado(device)
    except Exception as e:
        print(f"[!] Error teclado virtual: {e}")

def _run_teclado(gamepad_device):
    import pygame, evdev as _evdev, select as _sel, time as _tm
    from evdev import ecodes as ec
    ROWS = [
        ['1','2','3','4','5','6','7','8','9','0','-','=','\u232b'],
        ['q','w','e','r','t','y','u','i','o','p','[',']','\\'],
        ['a','s','d','f','g','h','j','k','l',';',"'",'\u21b5'],
        ['z','x','c','v','b','n','m',',','.','/',],
        ['\u21e7','ESPACIO','.com','@','\u2715'],
    ]
    KEY_MAP = {
        '1':ec.KEY_1,'2':ec.KEY_2,'3':ec.KEY_3,'4':ec.KEY_4,'5':ec.KEY_5,
        '6':ec.KEY_6,'7':ec.KEY_7,'8':ec.KEY_8,'9':ec.KEY_9,'0':ec.KEY_0,
        '-':ec.KEY_MINUS,'=':ec.KEY_EQUAL,'q':ec.KEY_Q,'w':ec.KEY_W,'e':ec.KEY_E,
        'r':ec.KEY_R,'t':ec.KEY_T,'y':ec.KEY_Y,'u':ec.KEY_U,'i':ec.KEY_I,
        'o':ec.KEY_O,'p':ec.KEY_P,'[':ec.KEY_LEFTBRACE,']':ec.KEY_RIGHTBRACE,
        '\\':ec.KEY_BACKSLASH,'a':ec.KEY_A,'s':ec.KEY_S,'d':ec.KEY_D,
        'f':ec.KEY_F,'g':ec.KEY_G,'h':ec.KEY_H,'j':ec.KEY_J,'k':ec.KEY_K,
        'l':ec.KEY_L,';':ec.KEY_SEMICOLON,"'":ec.KEY_APOSTROPHE,'z':ec.KEY_Z,
        'x':ec.KEY_X,'c':ec.KEY_C,'v':ec.KEY_V,'b':ec.KEY_B,'n':ec.KEY_N,
        'm':ec.KEY_M,',':ec.KEY_COMMA,'.':ec.KEY_DOT,'/':ec.KEY_SLASH,
        '\u232b':ec.KEY_BACKSPACE,'\u21b5':ec.KEY_ENTER,'ESPACIO':ec.KEY_SPACE,
    }
    SHIFT_MAP = {
        '1':'!','2':'@','3':'#','4':'$','5':'%','6':'^','7':'&','8':'*',
        '9':'(','0':')','-':'_','=':'+','[':'{',']':'}','\\':'|',
        ';':':','\'':'"',',':'<','.':'>','/':'?',
    }
    KW,KH,GAP,PAD=56,48,5,18
    total_w=max(len(r) for r in ROWS)*(KW+GAP)-GAP+PAD*2
    total_h=len(ROWS)*(KH+GAP)-GAP+PAD*2+50
    TH,SPEED,DEAD=14000,280.0,0.12
    import os as _os, ctypes as _ct
    _os.environ['SDL_VIDEODRIVER'] = 'x11'  # XWayland
    pygame.init()
    info = pygame.display.Info()
    _os.environ['SDL_VIDEO_WINDOW_POS'] = f'{(info.current_w-total_w)//2},{info.current_h-total_h-30}'
    screen = pygame.display.set_mode((total_w, total_h), pygame.NOFRAME)
    # Aplicar override_redirect=True via XChangeWindowAttributes + unmap/remap
    # override_redirect impide que KWin gestione la ventana → no le da foco de teclado
    # Usamos X11 API directamente porque SDL_VIDEO_X11_OVERRIDE_REDIRECT no es fiable
    try:
        _x11 = _ct.cdll.LoadLibrary('libX11.so.6')
        _x11.XOpenDisplay.restype = _ct.c_void_p
        _dpy = _x11.XOpenDisplay(None)
        _our = pygame.display.get_wm_info().get('window', 0)
        if _dpy and _our:
            class _XWA(_ct.Structure):
                _fields_ = [('background_pixmap',_ct.c_ulong),
                            ('background_pixel', _ct.c_ulong),
                            ('border_pixmap',    _ct.c_ulong),
                            ('border_pixel',     _ct.c_ulong),
                            ('bit_gravity',      _ct.c_int),
                            ('win_gravity',      _ct.c_int),
                            ('backing_store',    _ct.c_int),
                            ('backing_planes',   _ct.c_ulong),
                            ('backing_pixel',    _ct.c_ulong),
                            ('save_under',       _ct.c_int),
                            ('event_mask',       _ct.c_long),
                            ('do_not_propagate', _ct.c_long),
                            ('override_redirect',_ct.c_int),
                            ('colormap',         _ct.c_ulong),
                            ('cursor',           _ct.c_ulong)]
            _wa = _XWA(); _wa.override_redirect = 1
            _CWOverrideRedirect = _ct.c_ulong(0x200)
            _x11.XUnmapWindow(_ct.c_void_p(_dpy), _ct.c_ulong(_our))
            _x11.XChangeWindowAttributes(_ct.c_void_p(_dpy), _ct.c_ulong(_our),
                                         _CWOverrideRedirect, _ct.byref(_wa))
            _x11.XMapWindow(_ct.c_void_p(_dpy), _ct.c_ulong(_our))
            _x11.XFlush(_ct.c_void_p(_dpy))
            _x11.XCloseDisplay(_ct.c_void_p(_dpy))
    except: pass
    fk=pygame.font.SysFont('DejaVu Sans',18,bold=True)
    fp=pygame.font.SysFont('DejaVu Sans',20)
    try:
        ui_kb=_evdev.UInput({ec.EV_KEY:list(range(256))},name="TecladoVirtual_DS")
    except Exception as e:
        print(f"[!] UInput: {e}"); pygame.quit(); return
    def build_layout():
        keys=[]
        for ri,rw in enumerate(ROWS):
            if ri==len(ROWS)-1:
                sp={'ESPACIO':KW*5+GAP*4,'.com':KW*2,'@':KW*2}; x=PAD
                for ci,lb in enumerate(rw):
                    w=sp.get(lb,KW)
                    keys.append((ri,ci,lb,pygame.Rect(x,PAD+50+ri*(KH+GAP),w,KH))); x+=w+GAP
            else:
                n=len(rw); rw_w=n*KW+(n-1)*GAP; x0=PAD+(total_w-PAD*2-rw_w)//2
                for ci,lb in enumerate(rw):
                    keys.append((ri,ci,lb,pygame.Rect(x0+ci*(KW+GAP),PAD+50+ri*(KH+GAP),KW,KH)))
        return keys
    layout=build_layout()
    def key_at(mx,my):
        for ri,ci,lb,rect in layout:
            if rect.collidepoint(mx,my): return ri,ci
        return None,None
    def rect_of(r,c):
        for ri,ci,_,rect in layout:
            if ri==r and ci==c: return rect
        return None
    def press_k(code, shift):
        # UInput: el juego tiene foco Wayland (override-redirect + KWin activateWindow)
        # el compositor entrega los eventos al juego directamente
        if shift: ui_kb.write(ec.EV_KEY, ec.KEY_LEFTSHIFT, 1); ui_kb.syn()
        ui_kb.write(ec.EV_KEY, code, 1); ui_kb.syn()
        ui_kb.write(ec.EV_KEY, code, 0); ui_kb.syn()
        if shift: ui_kb.write(ec.EV_KEY, ec.KEY_LEFTSHIFT, 0); ui_kb.syn()
    def do_key(lb,shift):
        nonlocal preview
        if lb=='\u21e7': return 'shift'
        if lb=='\u2715': return 'close'
        if lb=='ESPACIO': press_k(ec.KEY_SPACE,False); preview+=' '
        elif lb=='.com':
            for cd in [ec.KEY_DOT,ec.KEY_C,ec.KEY_O,ec.KEY_M]: press_k(cd,False)
            preview+='.com'
        elif lb=='@': press_k(ec.KEY_2,True); preview+='@'
        elif lb=='\u21b5': press_k(ec.KEY_ENTER,False); preview=''
        elif lb=='\u232b': press_k(ec.KEY_BACKSPACE,False); preview=preview[:-1]
        else:
            real=SHIFT_MAP.get(lb,lb.upper() if shift else lb)
            kc=KEY_MAP.get(lb)
            if kc: press_k(kc,shift and (lb.isalpha() or lb in SHIFT_MAP))
            preview+=real
        return None
    row,col,shift,preview=1,0,False,''
    ax_val={}; cx,cy=float(total_w//2),float(total_h//2)
    last_move=0; move_delay=0.4
    C={'bg':(20,20,30,210),'key':(55,55,75,230),'sel':(80,140,220,255),
       'sh':(220,160,50,255),'txt':(240,240,240),'sel_t':(255,255,255),
       'prev':(180,220,255),'cur':(255,80,80)}
    clock=pygame.time.Clock(); running=True
    def clamp_col(r,c): return max(0,min(c,len(ROWS[r])-1))
    while running:
        dt=clock.tick(60)/1000.0; now=_tm.time()
        for ev in pygame.event.get():
            if ev.type==pygame.QUIT: running=False
            elif ev.type==pygame.MOUSEMOTION:
                cx,cy=float(ev.pos[0]),float(ev.pos[1])
                mr,mc=key_at(cx,cy)
                if mr is not None: row,col=mr,mc
            elif ev.type==pygame.MOUSEBUTTONDOWN and ev.button==1:
                cx,cy=float(ev.pos[0]),float(ev.pos[1]); mr,mc=key_at(cx,cy)
                if mr is not None:
                    row,col=mr,mc; r=do_key(ROWS[row][col],shift)
                    if r=='shift': shift=not shift
                    elif r=='close': running=False
        rr,_,_=_sel.select([gamepad_device],[],[],0)
        if rr:
            try:
                for ev in gamepad_device.read():
                    if ev.type==ec.EV_ABS: ax_val[ev.code]=ev.value
                    elif ev.type==ec.EV_KEY and ev.value==1:
                        if ev.code==304:
                            mr,mc=key_at(cx,cy)
                            if mr is not None: row,col=mr,mc
                            r=do_key(ROWS[row][col],shift)
                            if r=='shift': shift=not shift
                            elif r=='close': running=False
                        elif ev.code==305: press_k(ec.KEY_BACKSPACE,False); preview=preview[:-1]
                        elif ev.code==308: press_k(ec.KEY_SPACE,False); preview+=' '
                        elif ev.code in (315,313): running=False
                        elif ev.code in (314,312): shift=not shift
            except: pass
        rx_r=ax_val.get(ec.ABS_RX,0); ry_r=ax_val.get(ec.ABS_RY,0)
        rx_n=max(-1.0,min(1.0,rx_r/32767.0 if rx_r>=0 else rx_r/32768.0))
        ry_n=max(-1.0,min(1.0,ry_r/32767.0 if ry_r>=0 else ry_r/32768.0))
        if abs(rx_n)<DEAD: rx_n=0.0
        if abs(ry_n)<DEAD: ry_n=0.0
        if rx_n or ry_n:
            cx=max(0.0,min(float(total_w-1),cx+rx_n*SPEED*dt))
            cy=max(0.0,min(float(total_h-1),cy+ry_n*SPEED*dt))
            mr,mc=key_at(cx,cy)
            if mr is not None: row,col=mr,mc
        ax=ax_val.get(ec.ABS_X,0); ay=ax_val.get(ec.ABS_Y,0)
        hx=ax_val.get(ec.ABS_HAT0X,0); hy=ax_val.get(ec.ABS_HAT0Y,0)
        dx=(1 if ax>TH else -1 if ax<-TH else 0) or (1 if hx>0 else -1 if hx<0 else 0)
        dy=(1 if ay>TH else -1 if ay<-TH else 0) or (1 if hy>0 else -1 if hy<0 else 0)
        if (dx or dy) and (now-last_move>move_delay):
            row=max(0,min(row+dy,len(ROWS)-1)); col=clamp_col(row,col+dx)
            r2=rect_of(row,col)
            if r2: cx,cy=float(r2.centerx),float(r2.centery)
            last_move=now; move_delay=0.12
        elif not dx and not dy: move_delay=0.4
        surf=pygame.Surface((total_w,total_h),pygame.SRCALPHA); surf.fill(C['bg'])
        surf.blit(fp.render(preview[-40:]+'\u258c',True,C['prev']),(PAD,10))
        for ri,ci,lb,rect in layout:
            sel=(ri==row and ci==col)
            bg=C['sel'] if sel else (C['sh'] if lb=='\u21e7' and shift else C['key'])
            pygame.draw.rect(surf,bg,rect,border_radius=6)
            if sel: pygame.draw.rect(surf,C['sel_t'],rect,2,border_radius=6)
            disp=lb
            if len(lb)==1 and lb.isalpha(): disp=lb.upper() if shift else lb
            elif lb in SHIFT_MAP and shift: disp=SHIFT_MAP[lb]
            t=fk.render(disp,True,C['sel_t'] if sel else C['txt'])
            surf.blit(t,(rect.x+(rect.width-t.get_width())//2,rect.y+(rect.height-t.get_height())//2))
        ix,iy=int(cx),int(cy)
        pygame.draw.circle(surf,(255,255,255),(ix,iy),8)
        pygame.draw.circle(surf,C['cur'],(ix,iy),6)
        pygame.draw.circle(surf,(255,255,255),(ix,iy),2)
        screen.blit(surf,(0,0)); pygame.display.flip()
    ui_kb.close(); pygame.quit()

def main():
    try:
        os.nice(-10)
    except:
        pass

    if len(sys.argv) < 2:
        print("Uso: python3 mapeador.py archivo.keys")
        return

    try:
        with open(sys.argv[1], 'r') as f:
            data = json.load(f)
    except Exception as e:
        print(f"Error al cargar .keys: {e}")
        return

    pads = []
    for p in evdev.list_devices():
        try:
            dev = evdev.InputDevice(p)
            dev_name = dev.name.lower()
            if any(x in dev_name for x in ["motion", "accelerometer", "gyro", "touchpad", "mouse", "keyboard", "mapeador"]):
                continue
            if ecodes.EV_ABS in dev.capabilities() and ecodes.EV_KEY in dev.capabilities():
                pads.append(dev)
        except:
            continue

    if not pads:
        print("No se encontró ningún mando válido en el sistema.")
        return

    print("[+] Esperando pulsación en el mando (Timeout ampliado: 30s)...")
    device = None
    start_time = time.time()

    while not device and (time.time() - start_time) < 30.0:
        r, _, _ = select.select(pads, [], [], 0.1)
        for fd in r:
            try:
                for event in fd.read():
                    if event.type == ecodes.EV_KEY and event.value == 1:
                        device = fd
                        break
            except:
                continue
            if device:
                break

    if not device:
        print("[-] Timeout alcanzado. Aplicando auto-selección de mando...")
        for pad in pads:
            if any(m in pad.name.lower() for m in ["xbox", "360", "microsoft", "8bitdo", "ultimate", "dualsense", "sony", "nintendo", "wireless"]):
                device = pad
                break
        if not device:
            device = pads[0]

    print(f"VINCULADO DE FORMA SEGURA: {device.name}")

    perfil_actual = get_perfil(device.name)
    ids            = perfil_actual["ids"]
    abs_map_actual = perfil_actual["abs_map"]
    threshold      = perfil_actual["threshold"]
    center         = perfil_actual["center"]

    map_normal = {}
    map_combos = []
    DIR_KEYS = [
        "up", "down", "left", "right",
        "joystick1up", "joystick1down", "joystick1left", "joystick1right",
        "joystick2up", "joystick2down", "joystick2left", "joystick2right",
    ]
    map_dirs = {k: [] for k in DIR_KEYS}

    for act in data.get('actions_player1', []):
        trig, target = act['trigger'], act['target']
        is_kb = (target == "TECLADO_VIRTUAL")
        t_codes = [] if is_kb else [getattr(ecodes, t)
                   for t in (target if isinstance(target, list) else [target])
                   if hasattr(ecodes, t)]
        if isinstance(trig, list):
            map_combos.append({"req": [ids.get(x, x) for x in trig], "outs": t_codes,
                               "active": False, "kb": is_kb})
        elif trig in map_dirs:
            map_dirs[trig] = t_codes
        elif trig in ids:
            map_normal[ids[trig]] = t_codes

    # ── Teclado virtual para shortcuts ──────────────────────────────────────
    try:
        ui = evdev.UInput(name="Mapeador_KB_Portable")
    except Exception as e:
        print(f"ERROR UInput teclado: {e}")
        return

    import time as _tm
    _mcfg=data.get("mouse",{})
    _MAXIS={"joystick1":(ecodes.ABS_X,ecodes.ABS_Y),"joystick2":(ecodes.ABS_RX,ecodes.ABS_RY)}
    _mabs_x,_mabs_y=_MAXIS.get(_mcfg.get("axis","joystick2"),(ecodes.ABS_RX,ecodes.ABS_RY))
    _mclick=ids.get(_mcfg.get("click_left","r2")) if _mcfg else None
    _mspeed=float(_mcfg.get("speed",900))
    # Mapa de triggers analógicos: en Xbox 360/One el R2 es ABS_RZ, no un botón digital
    _TRIG_ABS = {
        ids.get("r2"): (ecodes.ABS_RZ, ecodes.ABS_GAS),
        ids.get("l2"): (ecodes.ABS_Z,  ecodes.ABS_BRAKE),
    }
    _mclick_abs = _TRIG_ABS.get(_mclick, ()) if _mclick else ()
    _mclick_pressed = False  # Estado previo del trigger analógico
    ui_mouse=None
    if _mcfg:
        try:
            ui_mouse=evdev.UInput({ecodes.EV_REL:[ecodes.REL_X,ecodes.REL_Y],
                                   ecodes.EV_KEY:[ecodes.BTN_LEFT,ecodes.BTN_RIGHT]},
                                  name="Mapeador_Mouse_Portable")
            print(f"[+] Ratón: {_mcfg.get('axis','joystick2')} → mover | {_mcfg.get('click_left','r2')} → click")
        except Exception as e:
            print(f"[!] Sin ratón virtual: {e}"); ui_mouse=None
    _macc_x=0.0; _macc_y=0.0; _mlast=_tm.monotonic(); _msx=center; _msy=center

    pulsados = set()
    ejes_on  = {k: False for k in DIR_KEYS}

    try:
        while True:
            r, _, _ = select.select([device], [], [], 0.001)
            if r:
                try:
                    for event in device.read():

                        # ── Botones digitales ────────────────────────────────
                        if event.type == ecodes.EV_KEY:
                            if event.value == 1:
                                pulsados.add(event.code)
                            elif event.value == 0:
                                pulsados.discard(event.code)

                            # Combos → teclado / acciones especiales
                            for c in map_combos:
                                all_pressed = all(btn in pulsados for btn in c["req"])
                                if all_pressed and not c["active"] and event.value == 1:
                                    c["active"] = True
                                    if c.get("kb"):
                                        ui.syn()
                                        try: launch_teclado_virtual(device)
                                        except Exception as _e: print(f"[!] {_e}")
                                        pulsados.clear()
                                    else:
                                        for t in c["outs"]: ui.write(ecodes.EV_KEY, t, 1)
                                elif c["active"] and not all_pressed and event.value == 0:
                                    c["active"] = False
                                    if not c.get("kb"):
                                        for t in c["outs"]: ui.write(ecodes.EV_KEY, t, 0)

                            # Botón individual → teclado (solo si no está en combo activo)
                            in_active_combo = any(
                                event.code in c["req"] and c["active"] for c in map_combos
                            )
                            if not in_active_combo and event.code in map_normal:
                                for t in map_normal[event.code]:
                                    ui.write(ecodes.EV_KEY, t, event.value)

                            # Click digital (PS4, bumpers, botones)
                            if ui_mouse and _mclick and not _mclick_abs and event.code == _mclick:
                                ui_mouse.write(ecodes.EV_KEY,ecodes.BTN_LEFT,event.value)
                                ui_mouse.syn()
                            ui.syn()

                        # ── Ejes analógicos ──────────────────────────────────
                        elif event.type == ecodes.EV_ABS:
                            if event.code == _mabs_x: _msx = event.value
                            elif event.code == _mabs_y: _msy = event.value
                            # Click analógico: R2/L2 Xbox 360 mandan ABS_RZ/ABS_Z
                            elif ui_mouse and _mclick_abs and event.code in _mclick_abs:
                                _now_pressed = event.value > 64  # umbral: trigger > 25% de recorrido
                                if _now_pressed != _mclick_pressed:
                                    _mclick_pressed = _now_pressed
                                    ui_mouse.write(ecodes.EV_KEY, ecodes.BTN_LEFT,
                                                   1 if _now_pressed else 0)
                                    ui_mouse.syn()
                            # Mapeo de dirección → teclado
                            if event.code in abs_map_actual:
                                neg_dir, pos_dir = abs_map_actual[event.code]
                                val = event.value - center
                                neg_active = val < -threshold
                                pos_active = val > threshold
                                for direction, active in ((neg_dir, neg_active), (pos_dir, pos_active)):
                                    if active != ejes_on[direction]:
                                        ejes_on[direction] = active
                                        for t in map_dirs[direction]:
                                            ui.write(ecodes.EV_KEY, t, 1 if active else 0)

                            ui.syn()

                except (IOError, OSError):
                    break
            if ui_mouse:
                _n=_tm.monotonic(); _dt=min(_n-_mlast,0.05); _mlast=_n
                _mr=32767.0 if center==0 else 127.0
                _rx=max(-1.0,min(1.0,(_msx-center)/_mr))
                _ry=max(-1.0,min(1.0,(_msy-center)/_mr))
                if abs(_rx)<0.12: _rx=0.0
                if abs(_ry)<0.12: _ry=0.0
                _macc_x+=_rx*_mspeed*_dt; _macc_y+=_ry*_mspeed*_dt
                _ix=int(_macc_x); _iy=int(_macc_y)
                if _ix: ui_mouse.write(ecodes.EV_REL,ecodes.REL_X,_ix); _macc_x-=_ix
                if _iy: ui_mouse.write(ecodes.EV_REL,ecodes.REL_Y,_iy); _macc_y-=_iy
                if _ix or _iy: ui_mouse.syn()
    finally:
        if ui_mouse:
            try: ui_mouse.close()
            except: pass

if __name__ == "__main__":
    main()

MAPEOF
}

find_keys_file() {
    # $1 = ruta del juego (wsquashfs o exe), $2 = gid. Orden del script antiguo.
    local p="$1" gid="$2"
    for k in "${p%.*}.keys" "$p.keys" "$PROFILE_DIR/$gid.keys"; do
        [ -f "$k" ] && { printf '%s' "$k"; return 0; }
    done
    return 1
}

mapeador_start() {
    # $1 = fichero .keys
    write_mapeador
    # evdev es imprescindible: probar el import y avisar CLARO si falta
    if ! WP_RT="$RUNTIME_DIR" "$PY_BIN" -c 'import sys,os
rt=os.environ["WP_RT"]; base=os.path.dirname(rt)
sys.path.insert(0, os.path.join(rt, "libs_py%d.%d" % sys.version_info[:2]))
[sys.path.insert(0, d) for d in (os.path.join(base,"evmapy"), os.path.join(rt,"evmapy")) if os.path.isdir(d)]
import evdev' >> "$LOG_FILE" 2>&1; then
        say "AVISO: mapeador .keys NO activado: falta el modulo python evdev"
        say "       Solucion: ejecuta --setup (CachyOS con gcc) o copia tu carpeta evmapy/ a la raiz de WProton"
        return 1
    fi
    say "[+] Engranando mapeador para: $(basename "$1")"
    PYGAME_HIDE_SUPPORT_PROMPT=1 "$PY_BIN" "$MAPEADOR_PY" "$1" >> "$LOG_FILE" 2>&1 &
    MAPEADOR_PID=$!
    sleep 1
    if ! kill -0 "$MAPEADOR_PID" 2>/dev/null; then
        say "AVISO: el mapeador murio al arrancar; ultimas lineas del log:"
        tail -n 4 "$LOG_FILE" >> "$LOG_FILE" 2>&1
        MAPEADOR_PID=""
        return 1
    fi
    return 0
}

mapeador_stop() {
    [ -n "$MAPEADOR_PID" ] && kill "$MAPEADOR_PID" 2>/dev/null
    MAPEADOR_PID=""
    pkill -f "$MAPEADOR_PY" 2>/dev/null
    return 0
}

# ----------------------------------------------------------------------------
# 4b. MENU PYGAME (preferido): mando nativo via SDL, cero dependencias del
#     sistema (usa el Python portable + pygame de runtime/libs_pyX.Y)
# ----------------------------------------------------------------------------
MENU_PYGAME_PY="$RUNTIME_DIR/menu_pygame.py"
HAS_PYGAME=-1   # -1 = sin comprobar

PYGAME_OK_MARK="$RUNTIME_DIR/.pygame_ok"
pygame_available() {
    [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ] || return 1
    # Cache en fichero: menu() corre en subshells y una variable no persiste,
    # asi que sin esto el import de prueba (y su BANNER por stdout, que
    # contaminaba la seleccion capturada) se ejecutaba en CADA menu.
    if [ -f "$PYGAME_OK_MARK" ]; then
        [ "$(cat "$PYGAME_OK_MARK" 2>/dev/null)" = "$PY_BIN" ] && return 0
    fi
    if [ "$HAS_PYGAME" = -1 ]; then
        if [ -n "$PY_BIN" ] && \
           WP_RT="$RUNTIME_DIR" PYGAME_HIDE_SUPPORT_PROMPT=1 \
           "$PY_BIN" -c 'import sys,os;sys.path.insert(0,os.path.join(os.environ["WP_RT"],"libs_py%d.%d"%sys.version_info[:2]));import pygame' >/dev/null 2>&1; then
            HAS_PYGAME=1
            printf '%s' "$PY_BIN" > "$PYGAME_OK_MARK"
        else
            HAS_PYGAME=0
            rm -f "$PYGAME_OK_MARK"
            log "pygame no disponible: menus via GTK/zenity (instala con --setup)" WARN
        fi
    fi
    [ "$HAS_PYGAME" = 1 ]
}

write_menu_pygame() {
    # Reescribir solo si falta o es de otra version (I/O gratis en cada menu)
    grep -q "WPROTON_HELPER_V38" "$MENU_PYGAME_PY" 2>/dev/null && return 0
    cat > "$MENU_PYGAME_PY" <<'PGEOF'
#!/usr/bin/env python3
# WPROTON_HELPER_V38
# Menu/explorador de WProton en pygame: mando via hilo evdev (sin foco),
# navegador persistente, y BUSQUEDA: teclado real (type-ahead) o teclado
# virtual en pantalla para el mando (boton Y).
# Modos:
#   list   <titulo> <salida> <fichero_opciones>
#   check  <titulo> <salida> <fichero_opciones>   ("0|Texto"/"1|Texto")
#   browse <titulo> <salida> <dir_inicial> <file|dir|play|keys>
#   grid   <titulo> <salida> <manifiesto>   (lineas "titulo|imagen|payload")
#   progress <titulo> <fichero_estado>     (el fichero lleva "pct|texto")
#   text   <titulo> <salida> <valor_inicial>  (teclado en pantalla)
#   canvas <titulo> <fichero_estado>       (fondo persistente del modo Juego)
import os, sys, time

BASE = os.path.dirname(os.path.abspath(__file__))
LIBS = os.path.join(BASE, 'libs_py%d.%d' % sys.version_info[:2])
if os.path.isdir(LIBS):
    sys.path.insert(0, LIBS)

os.environ.setdefault('SDL_JOYSTICK_ALLOW_BACKGROUND_EVENTS', '1')
os.environ.setdefault('PYGAME_HIDE_SUPPORT_PROMPT', '1')
os.environ.setdefault('SDL_VIDEO_CENTERED', '1')
os.environ.setdefault('SDL_VIDEO_MINIMIZE_ON_FOCUS_LOSS', '0')
# Pantalla completa: forzada en Batocera, o recordada entre menus con un
# marcador (cada menu es un proceso nuevo, asi que la preferencia va a fichero)
FS_MARK = os.path.join(BASE, '.menu_fullscreen')
FULLSCREEN = os.environ.get('WP_MENU_FS') == '1' or os.path.isfile(FS_MARK)
# Orden de drivers de video a probar. En sesion gamescope (modo Juego de
# SteamOS) va primero Wayland: forzar x11/XWayland deja la ventana detras y
# se ve la pantalla en negro. En escritorio, al reves.
IS_GAMESCOPE_SESS = bool(os.environ.get('GAMESCOPE_WAYLAND_DISPLAY')) or \
    os.environ.get('XDG_CURRENT_DESKTOP') == 'gamescope'
if os.environ.get('SDL_VIDEODRIVER'):
    DRIVER_ORDER = [os.environ['SDL_VIDEODRIVER'], None]
elif IS_GAMESCOPE_SESS:
    DRIVER_ORDER = ['wayland', 'x11', None]
elif os.environ.get('DISPLAY'):
    DRIVER_ORDER = ['x11', 'wayland', None]
else:
    DRIVER_ORDER = ['wayland', None]
import pygame

MODE, TITLE, OUTFILE = sys.argv[1], sys.argv[2], sys.argv[3]
# en modo 'progress' el 3er argumento ya es el fichero de estado
ARG4 = sys.argv[4] if len(sys.argv) > 4 else OUTFILE
BROWSE_KIND = sys.argv[5] if len(sys.argv) > 5 else 'file'
BROWSE_EXTS = ('.wsquashfs', '.squashfs', '.dwarfs', '.zip', '.7z', '.rar',
               '.001', '.z01', '.exe', '.wtgz')
if BROWSE_KIND == 'keys':
    BROWSE_EXTS = ('.keys',)
K_HDR, K_UP2, K_CANCEL, K_DIR, K_FILE, K_PLAIN = range(6)
HEADER_KINDS = (K_HDR, K_UP2, K_CANCEL)

items = []          # [tipo, texto, marcado]
view = []           # indices visibles segun el filtro de busqueda
cur_path = ''
sel, scroll = 0, 0
FILTER = ''
kb_open = False
kb_r, kb_c = 0, 0

def _match(text, f):
    # Coincidencia por PREFIJO de palabra: "s" -> solo titulos con alguna
    # palabra que empiece por s (no cualquier titulo que contenga una s).
    # Varias palabras ("sil h"): cada trozo debe ser prefijo de alguna palabra.
    words = text.lower().replace('_', ' ').replace('-', ' ').replace('.', ' ').split()
    for tok in f.split():
        if not any(w.startswith(tok) for w in words):
            return False
    return True

def apply_filter():
    global view, sel, scroll
    if FILTER.strip():
        f = FILTER.lower()
        view = [i for i, it in enumerate(items)
                if it[0] in HEADER_KINDS or _match(it[1], f)]
    else:
        view = list(range(len(items)))
    sel = 0
    scroll = 0

def load_options():
    global items
    items = []
    with open(ARG4, encoding='utf-8') as f:
        for l in f:
            l = l.rstrip('\n')
            if not l.strip():
                continue
            if MODE == 'check':
                on, _, txt = l.partition('|')
                items.append([K_PLAIN, txt, on == '1'])
            else:
                items.append([K_PLAIN, l, False])
    apply_filter()

def load_dir(path):
    # Navegacion EN PROCESO: sin relanzar python/ventana por carpeta
    global items, cur_path, FILTER
    cur_path = os.path.realpath(path)
    FILTER = ''
    items = []
    if BROWSE_KIND == 'dir':
        items.append([K_HDR, '>> USAR ESTA CARPETA <<', False])
    elif BROWSE_KIND == 'play':
        items.append([K_HDR, '>> JUGAR ESTA CARPETA <<', False])
    elif BROWSE_KIND != 'keys':
        items.append([K_HDR, '>> IMPORTAR ESTA CARPETA <<', False])
    items.append([K_UP2, '.. (subir)', False])
    items.append([K_CANCEL, '<< Cancelar', False])
    try:
        names = sorted(os.listdir(cur_path), key=str.lower)
    except OSError:
        names = []
    for n in names:
        if not n.startswith('.') and os.path.isdir(os.path.join(cur_path, n)):
            items.append([K_DIR, n + '/', False])
    if BROWSE_KIND in ('file', 'play', 'keys'):
        for n in names:
            p = os.path.join(cur_path, n)
            if (not n.startswith('.') and os.path.isfile(p)
                    and n.lower().endswith(BROWSE_EXTS)):
                items.append([K_FILE, n, False])
    apply_filter()

GITEMS = []          # (titulo, ruta_imagen, payload)

def load_manifest():
    global GITEMS
    GITEMS = []
    with open(ARG4, encoding='utf-8') as f:
        for l in f:
            l = l.rstrip('\n')
            if not l.strip():
                continue
            parts = l.split('|')
            while len(parts) < 4:
                parts.append('')
            GITEMS.append((parts[0], parts[1], parts[2], parts[3]))

def grid_apply_filter():
    global view, sel, scroll
    if FILTER.strip():
        f = FILTER.lower()
        view = [i for i, it in enumerate(GITEMS) if _match(it[0], f)]
    else:
        view = list(range(len(GITEMS)))
    sel = 0
    scroll = 0

if MODE in ('progress', 'text', 'canvas'):
    pass
elif MODE == 'browse':
    load_dir(ARG4 if os.path.isdir(ARG4) else os.path.expanduser('~'))
elif MODE == 'grid':
    load_manifest()
    grid_apply_filter()
else:
    load_options()

def init_video():
    # pygame.init() NO lanza excepcion si solo falla el video: devuelve el
    # numero de subsistemas fallidos y sigue, y luego revienta el primer uso
    # ("video system not initialized"). Hay que inicializar el video aparte
    # y probar los drivers uno a uno.
    for drv in DRIVER_ORDER:
        if drv:
            os.environ['SDL_VIDEODRIVER'] = drv
        else:
            os.environ.pop('SDL_VIDEODRIVER', None)
        try:
            pygame.display.quit()
        except Exception:
            pass
        try:
            pygame.display.init()
            sys.stderr.write('menu_pygame: video OK con driver %s\n' % (drv or 'auto'))
            return True
        except Exception as e:
            sys.stderr.write('menu_pygame: driver %s no vale (%s)\n' % (drv or 'auto', e))
    return False

pygame.init()          # el resto de subsistemas (no falla aunque el video si)
if not init_video():
    sys.stderr.write('menu_pygame: sin video utilizable; se usaran menus de texto\n')
    sys.exit(2)
pygame.key.set_repeat(400, 120)

# --- hilo evdev: unico camino del mando (funciona sin foco de ventana) ---
import struct, threading, select as _select

EV_KEY_RAW, EV_ABS_RAW = 1, 3
IE_FMT = 'llHHi'
IE_SZ = struct.calcsize(IE_FMT)
# A/Start=Enter | B=Esc | X=Espacio | Y=Tab (abre el teclado de busqueda)
RAW_BTN = {304: pygame.K_RETURN, 315: pygame.K_RETURN,
           305: pygame.K_ESCAPE, 307: pygame.K_SPACE,
           308: pygame.K_TAB}
SELECT_BTN = 314          # BTN_SELECT: con A pulsa pantalla completa
# Crucetas que reportan BOTONES (Anbernic/Decktroid...) en vez de hat:
DPAD_BTN = {544: pygame.K_UP, 545: pygame.K_DOWN,
            546: pygame.K_LEFT, 547: pygame.K_RIGHT}

def parse_input_chunk(data):
    out = []
    for off in range(0, len(data) - IE_SZ + 1, IE_SZ):
        _, _, t, c, v = struct.unpack_from(IE_FMT, data, off)
        out.append((t, c, v))
    return out

BAD_DEV = ('accel', 'gyro', 'imu', 'motion', 'sensor')
def find_raw_pads():
    # Solo mandos de verdad: fuera acelerometros/giroscopos que Batocera y los
    # handhelds exponen como joystick (movian el menu al inclinar la consola)
    pads = []
    try:
        blocks = open('/proc/bus/input/devices').read().split('\n\n')
    except OSError:
        return pads
    for b in blocks:
        name, ev, has_js = '', None, False
        for line in b.split('\n'):
            if line.startswith('N:'):
                name = line.lower()
            elif line.startswith('H:'):
                l2 = line.replace('=', ' ')
                if ' js' in l2:
                    has_js = True
                for tok in l2.split():
                    if tok.startswith('event'):
                        ev = tok
        if has_js and ev and not any(k in name for k in BAD_DEV):
            pads.append('/dev/input/' + ev)
    return pads

def post_key(k):
    try:
        pygame.event.post(pygame.event.Event(pygame.KEYDOWN, key=k))
    except Exception:
        pass

AXIS_KEYS = {17: (pygame.K_UP, pygame.K_DOWN),      # dpad vertical
             16: (pygame.K_LEFT, pygame.K_RIGHT),   # dpad horizontal
             1:  (pygame.K_UP, pygame.K_DOWN),      # stick izq vertical
             0:  (pygame.K_LEFT, pygame.K_RIGHT)}   # stick izq horizontal

def evdev_thread():
    fds, held, ax = {}, {}, {}
    sel_held = [False]
    last_scan = 0.0
    REP_FIRST, REP_NEXT = 0.40, 0.15
    TH_ON, TH_OFF = 18000, 12000
    sys.stderr.write('menu_pygame: fallback evdev ACTIVO (leyendo /dev/input)\n')
    while True:
        now = time.time()
        if now - last_scan > 2:
            last_scan = now
            for p in find_raw_pads():
                if p not in fds:
                    try:
                        fds[p] = os.open(p, os.O_RDONLY | os.O_NONBLOCK)
                        sys.stderr.write('menu_pygame: mando via evdev: %s\n' % p)
                    except OSError as e:
                        sys.stderr.write('menu_pygame: sin acceso a %s (%s)\n' % (p, e))
        try:
            r, _, _ = _select.select(list(fds.values()), [], [], 0.05 if held else 0.5)
        except OSError:
            r = []
        for fd in r:
            try:
                data = os.read(fd, IE_SZ * 64)
            except OSError:
                for p, f in list(fds.items()):
                    if f == fd:
                        try: os.close(f)
                        except OSError: pass
                        del fds[p]
                continue
            for t, c, v in parse_input_chunk(data):
                if t == EV_KEY_RAW and c in DPAD_BTN:
                    k = DPAD_BTN[c]
                    if v == 1:
                        post_key(k); held[k] = time.time() + REP_FIRST
                    else:
                        held.pop(k, None)
                elif t == EV_KEY_RAW and c == SELECT_BTN:
                    sel_held[0] = (v != 0)
                elif t == EV_KEY_RAW and c in RAW_BTN and v == 1:
                    if c == 304 and sel_held[0]:
                        post_key(pygame.K_F11)      # Select + A
                    else:
                        post_key(RAW_BTN[c])
                elif t == EV_ABS_RAW and c in (16, 17):
                    neg, pos = AXIS_KEYS[c]
                    for n in (neg, pos):
                        held.pop(n, None)
                    if v != 0:
                        k = pos if v > 0 else neg
                        post_key(k); held[k] = time.time() + REP_FIRST
                elif t == EV_ABS_RAW and c in (0, 1):
                    st = ax.get((fd, c), 0)
                    new = st
                    if st == 0 and abs(v) > TH_ON: new = 1 if v > 0 else -1
                    elif st != 0 and abs(v) < TH_OFF: new = 0
                    if new != st:
                        ax[(fd, c)] = new
                        neg, pos = AXIS_KEYS[c]
                        for n in (neg, pos):
                            held.pop(n, None)
                        if new != 0:
                            k = pos if new > 0 else neg
                            post_key(k); held[k] = time.time() + REP_FIRST
        now = time.time()
        for k, t_ in list(held.items()):
            if now >= t_:
                post_key(k); held[k] = now + REP_NEXT

if MODE != 'canvas':
    # el lienzo solo pinta: si leyera el mando competiria con el menu que
    # tiene delante (dos lectores del mismo /dev/input)
    threading.Thread(target=evdev_thread, daemon=True).start()

W, H = 960, 680
def _open_window():
    if FULLSCREEN:
        return pygame.display.set_mode((0, 0), pygame.FULLSCREEN)
    return pygame.display.set_mode((W, H))
try:
    screen = _open_window()
except Exception as e:
    sys.stderr.write('menu_pygame: no se pudo abrir la ventana (%s)\n' % e)
    if FULLSCREEN:                      # reintentar en ventana
        FULLSCREEN = False
        screen = _open_window()
    else:
        raise
if FULLSCREEN:
    W, H = screen.get_size()
pygame.display.set_caption('WProton')
sys.stderr.write('menu_pygame: video driver = %s\n' % pygame.display.get_driver())

if IS_GAMESCOPE_SESS:
    # En modo Juego la ventana puede nacer sin foco (el compositor aun se lo
    # esta quitando al juego que acaba de cerrarse): lo pedimos explicitamente.
    try:
        pygame.event.set_grab(False)
    except Exception:
        pass
    for _i in range(3):
        try:
            pygame.display.flip()
        except Exception:
            break
        time.sleep(0.15)

def apply_layout():
    global W, H, VIS_FULL, VIS_KB, GCOLS, LIST_X, LIST_Y, LIST_W, LIST_H, SIDE_X, SIDE_W
    W, H = screen.get_size()
    make_bg()
    make_scan()
    if PANEL_UI and MODE == 'grid':
        # en rejilla no hay panel lateral: todo el ancho para las caratulas
        LIST_X, LIST_Y = 20, HEAD + 16
        LIST_H = H - LIST_Y - 76
        LIST_W = W - 40
        SIDE_W, SIDE_X = 0, 0
    elif PANEL_UI:
        # Interfaz de dos paneles: lista a la izquierda, detalles a la derecha
        foot = 62
        LIST_X, LIST_Y = 20, HEAD + 16
        LIST_H = H - LIST_Y - foot - 14
        if MODE in ('list', 'check', 'browse'):
            SIDE_W = max(240, int(W * 0.34))
            SIDE_X = W - SIDE_W - 20
            LIST_W = SIDE_X - LIST_X - 16
        else:
            SIDE_W, SIDE_X = 0, 0
            LIST_W = W - 40
    else:
        LIST_X, LIST_Y = 16, TOP
        LIST_W, LIST_H = W - 32, H - TOP - 60
    VIS_FULL = max(1, LIST_H // ROW)
    VIS_KB = max(1, (LIST_H - KB_H) // ROW)
    grid_metrics()

def toggle_fullscreen():
    global screen, FULLSCREEN, scroll
    FULLSCREEN = not FULLSCREEN
    try:
        screen = _open_window()
    except Exception:
        FULLSCREEN = not FULLSCREEN
        screen = _open_window()
    try:
        if FULLSCREEN:
            open(FS_MARK, 'w').close()
        elif os.path.isfile(FS_MARK):
            os.remove(FS_MARK)
    except Exception:
        pass
    apply_layout()
    scroll = 0
    sys.stderr.write('menu_pygame: pantalla completa = %s\n' % FULLSCREEN)
clock = pygame.time.Clock()
f_tit = pygame.font.Font(None, 34)
f_it  = pygame.font.Font(None, 30)
f_sm  = pygame.font.Font(None, 24)
f_kb  = pygame.font.Font(None, 28)

# ---------------------------------------------------------------------------
# TEMAS: "clasico" (el de siempre, sobrio) y "moderno" (paneles y acento neon).
# Se elige con WP_THEME; para anadir uno nuevo basta con copiar un bloque y
# cambiar los colores: el resto del helper se adapta solo.
# ---------------------------------------------------------------------------
THEMES = {
    'clasico': {
        'bg': (24, 26, 32), 'bg2': (24, 26, 32),
        'fg': (225, 228, 235), 'dim': (140, 145, 155),
        'sel_bg': (38, 92, 170), 'sel_fg': (255, 255, 255),
        'acc': (120, 200, 130), 'dir': (150, 190, 240),
        'warn': (230, 180, 90), 'kb_bg': (34, 37, 46),
        'panel': None, 'border': (60, 64, 74), 'card': (44, 48, 60),
        'radius': 6, 'pill': False, 'rule': True, 'glow': False,
        'layout': 'simple', 'row': 40,
    },
    'moderno': {
        'bg': (14, 17, 26), 'bg2': (24, 30, 46),
        'fg': (232, 240, 252), 'dim': (128, 142, 168),
        'sel_bg': (26, 60, 82), 'sel_fg': (150, 240, 255),
        'acc': (56, 214, 224), 'dir': (124, 200, 255),
        'warn': (250, 196, 106), 'kb_bg': (20, 26, 40),
        'panel': (22, 28, 42), 'border': (44, 60, 88), 'card': (26, 33, 50),
        'radius': 12, 'pill': True, 'rule': False, 'glow': True,
        'layout': 'panel', 'row': 48,
        'acc2': (168, 120, 255), 'ok': (86, 226, 160),
        'btn': True, 'labelcolor': True, 'shape': 'notch',
    },
    # Arcade synthwave: rejilla en perspectiva, escaneado CRT, marcador de
    # seleccion y esquinas de HUD. Nada minimalista, a proposito.
    'arcade': {
        'bg': (12, 4, 30), 'bg2': (58, 12, 74),
        'fg': (255, 244, 252), 'dim': (170, 130, 200),
        'sel_bg': (92, 12, 96), 'sel_fg': (255, 255, 255),
        'acc': (255, 46, 147), 'dir': (94, 234, 255),
        'warn': (255, 214, 84), 'kb_bg': (24, 8, 44),
        'panel': (26, 8, 48), 'border': (120, 40, 140), 'card': (36, 12, 60),
        'radius': 0, 'pill': True, 'rule': False, 'glow': True,
        'layout': 'arcade', 'row': 48,
        'acc2': (94, 234, 255), 'ok': (120, 255, 170),
        'scan': True, 'gridbg': True, 'brackets': True,
        'marker': True, 'numbered': True, 'shadow': True,
        'btn': True, 'labelcolor': True, 'shape': 'rect',
    },
}
# Accion secundaria: con WP_ACTION_X=1, la X devuelve la seleccion marcada
# para que quien llame abra la configuracion en vez de jugar.
ACTION_X = os.environ.get('WP_ACTION_X') == '1'
LANG = os.environ.get('WP_LANG', 'es')
# El helper lee el MISMO lang/<codigo>.json que el script: asi los textos
# propios (SELECCION, chips, teclado) se traducen a cualquier idioma nuevo
# sin tocar el codigo.
_LANGMAP = {}
if LANG != 'es':
    try:
        import json as _json
        with open(os.path.join(os.path.dirname(BASE), 'lang', LANG + '.json'),
                  encoding='utf-8') as _fh:
            _LANGMAP = {k: v for k, v in _json.load(_fh).items() if isinstance(v, str) and v}
    except Exception:
        _LANGMAP = {}

def L(es, en=None):
    # busca en el json; si no esta, usa el ingles de respaldo (si se paso)
    if LANG == 'es':
        return es
    if es in _LANGMAP:
        return _LANGMAP[es]
    return en if en is not None else es
THEME_NAME = os.environ.get('WP_THEME', 'clasico')
if THEME_NAME not in THEMES:
    THEME_NAME = 'clasico'
TH = THEMES[THEME_NAME]

BG   = TH['bg']
FG   = TH['fg']
HIBG = TH['sel_bg']
DIM  = TH['dim']
ACC  = TH['acc']
DIRC = TH['dir']
KBBG = TH['kb_bg']
WARN = TH['warn']
RAD  = TH['radius']

BGSURF = None
SCANSURF = None
def make_scan():
    # Velo de lineas de escaneo (CRT): se dibuja una vez y se superpone
    global SCANSURF
    if not TH.get('scan'):
        SCANSURF = None
        return
    try:
        surf = pygame.Surface((W, H), pygame.SRCALPHA)
    except Exception:
        SCANSURF = None
        return
    for y in range(0, H, 3):
        pygame.draw.rect(surf, (0, 0, 0, 46), (0, y, W, 1))
    SCANSURF = surf

def make_bg():
    # Fondo: liso en clasico, degradado vertical suave en moderno
    global BGSURF
    surf = pygame.Surface((W, H))
    if TH.get('gridbg'):
        # Cielo degradado + horizonte con rejilla en fuga (synthwave)
        c1, c2 = TH['bg2'], TH['bg']
        hz = int(H * 0.42)
        for i in range(hz):
            f = i / float(max(1, hz - 1))
            col = tuple(int(c1[k] + (c2[k] - c1[k]) * f) for k in range(3))
            pygame.draw.rect(surf, col, (0, i, W, 1))
        pygame.draw.rect(surf, TH['bg'], (0, hz, W, H - hz))
        pygame.draw.rect(surf, TH['acc'], (0, hz - 2, W, 2))
        gcol = (TH['border'][0], TH['border'][1], TH['border'][2])
        vp = W // 2
        for k in range(-14, 15):          # verticales que convergen
            pygame.draw.line(surf, gcol, (vp + k * 46, hz), (vp + k * 300, H), 1)
        yy, step = hz + 6, 6              # horizontales cada vez mas separadas
        while yy < H:
            pygame.draw.line(surf, gcol, (0, yy), (W, yy), 1)
            step = int(step * 1.42) + 1
            yy += step
    elif TH['bg'] == TH['bg2']:
        surf.fill(TH['bg'])
    else:
        c1, c2 = TH['bg'], TH['bg2']
        steps = 48
        bh = H // steps + 1
        for i in range(steps):
            f = i / float(steps - 1)
            col = tuple(int(c1[k] + (c2[k] - c1[k]) * f) for k in range(3))
            pygame.draw.rect(surf, col, (0, i * bh, W, bh))
    BGSURF = surf

def draw_panel(rect):
    if TH['panel'] is None:
        return
    x, y, w, h = rect
    pygame.draw.rect(screen, TH['panel'], rect, border_radius=RAD)
    if TH.get('brackets'):
        # Marco de HUD: solo las esquinas, en color de acento
        c, L, t = ACC, 26, 3
        for (cx, cy, dx, dy) in ((x, y, 1, 1), (x + w, y, -1, 1),
                                 (x, y + h, 1, -1), (x + w, y + h, -1, -1)):
            pygame.draw.rect(screen, c, (min(cx, cx + dx * L), cy - (t if dy < 0 else 0), L, t))
            pygame.draw.rect(screen, c, (cx - (t if dx < 0 else 0), min(cy, cy + dy * L), t, L))
        pygame.draw.rect(screen, TH['border'], rect, 1)
    else:
        pygame.draw.rect(screen, TH['border'], rect, 1, border_radius=RAD)

def hbar(rect, c1, c2):
    # Barra con degradado horizontal (cabecera y seleccion del tema moderno)
    x, y, w, h = rect
    if w <= 0:
        return
    steps = 26
    sw = max(1, w // steps + 1)
    for i in range(steps):
        f = i / float(steps - 1)
        col = tuple(int(c1[k] + (c2[k] - c1[k]) * f) for k in range(3))
        pygame.draw.rect(screen, col, (x + i * sw, y, sw, h))

def vbar(rect, c1, c2):
    # Degradado vertical: da relieve de boton a las filas
    x, y, w, h = rect
    if h <= 0 or w <= 0:
        return
    steps = 12
    sh = max(1, h // steps + 1)
    for i in range(steps):
        f = i / float(steps - 1)
        col = tuple(int(c1[k] + (c2[k] - c1[k]) * f) for k in range(3))
        pygame.draw.rect(screen, col, (x, y + i * sh, w, sh))

def notch_points(x, y, w, h, n=15):
    # Cantos cortados en diagonal (arriba-derecha y abajo-izquierda)
    return [(x, y), (x + w - n, y), (x + w, y + n),
            (x + w, y + h), (x + n, y + h), (x, y + h - n)]

def draw_button_notch(rect, active):
    # Moderno: cápsula achaflanada, relleno plano y pestana de acento
    x, y, w, h = rect
    pts = notch_points(x, y, w, h)
    fill = TH['card'] if not active else tuple(min(255, int(c * 0.34) + 18) for c in ACC)
    try:
        pygame.draw.polygon(screen, fill, pts)
        pygame.draw.polygon(screen, ACC if active else TH['border'], pts, 2 if active else 1)
    except Exception:
        pygame.draw.rect(screen, fill, rect)
    # pestana lateral: fina si esta en reposo, gruesa y luminosa al elegir
    pygame.draw.rect(screen, ACC if active else TH['border'],
                     (x, y + (0 if active else 8), 6 if active else 3,
                      h - (0 if active else 16)))
    if active:
        pygame.draw.rect(screen, TH.get('acc2', ACC), (x + w - 15, y, 15, 3))

def draw_button(rect, active):
    # Fila con aspecto de boton: relieve, borde y brillo superior
    if TH.get('shape') == 'notch':
        draw_button_notch(rect, active)
        return
    x, y, w, h = rect
    if active:
        base = tuple(min(255, int(c * 0.42)) for c in ACC)
        vbar((x, y, w, h), base, TH['panel'])
        pygame.draw.rect(screen, ACC, (x, y, w, h), 2, border_radius=RAD)
        pygame.draw.rect(screen, ACC, (x + 2, y + 4, 5, h - 8), border_radius=2)
    else:
        c1 = tuple(min(255, c + 14) for c in TH['card'])
        vbar((x, y, w, h), c1, TH['card'])
        pygame.draw.rect(screen, TH['border'], (x, y, w, h), 1, border_radius=RAD)
    # brillo sutil en el borde superior
    hl = tuple(min(255, c + (46 if active else 22)) for c in TH['card'])
    pygame.draw.rect(screen, hl, (x + 3, y + 1, w - 6, 1))

def draw_chip(x, y, key, text, font):
    # "Pastilla" de ayuda: [A] elegir
    kw = rtext(font, key, TH['bg'])
    tw = rtext(font, text, TH['dim'])
    bw = kw.get_width() + 16
    pygame.draw.rect(screen, ACC, (x, y, bw, 24), border_radius=(0 if ARCADE else 8))
    if ARCADE:
        pygame.draw.rect(screen, TH['acc2'], (x, y, bw, 24), 1)
    screen.blit(kw, (x + 8, y + 3))
    screen.blit(tw, (x + bw + 8, y + 3))
    return x + bw + 16 + tw.get_width()

def draw_header():
    # Cabecera de marca a todo lo ancho, con acento y contador
    hh = HEAD - 6
    pygame.draw.rect(screen, TH['panel'], (0, 0, W, hh))
    hbar((0, hh - 3, W, 3), ACC, TH.get('acc2', ACC))
    if ARCADE:
        for _o, _c in (((3, 3), TH['acc2']), ((0, 0), ACC)):
            screen.blit(f_tit.render('WPROTON', True, _c), (24 + _o[0], 16 + _o[1]))
        brand = f_tit.render('WPROTON', True, ACC)
    else:
        brand = f_tit.render('WPROTON', True, ACC)
        screen.blit(brand, (24, 16))
    bx = 24 + brand.get_width() + 16
    pygame.draw.rect(screen, TH['border'], (bx - 8, 14, 2, hh - 34))
    for i, tl in enumerate(TITLE_LINES):
        screen.blit(f_it.render(fit_label(tl, f_it, W - bx - 150), True, FG),
                    (bx, 16 + i * 26))
    if view:
        badge = f_sm.render('%d/%d' % (sel + 1, len(view)), True, TH['bg'])
        bwd = badge.get_width() + 18
        pygame.draw.rect(screen, ACC, (W - bwd - 20, 18, bwd, 24), border_radius=12)
        screen.blit(badge, (W - bwd - 11, 21))

def draw_side_panel():
    # Panel derecho: detalle de lo seleccionado
    if SIDE_W <= 0:
        return
    rect = (SIDE_X, LIST_Y, SIDE_W, LIST_H)
    draw_panel(rect)
    px, py = SIDE_X + 16, LIST_Y + 14
    screen.blit(f_sm.render(L('SELECCION', 'SELECTION'), True, TH.get('acc2', ACC)), (px, py))
    py += 26
    pygame.draw.rect(screen, TH['border'], (px, py, SIDE_W - 32, 1))
    py += 14
    if view:
        txt = items[view[sel]][1] if MODE != 'grid' else GITEMS[view[sel]][0]
        for ln in wrap_title(txt, f_it, SIDE_W - 34, 6):
            screen.blit(rtext(f_it, ln, FG), (px, py))
            py += 28
    else:
        screen.blit(f_it.render(L('(vacio)', '(empty)'), True, DIM), (px, py))
        py += 28
    if MODE == 'browse':
        py += 8
        screen.blit(f_sm.render(L('CARPETA', 'FOLDER'), True, TH.get('acc2', ACC)), (px, py))
        py += 22
        for ln in wrap_title(cur_path, f_sm, SIDE_W - 34, 4):
            screen.blit(rtext(f_sm, ln, DIM), (px, py))
            py += 20
    if FILTER:
        py += 10
        screen.blit(f_sm.render('BUSCANDO: %s' % FILTER, True, WARN), (px, py))

def draw_footer(chips):
    fy = H - 46
    pygame.draw.rect(screen, TH['panel'], (0, fy - 8, W, 54))
    hbar((0, fy - 10, W, 2), TH.get('acc2', ACC), ACC)
    x = 24
    for k, t in chips:
        x = draw_chip(x, fy + 6, k, t, f_sm)
        if x > W - 160:
            break

def draw_selection(rect):
    # clasico: barra plana | moderno: tarjeta | arcade: barra con marcador
    x, y, w, h = rect
    if TH.get('marker'):
        hbar((x, y, w, h), TH['sel_bg'], TH['bg'])
        pulse = 0.55 + 0.45 * abs(((time.time() * 1.6) % 2.0) - 1.0)
        col = tuple(int(c * pulse) for c in ACC)
        pygame.draw.rect(screen, col, (x, y, w, h), 2)
        pygame.draw.rect(screen, ACC, (x, y, 6, h))
        tri = [(x + 14, y + h // 2), (x + 4, y + 8), (x + 4, y + h - 8)]
        try:
            pygame.draw.polygon(screen, ACC, tri)
        except Exception:
            pass
        return
    if TH['pill']:
        hbar((x, y, w, h), TH['sel_bg'], TH['panel'])
        pygame.draw.rect(screen, ACC, (x, y, w, h), 1, border_radius=RAD)
        pygame.draw.rect(screen, ACC, (x + 2, y + 5, 5, h - 10), border_radius=3)
    else:
        pygame.draw.rect(screen, TH['sel_bg'], (x, y, w, h), border_radius=RAD)

_rcache = {}
def rtext(font, txt, color):
    # font.render cacheado: mismo texto+color+fuente -> misma superficie
    k = (id(font), txt, color)
    surf = _rcache.get(k)
    if surf is None:
        surf = font.render(txt, True, color)
        if len(_rcache) > 900:
            _rcache.clear()
        _rcache[k] = surf
    return surf

def wrap_title(text, font, maxw, maxlines=6):
    # Respeta los saltos de linea y ajusta al ancho; las rutas largas se
    # parten por caracteres (antes se cortaba el titulo y se perdia la pregunta)
    out = []
    for para in text.split('\n'):
        para = para.rstrip()
        if not para:
            out.append('')
            continue
        words, line = para.split(' '), ''
        for wd in words:
            probe = (line + ' ' + wd).strip()
            if rtext(font, probe, FG).get_width() <= maxw:
                line = probe
                continue
            if line:
                out.append(line)
                line = ''
            while rtext(font, wd, FG).get_width() > maxw:
                cut = len(wd)
                while cut > 1 and rtext(font, wd[:cut], FG).get_width() > maxw:
                    cut -= 1
                out.append(wd[:cut])
                wd = wd[cut:]
            line = wd
        if line:
            out.append(line)
    if len(out) > maxlines:
        out = out[:maxlines - 1] + ['\u2026']
    return out or ['']

TITLE_LINES = wrap_title(TITLE, f_tit if len(TITLE) < 60 else f_it, 912)
T_FONT = f_tit if len(TITLE) < 60 else f_it
T_LH = 34 if T_FONT is f_tit else 30
HEAD = 22 + len(TITLE_LINES) * T_LH + 14

ROW = TH['row']
PANEL_UI = TH.get('layout') in ('panel', 'arcade')
ARCADE = TH.get('layout') == 'arcade'
TOP = (HEAD + 30) if MODE == 'browse' else HEAD
LIST_X, LIST_Y, LIST_W, LIST_H = 16, TOP, 900, 480
SIDE_X, SIDE_W = 0, 0
VIS_FULL = (H - TOP - 60) // ROW
KB_H = 200
VIS_KB = (H - TOP - 60 - KB_H) // ROW

# --- teclado virtual (rejilla navegable con el dpad) ---
KB_ROWS = ['ABCDEFGHIJ',
           'KLMNOPQRST',
           'UVWXYZ0123',
           '456789 .-_']
KB_ACTIONS = ['BORRAR', 'LIMPIAR', 'LISTO'] if LANG != 'en' else ['DELETE', 'CLEAR', 'DONE']

def kb_cols(r):
    return len(KB_ACTIONS) if r == len(KB_ROWS) else len(KB_ROWS[r])

def shorten(p, n=82):
    return p if len(p) <= n else '\u2026' + p[-(n - 1):]

def write_out(text):
    with open(OUTFILE, 'w', encoding='utf-8') as f:
        f.write(text)

def safe_quit(code):
    # el texto ya esta escrito: pase lo que pase al cerrar, salimos con el
    # codigo correcto para que el llamador reciba el valor
    try:
        pygame.quit()
    except Exception:
        pass
    sys.exit(code)

def vis():
    return VIS_KB if kb_open else VIS_FULL

def move(d):
    global sel, scroll
    if not view:
        return
    sel = (sel + d) % len(view)
    if sel < scroll:
        scroll = sel
    if sel >= scroll + vis():
        scroll = sel - vis() + 1

def toggle():
    if MODE == 'check' and view:
        it = items[view[sel]]
        it[2] = not it[2]

# Rejilla adaptativa: en pantallas de portatil/consola (Steam Deck, Legion Go)
# menos columnas y caratulas MAS GRANDES; en monitores grandes, mas columnas.
# WP_GRID_COLS fuerza un numero concreto de columnas (0 = automatico).
GCOLS = 5
GCW, GCH = 176, 268
GIMG_W, GIMG_H = 150, 225
_imgcache = {}

def grid_metrics():
    # Tamano de caratula segun la pantalla. La regla que manda es la ALTURA:
    # la caratura debe caber en su fila con holgura (2 filas en monitores,
    # 1 fila grande en consolas portatiles). Antes solo se repartia el ancho
    # y en un monitor de sobremesa salian gigantes.
    global GCOLS, GCW, GCH, GIMG_W, GIMG_H
    avail_w = (LIST_W if PANEL_UI else (W - 40))
    avail_h = max(120, LIST_H - 16)
    forced = 0
    try:
        forced = int(os.environ.get('WP_GRID_COLS', '0'))
    except ValueError:
        forced = 0
    if forced > 0:
        rows = 1 if avail_h < 620 else 2
    elif avail_h < 620:          # Steam Deck, Legion Go, ventana baja
        rows = 1
    else:                        # monitor: dos filas de caratulas
        rows = 2
    # altura por fila (incluye el hueco del titulo): asi las filas CABEN
    h_max = int(avail_h / rows) - 48
    w_from_h = int(h_max / 1.5)
    # ancho maximo razonable por caratula segun el tamano de pantalla
    w_cap = 190 if W <= 1400 else (210 if W <= 1920 else 240)
    GIMG_W = max(120, min(w_from_h, w_cap))
    GIMG_H = int(GIMG_W * 1.5)
    GCW = GIMG_W + 26
    GCH = GIMG_H + 48
    if forced > 0:
        GCOLS = forced
        GCW = max(GIMG_W + 12, avail_w // max(1, forced))
    else:
        GCOLS = max(3, min(9, avail_w // GCW))
    _imgcache.clear()          # las imagenes se reescalan al nuevo tamano

def grid_rows_vis():
    area = H - TOP - 60 - (KB_H if kb_open else 0)
    return max(1, area // GCH)

def grid_move(dx, dy):
    global sel, scroll
    if not view:
        return
    n = len(view)
    if dy == 0:
        sel = (sel + dx) % n
    else:
        s2 = sel + dy * GCOLS
        if 0 <= s2 < n:
            sel = s2
        elif dy > 0 and (sel // GCOLS) < ((n - 1) // GCOLS):
            sel = n - 1          # bajar a una fila incompleta: ultimo juego
        # en los bordes verticales: quieto (el horizontal si envuelve)
    row = sel // GCOLS
    first = scroll // GCOLS
    vis_r = grid_rows_vis()
    if row < first:
        scroll = row * GCOLS
    elif row >= first + vis_r:
        scroll = (row - vis_r + 1) * GCOLS

apply_layout()

def row_segments(label, base_color):
    # "Prefijo: compartido" -> etiqueta en color de acento, valor en blanco.
    # "MangoHud: ON" -> ON en verde, OFF apagado.
    if not TH.get('labelcolor') or ':' not in label:
        return [(label, base_color)]
    k, _, v = label.partition(':')
    # "arcade - synthwave: ..." no es etiqueta+valor, es una descripcion
    if ' - ' in k or len(k) > 36:
        return [(label, base_color)]
    segs = [(k + ':', TH.get('acc2', ACC))]
    v = v.strip()
    if v:
        low = v.lower()
        if low in ('on', 'si'):
            segs.append((' ' + v, TH.get('ok', ACC)))
        elif low in ('off', 'no'):
            segs.append((' ' + v, DIM))
        else:
            segs.append((' ' + v, base_color))
    return segs

def draw_segments(segs, font, x, y, maxw, active):
    # Pinta varios trozos de texto con colores distintos, con marquesina si
    # el conjunto no cabe (solo en la fila seleccionada) y recorte estricto.
    surfs = [(rtext(font, t, c), t, c) for t, c in segs if t]
    total = sum(sf.get_width() for sf, _, _ in surfs)
    if total <= maxw:
        cx = x
        for sf, _, _ in surfs:
            screen.blit(sf, (cx, y))
            cx += sf.get_width()
        return
    if not active:
        cx, rest = x, maxw
        for sf, t, c in surfs:
            wsf = sf.get_width()
            if wsf <= rest:
                screen.blit(sf, (cx, y)); cx += wsf; rest -= wsf
            else:
                screen.blit(rtext(font, fit_label(t, font, rest), c), (cx, y))
                break
        return
    over = total - maxw
    period = 2.2 + over / 70.0
    tt = (time.time() % (period * 2)) / period
    f = tt if tt <= 1.0 else 2.0 - tt
    f = max(0.0, min(1.0, (f - 0.14) / 0.72))
    old = None
    try:
        old = screen.get_clip()
        screen.set_clip((x, y - 2, maxw, ROW))
    except Exception:
        pass
    cx = x - int(over * f)
    for sf, _, _ in surfs:
        screen.blit(sf, (cx, y))
        cx += sf.get_width()
    try:
        screen.set_clip(old)
    except Exception:
        pass

def draw_row_text(text, font, color, x, y, maxw, active):
    # Si el texto no cabe: en la fila seleccionada se desplaza (marquesina),
    # en las demas se recorta. Antes se salia de la tarjeta e invadia el panel.
    surf = rtext(font, text, color)
    w = surf.get_width()
    if w <= maxw:
        screen.blit(surf, (x, y))
        return
    if not active:
        screen.blit(rtext(font, fit_label(text, font, maxw), color), (x, y))
        return
    over = w - maxw
    period = 2.2 + over / 70.0          # cuanto mas larga, mas despacio
    tt = (time.time() % (period * 2)) / period
    f = tt if tt <= 1.0 else 2.0 - tt   # ida y vuelta
    f = max(0.0, min(1.0, (f - 0.14) / 0.72))   # pausa en los extremos
    old = None
    try:
        old = screen.get_clip()
        screen.set_clip((x, y - 2, maxw, ROW))
    except Exception:
        pass
    screen.blit(surf, (x - int(over * f), y))
    try:
        screen.set_clip(old)
    except Exception:
        pass

_fitcache = {}
def fit_label(txt, font, maxw):
    # Recorta midiendo el ancho renderizado (por caracteres se solapaban)
    k = (txt, maxw)
    if k in _fitcache:
        return _fitcache[k]
    if rtext(font, txt, FG).get_width() <= maxw:
        _fitcache[k] = txt
        return txt
    t = txt
    while t and rtext(font, t + '\u2026', FG).get_width() > maxw:
        t = t[:-1]
    t = (t.rstrip() + '\u2026') if t else '\u2026'
    _fitcache[k] = t
    return t

def grid_img(path):
    if not path or not os.path.isfile(path):
        return None
    if path not in _imgcache:
        try:
            img = pygame.image.load(path)
            _imgcache[path] = pygame.transform.smoothscale(img, (GIMG_W, GIMG_H))
        except Exception:
            _imgcache[path] = None
    return _imgcache[path]

def draw_grid():
    gx0 = LIST_X + max(0, (LIST_W - GCOLS * GCW) // 2) + (GCW - GIMG_W) // 2
    vis_r = grid_rows_vis()
    first = scroll
    for i in range(first, min(first + vis_r * GCOLS, len(view))):
        col = (i - first) % GCOLS
        rowi = (i - first) // GCOLS
        x = gx0 + col * GCW
        y = LIST_Y + 8 + rowi * GCH
        _cell = (x - 6, y - 6, GIMG_W + 12, GCH - 18)
        if TH['panel'] is not None:
            pygame.draw.rect(screen, TH['card'], _cell, border_radius=RAD)
        if i == sel and not kb_open:
            draw_selection(_cell)
        title, ipath, _pay = GITEMS[view[i]][:3]
        is_fav = len(GITEMS[view[i]]) > 3 and GITEMS[view[i]][3] == '1' 
        img = grid_img(ipath)
        if img:
            screen.blit(img, (x, y))
        else:
            pygame.draw.rect(screen, TH['card'], (x, y, GIMG_W, GIMG_H), border_radius=RAD)
            pygame.draw.rect(screen, TH['border'], (x, y, GIMG_W, GIMG_H), 1, border_radius=RAD)
            line, yy = '', y + 16
            for wd in title.split() + ['']:
                t2 = (line + ' ' + wd).strip()
                if wd and f_sm.render(t2, True, FG).get_width() < GIMG_W - 12:
                    line = t2
                    continue
                if line and yy < y + GIMG_H - 20:
                    screen.blit(f_sm.render(fit_label(line, f_sm, GIMG_W - 12), True, FG), (x + 6, yy))
                    yy += 22
                line = wd
        if is_fav:
            # cinta diagonal en la esquina superior derecha de la caratula
            rb = max(26, GIMG_W // 5)
            try:
                pygame.draw.polygon(screen, TH.get('acc2', ACC),
                                    [(x + GIMG_W - rb, y), (x + GIMG_W, y),
                                     (x + GIMG_W, y + rb)])
                pygame.draw.line(screen, FG, (x + GIMG_W - rb, y),
                                 (x + GIMG_W, y + rb), 2)
            except Exception:
                pygame.draw.rect(screen, TH.get('acc2', ACC),
                                 (x + GIMG_W - rb, y, rb, 8))
        draw_row_text(title, f_sm, FG if i == sel else DIM,
                      x, y + GIMG_H + 8, GIMG_W, i == sel)

def action_x():
    # X sobre un juego -> devolver "WPACT:CONFIG|<lo elegido>"
    global running, done
    if not view:
        return
    if MODE == 'grid':
        payload = GITEMS[view[sel]][2]
    else:
        payload = items[view[sel]][1]
    write_out('WPACT:CONFIG|' + payload)
    running = False; done = True

def on_enter():
    global running, done
    if MODE == 'grid':
        if not view:
            return
        write_out(GITEMS[view[sel]][2])
        running = False; done = True
        return
    if not view:
        return
    kind, txt, _ = items[view[sel]]
    if MODE == 'check':
        write_out('|'.join(t for k, t, on in items if on))
        running = False; done = True
    elif MODE == 'browse':
        if kind == K_HDR:
            write_out(cur_path); running = False; done = True
        elif kind == K_UP2:
            load_dir(os.path.dirname(cur_path))
        elif kind == K_CANCEL:
            running = False
        elif kind == K_DIR:
            load_dir(os.path.join(cur_path, txt[:-1]))
        else:
            write_out(os.path.join(cur_path, txt)); running = False; done = True
    else:
        write_out(txt); running = False; done = True

def on_escape():
    global running, FILTER
    if FILTER:
        FILTER = ''
        _refilter()
        return
    if MODE == 'browse':
        parent = os.path.dirname(cur_path)
        if parent != cur_path:
            load_dir(parent)
    else:
        running = False

def _refilter():
    if MODE == 'grid':
        grid_apply_filter()
    else:
        apply_filter()

def filter_add(ch):
    global FILTER
    FILTER += ch
    _refilter()

def filter_back():
    global FILTER
    if FILTER:
        FILTER = FILTER[:-1]
        _refilter()

def kb_press():
    global kb_open
    if kb_r == len(KB_ROWS):
        act = KB_ACTIONS[kb_c]
        if act in ('BORRAR', 'DELETE'):
            filter_back()
        elif act in ('LIMPIAR', 'CLEAR'):
            global FILTER
            FILTER = ''
            _refilter()
        else:                       # LISTO
            kb_open = False
    else:
        filter_add(KB_ROWS[kb_r][kb_c].lower())

if MODE == 'canvas':
    # Fondo persistente para el MODO JUEGO de SteamOS.
    #
    # El problema: cada menu abria y cerraba su ventana. Al salir de un juego,
    # gamescope se quedaba sin ninguna superficie nuestra y no sabia a quien
    # devolver el foco: el menu siguiente nacia detras y parecia que WProton
    # no volvia. Con esta ventana SIEMPRE viva, el compositor siempre tiene a
    # donde volver, y los menus se dibujan encima de ella.
    #
    # Se cierra sola cuando el fichero de estado dice STOP (o desaparece).
    clockC = pygame.time.Clock()
    status = ''
    misses = 0
    while True:
        for ev in pygame.event.get():
            if ev.type == pygame.QUIT:
                safe_quit(0)
        try:
            with open(ARG4, encoding='utf-8') as fh:
                status = fh.readline().strip()
            misses = 0
        except Exception:
            misses += 1
            if misses > 40:            # el fichero ya no esta: nos vamos
                safe_quit(0)
        if status.startswith('STOP'):
            safe_quit(0)
        screen.blit(BGSURF, (0, 0))
        if PANEL_UI:
            draw_header()
        # marca centrada
        big = pygame.font.Font(None, max(48, W // 14))
        brand = big.render('WPROTON', True, ACC)
        screen.blit(brand, ((W - brand.get_width()) // 2, H // 2 - 60))
        if status:
            for _i, _ln in enumerate(wrap_title(status, f_it, W - 120, 3)):
                sf = rtext(f_it, _ln, FG)
                screen.blit(sf, ((W - sf.get_width()) // 2, H // 2 + 10 + _i * 30))
        # punto animado, para que se vea que sigue vivo
        _p = int(time.time() * 2) % 4
        dots = rtext(f_sm, '.' * _p, DIM)
        screen.blit(dots, ((W - dots.get_width()) // 2, H // 2 + 110))
        if SCANSURF is not None:
            screen.blit(SCANSURF, (0, 0))
        pygame.display.flip()
        clockC.tick(15)          # muy poco consumo: no compite con el juego

if MODE == 'progress':
    # Ventana de espera: lee "pct|texto" del fichero de estado hasta DONE
    bar_pct, bar_txt = 0, L('Preparando...', 'Preparing...')
    clock2 = pygame.time.Clock()
    while True:
        for ev in pygame.event.get():
            if ev.type == pygame.QUIT:
                pygame.quit(); sys.exit(0)
        try:
            with open(ARG4, encoding='utf-8') as fh:
                raw = fh.readline().rstrip('\n')
            if raw.startswith('DONE'):
                break
            p, _, t = raw.partition('|')
            bar_pct = max(0, min(100, int(p or 0)))
            bar_txt = t or bar_txt
        except Exception:
            pass
        screen.blit(BGSURF, (0, 0))
        for _i, _tl in enumerate(TITLE_LINES):
            screen.blit(rtext(T_FONT, _tl, FG), (24, 22 + _i * T_LH))
        pygame.draw.line(screen, (60, 64, 74), (24, HEAD - 8), (W - 24, HEAD - 8), 1)
        screen.blit(f_it.render(fit_label(bar_txt, f_it, W - 60), True, FG), (30, HEAD + 24))
        bx, by, bw, bh = 30, HEAD + 74, W - 60, 26
        pygame.draw.rect(screen, TH['card'], (bx, by, bw, bh), border_radius=RAD)
        if TH['panel'] is not None:
            pygame.draw.rect(screen, TH['border'], (bx, by, bw, bh), 1, border_radius=RAD)
        if bar_pct > 0:
            pygame.draw.rect(screen, ACC if TH['glow'] else HIBG,
                             (bx, by, int(bw * bar_pct / 100.0), bh), border_radius=RAD)
        else:
            t0 = (time.time() * 220) % (bw * 2)
            xx = t0 if t0 < bw else (bw * 2 - t0)
            pygame.draw.rect(screen, ACC if TH['glow'] else HIBG,
                             (bx + max(0, min(bw - 140, xx - 70)), by, 140, bh), border_radius=RAD)
        if bar_pct:
            screen.blit(f_sm.render('%d%%' % bar_pct, True, DIM), (bx, by + bh + 8))
        screen.blit(f_sm.render(L('Espera, esto puede tardar...', 'Please wait, this may take a while...'), True, DIM), (24, H - 40))
        if SCANSURF is not None:
            screen.blit(SCANSURF, (0, 0))
        pygame.display.flip()
        clock2.tick(30)
    pygame.quit()
    sys.exit(0)

if MODE == 'text':
    # Editor de una linea con teclado en pantalla: para argumentos, DLL
    # overrides, notas... Se maneja con el mando (o el teclado real).
    TXT = ARG4 if len(sys.argv) > 4 else ''
    TROWS = ['1234567890-=',
             'qwertyuiop[]',
             'asdfghjkl;\'',
             'zxcvbnm,./\\',
             ' _:"|+*@#$%&']
    TACT = [L('MAYUS', 'SHIFT'), L('BORRAR', 'DELETE'),
            L('LIMPIAR', 'CLEAR'), L('ACEPTAR', 'ACCEPT'), L('CANCELAR', 'CANCEL')]
    tr_r, tr_c, shift = 0, 0, False
    clockT = pygame.time.Clock()
    t_open2 = time.time()

    def tcols(r):
        return len(TACT) if r == len(TROWS) else len(TROWS[r])

    def t_press():
        global TXT, shift, tr_r, tr_c
        if tr_r == len(TROWS):
            act = TACT[tr_c]
            if act in ('MAYUS', 'SHIFT'):
                shift = not shift
            elif act in ('BORRAR', 'DELETE'):
                TXT = TXT[:-1]
            elif act in ('LIMPIAR', 'CLEAR'):
                TXT = ''
            elif act in ('ACEPTAR', 'ACCEPT'):
                return 'ok'
            else:
                return 'cancel'
        else:
            ch = TROWS[tr_r][tr_c]
            TXT += ch.upper() if shift else ch
        return None

    while True:
        for ev in pygame.event.get():
            if ev.type == pygame.QUIT:
                safe_quit(1)
            if ev.type != pygame.KEYDOWN:
                continue
            if time.time() - t_open2 < 0.35:
                continue
            if ev.key == pygame.K_UP:
                tr_r = (tr_r - 1) % (len(TROWS) + 1); tr_c = min(tr_c, tcols(tr_r) - 1)
            elif ev.key == pygame.K_DOWN:
                tr_r = (tr_r + 1) % (len(TROWS) + 1); tr_c = min(tr_c, tcols(tr_r) - 1)
            elif ev.key == pygame.K_LEFT:
                tr_c = (tr_c - 1) % tcols(tr_r)
            elif ev.key == pygame.K_RIGHT:
                tr_c = (tr_c + 1) % tcols(tr_r)
            elif ev.key in (pygame.K_RETURN, pygame.K_KP_ENTER):
                r = t_press()
                if r == 'ok':
                    write_out(TXT); safe_quit(0)
                if r == 'cancel':
                    safe_quit(1)
            elif ev.key == pygame.K_SPACE:      # X del mando: borrar
                TXT = TXT[:-1]
            elif ev.key == pygame.K_BACKSPACE:
                TXT = TXT[:-1]
            elif ev.key == pygame.K_TAB:        # Y: aceptar rapido
                write_out(TXT); safe_quit(0)
            elif ev.key == pygame.K_ESCAPE:
                safe_quit(1)
            else:
                ch = getattr(ev, 'unicode', '')
                if ch and ch.isprintable():
                    TXT += ch

        screen.blit(BGSURF, (0, 0))
        if PANEL_UI:
            draw_header()
        else:
            for _i, _tl in enumerate(TITLE_LINES):
                screen.blit(rtext(T_FONT, _tl, FG), (24, 22 + _i * T_LH))
            pygame.draw.line(screen, TH['border'], (24, HEAD - 8), (W - 24, HEAD - 8), 1)
        # caja de texto
        bx, by, bw, bh = 30, HEAD + 20, W - 60, 54
        pygame.draw.rect(screen, TH['card'], (bx, by, bw, bh), border_radius=RAD)
        pygame.draw.rect(screen, ACC, (bx, by, bw, bh), 2, border_radius=RAD)
        cursor = '_' if int(time.time() * 2) % 2 == 0 else ' '
        shown = TXT
        while f_it.render(shown + cursor, True, FG).get_width() > bw - 24 and shown:
            shown = shown[1:]
        screen.blit(f_it.render(shown + cursor, True, FG), (bx + 12, by + 14))
        # teclado
        ky0 = by + bh + 26
        cw = (W - 80) // 12
        for r, row in enumerate(TROWS):
            for c, ch in enumerate(row):
                x = 40 + c * cw
                y = ky0 + r * 44
                if r == tr_r and c == tr_c:
                    draw_selection((x - 8, y - 6, cw - 6, 38))
                lab = ch.upper() if shift else ch
                if ch == ' ':
                    lab = L('ESP', 'SPC')
                screen.blit(f_it.render(lab, True, FG), (x, y))
        aw = (W - 80) // len(TACT)
        for c, act in enumerate(TACT):
            x = 40 + c * aw
            y = ky0 + len(TROWS) * 44
            if tr_r == len(TROWS) and c == tr_c:
                draw_selection((x - 8, y - 6, aw - 14, 38))
            col = ACC if act in ('ACEPTAR', 'ACCEPT') else (
                  WARN if act in ('MAYUS', 'SHIFT') and shift else FG)
            screen.blit(f_it.render(act, True, col), (x, y))
        hint2 = L('Dpad: moverse   A: pulsar   X: borrar   Y: aceptar   B: cancelar',
                  'Dpad: move   A: press   X: delete   Y: accept   B: cancel')
        if PANEL_UI:
            draw_footer([('A', L('pulsar', 'press')), ('X', L('borrar', 'delete')),
                         ('Y', L('aceptar', 'accept')), ('B', L('cancelar', 'cancel'))])
        else:
            screen.blit(f_sm.render(hint2, True, DIM), (24, H - 40))
        if SCANSURF is not None:
            screen.blit(SCANSURF, (0, 0))
        pygame.display.flip()
        clockT.tick(30)

running, done = True, False
GRACE = 0.35
t_open = time.time()
def ready():
    return time.time() - t_open >= GRACE

_last_key = [None, 0.0]
DEBOUNCE = 0.08
while running:
    for ev in pygame.event.get():
        if ev.type == pygame.QUIT:
            running = False
        elif ev.type == pygame.KEYDOWN:
            t_now = time.time()
            if ev.key == _last_key[0] and (t_now - _last_key[1]) < DEBOUNCE:
                continue
            _last_key[0], _last_key[1] = ev.key, t_now
            if ev.key == pygame.K_F11:
                toggle_fullscreen()
                continue
            if kb_open:
                # --- navegacion del teclado virtual ---
                if ev.key == pygame.K_UP:
                    kb_r = (kb_r - 1) % (len(KB_ROWS) + 1)
                    kb_c = min(kb_c, kb_cols(kb_r) - 1)
                elif ev.key == pygame.K_DOWN:
                    kb_r = (kb_r + 1) % (len(KB_ROWS) + 1)
                    kb_c = min(kb_c, kb_cols(kb_r) - 1)
                elif ev.key == pygame.K_LEFT:
                    kb_c = (kb_c - 1) % kb_cols(kb_r)
                elif ev.key == pygame.K_RIGHT:
                    kb_c = (kb_c + 1) % kb_cols(kb_r)
                elif ev.key in (pygame.K_RETURN, pygame.K_KP_ENTER):
                    if ready(): kb_press()
                elif ev.key == pygame.K_SPACE:
                    if ready(): filter_back()          # X = borrar
                elif ev.key in (pygame.K_ESCAPE, pygame.K_TAB):
                    if ready(): kb_open = False        # B / Y = cerrar
                elif ev.key == pygame.K_BACKSPACE:
                    filter_back()
                else:
                    ch = getattr(ev, 'unicode', '')
                    if ch and ch.isprintable():
                        filter_add(ch)
            else:
                if ev.key == pygame.K_ESCAPE:
                    if ready(): on_escape()
                elif ev.key in (pygame.K_RETURN, pygame.K_KP_ENTER):
                    if ready(): on_enter()
                elif ev.key == pygame.K_UP:
                    if MODE == 'grid': grid_move(0, -1)
                    else: move(-1)
                elif ev.key == pygame.K_DOWN:
                    if MODE == 'grid': grid_move(0, 1)
                    else: move(1)
                elif ev.key == pygame.K_LEFT:
                    if MODE == 'grid': grid_move(-1, 0)
                elif ev.key == pygame.K_RIGHT:
                    if MODE == 'grid': grid_move(1, 0)
                elif ev.key == pygame.K_TAB:
                    # Y del mando (o Tab): abrir teclado de busqueda
                    if ready() and MODE != 'check':
                        kb_open = True
                        kb_r, kb_c = 0, 0
                        scroll = max(0, min(scroll, max(0, len(view) - VIS_KB)))
                elif ev.key == pygame.K_BACKSPACE:
                    filter_back()
                elif ev.key == pygame.K_SPACE:
                    if ready():
                        if MODE == 'check':
                            toggle()
                        elif ACTION_X and MODE in ('list', 'grid'):
                            action_x()
                        else:
                            on_enter()
                else:
                    # TYPE-AHEAD con teclado real: filtra al escribir
                    if MODE != 'check':
                        ch = getattr(ev, 'unicode', '')
                        if ch and ch.isprintable():
                            filter_add(ch)

    screen.blit(BGSURF, (0, 0))
    if PANEL_UI:
        draw_header()
        draw_panel((LIST_X - 6, LIST_Y, LIST_W + 12, LIST_H))
        draw_side_panel()
    else:
        for _i, _tl in enumerate(TITLE_LINES):
            screen.blit(rtext(T_FONT, _tl, FG), (24, 22 + _i * T_LH))
        if MODE == 'browse':
            screen.blit(f_sm.render(shorten(cur_path), True, DIM), (24, HEAD - 8))
            _ry = HEAD + 20
        else:
            _ry = HEAD - 8
        pygame.draw.line(screen, TH['border'], (24, _ry), (W - 24, _ry), 1)

    if MODE == 'grid':
        draw_grid()
    for i in ([] if MODE == 'grid' else range(scroll, min(scroll + vis(), len(view)))):
        y = LIST_Y + 8 + (i - scroll) * ROW
        _rect = (LIST_X, y - 4, LIST_W, ROW - 6)
        if TH.get('btn'):
            draw_button(_rect, i == sel and not kb_open)
            if i == sel and not kb_open and TH.get('marker'):
                try:
                    pygame.draw.polygon(screen, ACC,
                        [(LIST_X + 20, y + ROW // 2 - 4), (LIST_X + 10, y + 2),
                         (LIST_X + 10, y + ROW - 14)])
                except Exception:
                    pass
        else:
            if PANEL_UI and i != sel:
                pygame.draw.rect(screen, TH['card'], _rect, border_radius=RAD)
            if i == sel and not kb_open:
                draw_selection(_rect)
        kind, txt, on = items[view[i]]
        if MODE == 'check':
            label = ('[x] ' if on else '[  ] ') + txt
            color = ACC if on else FG
        elif kind == K_DIR:
            label, color = txt, DIRC
        elif kind in HEADER_KINDS:
            label, color = txt, (ACC if kind == K_HDR else DIM)
        else:
            label, color = txt, FG
        _tx = LIST_X + (18 if PANEL_UI else 14)
        if TH.get('numbered'):
            _tx += 46
            screen.blit(f_sm.render('%02d' % (i + 1), True, ACC if i == sel else TH['border']),
                        (LIST_X + 28, y + 12))
        _ty = y + (6 if PANEL_UI else 0)
        _tw = LIST_X + LIST_W - _tx - 18     # ancho util hasta el borde
        if TH.get('shadow'):
            draw_row_text(label, f_it, (0, 0, 0), _tx + 2, _ty + 2, _tw, i == sel)
        if kind in HEADER_KINDS or MODE == 'check':
            draw_row_text(label, f_it, color, _tx, _ty, _tw, i == sel)
        else:
            draw_segments(row_segments(label, color), f_it, _tx, _ty, _tw, i == sel)
    if not view and FILTER:
        screen.blit(f_it.render("(sin coincidencias para '%s')" % FILTER, True, WARN),
                    (LIST_X + 14, LIST_Y + 14))

    # Barra lateral: avisa de que hay mas opciones de las que caben en pantalla
    _total = len(view)
    _vis = (grid_rows_vis() * GCOLS) if MODE == 'grid' else vis()
    if _total > _vis:
        _tr_x = (LIST_X + LIST_W + 2) if PANEL_UI else (W - 14)
        _tr_y = LIST_Y + 8
        _tr_h = LIST_H - 16
        pygame.draw.rect(screen, TH['card'], (_tr_x, _tr_y, 6, _tr_h), border_radius=3)
        _kh = max(28, int(_tr_h * _vis / float(_total)))
        _maxoff = max(1, _total - _vis)
        _ky = _tr_y + int((_tr_h - _kh) * min(1.0, scroll / float(_maxoff)))
        pygame.draw.rect(screen, ACC if TH['glow'] else (120, 130, 150),
                         (_tr_x, _ky, 6, _kh), border_radius=3)
    if view and not PANEL_UI:
        pos = f_sm.render('%d/%d' % (sel + 1, len(view)), True, DIM)
        screen.blit(pos, (W - 24 - pos.get_width(), max(4, HEAD - 30)))
    if (FILTER or kb_open) and not PANEL_UI:
        ft = f_sm.render('Buscar: %s_' % FILTER, True, WARN)
        screen.blit(ft, (W - 24 - ft.get_width(), max(24, HEAD - 30)))

    if kb_open:
        ky0 = H - KB_H - 44
        pygame.draw.rect(screen, KBBG, (12, ky0 - 8, W - 24, KB_H + 8), border_radius=RAD)
        if TH['panel'] is not None:
            pygame.draw.rect(screen, TH['border'], (12, ky0 - 8, W - 24, KB_H + 8), 1, border_radius=RAD)
        cw = (W - 60) // 10
        for r, row in enumerate(KB_ROWS):
            for c, ch in enumerate(row):
                x = 30 + c * cw
                y = ky0 + r * 36
                if r == kb_r and c == kb_c:
                    draw_selection((x - 6, y - 4, cw - 6, 32))
                lab = 'ESP' if ch == ' ' else ch
                screen.blit(f_kb.render(lab, True, FG), (x, y))
        aw = (W - 60) // len(KB_ACTIONS)
        for c, act in enumerate(KB_ACTIONS):
            x = 30 + c * aw
            y = ky0 + len(KB_ROWS) * 36
            if kb_r == len(KB_ROWS) and c == kb_c:
                draw_selection((x - 6, y - 4, aw - 12, 32))
            screen.blit(f_kb.render(act, True, ACC if act == 'LISTO' else FG), (x, y))

    if kb_open:
        hint = 'Dpad: moverse   A: pulsar   X: borrar   B/Y: cerrar teclado'
    elif MODE == 'check':
        hint = 'X/Espacio: marcar   A/Enter: aceptar   B/Esc: cancelar'
    elif MODE == 'browse':
        hint = 'A: entrar/elegir   B: subir   Y: buscar   (o escribe para filtrar)'
    elif MODE == 'grid':
        hint = ('A: jugar   X: configurar   B: volver   Y: buscar' if ACTION_X
                else 'Dpad: moverse   A: jugar   B: volver   Y: buscar   Select+A/F11: pantalla')
    else:
        hint = 'A: elegir   B: volver   Y: buscar   Select+A/F11: pantalla completa'
    if PANEL_UI:
        if kb_open:
            _chips = [('Dpad', L('moverse', 'move')), ('A', L('pulsar', 'press')),
                      ('X', L('borrar', 'delete')), ('B/Y', L('cerrar', 'close'))]
        elif MODE == 'check':
            _chips = [('X', L('marcar', 'toggle')), ('A', L('aceptar', 'accept')),
                      ('B', L('cancelar', 'cancel'))]
        elif MODE == 'browse':
            _chips = [('A', L('entrar', 'enter')), ('B', L('subir', 'up')),
                      ('Y', L('buscar', 'search')), ('Sel+A', L('pantalla', 'screen'))]
        elif MODE == 'grid':
            _chips = [('A', L('jugar', 'play')), ('X', L('configurar', 'configure')),
                      ('B', L('volver', 'back')), ('Y', L('buscar', 'search'))] if ACTION_X else \
                     [('Dpad', L('moverse', 'move')), ('A', L('jugar', 'play')),
                      ('B', L('volver', 'back')), ('Y', L('buscar', 'search'))]
        else:
            _chips = [('A', L('jugar', 'play')), ('X', L('configurar', 'configure')),
                      ('B', L('volver', 'back')), ('Y', L('buscar', 'search'))] if ACTION_X else \
                     [('A', L('elegir', 'choose')), ('B', L('volver', 'back')),
                      ('Y', L('buscar', 'search')), ('Sel+A', L('pantalla', 'screen'))]
        draw_footer(_chips)
    else:
        screen.blit(f_sm.render(hint, True, DIM), (24, H - 40))
    if SCANSURF is not None:
        screen.blit(SCANSURF, (0, 0))
    pygame.display.flip()
    clock.tick(60)

pygame.quit()
sys.exit(0 if done else 1)
PGEOF
}

# ----------------------------------------------------------------------------
# 4c. SELECTOR GTK PROPIO (soluciona el foco: zenity deja el foco en los
#     botones y las flechas no mueven la lista; aqui forzamos grab_focus()
#     en la lista y preseleccionamos la primera fila -> el mando navega SI o SI)
# ----------------------------------------------------------------------------
MENU_GTK_PY="$RUNTIME_DIR/menu_gtk.py"
HAS_GTK=-1   # -1 = sin comprobar

gtk_available() {
    if [ "$HAS_GTK" = -1 ]; then
        if [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ] && \
           "$SYS_PY" -c 'import gi; gi.require_version("Gtk","3.0"); from gi.repository import Gtk' >/dev/null 2>&1; then
            HAS_GTK=1
        else
            HAS_GTK=0
            log "PyGObject/GTK no disponible: menus via zenity (flechas pueden requerir Tab)" WARN
        fi
    fi
    [ "$HAS_GTK" = 1 ]
}

write_menu_gtk() {
    cat > "$MENU_GTK_PY" <<'GTKEOF'
#!/usr/bin/env python3
# Selector de WProton con foco garantizado en la lista (navegable con mando)
# Uso: menu_gtk.py <list|check> <titulo> <fichero_salida> <fichero_opciones>
#   list : una opcion por linea; al elegir se escribe en salida
#   check: lineas "0|Texto" / "1|Texto"; Espacio (X) marca, Enter (A) acepta
import sys
import gi
gi.require_version('Gtk', '3.0')
from gi.repository import Gtk, Gdk

MODE, TITLE, OUTFILE, OPTFILE = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
with open(OPTFILE, encoding='utf-8') as f:
    LINES = [l.rstrip('\n') for l in f if l.strip()]

class Win(Gtk.Window):
    def __init__(self):
        super().__init__(title='WProton')
        self.set_default_size(660, 640)
        self.set_position(Gtk.WindowPosition.CENTER)
        self.set_keep_above(True)
        self.set_type_hint(Gdk.WindowTypeHint.DIALOG)
        v = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        v.set_margin_top(10); v.set_margin_bottom(10)
        v.set_margin_start(10); v.set_margin_end(10)
        lbl = Gtk.Label(label=TITLE); lbl.set_xalign(0); lbl.set_line_wrap(True)
        v.pack_start(lbl, False, False, 0)

        if MODE == 'check':
            self.store = Gtk.ListStore(bool, str)
            for l in LINES:
                on, _, txt = l.partition('|')
                self.store.append([on == '1', txt])
        else:
            self.store = Gtk.ListStore(str)
            for l in LINES:
                self.store.append([l])

        self.tv = Gtk.TreeView(model=self.store)
        self.tv.set_headers_visible(False)
        if MODE == 'check':
            tog = Gtk.CellRendererToggle()
            tog.connect('toggled', self.on_toggled)
            self.tv.append_column(Gtk.TreeViewColumn('', tog, active=0))
            self.tv.append_column(Gtk.TreeViewColumn('', Gtk.CellRendererText(), text=1))
        else:
            self.tv.append_column(Gtk.TreeViewColumn('', Gtk.CellRendererText(), text=0))
        self.tv.connect('row-activated', self.on_activate)
        sw = Gtk.ScrolledWindow(); sw.set_vexpand(True); sw.add(self.tv)
        v.pack_start(sw, True, True, 0)

        hint = 'A/Enter: elegir   B/Esc: volver' if MODE == 'list' \
               else 'X/Espacio: marcar   A/Enter: aceptar   B/Esc: cancelar'
        h = Gtk.Label(label=hint); h.set_xalign(0)
        h.get_style_context().add_class('dim-label')
        v.pack_start(h, False, False, 0)

        self.add(v)
        self.connect('key-press-event', self.on_key)
        self.connect('destroy', Gtk.main_quit)
        self.show_all()
        # === LA CLAVE: primera fila seleccionada y foco en la lista ===
        self.tv.set_cursor(Gtk.TreePath.new_first())
        self.tv.grab_focus()

    def cursor_row(self):
        path, _ = self.tv.get_cursor()
        return None if path is None else self.store[path]

    def on_toggled(self, cell, path):
        self.store[path][0] = not self.store[path][0]

    def on_activate(self, tv, path, col):
        if MODE == 'check':
            self.accept()
        else:
            with open(OUTFILE, 'w', encoding='utf-8') as f:
                f.write(self.store[path][0])
            Gtk.main_quit()

    def accept(self):
        with open(OUTFILE, 'w', encoding='utf-8') as f:
            f.write('|'.join(r[1] for r in self.store if r[0]))
        Gtk.main_quit()

    def on_key(self, w, ev):
        if ev.keyval == Gdk.KEY_Escape:
            Gtk.main_quit()
            return True
        if MODE == 'check':
            if ev.keyval == Gdk.KEY_space:
                row = self.cursor_row()
                if row is not None:
                    row[0] = not row[0]
                return True
            if ev.keyval in (Gdk.KEY_Return, Gdk.KEY_KP_Enter):
                self.accept()
                return True
        return False

Win()
Gtk.main()
GTKEOF
}

# ----------------------------------------------------------------------------
# 5. HELPERS DE MENU (seleccion via fichero temporal, nunca $( ) crudo con GUIs)
# ----------------------------------------------------------------------------
menu() {
    # $1 = titulo; resto = opciones (una por argumento). Imprime la elegida.
    # IMPORTANTE: se traduce solo para MOSTRAR; lo que se devuelve es siempre
    # la cadena original en castellano, para que los case de los llamadores
    # sigan funcionando igual en cualquier idioma.
    local title="$1"; shift
    [ $# -eq 0 ] && return 1
    local WP_ORIG=() WP_SHOW=() _o
    if [ "${LANGUAGE:-es}" != "es" ]; then
        for _o in "$@"; do
            WP_ORIG+=("$_o")
            WP_SHOW+=("$(wp_tr "$_o")")
        done
        title="$(wp_tr "$title")"
        set -- "${WP_SHOW[@]}"
    fi
    local tmpsel; tmpsel="$(mktemp)"
    if pygame_available; then
        # pygame lee el mando NATIVAMENTE: el puente uinput debe estar PARADO
        # (si no, cada pulsacion llega doble/triple: hat SDL + tecla sintetica)
        pad_bridge_stop
        write_menu_pygame
        local tmpopt; tmpopt="$(mktemp)"
        printf '%s\n' "$@" > "$tmpopt"
        PYGAME_HIDE_SUPPORT_PROMPT=1 SDL_JOYSTICK_ALLOW_BACKGROUND_EVENTS=1 \
            env -u LD_PRELOAD "$PY_BIN" "$MENU_PYGAME_PY" list "$title" "$tmpsel" "$tmpopt" >> "$LOG_FILE" 2>&1
        local hrc=$?
        # rc>=2 = el helper no pudo abrirse (video ocupado justo despues de
        # cerrar un juego, por ejemplo). NO es una cancelacion del usuario:
        # se reintenta y, si insiste, se cae a los menus de respaldo.
        if [ "$hrc" -ge 2 ]; then
            say "AVISO: el menu grafico no arranco (rc=$hrc); reintentando..."
            sleep 1.5
            PYGAME_HIDE_SUPPORT_PROMPT=1 SDL_JOYSTICK_ALLOW_BACKGROUND_EVENTS=1 \
                env -u LD_PRELOAD "$PY_BIN" "$MENU_PYGAME_PY" list "$title" "$tmpsel" "$tmpopt" >> "$LOG_FILE" 2>&1
            hrc=$?
            if [ "$hrc" -ge 2 ]; then
                say "AVISO: sigue sin arrancar; se usaran menus de respaldo"
                rm -f "$PYGAME_OK_MARK"          # que no se reintente en bucle
                HAS_PYGAME=0
                MENU_HELPER_FAILED=1
            fi
        fi
        rm -f "$tmpopt"
    elif gtk_available; then
        pad_bridge_start
        write_menu_gtk
        local tmpopt; tmpopt="$(mktemp)"
        printf '%s\n' "$@" > "$tmpopt"
        "$SYS_PY" "$MENU_GTK_PY" list "$title" "$tmpsel" "$tmpopt" >> "$LOG_FILE" 2>&1
        rm -f "$tmpopt"
    elif [ "$HAS_ZENITY" = 1 ]; then
        printf '%s\n' "$@" | zenity --list --title="WProton" --text="$title" \
            --column="Opcion" --hide-header \
            --height=600 --width=680 > "$tmpsel" 2>/dev/null
    else
        say ""
        say "=== $title ==="
        printf '%s\n' "$@" | nl -w2 -s') ' >&2
        printf 'Numero (vacio = volver): ' >&2; read -r n
        [ -n "$n" ] && printf '%s\n' "$@" | sed -n "${n}p" > "$tmpsel"
    fi
    local sel; sel="$(cat "$tmpsel")"; rm -f "$tmpsel"
    if [ -z "$sel" ]; then
        if [ "${MENU_HELPER_FAILED:-0}" = 1 ]; then
            MENU_HELPER_FAILED=0
            log "MENU [$title] -> FALLO del helper (no es cancelacion)"
            return 2
        fi
        log "MENU [$title] -> cancelado"
        return 1
    fi
    if [ "${LANGUAGE:-es}" != "es" ] && [ "${#WP_ORIG[@]}" -gt 0 ]; then
        local _i
        for _i in "${!WP_SHOW[@]}"; do
            if [ "${WP_SHOW[$_i]}" = "$sel" ]; then
                sel="${WP_ORIG[$_i]}"
                break
            fi
        done
    fi
    log "MENU [$title] -> [$sel]"
    printf '%s' "$sel"
}

ask_text() {
    # $1 = pregunta, $2 = valor actual. Imprime el nuevo valor.
    # Con pygame se usa un TECLADO EN PANTALLA: asi se pueden escribir
    # argumentos, DLL overrides o notas con el mando, sin teclado fisico.
    local title="$1" default="${2:-}"
    if pygame_available; then
        pad_bridge_stop
        write_menu_pygame
        local tmpsel; tmpsel="$(mktemp)"
        printf '%s' "$default" > "$tmpsel"
        PYGAME_HIDE_SUPPORT_PROMPT=1 SDL_JOYSTICK_ALLOW_BACKGROUND_EVENTS=1 \
            env -u LD_PRELOAD "$PY_BIN" "$MENU_PYGAME_PY" text "$title" \
            "$tmpsel" "$default" >> "$LOG_FILE" 2>&1
        local rc=$? val; val="$(cat "$tmpsel")"; rm -f "$tmpsel"
        if [ $rc -ne 0 ]; then
            log "TEXTO [$title] -> cancelado"
            printf '%s' "$default"
            return 0
        fi
        log "TEXTO [$title] -> [$val]"
        printf '%s' "$val"
        return 0
    fi
    pad_bridge_start
    if [ "$HAS_ZENITY" = 1 ]; then
        zenity --entry --title="WProton" --text="$title" \
               --entry-text="$default" --width=560 2>/dev/null
    else
        printf '%s [%s]: ' "$title" "$default" >&2; read -r v
        printf '%s' "${v:-$default}"
    fi
}

pick_dir() {
    # $1 = titulo, $2 = dir inicial. Imprime el dir elegido.
    pad_bridge_start
    if [ "$HAS_ZENITY" = 1 ]; then
        zenity --file-selection --directory --title="$1" \
               --filename="${2:-$HOME}/" 2>/dev/null
    else
        ask_text "$1" "${2:-}"
    fi
}

# ----------------------------------------------------------------------------
# 6. DESCARGAS Y GITHUB API
# ----------------------------------------------------------------------------
filter_assets() {
    # Fuera arquitecturas que no son x86_64 y ficheros que no son paquetes
    grep -iv -e 'aarch64' -e 'arm64' -e 'armv7' -e 'armhf' -e 'riscv' \
             -e '\.sha' -e '\.sum' -e '\.txt' -e '\.asc' -e '\.sig' -e 'debug'
}

gh_latest_asset() {
    # $1 = repo, $2 = patron grep -> imprime URL del asset (x86_64)
    curl -fsSL "https://api.github.com/repos/$1/releases/latest" \
        | grep -o '"browser_download_url": *"[^"]*"' | cut -d'"' -f4 \
        | filter_assets | grep -iE "$2" | head -n1
}

gh_release_tags() {
    # $1 = repo, $2 = cuantos (def. 12) -> lista de tags recientes
    curl -fsSL "https://api.github.com/repos/$1/releases?per_page=${2:-12}" \
        | grep -o '"tag_name": *"[^"]*"' | cut -d'"' -f4
}

gh_tag_assets() {
    # $1 = repo, $2 = tag -> URLs de paquetes x86_64 de esa release
    curl -fsSL "https://api.github.com/repos/$1/releases/tags/$2" \
        | grep -o '"browser_download_url": *"[^"]*"' | cut -d'"' -f4 \
        | filter_assets | grep -iE '\.(tar\.(gz|xz|zst)|tgz|zip|7z)$'
}

ge_tags_curated() {
    # GE-Proton: las 8 mas recientes + la ULTIMA version de CADA serie
    # (p.ej. 11-2, 11-1, 10-15..., 9-27, 8-32, 7-55) en orden descendente
    local all
    all="$(curl -fsSL "https://api.github.com/repos/GloriousEggroll/proton-ge-custom/releases?per_page=100" \
        | grep -o '"tag_name": *"[^"]*"' | cut -d'"' -f4)"
    [ -z "$all" ] && return 1
    {
        printf '%s\n' "$all" | head -n 8
        printf '%s\n' "$all" | grep -E '^GE-Proton[0-9]+-[0-9]+$' | sort -V \
            | awk '{m=$0; sub(/^GE-Proton/,"",m); sub(/-.*/,"",m); last[m]=$0}
                   END{for (k in last) print last[k]}'
    } | sort -Vr | awk '!seen[$0]++'
}

dl() {
    # $1 = url, $2 = destino. Con barra de progreso zenity si hay GUI.
    say "Descargando $(basename "$2")..."
    if [ "$HAS_ZENITY" = 1 ]; then
        curl -fL --retry 3 -o "$2" "$1" >> "$LOG_FILE" 2>&1 &
        local pid=$!
        ( while kill -0 $pid 2>/dev/null; do echo 50; sleep 1; done; echo 100 ) \
            | zenity --progress --title="WProton" --text="Descargando $(basename "$2")..." \
                     --pulsate --auto-close --no-cancel 2>/dev/null
        wait $pid
    else
        curl -fL --retry 3 -o "$2" "$1"
    fi
}

run_with_progress() {
    # $1 = texto de estado; resto = comando. Pulsador zenity si hay GUI.
    local text="$1"; shift
    say "$text"
    if [ "$HAS_ZENITY" = 1 ]; then
        "$@" >> "$LOG_FILE" 2>&1 &
        local pid=$!
        ( while kill -0 $pid 2>/dev/null; do echo 50; sleep 1; done; echo 100 ) \
            | zenity --progress --title="WProton" --text="$text" \
                     --pulsate --auto-close --no-cancel 2>/dev/null
        wait $pid
    else
        "$@" >> "$LOG_FILE" 2>&1
    fi
}

extract_archive() {
    # $1 = archivo, $2 = dir destino
    mkdir -p "$2"
    case "$1" in
        *.tar.gz|*.tgz|*.wtgz) tar -xzf "$1" -C "$2" ;;
        *.tar.xz)       tar -xJf "$1" -C "$2" ;;
        *.tar.zst)      tar --zstd -xf "$1" -C "$2" ;;
        *.tar)          tar -xf  "$1" -C "$2" ;;
        *.zip)          "$PY_BIN" -c "import zipfile,sys;zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])" "$1" "$2" ;;
        *.7z)
            if command -v 7z >/dev/null 2>&1; then 7z x -y -o"$2" "$1" >> "$LOG_FILE" 2>&1
            elif command -v bsdtar >/dev/null 2>&1; then bsdtar -xf "$1" -C "$2"
            else return 1; fi ;;
        *) return 1 ;;
    esac
}

# ----------------------------------------------------------------------------
# 7. BOOTSTRAP: python portable + umu-launcher + GE-Proton x86_64
# ----------------------------------------------------------------------------
pbs_latest_url() {
    # python-build-standalone SIN la API de GitHub (evita el rate limit de 60/h
    # que provocaba "No se encontro python-build-standalone x86_64"):
    # 1) tag desde latest-release.json (raw.githubusercontent, sin limite)
    # 2) asset desde la pagina expanded_assets (HTML, sin limite)
    local tag page url
    tag="$(curl -fsSL "https://raw.githubusercontent.com/astral-sh/python-build-standalone/latest-release/latest-release.json" \
        | grep -o '"tag": *"[^"]*"' | head -n1 | cut -d'"' -f4)"
    if [ -n "$tag" ]; then
        page="https://github.com/astral-sh/python-build-standalone/releases/expanded_assets/$tag"
        url="$(curl -fsSL "$page" \
            | grep -o 'href="[^"]*cpython-3\.12\.[0-9]*[^"]*x86_64-unknown-linux-gnu-install_only\.tar\.gz"' \
            | head -n1 | cut -d'"' -f2)"
        if [ -n "$url" ]; then
            case "$url" in
                http*) printf '%s' "$url" ;;
                *)     printf 'https://github.com%s' "$url" ;;
            esac
            return 0
        fi
        log "expanded_assets sin resultado para tag $tag, probando API..." WARN
    fi
    # Fallback: API clasica con paginacion de assets
    local api="https://api.github.com/repos/astral-sh/python-build-standalone/releases/latest"
    local assets_url p
    assets_url="$(curl -fsSL "$api" | grep -o '"assets_url": *"[^"]*"' | head -n1 | cut -d'"' -f4)"
    [ -z "$assets_url" ] && { log "API de GitHub sin respuesta (rate limit?)" WARN; return 1; }
    for p in 1 2 3 4 5 6; do
        url="$(curl -fsSL "${assets_url}?per_page=100&page=$p" \
            | grep -o '"browser_download_url": *"[^"]*"' | cut -d'"' -f4 \
            | grep -E 'cpython-3\.12\.[0-9]+\+[0-9]+-x86_64-unknown-linux-gnu-install_only\.tar\.gz$' \
            | head -n1)"
        [ -n "$url" ] && { printf '%s' "$url"; return 0; }
    done
    return 1
}

setup_python() {
    say "Instalando Python portable (python-build-standalone)..."
    local url tmp="$RUNTIME_DIR/.py_tmp"
    url="$(pbs_latest_url)"
    [ -z "$url" ] && { ui_error "No se encontro python-build-standalone x86_64"; return 1; }
    rm -rf "$tmp"; mkdir -p "$tmp"
    dl "$url" "$tmp/python.tar.gz" || { ui_error "Fallo descargando Python portable"; rm -rf "$tmp"; return 1; }
    tar -xzf "$tmp/python.tar.gz" -C "$tmp" || { ui_error "Fallo extrayendo Python portable"; rm -rf "$tmp"; return 1; }
    [ -x "$tmp/python/bin/python3" ] || { ui_error "Paquete de Python inesperado"; rm -rf "$tmp"; return 1; }
    rm -rf "$PY_DIR"
    mv "$tmp/python" "$PY_DIR"
    rm -rf "$tmp"
    resolve_python
    say "Python portable: $("$PY_BIN" -V 2>&1)"

    # pygame al estilo DeckStation: pip --target runtime/libs_pyX.Y
    say "Instalando pygame en runtime/$(py_libs_dir)..."
    "$PY_BIN" -m ensurepip --default-pip >> "$LOG_FILE" 2>&1 || true
    "$PY_BIN" -m pip install --target "$RUNTIME_DIR/$(py_libs_dir)" \
        --disable-pip-version-check --no-warn-script-location --upgrade pygame >> "$LOG_FILE" 2>&1 \
        || { ui_error "Fallo instalando pygame (los menus caeran a GTK/zenity)"; return 1; }
    say "Instalando evdev para el mapeador .keys (opcional)..."
    "$PY_BIN" -m pip install --target "$RUNTIME_DIR/$(py_libs_dir)" \
        --disable-pip-version-check --no-warn-script-location evdev >> "$LOG_FILE" 2>&1 \
        || say "evdev no compilo (normal en SteamOS): deja tu carpeta evmapy/ en la raiz de WProton"
    HAS_PYGAME=-1   # re-evaluar
    rm -f "$PYGAME_OK_MARK"
    ui_info "Python portable listo: $("$PY_BIN" -V 2>&1) + pygame"
}

setup_umu() {
    say "Descargando umu-launcher (zipapp)..."
    local url tmp="$RUNTIME_DIR/.umu_tmp"
    url="$(gh_latest_asset "Open-Wine-Components/umu-launcher" "zipapp")"
    [ -z "$url" ] && die "No se pudo obtener la URL de umu-launcher"
    rm -rf "$tmp"; mkdir -p "$tmp"
    dl "$url" "$tmp/umu.pkg" || die "Fallo descargando umu"
    case "$url" in
        *.zip) mv "$tmp/umu.pkg" "$tmp/umu.zip"; extract_archive "$tmp/umu.zip" "$tmp" ;;
        *)     mv "$tmp/umu.pkg" "$tmp/umu.tar"; tar -xf "$tmp/umu.tar" -C "$tmp" ;;
    esac
    local found; found="$(find "$tmp" -type f -name 'umu-run' | head -n1)"
    [ -z "$found" ] && die "umu-run no encontrado en el paquete descargado"
    rm -rf "$RUNTIME_DIR/umu"; mkdir -p "$RUNTIME_DIR/umu"
    cp "$found" "$UMU_BIN" && chmod +x "$UMU_BIN"
    rm -rf "$tmp"
    say "umu-launcher instalado en runtime/umu/"
}

setup_proton() {
    # Descarga rapida: ultimo GE-Proton x86_64 (excluye aarch64)
    say "Buscando ultimo GE-Proton x86_64..."
    local url
    url="$(gh_latest_asset "GloriousEggroll/proton-ge-custom" 'GE-Proton.*\.tar\.gz$')"
    [ -z "$url" ] && die "No se pudo obtener la URL de GE-Proton"
    local name; name="$(basename "$url" .tar.gz)"
    if [ -d "$RUNNERS_DIR/$name" ]; then
        ui_info "GE-Proton ya al dia: $name"
        return 0
    fi
    local tmp="$RUNNERS_DIR/.dl_tmp"; rm -rf "$tmp"; mkdir -p "$tmp"
    dl "$url" "$tmp/$(basename "$url")" || die "Fallo descargando GE-Proton"
    extract_archive "$tmp/$(basename "$url")" "$RUNNERS_DIR" || die "Fallo extrayendo GE-Proton"
    rm -rf "$tmp"
    ui_info "GE-Proton instalado: $name"
}

download_runner_tag() {
    # $1 = repo github, $2 = tag, $3 = 1 si es dwproton (fallback dawn.wine)
    local repo="$1" tag="$2" dwp="${3:-0}" assets url count
    say "Listando paquetes de $tag..."
    assets="$(gh_tag_assets "$repo" "$tag")"
    if [ -z "$assets" ] && [ "$dwp" = 1 ]; then
        assets="https://dawn.wine/dawn-winery/dwproton/releases/download/$tag/$tag-x86_64.tar.xz"
        say "Usando descarga directa de dawn.wine: $tag-x86_64.tar.xz"
    fi
    [ -z "$assets" ] && return 1
    count="$(printf '%s\n' "$assets" | grep -c .)"
    if [ "$count" -eq 1 ]; then
        url="$assets"
    else
        local names sel2
        names="$(printf '%s\n' "$assets" | sed 's|.*/||')"
        # shellcheck disable=SC2046
        sel2="$(IFS=$'\n'; set -f; menu "Elige paquete ($tag)" $names)" || return 1
        url="$(printf '%s\n' "$assets" | grep -F "/$sel2" | head -n1)"
    fi
    local tmp="$RUNNERS_DIR/.dl_tmp"; rm -rf "$tmp"; mkdir -p "$tmp"
    dl "$url" "$tmp/$(basename "$url")" || { rm -rf "$tmp"; return 1; }
    say "Extrayendo..."
    extract_archive "$tmp/$(basename "$url")" "$RUNNERS_DIR" || { rm -rf "$tmp"; return 1; }
    rm -rf "$tmp"
    return 0
}

ensure_runner() {
    # Si el perfil pide un RUNNER que no esta instalado, descargarlo antes
    # de lanzar (o abrir el menu de descargas si no sabemos resolverlo)
    [ -z "${RUNNER:-}" ] && return 0
    case "$RUNNER" in
        bundled) return 0 ;;   # se valida al montar
        sys:*)
        sys_runner_path "${RUNNER#sys:}" >/dev/null \
            || { say "AVISO: el runner del sistema '$RUNNER' no existe aqui"; RUNNER=""; }
        return 0 ;;
    esac
    [ -d "$RUNNERS_DIR/$RUNNER" ] && return 0
    say "El perfil pide el runner '$RUNNER' y no esta instalado"
    ui_ask "Este juego esta configurado con el runner:
$RUNNER
que no esta instalado. Descargarlo ahora?" || { RUNNER=""; return 0; }
    local ok=1
    case "$RUNNER" in
        GE-Proton*)
            download_runner_tag "GloriousEggroll/proton-ge-custom" "$RUNNER" 0 && ok=0 ;;
        dwproton-*)
            download_runner_tag "dawn-winery/dwproton-mirror" "$RUNNER" 1 && ok=0 ;;
        WINE_LG_*|PROTON_LG_*|PROTON_STEAM_*)
            download_runner_tag "Castro-Fidel/wine_builds" "$RUNNER" 0 && ok=0 ;;
        *)
            # busqueda del tag exacto en el resto de fuentes conocidas
            local repo
            for repo in "CachyOS/proton-cachyos" "GloriousEggroll/wine-ge-custom" "Kron4ek/Wine-Builds"; do
                if gh_release_tags "$repo" | grep -qx "$RUNNER"; then
                    download_runner_tag "$repo" "$RUNNER" 0 && ok=0
                    break
                fi
            done ;;
    esac
    if [ "$ok" != 0 ] || [ ! -d "$RUNNERS_DIR/$RUNNER" ]; then
        ui_error "No se pudo descargar '$RUNNER' automaticamente.
Se abrira el menu de descarga de runners."
        download_runner_menu
    fi
    if [ ! -d "$RUNNERS_DIR/$RUNNER" ]; then
        say "AVISO: '$RUNNER' sigue sin estar; se usara el runner automatico"
        RUNNER=""
    fi
}

# --- Descarga multi-fuente de runners (menu) ---
download_runner_menu() {
    local src repo
    src="$(menu "Descargar runner - elige fuente" \
        "GE-Proton [proton] - GloriousEggroll, el estandar" \
        "Proton-CachyOS [proton] - optimizado x86-64-v3" \
        "DWProton [proton] - Dawn Winery, fixes anime/gacha" \
        "Wine-LG [wine] - Castro-Fidel (PortWINE / PortProton)" \
        "Proton-LG [proton] - Castro-Fidel, basado en GE" \
        "Wine-GE [wine] - GloriousEggroll, juegos fuera de Steam" \
        "Wine Kron4ek [wine] - vanilla / staging / tkg" \
        "<< Volver")" || return
    local dwproton=0 tagfilter=""
    case "$src" in
        "GE-Proton"*)      repo="GloriousEggroll/proton-ge-custom" ;;
        "Proton-CachyOS"*) repo="CachyOS/proton-cachyos" ;;
        "DWProton"*)       repo="dawn-winery/dwproton-mirror"; dwproton=1 ;;
        "Wine-LG"*)        repo="Castro-Fidel/wine_builds"; tagfilter="^WINE_LG_" ;;
        "Proton-LG"*)      repo="Castro-Fidel/wine_builds"; tagfilter="^PROTON_" ;;
        "Wine-GE"*)        repo="GloriousEggroll/wine-ge-custom" ;;
        "Wine Kron4ek"*)   repo="Kron4ek/Wine-Builds" ;;
        *) return ;;
    esac

    say "Consultando versiones de $repo..."
    local tags
    if [ "$repo" = "GloriousEggroll/proton-ge-custom" ]; then
        tags="$(ge_tags_curated)"
    elif [ -n "$tagfilter" ]; then
        # el repo mezcla familias (WINE_LG / PROTON_LG / PROTON_STEAM):
        # pedir mas releases y quedarnos con la familia elegida
        tags="$(gh_release_tags "$repo" 40 | grep -E "$tagfilter" || true)"
    else
        tags="$(gh_release_tags "$repo")"
    fi
    [ -z "$tags" ] && { ui_error "No se pudieron listar versiones de $repo"; return; }
    local tag
    # shellcheck disable=SC2046
    tag="$(IFS=$'\n'; set -f; menu "Versiones de $repo" $tags)" || return

    say "Listando paquetes de $tag..."
    local assets; assets="$(gh_tag_assets "$repo" "$tag")"
    if [ -z "$assets" ] && [ "$dwproton" = 1 ]; then
        # El mirror puede no adjuntar binarios: patron oficial de dawn.wine
        # (el mismo que usa el paquete dwproton-bin de AUR)
        assets="https://dawn.wine/dawn-winery/dwproton/releases/download/$tag/$tag-x86_64.tar.xz"
        say "Usando descarga directa de dawn.wine: $tag-x86_64.tar.xz"
    fi
    [ -z "$assets" ] && { ui_error "Sin paquetes x86_64 en $tag"; return; }
    local url count
    count="$(printf '%s\n' "$assets" | grep -c .)"
    if [ "$count" -eq 1 ]; then
        url="$assets"
    else
        local names sel
        names="$(printf '%s\n' "$assets" | sed 's|.*/||')"
        # shellcheck disable=SC2046
        sel="$(IFS=$'\n'; set -f; menu "Elige paquete ($tag)" $names)" || return
        url="$(printf '%s\n' "$assets" | grep -F "/$sel" | head -n1)"
    fi

    local tmp="$RUNNERS_DIR/.dl_tmp"; rm -rf "$tmp"; mkdir -p "$tmp"
    dl "$url" "$tmp/$(basename "$url")" || { ui_error "Fallo la descarga"; rm -rf "$tmp"; return; }
    say "Extrayendo..."
    extract_archive "$tmp/$(basename "$url")" "$RUNNERS_DIR" || { ui_error "Fallo la extraccion"; rm -rf "$tmp"; return; }
    rm -rf "$tmp"
    ui_info "Runner instalado. Disponible en los perfiles como:
$(list_runners | tail -n3)"
}

# ----------------------------------------------------------------------------
# 8. RUNNERS (Proton via umu | Wine puro directo)
# ----------------------------------------------------------------------------
runner_kind() {
    [ -f "$1/proton" ] && { printf 'proton'; return 0; }
    [ -x "$1/bin/wine" ] && { printf 'wine'; return 0; }
    local w; w="$(find "$1" -maxdepth 3 -type f -name wine -path '*/bin/wine' | head -n1)"
    [ -n "$w" ] && { printf 'wine'; return 0; }
    return 1
}

runner_wine_bin() {
    [ -x "$1/bin/wine" ] && { printf '%s' "$1/bin/wine"; return; }
    find "$1" -maxdepth 3 -type f -name wine -path '*/bin/wine' | head -n1
}

list_runners() {
    local d name kind
    for d in "$RUNNERS_DIR"/*/; do
        [ -d "$d" ] || continue
        name="$(basename "$d")"
        case "$name" in .*) continue ;; esac
        kind="$(runner_kind "$d")" || continue
        printf '%s [%s]\n' "$name" "$kind"
    done | sort -V
    sys_wine_runners
}

SYS_WINE_BASES="/userdata/system/wine/custom /usr/wine"

sys_wine_runners() {
    # Runners del sistema en Batocera: los custom del usuario en
    # /userdata/system/wine/custom (prioridad) y los del sistema en /usr/wine.
    # Detecta tanto wine (bin/wine) como proton (script proton).
    local base d kind
    for base in $SYS_WINE_BASES; do
        [ -d "$base" ] || continue
        for d in "$base"/*/; do
            [ -d "$d" ] || continue
            kind="$(runner_kind "$d")" || continue
            printf 'sys:%s [%s]\n' "$(basename "$d")" "$kind"
        done
    done 2>/dev/null | awk '!seen[$1]++'
}

sys_runner_path() {
    # $1 = nombre (sin el prefijo sys:) -> ruta real, custom primero
    local base
    for base in $SYS_WINE_BASES; do
        [ -d "$base/$1" ] && { printf '%s' "$base/$1"; return 0; }
    done
    return 1
}

runner_names() { list_runners | sed 's/ \[[a-z]*\]$//'; }
local_runner_names() {
    # solo los descargados (borrables); los sys: no se tocan
    runner_names | grep -v '^sys:' || true
}

get_runner_path() {
    if [ "${RUNNER:-}" = "bundled" ] && [ -n "$BUNDLED_RUNNER_DIR" ]; then
        printf '%s' "$BUNDLED_RUNNER_DIR"; return
    fi
    case "${RUNNER:-}" in
        sys:*)
            local sysd
            sysd="$(sys_runner_path "${RUNNER#sys:}")" && { printf '%s' "$sysd"; return; } ;;
    esac
    if [ -n "${RUNNER:-}" ] && [ -d "$RUNNERS_DIR/$RUNNER" ]; then
        printf '%s' "$RUNNERS_DIR/$RUNNER"; return
    fi
    # En Batocera sin runners descargados: usar el wine del sistema
    if [ "$IS_BATOCERA" = 1 ] && [ -z "$(find "$RUNNERS_DIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null)" ]; then
        local sw swd
        sw="$(sys_wine_runners | head -n1 | sed 's/^sys:\(.*\) \[[a-z]*\]$/\1/')"
        [ -n "$sw" ] && swd="$(sys_runner_path "$sw")" && { printf '%s' "$swd"; return; }
    fi
    local ge
    ge="$(find "$RUNNERS_DIR" -maxdepth 1 -type d -name 'GE-Proton*' | sort -V | tail -n1)"
    [ -n "$ge" ] && { printf '%s' "$ge"; return; }
    local any; any="$(runner_names | head -n1)"
    [ -n "$any" ] && printf '%s' "$RUNNERS_DIR/$any"
}

# ----------------------------------------------------------------------------
# 9. MONTAJE WSQUASHFS (esquema del PortProton antiguo)
#      wsquashfs/tmp_mount/<n>_ro   <- squashfuse (solo lectura)
#      wsquashfs/tmp_mount/<n>      <- overlay fusionado (aqui vive el juego)
#      wsquashfs/overlays/<n>/upper <- saves persistentes (JAMAS se toca)
#      wsquashfs/overlays/<n>/work  <- interno de fuse-overlayfs (se regenera)
#    Si el overlay esta ya montado se REUTILIZA; si falla, modo solo lectura.
# ----------------------------------------------------------------------------
MOUNT_RO=""
MOUNT_RW=""
MOUNT_POINT=""
MOUNT_OK=0

image_format() {
    # Formato REAL del archivo por su cabecera (no por la extension):
    # squashfs -> "hsqs"/"sqsh" | dwarfs -> "DWARFS"
    local f="$1" m
    m="$(head -c 6 "$f" 2>/dev/null)"
    case "$m" in
        DWARFS*) printf 'dwarfs' ;;
        hsqs*|sqsh*) printf 'squashfs' ;;
        *) case "$f" in
               *.dwarfs|*.dwfs) printf 'dwarfs' ;;
               *) printf 'squashfs' ;;
           esac ;;
    esac
}

mount_image_ro() {
    # $1 = imagen, $2 = punto de montaje. Elige squashfuse o el driver dwarfs.
    local img="$1" mp="$2" fmt
    fmt="$(image_format "$img")"
    if [ "$fmt" = "dwarfs" ]; then
        find_dwarfs_tools
        if [ -z "$DWARFS_BIN" ]; then
            say "Falta el driver de DwarFS: descargandolo..."
            setup_dwarfs_tools || { ui_error "No hay driver de DwarFS para montar:
$(basename "$img")"; return 1; }
        fi
        say "[+] Montando imagen DwarFS con $(basename "$DWARFS_BIN")"
        "$DWARFS_BIN" "$img" "$mp" -o ro >>"$LOG_FILE" 2>&1 || return 1
    else
        "$SQUASHFUSE_BIN" "$img" "$mp" >>"$LOG_FILE" 2>&1 || return 1
    fi
    return 0
}

is_mounted() {
    if command -v mountpoint >/dev/null 2>&1; then
        mountpoint -q "$1" 2>/dev/null
    else
        grep -qs " $1 " /proc/mounts
    fi
}

umount_dir() {
    # Desmontar con reintentos (wine puede tardar en soltar ficheros) y borrar
    # el directorio: objetivo -> tmp_mount/ queda VACIO al cerrar el juego
    local d="$1" i
    [ -d "$d" ] || return 0
    if is_mounted "$d"; then
        for i in 1 2 3 4 5; do
            "$FUSERMOUNT_BIN" -u "$d" 2>/dev/null && break
            log "umount ocupado ($d), reintento $i/5..." WARN
            sleep 1
        done
        is_mounted "$d" && "$FUSERMOUNT_BIN" -uz "$d" 2>/dev/null
    fi
    is_mounted "$d" || rmdir "$d" 2>/dev/null
}

sweep_stale_mounts() {
    # Limpia restos de sesiones anteriores (crashes, cortes...)
    local d
    for d in "$MOUNT_BASE"/*/; do
        [ -d "$d" ] || continue
        umount_dir "${d%/}"
    done
    # work/ nunca debe sobrevivir entre sesiones (fuse-overlayfs lo quiere vacio)
    find "$OVERLAY_BASE" -mindepth 2 -maxdepth 2 -type d -name work -exec rm -rf {} + 2>/dev/null
    # Migracion desde el layout viejo de WProton (mounts/<n>/upper) si existiera
    if [ -d "$BASE_DIR/mounts" ]; then
        local m gid
        for m in "$BASE_DIR/mounts"/*/upper; do
            [ -d "$m" ] || continue
            gid="$(basename "$(dirname "$m")")"
            if [ ! -d "$OVERLAY_BASE/$gid/upper" ]; then
                mkdir -p "$OVERLAY_BASE/$gid"
                mv "$m" "$OVERLAY_BASE/$gid/upper" && say "[~] saves migrados: mounts/$gid -> overlays/$gid"
            fi
        done
        rmdir "$BASE_DIR/mounts"/*/ "$BASE_DIR/mounts" 2>/dev/null
    fi
}

mount_game() {
    local squash="$1" gid="$2"
    MOUNT_RO="$MOUNT_BASE/${gid}_ro"
    MOUNT_RW="$MOUNT_BASE/${gid}"
    local ov="$OVERLAY_BASE/$gid"
    mkdir -p "$ov"
    # Compatibilidad con el layout antiguo: data/ era el upper
    if [ -d "$ov/data" ] && [ ! -d "$ov/upper" ]; then
        mv "$ov/data" "$ov/upper" 2>/dev/null && say "[~] upper migrado: data/ -> upper/"
    fi
    local upper="$ov/upper" work="$ov/work"

    # Reutilizar montaje si ya esta activo (evita desmonte/remonte innecesario)
    if is_mounted "$MOUNT_RW"; then
        say "[+] Overlay ya montado - reutilizando $MOUNT_RW"
        MOUNT_OK=1
        MOUNT_POINT="$MOUNT_RW"
        return 0
    fi
    umount_dir "$MOUNT_RW"
    umount_dir "$MOUNT_RO"

    # work/ SIEMPRE vacio; upper/ JAMAS se toca (saves)
    rm -rf "$work"; mkdir -p "$upper" "$work" "$MOUNT_RO" "$MOUNT_RW"

    say "Montando $squash..."
    mount_image_ro "$squash" "$MOUNT_RO" || die "no se pudo montar $squash"
    # squash_to_uid/gid: los wsquashfs hechos en Batocera llevan los ficheros
    # como root; sin esto, cuando fuse-overlayfs copia uno a la capa superior
    # intenta conservar el propietario y falla con "Operation not permitted"
    # (era lo que impedia a Wine escribir el registro del prefix incluido).
    local ovl_opts="lowerdir=$MOUNT_RO,upperdir=$upper,workdir=$work"
    local ovl_squash="$ovl_opts,squash_to_uid=$(id -u),squash_to_gid=$(id -g)"
    if "$OVERLAYFS_BIN" -o "$ovl_squash" "$MOUNT_RW" >>"$LOG_FILE" 2>&1; then
        MOUNT_OK=1
        MOUNT_POINT="$MOUNT_RW"
    elif "$OVERLAYFS_BIN" -o "$ovl_opts" "$MOUNT_RW" >>"$LOG_FILE" 2>&1; then
        say "AVISO: fuse-overlayfs sin squash_to_uid (version antigua): si el"
        say "       juego trae prefix incluido puede que no pueda escribirlo"
        MOUNT_OK=1
        MOUNT_POINT="$MOUNT_RW"
    else
        say "AVISO: fallo OverlayFS, modo Solo Lectura activado (los saves no persistiran)"
        rmdir "$MOUNT_RW" 2>/dev/null
        MOUNT_OK=1
        MOUNT_POINT="$MOUNT_RO"
    fi
}

mount_ro_only() {
    local squash="$1" gid="$2"
    MOUNT_RO="$MOUNT_BASE/${gid}_ro"
    MOUNT_RW=""
    if is_mounted "$MOUNT_RO"; then
        MOUNT_OK=1; MOUNT_POINT="$MOUNT_RO"; return 0
    fi
    umount_dir "$MOUNT_RO"
    mkdir -p "$MOUNT_RO"
    mount_image_ro "$squash" "$MOUNT_RO" || die "no se pudo montar $squash"
    MOUNT_OK=1
    MOUNT_POINT="$MOUNT_RO"
}

cleanup_mount() {
    [ "$MOUNT_OK" = 1 ] || return 0
    say "Desmontando..."
    [ -n "$MOUNT_RW" ] && umount_dir "$MOUNT_RW"
    [ -n "$MOUNT_RO" ] && umount_dir "$MOUNT_RO"
    # el work del overlay correspondiente se regenera en el proximo montaje
    if [ -n "$MOUNT_RW" ]; then
        rm -rf "$OVERLAY_BASE/$(basename "$MOUNT_RW")/work" 2>/dev/null
    fi
    # barrido final: cualquier dir vacio que quede en tmp_mount, fuera
    # (rmdir no toca montajes activos de otros juegos: fallan con EBUSY)
    rmdir "$MOUNT_BASE"/* 2>/dev/null
    if [ -z "$(ls -A "$MOUNT_BASE" 2>/dev/null)" ]; then
        log "tmp_mount vacio tras el desmontaje [OK]"
    else
        log "tmp_mount aun contiene: $(ls -A "$MOUNT_BASE" 2>/dev/null | tr '\n' ' ')" WARN
    fi
    MOUNT_OK=0
}

cleanup_all() { cleanup_mount; pad_bridge_stop; mapeador_stop; canvas_stop; }
trap cleanup_all EXIT INT TERM


# ----------------------------------------------------------------------------
# 10. DETECCION DEL EJECUTABLE (heuristica completa del PortProton antiguo)
#     autorun.cmd formato DIR="..."/CMD="..." (UTF-16 soportado) manda;
#     el .ppdb del wsquashfs, si existe, se IGNORA a proposito.
# ----------------------------------------------------------------------------
_fexe() {
    # Filtro maestro de herramientas/instaladores (grep -iv, nunca globs)
    grep -iv \
        -e 'dgvoodoocpl'  -e 'dxwnd'       -e 'reshade'    -e 'enbhost'   -e 'enbinjector' \
        -e 'winecfg'      -e 'wineboot'    -e 'winedbg'    -e 'winepath' \
        -e 'regedit'      -e 'iexplore'    -e 'explorer\.exe' \
        -e 'msiexec'      -e 'rundll32'    -e 'regsvr32'   -e 'regasm'    -e 'regsvcs' \
        -e 'notepad'      -e 'wordpad'     -e 'mspaint'    -e 'wmplayer' \
        -e 'dxdiag'       -e 'msconfig'    -e 'taskmgr'    -e 'conhost'   -e 'cmd\.exe' \
        -e 'wscript'      -e 'cscript'     -e 'mshta'      -e 'control\.exe' \
        -e 'winver'       -e 'mmc\.exe'    -e 'werfault'   -e 'drwatson'  -e 'dwwin' \
        -e 'unitycrashandler' -e 'unityplayer' \
        -e 'ue4prereq'    -e 'ue5prereq'   -e 'epicwebhelper' \
        -e 'vcredist'     -e 'vc_redist'   -e 'dxsetup'    -e 'dotnetfx' \
        -e 'oalinst'      -e 'physx'       -e 'msvcr'      -e 'msvcp' \
        -e 'modorganizer' -e 'xivlauncher' -e 'openxr'     -e 'fpsmon' \
        -e 'setup\.exe$'  -e 'unins'       -e 'install\.exe$' \
        -e 'redist\.exe$' -e 'prerequisite' -e 'crashreport' -e 'bugsplat' \
        -e 'scriptinterpreter' -e 'goggame' -e 'galaxycommunication'
}

scan_exes() {
    # Lista filtrada para menus de seleccion manual
    find "$1" -type f -iname '*.exe' \
        ! -ipath '*/windows/*' ! -ipath '*/Windows/*' ! -ipath '*/system32/*' \
        ! -ipath '*/syswow64/*' 2>/dev/null | _fexe
}

find_game_exe() {
    # Heuristica del script antiguo, en orden de fiabilidad
    local ROOT="$1" EXE=""

    # 1) Binarios de motor (Unreal y similares)
    EXE=$(find "$ROOT" -type f -iname '*.exe' \
        \( -ipath '*/Binaries/Win64/*' -o -ipath '*/Binaries/Win32/*' \
           -o -ipath '*/Win64/*' -o -ipath '*/Win32/*' \) \
        ! -ipath '*/windows/*' ! -ipath '*/Windows/*' 2>/dev/null | _fexe | head -n1)
    [ -n "$EXE" ] && { printf '%s' "$EXE"; return; }

    # 2) exe en la raiz
    EXE=$(find "$ROOT" -maxdepth 1 -type f -iname '*.exe' 2>/dev/null | _fexe | head -n1)
    [ -n "$EXE" ] && { printf '%s' "$EXE"; return; }

    # 3) prefijos con drive_c
    if [ -d "$ROOT/drive_c" ]; then
        EXE=$(find "$ROOT/drive_c" -type f -iname '*.exe' \
              ! -ipath '*/windows/*' ! -ipath '*/Windows/*' \
              ! -ipath '*/system32/*' ! -ipath '*/syswow64/*' \
              ! -ipath '*/ProgramData/*' ! -ipath '*/Common Files/*' \
              2>/dev/null | _fexe | head -n1)
        [ -n "$EXE" ] && { printf '%s' "$EXE"; return; }
    fi

    # 4) Unity: <Nombre>_Data junto a <Nombre>.exe
    local DATA_DIR UNITY_NAME
    DATA_DIR=$(find "$ROOT" -maxdepth 5 -type d \( -iname '*_Data' -o -iname '*.Data' \) 2>/dev/null | head -n1)
    if [ -n "$DATA_DIR" ]; then
        UNITY_NAME=$(basename "$DATA_DIR" | sed 's/[_.]Data$//i')
        EXE=$(find "$(dirname "$DATA_DIR")" -maxdepth 1 -type f -iname "${UNITY_NAME}.exe" 2>/dev/null | head -n1)
        [ -n "$EXE" ] && { printf '%s' "$EXE"; return; }
    fi

    # 5) barrido general
    find "$ROOT" -type f -iname '*.exe' \
        ! -ipath '*/windows/*' ! -ipath '*/Windows/*' ! -ipath '*/system32/*' \
        2>/dev/null | _fexe | head -n1
}

parse_autorun() {
    # Formato autorun.cmd de Batocera con CRLF y UTF-16. Ademas de DIR/CMD
    # soporta ENV= (variables, p.ej. WINEDLLOVERRIDES) y LANG= (locale del
    # juego). SAVEDIR/SAVEFILES se ignoran: nuestro overlay ya persiste todo.
    local FILE="$1" CONTENT
    R_DIR=""; R_CMD=""; R_CMD_BASE=""; R_ARGS=""; R_ENV=""; R_LANG=""
    [ -f "$FILE" ] || return
    if command -v file >/dev/null 2>&1 && file "$FILE" | grep -qi 'UTF-16'; then
        CONTENT=$(iconv -f UTF-16 -t UTF-8 "$FILE" 2>/dev/null)
    else
        CONTENT=$(cat "$FILE")
    fi
    CONTENT=$(printf '%s' "$CONTENT" | tr -d '\r' | sed 's/\\/\//g')
    _aval() {  # $1 = clave -> valor sin comillas envolventes ni espacios
        printf '%s\n' "$CONTENT" | grep -i "^$1=" | head -n1 \
            | sed -e "s/^[^=]*=//" -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
    }
    R_DIR="$(_aval DIR | sed -e 's/^"//' -e 's/"$//' -e 's|^\./||')"
    local rawcmd; rawcmd="$(_aval CMD)"
    # CMD puede llevar comillas y argumentos: CMD="Rayman Origins.exe" --full
    case "$rawcmd" in
        '"'*)
            R_CMD="${rawcmd#\"}"; R_CMD="${R_CMD%%\"*}"
            R_ARGS="${rawcmd#\"$R_CMD\"}"; R_ARGS="${R_ARGS# }" ;;
        *)
            R_CMD="${rawcmd%% *}"
            [ "$R_CMD" != "$rawcmd" ] && R_ARGS="${rawcmd#* }" ;;
    esac
    R_CMD_BASE=$(basename "$R_CMD" 2>/dev/null)
    R_ENV="$(_aval ENV)"
    R_LANG="$(_aval LANG)"
    if printf '%s\n' "$CONTENT" | grep -qi '^SAVEDIR='; then
        log "autorun.cmd trae SAVEDIR (Batocera): ignorado, el overlay ya persiste los saves"
    fi
}

write_autorun() {
    # $1 = raiz del juego, $2 = exe absoluto dentro de la raiz
    local root="$1" exe="$2" rel_dir exe_name
    exe_name="$(basename "$exe")"
    rel_dir="$(realpath --relative-to="$root" "$(dirname "$exe")" 2>/dev/null)"
    if [ -n "$rel_dir" ] && [ "$rel_dir" != "." ]; then
        printf 'DIR="%s"\r\nCMD="%s"\r\n' "$rel_dir" "$exe_name" > "$root/autorun.cmd"
    else
        printf 'CMD="%s"\r\n' "$exe_name" > "$root/autorun.cmd"
    fi
}

find_exe() {
    local root="$1" mode="${2:-auto}"

    if [ "$mode" = "auto" ]; then
        # Paso 1: autorun.cmd (maxima prioridad, raiz primero)
        local M_AUTO
        M_AUTO=$(find "$root" -maxdepth 1 -type f -iname 'autorun.cmd' 2>/dev/null | head -n1)
        [ -z "$M_AUTO" ] && M_AUTO=$(find "$root" -type f -iname 'autorun.cmd' 2>/dev/null | head -n1)
        if [ -f "$M_AUTO" ]; then
            parse_autorun "$M_AUTO"
            if [ -n "$R_CMD_BASE" ]; then
                local hit=""
                if [ -n "$R_DIR" ]; then
                    hit=$(find "$root" -ipath "*${R_DIR}*" -iname "$R_CMD_BASE" 2>/dev/null | head -n1)
                else
                    # sin DIR: preferir raiz antes que homonimos en subcarpetas
                    hit=$(find "$root" -maxdepth 1 -iname "$R_CMD_BASE" 2>/dev/null | head -n1)
                    [ -z "$hit" ] && hit=$(find "$root" -maxdepth 2 -iname "$R_CMD_BASE" 2>/dev/null | head -n1)
                    [ -z "$hit" ] && hit=$(find "$root" -iname "$R_CMD_BASE" 2>/dev/null | head -n1)
                fi
                [ -n "$hit" ] && { EXE_PATH="$hit"; EXE_ARGS="${ARGS_OVERRIDE:-}"; say "[+] Ejecutable por autorun.cmd: $hit"; return 0; }
            fi
        fi
        # Paso 2: heuristica completa
        local guess; guess="$(find_game_exe "$root")"
        [ -n "$guess" ] && { EXE_PATH="$guess"; EXE_ARGS="${ARGS_OVERRIDE:-}"; say "[+] Ejecutable por heuristica: $guess"; return 0; }
    fi

    # Paso 3: seleccion manual (menu)
    local list rels sel
    list="$(scan_exes "$root")"
    [ -z "$list" ] && return 1
    rels="$(printf '%s\n' "$list" | sed "s|^$root/||")"
    # shellcheck disable=SC2046
    sel="$(IFS=$'\n'; set -f; menu "Elige el ejecutable" $rels)" || return 1
    EXE_PATH="$root/$sel"; EXE_ARGS="${ARGS_OVERRIDE:-}"
    return 0
}


# ----------------------------------------------------------------------------
# 11. PERFILES POR JUEGO (estilo TeknoParrot): profiles/<id>.conf
# ----------------------------------------------------------------------------
game_id() {
    local gid; gid="$(basename "$1")"
    [ -d "$1" ] || gid="${gid%.*}"
    printf '%s' "$gid" | tr ' /' '__'
}

profile_defaults() {
    GAMEID="umu-default"; STORE="none"
    RUNNER=""                # carpeta en runtime/proton/ (vacio = auto)
    EXE_OVERRIDE=""; ARGS_OVERRIDE=""
    PREFIX_MODE="shared"     # shared = prefixes/default (comun) | own = por juego
    MANGOHUD=0; GAMEMODE=1; FSYNC=1; ESYNC=1; DXVK_ASYNC=1; WAYLAND=0
    PAD_SDL=auto             # auto | 1 | 0  (auto: activarlo solo si hace falta)
    NTSYNC=0                 # sincronizacion NT por kernel (necesita /dev/ntsync)
    FAVORITO=0               # 1 = aparece primero en la lista
    NOTAS=""                 # apunte libre ("necesita -novr", "usar GE 9-27"...)
    PLAY_COUNT=0             # veces jugado
    PLAY_SECONDS=0           # tiempo total jugado (segundos)
    LAST_PLAYED=""           # fecha de la ultima partida (YYYY-MM-DD HH:MM)
    SAVE_PATHS=""            # carpetas de partidas detectadas al jugar (: separadas)
    PAD_STEAMFIX=1           # SteamOS: no ocultar el mando fisico al juego
    NESTED_GAMESCOPE=0       # modo Juego: lanzar dentro de gamescope propio
                             # (OFF por defecto: gamescope dentro de gamescope
                             #  rompe su capa Vulkan -> "Hooking has failed")
    USE_BATOCERA="$IS_BATOCERA"   # en Batocera: lanzar via batocera-wine
    WINED3D=0                # 1 = OpenGL (PROTON_USE_WINED3D) para juegos viejos
    FSR=0                    # 1 = escalado AMD FSR en pantalla completa
    LAA=0                    # 1 = Large Address Aware (32bit >2GB RAM)
    GAMESCOPE=""             # args de gamescope (vacio = desactivado)
    DLL_OVERRIDES=""         # WINEDLLOVERRIDES, ej: d3d9,ddraw=n,b
    GAME_LANG=""             # locale, ej: ru_RU.UTF-8 / ja_JP.UTF-8
    EXTRA_ENV=""
}

profile_exists() { [ -f "$PROFILE_DIR/$1.conf" ]; }

load_profile() {
    local conf="$PROFILE_DIR/$1.conf"
    profile_defaults
    if [ -f "$conf" ]; then
        # shellcheck disable=SC1090
        . "$conf"
        log "Perfil cargado: $conf"
    fi
}

write_full_profile() {
    local gid="$1" conf="$PROFILE_DIR/$1.conf"
    cat > "$conf" <<EOF
# Perfil WProton para: $gid  (editable a mano o via ./wproton.sh --config)
GAMEID="$GAMEID"
STORE="$STORE"
RUNNER="$RUNNER"
EXE_OVERRIDE="$EXE_OVERRIDE"
ARGS_OVERRIDE="$ARGS_OVERRIDE"
PREFIX_MODE="$PREFIX_MODE"
MANGOHUD=$MANGOHUD
PAD_SDL=$PAD_SDL
PAD_STEAMFIX=$PAD_STEAMFIX
NESTED_GAMESCOPE=$NESTED_GAMESCOPE
NTSYNC=$NTSYNC
FAVORITO=$FAVORITO
NOTAS="$NOTAS"
PLAY_COUNT=$PLAY_COUNT
PLAY_SECONDS=$PLAY_SECONDS
LAST_PLAYED="$LAST_PLAYED"
SAVE_PATHS="$SAVE_PATHS"
USE_BATOCERA=$USE_BATOCERA
GAMEMODE=$GAMEMODE
FSYNC=$FSYNC
ESYNC=$ESYNC
DXVK_ASYNC=$DXVK_ASYNC
WAYLAND=$WAYLAND
WINED3D=$WINED3D
FSR=$FSR
LAA=$LAA
GAMESCOPE="$GAMESCOPE"
DLL_OVERRIDES="$DLL_OVERRIDES"
GAME_LANG="$GAME_LANG"
EXTRA_ENV="$EXTRA_ENV"
EOF
}

ACQ_MOUNTED=0
acquire_game_root() {
    # $1 = wsquashfs O carpeta, $2 = gid, $3 = rw|ro
    # Deja la raiz del juego en MOUNT_POINT. Con carpeta no hay nada que montar.
    if [ -d "$1" ]; then
        MOUNT_POINT="$1"
        ACQ_MOUNTED=0
    else
        ACQ_MOUNTED=1
        if [ "${3:-rw}" = "ro" ]; then
            mount_ro_only "$1" "$2"
        else
            mount_game "$1" "$2"
        fi
    fi
}
release_game_root() {
    [ "${ACQ_MOUNTED:-0}" = 1 ] && cleanup_mount
    ACQ_MOUNTED=0
}

has_bundled_prefix() {
    # wsquashfs estilo Batocera: el archivo ES un prefix de Wine comprimido
    [ -d "$1/drive_c" ] && { [ -f "$1/system.reg" ] || [ -f "$1/user.reg" ]; }
}

BUNDLED_PREFIX_DIR=""
BUNDLED_RUNNER_DIR=""

find_bundled_runner() {
    # Algunos wsquashfs (estilo Batocera) traen su propio Wine dentro.
    # $1 = raiz del juego -> dir del runner incluido (vacio si no hay)
    find "$1" -maxdepth 4 -type f -name wine -path '*/bin/wine' 2>/dev/null \
        | head -n1 | xargs -r dirname | xargs -r dirname
}

prefix_label() {
    case "$PREFIX_MODE" in
        own)     printf 'propio del juego' ;;
        bundled) printf 'incluido en el wsquashfs' ;;
        *)       printf 'compartido (default)' ;;
    esac
}

prefix_path() {
    # shared = prefixes/default | own = por juego | bundled = el propio montaje
    # (con bundled, las escrituras del registro caen en overlays/<n>/upper/)
    case "$PREFIX_MODE" in
        own)     printf '%s' "$PREFIX_DIR/$1" ;;
        bundled)
            if [ -n "$BUNDLED_PREFIX_DIR" ]; then
                printf '%s' "$BUNDLED_PREFIX_DIR"
            else
                printf '%s' "$PREFIX_DIR/default"
            fi ;;
        *)       printf '%s' "$PREFIX_DIR/default" ;;
    esac
}

# ----------------------------------------------------------------------------
# 12. ASISTENTE DE PRIMERA EJECUCION (runner + config basica)
# ----------------------------------------------------------------------------
wizard_pick_runner() {
    local runners sel
    runners="$(list_runners)"
    if [ -z "$runners" ]; then
        ui_info "No hay runners en runtime/proton/. Descargando GE-Proton..."
        setup_proton
        runners="$(list_runners)"
        [ -z "$runners" ] && die "Sigue sin haber runners instalados"
    fi
    local brow=""
    [ "${HAS_BUNDLED_RUNNER:-0}" = 1 ] && brow="(incluido en el wsquashfs) [wine]"
    # shellcheck disable=SC2046
    sel="$(IFS=$'\n'; set -f; menu "Paso 1/3 - Elige Proton/Wine para este juego" \
            "(automatico: ultimo GE-Proton instalado)" "$brow" $runners)" || return 1
    if [ "$sel" = "(incluido en el wsquashfs) [wine]" ]; then
        RUNNER="bundled"
        return 0
    fi
    if [ "$sel" = "(automatico: ultimo GE-Proton instalado)" ]; then
        RUNNER=""
    else
        RUNNER="${sel% \[*\]}"
    fi
    return 0
}

wizard_pick_exe() {
    local root="$1" list rels sel
    list="$(scan_exes "$root")"
    rels="$(printf '%s\n' "$list" | sed "s|^$root/||")"
    # shellcheck disable=SC2046
    sel="$(IFS=$'\n'; set -f; menu "Paso 2/3 - Ejecutable del juego" \
            "(automatico: autorun.cmd / escaneo)" $rels)" || return 1
    if [ "$sel" = "(automatico: autorun.cmd / escaneo)" ]; then
        EXE_OVERRIDE=""
    else
        EXE_OVERRIDE="$sel"
    fi
    return 0
}

wizard_toggles() {
    if pygame_available; then
        pad_bridge_stop
        write_menu_pygame
        local tmpsel tmpopt; tmpsel="$(mktemp)"; tmpopt="$(mktemp)"
        cat > "$tmpopt" <<EOF
0|MangoHud (FPS en pantalla)
1|GameMode (prioridad CPU)
1|Fsync (sincronizacion rapida)
1|DXVK Async + GPL (menos stutter en AMD)
1|Mando via SDL automatico (DualSense/DS4 como Xbox)
0|NTsync (sincronizacion por kernel, 6.14+)
0|Wayland nativo (experimental)
EOF
        PYGAME_HIDE_SUPPORT_PROMPT=1 SDL_JOYSTICK_ALLOW_BACKGROUND_EVENTS=1 \
            env -u LD_PRELOAD "$PY_BIN" "$MENU_PYGAME_PY" check "Paso 3/3 - Configuracion basica" "$tmpsel" "$tmpopt" >> "$LOG_FILE" 2>&1
        local rc=$? sel; sel="$(cat "$tmpsel")"; rm -f "$tmpsel" "$tmpopt"
        [ $rc -ne 0 ] && return 1
        MANGOHUD=0; GAMEMODE=0; FSYNC=0; DXVK_ASYNC=0; WAYLAND=0; PAD_SDL=0; NTSYNC=0
        case "$sel" in *MangoHud*)  MANGOHUD=1 ;; esac
        case "$sel" in *GameMode*)  GAMEMODE=1 ;; esac
        case "$sel" in *Fsync*)     FSYNC=1 ;; esac
        case "$sel" in *DXVK*)      DXVK_ASYNC=1 ;; esac
        case "$sel" in *"Mando via SDL"*) PAD_SDL=auto ;; esac
        case "$sel" in *NTsync*)    NTSYNC=1 ;; esac
        case "$sel" in *Wayland*)   WAYLAND=1 ;; esac
        return 0
    fi
    if gtk_available; then
        pad_bridge_start
        write_menu_gtk
        local tmpsel tmpopt; tmpsel="$(mktemp)"; tmpopt="$(mktemp)"
        cat > "$tmpopt" <<EOF
0|MangoHud (FPS en pantalla)
1|GameMode (prioridad CPU)
1|Fsync (sincronizacion rapida)
1|DXVK Async + GPL (menos stutter en AMD)
1|Mando via SDL automatico (DualSense/DS4 como Xbox)
0|Wayland nativo (experimental)
EOF
        "$SYS_PY" "$MENU_GTK_PY" check "Paso 3/3 - Configuracion basica" "$tmpsel" "$tmpopt" >> "$LOG_FILE" 2>&1
        local sel; sel="$(cat "$tmpsel")"; rm -f "$tmpsel" "$tmpopt"
        [ -z "$sel" ] && return 1
        MANGOHUD=0; GAMEMODE=0; FSYNC=0; DXVK_ASYNC=0; WAYLAND=0
        case "$sel" in *MangoHud*)  MANGOHUD=1 ;; esac
        case "$sel" in *GameMode*)  GAMEMODE=1 ;; esac
        case "$sel" in *Fsync*)     FSYNC=1 ;; esac
        case "$sel" in *DXVK*)      DXVK_ASYNC=1 ;; esac
        case "$sel" in *Wayland*)   WAYLAND=1 ;; esac
        return 0
    fi
    if [ "$HAS_ZENITY" = 1 ]; then
        local tmpsel; tmpsel="$(mktemp)"
        zenity --list --checklist --title="WProton" \
            --text="Paso 3/3 - Configuracion basica (X del mando marca/desmarca)" \
            --column="On" --column="Opcion" \
            FALSE "MangoHud (FPS en pantalla)" \
            TRUE  "GameMode (prioridad CPU)" \
            TRUE  "Fsync (sincronizacion rapida)" \
            TRUE  "DXVK Async + GPL (menos stutter en AMD)" \
            FALSE "Wayland nativo (experimental)" \
            --height=440 --width=560 --separator='|' > "$tmpsel" 2>/dev/null
        local rc=$? sel; sel="$(cat "$tmpsel")"; rm -f "$tmpsel"
        [ $rc -ne 0 ] && return 1
        MANGOHUD=0; GAMEMODE=0; FSYNC=0; DXVK_ASYNC=0; WAYLAND=0
        case "$sel" in *MangoHud*)  MANGOHUD=1 ;; esac
        case "$sel" in *GameMode*)  GAMEMODE=1 ;; esac
        case "$sel" in *Fsync*)     FSYNC=1 ;; esac
        case "$sel" in *DXVK*)      DXVK_ASYNC=1 ;; esac
        case "$sel" in *Wayland*)   WAYLAND=1 ;; esac
    else
        local r
        printf 'MangoHud? [s/N]: '  >&2; read -r r; { [ "$r" = s ] || [ "$r" = S ]; } && MANGOHUD=1 || MANGOHUD=0
        printf 'GameMode? [S/n]: '  >&2; read -r r; [ "$r" = n ] || [ "$r" = N ] && GAMEMODE=0 || GAMEMODE=1
        printf 'Fsync? [S/n]: '     >&2; read -r r; [ "$r" = n ] || [ "$r" = N ] && FSYNC=0 || FSYNC=1
        printf 'DXVK Async? [S/n]: ' >&2; read -r r; [ "$r" = n ] || [ "$r" = N ] && DXVK_ASYNC=0 || DXVK_ASYNC=1
        printf 'Wayland? [s/N]: '   >&2; read -r r; { [ "$r" = s ] || [ "$r" = S ]; } && WAYLAND=1 || WAYLAND=0
    fi
    return 0
}

first_run_wizard() {
    local gid="$1" root="$2"
    say "Primera ejecucion de $gid: lanzando asistente..."
    profile_defaults
    HAS_BUNDLED_RUNNER=0
    local wiz_brun; wiz_brun="$(find_bundled_runner "$root")"
    [ -n "$wiz_brun" ] && HAS_BUNDLED_RUNNER=1
    wizard_pick_runner || return 1
    if [ "$HAS_BUNDLED_RUNNER" = 1 ] && [ "$RUNNER" != "bundled" ] && [ -z "$RUNNER" ]; then
        : # eligio automatico pudiendo elegir el incluido: respetar
    fi
    if [ "$RUNNER" = "bundled" ] && has_bundled_prefix "$root"; then
        # Wine incluido elegido: ofrecer tambien su prefix (van de la mano)
        if ui_ask "Usar tambien el prefix incluido en el wsquashfs?
(registro y DLLs que acompanan a ese Wine)"; then
            PREFIX_MODE="bundled"
        fi
    elif has_bundled_prefix "$root"; then
        if ui_ask "Este wsquashfs incluye un prefix de Wine (estilo Batocera).
Usarlo como prefijo del juego?
(Si: registro y DLLs propios del juego, escrituras al overlay
 No: prefijo compartido de WProton)"; then
            PREFIX_MODE="bundled"
        fi
    fi
    wizard_pick_exe "$root" || return 1
    wizard_toggles || return 1
    write_full_profile "$gid"
    ui_info "Perfil creado: profiles/$gid.conf
Runner: ${RUNNER:-ultimo GE-Proton} | Prefijo: compartido (prefixes/default)
Afinalo cuando quieras con: ./wproton.sh --config"
    return 0
}

# ----------------------------------------------------------------------------
# 13. ENTORNO PORTABLE + LANZAMIENTO
# ----------------------------------------------------------------------------
export_game_env() {
    local gid="$1"
    export WINEPREFIX; WINEPREFIX="$(prefix_path "$gid")"
    mkdir -p "$WINEPREFIX"
    export UMU_RUNTIME_PATH="$RUNTIME_DIR/steamrt"
    export XDG_DATA_HOME="$RUNTIME_DIR/xdg-data"
    mkdir -p "$UMU_RUNTIME_PATH" "$XDG_DATA_HOME"
    export DXVK_STATE_CACHE_PATH="$CACHE_DIR/dxvk"
    export VKD3D_SHADER_CACHE_PATH="$CACHE_DIR/vkd3d"
    export MESA_SHADER_CACHE_DIR="$CACHE_DIR/mesa"
    export __GL_SHADER_DISK_CACHE_PATH="$CACHE_DIR/nvidia"
    mkdir -p "$DXVK_STATE_CACHE_PATH" "$VKD3D_SHADER_CACHE_PATH" \
             "$MESA_SHADER_CACHE_DIR" "$__GL_SHADER_DISK_CACHE_PATH"
    # Tweaks estilo PortProton
    if [ "$FSYNC" = 1 ]; then export WINEFSYNC=1; else export PROTON_NO_FSYNC=1; fi
    if [ "$ESYNC" = 1 ]; then export WINEESYNC=1; else export PROTON_NO_ESYNC=1; fi
    [ "$DXVK_ASYNC" = 1 ] && export DXVK_ASYNC=1 RADV_PERFTEST=gpl
    [ "$MANGOHUD" = 1 ]   && export MANGOHUD=1
    # Mandos Sony/Switch fuera de Steam: sin esto Proton los pasa por hidraw
    # y los juegos solo-XInput no los ven (el caso The Mummy Demastered)
    local pad_auto pad_eff pad_why
    if [ "${PAD_SDL:-auto}" = auto ]; then
        pad_auto="$(pad_sdl_auto)"
        pad_eff="${pad_auto%%|*}"; pad_why="auto: ${pad_auto#*|}"
    else
        pad_eff="$PAD_SDL"; pad_why="fijado en el perfil"
    fi
    if [ "$pad_eff" = 1 ]; then
        export PROTON_PREFER_SDL=1 PROTON_DISABLE_HIDRAW=1
        say "[+] Mando via SDL: ACTIVADO ($pad_why)"
    else
        say "[+] Mando via SDL: desactivado ($pad_why)"
    fi
    # --- SteamOS / Steam Input -------------------------------------------
    # Steam oculta el mando FISICO a los procesos que lanza (para que usen su
    # mando virtual) con SDL_GAMECONTROLLER_IGNORE_DEVICES*. Si WProton se
    # abre desde Steam, el juego hereda esa ocultacion pero no siempre el
    # mando virtual: SDL no ve ninguno y el mando "no funciona" aunque los
    # menus si lo lean (nosotros leemos /dev/input en crudo).
    if [ "${PAD_STEAMFIX:-1}" = 1 ]; then
        local v val cleared=""
        for v in SDL_GAMECONTROLLER_IGNORE_DEVICES \
                 SDL_GAMECONTROLLER_IGNORE_DEVICES_EXCEPT \
                 SDL_JOYSTICK_HIDAPI_IGNORE_DEVICES \
                 SDL_JOYSTICK_HIDAPI_IGNORE_DEVICES_EXCEPT; do
            eval "val=\${$v:-}"
            if [ -n "$val" ]; then
                unset "$v"
                cleared="$cleared $v"
            fi
        done
        if [ -n "$cleared" ]; then
            say "[+] Mando: quitada la ocultacion de Steam Input ->$cleared"
        fi
        # que SDL busque tambien por evdev clasico, no solo hidapi
        export SDL_JOYSTICK_DISABLE_UDEV="${SDL_JOYSTICK_DISABLE_UDEV:-0}"
    fi
    # NTsync: primitivas de sincronizacion NT dentro del kernel (6.14+).
    # Sustituye a esync/fsync; los runners parcheados la activan con
    # PROTON_USE_NTSYNC=1 (GE-Proton 10-9+, Proton/Wine-CachyOS, DWProton).
    if [ "${NTSYNC:-0}" = 1 ]; then
        if [ -e /dev/ntsync ]; then
            export PROTON_USE_NTSYNC=1 WINENTSYNC=1
            export WINEESYNC=0 WINEFSYNC=0
            say "[+] NTsync activado (/dev/ntsync presente)"
        else
            say "AVISO: NTsync pedido pero no existe /dev/ntsync (kernel <6.14 o"
            say "       modulo sin cargar: sudo modprobe ntsync). Se usara fsync/esync."
        fi
    fi
    # Parametros del autorun.cmd estilo Batocera (ENV= y LANG=)
    if [ -n "${AUTORUN_LANG:-}" ]; then
        export LANG="$AUTORUN_LANG" LC_ALL="$AUTORUN_LANG"
        say "[+] LANG del autorun: $AUTORUN_LANG"
    fi
    if [ -n "${AUTORUN_ENV:-}" ]; then
        say "[+] ENV del autorun: $AUTORUN_ENV"
        # shellcheck disable=SC2163
        eval "export $AUTORUN_ENV"
    fi
    [ "$WAYLAND" = 1 ]    && export PROTON_ENABLE_WAYLAND=1
    [ "$WINED3D" = 1 ]    && export PROTON_USE_WINED3D=1
    [ "$FSR" = 1 ]        && export WINE_FULLSCREEN_FSR=1 WINE_FULLSCREEN_FSR_STRENGTH=2
    [ "$LAA" = 1 ]        && export PROTON_FORCE_LARGE_ADDRESS_AWARE=1
    [ -n "$DLL_OVERRIDES" ] && export WINEDLLOVERRIDES="$DLL_OVERRIDES"
    [ -n "$GAME_LANG" ]     && export LC_ALL="$GAME_LANG" LANG="$GAME_LANG"
    if [ -n "$EXTRA_ENV" ]; then
        # shellcheck disable=SC2086
        export $EXTRA_ENV
    fi
}

build_runner_cmd() {
    local rdir="$1" kind
    kind="$(runner_kind "$rdir")" || die "Runner invalido: $rdir"
    RUN_CMD=()
    local gs_args="$GAMESCOPE"
    if [ -z "$gs_args" ] && [ "${IS_GAMESCOPE:-0}" = 1 ] && [ "${NESTED_GAMESCOPE:-0}" = 1 ]; then
        # Modo Juego con gamescope anidado (opcional, OFF por defecto).
        # Ayuda a que el foco vuelva a los menus al salir del juego, PERO la
        # capa Vulkan del gamescope exterior intenta enganchar un swapchain
        # que ya no controla y el juego avisa de "Hooking has failed
        # somewhere!" con la imagen a tirones. Por eso se desactiva aqui esa
        # capa: es el arreglo documentado para gamescope dentro de gamescope.
        gs_args="-f"
        export ENABLE_GAMESCOPE_WSI=0
        say "[+] Modo Juego: gamescope anidado (capa WSI exterior desactivada)"
    fi
    if [ -n "$gs_args" ] && [ "${IS_GAMESCOPE:-0}" = 1 ] && [ -n "$GAMESCOPE" ]; then
        # gamescope manual dentro del modo Juego: mismo problema de capas
        export ENABLE_GAMESCOPE_WSI=0
    fi
    if [ -n "$gs_args" ] && command -v gamescope >/dev/null 2>&1; then
        # shellcheck disable=SC2206
        RUN_CMD+=(gamescope $gs_args --)
    fi
    [ "$GAMEMODE" = 1 ] && command -v gamemoderun >/dev/null 2>&1 && RUN_CMD+=(gamemoderun)
    if [ "$kind" = "proton" ]; then
        [ -x "$UMU_BIN" ] || die "Falta umu-run (necesario para runners Proton). Ejecuta: $0 --setup"
        export PROTONPATH="$rdir"
        export GAMEID STORE
        RUN_CMD+=("$PY_BIN" "$UMU_BIN")
    else
        local wbin; wbin="$(runner_wine_bin "$rdir")"
        [ -n "$wbin" ] || die "No se encontro bin/wine en $rdir"
        export PATH="$(dirname "$wbin"):$PATH"
        RUN_CMD+=("$wbin")
    fi
    RUNNER_KIND="$kind"
}

launch_game() {
    local squash="$1" mode="${2:-auto}"
    local gid; gid="$(game_id "$squash")"

    # Recordar como "ultimo juego jugado"
    local abs_squash; abs_squash="$(readlink -f "$squash" 2>/dev/null || printf '%s' "$squash")"
    if [ "$abs_squash" != "$LAST_GAME" ]; then
        LAST_GAME="$abs_squash"
        save_settings
    fi

    # Comprobacion rapida de integridad antes de montar (cabecera squashfs)
    if [ -f "$abs_squash" ]; then
        local mg; mg="$(head -c 6 "$abs_squash" 2>/dev/null)"
        case "$mg" in
            hsqs*|sqsh*|DWARFS*) ;;
            *) ui_error "'$(basename "$abs_squash")' no parece una imagen valida
(ni squashfs ni DwarFS). Comprueba el archivo desde:
Configurar juego -> Comprobar integridad"
               return 1 ;;
        esac
    fi

    # En Batocera, la via robusta es su propio lanzador (perfil: USE_BATOCERA)
    if [ "$IS_BATOCERA" = 1 ] && [ -n "$BATOCERA_WINE_BIN" ]; then
        load_profile "$gid"
        if [ "${USE_BATOCERA:-1}" = 1 ]; then
            local kf=""
            if kf="$(find_keys_file "$abs_squash" "$gid")"; then
                mapeador_start "$kf"
            fi
            batocera_play "$abs_squash"
            local brc=$?
            mapeador_stop
            post_game_resettle
            return $brc
        fi
    fi

    mount_game "$squash" "$gid"
    local merged="$MOUNT_POINT"

    BUNDLED_PREFIX_DIR=""
    if has_bundled_prefix "$merged"; then
        BUNDLED_PREFIX_DIR="$merged"
        say "[+] Este wsquashfs incluye un prefix de Wine (estilo Batocera)"
    fi
    BUNDLED_RUNNER_DIR="$(find_bundled_runner "$merged")"
    [ -n "$BUNDLED_RUNNER_DIR" ] && say "[+] Este wsquashfs incluye su propio Wine: $(basename "$BUNDLED_RUNNER_DIR")"

    if ! profile_exists "$gid"; then
        first_run_wizard "$gid" "$merged" || die "Asistente cancelado"
    fi
    load_profile "$gid"
    if [ "${RUNNER:-}" = "bundled" ] && [ -z "$BUNDLED_RUNNER_DIR" ]; then
        say "AVISO: el perfil pide el Wine incluido pero este wsquashfs no lo trae - runner automatico"
        RUNNER=""
    fi
    if [ "$PREFIX_MODE" = "bundled" ]; then
        if [ -z "$BUNDLED_PREFIX_DIR" ]; then
            say "AVISO: el perfil pide el prefix incluido pero este wsquashfs no lo trae - usando el compartido"
            PREFIX_MODE="shared"
        elif [ "$merged" = "$MOUNT_RO" ]; then
            say "AVISO: montaje solo-lectura, el prefix incluido no puede escribirse - usando el compartido"
            PREFIX_MODE="shared"
        fi
    fi

    EXE_PATH=""; EXE_ARGS=""
    if [ -n "$EXE_OVERRIDE" ] && [ -f "$merged/$EXE_OVERRIDE" ] && [ "$mode" = "auto" ]; then
        EXE_PATH="$merged/$EXE_OVERRIDE"; EXE_ARGS="$ARGS_OVERRIDE"
    else
        find_exe "$merged" "$mode" || die "No se selecciono ningun ejecutable"
        [ -n "$ARGS_OVERRIDE" ] && EXE_ARGS="$ARGS_OVERRIDE"
    fi
    say "Ejecutable: $EXE_PATH"
    [ -n "$EXE_ARGS" ] && say "Argumentos: $EXE_ARGS"

    ensure_runner
    local rdir; rdir="$(get_runner_path)"
    [ -z "$rdir" ] && die "No hay runners instalados. Ejecuta: $0 --setup"

    export_game_env "$gid"
    build_runner_cmd "$rdir"
    pad_sdl_prefix_setup "$rdir"
    bundled_prefix_prepare "$rdir"

    pad_bridge_stop   # el mando vuelve a ser del juego, no de los menus
    canvas_say "Jugando: $gid"
    log_input_devices
    local keys_file=""
    if keys_file="$(find_keys_file "$abs_squash" "$gid")"; then
        mapeador_start "$keys_file"
    else
        say "[i] Sin .keys para $gid (buscado: ${abs_squash%.*}.keys | $abs_squash.keys | profiles/$gid.keys)"
    fi
    gamepad_retrigger &
    local trig=$!
    say "Lanzando con $(basename "$rdir") [$RUNNER_KIND] | prefix=$(basename "$WINEPREFIX")"
    local t0; t0=$(date +%s)
    STATS_T0="$t0"
    saves_detect_start
    (
        cd "$(dirname "$EXE_PATH")" || exit 1
        # shellcheck disable=SC2086
        "${RUN_CMD[@]}" "$EXE_PATH" $EXE_ARGS >> "$LOG_FILE" 2>&1
    )
    local rc=$?
    local dur=$(( $(date +%s) - t0 ))
    if [ $rc -ne 0 ] && [ $dur -lt 10 ]; then
        ui_error "El juego fallo al arrancar (rc=$rc en ${dur}s).
Ultimas lineas del log:
$(tail -n 8 "$LOG_FILE")"
    fi
    kill "$trig" 2>/dev/null
    mapeador_stop
    stats_record "$gid" "$(( $(date +%s) - ${STATS_T0:-$(date +%s)} ))"
    saves_detect_end "$gid"
    post_game_resettle
    # Esperar a que el wineserver del prefijo termine ANTES de desmontar:
    # si no, el overlay sigue "ocupado" y tmp_mount no queda vacio
    if [ "$RUNNER_KIND" = "wine" ]; then
        local wsrv; wsrv="$(dirname "$(runner_wine_bin "$rdir")")/wineserver"
        [ -x "$wsrv" ] && "$wsrv" -w 2>/dev/null
    elif [ "$RUNNER_KIND" = "proton" ]; then
        local psrv
        for psrv in "$rdir/files/bin/wineserver" "$rdir/dist/bin/wineserver"; do
            [ -x "$psrv" ] && { "$psrv" -w 2>/dev/null; break; }
        done
    fi
    say "El juego termino (rc=$rc). Saves conservados en wsquashfs/overlays/$gid/upper/"
    cleanup_mount
    return $rc
}

self_update() {
    local SELF; SELF="$(readlink -f "$0")"
    if [ -z "$WPROTON_REPO" ]; then
        ui_info "Auto-actualizacion sin configurar todavia.
Cuando WProton este en GitHub, edita WPROTON_REPO en la cabecera
del script (formato usuario/repo)."
        return 0
    fi
    say "Comprobando actualizaciones (actual: v$WPROTON_VERSION)..."
    local remote=""
    remote="$(curl -fsSL "https://api.github.com/repos/$WPROTON_REPO/releases/latest" 2>/dev/null \
        | grep -o '"tag_name": *"[^"]*"' | cut -d'"' -f4 | sed 's/^v//')"
    if [ -z "$remote" ]; then
        # sin releases: leer la version de la rama main
        remote="$(curl -fsSL "https://raw.githubusercontent.com/$WPROTON_REPO/main/wproton.sh" 2>/dev/null \
            | grep -m1 '^WPROTON_VERSION=' | cut -d'"' -f2)"
    fi
    [ -z "$remote" ] && { ui_error "No se pudo consultar la version en GitHub ($WPROTON_REPO)"; return 1; }
    # Nomenclatura decimal: 0.5 < 0.51 < 0.52 < 0.6 < 1.0 (sort -V NO vale aqui)
    if ! awk -v a="$WPROTON_VERSION" -v b="$remote" 'BEGIN{exit !(b+0 > a+0)}'; then
        ui_info "WProton esta al dia (v$WPROTON_VERSION; remota: v$remote)"
        return 0
    fi
    ui_ask "Hay una version nueva: v$remote (actual v$WPROTON_VERSION).
Descargar y actualizar ahora?" || return 0
    local tmp; tmp="$(mktemp)"
    local url_rel="https://github.com/$WPROTON_REPO/releases/download/v$remote/wproton.sh"
    local url_tag="https://raw.githubusercontent.com/$WPROTON_REPO/v$remote/wproton.sh"
    local url_main="https://raw.githubusercontent.com/$WPROTON_REPO/main/wproton.sh"
    if ! curl -fsSL "$url_rel" -o "$tmp" 2>/dev/null; then
        curl -fsSL "$url_tag" -o "$tmp" 2>/dev/null || curl -fsSL "$url_main" -o "$tmp" 2>/dev/null \
            || { rm -f "$tmp"; ui_error "Fallo la descarga de v$remote"; return 1; }
    fi
    # Validar antes de tocar nada: sintaxis + que es WProton de verdad
    if ! bash -n "$tmp" 2>>"$LOG_FILE" || ! grep -q '^WPROTON_VERSION=' "$tmp"; then
        rm -f "$tmp"
        ui_error "El fichero descargado no valida (sintaxis o formato). No se actualiza."
        return 1
    fi
    cp -f "$SELF" "$SELF.bak"
    cat "$tmp" > "$SELF" && chmod +x "$SELF"
    rm -f "$tmp"
    say "[OK] Actualizado a v$remote (copia anterior en $(basename "$SELF").bak)"
    if ui_ask "Actualizado a v$remote.
Reiniciar WProton ahora?"; then
        cleanup_all
        exec "$SELF"
    fi
}

# ----------------------------------------------------------------------------
# 4g. PERFILES DE LA COMUNIDAD
#     Carpeta profiles/ del repositorio: configuraciones ya probadas para
#     juegos problematicos (argumentos raros, runner concreto, prefix
#     incluido...). Se descargan al profiles/ local sin pisar nada sin avisar.
# ----------------------------------------------------------------------------
community_list() {
    # Lista los .conf de la carpeta profiles/ del repo (API de GitHub)
    curl -fsSL "https://api.github.com/repos/$WPROTON_REPO/contents/profiles" 2>/dev/null \
        | grep -o '"name": *"[^"]*\.conf"' | cut -d'"' -f4 | sort
}

community_fetch() {
    # $1 = nombre del .conf -> lo trae a profiles/ (preguntando si ya existe)
    local name="$1" dest="$PROFILE_DIR/$name" tmp
    tmp="$(mktemp)"
    local url="https://raw.githubusercontent.com/$WPROTON_REPO/main/profiles/$name"
    if ! dl "$url" "$tmp"; then
        rm -f "$tmp"; ui_error "No se pudo descargar $name"; return 1
    fi
    # seguridad: un perfil es solo CLAVE=valor, nada de ordenes
    if grep -qE '^[[:space:]]*(#|[A-Z_]+=)' "$tmp" && \
       ! grep -qE '`|\$\(|;[[:space:]]*[a-z]+ |^[[:space:]]*(rm|curl|wget|bash|sh|eval) ' "$tmp"; then
        :
    else
        rm -f "$tmp"
        ui_error "El perfil descargado tiene contenido raro y se ha descartado."
        return 1
    fi
    if [ -f "$dest" ]; then
        ui_ask "Ya tienes un perfil para este juego:
$name

Sustituirlo por el de la comunidad?
(se guardara el tuyo como $name.bak)" || { rm -f "$tmp"; return 1; }
        cp -f "$dest" "$dest.bak"
    fi
    mkdir -p "$PROFILE_DIR"
    cat "$tmp" > "$dest"
    rm -f "$tmp"
    local notas; notas="$(grep -m1 '^NOTAS=' "$dest" | cut -d= -f2- | tr -d '"')"
    ui_info "Perfil instalado: $name
${notas:+
Notas del autor: $notas}"
    return 0
}

community_share() {
    # $1 = gid: prepara el perfil para enviarlo al repositorio
    local gid="$1" src="$PROFILE_DIR/$gid.conf" out
    [ -f "$src" ] || { ui_error "Este juego no tiene perfil todavia"; return 1; }
    mkdir -p "$BASE_DIR/compartir"
    out="$BASE_DIR/compartir/$gid.conf"
    # se quitan rutas y datos locales: solo lo que sirve a otros
    grep -vE '^(LAST_PLAYED|PLAY_COUNT|PLAY_SECONDS|FAVORITO|EXE_OVERRIDE)=' "$src" > "$out"
    ui_info "Perfil listo para compartir:

compartir/$gid.conf

Subelo a la carpeta profiles/ del repositorio (pull request).
Se han quitado tus estadisticas y rutas locales."
    return 0
}

community_menu() {
    local list sel
    if [ -z "${WPROTON_REPO:-}" ]; then
        ui_info "No hay repositorio configurado (WPROTON_REPO)."
        return 1
    fi
    say "Consultando perfiles de la comunidad..."
    list="$(community_list)"
    if [ -z "$list" ]; then
        ui_info "No se pudieron leer los perfiles del repositorio.
Comprueba la conexion o que exista la carpeta profiles/ en:
$WPROTON_REPO"
        return 1
    fi
    while true; do
        # shellcheck disable=SC2046
        sel="$(IFS=$'\n'; set -f; menu "Perfiles de la comunidad ($(printf '%s\n' "$list" | grep -c .) disponibles)" $list "<< Volver")" || return
        case "$sel" in
            "<< Volver"|"") return ;;
            *) community_fetch "$sel" ;;
        esac
    done
}

redist_target_menu() {
    # Desde el menu principal: elegir en QUE prefijo instalar las librerias
    local t
    t="$(menu "Instalar librerias - elige el prefijo destino" \
        "Prefijo compartido (default) - lo usan todos los juegos en modo compartido" \
        "Prefijo de un juego concreto (elegir juego)" \
        "<< Volver")" || return
    case "$t" in
        "Prefijo compartido"*)
            load_profile "__wp_default__"   # inexistente -> defaults (shared)
            redist_menu "" "default" ;;
        "Prefijo de un juego"*)
            local g gid2
            g="$(pick_squash)" || return
            g="${g#WPACT:CONFIG|}"
            gid2="$(game_id "$g")"
            load_profile "$gid2"
            redist_menu "$g" "$gid2" ;;
    esac
}

redist_menu() {
    # Multi-seleccion de redistribuibles e instalacion via winetricks en el
    # prefijo del juego (idea tomada del sistema de redist de Batocera)
    local squash="$1" gid="$2"
    if ! pygame_available; then
        ui_info "La seleccion de redistribuibles necesita los menus pygame (--setup)"
        return 1
    fi
    pad_bridge_stop
    write_menu_pygame
    local tmpsel tmpopt; tmpsel="$(mktemp)"; tmpopt="$(mktemp)"
    cat > "$tmpopt" <<'EOF'
1|vcrun2022 (VC++ 2015-2022, el mas comun)
0|vcrun2013 (VC++ 2013)
0|vcrun2012 (VC++ 2012)
0|vcrun2010 (VC++ 2010)
0|vcrun2008 (VC++ 2008)
0|vcrun2005 (VC++ 2005)
0|d3dx9 (DirectX 9 - D3DX)
0|d3dcompiler_47 (compilador de shaders D3D)
0|physx (NVIDIA PhysX)
0|ue4prereqs (Prerrequisitos Unreal Engine - pack)
0|xact (XACT/XAudio, juegos viejos)
0|mf (Media Foundation - videos in-game)
0|dotnet48 (.NET 4.8 - instalacion LENTA)
EOF
    PYGAME_HIDE_SUPPORT_PROMPT=1 SDL_JOYSTICK_ALLOW_BACKGROUND_EVENTS=1 \
        env -u LD_PRELOAD "$PY_BIN" "$MENU_PYGAME_PY" check "Redistribuibles para $gid (X marca, A instala)" \
        "$tmpsel" "$tmpopt" >> "$LOG_FILE" 2>&1
    local rc=$? sel; sel="$(cat "$tmpsel")"; rm -f "$tmpsel" "$tmpopt"
    [ $rc -ne 0 ] && return 1
    local verbs; verbs="$(printf '%s' "$sel" | tr '|' '\n' | awk 'NF{print $1}' | tr '\n' ' ')"
    verbs="${verbs% }"
    # "ue4prereqs" no es un verbo de winetricks: expandir al pack equivalente
    # al UE4PrereqSetup (VC++ moderno + shaders D3D + XAudio)
    case " $verbs " in *" ue4prereqs "*)
        verbs="$(printf '%s' " $verbs " | sed 's/ ue4prereqs / vcrun2022 d3dcompiler_47 d3dx11_43 xact /')"
        verbs="$(printf '%s' "$verbs" | tr ' ' '\n' | awk 'NF' | awk '!seen[$0]++' | tr '\n' ' ')"
        verbs="${verbs% }"; verbs="${verbs# }" ;;
    esac
    [ -z "$verbs" ] && { say "Sin redistribuibles seleccionados"; return 0; }
    say "Instalando redistribuibles en el prefijo: $verbs"
    # shellcheck disable=SC2086
    run_with_progress "Instalando: $verbs ..." \
        run_in_prefix_quiet "$squash" "$gid" $verbs
    ui_info "Redistribuibles procesados: $verbs
Revisa el ultimo log si algo fallo."
}

run_in_prefix_quiet() {
    # winetricks -q con verbos (sin GUI) en el prefijo del juego
    local squash="$1" gid="$2"; shift 2
    run_in_prefix "$squash" "$gid" winetricks -q "$@"
}

run_in_prefix() {
    # Herramienta (winecfg, winetricks...) en el prefijo del juego
    # $1 = wsquashfs (para poder montar si el prefix es el incluido), $2 = gid
    local squash="$1" gid="$2"; shift 2
    load_profile "$gid"
    local mounted_here=0
    BUNDLED_PREFIX_DIR=""
    if [ "$PREFIX_MODE" = "bundled" ] || [ "${RUNNER:-}" = "bundled" ]; then
        acquire_game_root "$squash" "$gid" rw
        if [ "$PREFIX_MODE" = "bundled" ]; then
            if has_bundled_prefix "$MOUNT_POINT"; then
                BUNDLED_PREFIX_DIR="$MOUNT_POINT"
            else
                say "AVISO: el juego no incluye prefix - usando el compartido"
            fi
        fi
        if [ "${RUNNER:-}" = "bundled" ]; then
            BUNDLED_RUNNER_DIR="$(find_bundled_runner "$MOUNT_POINT")"
            [ -z "$BUNDLED_RUNNER_DIR" ] && { say "AVISO: sin Wine incluido - runner automatico"; RUNNER=""; }
        fi
        mounted_here=1
    fi
    local rdir; rdir="$(get_runner_path)"
    [ -z "$rdir" ] && die "No hay runners instalados. Ejecuta: $0 --setup"
    export_game_env "$gid"
    build_runner_cmd "$rdir"
    pad_bridge_stop
    if [ "$RUNNER_KIND" = "wine" ] && [ "$1" = "winetricks" ]; then
        command -v winetricks >/dev/null 2>&1 || { ui_info "winetricks no esta instalado en el host"; return 1; }
        WINE="$(runner_wine_bin "$rdir")" winetricks "${@:2}" >> "$LOG_FILE" 2>&1
    else
        "${RUN_CMD[@]}" "$@" >> "$LOG_FILE" 2>&1
    fi
    [ "$mounted_here" = 1 ] && release_game_root
    return 0
}

bundled_prefix_prepare() {
    # Los prefijos que vienen dentro de un wsquashfs de Batocera traen DXVK (y
    # a veces otras DLLs) instalado como ENLACES SIMBOLICOS a rutas del propio
    # Batocera (/usr/wine/..., /userdata/...). En otra maquina esos enlaces
    # apuntan a la nada: Wine ve que el fichero "existe" (wineboot falla con
    # error=80, ERROR_FILE_EXISTS) pero no puede cargarlo y el juego muere con
    # "Library dxgi.dll not found". Batocera los reinstala al lanzar; nosotros
    # los borramos y dejamos que wineboot recree las DLLs del propio runner.
    [ "$PREFIX_MODE" = "bundled" ] || return 0
    [ -n "${BUNDLED_PREFIX_DIR:-}" ] || return 0
    local rdir="$1"
    local probe="$WINEPREFIX/.wp_write_test"
    if ! ( : > "$probe" ) 2>/dev/null; then
        say "AVISO: el prefix incluido NO es escribible; el juego puede fallar."
        say "       Cambia el prefijo a 'propio' o 'compartido' en Configurar."
        return 0
    fi
    rm -f "$probe"

    # 1) Enlaces rotos en system32/syswow64 (y en la raiz del prefijo)
    local dirs d broken n=0 first=""
    dirs="$WINEPREFIX/drive_c/windows/system32 $WINEPREFIX/drive_c/windows/syswow64"
    for d in $dirs; do
        [ -d "$d" ] || continue
        while IFS= read -r broken; do
            [ -n "$broken" ] || continue
            [ -z "$first" ] && first="$(readlink "$broken" 2>/dev/null)"
            rm -f "$broken" 2>/dev/null && n=$((n+1))
        done <<EOF2
$(find "$d" -maxdepth 1 -xtype l 2>/dev/null)
EOF2
    done
    if [ "$n" -gt 0 ]; then
        say "[+] Prefix incluido: $n enlaces rotos eliminados (DXVK de Batocera)"
        [ -n "$first" ] && say "    apuntaban a: $first"
        rm -f "$WINEPREFIX/.wp_bundled_ready"
    fi

    [ -f "$WINEPREFIX/.wp_bundled_ready" ] && return 0

    # 2) wineboot para que Wine reponga sus propias DLLs (d3d9/d3d11/dxgi...)
    local wbin; wbin="$(runner_wine_bin "$rdir" 2>/dev/null)"
    if [ -n "$wbin" ] && [ -x "$wbin" ]; then
        say "[+] Actualizando el prefix incluido (wineboot)..."
        "$wbin" wineboot -u >> "$LOG_FILE" 2>&1
        local wsrv="$(dirname "$wbin")/wineserver"
        [ -x "$wsrv" ] && "$wsrv" -w 2>/dev/null
    fi

    # 2b) Reinstalar DXVK desde el propio runner (es lo que hace Batocera al
    #     lanzar). Si el runner no lo trae, Wine tirara de WineD3D.
    local cand dxvk64="" dxvk32=""
    for cand in "$rdir/lib/wine/dxvk" "$rdir/lib64/wine/dxvk" \
                "$rdir/files/lib/wine/dxvk" "$rdir/dist/lib/wine/dxvk" \
                "$rdir/lib/wine/x86_64-windows" "$rdir/files/lib/wine/x86_64-windows"; do
        [ -d "$cand" ] && [ -f "$cand/dxgi.dll" ] && { dxvk64="$cand"; break; }
    done
    for cand in "$rdir/lib32/wine/dxvk" "$rdir/lib/wine/i386-windows" \
                "$rdir/files/lib/wine/i386-windows"; do
        [ -d "$cand" ] && [ -f "$cand/dxgi.dll" ] && { dxvk32="$cand"; break; }
    done
    if [ -n "$dxvk64" ]; then
        local lib
        for lib in dxgi.dll d3d9.dll d3d10core.dll d3d11.dll d3d12.dll; do
            [ -f "$dxvk64/$lib" ] && cp -f "$dxvk64/$lib" \
                "$WINEPREFIX/drive_c/windows/system32/$lib" 2>/dev/null
        done
        [ -n "$dxvk32" ] && [ -d "$WINEPREFIX/drive_c/windows/syswow64" ] && \
            for lib in dxgi.dll d3d9.dll d3d10core.dll d3d11.dll; do
                [ -f "$dxvk32/$lib" ] && cp -f "$dxvk32/$lib" \
                    "$WINEPREFIX/drive_c/windows/syswow64/$lib" 2>/dev/null
            done
        say "[+] DLLs de Direct3D repuestas desde el runner"
    fi

    # 3) Comprobacion: si aun faltan las DLLs de Direct3D, avisar con salida
    local miss="" lib
    for lib in dxgi.dll d3d9.dll d3d11.dll; do
        [ -e "$WINEPREFIX/drive_c/windows/system32/$lib" ] || miss="$miss $lib"
    done
    if [ -n "$miss" ]; then
        say "AVISO: el prefix incluido sigue sin:$miss"
        say "       Prueba con prefijo 'propio' o instala DXVK desde el menu"
        say "       'Instalar librerias' del menu principal."
    else
        touch "$WINEPREFIX/.wp_bundled_ready" 2>/dev/null
    fi
    return 0
}

pad_sdl_auto() {
    # Decide si conviene el backend SDL de Proton segun el mando conectado:
    #  - Sony/Nintendo (DualSense, DS4, Pro Controller...): SI, porque fuera
    #    de Steam llegan por hidraw y los juegos solo-XInput no los ven.
    #  - XInput integrados (Steam Deck, Legion Go, ROG Ally, Xbox...): NO,
    #    ya son XInput nativo y forzar SDL les estorba.
    # Imprime "valor|motivo": el motivo NO puede ir en una variable global
    # porque esta funcion se llama dentro de $( ) y ahi todo es un subshell.
    local names sony=0 xin=0
    if [ ! -r /proc/bus/input/devices ]; then
        printf '0|sin informacion de dispositivos'; return
    fi
    names="$(awk '/^N: Name=/{n=tolower($0)} /^H: Handlers=.*js/{print n}' \
             /proc/bus/input/devices 2>/dev/null)"
    printf '%s\n' "$names" | grep -qE 'dualsense|dualshock|wireless controller|sony|playstation|nintendo|pro controller|joy-?con|switch' && sony=1
    printf '%s\n' "$names" | grep -qE 'x-?box|steam deck|steam virtual|legion|rog ally|claw|ayaneo|gpd|onexplayer|xinput' && xin=1
    if [ "$sony" = 1 ]; then
        printf '1|mando Sony/Nintendo detectado'
    elif [ "$xin" = 1 ]; then
        printf '0|mando XInput nativo'
    else
        printf '0|sin mandos Sony detectados'
    fi
}

pad_sdl_effective() {
    # solo el valor (0/1)
    case "${PAD_SDL:-auto}" in
        1) printf '1' ;;
        0) printf '0' ;;
        *) local r; r="$(pad_sdl_auto)"; printf '%s' "${r%%|*}" ;;
    esac
}

pad_sdl_prefix_setup() {
    # Para runners Wine puro: activar el backend SDL de winebus en el registro
    # (equivalente a lo que hace PortProton; en Proton basta la variable)
    # $1 = dir del runner
    [ "$(pad_sdl_effective)" = 1 ] || return 0
    [ "$RUNNER_KIND" = "wine" ] || return 0
    [ -f "$WINEPREFIX/.wp_pad_sdl" ] && return 0
    local wbin; wbin="$(runner_wine_bin "$1")"
    [ -n "$wbin" ] || return 0
    say "[+] Configurando winebus (mando via SDL) en el prefijo..."
    "$wbin" reg add 'HKLM\System\CurrentControlSet\Services\winebus' \
        /v 'Enable SDL' /t REG_DWORD /d 1 /f >> "$LOG_FILE" 2>&1
    "$wbin" reg add 'HKLM\System\CurrentControlSet\Services\winebus' \
        /v 'DisableHidraw' /t REG_DWORD /d 1 /f >> "$LOG_FILE" 2>&1 \
        && touch "$WINEPREFIX/.wp_pad_sdl"
}

run_exe_in_game() {
    # Ejecuta un .exe (Cpl de dgVoodoo, etc.) dentro del overlay montado
    local squash="$1" gid="$2" exe_rel="$3"
    load_profile "$gid"
    mount_game "$squash" "$gid"
    local merged="$MOUNT_POINT"
    local target="$merged/$exe_rel"
    [ -f "$target" ] || { ui_error "No existe: $exe_rel"; release_game_root; return 1; }
    local rdir; rdir="$(get_runner_path)"
    export_game_env "$gid"
    build_runner_cmd "$rdir"
    pad_bridge_stop
    ( cd "$(dirname "$target")" && "${RUN_CMD[@]}" "$target" >> "$LOG_FILE" 2>&1 )
    release_game_root
}

# ----------------------------------------------------------------------------
# 14. EXTRAS ESTILO PORTPROTON: dgVoodoo2 y OptiScaler
#     Se instalan DENTRO del overlay: los ficheros van a upper/ y persisten
#     sin tocar el wsquashfs original.
# ----------------------------------------------------------------------------
merge_overrides() {
    # Anade $1 a DLL_OVERRIDES sin duplicar
    case "$DLL_OVERRIDES" in
        *"$1"*) : ;;
        "")     DLL_OVERRIDES="$1" ;;
        *)      DLL_OVERRIDES="$DLL_OVERRIDES;$1" ;;
    esac
}

need_exe_dir() {
    # Garantiza EXE_OVERRIDE definido; imprime el dir (relativo) del exe
    local root="$1" gid="$2"
    if [ -z "$EXE_OVERRIDE" ]; then
        ui_info "Primero hay que fijar el ejecutable del juego"
        wizard_pick_exe "$root" || return 1
        [ -z "$EXE_OVERRIDE" ] && { ui_error "dgVoodoo/OptiScaler necesitan un exe fijo (no automatico)"; return 1; }
        write_full_profile "$gid"
    fi
    dirname "$EXE_OVERRIDE"
}

install_dgvoodoo() {
    local squash="$1" gid="$2"
    load_profile "$gid"
    acquire_game_root "$squash" "$gid" rw
    local merged="$MOUNT_POINT"
    local exedir; exedir="$(need_exe_dir "$merged" "$gid")" || { release_game_root; return 1; }
    local target="$merged/$exedir"

    local pkg="$DL_DIR/dgvoodoo2.zip"
    if [ ! -f "$pkg" ]; then
        local url
        url="$(gh_latest_asset "dege-diosg/dgVoodoo2" '\.zip$' | grep -iv dbg | head -n1)"
        [ -z "$url" ] && { ui_error "No se encontro dgVoodoo2 en GitHub"; release_game_root; return 1; }
        dl "$url" "$pkg" || { ui_error "Fallo descargando dgVoodoo2"; rm -f "$pkg"; release_game_root; return 1; }
    fi
    local tmp; tmp="$(mktemp -d)"
    extract_archive "$pkg" "$tmp" || { ui_error "Fallo extrayendo dgVoodoo2"; rm -rf "$tmp"; release_game_root; return 1; }

    # DLLs x86 (D3D8, D3D9, DDraw, D3DImm) junto al exe + panel de control
    find "$tmp" -ipath '*MS/x86/*.dll' -exec cp {} "$target/" \;
    find "$tmp" -maxdepth 2 -iname 'dgVoodooCpl.exe' -exec cp {} "$target/" \;
    find "$tmp" -maxdepth 2 -iname 'dgVoodoo.conf' -exec cp {} "$target/" \;
    rm -rf "$tmp"

    merge_overrides "d3d8,d3d9,d3dimm,ddraw=n,b"
    write_full_profile "$gid"
    release_game_root
    ui_info "dgVoodoo2 instalado junto al exe (persistente en upper/).
DLL overrides actualizados: $DLL_OVERRIDES
Configuralo con la opcion 'Configurar dgVoodoo (Cpl)'"
}

install_optiscaler() {
    local squash="$1" gid="$2"
    load_profile "$gid"
    acquire_game_root "$squash" "$gid" rw
    local merged="$MOUNT_POINT"
    local exedir; exedir="$(need_exe_dir "$merged" "$gid")" || { release_game_root; return 1; }
    local target="$merged/$exedir"

    local url pkg
    url="$(gh_latest_asset "optiscaler/OptiScaler" '\.(7z|zip)$')"
    [ -z "$url" ] && { ui_error "No se encontro OptiScaler en GitHub"; release_game_root; return 1; }
    pkg="$DL_DIR/$(basename "$url")"
    if [ ! -f "$pkg" ]; then
        dl "$url" "$pkg" || { ui_error "Fallo descargando OptiScaler"; rm -f "$pkg"; release_game_root; return 1; }
    fi
    local tmp; tmp="$(mktemp -d)"
    extract_archive "$pkg" "$tmp" || { ui_error "Fallo extrayendo (se necesita 7z o bsdtar)"; rm -rf "$tmp"; release_game_root; return 1; }

    local dll; dll="$(find "$tmp" -iname 'OptiScaler.dll' | head -n1)"
    [ -z "$dll" ] && { ui_error "OptiScaler.dll no encontrado en el paquete"; rm -rf "$tmp"; release_game_root; return 1; }
    cp "$dll" "$target/dxgi.dll"
    find "$tmp" -iname 'OptiScaler.ini' -exec cp {} "$target/" \;
    rm -rf "$tmp"

    merge_overrides "dxgi=n,b"
    write_full_profile "$gid"
    release_game_root
    ui_info "OptiScaler instalado como dxgi.dll junto al exe (persistente en upper/).
DLL overrides actualizados: $DLL_OVERRIDES
Ajustes finos: edita OptiScaler.ini o pulsa Insert dentro del juego."
}

config_dgvoodoo_cpl() {
    local squash="$1" gid="$2"
    load_profile "$gid"
    [ -z "$EXE_OVERRIDE" ] && { ui_error "Fija primero el ejecutable del juego"; return 1; }
    run_exe_in_game "$squash" "$gid" "$(dirname "$EXE_OVERRIDE")/dgVoodooCpl.exe"
}

# ----------------------------------------------------------------------------
# 14b. IMPORTAR JUEGOS -> WSQUASHFS (logica del PortProton antiguo)
#      * zip/7z/rar (multiparte .001/.partN.rar/.rNN/.z01): extraer con 7z,
#        purgar los archivos originales tras extraer con exito, empaquetar
#      * .exe: detectar raiz real (Unreal Binaries/WinXX, Win64, Unity _Data),
#        empaquetar la carpeta y borrar la original
#      * carpeta: empaquetar (o lanzar .sh si lo contiene)
#      Salida siempre: $GAMES_PATH/<Nombre>.wsquashfs  (zstd -b 1M)
# ----------------------------------------------------------------------------
ARCHIVE_REGEX='\.(zip|7z|rar|wtgz)(\.001)?$|\.part[0-9]+\.rar$|\.r[0-9]{2}$|\.z01$'

need_mksquashfs() {
    command -v mksquashfs >/dev/null 2>&1 && return 0
    die "Falta mksquashfs (paquete squashfs-tools):
CachyOS: sudo pacman -S squashfs-tools"
}

clean_game_name() {
    # Limpieza de nombres de release (v1.2, builds, grupos, [2020]...)
    printf '%s' "$1" \
        | sed 's/\.part[0-9][0-9]*$//; s/\.r[0-9][0-9]$//' \
        | sed 's/[-_ ]*[vV][0-9][0-9]*\(\.[0-9][0-9]*\)*[[:alnum:]_.]*//g' \
        | sed 's/[-_ ]*[Bb]uild[0-9][0-9]*\(\.[0-9][0-9]*\)*[[:alnum:]_.]*//g' \
        | sed 's/[-_ ]*\(P2P\|CODEX\|SKIDROW\|REPACK\|FitGirl\|GOG\|DODI\|KaOs\|RAZOR\|CPY\|PLAZA\|FLT\|TENOKE\|TiNYiSO\|EMPRESS\|ElAmigos\|DAZA\|DARKSiDERS\)//gi' \
        | sed 's/[-_ ]*\[[0-9]\{4\}\][-_ ]*/ /g' \
        | sed 's/[-_ ]*([0-9]\{4\})[-_ ]*/ /g' \
        | sed 's/[-_.]*$//' \
        | sed 's/  */ /g; s/^ //; s/ $//'
}

build_wsquashfs() {
    # Empaqueta una carpeta en el formato elegido (PACK_FORMAT):
    #   wsquashfs -> mksquashfs (compatible con Batocera y PortProton)
    #   dwarfs    -> mkdwarfs   (comprime bastante mas, monta igual de rapido)
    local src="$1" name="$2"
    local fmt="${PACK_FORMAT:-wsquashfs}" out
    if [ "$fmt" = "dwarfs" ]; then
        find_dwarfs_tools
        if [ -z "$MKDWARFS_BIN" ]; then
            say "Falta mkdwarfs: descargando las herramientas DwarFS..."
            setup_dwarfs_tools || {
                say "AVISO: sin DwarFS; se empaqueta en wsquashfs"
                fmt="wsquashfs"
            }
        fi
    fi
    [ "$fmt" = "dwarfs" ] && out="$GAMES_PATH/${name}.dwarfs" || out="$GAMES_PATH/${name}.wsquashfs"
    local need; need="$(dir_bytes "$src")"
    if [ -n "$need" ] && ! check_space "$(( need * 7 / 10 ))" "$GAMES_PATH" "empaquetar '$name'"; then
        return 1
    fi
    if [ "$fmt" = "dwarfs" ]; then
        # -l7: buen equilibrio; zstd por defecto = montaje y lectura rapidos
        run_with_progress "Empaquetando '$name' a DwarFS (puede tardar)..." \
            "$MKDWARFS_BIN" -i "$src" -o "$out" -l7 --log-level=warn \
            || { rm -f "$out"; die "mkdwarfs fallo"; }
    else
        need_mksquashfs
        run_with_progress "Empaquetando '$name' a wsquashfs (zstd, puede tardar)..." \
            mksquashfs "$src" "$out" -comp zstd -b 1M -noappend \
            || { rm -f "$out"; die "mksquashfs fallo"; }
    fi
    rm -rf "${OVERLAY_BASE:?}/${name}"
    printf '%s' "$out"
}

PACKED_OUT=""

do_pack_dir() {
    # Empaqueta la carpeta y pregunta el borrado. NO lanza (decide el llamador).
    # Deja la ruta resultante en PACKED_OUT.
    local dir="$1" name="$2" out
    out="$(build_wsquashfs "$dir" "$name")"
    if [ -n "$out" ] && [ -s "$out" ]; then
        say "[OK] Empaquetado: $out"
        if ui_ask "Borrar la carpeta original?
$(basename "$dir")
(empaquetado con exito en $(basename "$GAMES_PATH"))"; then
            say "[+] Eliminando carpeta original: $dir"
            rm -rf "$dir"
        else
            say "[+] Carpeta original conservada: $dir"
        fi
        PACKED_OUT="$out"
        return 0
    fi
    die "El empaquetado fallo; la carpeta original se conserva"
}

offer_test_then_pack() {
    # Bucle probar/empaquetar: ideal para mods (probar N veces sin comprimir).
    # $1 = raiz (carpeta), $2 = exe absoluto, $3 = nombre
    local root="$1" exe="$2" name="$3" sel
    while true; do
        sel="$(menu "Juego en carpeta: $name" \
            "Probar el juego (sin empaquetar)" \
            "Configurar (runner, prefijo, opciones)" \
            "Empaquetar a wsquashfs" \
            "<< Cancelar")" || return 1
        case "$sel" in
            "Configurar"*)
                # Cambiar runner/prefijo/opciones y volver aqui para reprobar
                game_config_menu "$root" "$(printf '%s' "$name" | tr ' /' '__')"
                continue ;;
            "Probar"*)
                say "[+] Probando '$name' desde la carpeta (sin empaquetar)..."
                launch_loose_exe "$name" "$exe"
                say "[+] Prueba terminada (rc=$?)"
                if ui_ask "Prueba terminada.
Empaquetar '$name' a wsquashfs ahora?
(No = volver al menu para cambiar el runner o seguir probando)"; then
                    do_pack_dir "$root" "$name" || return 1
                    return 0
                fi ;;
            "Empaquetar"*)
                do_pack_dir "$root" "$name" || return 1
                return 0 ;;
            *) return 1 ;;
        esac
    done
}




INNOEXTRACT_BIN=""
find_innoextract() {
    INNOEXTRACT_BIN=""
    if [ -x "$RUNTIME_DIR/tools/innoextract" ]; then INNOEXTRACT_BIN="$RUNTIME_DIR/tools/innoextract"
    elif [ -x "$BASE_DIR/innoextract" ]; then INNOEXTRACT_BIN="$BASE_DIR/innoextract"
    elif command -v innoextract >/dev/null 2>&1; then INNOEXTRACT_BIN="$(command -v innoextract)"
    else return 1; fi
}

setup_innoextract() {
    # innoextract PORTABLE: binario estatico oficial (incluye amd64, i686 y
    # ARM) en runtime/tools. Nada de depender del paquete del sistema.
    find_innoextract && [ -n "$INNOEXTRACT_BIN" ] && \
        case "$INNOEXTRACT_BIN" in "$RUNTIME_DIR"/*|"$BASE_DIR"/innoextract) return 0 ;; esac
    mkdir -p "$RUNTIME_DIR/tools"
    local tmp="$RUNTIME_DIR/downloads/innoextract_dl"
    rm -rf "$tmp"; mkdir -p "$tmp"
    local urls url tgz=""
    say "[innoextract] buscando binario estatico..."
    urls="$(curl -fsSL "https://api.github.com/repos/dscharrer/innoextract/releases/latest" 2>/dev/null \
        | grep -o '"browser_download_url": *"[^"]*"' | cut -d'"' -f4 | grep -i 'linux' | grep -iE '\.tar\.(xz|gz|bz2)$')"
    urls="$urls
https://constexpr.org/innoextract/files/innoextract-1.9-linux.tar.xz"
    while IFS= read -r url; do
        [ -n "$url" ] || continue
        say "[innoextract] probando: $(basename "$url")"
        if dl "$url" "$tmp/$(basename "$url")"; then
            tgz="$tmp/$(basename "$url")"
            extract_archive "$tgz" "$tmp" >>"$LOG_FILE" 2>&1 && break
            tgz=""
        fi
    done <<EOF2
$urls
EOF2
    if [ -z "$tgz" ]; then
        rm -rf "$tmp"
        ui_error "No se pudo descargar innoextract.
Puedes bajar innoextract-1.9-linux.tar.xz de constexpr.org/innoextract
y dejar el binario 'innoextract' junto a wproton.sh"
        return 1
    fi
    # El tarball trae binarios para varias arquitecturas: probamos cual corre
    local c
    while IFS= read -r c; do
        [ -n "$c" ] || continue
        chmod +x "$c" 2>/dev/null
        if "$c" --version >/dev/null 2>&1; then
            cp -f "$c" "$RUNTIME_DIR/tools/innoextract"
            chmod +x "$RUNTIME_DIR/tools/innoextract"
            INNOEXTRACT_BIN="$RUNTIME_DIR/tools/innoextract"
            rm -rf "$tmp"
            say "[innoextract] listo: $("$INNOEXTRACT_BIN" --version 2>&1 | head -n1)"
            return 0
        fi
    done <<EOF3
$(find "$tmp" -type f -name 'innoextract*' ! -name '*.txt' ! -name '*.md' 2>/dev/null)
EOF3
    rm -rf "$tmp"
    ui_error "El innoextract descargado no funciona en esta maquina"
    return 1
}

INNOUNP_DIR="$RUNTIME_DIR/tools/innounp"

find_innounp() {
    INNOUNP_EXE="$(find "$INNOUNP_DIR" -maxdepth 2 -type f -iname 'innounp*.exe' 2>/dev/null | head -n1)"
    [ -n "$INNOUNP_EXE" ]
}

setup_innounp() {
    # innounp-2 (jrathlev): unpacker YA COMPILADO que soporta Inno Setup
    # hasta 6.7 (innoextract se quedo en la 6.1 de su release de 2020).
    # Es un .exe de Windows, pero tenemos Wine: no hay que compilar nada.
    find_innounp && return 0
    mkdir -p "$INNOUNP_DIR"
    local tmp="$RUNTIME_DIR/downloads/innounp_dl"
    rm -rf "$tmp"; mkdir -p "$tmp"
    local urls url ok=1
    say "[innounp] buscando descarga en GitHub..."
    # 1) assets de la ultima release
    urls="$(curl -fsSL "https://api.github.com/repos/jrathlev/InnoUnpacker-Windows-GUI/releases/latest" 2>/dev/null \
        | grep -o '"browser_download_url": *"[^"]*"' | cut -d'"' -f4)"
    # 2) ficheros sueltos del repo (carpetas distribution/ e innounp-2/)
    local d
    for d in distribution innounp-2; do
        urls="$urls
$(curl -fsSL "https://api.github.com/repos/jrathlev/InnoUnpacker-Windows-GUI/contents/$d" 2>/dev/null \
            | grep -o '"download_url": *"[^"]*"' | cut -d'"' -f4 | grep -iE '\.(zip|exe)$')"
    done
    urls="$(printf '%s\n' "$urls" | grep -iE '\.(zip|exe)$' | grep -viE 'source' | awk 'NF')"
    [ -z "$urls" ] && { ui_error "No se pudo localizar la descarga de innounp"; rm -rf "$tmp"; return 1; }
    while IFS= read -r url; do
        [ -n "$url" ] || continue
        say "[innounp] probando: $(basename "$url")"
        dl "$url" "$tmp/$(basename "$url")" || continue
        case "$url" in
            *.zip|*.ZIP)
                extract_archive "$tmp/$(basename "$url")" "$tmp" >/dev/null 2>&1 || true ;;
        esac
        if find "$tmp" -type f -iname 'innounp*.exe' | head -n1 | grep -q .; then
            ok=0; break
        fi
    done <<EOF2
$urls
EOF2
    if [ "$ok" != 0 ]; then
        rm -rf "$tmp"
        ui_error "No se encontro innounp.exe en las descargas.
Puedes bajarlo a mano y dejarlo en:
$INNOUNP_DIR/innounp.exe"
        return 1
    fi
    find "$tmp" -type f -iname 'innounp*.exe' -exec cp -f {} "$INNOUNP_DIR"/ \;
    rm -rf "$tmp"
    find_innounp && { say "[innounp] listo: $(basename "$INNOUNP_EXE")"; return 0; }
    return 1
}

win_path() {
    # /ruta/unix -> Z:\ruta\unix (Wine mapea Z: a la raiz del sistema)
    printf 'Z:%s' "$(readlink -f "$1" | sed 's|/|\\|g')"
}

extract_with_innounp() {
    # $1 = instalador, $2 = carpeta destino. Ejecuta innounp.exe con Wine.
    local inst="$1" dest="$2"
    setup_innounp || return 1
    local gid="__wptools__"
    load_profile "$gid"
    RUNNER="${RUNNER:-}"
    local rdir; rdir="$(get_runner_path)"
    [ -z "$rdir" ] && { ui_error "No hay runner de Wine/Proton para ejecutar innounp"; return 1; }
    export_game_env "$gid"
    build_runner_cmd "$rdir"
    mkdir -p "$dest"
    say "[innounp] extrayendo con $(basename "$rdir")..."
    ( cd "$dest" && "${RUN_CMD[@]}" "$(win_path "$INNOUNP_EXE")" -x -y -b "$(win_path "$inst")" ) 2>&1 \
        | grep -vE '^#[0-9]+ .*extracted' >> "$LOG_FILE"
    local n; n="$(find "$dest" -type f 2>/dev/null | wc -l)"
    say "[innounp] ficheros extraidos: $n"
    [ "$n" -gt 0 ]
}


is_inno_installer() {
    # $1 = exe. Instalador InnoSetup/GOG? Por nombre o por la firma que
    # todos los instaladores Inno Setup llevan en su cabecera.
    case "$(basename "$1")" in
        setup_*.exe|setup_*.EXE|setup.exe|Setup.exe) return 0 ;;
    esac
    head -c 20000000 "$1" 2>/dev/null | grep -qa 'Inno Setup'
}

install_exe_silent_wine() {
    # Instalacion DESATENDIDA con Wine: los instaladores Inno/GOG aceptan
    # /VERYSILENT y /DIR, asi que no hace falta teclado ni raton.
    local inst="$1" name="$2"
    local dest="$GAMES_PATH/$name"
    local gid="__wptools__"
    load_profile "$gid"
    local rdir; rdir="$(get_runner_path)"
    [ -z "$rdir" ] && { ui_error "No hay runner de Wine/Proton para instalar el juego"; return 1; }
    export_game_env "$gid"
    build_runner_cmd "$rdir"
    pad_bridge_stop
    rm -rf "$dest"; mkdir -p "$dest"
    local sw
    for sw in /VERYSILENT /SILENT; do
        say "[GOG] instalacion desatendida ($sw) en: $dest"
        run_with_progress "Instalando '$name' sin intervencion (puede tardar varios minutos)..." \
            "${RUN_CMD[@]}" "$(win_path "$inst")" "$sw" /SUPPRESSMSGBOXES /NORESTART /SP- /NOICONS \
            "/DIR=$(win_path "$dest")" || true
        local wsrv i
        wsrv="$(dirname "$(runner_wine_bin "$rdir")" 2>/dev/null)/wineserver"
        [ -x "$wsrv" ] && "$wsrv" -w 2>/dev/null
        for i in 1 2 3; do
            pgrep -f 'wineserver' >/dev/null 2>&1 || break
            sleep 1
        done
        [ -n "$(find "$dest" -type f -iname '*.exe' 2>/dev/null | head -n1)" ] && break
        say "[GOG] $sw no dejo ejecutables; probando el siguiente modo"
    done
    local n; n="$(find "$dest" -type f 2>/dev/null | wc -l)"
    say "[GOG] instalacion desatendida: $n ficheros en $dest"
    if [ "$n" -eq 0 ]; then
        rm -rf "$dest"
        return 1
    fi
    GOG_ROOT="$dest"
    GOG_EXE="$(find_game_exe "$dest")"
    [ -n "$GOG_EXE" ]
}

install_exe_with_wine() {
    # Plan B cuando innounp no puede con el instalador: ejecutarlo dentro
    # de un prefijo y luego importar la carpeta donde se haya instalado.
    local inst="$1" name="$2" gid pfx
    gid="$(printf '%s' "instalador_$name" | tr ' /' '__')"
    ui_info "Se abrira el instalador de Windows.
Instala el juego con la ruta que te ofrezca por defecto (C:\\...) y, al
terminar, WProton te dejara elegir la carpeta instalada para importarla."
    launch_loose_exe "$gid" "$(readlink -f "$inst")"
    load_profile "$gid"
    pfx="$(prefix_path "$gid")"
    local start="$pfx/drive_c"
    [ -d "$start" ] || start="$HOME"
    ui_info "Instalacion terminada.
Elige ahora la CARPETA del juego instalado (dentro de drive_c)."
    local dir
    dir="$(browse_for_path "Carpeta del juego instalado" "$start" "dir")" || return 1
    [ -d "$dir" ] || return 1
    package_dir "$dir"
}

gog_find_root() {
    # $1 = dir extraido -> carpeta REAL del juego.
    # Los instaladores GOG no siempre usan app/: muchos dejan el juego en la
    # raiz (bin/juego.exe + assets/) y en app/ solo un icono y webcache.zip.
    # Estrategia: quedarse con la carpeta del ejecutable MAS GRANDE, ignorando
    # las carpetas de servicio de GOG (tmp, __redist, commonappdata).
    local d="$1" cand exe best="" bestsz=0 sz parent
    GOG_ROOT_EXE=""
    for cand in $(find "$d" -maxdepth 2 -type d \( -iname 'app' -o -iname '{app}' \) 2>/dev/null); do
        exe="$(find_game_exe "$cand")"
        [ -n "$exe" ] && { GOG_ROOT_EXE="$exe"; printf '%s' "$cand"; return 0; }
    done
    while IFS= read -r exe; do
        [ -n "$exe" ] || continue
        sz="$(stat -c %s "$exe" 2>/dev/null || echo 0)"
        [ "$sz" -gt "$bestsz" ] && { bestsz=$sz; best="$exe"; }
    done <<EOF2
$(find "$d" -type f -iname '*.exe' \
    ! -ipath '*/tmp/*' ! -ipath '*/{tmp}/*' ! -ipath '*/__redist/*' \
    ! -ipath '*/commonappdata/*' ! -ipath '*/{commonappdata}/*' \
    ! -ipath '*/DirectX/*' 2>/dev/null | _fexe)
EOF2
    if [ -n "$best" ]; then
        cand="$(dirname "$best")"
        case "$(basename "$cand")" in
            bin|Bin|BIN|bin64|x64|win64|Win64|game|Game)
                parent="$(dirname "$cand")"
                [ "$parent" != "$cand" ] && [ "$parent" != "/" ] && cand="$parent" ;;
        esac
        say "[GOG] ejecutable principal: ${best#$d/}"
        GOG_ROOT_EXE="$best"
        printf '%s' "$cand"
        return 0
    fi
    printf '%s' "$d"
}

has_galaxy_chunks() {
    # GOG Galaxy: el juego va troceado en tmp/<xx>/<yy>/<md5>. Solo innoextract
    # sabe reensamblarlo; si vemos esto sin ejecutable, avisamos.
    local d="$1" n
    n="$(find "$d" \( -ipath '*/tmp/*' -o -ipath '*/{tmp}/*' \) -type f \
         -regextype posix-extended -regex '.*/[0-9a-f]{32}$' 2>/dev/null | head -n 5 | wc -l)"
    [ "$n" -ge 3 ]
}

gog_extract_try() {
    # $1 = herramienta (innoextract|innounp), $2 = instalador, $3 = destino
    # Deja en GOG_ROOT la carpeta con el juego si lo consigue.
    GOG_ROOT=""
    local tool="$1" inst="$2" dest="$3" nfiles root exe
    rm -rf "$dest"; mkdir -p "$dest"
    case "$tool" in
        innoextract)
            find_innoextract || return 1
            say "[GOG] probando innoextract: $("$INNOEXTRACT_BIN" --version 2>&1 | head -n1)"
            local gogflag=""
            ls "${inst%.exe}"-*.bin >/dev/null 2>&1 && gogflag="--gog"
            # el listado fichero-a-fichero llenaba el log de megas: solo avisos
            say "Extrayendo con innoextract: $(basename "$inst") ..."
            "$INNOEXTRACT_BIN" $gogflag -d "$dest" "$inst" 2>&1 \
                | grep -v '^ - "' >> "$LOG_FILE" ;;
        innounp)
            setup_innounp || return 1
            say "[GOG] probando innounp (via Wine)"
            run_with_progress "Extrayendo con innounp: $(basename "$inst") ..." \
                extract_with_innounp "$inst" "$dest" || return 1 ;;
    esac
    nfiles="$(find "$dest" -type f 2>/dev/null | wc -l)"
    say "[GOG] $tool extrajo $nfiles ficheros"
    [ "$nfiles" -eq 0 ] && return 1
    GOG_ROOT_EXE=""
    root="$(gog_find_root "$dest")"     # imprime la raiz...
    gog_find_root "$dest" >/dev/null    # ...y esta pasada rellena GOG_ROOT_EXE
    exe="$GOG_ROOT_EXE"
    [ -z "$exe" ] && exe="$(find_game_exe "$root")"
    [ -z "$exe" ] && [ "$root" != "$dest" ] && exe="$(find_game_exe "$dest")"
    if [ -z "$exe" ]; then
        if has_galaxy_chunks "$dest"; then
            say "[GOG] AVISO: formato GOG Galaxy (ficheros troceados por hash) sin reensamblar"
            GOG_GALAXY_SEEN=1
        fi
        say "[GOG] $tool no dejo ningun ejecutable utilizable"
        return 1
    fi
    GOG_ROOT="$root"
    GOG_EXE="$exe"
    return 0
}

import_gog_exe() {
    # Instalador GOG/InnoSetup -> juego en carpeta -> probar/empaquetar.
    #
    # ESTRATEGIA: instalacion DESATENDIDA con Wine (/VERYSILENT /DIR=...).
    # Es la via mas fiable porque la hace el propio instalador: funciona con
    # cualquier version de Inno Setup y con el formato GOG Galaxy (los trozos
    # los reensambla el, no nosotros) y no necesita teclado ni raton.
    # Si el instalador ignorase el modo silencioso, se prueba a extraerlo con
    # innoextract / innounp (si estan disponibles) y, en ultimo caso, el
    # instalador interactivo.
    local inst="$1" name root exe
    name="$(basename "$inst")"; name="${name%.*}"
    name="$(printf '%s' "$name" | sed -E 's/^setup_//; s/_\([^)]*\)//g; s/_[0-9]+(\.[0-9]+)+.*$//; s/_/ /g')"
    name="$(clean_game_name "$name")"
    [ -z "$name" ] && name="juego_gog"
    GOG_ROOT=""; GOG_EXE=""; GOG_GALAXY_SEEN=0
    local extract_dir="$GAMES_PATH/.gog_extract_$$"

    say "[GOG] '$name': instalacion desatendida con Wine"
    if ! install_exe_silent_wine "$inst" "$name"; then
        say "[GOG] el modo silencioso no dejo el juego; probando extractores"
        if ! gog_extract_try innoextract "$inst" "$extract_dir" \
           && ! gog_extract_try innounp "$inst" "$extract_dir"; then
            rm -rf "$extract_dir"
            local extra=""
            [ "${GOG_GALAXY_SEEN:-0}" = 1 ] && extra="
(El instalador usa el formato GOG Galaxy: los ficheros van troceados
 y solo el propio instalador o innoextract saben recomponerlos.)"
            if ui_ask "No se pudo obtener el juego de este instalador.$extra

Quieres abrir el instalador para hacerlo A MANO (necesita teclado/raton)?"; then
                install_exe_with_wine "$inst" "$name"
                return $?
            fi
            return 1
        fi
        # extraido: mover a su carpeta definitiva
        root="$GOG_ROOT"; exe="$GOG_EXE"
        local dest="$GAMES_PATH/$name"
        rm -rf "$dest"
        mv "$root" "$dest" 2>/dev/null || { mkdir -p "$dest"; mv "$root"/* "$dest"/ 2>/dev/null; }
        exe="$dest/${exe#"$root/"}"
        [ -f "$exe" ] || exe="$(find_game_exe "$dest")"
        rm -rf "$extract_dir"
        GOG_ROOT="$dest"; GOG_EXE="$exe"
    fi
    root="$GOG_ROOT"; exe="$GOG_EXE"
    [ -n "$exe" ] || { ui_error "No se encontro ejecutable en: $root"; return 1; }
    say "[+] Juego en: $root"
    say "[+] Ejecutable: $(basename "$exe")"
    write_autorun "$root" "$exe"
    if ui_ask "Borrar el instalador original?
$(basename "$inst")
(el juego ha quedado en: $(basename "$root"))"; then
        rm -f "$inst"
        rm -f "${inst%.*}"-*.bin 2>/dev/null
    fi
    if offer_test_then_pack "$root" "$exe" "$name"; then
        ui_ask "Lanzar '$name' desde el wsquashfs ahora?" \
            && launch_game "$PACKED_OUT" "auto"
    fi
}

pick_game_root() {
    # $1 = exe absoluto -> el usuario CONFIRMA la carpeta raiz (los datos del
    # juego pueden estar por encima de la carpeta del exe)
    local exe_dir="$1" h list c prev i sel
    h="$exe_dir"
    if printf '%s' "$exe_dir" | grep -qiE '/Binaries/Win(64|32)$'; then
        local strip="${exe_dir%/[Bb]inaries/[Ww]in*}"
        h="$(dirname "$strip")"
        { [ -z "$h" ] || [ "$h" = "/" ]; } && h="$strip"
    elif printf '%s' "$exe_dir" | grep -qiE '/Win(64|32)$'; then
        h="$(dirname "$(dirname "$exe_dir")")"
        { [ -z "$h" ] || [ "$h" = "/" ]; } && h="$(dirname "$exe_dir")"
    fi
    list="$h"
    c="$h"
    for i in 1 2 3; do
        prev="$c"; c="$(dirname "$c")"
        [ "$c" = "$prev" ] && break
        case "$c" in "$HOME"|"/"|"") break ;; esac
        list="$list
$c"
    done
    # shellcheck disable=SC2046
    sel="$(IFS=$'\n'; set -f; menu "Carpeta RAIZ del juego (se empaqueta ENTERA)" $list "(elegir otra carpeta...)")" || return 1
    if [ "$sel" = "(elegir otra carpeta...)" ]; then
        browse_for_path "Carpeta raiz del juego" "$exe_dir" "dir"
        return $?
    fi
    printf '%s' "$sel"
}

package_exe() {
    # .exe suelto -> confirmar raiz del juego, autorun, empaquetar, lanzar
    local exe_abs exe_dir game_root name out
    exe_abs="$(realpath "$1")"
    if is_inno_installer "$exe_abs"; then
        if ui_ask "Parece un instalador GOG/InnoSetup:
$(basename "$exe_abs")
Instalarlo (sin intervencion) y convertirlo a wsquashfs?"; then
            import_gog_exe "$exe_abs"
            return $?
        fi
    fi
    exe_dir="$(dirname "$exe_abs")"
    game_root="$(pick_game_root "$exe_dir")" || { say "Importacion cancelada"; return 1; }
    name="$(basename "$game_root")"
    say "Preparando ${name}..."
    write_autorun "$game_root" "$exe_abs"
    if offer_test_then_pack "$game_root" "$exe_abs" "$name"; then
        ui_ask "Lanzar '$name' desde el wsquashfs ahora?" \
            && launch_game "$PACKED_OUT" "auto"
    fi
}

package_dir() {
    # Carpeta -> .sh dentro se ejecuta; si no, empaquetar y lanzar
    local dir="$1" launcher name exe out
    launcher=$(find "$dir" -maxdepth 1 -type f -name '*.sh' | head -n1)
    if [ -n "$launcher" ]; then
        say "Lanzando script del juego: $launcher"
        pad_bridge_stop
        bash "$launcher"
        return $?
    fi
    name="$(basename "$dir")"
    exe="$(find_game_exe "$dir")"
    if [ -z "$exe" ]; then
        find_exe "$dir" "manual" || die "No se encontro ejecutable en la carpeta"
        exe="$EXE_PATH"
    fi
    write_autorun "$dir" "$exe"
    if offer_test_then_pack "$dir" "$exe" "$name"; then
        ui_ask "Lanzar '$name' desde el wsquashfs ahora?" \
            && launch_game "$PACKED_OUT" "auto"
    fi
}

import_archive() {
    # zip/7z/rar (multiparte) -> extraer, PURGAR originales, empaquetar/mover, lanzar
    command -v 7z >/dev/null 2>&1 || die "Falta 7z (paquete p7zip):
CachyOS: sudo pacman -S p7zip"
    local input="$1"
    local in_dir name_raw prefix game_name extract_dir
    in_dir="$(dirname "$input")"
    name_raw="$(basename "$input")"

    # Ancla de purga universal: nombre base sin partes/extensiones
    prefix="${input%.0*}"
    prefix="${prefix%.part*}"
    prefix="${prefix%.zip}"; prefix="${prefix%.7z}"; prefix="${prefix%.rar}"

    game_name="${name_raw%.001}"
    game_name="${game_name%.zip}"; game_name="${game_name%.7z}"
    game_name="${game_name%.z01}"; game_name="${game_name%.rar}"
    game_name="$(clean_game_name "$game_name")"
    [ -z "$game_name" ] && game_name="juego_importado"

    extract_dir="$BUILD_BASE/${game_name}_extract"
    rm -rf "$extract_dir"; mkdir -p "$extract_dir"
    # Espacio para extraer: los instaladores de juegos ya vienen con los
    # datos comprimidos (texturas, audio, video), asi que el factor real
    # ronda 1,6x, no 3x. Con archivos grandes se pide un extra fijo en vez
    # de multiplicar, para no exigir cifras disparatadas.
    local insz need
    insz="$(du -b "$input" 2>/dev/null | awk '{print $1}')"
    if [ -n "$insz" ]; then
        if [ "$insz" -gt 21474836480 ]; then       # > 20 GB
            need=$(( insz + insz / 4 ))            # +25%
        else
            need=$(( insz * 8 / 5 ))               # 1,6x
        fi
        if ! check_space "$need" "$GAMES_PATH" "extraer $(basename "$input")"; then
            return 1
        fi
    fi
    local ext_ok=1
    case "$input" in
        *.wtgz)
            run_with_progress "Descomprimiendo fichero: $name_raw ..." \
                tar -xzf "$input" -C "$extract_dir" || ext_ok=0 ;;
        *)
            run_with_progress "Descomprimiendo fichero: $name_raw ..." \
                7z x "$input" -o"$extract_dir" -y || ext_ok=0 ;;
    esac
    if [ "$ext_ok" = 1 ]; then
        say "[+] Extraccion completada."
        say "[+] Purgando archivos comprimidos originales..."
        rm -f "${prefix}"* 2>/dev/null
        find "$in_dir" -maxdepth 1 -type f -name "${game_name}*" 2>/dev/null | while read -r f; do
            case "${f##*.}" in
                zip|7z|rar|001|002|003|004|005|z01|z02|z03|z04|z05|ZIP|7Z|RAR) rm -f "$f" ;;
                *) case "$(basename "$f")" in
                       *.part*.rar|*.r[0-9][0-9]) rm -f "$f" ;;
                   esac ;;
            esac
        done
    else
        rm -rf "$extract_dir"
        die "La descompresion fallo o fue interrumpida. Se conservan los archivos fuente."
    fi

    # Contiene ya un wsquashfs? -> moverlo tal cual a la carpeta de juegos
    local inner
    inner=$(find "$extract_dir" -type f \( -iname '*.wsquashfs' -o -iname '*.squashfs' -o -iname '*.dwarfs' \) | head -n1)
    local out
    if [ -n "$inner" ]; then
        out="$GAMES_PATH/$(basename "$inner")"
        mv -f "$inner" "$out"
        rm -rf "$extract_dir"
        say "[OK] wsquashfs importado: $out"
    else
        # Empaquetar el contenido extraido con autorun
        local root="$extract_dir"
        # si todo esta dentro de una unica subcarpeta, usarla como raiz
        local entries; entries=$(find "$extract_dir" -mindepth 1 -maxdepth 1 | wc -l)
        if [ "$entries" -eq 1 ] && [ -d "$(find "$extract_dir" -mindepth 1 -maxdepth 1)" ]; then
            root="$(find "$extract_dir" -mindepth 1 -maxdepth 1)"
        fi
        say "[+] Buscando ejecutable del juego..."
        local exe; exe="$(find_game_exe "$root")"
        [ -n "$exe" ] && { say "[+] Ejecutable: $(basename "$exe") - escribiendo autorun.cmd"; write_autorun "$root" "$exe"; }
        out="$(build_wsquashfs "$root" "$game_name")"
        rm -rf "$extract_dir"
        say "[OK] Empaquetado: $out"
    fi
    launch_game "$out" "auto"
}

launch_loose_exe() {
    # Lanzar un exe suelto (sin squash) con el perfil del nombre dado
    local gid="$1" exe="$2"
    gid="$(printf '%s' "$gid" | tr ' /' '__')"
    BUNDLED_PREFIX_DIR=""
    BUNDLED_RUNNER_DIR=""
    [ "${PREFIX_MODE:-}" = "bundled" ] && PREFIX_MODE="shared"
    [ "${RUNNER:-}" = "bundled" ] && RUNNER=""
    local abs_exe; abs_exe="$(readlink -f "$exe" 2>/dev/null || printf '%s' "$exe")"
    if [ "$abs_exe" != "$LAST_GAME" ]; then
        LAST_GAME="$abs_exe"
        save_settings
    fi
    if [ "$IS_BATOCERA" = 1 ] && [ -n "$BATOCERA_WINE_BIN" ]; then
        load_profile "$gid"
        if [ "${USE_BATOCERA:-1}" = 1 ]; then
            batocera_play "$abs_exe"
            return $?
        fi
    fi
    if ! profile_exists "$gid"; then
        first_run_wizard "$gid" "$(dirname "$exe")" || die "Asistente cancelado"
    fi
    load_profile "$gid"
    local rdir; rdir="$(get_runner_path)"
    [ -z "$rdir" ] && die "No hay runners instalados. Ejecuta: $0 --setup"
    export_game_env "$gid"
    build_runner_cmd "$rdir"
    pad_sdl_prefix_setup "$rdir"
    pad_bridge_stop
    local keys_file=""
    if keys_file="$(find_keys_file "$exe" "$gid")"; then
        mapeador_start "$keys_file"
    fi
    gamepad_retrigger &
    local trig=$!
    say "Lanzando exe suelto con $(basename "$rdir") [$RUNNER_KIND]"
    local st0; st0=$(date +%s)
    saves_detect_start
    local loose_args="${ARGS_OVERRIDE:-}"
    [ -n "$loose_args" ] && say "Argumentos: $loose_args"
    # shellcheck disable=SC2086
    ( cd "$(dirname "$exe")" && "${RUN_CMD[@]}" "$exe" $loose_args >> "$LOG_FILE" 2>&1 )
    local rc=$?
    kill "$trig" 2>/dev/null
    mapeador_stop
    stats_record "$gid" "$(( $(date +%s) - st0 ))"
    saves_detect_end "$gid"
    post_game_resettle
    return $rc
}

play_folder() {
    # Jugar una carpeta suelta SIN empaquetar ni preguntas de compresion
    local dir="$1" launcher exe name
    launcher=$(find "$dir" -maxdepth 1 -type f -name '*.sh' | head -n1)
    if [ -n "$launcher" ]; then
        say "Lanzando script del juego: $launcher"
        pad_bridge_stop
        bash "$launcher"
        return $?
    fi
    name="$(game_id "$dir")"
    load_profile "$name"
    if [ -n "$EXE_OVERRIDE" ] && [ -f "$dir/$EXE_OVERRIDE" ]; then
        exe="$dir/$EXE_OVERRIDE"
    else
        exe="$(find_game_exe "$dir")"
        if [ -z "$exe" ]; then
            find_exe "$dir" "manual" || die "No se encontro ejecutable en la carpeta"
            exe="$EXE_PATH"
        fi
    fi
    launch_loose_exe "$name" "$exe"
}

play_or_config() {
    # $1 = lo devuelto por pick_squash: jugar, o abrir su configuracion si el
    # usuario pulso X sobre el juego resaltado.
    case "$1" in
        "WPACT:CONFIG|"*)
            local g="${1#WPACT:CONFIG|}"
            [ -e "$g" ] || { ui_error "No existe: $g"; return 1; }
            game_config_menu "$g" ;;
        *) play_any "$1" ;;
    esac
}

play_any() {
    # Despachador de "jugar": wsquashfs -> montar | exe -> directo | carpeta -> directo
    local p="$1"
    case "$p" in
        *.wsquashfs|*.squashfs|*.dwarfs|*.WSQUASHFS|*.SQUASHFS|*.DWARFS)
            launch_game "$p" "auto" ;;
        *.exe|*.EXE)
            [ -f "$p" ] || die "No existe: $p"
            local nm; nm="$(game_id "$(dirname "$p")")"
            launch_loose_exe "$nm" "$(realpath "$p")" ;;
        *)
            if [ -d "$p" ]; then
                play_folder "$p"
            elif [ -f "$p" ]; then
                launch_game "$p" "auto"
            else
                die "No existe: $p"
            fi ;;
    esac
}

log_input_devices() {
    # Deja en el log que mandos ve el sistema justo antes de lanzar
    local blocks name handlers n=0
    [ -r /proc/bus/input/devices ] || return 0
    while IFS= read -r line; do
        case "$line" in
            N:*) name="${line#N: Name=}" ;;
            H:*) handlers="$line"
                 case "$handlers" in
                     *js*) n=$((n+1))
                           say "    mando $n: $name" ;;
                 esac ;;
        esac
    done < /proc/bus/input/devices
    if [ "$n" -eq 0 ]; then
        say "[!] El sistema no expone ningun joystick (/dev/input/js*)"
    else
        say "[+] Mandos detectados por el sistema: $n"
    fi
    # permisos: si no podemos leerlos, el juego tampoco
    local ev bad=0
    for ev in /dev/input/event*; do
        [ -e "$ev" ] || continue
        [ -r "$ev" ] || bad=$((bad+1))
    done
    [ "$bad" -gt 0 ] && say "[!] $bad dispositivos /dev/input sin permiso de lectura (grupo 'input'?)"
    return 0
}

CANVAS_PID=""
CANVAS_FILE=""

canvas_start() {
    # Fondo persistente: SOLO en modo Juego (sesion gamescope), donde el
    # compositor necesita que siempre exista una ventana nuestra.
    [ "${IS_GAMESCOPE:-0}" = 1 ] || return 0
    [ -n "$CANVAS_PID" ] && kill -0 "$CANVAS_PID" 2>/dev/null && return 0
    pygame_available || return 0
    write_menu_pygame
    CANVAS_FILE="$RUNTIME_DIR/.canvas_status"
    printf 'Cargando...
' > "$CANVAS_FILE"
    PYGAME_HIDE_SUPPORT_PROMPT=1 SDL_JOYSTICK_ALLOW_BACKGROUND_EVENTS=1 WP_MENU_FS=1 \
        env -u LD_PRELOAD "$PY_BIN" "$MENU_PYGAME_PY" canvas "WProton" \
        "$CANVAS_FILE" >> "$LOG_FILE" 2>&1 &
    CANVAS_PID=$!
    sleep 0.6
    if kill -0 "$CANVAS_PID" 2>/dev/null; then
        say "[+] Modo Juego: fondo persistente activo (pid $CANVAS_PID)"
    else
        say "AVISO: no se pudo abrir el fondo persistente"
        CANVAS_PID=""
    fi
    return 0
}

canvas_say() {
    # Mensaje que se ve en el fondo mientras no hay menu delante
    [ -n "$CANVAS_FILE" ] && printf '%s
' "$1" > "$CANVAS_FILE" 2>/dev/null
    return 0
}

canvas_stop() {
    [ -n "$CANVAS_FILE" ] && printf 'STOP
' > "$CANVAS_FILE" 2>/dev/null
    if [ -n "$CANVAS_PID" ]; then
        local i
        for i in 1 2 3 4 5; do
            kill -0 "$CANVAS_PID" 2>/dev/null || break
            sleep 0.2
        done
        kill "$CANVAS_PID" 2>/dev/null
    fi
    [ -n "$CANVAS_FILE" ] && rm -f "$CANVAS_FILE"
    CANVAS_PID=""; CANVAS_FILE=""
    return 0
}

post_game_resettle() {
    # En el MODO JUEGO (sesion gamescope) el compositor le da el foco al juego
    # y, al cerrarse este, no siempre se lo devuelve a la ventana siguiente:
    # el menu se abre pero queda detras/sin foco y parece que WProton no
    # vuelve. Aqui esperamos a que el juego muera del todo y forzamos que la
    # proxima ventana nazca en primer plano.
    local i
    for i in 1 2 3 4 5 6 7 8 9 10; do
        pgrep -x wineserver >/dev/null 2>&1 || break
        sleep 0.5
    done
    # tambien los procesos del propio juego (a veces sobreviven al wineserver)
    for i in 1 2 3 4 5 6; do
        pgrep -f '\.exe' >/dev/null 2>&1 || break
        sleep 0.5
    done
    canvas_say "Volviendo al menu..."
    if [ "${IS_GAMESCOPE:-0}" = 1 ]; then
        say "[+] Sesion gamescope: devolviendo el foco a los menus..."
        # ventana nueva SIEMPRE en primer plano y a pantalla completa
        export SDL_VIDEO_MINIMIZE_ON_FOCUS_LOSS=0
        export WP_MENU_FS=1
        export SDL_VIDEO_FORCE_FOCUS=1
        # si el juego dejo alguna instancia de gamescope anidada, fuera:
        # es la que retiene el foco del compositor
        pkill -f 'gamescope .*--' 2>/dev/null
        sleep 2
        # y que el helper se dibuje aunque nazca sin foco
        export SDL_HINT_VIDEO_MINIMIZE_ON_FOCUS_LOSS=0
        # si el fondo murio durante el juego, lo levantamos otra vez: es la
        # ventana a la que gamescope devuelve el foco
        if [ -n "$CANVAS_PID" ] && ! kill -0 "$CANVAS_PID" 2>/dev/null; then
            say "[+] El fondo persistente se cerro: reabriendolo"
            CANVAS_PID=""
            canvas_start
        fi
    else
        sleep 0.3
    fi
    return 0
}

# ----------------------------------------------------------------------------
# 4f. COPIAS DE SEGURIDAD DE PARTIDAS GUARDADAS
#     Las partidas pueden estar en tres sitios segun el juego:
#       - overlay del wsquashfs (wsquashfs/overlays/<gid>/upper)
#       - prefijo: drive_c/users/<user>/AppData/{Roaming,Local,LocalLow}
#       - prefijo: drive_c/users/<user>/Documents  (y Mis documentos)
#     Se empaqueta todo lo encontrado en un zip con fecha en backups/.
# ----------------------------------------------------------------------------
BACKUP_DIR="$BASE_DIR/backups"

SAVE_ROOTS() {
    # Raices donde suelen vivir las partidas (dentro del prefijo del juego
    # y en el overlay del wsquashfs)
    local gid="$1" pfx u d
    printf '%s\n' "$OVERLAY_BASE/$gid/upper"
    pfx="$(prefix_path "$gid")"
    for u in "$pfx"/drive_c/users/*/; do
        [ -d "$u" ] || continue
        case "$(basename "$u")" in Public|public) continue ;; esac
        for d in "AppData/Roaming" "AppData/Local" "AppData/LocalLow" \
                 "Documents" "Mis documentos" "My Documents" "Saved Games"; do
            [ -d "$u$d" ] && printf '%s\n' "$u$d"
        done
    done
    return 0
}

saves_detect_start() {
    # Antes de jugar: marca de tiempo para saber que se escribe DESPUES
    SAVES_MARK="$(mktemp)"
    touch "$SAVES_MARK"
    return 0
}

saves_detect_end() {
    # Tras jugar: busca los ficheros escritos DURANTE la partida y deduce la
    # carpeta concreta del juego (p.ej. AppData/Roaming/Yacht Club Games/Mina
    # the Hollower) en vez de guardar AppData entero. Lo aprendido se anota en
    # el perfil (SAVE_PATHS) y se usa en las copias siguientes.
    local gid="$1" root f rel dir cand="" p old="${SAVE_PATHS:-}" cambio=0
    [ -n "${SAVES_MARK:-}" ] && [ -f "$SAVES_MARK" ] || return 0
    while IFS= read -r root; do
        [ -d "$root" ] || continue
        case "$root" in */upper) continue ;; esac      # el overlay ya va entero
        while IFS= read -r f; do
            [ -n "$f" ] || continue
            # Fuera todo lo que NO es una partida: caches de shaders (DXVK,
            # VKD3D, NVIDIA, AMD, Unity/UE), temporales, volcados y logs.
            case "$f" in
                *"/Microsoft/"*|*"/Temp/"*|*"/Crashpad/"*|*"/GStreamer"*|\
                *"/cache/"*|*"/Cache/"*|*"/CachedData/"*|*"/NVIDIA/"*|*"/AMD/"*|\
                *"/D3DSCache/"*|*"/DXCache/"*|*"/shadercache/"*|*"/ShaderCache/"*|\
                *"/GPUCache/"*|*"/Intel/"*|*"/Unity/"*|*"/CrashReportClient/"*|\
                *.log|*.tmp|*.dmp|*.dxvk-cache|*.dxvk-cache-tmp|*.vkd3d-cache|\
                *.nvcache|*.bin.cache|*.shader*|*.pipeline_cache|*.ubulk) continue ;;
            esac
            rel="${f#"$root"/}"
            case "$rel" in */*) ;; *) continue ;; esac
            dir="$(printf '%s' "$rel" | awk -F/ 'NF>2{print $1"/"$2; next} {print $1}')"
            [ -n "$dir" ] || continue
            case "$(printf '%s' "$dir" | tr 'A-Z' 'a-z')" in
                *cache*|*shader*|*temp*|*crash*|*log*) continue ;;
            esac
            cand="$cand$root/$dir
"
        done <<EOFF
$(find "$root" -type f -newer "$SAVES_MARK" 2>/dev/null | head -n 400)
EOFF
    done <<EOFR
$(SAVE_ROOTS "$gid")
EOFR
    rm -f "$SAVES_MARK"; SAVES_MARK=""
    [ -z "$cand" ] && return 0
    while IFS= read -r p; do
        [ -n "$p" ] || continue
        case ":$old:" in *":$p:"*) continue ;; esac
        old="${old:+$old:}$p"
        cambio=1
        say "[saves] carpeta de partidas detectada: $p"
    done <<EOFP
$(printf '%s' "$cand" | awk 'NF' | sort -u)
EOFP
    if [ "$cambio" = 1 ]; then
        SAVE_PATHS="$old"
        write_full_profile "$gid"
    fi
    return 0
}

save_locations() {
    # $1 = gid -> "etiqueta|ruta" de cada sitio con partidas de ESTE juego.
    # 1) lo aprendido observando la partida (SAVE_PATHS del perfil)
    # 2) si no hay nada, carpetas cuyo nombre se parezca al del juego
    # 3) el overlay del wsquashfs, que siempre es del juego
    local gid="$1" p root up base
    if [ -n "${SAVE_PATHS:-}" ]; then
        while IFS= read -r p; do
            [ -n "$p" ] && [ -d "$p" ] && printf '%s|%s\n' "$(basename "$p")" "$p"
        done <<EOFSP
$(printf '%s' "$SAVE_PATHS" | tr ':' '\n')
EOFSP
    else
        base="$(printf '%s' "$gid" | tr '_.' '  ' | tr 'A-Z' 'a-z')"
        while IFS= read -r root; do
            [ -d "$root" ] || continue
            case "$root" in */upper) continue ;; esac
            while IFS= read -r p; do
                [ -n "$p" ] && printf '%s|%s\n' "$(basename "$p")" "$p"
            done <<EOFN
$(find "$root" -mindepth 1 -maxdepth 2 -type d 2>/dev/null | while IFS= read -r d; do
    n="$(basename "$d" | tr 'A-Z' 'a-z')"
    case "$base" in *"$n"*) printf '%s\n' "$d" ;; esac
    case "$n" in *"${base%% *}"*) printf '%s\n' "$d" ;; esac
done | sort -u | head -n 6)
EOFN
        done <<EOFR2
$(SAVE_ROOTS "$gid")
EOFR2
    fi
    up="$OVERLAY_BASE/$gid/upper"
    [ -d "$up" ] && [ -n "$(find "$up" -maxdepth 3 -type f 2>/dev/null | head -n1)" ] \
        && printf 'overlay|%s\n' "$up"
    return 0
}

backup_create() {
    # $1 = gid. Crea backups/<gid>_YYYYmmdd_HHMM.zip con todo lo localizado
    local gid="$1" locs n zip tmp label path rel
    locs="$(save_locations "$gid")"
    if [ -z "$locs" ]; then
        ui_info "No se han encontrado partidas guardadas de '$gid'.
Se busca en el overlay del juego y en AppData/Documents del prefijo."
        return 1
    fi
    mkdir -p "$BACKUP_DIR"
    zip="$BACKUP_DIR/${gid}_$(date '+%Y%m%d_%H%M').zip"
    tmp="$(mktemp -d)"
    n=0
    while IFS='|' read -r label path; do
        [ -n "$path" ] || continue
        mkdir -p "$tmp/$label"
        cp -a "$path/." "$tmp/$label/" 2>/dev/null && n=$((n+1))
        say "[backup] $label: $path"
    done <<EOFLOC
$locs
EOFLOC
    [ "$n" -eq 0 ] && { rm -rf "$tmp"; ui_error "No se pudo copiar ninguna carpeta"; return 1; }
    # ficha con el origen de cada carpeta (para restaurar en otra maquina)
    {
        printf 'juego=%s\nfecha=%s\nprefijo=%s\n' "$gid" "$(date '+%Y-%m-%d %H:%M')" "$(prefix_path "$gid")"
        printf '%s\n' "$locs"
    } > "$tmp/wproton_backup.txt"
    if run_with_progress "Creando copia de seguridad de '$gid'..." \
            sh -c "cd '$tmp' && zip -qr '$zip' ."; then
        rm -rf "$tmp"
        ui_info "Copia creada:
$(basename "$zip")   ($(du -h "$zip" 2>/dev/null | cut -f1))
Carpetas guardadas: $n"
        return 0
    fi
    rm -rf "$tmp" "$zip"
    ui_error "Fallo creando el zip (falta el comando 'zip'?)"
    return 1
}

backup_restore() {
    # $1 = gid. Elige un zip de backups/ y devuelve las carpetas a su sitio.
    local gid="$1" list sel zip tmp label path
    list="$(find "$BACKUP_DIR" -maxdepth 1 -name "${gid}_*.zip" -printf '%f\n' 2>/dev/null | sort -r)"
    [ -z "$list" ] && { ui_info "No hay copias de '$gid' en backups/"; return 1; }
    # shellcheck disable=SC2046
    sel="$(IFS=$'\n'; set -f; menu "Copias de $gid (la mas reciente arriba)" $list "<< Cancelar")" || return 1
    case "$sel" in "<< Cancelar"|"") return 1 ;; esac
    zip="$BACKUP_DIR/$sel"
    ui_ask "Restaurar '$sel'?
Se SOBRESCRIBIRAN las partidas actuales de este juego." || return 1
    tmp="$(mktemp -d)"
    if ! run_with_progress "Restaurando '$sel'..." unzip -qo "$zip" -d "$tmp"; then
        rm -rf "$tmp"; ui_error "No se pudo descomprimir (falta 'unzip'?)"; return 1
    fi
    local n=0
    while IFS='|' read -r label path; do
        [ -n "$path" ] || continue
        [ -d "$tmp/$label" ] || continue
        mkdir -p "$path"
        cp -a "$tmp/$label/." "$path/" 2>/dev/null && n=$((n+1))
        say "[restaurar] $label -> $path"
    done <<EOFR
$(grep '|' "$tmp/wproton_backup.txt" 2>/dev/null)
EOFR
    rm -rf "$tmp"
    ui_info "Restauradas $n carpeta(s) desde $sel"
    return 0
}

backup_menu() {
    # $1 = gid
    local gid="$1" sel locs nb
    while true; do
        locs="$(save_locations "$gid" | wc -l)"
        nb="$(find "$BACKUP_DIR" -maxdepth 1 -name "${gid}_*.zip" 2>/dev/null | wc -l)"
        sel="$(menu "Partidas guardadas de $gid" \
            "Crear copia de seguridad ahora ($locs carpeta(s) detectada(s))" \
            "Restaurar una copia ($nb disponibles)" \
            "Ver donde guarda las partidas" \
            "Olvidar carpetas detectadas (volver a detectar al jugar)" \
            "Sincronizar la carpeta backups (rsync / Syncthing)" \
            "<< Volver")" || return
        case "$sel" in
            "Crear copia"*)   backup_create "$gid" ;;
            "Restaurar"*)     backup_restore "$gid" ;;
            "Olvidar carpetas"*)
                SAVE_PATHS=""; write_full_profile "$gid"
                ui_info "Olvidado. La proxima partida volvera a detectar
donde guarda este juego." ;;
            "Ver donde"*)
                local det; det="$(save_locations "$gid")"
                if [ -z "$det" ]; then
                    ui_info "Todavia no se sabe donde guarda este juego.
Juega una partida: WProton observa que ficheros escribe y
aprende la carpeta exacta (no copia AppData entero)."
                else
                    ui_info "Partidas de $gid:

$(printf '%s\n' "$det" | sed 's/|/  ->  /')"
                fi ;;
            "Sincronizar"*)   backup_sync_menu ;;
            *) return ;;
        esac
    done
}

BACKUP_SYNC_DEST=""      # destino rsync (se guarda en settings)

backup_sync_menu() {
    # Sincroniza backups/ con otra maquina o carpeta usando herramientas
    # externas. WProton no reinventa la sincronizacion: solo la lanza.
    local sel
    while true; do
        sel="$(menu "Sincronizar backups/ con otro sitio" \
            "Destino rsync: ${BACKUP_SYNC_DEST:-sin configurar}" \
            "Sincronizar AHORA con rsync" \
            "Preparar carpeta para Syncthing" \
            "<< Volver")" || return
        case "$sel" in
            "Destino rsync:"*)
                BACKUP_SYNC_DEST="$(ask_text "Destino rsync (carpeta local, disco USB o usuario@equipo:/ruta)" "${BACKUP_SYNC_DEST:-}")"
                save_settings ;;
            "Sincronizar AHORA"*)
                if ! command -v rsync >/dev/null 2>&1; then
                    ui_error "rsync no esta instalado en el sistema.
En SteamOS/Batocera puedes usar Syncthing en su lugar."
                    continue
                fi
                if [ -z "${BACKUP_SYNC_DEST:-}" ]; then
                    ui_info "Configura primero el destino rsync."
                    continue
                fi
                mkdir -p "$BACKUP_DIR"
                if run_with_progress "Sincronizando backups con $BACKUP_SYNC_DEST ..." \
                        rsync -a --delete-after --info=stats1 "$BACKUP_DIR/" "$BACKUP_SYNC_DEST/"; then
                    ui_info "Backups sincronizados con:
$BACKUP_SYNC_DEST"
                else
                    ui_error "rsync fallo. Ultimas lineas:
$(tail -n 6 "$LOG_FILE")"
                fi ;;
            "Preparar carpeta"*)
                mkdir -p "$BACKUP_DIR"
                ui_info "Carpeta a compartir en Syncthing:

$BACKUP_DIR

Anadela como carpeta en Syncthing (en cada equipo) y las copias
viajaran solas. Consejo: usa 'Enviar y recibir' en el equipo
principal y 'Solo recibir' en los demas para evitar conflictos." ;;
            *) return ;;
        esac
    done
}

# ----------------------------------------------------------------------------
# 4h. INTEGRIDAD Y ESPACIO EN DISCO
# ----------------------------------------------------------------------------
human_size() {
    # $1 = bytes -> "1,2 GB" / "340 MB"
    local b="${1:-0}"
    awk -v b="$b" 'BEGIN{
        if (b >= 1073741824) printf "%.1f GB", b/1073741824;
        else if (b >= 1048576) printf "%.0f MB", b/1048576;
        else if (b >= 1024) printf "%.0f KB", b/1024;
        else printf "%d B", b;
    }'
}

free_bytes() {
    # $1 = ruta -> bytes libres en su sistema de ficheros
    local d="$1"
    while [ -n "$d" ] && [ ! -d "$d" ]; do d="$(dirname "$d")"; done
    df -PB1 "${d:-/}" 2>/dev/null | awk 'NR==2{print $4}'
}

dir_bytes() {
    du -sb "$1" 2>/dev/null | awk '{print $1}'
}

check_space() {
    # $1 = bytes necesarios, $2 = ruta destino, $3 = descripcion
    # Devuelve 1 si el usuario decide no continuar.
    local need="${1:-0}" dest="$2" what="${3:-la operacion}" free
    free="$(free_bytes "$dest")"
    [ -z "$free" ] && return 0
    say "[espacio] necesario ~$(human_size "$need") | libre $(human_size "$free") en $dest"
    if [ "$free" -lt "$need" ]; then
        ui_error "No hay espacio suficiente para $what.

Necesario:  ~$(human_size "$need")
Disponible:  $(human_size "$free")
En: $dest

Libera espacio (menu principal -> Espacio en disco) o elige otra carpeta."
        return 1
    fi
    # margen de seguridad: 2 GB fijos (un 10% de un juego enorme serian
    # varios GB de mas y bloquearia importaciones que si caben)
    if [ "$free" -lt "$(( need + 2147483648 ))" ]; then
        ui_ask "El espacio esta muy justo para $what.

Necesario:  ~$(human_size "$need")
Disponible:  $(human_size "$free")

Continuar de todos modos?" || return 1
    fi
    return 0
}

verify_squashfs() {
    # $1 = fichero. Comprueba que es un squashfs valido y que se puede leer.
    local f="$1" magic
    [ -f "$f" ] || { ui_error "No existe: $f"; return 1; }
    if [ ! -s "$f" ]; then
        ui_error "El fichero esta vacio: $(basename "$f")"
        return 1
    fi
    # cabecera: los squashfs empiezan por "hsqs" (o "sqsh" en big endian)
    magic="$(head -c 6 "$f" 2>/dev/null)"
    case "$magic" in
        hsqs*|sqsh*|DWARFS*) ;;
        *) ui_error "'$(basename "$f")' no parece una imagen valida.
Puede que la descarga o la copia se cortara a medias."
           return 1 ;;
    esac
    # DwarFS trae su propia comprobacion de integridad
    if [ "$(image_format "$f")" = "dwarfs" ]; then
        find_dwarfs_tools
        local ck="$RUNTIME_DIR/tools/dwarfsck"
        if [ -x "$ck" ]; then
            if ! run_with_progress "Comprobando '$(basename "$f")' (DwarFS)..." \
                    sh -c "'$ck' '$f' >/dev/null 2>&1"; then
                ui_error "La imagen DwarFS esta danada: $(basename "$f")"
                return 1
            fi
        fi
        return 0
    fi
    # prueba de lectura real: listar el contenido con unsquashfs si esta
    if command -v unsquashfs >/dev/null 2>&1; then
        if ! run_with_progress "Comprobando '$(basename "$f")'..." \
                sh -c "unsquashfs -s '$f' >/dev/null 2>&1"; then
            ui_error "El archivo esta danado (no se puede leer su indice):
$(basename "$f")"
            return 1
        fi
    else
        # sin unsquashfs: montarlo y leer un fichero
        local t; t="$(mktemp -d)"
        if ! "$SQUASHFUSE_BIN" "$f" "$t" >>"$LOG_FILE" 2>&1; then
            rmdir "$t" 2>/dev/null
            ui_error "El archivo no se puede montar (posible corrupcion):
$(basename "$f")"
            return 1
        fi
        find "$t" -maxdepth 2 -type f 2>/dev/null | head -n1 >/dev/null
        "$FUSERMOUNT_BIN" -u "$t" 2>/dev/null
        rmdir "$t" 2>/dev/null
    fi
    return 0
}

disk_report() {
    # Inventario de lo que ocupa WProton, por partes
    local games ov pfx cache runtime bkp cov total
    games="$(dir_bytes "$GAMES_PATH")"
    ov="$(dir_bytes "$OVERLAY_BASE")"
    pfx="$(dir_bytes "$PREFIX_DIR")"
    cache="$(dir_bytes "$CACHE_DIR")"
    runtime="$(dir_bytes "$RUNTIME_DIR")"
    bkp="$(dir_bytes "$BACKUP_DIR")"
    cov="$(dir_bytes "$COVERS_DIR")"
    total=$(( ${games:-0} + ${ov:-0} + ${pfx:-0} + ${cache:-0} + ${runtime:-0} + ${bkp:-0} + ${cov:-0} ))
    printf 'Juegos:            %s\n' "$(human_size "${games:-0}")"
    printf 'Saves (overlays):  %s\n' "$(human_size "${ov:-0}")"
    printf 'Prefijos:          %s\n' "$(human_size "${pfx:-0}")"
    printf 'Cache de shaders:  %s\n' "$(human_size "${cache:-0}")"
    printf 'Runners y runtime: %s\n' "$(human_size "${runtime:-0}")"
    printf 'Copias de saves:   %s\n' "$(human_size "${bkp:-0}")"
    printf 'Caratulas:         %s\n' "$(human_size "${cov:-0}")"
    printf -- '-------------------------------\n'
    printf 'TOTAL:             %s\n' "$(human_size "$total")"
    printf 'Libre en el disco: %s\n' "$(human_size "$(free_bytes "$BASE_DIR")")"
}

disk_games_list() {
    # Tamano por juego (archivo + su overlay + su prefijo propio), de mayor a menor
    local f gid a o p t
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        gid="$(game_id "$f")"
        a="$(dir_bytes "$f")"; a="${a:-0}"
        o="$(dir_bytes "$OVERLAY_BASE/$gid")"; o="${o:-0}"
        p=0
        [ -d "$PREFIX_DIR/$gid" ] && { p="$(dir_bytes "$PREFIX_DIR/$gid")"; p="${p:-0}"; }
        t=$(( a + o + p ))
        printf '%015d\t%s (%s)\n' "$t" "$(basename "$f")" "$(human_size "$t")"
    done <<EOFG
$(find "$GAMES_PATH" -maxdepth 3 -type f \( -iname '*.wsquashfs' -o -iname '*.squashfs' -o -iname '*.dwarfs' \) 2>/dev/null)
EOFG
}

orphan_scan() {
    # Prefijos y overlays de juegos que ya no estan. Imprime "tipo|ruta|tamano"
    local d gid found
    for d in "$OVERLAY_BASE"/*/ "$PREFIX_DIR"/*/; do
        [ -d "$d" ] || continue
        gid="$(basename "$d")"
        case "$gid" in default|__wptools__|.*) continue ;; esac
        found=0
        while IFS= read -r f; do
            [ -n "$f" ] || continue
            [ "$(game_id "$f")" = "$gid" ] && { found=1; break; }
        done <<EOFO
$(find "$GAMES_PATH" -maxdepth 3 \( -iname '*.wsquashfs' -o -iname '*.squashfs' -o -iname '*.dwarfs' \) 2>/dev/null)
EOFO
        [ "$found" = 1 ] && continue
        # tampoco es un juego en carpeta ni un perfil vivo
        [ -e "$GAMES_PATH/$gid" ] && continue
        [ -f "$PROFILE_DIR/$gid.conf" ] && continue
        case "$d" in
            "$OVERLAY_BASE"/*) printf 'overlay|%s|%s\n' "$d" "$(dir_bytes "$d")" ;;
            *)                 printf 'prefijo|%s|%s\n' "$d" "$(dir_bytes "$d")" ;;
        esac
    done 2>/dev/null
}

disk_menu() {
    local sel
    while true; do
        sel="$(menu "Espacio en disco" \
            "Mostrar el tamano de WProton" \
            "Tamano por juego" \
            "Limpiar cache de shaders" \
            "Buscar prefijos y saves huerfanos" \
            "Borrar copias de saves antiguas" \
            "<< Volver")" || return
        case "$sel" in
            "Mostrar el tamano"*)
                ui_info "$(disk_report)" ;;
            "Tamano por juego")
                local lst
                lst="$(disk_games_list | sort -r | cut -f2- | head -n 40)"
                if [ -z "$lst" ]; then
                    ui_info "No hay juegos en $GAMES_PATH"
                else
                    # shellcheck disable=SC2046
                    (IFS=$'\n'; set -f; menu "Tamano por juego (juego + saves + prefijo)" $lst "<< Volver") >/dev/null || true
                fi ;;
            "Limpiar cache de shaders")
                local csz; csz="$(dir_bytes "$CACHE_DIR")"
                if [ "${csz:-0}" -lt 1048576 ]; then
                    ui_info "La cache de shaders apenas ocupa ($(human_size "${csz:-0}"))."
                elif ui_ask "Borrar la cache de shaders ($(human_size "${csz:-0}"))?

No se pierde nada del juego: se vuelve a generar sola,
aunque los primeros minutos pueden tener algun tiron."; then
                    rm -rf "${CACHE_DIR:?}"/* 2>/dev/null
                    mkdir -p "$CACHE_DIR"
                    ui_info "Cache de shaders vaciada."
                fi ;;
            "Buscar prefijos"*)
                local orph tot=0 lines=""
                orph="$(orphan_scan)"
                if [ -z "$orph" ]; then
                    ui_info "No hay prefijos ni saves huerfanos: todo corresponde
a juegos que sigues teniendo."
                    continue
                fi
                local tipo ruta tam
                while IFS='|' read -r tipo ruta tam; do
                    [ -n "$ruta" ] || continue
                    tot=$(( tot + ${tam:-0} ))
                    lines="$lines$tipo: $(basename "$ruta") ($(human_size "${tam:-0}"))
"
                done <<EOFL
$orph
EOFL
                if ui_ask "Elementos de juegos que ya no tienes:

$lines
Total: $(human_size "$tot")

Borrarlos? (los saves de esos juegos se perderan)"; then
                    while IFS='|' read -r tipo ruta tam; do
                        [ -n "$ruta" ] && rm -rf "$ruta" && say "[limpieza] borrado $ruta"
                    done <<EOFD
$orph
EOFD
                    ui_info "Liberados $(human_size "$tot")."
                fi ;;
            "Borrar copias de saves antiguas")
                local n; n="$(find "$BACKUP_DIR" -maxdepth 1 -name '*.zip' 2>/dev/null | wc -l)"
                if [ "${n:-0}" -eq 0 ]; then
                    ui_info "No hay copias de partidas guardadas."
                elif ui_ask "Hay $n copias ($(human_size "$(dir_bytes "$BACKUP_DIR")")).

Conservar solo las 3 mas recientes de cada juego?"; then
                    local base
                    for base in $(find "$BACKUP_DIR" -maxdepth 1 -name '*.zip' -printf '%f\n' 2>/dev/null \
                                  | sed 's/_[0-9]\{8\}_[0-9]\{4\}\.zip$//' | sort -u); do
                        find "$BACKUP_DIR" -maxdepth 1 -name "${base}_*.zip" -printf '%T@ %p\n' 2>/dev/null \
                            | sort -rn | tail -n +4 | cut -d' ' -f2- | while IFS= read -r old; do
                                rm -f "$old"; say "[limpieza] borrada copia $old"
                            done
                    done
                    ui_info "Copias antiguas eliminadas."
                fi ;;
            *) return ;;
        esac
    done
}

fmt_playtime() {
    # segundos -> "3 h 12 min" / "45 min" / "2 min"
    local t="${1:-0}" h m
    h=$(( t / 3600 )); m=$(( (t % 3600) / 60 ))
    if [ "$h" -gt 0 ]; then printf '%d h %d min' "$h" "$m"
    elif [ "$m" -gt 0 ]; then printf '%d min' "$m"
    else printf '<1 min'; fi
}

stats_record() {
    # $1 = gid, $2 = segundos de la sesion. Suma al perfil del juego.
    local gid="$1" secs="${2:-0}"
    [ -n "$gid" ] || return 0
    [ "$secs" -lt 20 ] && return 0        # arranques fallidos no cuentan
    local f="$PROFILE_DIR/$gid.conf"
    [ -f "$f" ] || return 0
    local pc ps
    pc=$(( ${PLAY_COUNT:-0} + 1 ))
    ps=$(( ${PLAY_SECONDS:-0} + secs ))
    PLAY_COUNT="$pc"; PLAY_SECONDS="$ps"
    LAST_PLAYED="$(date '+%Y-%m-%d %H:%M')"
    write_full_profile "$gid"
    say "[+] Sesion: $(fmt_playtime "$secs") | total: $(fmt_playtime "$ps") en $pc partidas"
    return 0
}

gamepad_retrigger() {
    # Re-deteccion diferida del mando (del script antiguo): dispara un evento
    # udev "add" para que SDL2/Wine reinicialice botones y ejes del pad
    sleep 8
    udevadm trigger --subsystem-match=input --action=add 2>/dev/null || {
        local ev
        for ev in /sys/class/input/js*/device/uevent; do
            [ -w "$ev" ] && echo "add" > "$ev" 2>/dev/null
        done
    }
}

import_input() {
    # Dispatcher de entrada estilo PortProton antiguo
    local input="$1"
    case "$input" in
        *.wsquashfs|*.squashfs|*.dwarfs|*.WSQUASHFS|*.SQUASHFS|*.DWARFS)
            launch_game "$input" "auto" ;;
        *.sh)
            pad_bridge_stop
            bash "$input" ;;
        *.exe|*.EXE)
            [ -f "$input" ] || die "No existe: $input"
            play_any "$input" ;;
        *)
            if [ -d "$input" ]; then
                play_folder "$input"
            elif printf '%s' "$input" | grep -qiE "$ARCHIVE_REGEX"; then
                [ -f "$input" ] || die "No existe: $input"
                import_archive "$input"
            elif [ -f "$input" ]; then
                # extension desconocida: intentar como squash
                launch_game "$input" "auto"
            else
                die "No existe el fichero: $input"
            fi ;;
    esac
}

# ----------------------------------------------------------------------------
# 15. MENUS DE CONFIGURACION (estilo PortProton)
# ----------------------------------------------------------------------------
onoff() { [ "$1" = 1 ] && printf 'ON' || printf 'OFF'; }

stats_line() {
    if [ "${PLAY_COUNT:-0}" -gt 0 ]; then
        printf '%s en %s partidas' "$(fmt_playtime "${PLAY_SECONDS:-0}")" "${PLAY_COUNT}"
    else
        printf 'sin partidas todavia'
    fi
}

pad_sdl_label() {
    case "${PAD_SDL:-auto}" in
        1) printf 'ON (forzado)' ;;
        0) printf 'OFF (forzado)' ;;
        *) local r; r="$(pad_sdl_auto)"
           printf 'AUTO -> %s (%s)' "$(onoff "${r%%|*}")" "${r#*|}" ;;
    esac
}

COVERS_DIR="$BASE_DIR/covers"
PROGRESS_PID=""
PROGRESS_FILE=""

progress_start() {
    # Ventana de progreso con pygame. $1 = titulo
    PROGRESS_PID=""; PROGRESS_FILE=""
    pygame_available || return 0
    pad_bridge_stop
    write_menu_pygame
    PROGRESS_FILE="$(mktemp)"
    printf '0|Preparando...\n' > "$PROGRESS_FILE"
    PYGAME_HIDE_SUPPORT_PROMPT=1 SDL_JOYSTICK_ALLOW_BACKGROUND_EVENTS=1 \
        env -u LD_PRELOAD "$PY_BIN" "$MENU_PYGAME_PY" progress "$1" "$PROGRESS_FILE" >> "$LOG_FILE" 2>&1 &
    PROGRESS_PID=$!
    return 0
}

progress_set() {
    # $1 = porcentaje (0 = barra indeterminada), $2 = texto
    [ -n "$PROGRESS_FILE" ] || return 0
    printf '%s|%s\n' "$1" "$2" > "$PROGRESS_FILE" 2>/dev/null
    return 0
}

progress_stop() {
    [ -n "$PROGRESS_FILE" ] && printf 'DONE|\n' > "$PROGRESS_FILE" 2>/dev/null
    if [ -n "$PROGRESS_PID" ]; then
        local i
        for i in 1 2 3; do
            kill -0 "$PROGRESS_PID" 2>/dev/null || break
            sleep 0.2
        done
        kill "$PROGRESS_PID" 2>/dev/null
    fi
    [ -n "$PROGRESS_FILE" ] && rm -f "$PROGRESS_FILE"
    PROGRESS_PID=""; PROGRESS_FILE=""
    return 0
}

cover_for() {
    # $1 = gid -> ruta de la caratula si existe
    local e
    for e in png jpg jpeg webp; do
        [ -f "$COVERS_DIR/$1.$e" ] && { printf '%s' "$COVERS_DIR/$1.$e"; return 0; }
    done
    return 1
}

urlencode_py() {
    "$PY_BIN" -c 'import sys,urllib.parse;print(urllib.parse.quote(sys.argv[1]))' "$1" 2>/dev/null
}

sgdb_download_covers() {
    # Descarga caratulas 600x900 de SteamGridDB para los juegos sin caratula
    if [ -z "$SGDB_KEY" ]; then
        local k
        k="$(ask_text "Pega tu API key de SteamGridDB
(gratis en steamgriddb.com -> Profile -> Preferences -> API)" "")"
        [ -z "$k" ] && return 1
        SGDB_KEY="$k"; save_settings
    fi
    mkdir -p "$COVERS_DIR"
    local list total=0 got=0 pend=0 idx=0
    list="$(find "$GAMES_PATH" -maxdepth 3 -type f \( -iname '*.wsquashfs' -o -iname '*.squashfs' -o -iname '*.dwarfs' \) 2>/dev/null | sort)"
    [ -z "$list" ] && { ui_info "No hay juegos en $GAMES_PATH"; return 1; }
    local f gid title q gjson gameid ujson url ext
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        cover_for "$(game_id "$f")" >/dev/null || pend=$((pend+1))
    done <<EOF0
$list
EOF0
    [ "$pend" -eq 0 ] && { ui_info "Todos los juegos ya tienen caratula en covers/"; return 0; }
    progress_start "Descargando caratulas de SteamGridDB"
    while IFS= read -r f; do
        gid="$(game_id "$f")"
        cover_for "$gid" >/dev/null && continue
        total=$((total+1)); idx=$((idx+1))
        title="$(basename "$f")"; title="${title%.*}"; title="$(printf '%s' "$title" | tr '_.' '  ')"
        progress_set "$(( idx * 100 / pend ))" "($idx/$pend) $title"
        say "[SGDB] Buscando caratula: $title"
        q="$(urlencode_py "$title")"
        gjson="$(curl -fsSL -H "Authorization: Bearer $SGDB_KEY" \
            "https://www.steamgriddb.com/api/v2/search/autocomplete/$q" 2>>"$LOG_FILE")"
        if printf '%s' "$gjson" | grep -q '"success": *false'; then
            progress_stop
            ui_error "SteamGridDB rechazo la peticion (API key invalida?)"; return 1
        fi
        gameid="$(printf '%s' "$gjson" | grep -o '"id": *[0-9]*' | head -n1 | grep -o '[0-9]*')"
        [ -z "$gameid" ] && { say "[SGDB]   sin resultados para: $title"; continue; }
        ujson="$(curl -fsSL -H "Authorization: Bearer $SGDB_KEY" \
            "https://www.steamgriddb.com/api/v2/grids/game/$gameid?dimensions=600x900&types=static" 2>>"$LOG_FILE")"
        url="$(printf '%s' "$ujson" | grep -o '"url": *"[^"]*"' | head -n1 | cut -d'"' -f4 | sed 's|\\/|/|g')"
        [ -z "$url" ] && { say "[SGDB]   sin grids 600x900 para: $title"; continue; }
        ext="${url##*.}"; case "$ext" in png|jpg|jpeg|webp) ;; *) ext=png ;; esac
        if curl -fsSL "$url" -o "$COVERS_DIR/$gid.$ext" 2>>"$LOG_FILE"; then
            got=$((got+1)); say "[SGDB]   OK -> covers/$gid.$ext"
        fi
    done <<EOF2
$list
EOF2
    progress_stop
    ui_info "Caratulas: $got descargadas de $total pendientes.
(Las que falten: pon un png/jpg a mano en covers/<juego>.png)"
}

browse_start() {
    # Carpeta inicial del navegador: la ultima visitada. Si ya no existe
    # (p.ej. la carpeta del juego se borro al empaquetar), sube por sus
    # padres hasta encontrar una que siga estando.
    local d="${LAST_BROWSE:-}"
    while [ -n "$d" ] && [ "$d" != "/" ]; do
        [ -d "$d" ] && { printf '%s' "$d"; return 0; }
        d="$(dirname "$d")"
    done
    printf '%s' "${1:-$HOME}"
}

remember_browse() {
    # $1 = ruta elegida -> recordar la carpeta CONTENEDORA, no el juego:
    # si eliges ROMs/Windows/Constance se recuerda ROMs/Windows, que sigue
    # existiendo aunque luego se borre la carpeta del juego al empaquetar.
    local d="$1"
    [ -n "$d" ] || return 0
    d="$(dirname "$d")"
    [ -d "$d" ] || return 0
    if [ "$d" != "${LAST_BROWSE:-}" ]; then
        LAST_BROWSE="$d"
        save_settings
    fi
    return 0
}

browse_for_path() {
    # Navegador con el mando. Con pygame: UNA sola ventana persistente para
    # toda la navegacion (antes se relanzaba python+SDL por cada carpeta y en
    # la Deck se notaba lento). GTK/zenity/CLI conservan el bucle de menus.
    local title="$1" cur="$2" mode="$3" sel dirs files header
    [ -d "$cur" ] || cur="$HOME"
    cur="$(readlink -f "$cur")"
    if pygame_available; then
        pad_bridge_stop
        write_menu_pygame
        local tmpsel; tmpsel="$(mktemp)"
        PYGAME_HIDE_SUPPORT_PROMPT=1 SDL_JOYSTICK_ALLOW_BACKGROUND_EVENTS=1 \
            env -u LD_PRELOAD "$PY_BIN" "$MENU_PYGAME_PY" browse "$title" "$tmpsel" "$cur" "$mode" >> "$LOG_FILE" 2>&1
        sel="$(cat "$tmpsel")"; rm -f "$tmpsel"
        if [ -z "$sel" ]; then
            log "BROWSE [$title] -> cancelado"
            return 1
        fi
        log "BROWSE [$title] -> [$sel]"
        remember_browse "$sel"
        printf '%s' "$sel"
        return 0
    fi
    while true; do
        dirs="$(find "$cur" -mindepth 1 -maxdepth 1 -type d ! -name '.*' -printf '%f/\n' 2>/dev/null | sort)"
        files=""
        if [ "$mode" = "keys" ]; then
            files="$(find "$cur" -mindepth 1 -maxdepth 1 -type f -iname '*.keys' ! -name '.*' -printf '%f\n' 2>/dev/null | sort)"
            header=".. (subir)"
        elif [ "$mode" = "file" ] || [ "$mode" = "play" ]; then
            files="$(find "$cur" -mindepth 1 -maxdepth 1 -type f \( \
                -iname '*.wsquashfs' -o -iname '*.squashfs' -o -iname '*.dwarfs' -o -iname '*.zip' \
                -o -iname '*.7z' -o -iname '*.rar' -o -iname '*.001' \
                -o -iname '*.z01' -o -iname '*.exe' -o -iname '*.wtgz' \) ! -name '.*' -printf '%f\n' 2>/dev/null | sort)"
            header=">> IMPORTAR ESTA CARPETA <<
.. (subir)"
            [ "$mode" = "play" ] && header=">> JUGAR ESTA CARPETA <<
.. (subir)"
        else
            header=">> USAR ESTA CARPETA <<
.. (subir)"
        fi
        # shellcheck disable=SC2046
        sel="$(IFS=$'\n'; set -f; menu "$title  [$cur]" $header $dirs $files)" || return 1
        case "$sel" in
            ">> IMPORTAR ESTA CARPETA <<"|">> USAR ESTA CARPETA <<"|">> JUGAR ESTA CARPETA <<")
                remember_browse "$cur"; printf '%s' "$cur"; return 0 ;;
            ".. (subir)")
                cur="$(dirname "$cur")" ;;
            */)
                cur="$cur/${sel%/}" ;;
            *)
                remember_browse "$cur"; printf '%s' "$cur/$sel"; return 0 ;;
        esac
    done
}

game_meta() {
    # $1 = ruta del juego -> "fav|last_played|play_seconds" leidos de su perfil
    local gid f fav=0 last="" secs=0
    gid="$(game_id "$1")"
    f="$PROFILE_DIR/$gid.conf"
    if [ -f "$f" ]; then
        fav="$(grep -m1 '^FAVORITO=' "$f" | cut -d= -f2 | tr -d '"')"
        last="$(grep -m1 '^LAST_PLAYED=' "$f" | cut -d= -f2- | tr -d '"')"
        secs="$(grep -m1 '^PLAY_SECONDS=' "$f" | cut -d= -f2 | tr -d '"')"
    fi
    printf '%s|%s|%s' "${fav:-0}" "${last:-}" "${secs:-0}"
}

sort_games() {
    # Ordena la lista (rutas relativas, una por linea) segun GAMES_SORT.
    # Los favoritos van SIEMPRE primero. Para los criterios descendentes
    # (recientes / mas jugados) se INVIERTE la clave numerica en vez de usar
    # "sort -r", que tambien invertiria la prioridad de los favoritos.
    local rel meta fav last secs n
    while IFS= read -r rel; do
        [ -n "$rel" ] || continue
        meta="$(game_meta "$GAMES_PATH/$rel")"
        fav="${meta%%|*}"; meta="${meta#*|}"
        last="${meta%%|*}"; secs="${meta#*|}"
        case "${GAMES_SORT:-nombre}" in
            recientes)
                n="$(printf '%s' "${last:-}" | tr -cd '0-9')"
                [ -z "$n" ] && n=0
                n="$(printf '%012d' "${n:0:12}")"
                printf '%d %012d\t%s\n' "$((1-fav))" "$(( 999999999999 - 10#$n ))" "$rel" ;;
            jugados)
                printf '%d %012d\t%s\n' "$((1-fav))" "$(( 999999999 - ${secs:-0} ))" "$rel" ;;
            *)
                printf '%d %s\t%s\n' "$((1-fav))" "$(printf '%s' "$rel" | tr 'A-Z' 'a-z')" "$rel" ;;
        esac
    done | sort | cut -f2-
}

pick_squash() {
    # Devuelve un wsquashfs de la biblioteca O una carpeta/exe suelto (navegador)
    local list loose="(juego suelto: elegir carpeta o exe...)"
    list="$(find "$GAMES_PATH" -maxdepth 3 -type f \( -iname '*.wsquashfs' -o -iname '*.squashfs' -o -iname '*.dwarfs' \) -printf '%P\n' 2>/dev/null | sort | sort_games)"
    local sel
    export WP_ACTION_X=1                 # X = configurar el juego resaltado
    if [ "$GAMES_VIEW" = "grid" ] && pygame_available && [ -n "$list" ]; then
        pad_bridge_stop
        write_menu_pygame
        local man tmpsel rel gid2 t2 cov
        man="$(mktemp)"; tmpsel="$(mktemp)"
        printf '%s\n' "(juego suelto: carpeta o exe)||__LOOSE__" >> "$man"
        while IFS= read -r rel; do
            gid2="$(game_id "$GAMES_PATH/$rel")"
            t2="$(basename "$rel")"; t2="${t2%.*}"
            cov="$(cover_for "$gid2")" || cov=""
            local mt fv sc lp info=""
            mt="$(game_meta "$GAMES_PATH/$rel")"
            fv="${mt%%|*}"; mt="${mt#*|}"; lp="${mt%%|*}"; sc="${mt#*|}"
            [ "${sc:-0}" -gt 0 ] 2>/dev/null && info="$info$(fmt_playtime "$sc")"
            # OJO: nada de "|" aqui. El manifiesto usa | como separador de
            # columnas: al jugar aparecia la fecha y partia la linea, con lo
            # que la ruta de la caratula se perdia y el juego salia sin ella.
            [ -n "$lp" ] && info="${info:+$info - }${lp%% *}"
            local t3="$t2$([ -n "$info" ] && printf '   [%s]' "$info")"
            t3="$(printf '%s' "$t3" | tr '|' '/')"     # el separador es sagrado
            printf '%s|%s|%s|%s\n' "$t3" "$cov" "$rel" "${fv:-0}" >> "$man"
        done <<EOF2
$list
EOF2
        PYGAME_HIDE_SUPPORT_PROMPT=1 SDL_JOYSTICK_ALLOW_BACKGROUND_EVENTS=1 \
            env -u LD_PRELOAD "$PY_BIN" "$MENU_PYGAME_PY" grid "Elige un juego  [$GAMES_PATH]" \
            "$tmpsel" "$man" >> "$LOG_FILE" 2>&1
        sel="$(cat "$tmpsel")"; rm -f "$tmpsel" "$man"
        unset WP_ACTION_X
        [ -z "$sel" ] && { log "GRID -> cancelado"; return 1; }
        log "GRID -> [$sel]"
        if [ "${sel#WPACT:CONFIG|}" != "$sel" ]; then
            local rel="${sel#WPACT:CONFIG|}"
            [ "$rel" = "__LOOSE__" ] && return 1
            printf 'WPACT:CONFIG|%s' "$GAMES_PATH/$rel"
            return 0
        fi
        if [ "$sel" = "__LOOSE__" ]; then
            browse_for_path "Juego suelto (carpeta o exe)" "$(browse_start "$HOME")" "play"
            return $?
        fi
        printf '%s' "$GAMES_PATH/$sel"
        return 0
    fi
    # shellcheck disable=SC2046
    sel="$(IFS=$'\n'; set -f; menu "Elige un juego  [$GAMES_PATH]" "$loose" $list)"
    local src=$?
    if [ "$src" != 0 ]; then unset WP_ACTION_X; return "$src"; fi
    unset WP_ACTION_X
    if [ "${sel#WPACT:CONFIG|}" != "$sel" ]; then
        local rel2="${sel#WPACT:CONFIG|}"
        [ "$rel2" = "$loose" ] && return 1
        printf 'WPACT:CONFIG|%s' "$GAMES_PATH/$rel2"
        return 0
    fi
    if [ "$sel" = "$loose" ]; then
        browse_for_path "Juego suelto (carpeta o exe)" "$(browse_start "$HOME")" "play"
        return $?
    fi
    printf '%s' "$GAMES_PATH/$sel"
}

config_pick_exe() {
    local squash="$1" gid="$2"
    acquire_game_root "$squash" "$gid" ro
    local ro="$MOUNT_POINT"
    wizard_pick_exe "$ro" && write_full_profile "$gid"
    release_game_root
}

config_gamescope() {
    local gid="$1" sel
    sel="$(menu "Gamescope (actual: ${GAMESCOPE:-OFF})" \
        "Desactivado" \
        "1280x800 (Steam Deck)" \
        "1280x720" \
        "1920x1080" \
        "Pantalla completa nativa" \
        "Personalizado (escribir argumentos)")" || return
    case "$sel" in
        "Desactivado")        GAMESCOPE="" ;;
        "1280x800"*)          GAMESCOPE="-W 1280 -H 800 -f" ;;
        "1280x720")           GAMESCOPE="-W 1280 -H 720 -f" ;;
        "1920x1080")          GAMESCOPE="-W 1920 -H 1080 -f" ;;
        "Pantalla completa"*) GAMESCOPE="-f" ;;
        "Personalizado"*)     GAMESCOPE="$(ask_text "Argumentos de gamescope" "${GAMESCOPE:--W 1280 -H 800 -f}")" ;;
    esac
    write_full_profile "$gid"
}

game_config_menu() {
    # $1 = juego (wsquashfs o carpeta), $2 = gid explicito (opcional: al venir
    # del flujo de importacion, el perfil es el del nombre limpio del juego)
    local squash="$1"
    local gid; gid="${2:-$(game_id "$squash")}"

    # Si nunca se configuro, pasar por el asistente primero
    if ! profile_exists "$gid"; then
        acquire_game_root "$squash" "$gid" ro
        local ro="$MOUNT_POINT"
        first_run_wizard "$gid" "$ro" || { release_game_root; return; }
        release_game_root
    fi
    load_profile "$gid"

    while true; do
        local bat_row=" "
        [ "$IS_BATOCERA" = 1 ] && bat_row="Lanzar via batocera-wine: $(onoff "${USE_BATOCERA:-1}")"
        local gs_row=" "
        [ "${IS_GAMESCOPE:-0}" = 1 ] && gs_row="Gamescope anidado (solo si no vuelve al menu): $(onoff "${NESTED_GAMESCOPE:-0}")"
        local pack_row=""
        [ -d "$squash" ] && pack_row=">> EMPAQUETAR A WSQUASHFS <<"
        local kstat="ninguno (auto si existe <juego>.keys)" kf0=""
        kf0="$(find_keys_file "$squash" "$gid")" || kf0=""
        [ -n "$kf0" ] && kstat="$(basename "$kf0") [auto al lanzar]"
        local sel
        sel="$(menu "Configuracion de: $gid" \
            ">> JUGAR AHORA <<" \
            "Runner (Proton/Wine): ${RUNNER:-auto (ultimo GE-Proton)}" \
            "Ejecutable: ${EXE_OVERRIDE:-auto (autorun.cmd / escaneo)}" \
            "Argumentos: ${ARGS_OVERRIDE:-ninguno}" \
            "Prefijo: $(prefix_label)" \
            "GAMEID (protonfixes): $GAMEID" \
            "MangoHud: $(onoff "$MANGOHUD")" \
            "Mando via SDL (DualSense como Xbox): $(pad_sdl_label)" \
            "NTsync (sincronizacion por kernel): $(onoff "${NTSYNC:-0}")$([ -e /dev/ntsync ] || printf ' [sin /dev/ntsync]')" \
            "Arreglo mando SteamOS (Steam Input): $(onoff "${PAD_STEAMFIX:-1}")" \
            "$gs_row" \
            "$bat_row" \
            "GameMode: $(onoff "$GAMEMODE")" \
            "Fsync: $(onoff "$FSYNC")" \
            "Esync: $(onoff "$ESYNC")" \
            "DXVK Async + GPL: $(onoff "$DXVK_ASYNC")" \
            "WineD3D (OpenGL, juegos viejos): $(onoff "$WINED3D")" \
            "FSR escalado pantalla completa: $(onoff "$FSR")" \
            "LAA (32bit +2GB RAM): $(onoff "$LAA")" \
            "Wayland nativo: $(onoff "$WAYLAND")" \
            "Gamescope: ${GAMESCOPE:-OFF}" \
            "DLL overrides: ${DLL_OVERRIDES:-ninguno}" \
            "Idioma del juego: ${GAME_LANG:-sistema}" \
            "Variables extra: ${EXTRA_ENV:-ninguna}" \
            "Instalar dgVoodoo2 (DX1-9/Glide en juegos viejos)" \
            "Configurar dgVoodoo (Cpl)" \
            "Instalar OptiScaler (FSR/DLSS/XeSS upscaling)" \
            "Abrir winecfg" \
            "Abrir winetricks" \
            "Mapeador .keys: $kstat" \
            "Favorito: $(onoff "${FAVORITO:-0}")" \
            "Notas: ${NOTAS:-(ninguna)}" \
            "Estadisticas: $(stats_line)" \
            "Partidas guardadas (copias de seguridad)" \
            "Comprobar integridad y ver tamano" \
            "$pack_row" \
            "Anadir este juego a Steam" \
            "Repetir asistente de primera ejecucion" \
            "Borrar prefijo (reinstala DLLs)" \
            "Borrar saves del overlay (upper/)" \
            "<< Volver")" || return

        case "$sel" in
            ">> JUGAR AHORA <<") play_any "$squash"; load_profile "$gid" ;;
            "Runner"*)
                HAS_BUNDLED_RUNNER=0
                acquire_game_root "$squash" "$gid" ro
                [ -n "$(find_bundled_runner "$MOUNT_POINT")" ] && HAS_BUNDLED_RUNNER=1
                release_game_root
                wizard_pick_runner && write_full_profile "$gid" ;;
            "Ejecutable:"*)   config_pick_exe "$squash" "$gid" ;;
            "Argumentos:"*)
                ARGS_OVERRIDE="$(ask_text "Argumentos de lanzamiento" "$ARGS_OVERRIDE")"
                write_full_profile "$gid" ;;
            "Prefijo:"*)
                local psel
                psel="$(menu "Prefijo de Wine para $gid (actual: $(prefix_label))" \
                    "Compartido (prefixes/default)" \
                    "Propio del juego (prefixes/$gid)" \
                    "Incluido en el wsquashfs (estilo Batocera)")" || psel=""
                case "$psel" in
                    "Compartido"*) PREFIX_MODE="shared"; write_full_profile "$gid" ;;
                    "Propio"*)     PREFIX_MODE="own";    write_full_profile "$gid" ;;
                    "Incluido"*)
                        acquire_game_root "$squash" "$gid" ro
                        local ro2="$MOUNT_POINT"
                        if has_bundled_prefix "$ro2"; then
                            PREFIX_MODE="bundled"; write_full_profile "$gid"
                            release_game_root
                            ui_info "Prefix incluido activado."
                        else
                            release_game_root
                            ui_error "Este juego NO incluye un prefix de Wine (falta drive_c/ + system.reg)"
                        fi ;;
                esac ;;
            "GAMEID"*)
                GAMEID="$(ask_text "GAMEID de umu-database (umu-default = generico).
Solo aplica a runners Proton. Busca el id en https://umu.openwinecomponents.org" "$GAMEID")"
                [ -z "$GAMEID" ] && GAMEID="umu-default"
                write_full_profile "$gid" ;;
            "MangoHud:"*)     MANGOHUD=$((1-MANGOHUD));     write_full_profile "$gid" ;;
            "Lanzar via batocera-wine"*)
                USE_BATOCERA=$((1-${USE_BATOCERA:-1})); write_full_profile "$gid" ;;
            "NTsync"*)
                NTSYNC=$((1-${NTSYNC:-0})); write_full_profile "$gid" ;;
            "Arreglo mando SteamOS"*)
                PAD_STEAMFIX=$((1-${PAD_STEAMFIX:-1})); write_full_profile "$gid" ;;
            "Gamescope anidado"*)
                NESTED_GAMESCOPE=$((1-${NESTED_GAMESCOPE:-0}))
                write_full_profile "$gid"
                [ "${NESTED_GAMESCOPE}" = 1 ] && ui_info "Gamescope anidado activado para este juego.
Ayuda a volver al menu en modo Juego, pero algunos juegos
avisan de 'Hooking has failed' o van a tirones. Si pasa,
desactivalo aqui mismo." ;;
            "Mando via SDL"*)
                case "${PAD_SDL:-auto}" in
                    auto) PAD_SDL=1 ;;
                    1)    PAD_SDL=0 ;;
                    *)    PAD_SDL=auto ;;
                esac
                write_full_profile "$gid"
                # el registro del prefijo debe reevaluarse
                rm -f "$(prefix_path "$gid")/.wp_pad_sdl" 2>/dev/null ;;
            "GameMode:"*)     GAMEMODE=$((1-GAMEMODE));     write_full_profile "$gid" ;;
            "Fsync:"*)        FSYNC=$((1-FSYNC));           write_full_profile "$gid" ;;
            "Esync:"*)        ESYNC=$((1-ESYNC));           write_full_profile "$gid" ;;
            "DXVK Async"*)    DXVK_ASYNC=$((1-DXVK_ASYNC)); write_full_profile "$gid" ;;
            "WineD3D"*)       WINED3D=$((1-WINED3D));       write_full_profile "$gid" ;;
            "FSR"*)           FSR=$((1-FSR));               write_full_profile "$gid" ;;
            "LAA"*)           LAA=$((1-LAA));               write_full_profile "$gid" ;;
            "Wayland"*)       WAYLAND=$((1-WAYLAND));       write_full_profile "$gid" ;;
            "Gamescope:"*)    config_gamescope "$gid" ;;
            "DLL overrides:"*)
                DLL_OVERRIDES="$(ask_text "WINEDLLOVERRIDES (ej: d3d9,ddraw=n,b ; winmm=n,b)" "$DLL_OVERRIDES")"
                write_full_profile "$gid" ;;
            "Idioma del juego:"*)
                GAME_LANG="$(ask_text "Locale (vacio = sistema; ej: ru_RU.UTF-8, ja_JP.UTF-8, en_US.UTF-8)" "$GAME_LANG")"
                write_full_profile "$gid" ;;
            "Variables extra:"*)
                EXTRA_ENV="$(ask_text "Variables extra (ej: PROTON_USE_WINED3D=1)" "$EXTRA_ENV")"
                write_full_profile "$gid" ;;
            "Instalar dgVoodoo2"*)  install_dgvoodoo "$squash" "$gid"; load_profile "$gid" ;;
            "Configurar dgVoodoo"*) config_dgvoodoo_cpl "$squash" "$gid" ;;
            "Instalar OptiScaler"*) install_optiscaler "$squash" "$gid"; load_profile "$gid" ;;
            "Abrir winecfg")    run_in_prefix "$squash" "$gid" winecfg ;;
            "Abrir winetricks") run_in_prefix "$squash" "$gid" winetricks --gui ;;
            ">> EMPAQUETAR A WSQUASHFS <<")
                # El juego es una carpeta: comprimirlo conservando su perfil
                if do_pack_dir "$squash" "$gid"; then
                    ui_info "Empaquetado: $(basename "$PACKED_OUT")
La configuracion de '$gid' se conserva para el wsquashfs."
                    if ui_ask "Jugar ahora desde el wsquashfs?"; then
                        launch_game "$PACKED_OUT" "auto"
                    fi
                    [ -d "$squash" ] || return 0   # la carpeta ya no existe
                fi ;;
            "Anadir este juego a Steam")
                add_game_to_steam "$squash" "$gid" ;;
            "Favorito:"*)
                FAVORITO=$((1-${FAVORITO:-0})); write_full_profile "$gid" ;;
            "Notas:"*)
                NOTAS="$(ask_text "Notas de este juego (argumentos que necesita, runner recomendado...)" "${NOTAS:-}")"
                write_full_profile "$gid" ;;
            "Partidas guardadas"*) backup_menu "$gid" ;;
            "Comprobar integridad"*)
                local gsz osz psz
                gsz="$(dir_bytes "$squash")"
                osz="$(dir_bytes "$OVERLAY_BASE/$gid" 2>/dev/null)"
                psz="$(dir_bytes "$(prefix_path "$gid")" 2>/dev/null)"
                if [ -f "$squash" ] && verify_squashfs "$squash"; then
                    ui_info "Archivo correcto: $(basename "$squash")

Juego:            $(human_size "${gsz:-0}")
Saves (overlay):  $(human_size "${osz:-0}")
Prefijo:          $(human_size "${psz:-0}")
Libre en disco:   $(human_size "$(free_bytes "$squash")")"
                elif [ -d "$squash" ]; then
                    ui_info "Juego en carpeta (no hay archivo que comprobar)

Carpeta:          $(human_size "${gsz:-0}")
Prefijo:          $(human_size "${psz:-0}")
Libre en disco:   $(human_size "$(free_bytes "$squash")")"
                fi ;;
            # "Compartir este perfil": DESACTIVADO de momento. El envio por
            # pull request no es practico para la mayoria de usuarios; queda
            # pendiente decidir como se recogeran los perfiles. La funcion
            # community_share() sigue en el script, lista para reactivarla
            # anadiendo de nuevo su fila al menu de arriba.
            "Compartir este perfil"*) community_share "$gid" ;;
            "Estadisticas:"*)
                if [ "${PLAY_COUNT:-0}" -gt 0 ]; then
                    ui_ask "Partidas: ${PLAY_COUNT:-0}
Tiempo total: $(fmt_playtime "${PLAY_SECONDS:-0}")
Ultima vez: ${LAST_PLAYED:-nunca}

Poner el contador a cero?" && {
                        PLAY_COUNT=0; PLAY_SECONDS=0; LAST_PLAYED=""
                        write_full_profile "$gid"
                    }
                else
                    ui_info "Todavia no hay partidas registradas de este juego."
                fi ;;
            "Mapeador .keys"*)
                local kmenu
                kmenu="$(menu "Mapeador .keys para $gid (actual: $kstat)" \
                    "Asignar fichero .keys (se copia a profiles/$gid.keys)" \
                    "Quitar el .keys de profiles" \
                    "<< Volver")" || kmenu=""
                case "$kmenu" in
                    "Asignar"*)
                        local kfsel
                        kfsel="$(browse_for_path "Elige el fichero .keys" "$(browse_start "$HOME")" "keys")" || kfsel=""
                        if [ -n "$kfsel" ] && [ -f "$kfsel" ]; then
                            cp -f "$kfsel" "$PROFILE_DIR/$gid.keys"
                            ui_info "Asignado: $(basename "$kfsel") -> profiles/$gid.keys
El mapeador se engancha SOLO al lanzar el juego (sin pulsar nada)."
                        fi ;;
                    "Quitar"*)
                        rm -f "$PROFILE_DIR/$gid.keys"
                        ui_info "Eliminado profiles/$gid.keys" ;;
                esac ;;
            "Repetir asistente"*)
                acquire_game_root "$squash" "$gid" ro
                local ro="$MOUNT_POINT"
                first_run_wizard "$gid" "$ro"
                release_game_root
                load_profile "$gid"
                ui_ask "Lanzar el juego ahora?" && launch_game "$squash" "auto" ;;
            "Borrar prefijo"*)
                if [ "$PREFIX_MODE" = "bundled" ]; then
                    ui_info "Con el prefix incluido, los cambios viven en el overlay:
usa 'Borrar saves del overlay (upper/)' para dejarlo de fabrica."
                    continue
                fi
                local pfx; pfx="$(prefix_path "$gid")"
                ui_ask "Borrar el prefijo $(basename "$pfx")?$([ "$PREFIX_MODE" = shared ] && printf '\nOJO: es el COMPARTIDO, afecta a todos los juegos que lo usan.')" \
                    && { rm -rf "$pfx"; ui_info "Prefijo borrado."; } ;;
            "Borrar saves"*)
                if [ -d "$squash" ]; then
                    ui_info "Este juego es una carpeta suelta: no usa overlay.
Los saves viven en la propia carpeta o en el prefijo."
                    continue
                fi
                ui_ask "SEGURO? Se borraran las partidas guardadas en el overlay de $gid" \
                    && { rm -rf "${OVERLAY_BASE:?}/$gid/upper"; ui_info "Overlay borrado."; } ;;
            "<< Volver") return ;;
        esac
    done
}

direct_play_loop() {
    # Modo solo-jugar: lista de juegos en bucle; al cancelar, se cierra.
    local g
    while true; do
        g="$(pick_squash)"
        local prc=$?
        if [ "$prc" = 2 ]; then
            say "Reintentando abrir la lista de juegos..."
            sleep 1
            continue
        fi
        [ "$prc" != 0 ] && break
        [ -n "$g" ] || break
        play_or_config "$g"
    done
    cleanup_all
    exit 0
}

main_dispatch() {
    local sel="$1"
    case "$sel" in
        "Jugar al ultimo:"*)
            play_any "$LAST_GAME" ;;
        "Jugar"*)
            local g; g="$(pick_squash)" && play_or_config "$g" ;;
        "Importar juego"*)
            local imp=""
            if pygame_available; then
                imp="$(browse_for_path "Importar juego (A: entrar/elegir, B: volver)" "$(browse_start "$HOME")" "file")" || imp=""
            elif [ "$HAS_ZENITY" = 1 ]; then
                pad_bridge_start
                imp="$(zenity --file-selection --title="Elige zip/7z/rar/exe o entra en la carpeta" 2>/dev/null)"
            else
                imp="$(ask_text "Ruta del archivo/carpeta a importar" "")"
            fi
            if [ -n "$imp" ]; then
                case "$imp" in
                    *.exe|*.EXE) package_exe "$imp" ;;
                    *) if [ -d "$imp" ]; then package_dir "$imp"; else import_input "$imp"; fi ;;
                esac
            fi ;;
        "Instalar librerias"*) redist_target_menu ;;
        "Configurar un juego"*)
            local g2
            if g2="$(pick_squash)"; then
                game_config_menu "${g2#WPACT:CONFIG|}"
            fi ;;
        "Descargar runners"*)    download_runner_menu ;;
        "Actualizar GE-Proton"*) setup_proton ;;
        "Actualizar umu-launcher") setup_umu ;;
        "Instalar/actualizar Python portable + pygame") setup_python ;;
        "Descargar herramientas DwarFS"*)
            if setup_dwarfs_tools; then
                find_dwarfs_tools
                ui_info "DwarFS listo en runtime/tools:
mkdwarfs para empaquetar y dwarfs para montar."
            fi ;;
        "Descargar herramientas FUSE"*)
            SQUASHFUSE_BIN=""; OVERLAYFS_BIN=""
            setup_fuse_tools
            ui_info "squashfuse:     ${SQUASHFUSE_BIN:-NO disponible}
fuse-overlayfs: ${OVERLAYFS_BIN:-NO disponible}" ;;
        "Descargar extractores GOG"*)
            local ok1="NO" ok2="NO"
            setup_innoextract && ok1="OK"
            setup_innounp && ok2="OK"
            ui_info "Extractores portables en runtime/tools:
  innoextract (principal, reensambla GOG Galaxy): $ok1
  innounp (respaldo via Wine, Inno Setup hasta 6.7): $ok2" ;;
        "Borrar un runner")
            local vers v
            vers="$(local_runner_names)"
            [ -z "$vers" ] && { ui_info "No hay runners instalados."; continue; }
            # shellcheck disable=SC2046
            if v="$(IFS=$'\n'; set -f; menu "Borrar runner" $vers)"; then
                ui_ask "Borrar $v?" && rm -rf "${RUNNERS_DIR:?}/$v"
            fi ;;
        "Idioma:"*)
            local langs li
            langs="$(lang_available)"
            # shellcheck disable=SC2046
            li="$(IFS=$'\n'; set -f; menu "Idioma de los menus / Menu language" $langs "<< Volver")" || li=""
            case "$li" in
                "<< Volver"|"") ;;
                *)  LANGUAGE="$li"; save_settings
                    export WP_LANG="$LANGUAGE"
                    tr_init
                    ui_info "Idioma: $LANGUAGE" ;;
            esac ;;
        "Tema de los menus:"*)
            local th
            th="$(menu "Elige el aspecto de los menus" \
                "clasico - el original" \
                "moderno - paneles y acento neon" \
                "arcade - synthwave con efecto CRT" \
                "<< Volver")" || th=""
            case "$th" in
                clasico*|moderno*|arcade*)
                    THEME="${th%% *}"
                    export WP_THEME="$THEME"
                    save_settings
                    ui_info "Tema activado: $THEME" ;;
            esac ;;
        "Espacio en disco") disk_menu ;;
        "Biblioteca y aspecto") library_menu ;;
        "Runners y herramientas"*) tools_menu ;;
        "Caratulas y perfiles"*) media_menu ;;
        "Formato al empaquetar:"*)
            local pf
            pf="$(menu "Formato para los juegos que empaquetes" \
                "wsquashfs - compatible con Batocera y PortProton" \
                "dwarfs - comprime bastante mas, monta igual de rapido" \
                "<< Volver")" || pf=""
            case "$pf" in
                wsquashfs*)
                    PACK_FORMAT=wsquashfs; save_settings
                    ui_info "Los juegos nuevos se empaquetaran en wsquashfs." ;;
                dwarfs*)
                    find_dwarfs_tools || setup_dwarfs_tools || true
                    find_dwarfs_tools
                    if [ -n "$MKDWARFS_BIN" ]; then
                        PACK_FORMAT=dwarfs; save_settings
                        ui_info "Los juegos nuevos se empaquetaran en DwarFS.
Los wsquashfs que ya tienes se siguen usando igual."
                    else
                        ui_error "No se pudieron preparar las herramientas de DwarFS."
                    fi ;;
            esac ;;
        "Ordenar juegos por:"*)
            local so
            so="$(menu "Como ordenar la lista de juegos" \
                "nombre - alfabetico" \
                "recientes - los ultimos jugados primero" \
                "jugados - los de mas tiempo primero" \
                "<< Volver")" || so=""
            case "$so" in
                nombre*|recientes*|jugados*)
                    GAMES_SORT="${so%% *}"; save_settings
                    ui_info "Orden: $GAMES_SORT (los favoritos van siempre primero)" ;;
            esac ;;
        "Vista de juegos:"*)
            [ "$GAMES_VIEW" = grid ] && GAMES_VIEW=list || GAMES_VIEW=grid
            save_settings ;;
        "Perfiles de la comunidad"*) community_menu ;;
        "Descargar caratulas"*)
            sgdb_download_covers ;;
        "Carpeta de juegos:"*)
            local nd=""
            if pygame_available; then
                nd="$(browse_for_path "Elige la carpeta de juegos" "$GAMES_PATH" "dir")" || nd=""
            else
                nd="$(pick_dir "Elige la carpeta donde estan tus juegos" "$GAMES_PATH")"
            fi
            if [ -n "$nd" ] && [ -d "$nd" ]; then
                GAMES_PATH="$nd"; save_settings
                ui_info "Carpeta de juegos: $GAMES_PATH"
            fi ;;
        "Detener Wine y desmontar todo") kill_all ;;
        "Buscar actualizaciones"*) self_update ;;
        "Ver ultimo log")
            if [ "$HAS_ZENITY" = 1 ]; then
                zenity --text-info --title="WProton log" --filename="$LOG_FILE" \
                       --width=820 --height=620 2>/dev/null
            elif pygame_available; then
                local loglines
                loglines="$(tail -n 60 "$LOG_FILE" | grep -v '^$')"
                # shellcheck disable=SC2046
                (IFS=$'\n'; set -f; menu "Ultimo log (B para volver)" $loglines) >/dev/null 2>&1 || true
            else
                tail -n 50 "$LOG_FILE" >&2
            fi ;;
        "Salir") exit 0 ;;
    esac
    return 0
}

library_menu() {
    # Todo lo que afecta a como se ve y se ordena la biblioteca
    local sel
    while true; do
        sel="$(menu "Biblioteca y aspecto" \
            "Carpeta de juegos: $GAMES_PATH" \
            "Vista de juegos: $([ "$GAMES_VIEW" = grid ] && printf 'rejilla (caratulas)' || printf 'lista')" \
            "Ordenar juegos por: ${GAMES_SORT:-nombre}" \
            "Formato al empaquetar: ${PACK_FORMAT:-wsquashfs}" \
            "Tema de los menus: $THEME" \
            "Idioma: ${LANGUAGE:-es}" \
            "<< Volver")" || return
        case "$sel" in
            "<< Volver"|"") return ;;
            *) main_dispatch "$sel" ;;
        esac
    done
}

tools_menu() {
    # Instalacion y actualizacion de todo lo que WProton usa por debajo
    local sel nrunners
    while true; do
        nrunners="$(list_runners | grep -c . || true)"
        sel="$(menu "Runners y herramientas" \
            "Descargar runners (Proton / Wine) [$nrunners instalados]" \
            "Actualizar GE-Proton a la ultima" \
            "Borrar un runner" \
            "Instalar librerias en un prefijo (vcredist, PhysX...)" \
            "Actualizar umu-launcher" \
            "Instalar/actualizar Python portable + pygame" \
            "Descargar extractores GOG (innoextract + innounp)" \
            "Descargar herramientas FUSE portables (squashfuse, overlayfs)" \
            "Descargar herramientas DwarFS (mkdwarfs + driver)" \
            "<< Volver")" || return
        case "$sel" in
            "<< Volver"|"") return ;;
            *) main_dispatch "$sel" ;;
        esac
    done
}

media_menu() {
    local sel
    while true; do
        sel="$(menu "Caratulas y perfiles de la comunidad" \
            "Descargar caratulas (SteamGridDB)" \
            "Perfiles de la comunidad (juegos problematicos)" \
            "<< Volver")" || return
        case "$sel" in
            "<< Volver"|"") return ;;
            *) main_dispatch "$sel" ;;
        esac
    done
}

main_menu() {
    while true; do
        local nrunners; nrunners="$(list_runners | grep -c . || true)"
        local opts=("Jugar (elegir juego)")
        if [ -n "$LAST_GAME" ] && [ -e "$LAST_GAME" ]; then
            local lg; lg="$(basename "$LAST_GAME")"; lg="${lg%.*}"
            opts+=("Jugar al ultimo: $lg")
        fi
        opts+=("Importar juego (zip/7z/rar/exe/carpeta)" \
               "Configurar un juego" \
               "Biblioteca y aspecto" \
               "Runners y herramientas [$nrunners runners]" \
               "Caratulas y perfiles de la comunidad" \
               "Espacio en disco" \
               "Detener Wine y desmontar todo" \
               "Ver ultimo log" \
               "Buscar actualizaciones [v$WPROTON_VERSION]" \
               "Salir")
        local sel
        sel="$(menu "WProton v$WPROTON_VERSION - Menu principal" "${opts[@]}")"
        local mrc=$?
        if [ "$mrc" = 2 ]; then
            # el menu no se pudo dibujar: reintentar el bucle, no cerrar
            say "Reintentando abrir el menu principal..."
            sleep 1
            continue
        fi
        [ "$mrc" != 0 ] && exit 0

        main_dispatch "$sel"
    done
}

# ----------------------------------------------------------------------------
# 16. UTILIDADES
# ----------------------------------------------------------------------------
kill_all() {
    say "Deteniendo Wine y desmontando todo..."
    pkill -f 'wineserver' 2>/dev/null
    pkill -f 'winedevice' 2>/dev/null
    sleep 1
    sweep_stale_mounts
    ui_info "Todo desmontado."
}

bootstrap_if_needed() {
    # Python portable primero: umu, menus y extraccion zip dependen de el
    if [ ! -x "$PY_DIR/bin/python3" ]; then
        if [ -n "$SYS_PY" ]; then
            # hay python del sistema: instalar el portable en segundo plano no,
            # mejor ahora y en orden para que todo quede autocontenido
            setup_python || say "Aviso: sin Python portable, usando el del sistema"
        else
            setup_python || die "No hay python3 en el sistema ni se pudo instalar el portable"
        fi
    fi
    [ -x "$UMU_BIN" ] || setup_umu
    if [ -z "$(runner_names)" ]; then
        setup_proton
    fi
}

# ----------------------------------------------------------------------------
# 17. ENTRADA
# ----------------------------------------------------------------------------
case "${1:-}" in
    --version) printf 'WProton v%s\n' "$WPROTON_VERSION"; exit 0 ;;
esac

rotate_logs() {
    # Conservar solo los logs de los ultimos 2 dias (y 40 como maximo)
    [ -d "$LOG_DIR" ] || return 0
    find "$LOG_DIR" -maxdepth 1 -type f -name 'wproton_*.log' -mtime +2 -delete 2>/dev/null
    local n old
    n="$(find "$LOG_DIR" -maxdepth 1 -type f -name 'wproton_*.log' 2>/dev/null | wc -l)"
    if [ "$n" -gt 40 ]; then
        find "$LOG_DIR" -maxdepth 1 -type f -name 'wproton_*.log' -printf '%T@ %p\n' 2>/dev/null \
            | sort -n | head -n $((n - 40)) | cut -d' ' -f2- | while IFS= read -r old; do
                rm -f "$old"
            done
    fi
    return 0
}

export WP_THEME="${THEME:-clasico}"
export WP_GRID_COLS="${GRID_COLS:-0}"
export WP_LANG="${LANGUAGE:-es}"

check_deps
rotate_logs          # no acumular cientos de logs antiguos
sweep_stale_mounts   # limpiar restos de sesiones anteriores (ro/merged llenos)
pkill -f "$PAD_BRIDGE_PY" 2>/dev/null   # puentes uinput zombis -> fuera

case "${1:-}" in
    --setup)  setup_python; setup_umu; setup_proton
              ui_info "Runtime listo. Lanza juegos por CLI o entra al menu.
Mas runners: menu principal -> Descargar runners" ;;
    --kill)   kill_all ;;
    --config)
        bootstrap_if_needed
        if [ -n "${2:-}" ]; then
            [ -f "$2" ] || die "No existe el fichero: $2"
            game_config_menu "$2"
        else
            main_menu
        fi ;;
    --version)
        printf 'WProton v%s\n' "$WPROTON_VERSION"; exit 0 ;;
    --update)
        bootstrap_if_needed
        self_update; exit $? ;;
    --exe)
        [ -z "${2:-}" ] && die "Uso: $0 --exe juego.wsquashfs"
        bootstrap_if_needed
        launch_game "$2" "manual" ;;
    --import)
        # Forzar el flujo de importacion/empaquetado (probar/comprimir) para
        # exe o carpeta; los comprimidos ya importan solos sin este flag
        [ -z "${2:-}" ] && die "Uso: $0 --import <exe|carpeta|zip|7z|rar>"
        bootstrap_if_needed
        case "$2" in
            *.exe|*.EXE) package_exe "$2" ;;
            *) if [ -d "$2" ]; then package_dir "$2"; else import_input "$2"; fi ;;
        esac ;;
    --menu)
        # Salida de emergencia del modo solo-jugar: menu completo siempre
        bootstrap_if_needed
        canvas_start
        main_menu ;;
    --play|--games)
        bootstrap_if_needed
        canvas_start
        direct_play_loop ;;
    "")
        bootstrap_if_needed
        canvas_start
        if [ "${DIRECT_PLAY:-0}" = 1 ]; then
            direct_play_loop
        else
            main_menu
        fi ;;
    *)
        # === LANZAMIENTO CLI (frontends): wsquashfs, zip/7z/rar, exe, carpeta, sh ===
        bootstrap_if_needed
        import_input "$1" ;;
esac
