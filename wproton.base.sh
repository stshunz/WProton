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
#     ./wproton.sh --config [juego]        -> menu de configuración
#     ./wproton.sh                         -> menu principal
# ============================================================================

set -u  # (NO set -e: la limpieza controlada es nuestra, leccion de update.sh)

# ----------------------------------------------------------------------------
# VERSION de WProton (nomenclatura: 0.5 -> 0.51 -> 0.52... salto grande -> 0.6)
# ----------------------------------------------------------------------------
WPROTON_VERSION="1.18"
# Repo de GitHub para las auto-actualizaciones (rellenar al subirlo):
#   formato "usuario/repo", p.ej. "dani/wproton". Las releases deben llevar
#   tag "v<versión>" (v0.5, v0.51...) y el script como asset o en la rama main.
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
LAST_GAME=""                             # último juego lanzado (ruta completa)
GAMES_VIEW="list"                        # list | grid | banner (panorámica) | cuadro (4:3)
LIST_COVER=vertical                      # forma de la carátula en la vista de lista
LAST_BROWSE=""                           # última carpeta visitada en el navegador
THEME="moderno"                          # aspecto de los menus: clasico | moderno | arcade
DIRECT_PLAY=0                            # 1 = arrancar directo en la lista de juegos
GRID_COLS=0                              # columnas de la rejilla (0 = automático)
LANGUAGE=es                              # idioma de los menus: es | en
GAMES_SORT=nombre                        # nombre | recientes | jugados
PACK_FORMAT=wsquashfs                    # wsquashfs | dwarfs (más compresion)
GAME_MODE_CANVAS=1                       # fondo entre menus (evita ver el escritorio)
MENU_SERVER=1                            # 1 = un solo proceso para todos los menus
OCULTAR_CURSOR=1                         # esconder el puntero mientras juegas
DIAG_MANDO=0                             # 1 = registro detallado del mando
PAD_EXIT=1                               # cerrar el juego con el mando
PAD_EXIT_COMBO=select                    # select | l3r3 | start
PAD_EXIT_SEGUNDOS=5                      # cuanto hay que mantener la combinacion
GAMES_PATHS_EXTRA=""                     # carpetas de juegos adicionales
GE_CUSTOM_NAME="GE-Custom"               # nombre del runner propio
GE_CUSTOM_URL="https://www.mediafire.com/file/oqprcy5dpju5m1k/ge-custom.tar.gz/file"
FONT_SCALE=1.0                           # tamaño de letra: 1.0 | 1.25 | 1.5
BACKUP_SYNC_DEST=""                      # destino rsync para backups/
SGDB_KEY=""                              # API key de steamgriddb.com (carátulas)
save_settings() {
    # RED DE SEGURIDAD para las carpetas de juegos.
    #
    # A un tester le desaparecio la carpeta de su disco externo de los ajustes
    # sin haberla quitado el. Como save_settings reescribe el fichero entero,
    # basta con que UNA llamada ocurra con la variable vacia para perderla.
    #
    # Aqui se compara con lo que ya habia guardado: si tenia carpetas y ahora
    # no hay ninguna, se conservan y se apunta QUIEN lo intento. Para
    # quitarlas de verdad esta la opcion "Quitar" del menu, que avisa con
    # WP_BORRAR_CARPETAS=1.
    if [ "${WP_BORRAR_CARPETAS:-0}" != 1 ] && [ -z "${GAMES_PATHS_EXTRA:-}" ] \
       && [ -f "$SETTINGS_FILE" ]; then
        local _antes
        _antes="$(sed -n 's/^GAMES_PATHS_EXTRA="\(.*\)"$/\1/p' "$SETTINGS_FILE" 2>/dev/null)"
        if [ -n "$_antes" ]; then
            GAMES_PATHS_EXTRA="$_antes"
            log "Ajustes: se iban a perder las carpetas extra desde ${FUNCNAME[1]:-?}; se conservan" WARN
        fi
    fi
    cat > "$SETTINGS_FILE" <<EOF
# ============================================
# Ajustes globales de WProton (editable a mano)
# ============================================
# Carpeta donde estan / se guardan los .wsquashfs:
GAMES_PATH="$GAMES_PATH"
# Último juego lanzado (para "Jugar al último" del menu):
LAST_GAME="$LAST_GAME"
# Vista del selector de juegos: list | grid
GAMES_VIEW="$GAMES_VIEW"
# Forma de la caratula que se enseña en el panel de la vista de lista:
#   vertical | wide (panoramica) | 43
LIST_COVER="$LIST_COVER"
# Última carpeta usada en el navegador de ficheros:
LAST_BROWSE="$LAST_BROWSE"
# Aspecto de los menus: clasico | moderno
THEME="$THEME"
# API key de SteamGridDB (https://www.steamgriddb.com/profile/preferences/api):
SGDB_KEY="$SGDB_KEY"
# --------------------------------------------------------------------------
# MODO "SOLO JUGAR" (no aparece en los menus: se activa aquí a mano)
#   1 = al abrir WProton se va DIRECTO a la lista de juegos, y al salir de
#       esa lista se cierra el programa. Para quien solo quiere jugar.
#   Volver al menu completo: pon 0 aquí, o ejecuta  wproton.sh --menu
# --------------------------------------------------------------------------
DIRECT_PLAY=$DIRECT_PLAY
# Columnas de la rejilla de carátulas: 0 = automático según la pantalla
# (4 en portatiles tipo Steam Deck, 5 en Full HD, 6 en pantallas grandes).
# Ponlo a mano si prefieres carátulas más pequenas y ver más juegos a la vez.
GRID_COLS=$GRID_COLS
# Idioma de los menus: es (castellano) | en (english)
LANGUAGE="$LANGUAGE"
# Orden de la lista de juegos: nombre | recientes | jugados
# (los marcados como favoritos van siempre primero)
GAMES_SORT="$GAMES_SORT"
# Formato al empaquetar juegos: wsquashfs (compatible con Batocera) o
# dwarfs (comprime bastante más y monta igual de rapido)
PACK_FORMAT="$PACK_FORMAT"
# --------------------------------------------------------------------------
# FONDO ENTRE MENUS
#   Ventana de fondo con la marca WProton que se mantiene MIENTRAS SE NAVEGA:
#   asi, al pasar de un menu a otro, no se ve el escritorio de por medio, y
#   el compositor siempre tiene una ventana nuestra a la que volver.
#   Se CIERRA antes de lanzar un juego y se reabre al terminar: mantener una
#   conexion grafica abierta durante la partida acababa en "XIO: fatal IO
#   error" cuando gamescope reconfigura XWayland.
#   Ponlo a 0 si prefieres que no aparezca.
# --------------------------------------------------------------------------
GAME_MODE_CANVAS="$GAME_MODE_CANVAS"
# --------------------------------------------------------------------------
# SERVIDOR DE MENUS
#   Con 1, TODOS los menus se dibujan en un mismo proceso, que no se cierra
#   entre uno y otro: se acaba el parpadeo al cambiar de menu y el compositor
#   siempre tiene una ventana nuestra a la que volver.
#   Se cierra mientras juegas y se reabre al terminar.
#   Ponlo a 0 para volver al comportamiento antiguo (un proceso por menu).
# --------------------------------------------------------------------------
MENU_SERVER="$MENU_SERVER"
# --------------------------------------------------------------------------
# CERRAR EL JUEGO CON EL MANDO
#   Con 1, una combinacion del mando cierra el juego. Util en el
#   donde no hay boton de Steam y algunos juegos no traen opcion de salir.
# --------------------------------------------------------------------------
OCULTAR_CURSOR="$OCULTAR_CURSOR"
# --------------------------------------------------------------------------
# DIAGNOSTICO DEL MANDO
#   Con 1, el registro anota que dispositivos se leen, que variables recibe
#   el juego y que botones llegan. Util solo cuando algo falla; en el uso
#   normal alarga el registro sin aportar nada.
# --------------------------------------------------------------------------
DIAG_MANDO="$DIAG_MANDO"
PAD_EXIT="$PAD_EXIT"
PAD_EXIT_COMBO="$PAD_EXIT_COMBO"
PAD_EXIT_SEGUNDOS="$PAD_EXIT_SEGUNDOS"
# --------------------------------------------------------------------------
# CARPETAS DE JUEGOS ADICIONALES
#   Una por linea. Util si tienes los juegos repartidos entre varios discos.
#   Se gestionan desde Biblioteca y preferencias -> Carpetas de juegos.
# --------------------------------------------------------------------------
GAMES_PATHS_EXTRA="$GAMES_PATHS_EXTRA"
# --------------------------------------------------------------------------
# RUNNER PROPIO DE WPROTON
#   Se descarga en la instalacion, junto al ultimo GE-Proton.
#   Deja GE_CUSTOM_URL vacio si no lo quieres.
# --------------------------------------------------------------------------
GE_CUSTOM_NAME="$GE_CUSTOM_NAME"
GE_CUSTOM_URL="$GE_CUSTOM_URL"
# Tamaño de la letra en los menus: 1.0 normal, 1.25 grande, 1.5 muy grande
FONT_SCALE="$FONT_SCALE"
# Destino de rsync para sincronizar backups/ (carpeta, USB o usuario@equipo:/ruta)
BACKUP_SYNC_DEST="$BACKUP_SYNC_DEST"
# Nota: GAMES_PATH admite rutas RELATIVAS (se resuelven respecto a la carpeta
# de wproton.sh, no al directorio actual). Ej.: GAMES_PATH="ROMs/windows"
EOF
    # Modo desarrollo: se anade al final y SOLO si ya estaba activo. Asi no
    # aparece en el fichero de quien no lo haya puesto a mano, pero tampoco
    # se pierde al guardar ajustes (esta funcion reescribe el fichero entero).
    [ "${DEV_MODE:-0}" = 1 ] && printf 'DEV_MODE=1\n' >> "$SETTINGS_FILE"
    return 0
}
abs_path() {
    # Rutas relativas -> relativas a la CARPETA DE WPROTON (no al directorio
    # actual): así funcionan aunque lance el script un frontend desde otro
    # sitio, y se puede mover la carpeta entera (o el pendrive) sin tocar nada.
    case "$1" in
        "")     printf '' ;;
        /*)     printf '%s' "$1" ;;
        # shellcheck disable=SC2088  # es un PATRON, no una expansion: casa
        # con la tilde literal que el usuario escribe en settings.conf
        "~/"*)  printf '%s/%s' "$HOME" "${1#*/}" ;;
        *)      printf '%s/%s' "$BASE_DIR" "$1" ;;
    esac
}

declare -A WP_TR
LANG_DIR="$BASE_DIR/lang"

LANG_EN_VERSION="1"

write_lang_en() {
    # El ingles viaja DENTRO de wproton.sh y se escribe en lang/en.json si
    # falta o es de otra version. Asi, al actualizar el script, las
    # traducciones llegan solas y no hay que copiar ficheros a mano.
    # Los demas idiomas (pt, fr...) son ficheros sueltos y NO se tocan.
    mkdir -p "$LANG_DIR" 2>/dev/null || return 0
    local f="$LANG_DIR/en.json"
    if [ -f "$f" ] && grep -q '"__version__": "'"$LANG_EN_VERSION"'"' "$f" 2>/dev/null; then
        return 0
    fi
    cat > "$f" <<'ENJSON'
@@INCLUIR_LANG@@
ENJSON
    return 0
}

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
    write_lang_en
    local code="${LANGUAGE:-es}"
    [ "$code" = "es" ] && return 0        # castellano = cadenas del script
    local f="$LANG_DIR/$code.json"
    if [ ! -f "$f" ]; then
        log "AVISO: no existe lang/$code.json; se usara el castellano" 2>/dev/null || true
        LANGUAGE=es
        return 0
    fi
    # El JSON se lee con Python (el portable o el del sistema). Si no hay
    # ninguno, seguimos en castellano en vez de fallar.
    local py="${PY_BIN:-}"
    [ -x "$py" ] || py="$(command -v python3 2>/dev/null)"
    if [ -z "$py" ]; then
        log "AVISO: sin Python para leer lang/$code.json" 2>/dev/null || true
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
    if k == "__version__":
        continue
    if isinstance(v, str) and v:
        print("%s\t%s" % (k.replace("\t", " "), v.replace("\t", " ")))
' "$f" 2>>"$LOG_FILE")" || {
        log "AVISO: lang/$code.json no es JSON valido" 2>/dev/null || true
        LANGUAGE=es
        return 0
    }
    local k v n=0
    while IFS=$'\t' read -r k v; do
        [ -n "$k" ] && { WP_TR["$k"]="$v"; n=$((n+1)); }
    done <<EOFLANG
$pairs
EOFLANG
    log "[i] Idioma $code: $n cadenas cargadas de lang/$code.json" 2>/dev/null || true
    return 0
}

wp_tr() {
    # OJO: esta funcion NO puede llamarse "tr": machacaria el comando tr de
    # Unix, que el script usa para game_id, ordenaciones, etc. (fallo real
    # de la 0.92: dejaron de encontrarse perfiles y carátulas).
    # Traduce si hay traduccion; si no, devuelve el original. Para lineas
    # tipo "Etiqueta: valor" traduce solo la etiqueta.
    local txt="$1"
    [ "${LANGUAGE:-es}" != "es" ] || { printf '%s' "$txt"; return 0; }
    if [ -n "${WP_TR[$txt]:-}" ]; then
        printf '%s' "${WP_TR[$txt]}"; return 0
    fi
    # "Runners y herramientas [5 runners]" -> traducir la parte fija
    case "$txt" in
        *" ["*"]")
            local base="${txt%% [*}" resto="${txt#"${txt%% [*}"}"
            if [ -n "${WP_TR[$base]:-}" ]; then
                printf '%s%s' "${WP_TR[$base]}" "$resto"
                return 0
            fi ;;
    esac
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

sgdb_key_leer() {
    # Clave de SteamGridDB.
    #
    # La idea es que nadie tenga que teclearla con el mando: basta con dejar
    # un fichero de texto junto a wproton.sh con la clave dentro, y WProton lo
    # recoge, lo convierte a sgdb.key con permisos solo para su dueño y borra
    # el original. Asi la clave deja de estar en un .txt a la vista.
    #
    # Todo vive junto a wproton.sh: nada en ~/.config, para no perder la
    # portabilidad (llevarse la carpeta a otro equipo y que funcione igual).
    #
    # Orden: sgdb.key -> cualquier .txt que parezca la clave -> settings.conf
    local f k perm
    if [ -r "$BASE_DIR/sgdb.key" ]; then
        k="$(grep -v '^\s*#' "$BASE_DIR/sgdb.key" 2>/dev/null | grep -m1 . | tr -d '[:space:]')"
        if [ -n "$k" ]; then
            perm="$(stat -c %a "$BASE_DIR/sgdb.key" 2>/dev/null || echo 600)"
            [ "$perm" = 600 ] || chmod 600 "$BASE_DIR/sgdb.key" 2>/dev/null
            printf '%s' "$k"
            return 0
        fi
    fi
    # CUALQUIER .txt que haya junto a wproton.sh. No se mira el nombre: la
    # gente lo llamara como quiera. Lo que decide es el CONTENIDO: una sola
    # linea de 16 o mas caracteres alfanumericos, que es como son las claves.
    # Un .txt con notas o instrucciones no pasa ese filtro y no se toca.
    for f in "$BASE_DIR"/*.txt; do
        [ -r "$f" ] || continue
        k="$(grep -v '^\s*#' "$f" 2>/dev/null | grep -m1 . | tr -d '[:space:]')"
        # una clave de SteamGridDB son 32 caracteres alfanumericos; se acepta
        # cualquier cosa razonable pero se descarta texto suelto
        case "$k" in
            *[!A-Za-z0-9_-]*|'') continue ;;
        esac
        [ "${#k}" -lt 16 ] && continue
        if (umask 077; printf '%s\n' "$k" > "$BASE_DIR/sgdb.key") 2>/dev/null; then
            chmod 600 "$BASE_DIR/sgdb.key" 2>/dev/null
            rm -f "$f" 2>/dev/null
            # OJO: esta funcion se lee con $(...), asi que NO puede escribir
            # nada por pantalla: se mezclaria con la clave. Solo al registro.
            log "Clave de SteamGridDB recogida de $(basename "$f"); guardada en sgdb.key y borrado el .txt"
        fi
        printf '%s' "$k"
        return 0
    done
    printf '%s' "${SGDB_KEY:-}"
    return 0
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
    # Convencion DeckStation: libs_pyX.Y según la versión del propio python
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

# Modo Juego de SteamOS (o cualquier sesión gamescope): los menus deben ir a
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
Últimas lineas del log:
$(tail -n 8 "$LOG_FILE")"
    return $rc
}

ui_error() {
    log "ERROR-UI: $1"
    set -- "$(wp_tr "$1")"
    if pygame_available; then
        # shellcheck disable=SC2046
        (IFS=$'\n'; set -f; menu "ERROR" $1 "<< Aceptar") >/dev/null 2>&1 || true
    elif [ "$HAS_ZENITY" = 1 ]; then
        zenity --error --title="WProton" --text="$1" 2>/dev/null
    fi
}
ui_info()  {
    set -- "$(wp_tr "$1")"
    # pygame PRIMERO: lee el mando de forma nativa. zenity necesita el puente
    # uinput y, si falla, el boton A no respondia en los avisos.
    if pygame_available; then
        # shellcheck disable=SC2046
        (IFS=$'\n'; set -f; menu "INFO" $1 "<< Aceptar") >/dev/null 2>&1 || true
    elif [ "$HAS_ZENITY" = 1 ]; then
        pad_bridge_start
        zenity --info --title="WProton" --text="$1" 2>/dev/null
    else
        say "$1"
    fi
}
ui_ask()   { # pregunta si/no -> rc 0 = si  (pygame primero: mando nativo)
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
    # $1 = nombre del binario, resto = URLs candidatas.
    # Descarga la primera que sirva de verdad en esta maquina y DEJA DICHO EN
    # EL REGISTRO por que descarta las demas: si un binario no arranca hay que
    # poder saber si es por arquitectura, por una libreria que falta o porque
    # lo descargado no era un binario.
    local name="$1"; shift
    local tmp url rc err magic
    mkdir -p "$RUNTIME_DIR/tools"
    tmp="$(mktemp -d)"
    for url in "$@"; do
        [ -n "$url" ] || continue
        say "[$name] probando $(basename "$url")..."
        if ! dl "$url" "$tmp/$name" >/dev/null 2>&1; then
            say "[$name] no se pudo descargar (404 o sin red)"
            continue
        fi
        [ -s "$tmp/$name" ] || { say "[$name] la descarga vino vacia"; continue; }
        # ¿es de verdad un binario? (a veces llega una pagina de error)
        magic="$(head -c 4 "$tmp/$name" 2>/dev/null | od -An -tx1 2>/dev/null | tr -d ' \n')"
        if [ "$magic" != "7f454c46" ]; then
            say "[$name] lo descargado no es un binario ELF (es $(head -c 40 "$tmp/$name" | tr -d '\n' | cut -c1-40))"
            continue
        fi
        chmod 755 "$tmp/$name" 2>/dev/null
        err="$("$tmp/$name" --help 2>&1)"
        rc=$?
        # Solo 126 y 127 significan "no se puede ejecutar" (arquitectura
        # equivocada o libreria ausente). Cualquier otro codigo quiere decir
        # que el programa ARRANCO: squashfuse, por ejemplo, responde a --help
        # con su version y sale con 254, y es perfectamente valido.
        case "$rc" in
            126|127)
                say "[$name] no arranca aqui (rc=$rc): $(printf '%s' "$err" | head -n1)" ;;
            *)
                cp -f "$tmp/$name" "$RUNTIME_DIR/tools/$name"
                chmod 755 "$RUNTIME_DIR/tools/$name"
                rm -rf "$tmp"
                say "[$name] listo (portable en runtime/tools): $(printf '%s' "$err" | head -n1)"
                return 0 ;;
        esac
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
            # el binario universal elige herramienta según el nombre del enlace
            local t
            for t in mkdwarfs dwarfs dwarfsck dwarfsextract; do
                ln -sf dwarfs-universal "$RUNTIME_DIR/tools/$t"
            done
            rm -rf "$tmp"
            find_dwarfs_tools
            say "[dwarfs] listo: $("$MKDWARFS_BIN" --help 2>&1 | head -n1)"
            return 0
        fi
        say "[dwarfs] ese binario no funciona aquí"
    done <<EOFDW
$urls
EOFDW
    rm -rf "$tmp"
    ui_error "El binario de DwarFS descargado no funciona en esta máquina."
    return 1
}

try_wproton_repo_tool() {
    # $1 = nombre del binario. Lo busca en el PROPIO repositorio de WProton,
    # que es la via mas fiable porque la controlamos nosotros:
    #   1) carpeta tools/ del repositorio (basta con subir el fichero)
    #      - tools/<arquitectura>/<binario>  (p.ej. tools/x86_64/squashfuse)
    #      - tools/<binario>
    #   2) ficheros adjuntos a las releases
    # Se valida igual que cualquier otra descarga: si no arranca aqui, se
    # descarta y se prueba la siguiente fuente.
    local name="$1" a urls
    [ -n "${WPROTON_REPO:-}" ] || return 1
    a="$(arch_tag)"
    urls="https://raw.githubusercontent.com/$WPROTON_REPO/main/tools/$a/$name
https://raw.githubusercontent.com/$WPROTON_REPO/main/tools/$name"
    urls="$urls
$(curl -fsSL "https://api.github.com/repos/$WPROTON_REPO/releases" 2>/dev/null \
    | grep -o '"browser_download_url": *"[^"]*"' | cut -d'"' -f4 \
    | grep -i "/$name" | head -n 4)"
    # shellcheck disable=SC2086
    try_static_tool "$name" $(printf '%s\n' "$urls" | awk 'NF')
}

try_arch_package() {
    # $1 = nombre del paquete y del binario (p.ej. squashfuse)
    # Los paquetes de Arch son tarballs comprimidos con zstd: dentro esta
    # usr/bin/<binario>. Sirve en Arch, CachyOS y SteamOS (que es Arch); en
    # otras distros puede no arrancar por las librerias, pero eso se
    # comprueba ejecutandolo antes de darlo por bueno.
    local name="$1" tmp url
    command -v tar >/dev/null 2>&1 || return 1
    tmp="$(mktemp -d)"
    url="https://archlinux.org/packages/extra/x86_64/$name/download/"
    say "[$name] probando el paquete de Arch Linux..."
    if ! dl "$url" "$tmp/pkg.tar.zst"; then
        rm -rf "$tmp"; return 1
    fi
    # tar con soporte zstd, o el zstd suelto si el tar no lo trae
    if ! ( cd "$tmp" && tar --zstd -xf pkg.tar.zst usr/bin/"$name" ) >>"$LOG_FILE" 2>&1; then
        if command -v zstd >/dev/null 2>&1; then
            ( cd "$tmp" && zstd -d -q pkg.tar.zst -o pkg.tar \
              && tar -xf pkg.tar usr/bin/"$name" ) >>"$LOG_FILE" 2>&1 || {
                say "[$name] no se pudo abrir el paquete de Arch"; rm -rf "$tmp"; return 1; }
        else
            say "[$name] el paquete de Arch necesita zstd para abrirse"
            rm -rf "$tmp"; return 1
        fi
    fi
    local bin="$tmp/usr/bin/$name"
    [ -f "$bin" ] || { rm -rf "$tmp"; return 1; }
    chmod +x "$bin" 2>/dev/null
    # comprobar que ARRANCA aqui: en distros no-Arch puede faltarle alguna
    # libreria. Solo 126/127 son "no ejecutable"; otros codigos son validos.
    "$bin" --help >/dev/null 2>&1
    local arc=$?
    if [ "$arc" != 126 ] && [ "$arc" != 127 ]; then
        mkdir -p "$RUNTIME_DIR/tools"
        cp -f "$bin" "$RUNTIME_DIR/tools/$name"
        chmod +x "$RUNTIME_DIR/tools/$name"
        rm -rf "$tmp"
        say "[$name] listo (del paquete de Arch, en runtime/tools)"
        return 0
    fi
    say "[$name] el binario de Arch no funciona en este sistema"
    rm -rf "$tmp"
    return 1
}

build_squashfuse_src() {
    # Ultimo recurso si no hay binario estatico para esta maquina: compilar
    # squashfuse desde su codigo oficial (github.com/vasi/squashfuse).
    #
    # Se usa el TARBALL DE LA RELEASE, no el codigo del repositorio: la
    # release ya trae el script ./configure generado, asi que basta con un
    # compilador y make. Con el codigo del repositorio harian falta ademas
    # autoconf, automake y libtool, que mucha gente no tiene.
    local falta="" c
    for c in gcc make sed; do
        command -v "$c" >/dev/null 2>&1 || falta="$falta $c"
    done
    if [ -n "$falta" ]; then
        say "[squashfuse] no se puede compilar: falta$falta"
        return 1
    fi
    local tmp url src
    tmp="$(mktemp -d)"
    # el tarball de distribucion de la ultima release (nombre squashfuse-X.Y.Z.tar.gz)
    url="$(curl -fsSL "https://api.github.com/repos/vasi/squashfuse/releases/latest" 2>/dev/null \
        | grep -o '"browser_download_url": *"[^"]*"' | cut -d'"' -f4 \
        | grep -iE 'squashfuse-[0-9].*\.tar\.(gz|xz)$' | head -n1)"
    if [ -n "$url" ]; then
        say "[squashfuse] compilando desde $(basename "$url") (un par de minutos)..."
        dl "$url" "$tmp/src.tar" || url=""
    fi
    if [ -z "$url" ]; then
        # sin tarball de release: probar con el codigo del repositorio, que
        # necesita autotools
        for c in autoconf automake libtool; do
            command -v "$c" >/dev/null 2>&1 || {
                say "[squashfuse] sin tarball de release y falta $c para generar configure"
                rm -rf "$tmp"; return 1; }
        done
        say "[squashfuse] compilando desde el repositorio (necesita autotools)..."
        dl "https://github.com/vasi/squashfuse/archive/refs/heads/master.tar.gz" \
           "$tmp/src.tar" || { rm -rf "$tmp"; return 1; }
    fi
    ( cd "$tmp" && tar xf src.tar ) >>"$LOG_FILE" 2>&1 || { rm -rf "$tmp"; return 1; }
    src="$(find "$tmp" -maxdepth 1 -type d -name 'squashfuse*' | head -n1)"
    [ -d "$src" ] || { rm -rf "$tmp"; return 1; }
    (
        cd "$src" || exit 1
        [ -x ./configure ] || ./autogen.sh || exit 1
        ./configure && make -j"$(nproc 2>/dev/null || echo 2)"
    ) >>"$LOG_FILE" 2>&1
    if [ -x "$src/squashfuse" ]; then
        mkdir -p "$RUNTIME_DIR/tools"
        cp -f "$src/squashfuse" "$RUNTIME_DIR/tools/squashfuse"
        chmod +x "$RUNTIME_DIR/tools/squashfuse"
        rm -rf "$tmp"
        say "[squashfuse] compilado e instalado en runtime/tools"
        return 0
    fi
    rm -rf "$tmp"
    say "[squashfuse] la compilacion fallo (mira el log)"
    return 1
}

tool_is_ours() {
    # ¿El binario resuelto es una copia NUESTRA (portable) o del sistema?
    case "${1:-}" in
        "$RUNTIME_DIR"/tools/*|"$BASE_DIR"/bin/*) return 0 ;;
        "$BASE_DIR"/*) case "${1#"$BASE_DIR"/}" in */*) return 1 ;; *) return 0 ;; esac ;;
        *) return 1 ;;
    esac
}

setup_fuse_tools() {
    # Consigue versiones PORTABLES de fuse-overlayfs y squashfuse. Solo
    # fusermount3 (paquete fuse3) sigue siendo del sistema: lo necesita el
    # kernel para montar como usuario y no puede ser portable.
    #
    # Se descargan AUNQUE el sistema ya los tenga: WProton debe poder moverse
    # a otro equipo (o a un pendrive) y seguir funcionando, y asi todos los
    # equipos usan la misma version. Si no se consiguen, se usan los del
    # sistema, que para eso estan.
    local a; a="$(arch_tag)"
    local ok=0
    if ! tool_is_ours "$OVERLAYFS_BIN"; then
        # fuse-overlayfs publica binarios ESTATICOS oficiales por arquitectura
        local ovl_urls
        ovl_urls="$(curl -fsSL "https://api.github.com/repos/containers/fuse-overlayfs/releases/latest" 2>/dev/null \
            | grep -o '"browser_download_url": *"[^"]*"' | cut -d'"' -f4 | grep -i "$a")"
        # shellcheck disable=SC2086
        if try_wproton_repo_tool fuse-overlayfs; then
            ok=1
        elif try_static_tool fuse-overlayfs $ovl_urls; then
            ok=1
        elif try_arch_package fuse-overlayfs; then
            ok=1
        fi
    fi
    if ! tool_is_ours "$SQUASHFUSE_BIN"; then
        # squashfuse no publica binarios: probamos fuentes de builds estaticos
        local sq_urls="https://bin.pkgforge.dev/$a/squashfuse"
        sq_urls="$sq_urls
$(curl -fsSL "https://api.github.com/repos/Azathothas/Toolpacks/releases/latest" 2>/dev/null \
    | grep -o '"browser_download_url": *"[^"]*"' | cut -d'"' -f4 | grep -i 'squashfuse' | grep -i "$a")"
        sq_urls="$sq_urls
$(curl -fsSL "https://api.github.com/repos/vasi/squashfuse/releases/latest" 2>/dev/null \
    | grep -o '"browser_download_url": *"[^"]*"' | cut -d'"' -f4 \
    | grep -iv 'sig\|asc' | grep -iv 'squashfuse-[0-9]' | grep -i "$a")"
        # Por orden: nuestro repositorio -> binarios estaticos -> paquete de
        # Arch -> compilar desde el codigo oficial.
        # shellcheck disable=SC2086
        if try_wproton_repo_tool squashfuse; then
            ok=1
        elif try_static_tool squashfuse $(printf '%s\n' "$sq_urls" | awk 'NF'); then
            ok=1
        elif try_arch_package squashfuse; then
            ok=1
        elif [ -z "$SQUASHFUSE_BIN" ]; then
            # Compilar es el ULTIMO recurso y solo si NO hay ninguna squashfuse
            # utilizable. Si el sistema ya trae una, se usa esa: no tiene
            # sentido tardar minutos compilando (y en SteamOS ni siquiera hay
            # compilador) solo por tener una copia propia.
            build_squashfuse_src && ok=1
        else
            say "[squashfuse] sin copia portable; se seguira usando la del sistema"
        fi
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
    # fusermount3 SI es imprescindible y no se puede suplir: lo exige el kernel
    [ -z "$FUSERMOUNT_BIN" ]  && missing="$missing fusermount3(paquete fuse3)"
    [ -n "$missing" ] && die "Faltan dependencias del sistema:$missing

Instalalas con el gestor de paquetes de tu distribucion."

    # squashfuse y fuse-overlayfs: se busca una copia PROPIA aunque el sistema
    # ya las tenga, porque WProton debe poder moverse a otro equipo o a un
    # pendrive. Si no se consiguen, se usan las del sistema y no se aborta:
    # es mejor dejar entrar (para configurar o reintentar desde el menu) que
    # cerrarse sin darle opciones al usuario.
    if ! tool_is_ours "$SQUASHFUSE_BIN" || ! tool_is_ours "$OVERLAYFS_BIN"; then
        local reintentar=1 marca="$RUNTIME_DIR/.fuse_tools_try" edad
        # Si ya se intento hace poco y las del sistema sirven, no insistir en
        # cada arranque; si faltan del todo, se intenta siempre.
        if [ -n "$SQUASHFUSE_BIN" ] && [ -n "$OVERLAYFS_BIN" ] && [ -f "$marca" ]; then
            edad=$(( $(date +%s) - $(stat -c %Y "$marca" 2>/dev/null || echo 0) ))
            if [ "$edad" -lt 604800 ]; then       # una semana
                reintentar=0
                log "Herramientas FUSE: ultimo intento hace $((edad/3600))h; se usan las del sistema"
            fi
        fi
        if [ "$reintentar" = 1 ]; then
            if [ -z "$SQUASHFUSE_BIN" ] || [ -z "$OVERLAYFS_BIN" ]; then
                say "Preparando las herramientas de montaje (squashfuse, fuse-overlayfs)..."
            else
                say "Buscando copias portables de squashfuse y fuse-overlayfs..."
            fi

            mkdir -p "$RUNTIME_DIR" 2>/dev/null
            setup_fuse_tools || true
            : > "$marca" 2>/dev/null
            SQUASHFUSE_BIN="$(resolve_tool squashfuse)"
            OVERLAYFS_BIN="$(resolve_tool fuse-overlayfs)"
            if tool_is_ours "$SQUASHFUSE_BIN" && tool_is_ours "$OVERLAYFS_BIN"; then
                say "[+] Herramientas de montaje propias listas en runtime/tools"
            fi
        fi
    fi
    if [ -z "$SQUASHFUSE_BIN" ] || [ -z "$OVERLAYFS_BIN" ]; then
        local falta=""
        [ -z "$SQUASHFUSE_BIN" ] && falta="$falta squashfuse"
        [ -z "$OVERLAYFS_BIN" ]  && falta="$falta fuse-overlayfs"
        say "AVISO: faltan$falta; los juegos empaquetados no se podran montar"
        WP_SIN_FUSE="$falta"
    fi
    log "Herramientas: squashfuse=$SQUASHFUSE_BIN$(tool_is_ours "$SQUASHFUSE_BIN" && printf ' [portable]' || printf ' [sistema]') | overlayfs=$OVERLAYFS_BIN$(tool_is_ours "$OVERLAYFS_BIN" && printf ' [portable]' || printf ' [sistema]') | fusermount=$FUSERMOUNT_BIN"
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
    PAD_BRIDGE_PID="$(lanzar_suelto "$PY_BIN" "$PAD_BRIDGE_PY")"
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
    grep -q "WPROTON_HELPER steam_add.py PENDIENTE" "$STEAM_ADD_PY" 2>/dev/null && return 0
    cat > "$STEAM_ADD_PY" <<'SAEOF'
@@INCLUIR:steam_add.py@@
SAEOF
}

find_steam_userdata_config() {
    # config/ del usuario de Steam más reciente
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

steam_esta_abierto() {
    pgrep -x steam >/dev/null 2>&1
}

steam_cerrar() {
    # Cierra Steam ORDENADAMENTE y espera a que termine. Es importante: Steam
    # reescribe shortcuts.vdf al salir, asi que si lo modificamos con Steam
    # abierto, nuestro cambio se pierde o el fichero queda corrupto.
    steam_esta_abierto || return 0
    loading_say "Cerrando Steam..."
    if command -v steam >/dev/null 2>&1; then
        steam -shutdown >/dev/null 2>&1 &
    else
        pkill -x steam 2>/dev/null
    fi
    local i
    for i in $(seq 1 30); do            # hasta 15 segundos
        steam_esta_abierto || { say "[+] Steam cerrado"; sleep 1; return 0; }
        sleep 0.5
    done
    say "AVISO: Steam sigue abierto tras 15 segundos"
    return 1
}

steam_abrir() {
    # Vuelve a abrir Steam en segundo plano, sin quedarse con el terminal
    command -v steam >/dev/null 2>&1 || return 1
    loading_say "Abriendo Steam..."
    lanzar_suelto steam >/dev/null 2>&1
    sleep 1
    loading_clear
    return 0
}

steam_appid_de() {
    # Steam identifica cada acceso directo con un numero calculado a partir
    # de su ruta y su nombre. Se necesita para saber como llamar a las
    # imagenes de la biblioteca.
    "$PY_BIN" - "$1" "$2" <<'PYAPPID' 2>/dev/null
import sys, zlib
exe, nombre = sys.argv[1], sys.argv[2]
crc = (zlib.crc32((exe + nombre).encode('utf-8')) | 0x80000000) & 0xFFFFFFFF
print(crc)
PYAPPID
}

arte_conseguir() {
    # Deja en runtime/arte/ las cuatro imagenes de la biblioteca de Steam.
    #
    # Orden de preferencia:
    #   1) las que ya haya (no se vuelven a descargar)
    #   2) una carpeta art/ junto a wproton.sh (para quien las quiera propias)
    #   3) las del repositorio (las buenas, hechas a mano)
    #   4) las que dibuja WProton (sencillas, pero siempre disponibles)
    local estilo="${1:-}" arte="$RUNTIME_DIR/arte" f faltan=0
    mkdir -p "$arte" 2>/dev/null
    # Al pedir un estilo concreto se empieza de cero: si no, se quedarian las
    # de antes y parecia que elegir no servia de nada.
    [ -n "$estilo" ] && rm -f "$arte"/wproton_*.png 2>/dev/null
    if [ "$estilo" = propio ]; then
        pygame_available || { ui_error "Hacen falta los menus graficos"; return 1; }
        write_menu_pygame
        PYGAME_HIDE_SUPPORT_PROMPT=1 SDL_VIDEODRIVER=dummy \
            env -u LD_PRELOAD "$PY_BIN" "$MENU_PYGAME_PY" logo "$arte" \
            >> "$LOG_FILE" 2>&1 || return 1
        return 0
    fi
    for f in wproton_p wproton_header wproton_hero wproton_logo wproton_icono; do
        [ -s "$arte/$f.png" ] && continue
        # copia local junto al script
        if [ -s "$BASE_DIR/art/$f.png" ]; then
            cp -f "$BASE_DIR/art/$f.png" "$arte/$f.png" 2>/dev/null && continue
        fi
        # repositorio
        if curl -fsSL --max-time 40 \
             "https://raw.githubusercontent.com/$WPROTON_REPO/main/art/$f.png" \
             -o "$arte/$f.png.tmp" 2>/dev/null \
           && [ -s "$arte/$f.png.tmp" ] \
           && head -c 8 "$arte/$f.png.tmp" | grep -q 'PNG'; then
            mv -f "$arte/$f.png.tmp" "$arte/$f.png"
            continue
        fi
        rm -f "$arte/$f.png.tmp"
        faltan=1
    done
    # lo que falte, dibujado por WProton
    if [ "$faltan" = 1 ]; then
        log "Alguna imagen no se pudo traer: se dibujan las que falten"
        pygame_available || return 1
        write_menu_pygame
        PYGAME_HIDE_SUPPORT_PROMPT=1 SDL_VIDEODRIVER=dummy \
            env -u LD_PRELOAD "$PY_BIN" "$MENU_PYGAME_PY" logo "$arte" \
            >> "$LOG_FILE" 2>&1 || return 1
    fi
    return 0
}

steam_poner_imagenes() {
    # Copia las imagenes de WProton a la carpeta "grid" de Steam, con los
    # nombres que Steam espera para cada formato. Sin esto, en el modo Juego
    # aparece un cuadro gris con el nombre.
    # $1 = carpeta userdata/<id>/config, $2 = appid, $3 = estilo (opcional)
    local cfg="$1" appid="$2" estilo="${3:-}"
    [ -n "$appid" ] || return 1
    local arte="$RUNTIME_DIR/arte"
    loading_say "Preparando las imagenes de la biblioteca..."
    arte_conseguir "$estilo" || return 1
    local grid="$cfg/grid"
    mkdir -p "$grid" || return 1
    # nombres que usa Steam: <appid>p (vertical), <appid> (apaisada),
    # <appid>_hero (cabecera) y <appid>_logo (logotipo encima)
    cp -f "$arte/wproton_p.png"      "$grid/${appid}p.png"     2>/dev/null
    cp -f "$arte/wproton_header.png" "$grid/${appid}.png"      2>/dev/null
    cp -f "$arte/wproton_hero.png"   "$grid/${appid}_hero.png" 2>/dev/null
    cp -f "$arte/wproton_logo.png"   "$grid/${appid}_logo.png" 2>/dev/null
    say "[+] Imagenes de la biblioteca puestas (appid $appid)"
    return 0
}

anadir_wproton_a_steam() {
    # Añade el propio WProton a Steam como juego no-Steam, con sus imagenes.
    # Asi se puede entrar en la biblioteca desde el modo Juego sin salir al
    # escritorio.
    if [ "${IS_GAMESCOPE:-0}" = 1 ]; then
        ui_error "Esto solo se puede hacer desde el modo Escritorio.

En el modo Juego, la sesion ES Steam y habria que cerrarlo."
        return 1
    fi
    local cfg; cfg="$(find_steam_userdata_config)"
    [ -n "$cfg" ] || { ui_error "No se encontro la carpeta de Steam"; return 1; }
    local self; self="$(readlink -f "$0")"
    local reabrir=0
    if steam_esta_abierto; then
        ui_ask "Steam está abierto y hay que cerrarlo para añadir WProton.

¿Cerrar Steam, añadirlo y volver a abrirlo?" || return 1
        steam_cerrar || { ui_error "No se pudo cerrar Steam"; return 1; }
        reabrir=1
    fi
    write_steam_add
    local vdf="$cfg/shortcuts.vdf"
    [ -f "$vdf" ] && cp -f "$vdf" "$vdf.wproton.bak"
    if ! "$PY_BIN" "$STEAM_ADD_PY" "$vdf" "WProton" "$self" \
         "$(dirname "$self")" "" "$(icono_wproton)" >> "$LOG_FILE" 2>&1; then
        ui_error "Fallo escribiendo shortcuts.vdf (mira el registro)"
        [ "$reabrir" = 1 ] && steam_abrir
        return 1
    fi
    steam_poner_imagenes "$cfg" "$(steam_appid_de "$self" "WProton")" || \
        say "AVISO: no se pudieron generar las imagenes de la biblioteca"
    [ "$reabrir" = 1 ] && steam_abrir
    ui_info "WProton añadido a Steam.

Lo encontraras en la seccion NO STEAM, con su imagen.
Desde el modo Juego podras abrir tu biblioteca sin salir
al escritorio."
    return 0
}

add_game_to_steam() {
    # $1 = ruta del juego (wsquashfs/exe/carpeta), $2 = gid
    local game="$1" gid="$2" reabrir=0
    # En el modo Juego de SteamOS NO se puede tocar: la sesion ES Steam, y
    # cerrarlo tumbaria la sesion entera del usuario.
    if [ "${IS_GAMESCOPE:-0}" = 1 ]; then
        ui_error "No se puede añadir juegos a Steam desde el modo Juego.

La sesión que estás usando ES Steam: para escribir el acceso
directo habría que cerrarlo, y eso cerraría tu sesión.

Cambia al modo Escritorio y vuelve a intentarlo."
        return 1
    fi
    local cfg; cfg="$(find_steam_userdata_config)"
    [ -z "$cfg" ] && { ui_error "No se encontro la carpeta userdata de Steam"; return 1; }

    if steam_esta_abierto; then
        if ui_ask "Steam está abierto.

Para añadir el juego hay que cerrarlo: si no, Steam reescribe
sus accesos directos al salir y se perdería el cambio.

¿Cerrar Steam, añadir el juego y volver a abrirlo?"; then
            steam_cerrar || {
                ui_error "No se pudo cerrar Steam. Ciérralo a mano y reintenta."
                return 1; }
            reabrir=1
        else
            return 1
        fi
    fi

    write_steam_add
    local SELF; SELF="$(readlink -f "$0")"
    local vdf="$cfg/shortcuts.vdf"
    local name; name="$(basename "$game")"; name="${name%.*}"; name="$(printf '%s' "$name" | tr '_' ' ')"
    local icon=""; icon="$(cover_for "$gid")" || icon=""
    [ -f "$vdf" ] && cp -f "$vdf" "$vdf.wproton.bak"
    if "$PY_BIN" "$STEAM_ADD_PY" "$vdf" "$name" "$SELF" "$(dirname "$SELF")" \
        "\"$(readlink -f "$game")\"" "$icon" >> "$LOG_FILE" 2>&1; then
        [ "$reabrir" = 1 ] && steam_abrir
        ui_info "'$name' añadido a Steam como juego no-Steam.

$([ "$reabrir" = 1 ] && printf 'Steam se está abriendo de nuevo.' \
                     || printf 'Abre Steam para verlo.')
Aparecerá en la sección NO STEAM.
Copia previa: shortcuts.vdf.wproton.bak"
    else
        ui_error "Fallo escribiendo shortcuts.vdf (mira el registro).
Se restauro la copia previa."
        [ -f "$vdf.wproton.bak" ] && cp -f "$vdf.wproton.bak" "$vdf"
        [ "$reabrir" = 1 ] && steam_abrir
        return 1
    fi
}

MAPEADOR_PY="$RUNTIME_DIR/mapeador.py"
MAPEADOR_PID=""

write_mapeador() {
    grep -q "WPROTON_HELPER mapeador.py PENDIENTE" "$MAPEADOR_PY" 2>/dev/null && return 0
    cat > "$MAPEADOR_PY" <<'MAPEOF'
@@INCLUIR:mapeador.py@@
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
    # estilo de nombres del .keys (xbox | nintendo), para este juego
    export WP_KEYS_ESTILO="${KEYS_ESTILO:-xbox}"
    # $1 = fichero .keys
    write_mapeador
    # evdev es imprescindible: probar el import y avisar CLARO si falta
    # evdev puede venir de tres sitios: instalado por pip (CachyOS con
    # compilador), de una carpeta evmapy/ con el modulo ya compilado (el caso
    # habitual en SteamOS), o del sistema. Se comprueban todos antes de
    # dar el mapeador por imposible.
    if ! WP_RT="$RUNTIME_DIR" "$PY_BIN" -c 'import sys,os
rt=os.environ["WP_RT"]; base=os.path.dirname(rt)
sys.path.insert(0, os.path.join(rt, "libs_py%d.%d" % sys.version_info[:2]))
[sys.path.insert(0, d) for d in (os.path.join(base,"evmapy"), os.path.join(rt,"evmapy")) if os.path.isdir(d)]
import evdev' >> "$LOG_FILE" 2>&1; then
        # Falta evdev y este juego SI tiene .keys: se intenta instalar aqui
        # mismo. Si la instalacion inicial fallo (un fallo de red, por
        # ejemplo), quien pusiera un .keys se encontraba con que "no
        # funciona" y sin saber por que.
        say "Falta el modulo evdev para el .keys; intentando instalarlo..."
        loading_say "Preparando el mapeador de mando..."
        instalar_evdev >/dev/null 2>&1
        loading_clear
        if ! WP_RT="$RUNTIME_DIR" "$PY_BIN" -c 'import sys,os
rt=os.environ["WP_RT"]; base=os.path.dirname(rt)
sys.path.insert(0, os.path.join(rt, "libs_py%d.%d" % sys.version_info[:2]))
[sys.path.insert(0, d) for d in (os.path.join(base,"evmapy"), os.path.join(rt,"evmapy")) if os.path.isdir(d)]
import evdev' >> "$LOG_FILE" 2>&1; then
            say "AVISO: mapeador .keys NO activado: falta el modulo python evdev"
            say "       Arreglalo en: Runners y herramientas -> Instalar evdev"
            return 1
        fi
        say "[+] evdev instalado; el .keys ya puede funcionar"
    fi
    say "[+] Engranando mapeador para: $(basename "$1")"
    # -u: sin el, Python guarda su salida en un bufer y el registro se queda
    # vacio hasta que el proceso muere. Con el mapeador eso significaba no
    # tener NI UNA linea con la que diagnosticar.
    MAPEADOR_PID="$(PYGAME_HIDE_SUPPORT_PROMPT=1 lanzar_suelto "$PY_BIN" -u "$MAPEADOR_PY" "$1")"
    sleep 0.5
    if [ -n "$MAPEADOR_PID" ] && kill -0 "$MAPEADOR_PID" 2>/dev/null; then
        log "Mapeador activo (pid $MAPEADOR_PID)"
    else
        say "AVISO: el mapeador se cerro nada mas arrancar (mira el registro)"
    fi
    sleep 1
    if ! kill -0 "$MAPEADOR_PID" 2>/dev/null; then
        say "AVISO: el mapeador murio al arrancar; últimas lineas del log:"
        tail -n 4 "$LOG_FILE" >> "$LOG_FILE" 2>&1
        MAPEADOR_PID=""
        return 1
    fi
    return 0
}

mapeador_stop() {
    # Parar el mapeador DE VERDAD, y comprobarlo.
    #
    # El identificador que guardabamos era el del "setsid" que lo lanza, y ese
    # muere en cuanto arranca al python: matarlo no servia de nada. El python
    # quedaba vivo con otro identificador, convirtiendo los botones del mando
    # en teclas mientras navegabas por los menus.
    [ -n "${MAPEADOR_PID:-}" ] && {
        kill "$MAPEADOR_PID" 2>/dev/null
        kill -- "-$MAPEADOR_PID" 2>/dev/null   # y su grupo (lo crea setsid)
    }
    MAPEADOR_PID=""
    # Se busca por el NOMBRE del script, no por su ruta completa: un mapeador
    # huerfano puede venir de OTRA copia de WProton (otra carpeta, una version
    # de pruebas, la del disco externo...) y entonces la ruta no coincide y
    # seguia vivo mandando teclas.
    pkill -f 'mapeador\.py' 2>/dev/null
    local i
    for i in 1 2 3; do
        pgrep -f 'mapeador\.py' >/dev/null 2>&1 || { log "Mapeador detenido"; return 0; }
        sleep 0.3
        pkill -9 -f 'mapeador\.py' 2>/dev/null
    done
    pgrep -f 'mapeador\.py' >/dev/null 2>&1 \
        && log "AVISO: el mapeador sigue vivo; seguira mandando teclas" WARN \
        || log "Mapeador detenido"
    return 0
}

# ----------------------------------------------------------------------------
# 4b. MENU PYGAME (preferido): mando nativo via SDL, cero dependencias del
#     sistema (usa el Python portable + pygame de runtime/libs_pyX.Y)
# ----------------------------------------------------------------------------
MENU_PYGAME_PY="$RUNTIME_DIR/menu_pygame.py"
HAS_PYGAME=-1   # -1 = sin comprobar

FIRSTRUN_MARK="$RUNTIME_DIR/.first_run_done"
WP_SIN_FUSE=""                           # herramientas de montaje que faltan
WP_JUGANDO=0                             # 1 = hay una partida en marcha
WP_PRIMERA_VEZ=0                         # 1 = puesta en marcha inicial
WP_INSTALL_SILENCIOSO=0                  # 1 = instalar sin pedir "Aceptar"
INSTALL_NOTICE_PID=""
PROGRESS_FILE=""
PYGAME_OK_MARK="$RUNTIME_DIR/.pygame_ok"
# Modo desarrollo: se pasa al helper para que F12 guarde la pantalla
if [ "${DEV_MODE:-0}" = 1 ]; then
    export WP_DEV=1
    export WP_CAPT_DIR="$BASE_DIR/capturas"
fi

pygame_available() {
    [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ] || return 1
    # Cache en fichero: menu() corre en subshells y una variable no persiste,
    # así que sin esto el import de prueba (y su BANNER por stdout, que
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
    # Reescribir solo si falta o es de otra versión (I/O gratis en cada menu)
    grep -q "WPROTON_HELPER menu_pygame.py PENDIENTE" "$MENU_PYGAME_PY" 2>/dev/null && return 0
    cat > "$MENU_PYGAME_PY" <<'PGEOF'
@@INCLUIR:menu_pygame.py@@
PGEOF
}

# ----------------------------------------------------------------------------
# 4c. SELECTOR GTK PROPIO (soluciona el foco: zenity deja el foco en los
#     botones y las flechas no mueven la lista; aquí forzamos grab_focus()
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
    grep -q "WPROTON_HELPER menu_gtk.py PENDIENTE" "$MENU_GTK_PY" 2>/dev/null && return 0
    cat > "$MENU_GTK_PY" <<'GTKEOF'
@@INCLUIR:menu_gtk.py@@
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
        local hrc
        # Primero el servidor de menus (una sola ventana para toda la sesion);
        # si no esta disponible, un proceso por menu como siempre.
        menu_server_request list "$title" "$tmpsel" "$tmpopt" "" "${WP_ACTION_X:-}" \
            "${WP_LIST_INFO:-}" "${WP_PRESEL:-}" "${WP_FAV_FILE:-}" \
            "${WP_GRID_BANNER:-vertical}"
        hrc=$?
        if [ "$hrc" = 9 ]; then
            PYGAME_HIDE_SUPPORT_PROMPT=1 SDL_JOYSTICK_ALLOW_BACKGROUND_EVENTS=1 \
                env -u LD_PRELOAD "$PY_BIN" "$MENU_PYGAME_PY" list "$title" "$tmpsel" "$tmpopt" >> "$LOG_FILE" 2>&1
            hrc=$?
        else
            : > "$tmpsel.done"      # el servidor no murio: cierre ordenado
        fi
        # rc=3 -> el menu dejo de dibujar (el compositor no responde).
        # Reintento cambiando de driver: si iba por X11, se prueba Wayland.
        if [ "$hrc" = 3 ]; then
            say "AVISO: el menu dejo de dibujarse; reintentando con otro driver"
            if [ -n "${WP_FORCE_WAYLAND:-}" ]; then
                unset WP_FORCE_WAYLAND
            else
                export WP_FORCE_WAYLAND=1
            fi
            PYGAME_HIDE_SUPPORT_PROMPT=1 SDL_JOYSTICK_ALLOW_BACKGROUND_EVENTS=1 \
                env -u LD_PRELOAD "$PY_BIN" "$MENU_PYGAME_PY" list "$title" "$tmpsel" "$tmpopt" >> "$LOG_FILE" 2>&1
            hrc=$?
        fi
        # rc>=2 = el helper no pudo abrirse (video ocupado justo después de
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
        # Si falta la marca de cierre ordenado, el proceso murio de golpe:
        # tipicamente gamescope recrea su XWayland al salir de un juego y Xlib
        # aborta con "XIO: fatal IO error"... saliendo con codigo 1, el MISMO
        # que usamos para "el usuario cancelo". Sin esta comprobacion WProton
        # se cerraba y, en modo Juego, parecia que la consola se reiniciaba.
        if [ ! -f "$tmpsel.done" ]; then
            say "AVISO: el menu se cerro de forma anormal (servidor grafico caido)"
            hrc=2
            MENU_HELPER_FAILED=1
        fi
        rm -f "$tmpsel.done"
    elif gtk_available; then
        pad_bridge_start
        write_menu_gtk
        local tmpopt; tmpopt="$(mktemp)"
        printf '%s\n' "$@" > "$tmpopt"
        "$SYS_PY" "$MENU_GTK_PY" list "$title" "$tmpsel" "$tmpopt" >> "$LOG_FILE" 2>&1
        rm -f "$tmpopt"
    elif [ "$HAS_ZENITY" = 1 ]; then
        printf '%s\n' "$@" | zenity --list --title="WProton" --text="$title" \
            --column="Opción" --hide-header \
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
    # Con pygame se usa un TECLADO EN PANTALLA: así se pueden escribir
    # argumentos, DLL overrides o notas con el mando, sin teclado fisico.
    local title="$1" default="${2:-}"
    if pygame_available; then
        pad_bridge_stop
        write_menu_pygame
        local tmpsel; tmpsel="$(mktemp)"
        printf '%s' "$default" > "$tmpsel"
        local rc
        menu_server_request text "$title" "$tmpsel" "$default" "" ""
        rc=$?
        if [ "$rc" = 9 ]; then
            PYGAME_HIDE_SUPPORT_PROMPT=1 SDL_JOYSTICK_ALLOW_BACKGROUND_EVENTS=1 \
                env -u LD_PRELOAD "$PY_BIN" "$MENU_PYGAME_PY" text "$title" \
                "$tmpsel" "$default" >> "$LOG_FILE" 2>&1
            rc=$?
        fi
        local val; val="$(cat "$tmpsel")"; rm -f "$tmpsel"
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
    # NUESTRO navegador primero: se maneja con el mando y no depende del
    # escritorio. zenity acababa abriendo el dialogo del sistema (Dolphin en
    # KDE), que no se puede usar con el mando.
    if pygame_available; then
        browse_for_path "$1" "${2:-$HOME}" "dir"
        return $?
    fi
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
    # GE-Proton: las 8 más recientes + la ULTIMA versión de CADA serie
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
    # $1 = url, $2 = destino.
    #
    # La barra es la NUESTRA (pygame). Con curl se puede saber el porcentaje
    # real, asi que la barra avanza de verdad en vez de ir "pulsando".
    local nombre; nombre="$(basename "$2")"
    say "Descargando $nombre..."
    # Si ya hay una ventana en pantalla, NO abrir otra encima: se solapaban.
    if [ -n "${INSTALL_NOTICE_PID:-}" ] || [ -n "${PROGRESS_FILE:-}" ]; then
        curl -fL --retry 3 -s -o "$2" "$1"
    elif pygame_available; then
        progress_start "Descargando $nombre"
        # Tamaño total, para que la barra avance de verdad. Si el servidor no
        # lo dice, se avanza despacio: al menos se ve que sigue trabajando.
        local total; total="$(curl -fsIL --max-time 15 "$1" 2>/dev/null \
            | grep -i '^content-length:' | tail -n1 \
            | tr -dc '0-9')"
        curl -fL --retry 3 -s -o "$2" "$1" &
        local pid=$! pct=0 hechos=0
        while kill -0 $pid 2>/dev/null; do
            sleep 1
            hechos="$(stat -c %s "$2" 2>/dev/null || echo 0)"
            if [ -n "$total" ] && [ "$total" -gt 0 ] 2>/dev/null; then
                pct=$(( hechos * 100 / total ))
                [ "$pct" -gt 99 ] && pct=99
                progress_set "$pct" "Descargando $nombre  ($(human_size "$hechos") de $(human_size "$total"))"
            else
                [ "$pct" -lt 90 ] && pct=$((pct + 2))
                progress_set "$pct" "Descargando $nombre  ($(human_size "$hechos"))"
            fi
        done
        wait $pid
        local rc=$?
        progress_set 100 "Listo"
        progress_stop
        return $rc
    elif [ "$HAS_ZENITY" = 1 ]; then
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
    # $1 = texto de estado; resto = comando.
    #
    # La ventana de progreso es la NUESTRA (pygame): se ve igual en escritorio
    # y en modo Juego, con el tema elegido y manejable con el mando. Zenity
    # queda solo como respaldo para quien no tenga pygame; mezclar los dos
    # estilos en la misma instalacion quedaba descuidado.
    local text="$1"; shift
    say "$text"
    menu_server_say "$text"      # tambien en la pantalla de menus
    canvas_say "$text"
    if [ -n "${INSTALL_NOTICE_PID:-}" ] || [ -n "${PROGRESS_FILE:-}" ]; then
        # ya hay una ventana en pantalla: no apilar otra encima
        "$@" >> "$LOG_FILE" 2>&1
        local _rc0=$?
        loading_clear
        return $_rc0
    elif pygame_available; then
        progress_start "WProton"
        progress_set 10 "$text"
        "$@" >> "$LOG_FILE" 2>&1 &
        local pid=$!
        # avance "vivo" mientras dura: no sabemos cuanto falta, pero al menos
        # se ve que la cosa sigue en marcha
        local pct=10
        while kill -0 $pid 2>/dev/null; do
            sleep 1
            [ "$pct" -lt 90 ] && pct=$((pct + 2))
            progress_set "$pct" "$text"
        done
        wait $pid
        local _rc1=$?
        progress_set 100 "Listo"
        progress_stop
        loading_clear
        return $_rc1
    elif [ "$HAS_ZENITY" = 1 ]; then
        "$@" >> "$LOG_FILE" 2>&1 &
        local pid=$!
        ( while kill -0 $pid 2>/dev/null; do echo 50; sleep 1; done; echo 100 ) \
            | zenity --progress --title="WProton" --text="$text" \
                     --pulsate --auto-close --no-cancel 2>/dev/null
        wait $pid
        local _rc=$?
        loading_clear
        return $_rc
    else
        "$@" >> "$LOG_FILE" 2>&1
        local _rc2=$?
        loading_clear
        return $_rc2
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
    local libs; libs="$RUNTIME_DIR/$(py_libs_dir)"
    if ! "$PY_BIN" -m pip install --target "$libs" \
            --disable-pip-version-check --no-warn-script-location --upgrade pygame \
            >> "$LOG_FILE" 2>&1; then
        # Segundo intento con la rueda precompilada (sin compilar nada) y sin
        # cache, que es lo que falla en sistemas con poco espacio en /tmp
        say "pygame no se instalo al primer intento; reintentando..."
        "$PY_BIN" -m pip install --target "$libs" --disable-pip-version-check \
            --no-warn-script-location --no-cache-dir --only-binary=:all: pygame \
            >> "$LOG_FILE" 2>&1 || true
    fi
    if ! "$PY_BIN" -c "import sys; sys.path.insert(0, '$libs'); import pygame" \
            >> "$LOG_FILE" 2>&1; then
        ui_error "No se pudo instalar pygame: los menus usaran GTK/zenity.

Ultimas lineas del registro:
$(grep -iE 'error|no matching|failed' "$LOG_FILE" | tail -n 3)

Puedes reintentarlo en
Runners y herramientas -> Instalar/actualizar Python portable + pygame"
        return 1
    fi
    instalar_evdev
    HAS_PYGAME=-1   # re-evaluar
    rm -f "$PYGAME_OK_MARK"
    if [ "${WP_INSTALL_SILENCIOSO:-0}" = 1 ]; then
        say "Python portable listo: $("$PY_BIN" -V 2>&1) + pygame"
    else
        ui_info "Python portable listo: $("$PY_BIN" -V 2>&1) + pygame"
    fi
}

evdev_disponible() {
    # ¿Puede el mapeador importar evdev? Se prueban las tres vias: lo
    # instalado por pip, una carpeta evmapy/ y el modulo del sistema.
    WP_RT="$RUNTIME_DIR" "$PY_BIN" -c 'import sys,os
rt=os.environ["WP_RT"]; base=os.path.dirname(rt)
sys.path.insert(0, os.path.join(rt, "libs_py%d.%d" % sys.version_info[:2]))
[sys.path.insert(0, d) for d in (os.path.join(base,"evmapy"), os.path.join(rt,"evmapy")) if os.path.isdir(d)]
import evdev' >/dev/null 2>&1
}

instalar_evdev() {
    # evdev hace falta para los ficheros .keys (traducir mando a teclado).
    #
    # En SteamOS no se puede compilar: no trae las cabeceras del kernel. Antes
    # se dejaba a medias y habia que buscarse la vida copiando una carpeta
    # evmapy/ a mano. Ahora se prueban varias vias hasta que una funcione.
    local libs; libs="$RUNTIME_DIR/$(py_libs_dir)"
    if evdev_disponible; then
        say "[+] evdev ya disponible (mapeador .keys listo)"
        return 0
    fi
    say "Instalando evdev para el mapeador .keys (opcional)..."
    # ¿Se puede compilar aqui? Hacen falta un compilador Y las cabeceras del
    # kernel. En SteamOS no hay ninguna de las dos, asi que intentar compilar
    # primero solo hace perder medio minuto para acabar fallando.
    local puede_compilar=0
    if { command -v gcc >/dev/null 2>&1 || command -v cc >/dev/null 2>&1; } \
       && [ -e /usr/include/linux/input.h ]; then
        puede_compilar=1
    fi
    local orden="evdev-binary evdev"
    [ "$puede_compilar" = 1 ] && orden="evdev evdev-binary"
    local paquete
    for paquete in $orden; do
        case "$paquete" in
            evdev)        say "Probando a compilar evdev..." ;;
            evdev-binary) say "Probando la version ya compilada..." ;;
        esac
        if "$PY_BIN" -m pip install --target "$libs" \
             --disable-pip-version-check --no-warn-script-location \
             "$paquete" >> "$LOG_FILE" 2>&1 && evdev_disponible; then
            say "[+] evdev instalado ($paquete)"
            return 0
        fi
    done
    # 3) una carpeta evmapy/ publicada en el repositorio de WProton
    if [ -n "${WPROTON_REPO:-}" ]; then
        say "Probando con la copia del repositorio..."
        local tmp; tmp="$(mktemp -d)"
        if curl -fsSL --max-time 60 \
             "https://raw.githubusercontent.com/$WPROTON_REPO/main/evmapy/evmapy.tar.gz" \
             -o "$tmp/evmapy.tar.gz" 2>/dev/null \
           && tar tzf "$tmp/evmapy.tar.gz" >/dev/null 2>&1 \
           && tar xzf "$tmp/evmapy.tar.gz" -C "$RUNTIME_DIR" 2>/dev/null \
           && evdev_disponible; then
            rm -rf "$tmp"
            say "[+] evdev listo (copia del repositorio)"
            return 0
        fi
        rm -rf "$tmp"
    fi
    say "AVISO: no se pudo instalar evdev; los ficheros .keys no funcionaran"
    say "    Puedes copiar una carpeta evmapy/ con evdev ya compilado a la"
    say "    raiz de WProton, o reintentarlo en Runners y herramientas."
    return 1
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

mediafire_directo() {
    # MediaFire no da un enlace directo: la pagina lleva dentro el enlace real
    # al fichero. Se extrae de ahi. Si algun dia cambian su web esto dejara de
    # funcionar, por eso el runner propio deberia acabar alojado en el
    # repositorio de WProton (ver GE_CUSTOM_URL en settings.conf).
    local pagina="$1" html directo
    case "$pagina" in
        *mediafire.com*) ;;
        *) printf '%s' "$pagina"; return 0 ;;   # ya es un enlace directo
    esac
    html="$(curl -fsSL --max-time 30 "$pagina" 2>/dev/null)" || return 1
    directo="$(printf '%s' "$html" \
        | grep -oE 'https://download[0-9]*\.mediafire\.com/[^"'"'"'<> ]+' \
        | head -n1)"
    [ -n "$directo" ] || return 1
    printf '%s' "$directo"
    return 0
}

setup_proton_custom() {
    # Runner propio de WProton. Se descarga en la instalacion junto al ultimo
    # GE-Proton, y tambien se puede pedir desde "Descargar runners".
    local url="${GE_CUSTOM_URL:-}"
    [ -n "$url" ] || { say "Sin URL para el runner propio (GE_CUSTOM_URL)"; return 1; }
    local nombre="${GE_CUSTOM_NAME:-GE-Custom}"
    if [ -d "$RUNNERS_DIR/$nombre" ]; then
        [ "${WP_INSTALL_SILENCIOSO:-0}" = 1 ] && say "Runner propio ya instalado: $nombre" \
                                              || ui_info "Runner propio ya instalado: $nombre"
        return 0
    fi
    # Si hay una ventana de progreso (la de Python), se informa por ahi; si
    # no, por el canal habitual. Nada de abrir un zenity aparte.
    if [ -n "${PROGRESS_FILE:-}" ]; then
        progress_set 90 "Descargando el runner propio de WProton..."
    else
        loading_say "Descargando el runner propio de WProton..."
    fi
    local directo; directo="$(mediafire_directo "$url")" || {
        say "AVISO: no se pudo resolver el enlace del runner propio"
        return 1; }
    local tmp="$RUNNERS_DIR/.dl_custom"; rm -rf "$tmp"; mkdir -p "$tmp"
    if ! dl "$directo" "$tmp/ge-custom.tar.gz"; then
        rm -rf "$tmp"; say "AVISO: fallo la descarga del runner propio"; return 1
    fi
    # comprobar que es de verdad un tar.gz y no una pagina de error
    if ! tar tzf "$tmp/ge-custom.tar.gz" >/dev/null 2>&1; then
        rm -rf "$tmp"
        say "AVISO: lo descargado no es un tar.gz (el enlace habra cambiado)"
        return 1
    fi
    if ! extract_archive "$tmp/ge-custom.tar.gz" "$RUNNERS_DIR"; then
        rm -rf "$tmp"; say "AVISO: fallo extrayendo el runner propio"; return 1
    fi
    rm -rf "$tmp"
    # si el tar traia otro nombre de carpeta, se respeta: solo se avisa
    if [ ! -d "$RUNNERS_DIR/$nombre" ]; then
        local real; real="$(find "$RUNNERS_DIR" -maxdepth 1 -type d -newer "$RUNNERS_DIR" \
                            ! -name '.*' 2>/dev/null | head -n1)"
        [ -n "$real" ] && nombre="$(basename "$real")"
    fi
    [ "${WP_INSTALL_SILENCIOSO:-0}" = 1 ] && say "Runner propio instalado: $nombre" \
                                          || ui_info "Runner propio instalado: $nombre"
    return 0
}

setup_proton() {
    # Descarga rapida: último GE-Proton x86_64 (excluye aarch64)
    say "Buscando último GE-Proton x86_64..."
    local url
    url="$(gh_latest_asset "GloriousEggroll/proton-ge-custom" 'GE-Proton.*\.tar\.gz$')"
    [ -z "$url" ] && die "No se pudo obtener la URL de GE-Proton"
    local name; name="$(basename "$url" .tar.gz)"
    if [ -d "$RUNNERS_DIR/$name" ]; then
        if [ "${WP_INSTALL_SILENCIOSO:-0}" = 1 ]; then
            say "GE-Proton ya al dia: $name"
        else
            ui_info "GE-Proton ya al dia: $name"
        fi
        return 0
    fi
    local tmp="$RUNNERS_DIR/.dl_tmp"; rm -rf "$tmp"; mkdir -p "$tmp"
    dl "$url" "$tmp/$(basename "$url")" || die "Fallo descargando GE-Proton"
    extract_archive "$tmp/$(basename "$url")" "$RUNNERS_DIR" || die "Fallo extrayendo GE-Proton"
    rm -rf "$tmp"
    if [ "${WP_INSTALL_SILENCIOSO:-0}" = 1 ]; then
        say "GE-Proton instalado: $name"
    else
        ui_info "GE-Proton instalado: $name"
    fi
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
            || { say "AVISO: el runner del sistema '$RUNNER' no existe aquí"; RUNNER=""; }
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
        ui_error "No se pudo descargar '$RUNNER' automáticamente.
Se abrira el menu de descarga de runners."
        download_runner_menu
    fi
    if [ ! -d "$RUNNERS_DIR/$RUNNER" ]; then
        say "AVISO: '$RUNNER' sigue sin estar; se usara el runner automático"
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
        "Wine Soda [wine] - Bottles, basado en el Wine de Valve" \
        "Wine Caffe [wine] - Bottles, Wine TKG estable" \
        "WProton Custom [proton] - el runner propio de WProton" \
        "<< Volver")" || return
    case "$src" in
        "WProton Custom"*)
            setup_proton_custom || ui_error "No se pudo descargar el runner propio.

Mira el registro: lo mas probable es que el enlace de descarga
haya cambiado. Puedes poner otro en GE_CUSTOM_URL, dentro de
settings.conf."
            return ;;
    esac
    local dwproton=0 tagfilter=""
    case "$src" in
        "GE-Proton"*)      repo="GloriousEggroll/proton-ge-custom" ;;
        "Proton-CachyOS"*) repo="CachyOS/proton-cachyos" ;;
        "DWProton"*)       repo="dawn-winery/dwproton-mirror"; dwproton=1 ;;
        "Wine-LG"*)        repo="Castro-Fidel/wine_builds"; tagfilter="^WINE_LG_" ;;
        "Proton-LG"*)      repo="Castro-Fidel/wine_builds"; tagfilter="^PROTON_" ;;
        "Wine-GE"*)        repo="GloriousEggroll/wine-ge-custom" ;;
        "Wine Kron4ek"*)   repo="Kron4ek/Wine-Builds" ;;
        # Los runners de Bottles: el mismo repositorio publica varias
        # familias, asi que se filtra por la etiqueta.
        "Wine Soda"*)      repo="bottlesdevs/wine"; tagfilter="^soda-" ;;
        "Wine Caffe"*)     repo="bottlesdevs/wine"; tagfilter="^caffe-" ;;
        *) return ;;
    esac

    say "Consultando versiones de $repo..."
    local tags
    if [ "$repo" = "GloriousEggroll/proton-ge-custom" ]; then
        tags="$(ge_tags_curated)"
    elif [ -n "$tagfilter" ]; then
        # el repo mezcla familias (WINE_LG / PROTON_LG / PROTON_STEAM):
        # pedir más releases y quedarnos con la familia elegida
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
#      wsquashfs/tmp_mount/<n>      <- overlay fusionado (aquí vive el juego)
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

montar_suelto() {
    # Lanza un montaje FUSE en su PROPIA sesion.
    #
    # Los montajes son demonios que quedan vivos mientras el juego juega. Si
    # nacen dentro de nuestro grupo de procesos y algo mata ese grupo -- por
    # ejemplo Steam, cuando WProton se lanza como acceso directo desde el modo
    # Juego -- se llevan por delante el montaje, y el juego se queda sin sus
    # ficheros ("Transport endpoint is not connected"). Con setsid sobreviven.
    if command -v setsid >/dev/null 2>&1; then
        setsid "$@" >>"$LOG_FILE" 2>&1
    else
        "$@" >>"$LOG_FILE" 2>&1
    fi
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
        montar_suelto "$DWARFS_BIN" "$img" "$mp" -o ro || return 1
    else
        montar_suelto "$SQUASHFUSE_BIN" "$img" "$mp" || return 1
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

    loading_say "Montando el juego..."
    mount_image_ro "$squash" "$MOUNT_RO" || die "no se pudo montar $squash"
    # squash_to_uid/gid: los wsquashfs hechos en Batocera llevan los ficheros
    # como root; sin esto, cuando fuse-overlayfs copia uno a la capa superior
    # intenta conservar el propietario y falla con "Operation not permitted"
    # (era lo que impedia a Wine escribir el registro del prefix incluido).
    local ovl_opts="lowerdir=$MOUNT_RO,upperdir=$upper,workdir=$work"
    local ovl_squash; ovl_squash="$ovl_opts,squash_to_uid=$(id -u),squash_to_gid=$(id -g)"
    if montar_suelto "$OVERLAYFS_BIN" -o "$ovl_squash" "$MOUNT_RW"; then
        MOUNT_OK=1
        MOUNT_POINT="$MOUNT_RW"
    elif montar_suelto "$OVERLAYFS_BIN" -o "$ovl_opts" "$MOUNT_RW"; then
        say "AVISO: fuse-overlayfs sin squash_to_uid (versión antigua): si el"
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
    loading_say "Montando el juego..."
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
        log "tmp_mount aún contiene: $(ls -A "$MOUNT_BASE" 2>/dev/null | tr '\n' ' ')" WARN
    fi
    MOUNT_OK=0
}

cleanup_all() {
    # Se ejecuta SIEMPRE al salir (tambien al cancelar con B, que sale por la
    # trampa y no por el menu "Salir"). Si no se para el servidor de menus,
    # su proceso sigue vivo con la ventana en pantalla y parece que WProton
    # se ha quedado colgado.
    #
    # Red de seguridad: si por lo que sea llegamos aqui con una partida en
    # marcha, se espera a que termine antes de desmontar. Desmontar debajo de
    # un juego que esta jugando es la peor forma de cerrarlo.
    # Espera acotada. Antes eran hasta DIEZ MINUTOS en silencio: desde fuera
    # parecia que WProton se habia colgado y no quedaba mas remedio que
    # matarlo. Veinte segundos son de sobra para que un juego suelte sus
    # procesos; si tarda mas, se sigue igualmente y se deja dicho en el
    # registro.
    if [ "${WP_JUGANDO:-0}" = 1 ]; then
        log "Cierre con el juego aun en marcha: se espera un poco" WARN
        local _i
        for _i in $(seq 1 20); do
            juego_sigue_vivo || break
            sleep 1
        done
        [ "$_i" -ge 20 ] && log "El juego no solto sus procesos; se cierra igualmente" WARN
    fi
    # Cada paso deja rastro: si el cierre se atasca, el registro dice donde.
    log "Cierre: desmontando"
    cleanup_mount
    log "Cierre: parando el puente del mando"
    pad_bridge_stop
    log "Cierre: parando el mapeador"
    mapeador_stop
    log "Cierre: parando el vigilante"
    guardia_salida_stop
    log "Cierre: parando el fondo"
    canvas_stop
    log "Cierre: parando el servidor de menus"
    menu_server_stop
    log "Cierre: completado"
}
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
    # Lista filtrada para menus de seleccion manual. Ademas de .exe se
    # incluyen .bat y .cmd: algunos juegos (sobre todo ports y titulos
    # antiguos) arrancan con un script por lotes que prepara variables o
    # elige la version correcta antes de llamar al ejecutable.
    find "$1" -type f \( -iname '*.exe' -o -iname '*.bat' -o -iname '*.cmd' \) \
        ! -ipath '*/windows/*' ! -ipath '*/Windows/*' ! -ipath '*/system32/*' \
        ! -ipath '*/syswow64/*' ! -iname 'autorun.cmd' 2>/dev/null | _fexe
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
    EXE=$(find "$ROOT" -type f -iname '*.exe' \
        ! -ipath '*/windows/*' ! -ipath '*/Windows/*' ! -ipath '*/system32/*' \
        2>/dev/null | _fexe | head -n1)
    [ -n "$EXE" ] && { printf '%s' "$EXE"; return; }

    # 6) sin ningun .exe utilizable: puede ser un juego que arranca por .bat
    find "$ROOT" -maxdepth 2 -type f \( -iname '*.bat' -o -iname '*.cmd' \) \
        ! -iname 'autorun.cmd' ! -ipath '*/windows/*' \
        2>/dev/null | _fexe | head -n1
}

parse_autorun() {
    # Formato autorun.cmd de Batocera con CRLF y UTF-16. Además de DIR/CMD
    # soporta ENV= (variables, p.ej. WINEDLLOVERRIDES) y LANG= (locale del
    # juego). SAVEDIR/SAVEFILES se ignoran: nuestro overlay ya persiste todo.
    local FILE="$1" CONTENT
    R_DIR=""; R_CMD=""; R_CMD_BASE=""; R_ARGS=""; R_ENV=""; R_LANG=""
    [ -f "$FILE" ] || return
    if command -v file >/dev/null 2>&1 && file "$FILE" | grep -qi 'UTF-16'; then
        CONTENT=$(iconv -f UTF-16 -t UTF-8 "$FILE" 2>/dev/null | tr -d '\000')
    else
        # tr -d '\000': algunos autorun vienen en UTF-16 sin que 'file' lo
        # detecte; sus bytes nulos hacen que bash llene la consola de avisos
        CONTENT=$(tr -d '\000' < "$FILE")
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
                if [ -n "$hit" ]; then
                    EXE_PATH="$hit"
                    # argumentos del propio autorun (CMD="juego.exe -novr"),
                    # salvo que el perfil traiga los suyos
                    EXE_ARGS="${ARGS_OVERRIDE:-$R_ARGS}"
                    # ENV= y LANG= del autorun estilo Batocera
                    AUTORUN_ENV="$R_ENV"
                    AUTORUN_LANG="$R_LANG"
                    say "[+] Ejecutable por autorun.cmd: $hit"
                    [ -n "$R_ARGS" ] && say "[+] Argumentos del autorun: $R_ARGS"
                    return 0
                fi
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
    # Mandos de Sony (DualSense / DS4) con GE-Proton 11-4 o mas nuevo:
    #   auto - lo que decida Proton (lo normal)
    #   1    - forzar que el mando se presente como uno de Xbox
    #   0    - no tocar nada
    #
    # Antes habia cuatro modos. Ninguno arreglo un solo caso real: el problema
    # de los mandos estaba en los permisos y en un proceso nuestro que se
    # mataba solo. Se deja en tres estados, como el resto de opciones.
    PAD_SONY=auto
    # Nombres de los botones dentro del .keys: xbox | nintendo (Batocera)
    KEYS_ESTILO=xbox
    NTSYNC=0                 # sincronizacion NT por kernel (necesita /dev/ntsync)
    FAVORITO=0               # 1 = aparece primero en la lista
    NOTAS=""                 # apunte libre ("necesita -novr", "usar GE 9-27"...)
    PLAY_COUNT=0             # veces jugado
    PLAY_SECONDS=0           # tiempo total jugado (segundos)
    LAST_PLAYED=""           # fecha de la última partida (YYYY-MM-DD HH:MM)
    SAVE_PATHS=""            # carpetas de partidas detectadas al jugar (: separadas)
    # Steam Input: DESACTIVADO por defecto. Muy pocos juegos se benefician de
    # el y en cambio puede interferir con los que leen el mando directamente.
    # Quien lo necesite lo activa en el ajuste del juego.
    PAD_STEAMFIX=0
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
PAD_SONY=${PAD_SONY:-auto}
KEYS_ESTILO=${KEYS_ESTILO:-xbox}
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
            "(automático: último GE-Proton instalado)" "$brow" $runners)" || return 1
    if [ "$sel" = "(incluido en el wsquashfs) [wine]" ]; then
        RUNNER="bundled"
        return 0
    fi
    if [ "$sel" = "(automático: último GE-Proton instalado)" ]; then
        RUNNER=""
    else
        RUNNER="${sel% \[*\]}"
    fi
    return 0
}

exes_ordenados() {
    # Todos los ejecutables de la carpeta y subcarpetas, ORDENADOS por lo
    # probable que es que sean el juego:
    #   1) el que sugiere la heuristica (marcado con >)
    #   2) los de la raiz de la carpeta
    #   3) los de subcarpetas
    #   4) los sospechosos (instaladores, desinstaladores, redistribuibles)
    # Se muestra la ruta relativa y el tamaño: distinguir el juego del
    # instalador de DirectX es inmediato viendo que uno pesa 40 MB y otro 300 KB.
    local root="$1" sugerido="${2:-}" f rel mb
    local raiz="" subs="" malos=""
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        rel="${f#"$root"/}"
        mb="$(du -m "$f" 2>/dev/null | cut -f1)"
        case "$(printf '%s' "$rel" | tr 'A-Z' 'a-z')" in
            *unins*|*setup*|*directx*|*dotnet*|*redist*|\
            *crashhandler*|*crashreport*|*bugreport*|*config.exe|*launcher.exe)
                malos="$malos$rel  [${mb:-0} MB]
" ;;
            */*) subs="$subs$rel  [${mb:-0} MB]
" ;;
            *)   raiz="$raiz$rel  [${mb:-0} MB]
" ;;
        esac
    done <<EOFEX
$(find "$root" -type f \( -iname '*.exe' -o -iname '*.bat' -o -iname '*.cmd' \) \
     ! -ipath '*/windows/*' ! -ipath '*/system32/*' ! -ipath '*/syswow64/*' \
     ! -iname 'autorun.cmd' 2>/dev/null | sort)
EOFEX
    [ -n "$sugerido" ] && printf '> %s  (sugerido)\n' "${sugerido#"$root"/}"
    printf '%s' "$raiz"
    printf '%s' "$subs"
    printf '%s' "$malos"
}

wizard_pick_exe() {
    local root="$1" list rels sel sugerido
    sugerido="$(find_game_exe "$root" 2>/dev/null)" || sugerido=""
    rels="$(exes_ordenados "$root" "$sugerido" | awk 'NF')"
    # shellcheck disable=SC2046
    sel="$(IFS=$'\n'; set -f; menu "Paso 2/3 - Ejecutable del juego" \
            "(automático: autorun.cmd / escaneo)" $rels)" || return 1
    if [ "$sel" = "(automático: autorun.cmd / escaneo)" ]; then
        EXE_OVERRIDE=""
    else
        # quitar los adornos: "> ruta/juego.exe  (sugerido)" o "ruta  [40 MB]"
        sel="${sel#> }"
        sel="${sel%  (sugerido)}"
        sel="$(printf '%s' "$sel" | sed 's/  \[[0-9]* MB\]$//')"
        EXE_OVERRIDE="$sel"
    fi
    return 0
}

aplicar_toggles_basicos() {
    # Aplica las opciones basicas marcadas en el asistente. Estaba escrito dos
    # veces (menus GTK y zenity): anadir una opcion nueva y tocar solo una de
    # las copias habria dado un fallo dificil de encontrar.
    local sel="$1"
    MANGOHUD=0; GAMEMODE=0; FSYNC=0; DXVK_ASYNC=0; WAYLAND=0
    case "$sel" in *MangoHud*)  MANGOHUD=1 ;; esac
    case "$sel" in *GameMode*)  GAMEMODE=1 ;; esac
    case "$sel" in *Fsync*)     FSYNC=1 ;; esac
    case "$sel" in *DXVK*)      DXVK_ASYNC=1 ;; esac
    case "$sel" in *Wayland*)   WAYLAND=1 ;; esac
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
1|Mando via SDL automático (DualSense/DS4 como Xbox)
0|NTsync (sincronizacion por kernel, 6.14+)
0|Wayland nativo (experimental)
EOF
        PYGAME_HIDE_SUPPORT_PROMPT=1 SDL_JOYSTICK_ALLOW_BACKGROUND_EVENTS=1 \
            env -u LD_PRELOAD "$PY_BIN" "$MENU_PYGAME_PY" check "Paso 3/3 - Configuración basica" "$tmpsel" "$tmpopt" >> "$LOG_FILE" 2>&1
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
1|Mando via SDL automático (DualSense/DS4 como Xbox)
0|Wayland nativo (experimental)
EOF
        "$SYS_PY" "$MENU_GTK_PY" check "Paso 3/3 - Configuración basica" "$tmpsel" "$tmpopt" >> "$LOG_FILE" 2>&1
        local sel; sel="$(cat "$tmpsel")"; rm -f "$tmpsel" "$tmpopt"
        [ -z "$sel" ] && return 1
        aplicar_toggles_basicos "$sel"
        return 0
    fi
    if [ "$HAS_ZENITY" = 1 ]; then
        local tmpsel; tmpsel="$(mktemp)"
        zenity --list --checklist --title="WProton" \
            --text="Paso 3/3 - Configuración basica (X del mando marca/desmarca)" \
            --column="On" --column="Opción" \
            FALSE "MangoHud (FPS en pantalla)" \
            TRUE  "GameMode (prioridad CPU)" \
            TRUE  "Fsync (sincronizacion rapida)" \
            TRUE  "DXVK Async + GPL (menos stutter en AMD)" \
            FALSE "Wayland nativo (experimental)" \
            --height=440 --width=560 --separator='|' > "$tmpsel" 2>/dev/null
        local rc=$? sel; sel="$(cat "$tmpsel")"; rm -f "$tmpsel"
        [ $rc -ne 0 ] && return 1
        aplicar_toggles_basicos "$sel"
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
        : # eligio automático pudiendo elegir el incluido: respetar
    fi
    if [ "$RUNNER" = "bundled" ] && has_bundled_prefix "$root"; then
        # Wine incluido elegido: ofrecer también su prefix (van de la mano)
        if ui_ask "Usar también el prefix incluido en el wsquashfs?
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
Runner: ${RUNNER:-último GE-Proton} | Prefijo: compartido (prefixes/default)
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
    # Mandos de Sony. GE-Proton 11-4 ("arreglo de mandos") cambio como se
    # manejan DualSense y DS4, y trajo estas variables pensadas sobre todo
    # para jugar FUERA de Steam, que es nuestro caso: los ajustes automaticos
    # de Proton solo se activan para juegos conocidos DE Steam.
    # OJO: los modos Sony trabajan SOBRE hidraw, y "Mando via SDL" lo APAGA
    # (PROTON_DISABLE_HIDRAW=1). Activar los dos a la vez deja los ajustes
    # Sony sin efecto, que es justo lo que pasaba: el registro decia
    # "DualSense como DualShock 4" y a la vez "SDL: ACTIVADO", y el mando
    # seguia sin responder. Si se elige un modo Sony, SDL se apaga.
    # Si el runner sabe manejarlos solo y el usuario no ha pedido un modo
    # concreto, WProton no toca NINGUNA variable de mando. Interferir era lo
    # que rompia el soporte nuevo.
    # ¿Deja WProton los mandos en manos del runner? Desde GE-Proton 11-4 el
    # soporte de Sony esta rehecho y funciona solo; interferir es lo que lo
    # rompia. OJO: aqui NO se puede hacer "return", porque despues de los
    # ajustes de mando esta todo lo demas (NTsync, FSR, WineD3D, overrides,
    # variables extra). Se usa una bandera y se saltan SOLO los de mando.
    local mandos_del_runner=0
    if [ "${PAD_SONY:-auto}" = auto ] && [ "${PAD_SDL:-auto}" = auto ] \
       && runner_gestiona_mandos "$(basename "$rdir")"; then
        mandos_del_runner=1
        unset PROTON_USE_SDL PROTON_PREFER_SDL PROTON_DISABLE_HIDRAW
        say "[+] Mandos: los gestiona $(basename "$rdir"), WProton no interviene"
        # GE-Proton 11-4+ lee los mandos de Sony por /dev/hidraw. Si esos
        # nodos no se pueden leer, el soporte nuevo no ve el mando y no hay
        # variable que lo arregle: es un permiso del sistema.
        if hidraw_sin_permiso >/dev/null; then
            say "[!] Hay nodos /dev/hidraw sin permiso de lectura."
            say "    $(basename "$rdir") lee ahi los mandos de Sony, asi que"
            say "    el mando puede no responder. Solucion en el manual"
            say "    (apartado 'Mi mando de PlayStation no responde')."
        fi
    fi
    local pad_sony_activo=0
    [ "$mandos_del_runner" = 1 ] || case "${PAD_SONY:-auto}" in
        1)
            export PROTON_SONY_HIDRAW_XINPUT=1
            pad_sony_activo=1
            say "[+] Mando Sony: forzado a mando de Xbox" ;;
        0)
            say "[+] Mando Sony: sin tocar (desactivado en el perfil)" ;;
    esac
    if [ "$mandos_del_runner" = 1 ]; then
        :                                   # el runner se encarga
    elif [ "$pad_sony_activo" = 1 ]; then
        # hidraw tiene que quedar ENCENDIDO para que los ajustes Sony valgan
        unset PROTON_USE_SDL PROTON_PREFER_SDL PROTON_DISABLE_HIDRAW
        say "    (Mando via SDL se ignora: es incompatible con los modos Sony)"
    elif [ "${PAD_SDL:-auto}" = auto ]; then
        pad_auto="$(pad_sdl_auto)"
        pad_eff="${pad_auto%%|*}"; pad_why="auto: ${pad_auto#*|}"
    else
        pad_eff="$PAD_SDL"; pad_why="fijado en el perfil"
    fi
    if [ "$mandos_del_runner" = 1 ] || [ "$pad_sony_activo" = 1 ]; then
        :                                   # ya resuelto arriba
    elif [ "$pad_eff" = 1 ]; then
        # PROTON_USE_SDL es la opcion "sdlinput" de GE-Proton: usa la
        # entrada SDL EN VEZ de hidraw, que es como funcionaba antes de la
        # 11-4. PROTON_PREFER_SDL es el nombre antiguo (GE-Proton 9-24), se
        # deja por si el runner es mas viejo.
        #
        # NO se toca PROTON_DISABLE_HIDRAW: en Proton no es un si/no, espera
        # una lista de fabricante/modelo. Pasarle "1" no desactivaba nada y
        # solo servia para chocar con los ajustes de mandos Sony.
        export PROTON_USE_SDL=1 PROTON_PREFER_SDL=1
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
    if [ "${PAD_STEAMFIX:-0}" = 1 ]; then
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
        # que SDL busque también por evdev clasico, no solo hidapi
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
        # shellcheck disable=SC2086,SC2163  # a proposito: EXTRA_ENV trae
        # varias asignaciones ("A=1 B=2") y hay que exportarlas todas
        export $EXTRA_ENV
    fi
}

build_runner_cmd() {
    local rdir="$1" kind
    kind="$(runner_kind "$rdir")" || die "Runner invalido: $rdir"
    RUN_CMD=()
    # La superposicion de Steam se cuela por LD_PRELOAD cuando WProton se
    # lanza desde el modo Juego, y en 32 bits ni siquiera carga: llena el
    # registro de "wrong ELF class" y puede estorbar. Se quita para el juego;
    # umu y Proton ya ponen lo que necesitan.
    case "${LD_PRELOAD:-}" in
        *gameoverlayrenderer*)
            log "Quitada la superposicion de Steam del LD_PRELOAD del juego"
            RUN_CMD+=(env -u LD_PRELOAD) ;;
    esac
    local gs_args="$GAMESCOPE"
    if [ -z "$gs_args" ] && [ "${IS_GAMESCOPE:-0}" = 1 ] && [ "${NESTED_GAMESCOPE:-0}" = 1 ]; then
        # Modo Juego con gamescope anidado (opcional, OFF por defecto).
        # Ayuda a que el foco vuelva a los menus al salir del juego, PERO la
        # capa Vulkan del gamescope exterior intenta enganchar un swapchain
        # que ya no controla y el juego avisa de "Hooking has failed
        # somewhere!" con la imagen a tirones. Por eso se desactiva aquí esa
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
        local _wdir; _wdir="$(dirname "$wbin")"
        export PATH="$_wdir:$PATH"
        RUN_CMD+=("$wbin")
    fi
    RUNNER_KIND="$kind"
}

launch_game() {
    local squash="$1" mode="${2:-auto}"
    local gid; gid="$(game_id "$squash")"

    # BLINDAJE: desde AQUI hasta que el juego termine, WProton ignora las
    # senales de cierre.
    #
    # En el modo Juego de SteamOS, WProton se lanza como acceso directo de
    # Steam. Al cerrarse nuestra ventana para dejar paso al juego, Steam o
    # gamescope pueden dar por terminado el "juego" y mandar una senal TERM.
    # Eso disparaba la trampa de salida, que DESMONTA... a veces incluso
    # antes de arrancar el juego. Y en los .wsquashfs con prefijo incluido
    # los ficheros de Wine viven DENTRO del montaje: el juego se quedaba sin
    # nada y moria con "Transport endpoint is not connected".
    trap '' INT TERM
    WP_JUGANDO=1

    # Juego nuevo: si la comunidad ya tiene una configuracion probada para el,
    # ofrecerla antes de que el usuario tenga que pelearse con los ajustes.
    profile_exists "$gid" || community_offer_for "$gid" || true

    # Recordar como "último juego jugado"
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
        say "AVISO: el perfil pide el Wine incluido pero este wsquashfs no lo trae - runner automático"
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
    AUTORUN_ENV=""; AUTORUN_LANG=""     # que no se hereden del juego anterior
    if [ -n "$EXE_OVERRIDE" ] && [ -f "$merged/$EXE_OVERRIDE" ] && [ "$mode" = "auto" ]; then
        EXE_PATH="$merged/$EXE_OVERRIDE"; EXE_ARGS="$ARGS_OVERRIDE"
    else
        find_exe "$merged" "$mode" || die "No se selecciono ningun ejecutable"
        [ -n "$ARGS_OVERRIDE" ] && EXE_ARGS="$ARGS_OVERRIDE"
    fi
    say "Ejecutable: $EXE_PATH"
    [ -n "$EXE_ARGS" ] && say "Argumentos: $EXE_ARGS"

    loading_say "Preparando el entorno de Windows..."
    ensure_runner
    local rdir; rdir="$(get_runner_path)"
    [ -z "$rdir" ] && die "No hay runners instalados. Ejecuta: $0 --setup"

    export_game_env "$gid"
    build_runner_cmd "$rdir"
    pad_sdl_prefix_setup "$rdir"
    bundled_prefix_prepare "$rdir"

    guardia_salida_start
    loading_say "Iniciando $gid..."
    # (el blindaje ya esta puesto desde el principio de launch_game)
    # BLINDAJE DURANTE LA PARTIDA
    #
    # En el modo Juego de SteamOS, WProton se lanza como acceso directo de
    # Steam. Al cerrarse nuestra ventana para dejar paso al juego, Steam o
    # gamescope pueden dar por terminado el "juego" y mandarnos una senal
    # TERM. Eso disparaba la trampa de salida, que DESMONTA... con el juego
    # todavia corriendo. Como en los .wsquashfs con prefijo incluido los
    # ficheros de Wine viven DENTRO del montaje, el juego se quedaba sin nada
    # y moria con "Transport endpoint is not connected".
    #
    # Mientras dura la partida esas senales se ignoran. Al terminar se
    # restablece la trampa normal.
    pad_bridge_stop   # el mando vuelve a ser del juego, no de los menus
    # La pantalla de carga aguanta unos segundos mas, hasta que el juego
    # pinta lo suyo: si la cerramos aqui se ve el escritorio de por medio.
    # Pero NO se queda durante toda la partida: mantener una conexion
    # grafica abierta mientras el juego corre es lo que acababa en "XIO:
    # fatal IO error" al reconfigurar gamescope su XWayland. El servidor se
    # vuelve a levantar al terminar, en post_game_resettle.
    # NUESTRA VENTANA SE CIERRA ANTES DE LANZAR, sin retrasos.
    #
    # Hubo un intento de dejarla viva unos segundos para tapar el hueco de
    # escritorio mientras el juego arranca. Salio caro: una ventana a
    # pantalla completa por delante del juego se queda con el FOCO DEL
    # TECLADO, asi que las teclas del mapeador (y del teclado de verdad) no
    # llegaban al juego, y los juegos en ventana parecian esconderse detras.
    # Un parpadeo de escritorio es mucho menos grave que un mando que no
    # responde: se cierra ya y punto.
    menu_server_stop
    canvas_stop
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
    # Avisos utiles para diagnosticar problemas de mando:
    if [ "$RUNNER_KIND" = proton ] && [ "${GAMEID:-umu-default}" = "umu-default" ]; then
        say "[!] Sin GAMEID propio: protonfixes no aplicara los arreglos de este juego"
        say "    (Ajustes del juego -> Buscar en la base de umu, o ponerlo en GAMEID)"
    fi
    case "$(basename "$WINEPREFIX")" in
        default|shared)
            say "[i] Usa el prefijo compartido: si el mando falla, prueba con uno propio" ;;
    esac
    # Diagnostico completo del mando (se puede apagar con WP_DIAG_PAD=0)
    [ "${DIAG_MANDO:-0}" = 1 ] && diag_mando_antes
    local t0; t0=$(date +%s)
    STATS_T0="$t0"
    saves_detect_start
    # Vigilante: cuando el juego ya este corriendo, apunta en el registro lo
    # que ha recibido DE VERDAD. Es la unica forma de saber si nuestras
    # variables llegaron o alguien las cambio por el camino.
    if [ "${DIAG_MANDO:-0}" = 1 ]; then
        ( exe_base="$(basename "$EXE_PATH")"
          for _i in $(seq 1 40); do
              sleep 0.5
              _p="$(pgrep -f "$exe_base" 2>/dev/null | head -n1)"
              [ -n "$_p" ] || continue
              diag_mando_despues "$_p"
              # ademas, que mandos ve el juego ya abierto
              _n="$(ls /dev/input/js* 2>/dev/null | wc -l)"
              say "    joysticks visibles con el juego abierto: $_n"
              break
          done ) >/dev/null 2>&1 &
    fi
    (
        cd "$(dirname "$EXE_PATH")" || exit 1
        # los .bat/.cmd se lanzan con "cmd /c"
        local -a PRE=()
        while IFS= read -r _a; do [ -n "$_a" ] && PRE+=("$_a"); done <<EOFRA
$(run_args_for "$EXE_PATH")
EOFRA
        # shellcheck disable=SC2086
        "${RUN_CMD[@]}" "${PRE[@]}" $EXE_ARGS >> "$LOG_FILE" 2>&1
    )
    local rc=$?
    guardia_salida_stop
    # El mapeador tiene que parar AQUI, al terminar el juego, no al cerrar
    # WProton. Mientras siga vivo convierte los botones del mando en teclas
    # del sistema, y esas teclas se las come el menu: con un .keys que asigne
    # A a la letra "i", entrar en una carpeta escribia "i" en el buscador.
    # Antes solo se paraba en la limpieza final, asi que seguia actuando
    # durante todo el rato que estuvieras navegando despues de jugar.
    mapeador_stop
    WP_JUGANDO=0
    trap cleanup_all INT TERM        # se vuelve a atender las senales
    local dur=$(( $(date +%s) - t0 ))
    if [ $rc -ne 0 ] && [ $dur -lt 10 ]; then
        ui_error "El juego fallo al arrancar (rc=$rc en ${dur}s).
Últimas lineas del log:
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

fecha_remota() {
    # Fecha (en segundos) de la ultima publicacion. Sirve para detectar que se
    # ha vuelto a subir la MISMA version con correcciones: mirando solo el
    # numero, esa republicacion pasaria desapercibida.
    local cab fecha
    fecha="$(curl -fsSL "https://api.github.com/repos/$WPROTON_REPO/releases/latest" 2>/dev/null \
        | grep -o '"published_at": *"[^"]*"' | head -n1 | cut -d'"' -f4)"
    if [ -n "$fecha" ]; then
        date -d "$fecha" +%s 2>/dev/null && return 0
    fi
    # sin release: la cabecera del fichero en la rama principal
    cab="$(curl -fsSLI "https://raw.githubusercontent.com/$WPROTON_REPO/main/wproton.sh" 2>/dev/null \
        | grep -i '^last-modified:' | head -n1 | cut -d' ' -f2-)"
    [ -n "$cab" ] || return 1
    date -d "$cab" +%s 2>/dev/null || return 1
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
    # Se guardan por separado la ETIQUETA tal cual esta en GitHub (para
    # construir las URLs) y su parte NUMERICA (para comparar). La etiqueta
    # puede venir como "v1.02", "V1.02" o "1.02": si se le quita solo la "v"
    # minuscula, awk convierte "V1.02" a 0 y WProton cree que esta al dia.
    local remote="" tag=""
    tag="$(curl -fsSL "https://api.github.com/repos/$WPROTON_REPO/releases/latest" 2>/dev/null \
        | grep -o '"tag_name": *"[^"]*"' | cut -d'"' -f4)"
    remote="$(printf '%s' "$tag" | sed 's/^[vV]//')"
    if [ -z "$remote" ]; then
        # sin releases: leer la versión de la rama main
        remote="$(curl -fsSL "https://raw.githubusercontent.com/$WPROTON_REPO/main/wproton.sh" 2>/dev/null \
            | grep -m1 '^WPROTON_VERSION=' | cut -d'"' -f2)"
        tag="v$remote"
    fi
    [ -z "$remote" ] && { ui_error "No se pudo consultar la versión en GitHub ($WPROTON_REPO)"; return 1; }
    # La version tiene que ser un numero: si no, algo raro pasa con la etiqueta
    # y es mejor decirlo que comparar contra cero y quedarse tan tranquilo.
    if ! printf '%s' "$remote" | grep -qE '^[0-9]+(\.[0-9]+)?$'; then
        ui_error "La versión publicada no se entiende: '$tag'

Se esperaba algo como v1.02. Revisa la etiqueta de la release."
        return 1
    fi
    log "Actualizaciones: local=$WPROTON_VERSION remota=$remote (etiqueta $tag)"
    local motivo=""
    # Nomenclatura decimal: 0.5 < 0.51 < 0.52 < 0.6 < 1.0 (sort -V NO vale aquí)
    if awk -v a="$WPROTON_VERSION" -v b="$remote" 'BEGIN{exit !(b+0 > a+0)}'; then
        motivo="Hay una versión nueva: v$remote (actual v$WPROTON_VERSION)."
    elif [ "$remote" = "$WPROTON_VERSION" ]; then
        # MISMA version: puede haberse vuelto a publicar con correcciones. Se
        # compara la FECHA de la publicacion con la de nuestro fichero. Solo
        # con la version IDENTICA: si la remota fuera mas baja, ofrecer
        # "actualizar" seria en realidad volver atras.
        local f_remota f_local
        f_remota="$(fecha_remota)" || f_remota=""
        f_local="$(stat -c %Y "$(readlink -f "$0")" 2>/dev/null || echo 0)"
        if [ -n "$f_remota" ] && [ "$f_remota" -gt $(( f_local + 120 )) ]; then
            log "Actualizaciones: misma version, pero la publicada es mas nueva"
            motivo="La versión v$remote se ha vuelto a publicar
el $(date -d "@$f_remota" '+%d/%m/%Y a las %H:%M') con correcciones."
        fi
    fi
    if [ -z "$motivo" ]; then
        ui_info "WProton esta al dia (v$WPROTON_VERSION; remota: v$remote)"
        return 0
    fi
    ui_ask "$motivo

Descargar y actualizar ahora?" || return 0
    local tmp; tmp="$(mktemp)"
    # Se usa la etiqueta REAL: si la release es "V1.02", pedir "v1.02" da 404
    local url_rel="https://github.com/$WPROTON_REPO/releases/download/$tag/wproton.sh"
    local url_tag="https://raw.githubusercontent.com/$WPROTON_REPO/$tag/wproton.sh"
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
    # $1 = nombre del .conf en el repositorio
    # $2 = gid del juego LOCAL (opcional). Es importante: el perfil de la
    #      comunidad se llama como el juego alli, y el nuestro puede llamarse
    #      distinto ("Dragon.Ball.FighterZ.Legendary.Edition" frente a
    #      "Dragon_Ball_FighterZ"). Si se guarda con el nombre de la
    #      comunidad, el juego nunca lo encuentra y parece que la descarga
    #      no hizo nada.
    local name="$1" gid="${2:-}"
    local dest tmp
    if [ -n "$gid" ]; then
        dest="$PROFILE_DIR/$gid.conf"
    else
        dest="$PROFILE_DIR/$name"
    fi
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
$(basename "$dest")

Sustituirlo por el de la comunidad?
(se guardara el tuyo como $(basename "$dest").bak)" || { rm -f "$tmp"; return 1; }
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
    local gid="$1"
    local src out
    src="$PROFILE_DIR/$gid.conf"
    [ -f "$src" ] || { ui_error "Este juego no tiene perfil todavia"; return 1; }
    mkdir -p "$BASE_DIR/compartir"
    out="$BASE_DIR/compartir/$gid.conf"
    # se quitan rutas y datos locales: solo lo que sirve a otros
    grep -vE '^(LAST_PLAYED|PLAY_COUNT|PLAY_SECONDS|FAVORITO|EXE_OVERRIDE)=' "$src" > "$out"
    ui_info "Perfil listo para compartir:

compartir/$gid.conf

Subelo a la carpeta profiles/ del repositorio (pull request).
Se han quitado tus estadísticas y rutas locales."
    return 0
}

COMMUNITY_INDEX="$RUNTIME_DIR/.community_index"

community_index_refresh() {
    # Lista de perfiles del repositorio, cacheada un dia. Se consulta en
    # segundo plano y sin ruido: si no hay red, simplemente no hay aviso.
    [ -n "${WPROTON_REPO:-}" ] || return 1
    if [ -f "$COMMUNITY_INDEX" ]; then
        local edad
        edad=$(( $(date +%s) - $(stat -c %Y "$COMMUNITY_INDEX" 2>/dev/null || echo 0) ))
        [ "$edad" -lt 86400 ] && return 0
    fi
    mkdir -p "$RUNTIME_DIR" 2>/dev/null
    community_list > "$COMMUNITY_INDEX.tmp" 2>/dev/null
    if [ -s "$COMMUNITY_INDEX.tmp" ]; then
        mv -f "$COMMUNITY_INDEX.tmp" "$COMMUNITY_INDEX"
    else
        rm -f "$COMMUNITY_INDEX.tmp"
        return 1
    fi
    return 0
}

nombre_clave() {
    # Nombre normalizado para comparar: sin mayusculas, sin separadores y sin
    # la coletilla de version o grupo que traen las descargas. Es la base de
    # TODAS las busquedas (umu, caratulas, ficha del juego): si esto falla,
    # se muestran datos de otro juego, que es peor que no mostrar ninguno.
    printf '%s' "$1" | tr 'A-ZÁÉÍÓÚÑ' 'a-záéíóúñ' | tr -d ' ._-'
}

nombre_coletilla() {
    # ¿Lo que sobra tras el nombre es una version o un grupo? Sirve para
    # aceptar "Mina.the.Hollower.v1.0.2" como "Mina the Hollower" sin que
    # "Doom" se lleve por delante a "Doom Eternal".
    case "${1:-}" in
        v[0-9]*|[0-9]*|gog*|repack*|p2p*|fitgirl*|dodi*|elamigos*|\
        multi[0-9]*|rip*|proper*|update*|build*|remastered0*) return 0 ;;
    esac
    return 1
}

# ---------------------------------------------------------------------------
# BASE DE DATOS DE UMU
#   umu-database.csv (Open-Wine-Components) relaciona titulos de juego con su
#   identificador umu. Ese identificador es el que usa protonfixes para
#   aplicar los arreglos concretos de cada juego, asi que ponerlo bien puede
#   ser la diferencia entre que un juego arranque o no.
#   Son ~1200 entradas y 90 KB: se descarga entera y se consulta en local.
# ---------------------------------------------------------------------------
UMUDB_URL="https://raw.githubusercontent.com/Open-Wine-Components/umu-database/main/umu-database.csv"

umudb_file()   { printf '%s' "$RUNTIME_DIR/umu-database.csv"; }
umudb_titles() { printf '%s' "$RUNTIME_DIR/.umu-titles"; }

umudb_update() {
    # Descarga la base si falta o si tiene mas de una semana. Sin red no pasa
    # nada: se usa la copia que haya, y si no hay ninguna se sigue sin ella.
    local f; f="$(umudb_file)"
    if [ -f "$f" ]; then
        local edad
        edad=$(( $(date +%s) - $(stat -c %Y "$f" 2>/dev/null || echo 0) ))
        [ "$edad" -lt 604800 ] && [ -s "$f" ] && return 0
    fi
    mkdir -p "$RUNTIME_DIR" 2>/dev/null
    say "Actualizando la base de datos de umu..."
    # Limite corto a proposito: esto solo sirve para PROPONER datos. Si la
    # red va lenta, se sigue sin ella; lo contrario es dejar al usuario
    # mirando una pantalla quieta sin saber cuanto falta.
    if curl -fsSL --max-time 8 "$UMUDB_URL" -o "$f.tmp" 2>/dev/null \
       && [ -s "$f.tmp" ] && grep -qi 'umu' "$f.tmp"; then
        mv -f "$f.tmp" "$f"
        rm -f "$(umudb_titles)"      # el indice se rehace
        log "Base de umu actualizada: $(wc -l < "$f") entradas"
        return 0
    fi
    rm -f "$f.tmp"
    [ -s "$f" ] && return 0
    log "No se pudo descargar la base de umu" WARN
    return 1
}

umudb_col() {
    # Numero de la columna cuya cabecera coincide con $1 (insensible a
    # mayusculas). Se lee de la CABECERA en vez de dar por hecho el orden:
    # si el proyecto reordena columnas, esto sigue funcionando.
    local f; f="$(umudb_file)"
    [ -f "$f" ] || return 1
    head -n1 "$f" | tr ',' '\n' | tr -d '"\r' \
        | grep -in "^$1$" | head -n1 | cut -d: -f1
}

umudb_index() {
    # Construye el indice de busqueda en UNA sola pasada de awk.
    #
    # Antes se recorria el CSV en bash llamando a 'tr' por linea: con las 1200
    # entradas reales, una busqueda sin resultado tardaba 7 SEGUNDOS. Con el
    # indice precalculado la busqueda es un 'grep' y es instantanea.
    #
    # Formato: clave|titulo|umu_id     (una linea por forma de encontrarlo)
    # Se indexa por TITULO, por ACRONIMO (aow -> Age of Wonders) y por
    # EXE_STRINGS: el nombre del ejecutable es la pista mas fiable de todas,
    # porque no depende de como se llame la carpeta.
    local f t ct cu ca ce
    f="$(umudb_file)"; t="$(umudb_titles)"
    [ -f "$f" ] || return 1
    [ -s "$t" ] && [ "$t" -nt "$f" ] && return 0
    ct="$(umudb_col title)";   [ -n "$ct" ] || ct=1
    cu="$(umudb_col umu_id)";  [ -n "$cu" ] || cu=4
    ca="$(head -n1 "$f" | tr ',' '\n' | grep -in 'acronym' | head -n1 | cut -d: -f1)"
    ce="$(head -n1 "$f" | tr ',' '\n' | grep -in 'exe_strings' | head -n1 | cut -d: -f1)"
    awk -F',' -v ct="$ct" -v cu="$cu" -v ca="${ca:-0}" -v ce="${ce:-0}" '
        function limpia(x) {
            gsub(/^"|"$|\r/, "", x)
            return x
        }
        function clave(x,   y) {
            y = tolower(limpia(x))
            gsub(/[ ._-]/, "", y)
            return y
        }
        NR == 1 { next }
        {
            titulo = limpia($ct); id = limpia($cu)
            if (titulo == "" || id == "") next
            k = clave(titulo)
            if (k != "" && !(k SUBSEP id in visto)) {
                visto[k SUBSEP id] = 1
                print k "|" titulo "|" id
            }
            if (ca > 0) {
                a = clave($ca)
                if (a != "" && length(a) >= 3 && !(a SUBSEP id in visto)) {
                    visto[a SUBSEP id] = 1
                    print a "|" titulo "|" id
                }
            }
            if (ce > 0) {
                n = split(limpia($ce), exes, /[;: ]+/)
                for (i = 1; i <= n; i++) {
                    e = clave(exes[i])
                    sub(/exe$/, "", e)
                    if (e != "" && length(e) >= 4 && !(e SUBSEP id in visto)) {
                        visto[e SUBSEP id] = 1
                        print e "|" titulo "|" id
                    }
                }
            }
        }' "$f" | sort -u > "$t"
    log "Indice de umu: $(wc -l < "$t") claves"
    return 0
}

umudb_buscar() {
    # $1 = nombre del juego (o del ejecutable). Imprime "titulo|umu_id".
    # Exacto primero; luego admitiendo la coletilla de version o grupo.
    local clave linea lclave resto t
    t="$(umudb_titles)"
    [ -s "$t" ] || return 1
    clave="$(nombre_clave "$1")"
    [ -n "$clave" ] || return 1
    linea="$(grep -m1 -F "$clave|" "$t" 2>/dev/null)" || linea=""
    if [ -n "$linea" ] && [ "${linea%%|*}" = "$clave" ]; then
        printf '%s' "${linea#*|}"
        return 0
    fi
    # el nombre del juego lleva version o grupo detras: "juego|" seria prefijo
    while IFS='|' read -r lclave titulo id; do
        [ -n "$lclave" ] || continue
        [ ${#lclave} -ge 6 ] || continue
        case "$clave" in
            "$lclave"*)
                resto="${clave#"$lclave"}"
                nombre_coletilla "$resto" && { printf '%s|%s' "$titulo" "$id"; return 0; } ;;
        esac
    done < "$t"
    return 1
}

umudb_parecidos() {
    # Titulos que empiezan igual, para preguntar en vez de adivinar
    local clave t
    t="$(umudb_titles)"; [ -s "$t" ] || return 1
    clave="$(nombre_clave "$1")"
    [ ${#clave} -ge 4 ] || return 1
    grep -F "${clave:0:4}" "$t" 2>/dev/null | cut -d'|' -f2 | sort -u | head -n 5
}

umudb_sugerir() {
    # $1 = gid del juego, $2 = ruta del ejecutable (opcional, la mejor pista)
    # Si la base conoce el juego, ofrecer su identificador. 0 = aceptado.
    local gid="$1" exe="${2:-}" r="" titulo id cands sel
    umudb_update || return 1
    umudb_index  || return 1
    # 1) por el nombre del EJECUTABLE: es la pista mas fiable, porque no
    #    depende de como se llame la carpeta del juego
    if [ -n "$exe" ]; then
        r="$(umudb_buscar "$(basename "$exe" .exe)")" || r=""
    fi
    # 2) por el nombre del juego
    [ -z "$r" ] && { r="$(umudb_buscar "$gid")" || r=""; }
    if [ -z "$r" ]; then
        # sin coincidencia clara: PREGUNTAR, nunca adivinar
        cands="$(umudb_parecidos "$gid")" || return 1
        [ -n "$cands" ] || return 1
        sel="$(IFS=$'\n'; set -f; menu "¿Cuál de estos es '$gid'?" \
              $cands "Ninguno")" || return 1
        [ "$sel" = "Ninguno" ] && return 1
        r="$(umudb_buscar "$sel")" || return 1
    fi
    titulo="${r%%|*}"; id="${r##*|}"
    [ -n "$id" ] || return 1
    if ui_ask "Este juego está en la base de datos de umu como:

$titulo
Identificador: $id

Con él, umu aplica los arreglos conocidos de este juego.
¿Usarlo?"; then
        GAMEID="$id"
        say "[+] GAMEID de umu: $id ($titulo)"
        return 0
    fi
    return 1
}

# ---------------------------------------------------------------------------
# FICHA DEL JUEGO
#   Datos de la tienda de Steam: no necesita clave ni cuenta, y trae fecha,
#   desarrollador, editor, generos y la nota de Metacritic. Cubre la mayoria
#   de juegos de PC. Lo que se consulta se guarda en covers/<gid>.info.json
#   para no repetir la peticion.
#   Si no hay red o el juego no esta, la ficha muestra igualmente lo que
#   sabemos por nosotros mismos: tamaño, veces jugado y tiempo total.
# ---------------------------------------------------------------------------
ficha_file() { printf '%s' "$DATOS_DIR/${1}.info.json"; }

ficha_appid() {
    # Busca el juego en la tienda de Steam y devuelve "appid|nombre".
    #
    # Todo en Python: analizar JSON con sed es fragil, y ademas el intento
    # anterior tenia un fallo tipico de bash -- un 'return' dentro de una
    # tuberia NO sale de la funcion, asi que siempre devolvia error aunque
    # hubiera encontrado el juego.
    #
    # De los candidatos se elige el que casa por nombre normalizado (sin
    # mayusculas ni separadores); si ninguno casa exactamente, se acepta el
    # que empiece igual. Nunca "el primero de la lista".
    local nombre="$1"
    [ -n "${PY_BIN:-}" ] && [ -x "$PY_BIN" ] || return 1
    "$PY_BIN" - "$nombre" <<'PYAPPID' 2>>"$LOG_FILE"
import json, re, sys, urllib.parse, urllib.request

def clave(x):
    x = x.lower()
    for c in ' ._-:\'!,':
        x = x.replace(c, '')
    return x

nombre = sys.argv[1]
k = clave(nombre)
url = ('https://steamcommunity.com/actions/SearchApps/'
       + urllib.parse.quote(nombre))
try:
    req = urllib.request.Request(url, headers={'User-Agent': 'WProton'})
    datos = json.load(urllib.request.urlopen(req, timeout=15))
except Exception as e:
    sys.stderr.write('ficha: fallo consultando Steam (%s)\n' % e)
    sys.exit(1)
if not datos:
    sys.stderr.write('ficha: Steam no conoce "%s"\n' % nombre)
    sys.exit(1)
exacto = None
parecido = None
for d in datos:
    n = d.get('name', '')
    a = d.get('appid', '')
    if not n or not a:
        continue
    kn = clave(n)
    if kn == k:
        exacto = (a, n)
        break
    if parecido is None and (kn.startswith(k) or k.startswith(kn)):
        parecido = (a, n)
elegido = exacto or parecido
if not elegido:
    sys.stderr.write('ficha: ningun resultado de Steam coincide con "%s"\n' % nombre)
    sys.exit(1)
print('%s|%s' % elegido)
PYAPPID
}

ficha_descargar() {
    # $1 = gid, $2 = nombre a buscar. Guarda la ficha en covers/<gid>.info.json
    local gid="$1" nombre="$2" r appid titulo out
    r="$(ficha_appid "$nombre")" || return 1
    appid="${r%%|*}"; titulo="${r##*|}"
    [ -n "$appid" ] || return 1
    out="$(ficha_file "$gid")"
    mkdir -p "$COVERS_DIR"
    curl -fsSL --max-time 8 \
        "https://store.steampowered.com/api/appdetails?appids=$appid&l=spanish" \
        -o "$out.tmp" 2>/dev/null || { rm -f "$out.tmp"; return 1; }
    if grep -q '"success"[^t]*true' "$out.tmp" 2>/dev/null; then
        mv -f "$out.tmp" "$out"
        log "Ficha de $gid: $titulo (appid $appid)"
        return 0
    fi
    rm -f "$out.tmp"
    return 1
}

# ---------------------------------------------------------------------------
# DURACION DEL JUEGO (HowLongToBeat)
#   Es un EXTRA OPCIONAL: howlongtobeat.com no tiene API oficial, asi que se
#   usa la biblioteca howlongtobeatpy (MIT), que se encarga de seguir los
#   cambios de su web. Si no esta instalada, la ficha simplemente no muestra
#   la duracion; nada mas deja de funcionar.
#   Se instala desde: Runners y herramientas -> Datos de duracion.
# ---------------------------------------------------------------------------
hltb_disponible() {
    [ -n "${PY_BIN:-}" ] && [ -x "$PY_BIN" ] || return 1
    PYTHONPATH="$RUNTIME_DIR/$(py_libs_dir)" "$PY_BIN" \
        -c 'import howlongtobeatpy' >/dev/null 2>&1
}

hltb_instalar() {
    if hltb_disponible; then
        ui_info "Los datos de duración ya están instalados."
        return 0
    fi
    if ! ui_ask "Instalar los datos de duración de partida (HowLongToBeat)?

Añade a la ficha del juego cuánto se tarda en terminarlo.
Ocupa poco (unos 100 KB) y es opcional: si no lo instalas,
el resto de la ficha funciona igual."; then
        return 1
    fi
    loading_say "Instalando datos de duración..."
    if "$PY_BIN" -m pip install --target "$RUNTIME_DIR/$(py_libs_dir)" \
            --disable-pip-version-check --no-warn-script-location \
            --upgrade howlongtobeatpy >> "$LOG_FILE" 2>&1 && hltb_disponible; then
        ui_info "Datos de duración instalados.

A partir de ahora la ficha del juego mostrará cuánto se tarda
en terminarlo."
        return 0
    fi
    ui_error "No se pudieron instalar (mira el registro).
El resto de la ficha del juego sigue funcionando."
    return 1
}

hltb_duracion() {
    # $1 = nombre del juego -> "historia|completo" en horas, o nada.
    # Solo se acepta un resultado si el nombre se parece de verdad (0.7): mas
    # vale no decir nada que dar la duracion de otro juego.
    hltb_disponible || return 1
    PYTHONPATH="$RUNTIME_DIR/$(py_libs_dir)" "$PY_BIN" - "$1" <<'PYHLTB' 2>/dev/null
import sys
try:
    from howlongtobeatpy import HowLongToBeat
    res = HowLongToBeat().search(sys.argv[1], similarity_case_sensitive=False)
    if not res:
        sys.exit(1)
    mejor = max(res, key=lambda e: e.similarity)
    if mejor.similarity < 0.7:          # no es el mismo juego: mejor callar
        sys.exit(1)
    hist = getattr(mejor, 'main_story', None) or 0
    todo = getattr(mejor, 'completionist', None) or 0
    if not hist and not todo:
        sys.exit(1)
    print('%s|%s' % (hist, todo))
except Exception:
    sys.exit(1)
PYHLTB
}

ficha_campo() {
    # $1 = fichero json, $2 = ruta tipo "release_date.date" o "metacritic.score"
    "$PY_BIN" - "$1" "$2" <<'PYFICHA' 2>/dev/null
import json, sys
try:
    d = json.load(open(sys.argv[1], encoding='utf-8'))
    d = list(d.values())[0].get('data', {})
    for parte in sys.argv[2].split('.'):
        if isinstance(d, list):
            d = d[int(parte)]
        else:
            d = d.get(parte)
        if d is None:
            sys.exit(1)
    if isinstance(d, list):
        d = ', '.join(x.get('description', x) if isinstance(x, dict) else str(x)
                      for x in d[:4])
    print(d)
except Exception:
    sys.exit(1)
PYFICHA
}

ficha_mostrar() {
    # $1 = gid, $2 = ruta del juego. Muestra la ficha del juego.
    local gid="$1" ruta="${2:-}" f titulo texto nom=""
    f="$(ficha_file "$gid")"
    if [ ! -s "$f" ]; then
        loading_say "Buscando información de $gid..."
        titulo="$(printf '%s' "$gid" | tr '_' ' ')"
        ficha_descargar "$gid" "$titulo" || true
        loading_clear
    fi
    texto=""
    if [ -s "$f" ]; then
        local fecha dev edi gen mc
        nom="$(ficha_campo "$f" name)"
        fecha="$(ficha_campo "$f" release_date.date)"
        dev="$(ficha_campo "$f" developers)"
        edi="$(ficha_campo "$f" publishers)"
        gen="$(ficha_campo "$f" genres)"
        mc="$(ficha_campo "$f" metacritic.score)"
        texto="${nom:-$gid}
"
        [ -n "$fecha" ] && texto="$texto
Publicación:  $fecha"
        [ -n "$dev" ]   && texto="$texto
Desarrollo:   $dev"
        [ -n "$edi" ]   && texto="$texto
Edición:      $edi"
        [ -n "$gen" ]   && texto="$texto
Géneros:      $gen"
        [ -n "$mc" ]    && texto="$texto
Metacritic:   $mc / 100"

    else
        texto="$(printf '%s' "$gid" | tr '_' ' ')

(Sin información en la tienda de Steam)"
    fi

    # Duracion: extra opcional e INDEPENDIENTE de Steam. Antes estaba dentro
    # del bloque anterior, asi que un juego que Steam no conociera se quedaba
    # tambien sin duracion aunque HowLongToBeat si lo tuviera.
    local dur hist todo nombre_busqueda
    nombre_busqueda="${nom:-$(printf '%s' "$gid" | tr '_' ' ')}"
    dur="$(cat "$DATOS_DIR/${gid}.hltb" 2>/dev/null)" || dur=""
    if [ -z "$dur" ] && hltb_disponible; then
        loading_say "Consultando la duración de $nombre_busqueda..."
        dur="$(hltb_duracion "$nombre_busqueda")" || dur=""
        [ -n "$dur" ] && { mkdir -p "$DATOS_DIR" 2>/dev/null
                           printf '%s' "$dur" > "$DATOS_DIR/${gid}.hltb"; }
        loading_clear
    fi
    if [ -n "$dur" ]; then
        hist="${dur%%|*}"; todo="${dur##*|}"
        [ "${hist%%.*}" != "0" ] && texto="$texto
Duración:     $hist h la historia"
        [ "${todo%%.*}" != "0" ] && texto="$texto
              $todo h al 100%"
    fi
    # Lo que sabemos por nosotros mismos: esto sale SIEMPRE, con red o sin ella
    load_profile "$gid" 2>/dev/null || true
    texto="$texto

--- Tu partida ---"
    [ -n "$ruta" ] && [ -e "$ruta" ] && \
        texto="$texto
Tamaño:       $(human_size "$(dir_bytes "$ruta")")"
    texto="$texto
Veces jugado: ${PLAY_COUNT:-0}
Tiempo total: $(fmt_playtime "${PLAY_SECONDS:-0}")"
    [ -n "${LAST_PLAYED:-}" ] && [ "${LAST_PLAYED:-0}" != 0 ] && \
        texto="$texto
Última vez:   $(date -d "@$LAST_PLAYED" '+%d/%m/%Y' 2>/dev/null)"
    [ -n "${NOTAS:-}" ] && texto="$texto

Notas: $NOTAS"
    ui_info "$texto"
    return 0
}

community_match() {
    # $1 = gid -> nombre del .conf de la comunidad que le corresponde, si lo hay.
    #
    # Compara ignorando mayusculas y separadores (espacios, puntos, guiones y
    # subrayados), porque el mismo juego llega escrito de mil formas:
    #   "Mina the Hollower" / "Mina_the_Hollower" / "Mina.the.Hollower"
    #
    # Y admite ademas la coleta de version o grupo que traen las descargas
    # ("Mina.the.Hollower.v1.0.2", "Constance-GOG", "...-P2P"), pero SOLO si
    # lo que sobra es claramente eso: asi "Doom" no se lleva por delante a
    # "Doom Eternal".
    local gid="$1" clave linea lclave resto
    [ -f "$COMMUNITY_INDEX" ] || return 1
    clave="$(printf '%s' "$gid" | tr 'A-Z' 'a-z' | tr -d ' ._-')"
    [ -n "$clave" ] || return 1
    # 1) coincidencia exacta
    while IFS= read -r linea; do
        [ -n "$linea" ] || continue
        lclave="$(printf '%s' "${linea%.conf}" | tr 'A-Z' 'a-z' | tr -d ' ._-')"
        [ "$lclave" = "$clave" ] && { printf '%s' "$linea"; return 0; }
    done < "$COMMUNITY_INDEX"
    # 2) el juego lleva version/grupo detras del nombre del perfil
    while IFS= read -r linea; do
        [ -n "$linea" ] || continue
        lclave="$(printf '%s' "${linea%.conf}" | tr 'A-Z' 'a-z' | tr -d ' ._-')"
        [ ${#lclave} -ge 6 ] || continue          # nombres muy cortos: no arriesgar
        case "$clave" in
            "$lclave"*)
                resto="${clave#"$lclave"}"
                case "$resto" in
                    v[0-9]*|[0-9]*|gog*|repack*|p2p*|fitgirl*|dodi*|elamigos*|                    multi[0-9]*|rip*|proper*|update*|build*)
                        printf '%s' "$linea"; return 0 ;;
                esac ;;
        esac
    done < "$COMMUNITY_INDEX"
    return 1
}

community_offer_for() {
    # Al configurar o lanzar un juego por primera vez: si la comunidad tiene
    # un perfil con ese nombre, ofrecerlo. Solo se pregunta UNA vez por juego.
    local gid="$1" cand marca
    marca="$PROFILE_DIR/.$gid.nocomm"
    [ -f "$marca" ] && return 1
    [ -n "${WPROTON_REPO:-}" ] || return 1
    community_index_refresh || return 1
    cand="$(community_match "$gid")" || { : > "$marca" 2>/dev/null; return 1; }
    say "[comunidad] hay perfil para $gid: $cand"
    if ui_ask "La comunidad tiene una configuracion ya probada para:

$gid

Suele traer el runner y los ajustes que hacen falta para que
funcione bien. Quieres descargarla?"; then
        community_fetch "$cand" "$gid" && return 0
    fi
    : > "$marca" 2>/dev/null      # no volver a preguntar por este juego
    return 1
}

perfiles_menu() {
    # Gestion de los perfiles guardados: ver que hay y borrar lo que sobre.
    # Util cuando un perfil se queda mal (un ajuste que rompe el juego, o un
    # perfil de la comunidad que no era el del juego que uno tiene).
    local sel conf gid n
    while true; do
        local lista=""
        for conf in "$PROFILE_DIR"/*.conf; do
            [ -f "$conf" ] || continue
            gid="$(basename "$conf" .conf)"
            # se muestra el runner, que es lo que mas distingue un perfil
            local r; r="$(profile_get "$gid" RUNNER)" || r=""
            lista="$lista$gid   [${r:-auto}]
"
        done
        n="$(printf '%s' "$lista" | grep -c . || true)"
        if [ "$n" = 0 ]; then
            ui_info "No hay ningun perfil guardado todavia.

Se crean solos al configurar un juego."
            return 0
        fi
        # shellcheck disable=SC2046
        sel="$(IFS=$'\n'; set -f; menu "Perfiles guardados ($n)" \
              $lista "Borrar TODOS los perfiles" "<< Volver")" || return 0
        case "$sel" in
            "<< Volver") return 0 ;;
            "Borrar TODOS"*)
                ui_ask "¿Borrar los $n perfiles guardados?

Se pierden los ajustes de todos los juegos: runner, prefijo,
argumentos, notas y favoritos. Los juegos y las partidas NO se
tocan.

Se guardara una copia en profiles/copia_$(date +%Y%m%d)/" || continue
                local copia="$PROFILE_DIR/copia_$(date +%Y%m%d_%H%M)"
                mkdir -p "$copia" 2>/dev/null
                cp -f "$PROFILE_DIR"/*.conf "$copia"/ 2>/dev/null
                rm -f "$PROFILE_DIR"/*.conf 2>/dev/null
                ui_info "Perfiles borrados.

La copia esta en:
$copia" ;;
            *)
                gid="${sel%%   [*}"
                perfil_borrar "$gid" ;;
        esac
    done
}

perfil_borrar() {
    # $1 = gid. Borra su perfil tras confirmar, guardando una copia.
    local gid="$1" conf="$PROFILE_DIR/$1.conf"
    [ -f "$conf" ] || { ui_error "No hay perfil para $gid"; return 1; }
    local resumen
    resumen="$(grep -E '^(RUNNER|GAMEID|PREFIX_MODE|ARGS_OVERRIDE|NOTAS)=' "$conf" \
               2>/dev/null | head -n 5 | sed 's/^/  /')"
    ui_ask "¿Borrar la configuracion de este juego?

$gid

$resumen

El juego y sus partidas NO se tocan: solo se pierde el ajuste.
La proxima vez que lo abras, WProton preguntara de nuevo.
(se guardara como $gid.conf.bak)" || return 1
    cp -f "$conf" "$conf.bak" 2>/dev/null
    rm -f "$conf"
    # tambien el marcador de "no volver a preguntar por la comunidad"
    rm -f "$PROFILE_DIR/.$gid.nocomm" 2>/dev/null
    say "[+] Perfil borrado: $gid"
    ui_info "Configuracion de '$gid' borrada.

Si vuelves a abrir el juego, WProton la creara de nuevo."
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
            g="$(wpact_ruta "$g")" || return
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
1|vcrun2022 (VC++ 2015-2022, el más comun)
0|vcrun2013 (VC++ 2013)
0|vcrun2012 (VC++ 2012)
0|vcrun2010 (VC++ 2010)
0|vcrun2008 (VC++ 2008)
0|vcrun2005 (VC++ 2005)
0|d3dx9 (DirectX 9 - D3DX)
0|d3dx10 (DirectX 10 - D3DX)
0|d3dx11_43 (DirectX 11 - D3DX)
0|d3dcompiler_43 (compilador de shaders, juegos DX9/DX11)
0|d3dcompiler_47 (compilador de shaders, juegos modernos)
0|directx_todo (pack: D3DX 9/10/11 + los dos compiladores)
0|xna40 (XNA 4.0 - muchos indies: Terraria, Bastion...)
0|physx (NVIDIA PhysX)
0|ue4prereqs (Prerrequisitos Unreal Engine - pack)
0|xact (XACT/XAudio, juegos viejos)
0|mf (Media Foundation - videos in-game)
0|openal (sonido OpenAL)
0|dinput8 (mando/teclado en juegos viejos)
0|corefonts (fuentes de Windows - textos que no se ven)
0|msxml6 (MSXML 6 - algunos instaladores y juegos)
0|dotnet48 (.NET 4.8 - instalacion LENTA)
EOF
    PYGAME_HIDE_SUPPORT_PROMPT=1 SDL_JOYSTICK_ALLOW_BACKGROUND_EVENTS=1 \
        env -u LD_PRELOAD "$PY_BIN" "$MENU_PYGAME_PY" check "Redistribuibles para $gid (X marca, A instala)" \
        "$tmpsel" "$tmpopt" >> "$LOG_FILE" 2>&1
    local rc=$? sel; sel="$(cat "$tmpsel")"; rm -f "$tmpsel" "$tmpopt"
    [ $rc -ne 0 ] && return 1
    local verbs; verbs="$(printf '%s' "$sel" | tr '|' '\n' | awk 'NF{print $1}' | tr '\n' ' ')"
    verbs="${verbs% }"
    # "directx_todo" no es un verbo de winetricks: es un pack nuestro con todo
    # lo de DirectX que suelen pedir los juegos, comodo cuando no se sabe cual
    # falta. OJO: no confundir con DXVK, que es otra cosa (la traduccion de
    # DirectX a Vulkan) y se activa en Rendimiento y compatibilidad.
    case " $verbs " in *" directx_todo "*)
        verbs="$(printf '%s' " $verbs " | sed 's/ directx_todo / d3dx9 d3dx10 d3dx11_43 d3dcompiler_43 d3dcompiler_47 /')"
        verbs="$(printf '%s' "$verbs" | tr ' ' '\n' | awk 'NF' | awk '!seen[$0]++' | tr '\n' ' ')"
        verbs="${verbs% }"; verbs="${verbs# }" ;;
    esac
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
Revisa el último log si algo fallo."
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
            [ -z "$BUNDLED_RUNNER_DIR" ] && { say "AVISO: sin Wine incluido - runner automático"; RUNNER=""; }
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
    # Batocera (/usr/wine/..., /userdata/...). En otra máquina esos enlaces
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
        local wsrv; wsrv="$(dirname "$wbin")/wineserver"
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

    # 3) Comprobacion: si aún faltan las DLLs de Direct3D, avisar con salida
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
    # Decide si conviene el backend SDL de Proton según el mando conectado:
    #  - Sony/Nintendo (DualSense, DS4, Pro Controller...): SI, porque fuera
    #    de Steam llegan por hidraw y los juegos solo-XInput no los ven.
    #  - XInput integrados (Steam Deck, Legion Go, ROG Ally, Xbox...): NO,
    #    ya son XInput nativo y forzar SDL les estorba.
    # Imprime "valor|motivo": el motivo NO puede ir en una variable global
    # porque esta funcion se llama dentro de $( ) y ahi todo es un subshell.
    local names sony=0 xin=0
    if [ ! -r /proc/bus/input/devices ]; then
        printf '0|sin información de dispositivos'; return
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
        [ -z "$EXE_OVERRIDE" ] && { ui_error "dgVoodoo/OptiScaler necesitan un exe fijo (no automático)"; return 1; }
        write_full_profile "$gid"
    fi
    dirname "$EXE_OVERRIDE"
}

preparar_carpeta_exe() {
    # Deja el juego montado en escritura y devuelve la carpeta donde vive su
    # ejecutable: es lo que necesitan las herramientas que copian ficheros
    # dentro del juego (dgVoodoo2, OptiScaler). Estaba escrito dos veces.
    # Si falla, desmonta y devuelve 1.
    local squash="$1" gid="$2"
    load_profile "$gid"
    acquire_game_root "$squash" "$gid" rw
    local merged="$MOUNT_POINT" exedir
    exedir="$(need_exe_dir "$merged" "$gid")" || { release_game_root; return 1; }
    printf '%s/%s' "$merged" "$exedir"
    return 0
}

install_dgvoodoo() {
    local squash="$1" gid="$2" target
    target="$(preparar_carpeta_exe "$squash" "$gid")" || return 1

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
Configuralo con la opción 'Configurar dgVoodoo (Cpl)'"
}

install_optiscaler() {
    local squash="$1" gid="$2" target
    target="$(preparar_carpeta_exe "$squash" "$gid")" || return 1

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

prefijo_limpiar() {
    # Quita del prefijo lo que NO debe viajar dentro del archivo:
    #   - enlaces a las carpetas del usuario (Wine crea enlaces de Escritorio,
    #     Documentos, etc. hacia $HOME): en otro equipo apuntarian a ninguna
    #     parte, y ademas se llevarian por delante ficheros ajenos al copiar.
    #   - caches de shaders y temporales: son GIGAS que se regeneran solos.
    local dc="$1" d
    say "Limpiando el prefijo antes de empaquetar..."
    # 1) enlaces del perfil de usuario -> carpetas normales y vacias
    find "$dc/users" -maxdepth 3 -type l 2>/dev/null | while IFS= read -r d; do
        rm -f "$d" && mkdir -p "$d"
    done
    # 2) basura conocida
    for d in "$dc"/windows/Temp "$dc"/users/*/Temp \
             "$dc"/users/*/AppData/Local/Temp \
             "$dc"/users/*/AppData/Local/NVIDIA \
             "$dc"/users/*/AppData/Local/AMD \
             "$dc"/users/*/AppData/Local/D3DSCache; do
        [ -d "$d" ] && rm -rf "$d" 2>/dev/null
    done
    find "$dc" -type f \( -name '*.dxvk-cache' -o -name '*.vkd3d-cache' \
        -o -name '*.log' -o -name '*.dmp' \) -delete 2>/dev/null
    return 0
}

package_con_prefijo() {
    # Empaqueta el juego JUNTO CON su prefijo, al estilo Batocera: dentro del
    # archivo hay un drive_c/ con Windows entero y el juego dentro, mas un
    # autorun.cmd que dice que ejecutar. El resultado es autosuficiente: se
    # copia a otro equipo y funciona sin instalar dependencias.
    #
    # $1 = carpeta del juego, $2 = gid, $3 = ejecutable (ruta absoluta)
    local src="$1" gid="$2" exe="$3"
    local pfx; pfx="$(prefix_path "$gid")"
    local dc="$pfx/drive_c"

    if [ ! -d "$dc" ]; then
        ui_error "Este juego no tiene un prefijo propio todavía.

Pruébalo al menos una vez con 'Prefijo: propio del juego'
para que se cree, y vuelve a intentarlo."
        return 1
    fi
    # El prefijo COMPARTIDO no vale: lleva dentro las librerias y los datos de
    # todos los demas juegos, y el archivo saldria enorme y con cosas ajenas.
    case "$pfx" in
        *"/default"|*"/shared") 
            ui_error "Este juego usa el prefijo compartido.

Un archivo autosuficiente necesita un prefijo SOLO suyo: el
compartido lleva dentro las librerías y los datos del resto de
juegos.

Cambia el prefijo a 'propio del juego', prueba el juego una vez
y vuelve a intentarlo."
            return 1 ;;
    esac

    local tam_pfx tam_juego total
    tam_pfx="$(dir_bytes "$dc")"
    tam_juego="$(dir_bytes "$src")"
    total=$(( ${tam_pfx:-0} + ${tam_juego:-0} ))
    if ! ui_ask "Empaquetar '$gid' CON su prefijo (autosuficiente)?

Juego:    $(human_size "${tam_juego:-0}")
Prefijo:  $(human_size "${tam_pfx:-0}")
Total:    $(human_size "$total") antes de comprimir

El resultado funciona en otro equipo sin instalar nada, pero
ocupa bastante mas. El juego original NO se toca.

Si el archivo va a ser grande, el formato DwarFS comprime bastante
mas que wsquashfs (se elige en Biblioteca y preferencias)."; then
        return 1
    fi
    # hace falta sitio para la copia de trabajo Y para el archivo final
    check_space "$(( total + total * 7 / 10 ))" "$WS_DIR" \
        "empaquetar '$gid' con su prefijo" || return 1

    local tmp; tmp="$WS_DIR/build_prefijo_$$"
    rm -rf "$tmp"; mkdir -p "$tmp" || { ui_error "No se pudo crear la carpeta de trabajo"; return 1; }

    loading_say "Copiando el prefijo..."
    if ! cp -a "$dc" "$tmp/drive_c" 2>>"$LOG_FILE"; then
        rm -rf "$tmp"; ui_error "No se pudo copiar el prefijo"; return 1
    fi
    prefijo_limpiar "$tmp/drive_c"

    # ¿El juego ya vive DENTRO del prefijo? Entonces no hay que copiarlo otra
    # vez: basta con apuntar al sitio donde ya esta.
    local rel_dir="" destino abs_src abs_dc
    abs_src="$(readlink -f "$src")"
    abs_dc="$(readlink -f "$dc")"
    case "$abs_src/" in
        "$abs_dc"/*)
            # el juego ya vive dentro del prefijo: no hay que copiarlo
            rel_dir="${abs_src#"$abs_dc"/}"
            say "[+] El juego ya estaba dentro del prefijo: $rel_dir" ;;
        *)
            destino="$tmp/drive_c/Games/$gid"
            loading_say "Copiando el juego dentro de drive_c..."
            mkdir -p "$(dirname "$destino")"
            if ! cp -a "$src" "$destino" 2>>"$LOG_FILE"; then
                rm -rf "$tmp"; ui_error "No se pudo copiar el juego"; return 1
            fi
            rel_dir="Games/$gid" ;;
    esac

    # autorun.cmd en la raiz, como los wsquashfs de Batocera
    local exe_rel exe_name
    exe_name="$(basename "$exe")"
    exe_rel="$rel_dir"
    if [ -n "$exe" ]; then
        # respetar la subcarpeta del ejecutable dentro del juego
        local sub; sub="$(dirname "$(readlink -f "$exe")")"
        local base_src; base_src="$(readlink -f "$src")"
        case "$sub/" in
            "$base_src"/*) exe_rel="$rel_dir/${sub#$base_src/}" ;;
        esac
    fi
    printf 'DIR="drive_c/%s"\r\nCMD="%s"\r\n' "$exe_rel" "$exe_name" \
        > "$tmp/autorun.cmd"
    say "[+] autorun.cmd -> DIR=drive_c/$exe_rel CMD=$exe_name"

    loading_clear
    if build_wsquashfs "$tmp" "$gid"; then
        rm -rf "$tmp"
        ui_info "'$gid' empaquetado con su prefijo.

Ese archivo ya lleva dentro todo lo necesario: cópialo a otro
equipo y funcionará sin instalar nada.

El juego y el prefijo originales siguen donde estaban.
Conviene probarlo antes de borrar nada."
        return 0
    fi
    rm -rf "$tmp"
    return 1
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
            remember_browse "$dir"      # recordar donde estaba antes de borrarla
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
                # Cambiar runner/prefijo/opciones y volver aquí para reprobar
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
    ui_error "El innoextract descargado no funciona en esta máquina"
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
    # 1) assets de la última release
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
    # /VERYSILENT y /DIR, así que no hace falta teclado ni raton.
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
    # Se lee linea a linea: con "for cand in $(find ...)" una carpeta llamada
    # "Mi Juego" se partia en "Mi" y "Juego" y no se encontraba nada.
    while IFS= read -r cand; do
        [ -n "$cand" ] || continue
        exe="$(find_game_exe "$cand")"
        [ -n "$exe" ] && { GOG_ROOT_EXE="$exe"; printf '%s' "$cand"; return 0; }
    done <<EOFGOG
$(find "$d" -maxdepth 2 -type d \( -iname 'app' -o -iname '{app}' \) 2>/dev/null)
EOFGOG
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
    # Es la via más fiable porque la hace el propio instalador: funciona con
    # cualquier versión de Inno Setup y con el formato GOG Galaxy (los trozos
    # los reensambla el, no nosotros) y no necesita teclado ni raton.
    # Si el instalador ignorase el modo silencioso, se prueba a extraerlo con
    # innoextract / innounp (si estan disponibles) y, en último caso, el
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
        remember_browse "$inst"     # recordar la carpeta antes de borrarlo
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
    # un script por lotes nunca es un instalador: no preguntamos por GOG
    case "$(printf '%s' "$exe_abs" | tr 'A-Z' 'a-z')" in
        *.bat|*.cmd) ;;
        *)
            if is_inno_installer "$exe_abs" && \
               ui_ask "Parece un instalador GOG/InnoSetup:
$(basename "$exe_abs")
Instalarlo (sin intervencion) y convertirlo a wsquashfs?"; then
                import_gog_exe "$exe_abs"
                return $?
            fi ;;
    esac
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
    lanzar_script_si_existe "$dir" && return 0
    name="$(basename "$dir")"
    # OJO: aqui NO se puede usar "die", que cierra WProton entero. Esto
    # ocurre dentro de un menu: si la carpeta elegida no sirve, se avisa y se
    # vuelve al menu, como cualquier otro error recuperable.
    if ! exe="$(resolver_exe_carpeta "$dir")" || [ -z "$exe" ]; then
        ui_error "No se encontro ningun ejecutable en esa carpeta.

$dir

Elige la carpeta que contiene el .exe del juego, o importa
directamente el ejecutable."
        return 1
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
    # datos comprimidos (texturas, audio, video), así que el factor real
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
        # la carpeta de donde vino el comprimido se recuerda ANTES de
        # borrarlo: si no, al purgarlo se perdia el sitio al que volver
        remember_browse "$input"
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
    local -a PRE=()
    while IFS= read -r _a; do [ -n "$_a" ] && PRE+=("$_a"); done <<EOFRB
$(run_args_for "$exe")
EOFRB
    # shellcheck disable=SC2086
    ( cd "$(dirname "$exe")" && "${RUN_CMD[@]}" "${PRE[@]}" $loose_args >> "$LOG_FILE" 2>&1 )
    local rc=$?
    kill "$trig" 2>/dev/null
    mapeador_stop
    stats_record "$gid" "$(( $(date +%s) - st0 ))"
    saves_detect_end "$gid"
    post_game_resettle
    return $rc
}

lanzar_script_si_existe() {
    # Si la carpeta trae su propio lanzador .sh, se usa ese y no se busca mas.
    # Estaba escrito dos veces (jugar / importar una carpeta).
    local dir="$1" launcher
    launcher="$(find "$dir" -maxdepth 1 -type f -name '*.sh' 2>/dev/null | head -n1)"
    [ -n "$launcher" ] || return 1
    say "Lanzando script del juego: $launcher"
    pad_bridge_stop
    bash "$launcher"
    return 0
}

resolver_exe_carpeta() {
    # Ejecutable de una carpeta de juego, en un solo sitio.
    #
    # Estaba escrito dos veces (jugar una carpeta / importarla) y por eso el
    # arreglo del autorun.cmd hubo que hacerlo por duplicado. El orden es:
    #   1) heuristica            2) autorun.cmd     3) preguntar al usuario
    local dir="$1"
    local e; e="$(find_game_exe "$dir")"
    if [ -n "$e" ]; then
        printf '%s' "$e"
        return 0
    fi
    # modo automatico: respeta el autorun.cmd (las .pc de Batocera lo llevan)
    if find_exe "$dir" "auto" || find_exe "$dir" "manual"; then
        printf '%s' "$EXE_PATH"
        return 0
    fi
    return 1
}

play_folder() {
    # Jugar una carpeta suelta SIN empaquetar ni preguntas de compresion
    local dir="$1" launcher exe name
    lanzar_script_si_existe "$dir" && return 0
    name="$(game_id "$dir")"
    load_profile "$name"
    if [ -n "$EXE_OVERRIDE" ] && [ -f "$dir/$EXE_OVERRIDE" ]; then
        exe="$dir/$EXE_OVERRIDE"
    else
        if ! exe="$(resolver_exe_carpeta "$dir")" || [ -z "$exe" ]; then
            ui_error "No se encontro ningun ejecutable en esa carpeta.

$dir

Elige la carpeta que contiene el .exe del juego."
            return 1
        fi
    fi
    launch_loose_exe "$name" "$exe"
}

play_or_config() {
    # $1 = lo devuelto por pick_squash: jugar, o abrir su configuración si el
    # usuario pulso X sobre el juego resaltado.
    case "$1" in
        "WPACT:CONFIG|"*)
            local g="${1#WPACT:CONFIG|}"
            [ -e "$g" ] || { ui_error "No existe: $g"; return 1; }
            game_config_menu "$g" ;;
        "WPACT:INFO|"*)
            # L1: ficha del juego, sin pasar por el menu de configuracion
            local gi="${1#WPACT:INFO|}"
            [ -e "$gi" ] || { ui_error "No existe: $gi"; return 1; }
            ficha_mostrar "$(game_id "$gi")" "$gi" ;;
        "WPACT:FAV|"*)
            # R1: marcar o quitar favorito al vuelo
            local gf="${1#WPACT:FAV|}" gidf
            [ -e "$gf" ] || { ui_error "No existe: $gf"; return 1; }
            gidf="$(game_id "$gf")"
            load_profile "$gidf"
            FAVORITO=$((1-${FAVORITO:-0}))
            write_full_profile "$gidf"
            say "[+] $gidf: favorito $([ "$FAVORITO" = 1 ] && printf 'SI' || printf 'no')" ;;
        *) play_any "$1" ;;
    esac
}

wpact_ruta() {
    # Quita el marcador de accion y devuelve la ruta. Si el usuario pulso L1
    # (ficha) o R1 (favorito) en un sitio donde solo se esperaba elegir un
    # juego, se atiende esa accion y se devuelve 1 para no seguir adelante.
    local v="$1"
    case "$v" in
        "WPACT:CONFIG|"*) printf '%s' "${v#WPACT:CONFIG|}" ;;
        "WPACT:INFO|"*|"WPACT:FAV|"*)
            play_or_config "$v" >&2
            return 1 ;;
        *) printf '%s' "$v" ;;
    esac
    return 0
}

play_any() {
    # Despachador de "jugar": wsquashfs -> montar | exe -> directo | carpeta -> directo
    local p="$1"
    case "$p" in
        *.wsquashfs|*.squashfs|*.dwarfs|*.WSQUASHFS|*.SQUASHFS|*.DWARFS)
            launch_game "$p" "auto" ;;
        *.exe|*.EXE|*.bat|*.BAT|*.cmd|*.CMD)
            [ -f "$p" ] || { ui_error "Ya no existe:\n$p"; return 1; }
            local nm; nm="$(game_id "$(dirname "$p")")"
            launch_loose_exe "$nm" "$(realpath "$p")" ;;
        *)
            if [ -d "$p" ]; then
                play_folder "$p"
            elif [ -f "$p" ]; then
                launch_game "$p" "auto"
            else
                ui_error "Ya no existe:\n$p"; return 1
            fi ;;
    esac
}

diag_mando_antes() {
    # Todo lo que hace falta para diagnosticar un problema de mando, ANTES de
    # lanzar. Sin esto habia que adivinar: el registro decia que se exportaban
    # las variables, pero no si el juego las recibia ni si veia el mando.
    say "--- diagnostico de mando -------------------------------------"
    # 1) Que variables de mando van a llegar al juego
    local v vistas=0
    for v in PROTON_USE_SDL PROTON_PREFER_SDL PROTON_DISABLE_HIDRAW \
             PROTON_SONY_HIDRAW_XINPUT PROTON_SONY_DUALSENSE_AS_DUALSHOCK4 \
             PROTON_STEAMINPUT_XINPUT_FALLBACK PROTON_ENABLE_HIDRAW \
             SDL_GAMECONTROLLER_IGNORE_DEVICES SDL_GAMECONTROLLER_IGNORE_DEVICES_EXCEPT \
             SDL_JOYSTICK_HIDAPI_IGNORE_DEVICES SDL_JOYSTICK_HIDAPI_PS5 \
             SDL_VIDEODRIVER ENABLE_GAMESCOPE_WSI; do
        if [ -n "$(eval printf '%s' "\${$v:-}")" ]; then
            say "    $v=$(eval printf '%s' "\${$v}")"
            vistas=$((vistas+1))
        fi
    done
    [ "$vistas" = 0 ] && say "    (ninguna variable de mando puesta)"
    # 2) Identificador y prefijo, que deciden que arreglos se aplican
    say "    GAMEID=${GAMEID:-umu-default}   STORE=${STORE:-none}"
    say "    prefijo=$WINEPREFIX"
    # 3) Los dispositivos, con su ruta: si el juego coge el equivocado (los
    #    sensores de movimiento del DualSense, por ejemplo) no responde nada
    local d nombre ev js
    for d in /sys/class/input/event*/device; do
        [ -r "$d/name" ] || continue
        nombre="$(cat "$d/name" 2>/dev/null)"
        case "$nombre" in
            *ontroller*|*amepad*|*oystick*|*DualSense*|*Xbox*|*X-Box*)
                ev="/dev/input/$(basename "$(dirname "$d")")"
                js="$(ls "$(dirname "$d")/../js"* 2>/dev/null | head -n1)"
                say "    $ev  [$( [ -r "$ev" ] && printf 'legible' || printf 'SIN PERMISO')]  $nombre" ;;
        esac
    done
    # 4) ¿Steam esta ocultando el mando fisico?
    if [ -n "${SDL_GAMECONTROLLER_IGNORE_DEVICES:-}" ] || \
       [ -n "${SDL_JOYSTICK_HIDAPI_IGNORE_DEVICES:-}" ]; then
        say "    [!] Steam esta ocultando mandos por SDL_*_IGNORE_DEVICES"
    fi
    # 5) hidraw: los modos Sony trabajan sobre estos nodos
    local h n_h=0
    for h in /dev/hidraw*; do
        [ -e "$h" ] || continue
        n_h=$((n_h+1))
        [ -r "$h" ] || say "    [!] $h sin permiso de lectura (el juego tampoco podra)"
    done
    say "    nodos hidraw: $n_h"
    # 6) ¿Alguien MAS tiene abierto el mando ahora mismo?
    #
    # Es la diferencia entre lanzar por linea de ordenes y por los menus: el
    # proceso de menus lee /dev/input directamente y, si sigue vivo, compite
    # con el juego por el mismo dispositivo.
    if command -v fuser >/dev/null 2>&1; then
        local dev otros
        for dev in /dev/input/event*; do
            [ -e "$dev" ] || continue
            otros="$(fuser "$dev" 2>/dev/null | tr -s ' ')"
            [ -n "$otros" ] || continue
            local p nombre lista=""
            for p in $otros; do
                [ "$p" = "$$" ] && continue
                nombre="$(ps -o comm= -p "$p" 2>/dev/null)"
                [ -n "$nombre" ] && lista="$lista $nombre($p)"
            done
            [ -n "$lista" ] && say "    [!] $dev lo tienen abierto:$lista"
        done
    else
        say "    (sin 'fuser': no se puede ver quien tiene abierto el mando)"
    fi
    # y si nuestros propios procesos siguen vivos
    local nuestro
    for nuestro in menu_pygame.py mapeador.py pad_bridge; do
        if pgrep -f "$nuestro" >/dev/null 2>&1; then
            say "    [!] sigue vivo un proceso nuestro: $nuestro"
        fi
    done
    say "-------------------------------------------------------------"
    return 0
}

diag_mando_despues() {
    # Que ha recibido DE VERDAD el proceso del juego. Es lo unico que
    # confirma si nuestras variables llegaron; lo anterior es lo que
    # CREEMOS haber puesto.
    local pid="$1" ent
    [ -n "$pid" ] || return 0
    ent="/proc/$pid/environ"
    [ -r "$ent" ] || { log "No se pudo leer el entorno del juego (pid $pid)"; return 0; }
    say "--- lo que recibio el juego (pid $pid) ----------------------"
    tr '\0' '\n' < "$ent" 2>/dev/null \
        | grep -E '^(PROTON_|SDL_|WINE|STEAM|ENABLE_GAMESCOPE)' \
        | sort | while IFS= read -r linea; do say "    $linea"; done
    say "-------------------------------------------------------------"
    return 0
}

log_input_devices() {
    # Deja en el log que mandos ve el sistema justo antes de lanzar
    local name handlers n=0
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

MOUNT_ERROR=""    # motivo del ultimo fallo al montar un disco
CANVAS_PID=""
CANVAS_FILE=""
# OJO: el pid NO puede vivir solo en una variable. El servidor se relanza
# dentro de post_game_resettle, que a veces corre en un subshell, y alli las
# asignaciones no vuelven al proceso padre: al salir, WProton creia que no
# habia servidor, no lo paraba, y el proceso se quedaba vivo con su ventana
# en pantalla (parecia que el programa no se cerraba).
MENUSRV_PID=""

# Las rutas se CALCULAN siempre desde RUNTIME_DIR, nunca se guardan en una
# variable: si se asignan dentro de un subshell (el servidor se relanza tras
# cada juego) el proceso padre no se entera y luego no sabe a quien parar.
# Lanzar en segundo plano SIN quedarse con el terminal: si un hijo lo
# conserva, la ventana de Konsole no se cierra al terminar WProton.
lanzar_suelto() {
    if command -v setsid >/dev/null 2>&1; then
        setsid "$@" < /dev/null >> "$LOG_FILE" 2>&1 &
    else
        "$@" < /dev/null >> "$LOG_FILE" 2>&1 &
    fi
    printf '%s' "$!"
}

menusrv_dir()     { printf '%s' "$RUNTIME_DIR/.menusrv"; }
menusrv_pidfile() { printf '%s' "$RUNTIME_DIR/.menusrv.pid"; }
menusrv_pid()     { cat "$(menusrv_pidfile)" 2>/dev/null; }

GUARDIA_PID=""

keys_ejemplo_crear() {
    # Deja un .keys de ejemplo con las combinaciones utiles, para quien quiera
    # usarlas. NO se aplica solo: para que funcione hay que ponerlo junto a un
    # juego (<juego>.wsquashfs.keys) o copiarlo como perfil del juego.
    #
    # No se activa de serie porque el mapeador crea un teclado virtual durante
    # la partida y algunos juegos se confunden al ver un dispositivo nuevo.
    local f="$RUNTIME_DIR/ejemplo.keys"
    mkdir -p "$RUNTIME_DIR" 2>/dev/null
    cat > "$f" <<'EOFKEYS'
{
  "_comentario": "Ejemplo de WProton. Copialo junto a un juego como <juego>.wsquashfs.keys",
  "_aviso": "Solo COMBINACIONES: si mapeas botones sueltos, el juego recibira la pulsacion del mando Y la tecla.",
  "actions_player1": [
    { "trigger": ["hotkey", "y"],  "target": ["KEY_LEFTALT", "KEY_TAB"] },
    { "trigger": ["l3", "r3"],     "target": ["KEY_LEFTALT", "KEY_F4"] }
  ]
}
EOFKEYS
    printf '%s' "$f"
    return 0
}

guardia_salida_start() {
    # Vigila la combinacion de salida durante la partida, para poder cerrar
    # el juego solo
    # con el mando. Hace falta en el escritorio: en el modo Juego se sale con
    # el boton de Steam, pero fuera de ahi un juego sin opcion de salir deja
    # atrapado a quien no tenga el teclado a mano.
    [ "${PAD_EXIT:-1}" = 1 ] || return 0
    pygame_available || return 0
    write_menu_pygame
    local marca="$RUNTIME_DIR/.salir_juego"
    rm -f "$marca" 2>/dev/null
    export WP_OCULTAR_CURSOR="${OCULTAR_CURSOR:-1}"
    GUARDIA_PID="$(lanzar_suelto "$PY_BIN" "$MENU_PYGAME_PY" guardia \
                   "$marca" "${PAD_EXIT_SEGUNDOS:-5}" "${PAD_EXIT_COMBO:-select}")"
    sleep 0.4
    if [ -z "$GUARDIA_PID" ] || ! kill -0 "$GUARDIA_PID" 2>/dev/null; then
        say "AVISO: el vigilante de salida no arranco (mira el registro)"
        GUARDIA_PID=""
    else
        # Y comprobarlo otra vez mas adelante: si se cae a los pocos segundos
        # (por ejemplo al tocar las X para el cursor), antes no nos
        # enterabamos y parecia que la combinacion de salida no servia.
        ( sleep 20
          kill -0 "$GUARDIA_PID" 2>/dev/null \
            || say "AVISO: el vigilante de salida SE CERRO; el cierre con el mando no funcionara"
        ) < /dev/null >/dev/null 2>&1 &
    fi
    # Vigilante en bash: cuando aparezca la marca, cerrar el juego
    local titulo; titulo="$(basename "${EXE_PATH:-juego}" .exe)"
    ( orden=""
      while :; do
          if [ -f "$marca" ]; then
              orden="$(cat "$marca" 2>/dev/null)"
              rm -f "$marca" 2>/dev/null
              case "$orden" in
                  salir)
                      say "[+] Cerrando el juego a peticion del usuario"
                      pkill -f "wineserver" 2>/dev/null
                      [ -n "${MOUNT_BASE:-}" ] && pkill -f "$MOUNT_BASE/" 2>/dev/null
                      break ;;
              esac
          fi
          sleep 0.4
      done
    ) < /dev/null >/dev/null 2>&1 &
    case "${PAD_EXIT_COMBO:-select}" in
        l3r3)  say "[i] Con el mando: manten L3+R3 para cerrar el juego" ;;
        start) say "[i] Con el mando: manten Select+Start para cerrar el juego" ;;
        *)     say "[i] Con el mando: manten SELECT ${PAD_EXIT_SEGUNDOS:-5}s para cerrar el juego" ;;
    esac
    return 0
}

guardia_salida_stop() {
    [ -n "${GUARDIA_PID:-}" ] && kill "$GUARDIA_PID" 2>/dev/null
    GUARDIA_PID=""
    rm -f "$RUNTIME_DIR/.salir_juego" 2>/dev/null
    return 0
}

menu_server_reiniciar() {
    # El proceso de menus lee el tema, el idioma, el tamaño de letra y las
    # columnas de la rejilla UNA VEZ, al arrancar. Como desde la 1.02 ese
    # proceso es persistente, cambiar cualquiera de esas cosas no se notaba
    # hasta cerrar y volver a abrir WProton. Aqui se reinicia para que el
    # cambio se vea al momento.
    export WP_THEME="${THEME:-moderno}"
    export WP_GRID_COLS="${GRID_COLS:-0}"
    export WP_LANG="${LANGUAGE:-es}"
    export WP_FONT_SCALE="${FONT_SCALE:-1.0}"
    menu_server_alive || return 0          # si no habia servidor, nada que hacer
    menu_server_stop
    menu_server_start || true
    return 0
}

menu_server_start() {
    # Arranca el proceso de menus persistente: UNA ventana para toda la
    # sesion. Sin esto, cada menu abria y cerraba la suya (parpadeo entre
    # menus, y en el modo Juego el compositor se quedaba sin ventana a la
    # que volver al salir de un juego).
    [ "${MENU_SERVER:-1}" = 1 ] || return 1
    [ -n "$MENUSRV_PID" ] && kill -0 "$MENUSRV_PID" 2>/dev/null && return 0
    pygame_available || return 1
    write_menu_pygame
    local dir; dir="$(menusrv_dir)"
    rm -rf "$dir"; mkdir -p "$dir"
    MENUSRV_PID="$(PYGAME_HIDE_SUPPORT_PROMPT=1 SDL_JOYSTICK_ALLOW_BACKGROUND_EVENTS=1 \
        lanzar_suelto env -u LD_PRELOAD "$PY_BIN" "$MENU_PYGAME_PY" server "$dir")"
    disown "$MENUSRV_PID" 2>/dev/null || true
    printf '%s' "$MENUSRV_PID" > "$(menusrv_pidfile)" 2>/dev/null
    # Esperar a que este vivo Y respondiendo: que el proceso exista no basta,
    # puede caerse al dibujar la primera pantalla.
    local i
    for i in 1 2 3 4 5 6 7 8 9 10; do
        sleep 0.2
        kill -0 "$MENUSRV_PID" 2>/dev/null || break
    done
    if kill -0 "$MENUSRV_PID" 2>/dev/null; then
        say "[+] Servidor de menus activo (pid $MENUSRV_PID)"
        return 0
    fi
    say "AVISO: el servidor de menus no arranco; un proceso por menu"
    say "    (el motivo esta unas lineas mas arriba en este registro)"
    MENUSRV_PID=""
    rm -f "$(menusrv_pidfile)" 2>/dev/null
    return 1
}

menu_server_alive() {
    local p; p="$(menusrv_pid)"
    [ -n "$p" ] && kill -0 "$p" 2>/dev/null
}

menu_server_stop() {
    local p dir
    p="$(menusrv_pid)"
    dir="$(menusrv_dir)"
    if [ -n "$p" ] && kill -0 "$p" 2>/dev/null; then
        : > "$dir/stop" 2>/dev/null      # salida ordenada
        local i
        for i in 1 2 3 4 5 6; do
            kill -0 "$p" 2>/dev/null || break
            sleep 0.2
        done
        # si sigue vivo, por las buenas y luego por las malas: al salir de
        # WProton no puede quedarse un proceso con una ventana en pantalla
        kill "$p" 2>/dev/null
        for i in 1 2 3; do
            kill -0 "$p" 2>/dev/null || break
            sleep 0.2
        done
        kill -9 "$p" 2>/dev/null
    fi
    rm -rf "$dir" 2>/dev/null
    rm -f "$(menusrv_pidfile)" 2>/dev/null
    MENUSRV_PID=""
    return 0
}

loading_clear() {
    # Borra el mensaje de espera cuando la tarea ha terminado. Sin esto, el
    # ultimo texto ("Descargando...", "Configurando...") se quedaba fijo en
    # pantalla como si algo siguiera en marcha.
    menu_server_say ""
    canvas_say ""
    return 0
}

loading_say() {
    # Mensaje de "cargando" mientras se monta y prepara el juego. Va a la
    # ventana que haya viva (el proceso de menus o el fondo) y al registro:
    # antes esos segundos eran una pantalla muda y parecia que no pasaba nada.
    menu_server_say "$1"
    canvas_say "$1"
    say "$1"
    return 0
}


menu_server_say() {
    # Texto de la pantalla de reposo (lo que se ve mientras no hay menu)
    menu_server_alive || return 0
    printf 'idle\n%s\n\n\n\n\n' "$1" > "$(menusrv_dir)/req" 2>/dev/null
    : > "$(menusrv_dir)/req.ready" 2>/dev/null
    return 0
}

menusrv_escapa() {
    # El protocolo es UNA LINEA POR CAMPO, pero los titulos suelen tener
    # varias lineas ("Hay una version nueva...\nDescargar ahora?"). Sin
    # escapar, ese salto corria todos los campos: el helper tomaba el texto
    # del dialogo como nombre del fichero de salida y lo creaba en la carpeta
    # de WProton. Aqui los saltos se convierten en \n literal.
    printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e ':a' -e 'N' -e '$!ba' -e 's/\n/\\n/g'
}

menu_server_request() {
    # $1=modo $2=titulo $3=salida $4=arg4 $5=tipo $6=accion_x $7=manifiesto
    # $8=preseleccion (juego sobre el que abrir la lista)
    # $10=proporcion de la caratula (vertical | wide | 43)
    # Manda la peticion al servidor y espera su respuesta. Devuelve el codigo
    # de la sesion, o 9 si el servidor se ha caido (para que el llamador use
    # el camino de siempre, un proceso por menu).
    menu_server_alive || return 9
    rm -f "$(menusrv_dir)/resp" 2>/dev/null
    printf '%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n' \
        "$(menusrv_escapa "$1")" "$(menusrv_escapa "$2")" "$(menusrv_escapa "$3")" \
        "$(menusrv_escapa "${4:-}")" "$(menusrv_escapa "${5:-}")" "${6:-}" \
        "$(menusrv_escapa "${7:-}")" "$(menusrv_escapa "${8:-}")" \
        "$(menusrv_escapa "${9:-}")" "${10:-}" \
        > "$(menusrv_dir)/req"
    : > "$(menusrv_dir)/req.ready"
    local i=0
    while [ ! -f "$(menusrv_dir)/resp" ]; do
        if ! menu_server_alive; then
            say "AVISO: el servidor de menus se cerro; se abrira un menu suelto"
            MENUSRV_PID=""
            rm -f "$(menusrv_pidfile)" 2>/dev/null
            return 9
        fi
        sleep 0.1
        i=$((i+1))
        [ "$i" -gt 36000 ] && return 9      # una hora: algo va muy mal
    done
    local rc; rc="$(cat "$(menusrv_dir)/resp" 2>/dev/null)"
    rm -f "$(menusrv_dir)/resp"
    return "${rc:-1}"
}

canvas_start() {
    # El servidor de menus ya mantiene una ventana viva y ademas dibuja su
    # propio reposo: un fondo aparte seria una SEGUNDA ventana peleandose por
    # el foco (y recreandose sin parar). Con servidor, aqui no hay nada que hacer.
    menu_server_alive && return 0
    [ "${GAME_MODE_CANVAS:-1}" = 1 ] || return 0
    # Hace falta fondo siempre que los menus ocupen TODA la pantalla: en modo
    # Juego, en Batocera, y tambien cuando el usuario activa la pantalla
    # completa a mano con Select+A (queda anotado en .menu_fullscreen).
    # los menus van a pantalla completa salvo que el usuario haya pedido
    # ventana (marcador .menu_windowed)
    [ -f "$RUNTIME_DIR/.menu_windowed" ] && return 0
    [ -n "$CANVAS_PID" ] && kill -0 "$CANVAS_PID" 2>/dev/null && return 0
    pygame_available || return 0
    write_menu_pygame
    CANVAS_FILE="$RUNTIME_DIR/.canvas_status"
    printf 'Cargando...
' > "$CANVAS_FILE"
    PYGAME_HIDE_SUPPORT_PROMPT=1 SDL_JOYSTICK_ALLOW_BACKGROUND_EVENTS=1 WP_MENU_FS=1 \
        env -u LD_PRELOAD "$PY_BIN" "$MENU_PYGAME_PY" canvas "WProton" \
        "$CANVAS_FILE" < /dev/null >> "$LOG_FILE" 2>&1 &
    CANVAS_PID=$!
    sleep 0.6
    if kill -0 "$CANVAS_PID" 2>/dev/null; then
        say "[+] Fondo entre menus activo (pid $CANVAS_PID)"
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

juego_sigue_vivo() {
    # ¿Queda algo DEL JUEGO corriendo?
    #
    # CUIDADO con lo que se cuenta como "el juego". Nuestras propias
    # herramientas (squashfuse, fuse-overlayfs, el mapeador) llevan la ruta
    # del montaje en su linea de ordenes, y no mueren hasta que WProton
    # desmonta... lo que ocurre DESPUES de esta espera. Si se cuentan, la
    # espera no termina jamas y WProton se queda colgado sin volver al menu.
    local p linea
    pgrep -x wineserver >/dev/null 2>&1 && return 0
    while IFS= read -r linea; do
        [ -n "$linea" ] || continue
        p="${linea%% *}"
        [ "$p" = "$$" ] && continue
        [ "$p" = "$PPID" ] && continue
        case "$linea" in
            *squashfuse*|*fuse-overlayfs*|*dwarfs*|*mapeador.py*|\
            *menu_pygame.py*|*pad_bridge*|*wproton.sh*|*pgrep*) continue ;;
        esac
        return 0
    done <<EOFVIVO
$(pgrep -af "wine64-preloader|wine-preloader|${MOUNT_BASE:-/nunca_jamas}/" 2>/dev/null)
EOFVIVO
    return 1
}

post_game_resettle() {
    # Por si el juego duro menos que el cierre diferido de la pantalla de
    # carga: se para lo que quede pendiente antes de levantar el servidor
    # nuevo, o el diferido mataria justo al recien nacido.
    menu_server_stop
    # Puesta a punto tras salir de un juego. El orden importa:
    #   1) esperar a que el juego muera del todo
    #   2) esperar a que el servidor grafico se estabilice (gamescope RECREA
    #      su XWayland al cerrarse el juego, y hasta cambia la resolucion)
    #   3) solo entonces reabrir el fondo y los menus
    # Abrir antes de tiempo era lo que provocaba "XIO: fatal IO error".
    # Esperar a que el juego termine DE VERDAD.
    #
    # Muchos juegos de Windows arrancan un proceso que enseguida cede el
    # control a otro: el que WProton lanzo ya ha terminado, pero el juego
    # sigue en pantalla. Antes se esperaban solo 5 segundos y luego se seguia
    # adelante igualmente, asi que WProton reabria su ventana A PANTALLA
    # COMPLETA encima del juego y este parecia "esconderse detras".
    #
    # Ahora se espera mientras siga habiendo algo vivo, con un tope alto por
    # si algun proceso se queda colgado y no muere nunca.
    # A los 20 segundos se avisa y se ofrece salida: si un juego deja algo
    # colgado, esperar en silencio hasta 10 minutos parece que WProton se ha
    # quedado bloqueado y el usuario no tiene forma de intervenir.
    local i sin_juego=0 avisado=0
    for i in $(seq 1 1200); do            # tope: 10 minutos
        if juego_sigue_vivo; then
            sin_juego=0
        else
            # dos comprobaciones seguidas sin nada: ahora si ha terminado
            sin_juego=$((sin_juego + 1))
            [ "$sin_juego" -ge 2 ] && break
        fi
        if [ "$i" = 40 ] && [ "$avisado" = 0 ]; then
            avisado=1
            menu_server_start >/dev/null 2>&1 || true
            if ui_ask "El juego está tardando en cerrarse del todo.

Puede que se haya quedado algún proceso suyo colgado.

¿Forzar el cierre y volver al menú?"; then
                say "[+] Cierre forzado del juego a peticion del usuario"
                kill_all silencioso
                break
            fi
        fi
        sleep 0.5
    done
    [ "$i" -ge 1200 ] && log "El juego no soltaba sus procesos; se continua igualmente" WARN

    if [ "${IS_GAMESCOPE:-0}" = 1 ]; then
        # el XWayland puede volver con OTRO numero: buscar uno vivo
        local _d _sock
        if [ -n "${DISPLAY:-}" ] && [ ! -S "/tmp/.X11-unix/X${DISPLAY#:}" ]; then
            for _sock in /tmp/.X11-unix/X*; do
                [ -S "$_sock" ] || continue
                _d=":${_sock##*/X}"
                export DISPLAY="$_d"
                say "[+] XWayland cambio de numero: ahora DISPLAY=$_d"
                break
            done
        fi
        say "[+] Sesión gamescope: esperando a que la pantalla se estabilice..."
        local _i _prev="" _cur
        for _i in 1 2 3 4 5 6 7 8 9 10 11 12; do
            sleep 0.5
            _cur="$(xdpyinfo 2>/dev/null | awk '/dimensions:/{print $2; exit}')"
            [ -z "$_cur" ] && continue
            if [ "$_cur" = "$_prev" ]; then
                say "[+] Pantalla estable en $_cur"
                break
            fi
            _prev="$_cur"
        done
        export SDL_VIDEO_MINIMIZE_ON_FOCUS_LOSS=0
        export WP_MENU_FS=1
        # NUNCA matar procesos de gamescope aqui. En el modo Juego de SteamOS
        # la propia sesion ES un gamescope ("gamescope ... -- steam -gamepadui"),
        # asi que un pkill por patron se cargaba la sesion entera: eso era el
        # "reinicio de la consola" que se veia al salir de un juego.
        # Si alguna vez lanzamos un gamescope anidado, se cierra solo con el
        # juego, porque es su proceso padre.
        sleep 0.5
    else
        sleep 0.3
    fi

    # ahora que la pantalla esta estable, la ventana puede volver
    CANVAS_PID=""
    menu_server_start || canvas_start
    menu_server_say "Volviendo al menú..."
    canvas_say "Volviendo al menú..."
    return 0
}

# ----------------------------------------------------------------------------
# 4f. COPIAS DE SEGURIDAD DE PARTIDAS GUARDADAS
#     Las partidas pueden estar en tres sitios según el juego:
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
                *"/dxvk/"*|*"/DXVK/"*|*"/vkd3d/"*|*"/VKD3D/"*|*"/dxvk-cache/"*|\
                *"/mesa_shader_cache"*|*"/radv_builtin_shaders"*|\
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
    # Los perfiles guardados antes de esta version pueden traer carpetas de
    # cache que se colaron. Se descartan al usarlos, sin tener que borrar el
    # perfil ni volver a jugar.
    saves_es_cache() {
        case "$(printf '%s' "$1" | tr 'A-Z' 'a-z')" in
            */dxvk|*/vkd3d|*/dxvk-cache|*/d3dscache|*/shadercache|*/gpucache|\
            */nvidia|*/amd|*/temp|*/crashpad|*/mesa_shader_cache) return 0 ;;
        esac
        return 1
    }
    # 1) lo aprendido observando la partida (SAVE_PATHS del perfil)
    # 2) si no hay nada, carpetas cuyo nombre se parezca al del juego
    # 3) el overlay del wsquashfs, que siempre es del juego
    local gid="$1" p root up base
    if [ -n "${SAVE_PATHS:-}" ]; then
        while IFS= read -r p; do
            [ -n "$p" ] || continue
            [ -d "$p" ] || continue
            if saves_es_cache "$p"; then
                log "Copia: se omite $p (es cache de shaders, se regenera sola)"
                continue
            fi
            printf '%s|%s\n' "${p##*/}" "$p"
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

# Lo que NUNCA es una partida guardada: caches de shaders, temporales y, en
# los juegos con prefijo incluido, todo el Windows del prefijo. Sin esto, la
# copia de un juego con prefijo propio se llevaba GIGAS y tardaba una eternidad.
BACKUP_EXCLUDES='--exclude=./drive_c/windows --exclude=./drive_c/Program Files/Common Files
--exclude=*/dosdevices --exclude=*.dxvk-cache --exclude=*.dxvk-cache-tmp
--exclude=*.vkd3d-cache --exclude=*.nvcache --exclude=*.shadercache
--exclude=*/DXVK_state_cache --exclude=*/GLCache --exclude=*/ShaderCache
--exclude=*/shadercache --exclude=*/D3DSCache --exclude=*/NVIDIA --exclude=*/AMD
--exclude=*/Temp --exclude=*/Crashpad --exclude=*.log --exclude=*.tmp --exclude=*.dmp'

backup_size_of() {
    # Tamaño real de lo que se va a copiar (ya descontando lo excluido)
    local locs="$1" total=0 label path sz
    while IFS='|' read -r label path; do
        [ -n "$path" ] || continue
        sz="$(du -sb --exclude='*cache*' --exclude='*Cache*' --exclude='*/windows' \
              --exclude='*.log' "$path" 2>/dev/null | awk '{print $1}')"
        total=$(( total + ${sz:-0} ))
    done <<EOFSZ
$locs
EOFSZ
    printf '%s' "$total"
}

backup_create() {
    # $1 = gid. Crea backups/<gid>_YYYYmmdd_HHMM.zip con las partidas.
    local gid="$1" locs n zip tmp label path bytes
    locs="$(save_locations "$gid")"
    if [ -z "$locs" ]; then
        ui_info "No se han encontrado partidas guardadas de '$gid'.
Se busca en el overlay del juego y en AppData/Documents del prefijo."
        return 1
    fi
    bytes="$(backup_size_of "$locs")"
    say "[backup] a copiar: $(human_size "${bytes:-0}")"
    # Aviso si la copia es enorme: con prefijo incluido, el overlay puede
    # tener el juego entero y la compresion tardaria muchisimo.
    if [ "${bytes:-0}" -gt 2147483648 ]; then
        ui_ask "Este juego tiene $(human_size "$bytes") de datos guardados.

Suele pasar con los juegos que llevan su propio prefijo: en la carpeta
de escritura esta tambien parte del juego, no solo las partidas.

La copia puede tardar bastantes minutos. Continuar?" || return 1
    fi
    if ! command -v zip >/dev/null 2>&1; then
        ui_error "Falta el comando 'zip', necesario para las copias."
        return 1
    fi
    mkdir -p "$BACKUP_DIR"
    zip="$BACKUP_DIR/${gid}_$(date '+%Y%m%d_%H%M').zip"
    tmp="$(mktemp -d)"
    n=0
    progress_start "Copia de seguridad de $gid"
    progress_set 0 "Reuniendo las partidas..."
    while IFS='|' read -r label path; do
        [ -n "$path" ] || continue
        mkdir -p "$tmp/$label"
        progress_set 0 "Copiando: $label"
        # tar con exclusiones: evita arrastrar caches y el Windows del prefijo
        # shellcheck disable=SC2086
        if ( cd "$path" && tar $BACKUP_EXCLUDES -cf - . ) 2>>"$LOG_FILE" \
             | ( cd "$tmp/$label" && tar -xf - ) 2>>"$LOG_FILE"; then
            n=$((n+1))
            say "[backup] $label: $path"
        fi
    done <<EOFLOC
$locs
EOFLOC
    if [ "$n" -eq 0 ]; then
        progress_stop; rm -rf "$tmp"
        ui_error "No se pudo copiar ninguna carpeta"; return 1
    fi
    {
        printf 'juego=%s\nfecha=%s\nprefijo=%s\n' "$gid" "$(date '+%Y-%m-%d %H:%M')" "$(prefix_path "$gid")"
        printf '%s\n' "$locs"
    } > "$tmp/wproton_backup.txt"
    progress_set 0 "Comprimiendo $(human_size "$(dir_bytes "$tmp")")..."
    # -1 = compresion rapida: las partidas comprimen poco y lo que importa
    # aqui es no tener al usuario esperando media hora
    if ( cd "$tmp" && zip -1 -qr "$zip" . ) >>"$LOG_FILE" 2>&1; then
        progress_stop
        rm -rf "$tmp"
        ui_info "Copia creada:

$(basename "$zip")   ($(human_size "$(dir_bytes "$zip")"))
Carpetas guardadas: $n"
        return 0
    fi
    progress_stop
    rm -rf "$tmp" "$zip"
    ui_error "Fallo creando el zip de la copia"
    return 1
}

backup_restore() {
    # $1 = gid. Elige un zip de backups/ y devuelve las carpetas a su sitio.
    local gid="$1" list sel zip tmp label path
    list="$(find "$BACKUP_DIR" -maxdepth 1 -name "${gid}_*.zip" -printf '%f\n' 2>/dev/null | sort -r)"
    [ -z "$list" ] && { ui_info "No hay copias de '$gid' en backups/"; return 1; }
    # shellcheck disable=SC2046
    sel="$(IFS=$'\n'; set -f; menu "Copias de $gid (la más reciente arriba)" $list "<< Cancelar")" || return 1
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
    # Sincroniza backups/ con otra máquina o carpeta usando herramientas
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
                    ui_error "rsync fallo. Últimas lineas:
$(tail -n 6 "$LOG_FILE")"
                fi ;;
            "Preparar carpeta"*)
                mkdir -p "$BACKUP_DIR"
                ui_info "Carpeta a compartir en Syncthing:

$BACKUP_DIR

Anadela como carpeta en Syncthing (en cada equipo) y las copias
viajaran solas. Consejo: usa 'Enviar y recibir' en el equipo
principal y 'Solo recibir' en los demás para evitar conflictos." ;;
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
    # varios GB de más y bloquearia importaciones que si caben)
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
    printf 'Carátulas:         %s\n' "$(human_size "${cov:-0}")"
    printf -- '-------------------------------\n'
    printf 'TOTAL:             %s\n' "$(human_size "$total")"
    printf 'Libre en el disco: %s\n' "$(human_size "$(free_bytes "$BASE_DIR")")"
}

disk_games_list() {
    # Tamaño por juego (archivo + su overlay + su prefijo propio), de mayor a menor
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
    # Prefijos y overlays de juegos que ya no estan. Imprime "tipo|ruta|tamaño"
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

# ----------------------------------------------------------------------------
# 4i. EXPORTAR / IMPORTAR LA CONFIGURACION
#     Un zip con settings.conf, los perfiles (.conf y .keys) y las carátulas.
#     Sirve para pasar de máquina a máquina o como copia de seguridad. No
#     incluye juegos, prefijos ni runners: solo lo que has configurado tu.
# ----------------------------------------------------------------------------
config_export() {
    local dest zip tmp n
    dest="$BACKUP_DIR"
    mkdir -p "$dest"
    zip="$dest/wproton_config_$(date '+%Y%m%d_%H%M').zip"
    tmp="$(mktemp -d)"
    mkdir -p "$tmp/wproton_config"
    [ -f "$SETTINGS_FILE" ] && cp -f "$SETTINGS_FILE" "$tmp/wproton_config/"
    if [ -d "$PROFILE_DIR" ]; then
        mkdir -p "$tmp/wproton_config/profiles"
        cp -a "$PROFILE_DIR/." "$tmp/wproton_config/profiles/" 2>/dev/null
    fi
    if [ -d "$COVERS_DIR" ] && [ -n "$(find "$COVERS_DIR" -type f 2>/dev/null | head -n1)" ]; then
        mkdir -p "$tmp/wproton_config/covers"
        cp -a "$COVERS_DIR/." "$tmp/wproton_config/covers/" 2>/dev/null
    fi
    if [ -d "$COVERS_WIDE_DIR" ] && \
       [ -n "$(find "$COVERS_WIDE_DIR" -type f 2>/dev/null | head -n1)" ]; then
        mkdir -p "$tmp/wproton_config/covers_wide"
        cp -a "$COVERS_WIDE_DIR/." "$tmp/wproton_config/covers_wide/" 2>/dev/null
    fi
    if [ -d "$DATOS_DIR" ] && \
       [ -n "$(find "$DATOS_DIR" -type f 2>/dev/null | head -n1)" ]; then
        mkdir -p "$tmp/wproton_config/datos"
        cp -a "$DATOS_DIR/." "$tmp/wproton_config/datos/" 2>/dev/null
    fi
    if [ -d "$COVERS_43_DIR" ] && \
       [ -n "$(find "$COVERS_43_DIR" -type f 2>/dev/null | head -n1)" ]; then
        mkdir -p "$tmp/wproton_config/covers_43"
        cp -a "$COVERS_43_DIR/." "$tmp/wproton_config/covers_43/" 2>/dev/null
    fi
    if [ -d "$LANG_DIR" ]; then
        mkdir -p "$tmp/wproton_config/lang"
        cp -a "$LANG_DIR/." "$tmp/wproton_config/lang/" 2>/dev/null
    fi
    printf 'wproton=%s\nfecha=%s\nequipo=%s\n' \
        "$WPROTON_VERSION" "$(date '+%Y-%m-%d %H:%M')" "$(uname -n)" \
        > "$tmp/wproton_config/INFO.txt"
    n="$(find "$tmp/wproton_config/profiles" -name '*.conf' 2>/dev/null | wc -l)"
    if run_with_progress "Exportando tu configuración..." \
            sh -c "cd '$tmp' && zip -qr '$zip' wproton_config"; then
        rm -rf "$tmp"
        ui_info "Configuración exportada:

$(basename "$zip")   ($(human_size "$(dir_bytes "$zip")"))
Perfiles guardados: $n

Copia ese fichero a la otra máquina y usa
'Importar configuración' alli."
        return 0
    fi
    rm -rf "$tmp" "$zip"
    ui_error "No se pudo crear el zip (falta el comando 'zip'?)"
    return 1
}

config_import() {
    local zipf tmp base n modo
    zipf="$(browse_for_path "Elige el zip de configuración" "$(browse_start "$BACKUP_DIR")" "file")" || return 1
    [ -f "$zipf" ] || return 1
    case "$zipf" in *.zip|*.ZIP) ;; *) ui_error "Eso no es un zip de configuración"; return 1 ;; esac
    tmp="$(mktemp -d)"
    if ! run_with_progress "Leyendo $(basename "$zipf")..." unzip -qo "$zipf" -d "$tmp"; then
        rm -rf "$tmp"; ui_error "No se pudo abrir el zip (falta 'unzip'?)"; return 1
    fi
    base="$tmp/wproton_config"
    [ -d "$base" ] || base="$tmp"
    if [ ! -f "$base/settings.conf" ] && [ ! -d "$base/profiles" ]; then
        rm -rf "$tmp"
        ui_error "Ese zip no contiene una configuración de WProton."
        return 1
    fi
    n="$(find "$base/profiles" -name '*.conf' 2>/dev/null | wc -l)"
    modo="$(menu "Configuración de $(head -n2 "$base/INFO.txt" 2>/dev/null | tr '\n' ' ')  |  $n perfiles" \
        "Añadir lo que falte (conserva lo tuyo)" \
        "Sustituir todo (se pierde tu configuración actual)" \
        "<< Cancelar")" || modo=""
    case "$modo" in
        "Añadir lo que falte"*)
            mkdir -p "$PROFILE_DIR" "$COVERS_DIR"
            local f
            for f in "$base"/profiles/*; do
                [ -f "$f" ] || continue
                [ -e "$PROFILE_DIR/$(basename "$f")" ] || cp -f "$f" "$PROFILE_DIR/"
            done
            for f in "$base"/covers/*; do
                [ -f "$f" ] || continue
                [ -e "$COVERS_DIR/$(basename "$f")" ] || cp -f "$f" "$COVERS_DIR/"
            done
            [ -d "$base/lang" ] && { mkdir -p "$LANG_DIR"; cp -n "$base"/lang/* "$LANG_DIR/" 2>/dev/null; }
            rm -rf "$tmp"
            ui_info "Anadido lo que faltaba.
Tus ajustes y perfiles actuales no se han tocado." ;;
        "Sustituir todo"*)
            ui_ask "SEGURO? Se sustituiran tus perfiles, carátulas y ajustes
por los del zip. Se guardara antes una copia en backups/." || { rm -rf "$tmp"; return 1; }
            config_export >/dev/null 2>&1
            [ -f "$base/settings.conf" ] && cp -f "$base/settings.conf" "$SETTINGS_FILE"
            if [ -d "$base/profiles" ]; then
                rm -rf "${PROFILE_DIR:?}"; mkdir -p "$PROFILE_DIR"
                cp -a "$base/profiles/." "$PROFILE_DIR/" 2>/dev/null
            fi
            [ -d "$base/covers" ] && { mkdir -p "$COVERS_DIR"; cp -a "$base/covers/." "$COVERS_DIR/" 2>/dev/null; }
            [ -d "$base/covers_wide" ] && { mkdir -p "$COVERS_WIDE_DIR"; cp -a "$base/covers_wide/." "$COVERS_WIDE_DIR/" 2>/dev/null; }
            [ -d "$base/covers_43" ] && { mkdir -p "$COVERS_43_DIR"; cp -a "$base/covers_43/." "$COVERS_43_DIR/" 2>/dev/null; }
            [ -d "$base/datos" ] && { mkdir -p "$DATOS_DIR"; cp -a "$base/datos/." "$DATOS_DIR/" 2>/dev/null; }
            [ -d "$base/lang" ] && { mkdir -p "$LANG_DIR"; cp -a "$base/lang/." "$LANG_DIR/" 2>/dev/null; }
            rm -rf "$tmp"
            load_settings
            # las rutas de la otra máquina pueden no existir aquí
            if [ ! -d "$GAMES_PATH" ]; then
                say "AVISO: la carpeta de juegos del zip no existe aquí: $GAMES_PATH"
                GAMES_PATH="$BASE_DIR/games"
                mkdir -p "$GAMES_PATH"
                save_settings
                ui_info "Configuración importada.
La carpeta de juegos del otro equipo no existe aquí, así que se ha
puesto la de por defecto. Cambiala en Biblioteca y preferencias."
            else
                ui_info "Configuración importada por completo."
            fi ;;
        *) rm -rf "$tmp"; return 1 ;;
    esac
    return 0
}

config_menu() {
    local sel
    while true; do
        sel="$(menu "Copia de tu configuración (perfiles, ajustes y carátulas)" \
            "Exportar mi configuración a un zip" \
            "Importar configuración desde un zip" \
            "<< Volver")" || return
        case "$sel" in
            "Exportar"*) config_export ;;
            "Importar"*) config_import ;;
            *) return ;;
        esac
    done
}

disk_menu() {
    local sel
    while true; do
        sel="$(menu "Espacio en disco" \
            "Mostrar el tamaño de WProton" \
            "Tamaño por juego" \
            "Limpiar cache de shaders" \
            "Buscar prefijos y saves huerfanos" \
            "Borrar copias de saves antiguas" \
            "<< Volver")" || return
        case "$sel" in
            "Mostrar el tamaño"*)
                ui_info "$(disk_report)" ;;
            "Tamaño por juego")
                local lst
                lst="$(disk_games_list | sort -r | cut -f2- | head -n 40)"
                if [ -z "$lst" ]; then
                    ui_info "No hay juegos en $GAMES_PATH"
                else
                    # shellcheck disable=SC2046
                    (IFS=$'\n'; set -f; menu "Tamaño por juego (juego + saves + prefijo)" $lst "<< Volver") >/dev/null || true
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

Conservar solo las 3 más recientes de cada juego?"; then
                    # Linea a linea: con "for base in $(find ...)" un juego
                    # llamado "88 Heroes" se partia en dos y sus copias
                    # antiguas no se borraban nunca.
                    local base
                    while IFS= read -r base; do
                        [ -n "$base" ] || continue
                        find "$BACKUP_DIR" -maxdepth 1 -name "${base}_*.zip" -printf '%T@ %p\n' 2>/dev/null \
                            | sort -rn | tail -n +4 | cut -d' ' -f2- | while IFS= read -r old; do
                                rm -f "$old"; say "[limpieza] borrada copia $old"
                            done
                    done <<EOFBAK
$(find "$BACKUP_DIR" -maxdepth 1 -name '*.zip' -printf '%f\n' 2>/dev/null \
  | sed 's/_[0-9]\{8\}_[0-9]\{4\}\.zip$//' | sort -u)
EOFBAK
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
    # $1 = gid, $2 = segundos de la sesión. Suma al perfil del juego.
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
    say "[+] Sesión: $(fmt_playtime "$secs") | total: $(fmt_playtime "$ps") en $pc partidas"
    return 0
}

run_args_for() {
    # Devuelve los argumentos con que hay que lanzar un fichero: los .exe van
    # directos, pero un .bat/.cmd necesita el interprete de comandos de
    # Windows (cmd /c), o Wine no sabe que hacer con el.
    local f="$1"
    case "$(printf '%s' "$f" | tr 'A-Z' 'a-z')" in
        *.bat|*.cmd) printf 'cmd\n/c\n%s\n' "$f" ;;
        *)           printf '%s\n' "$f" ;;
    esac
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
        *.exe|*.EXE|*.bat|*.BAT|*.cmd|*.CMD)
            [ -f "$input" ] || { ui_error "Ya no existe:\n$input"; return 1; }
            play_any "$input" ;;
        *)
            if [ -d "$input" ]; then
                play_folder "$input"
            elif printf '%s' "$input" | grep -qiE "$ARCHIVE_REGEX"; then
                [ -f "$input" ] || { ui_error "Ya no existe:\n$input"; return 1; }
                import_archive "$input"
            elif [ -f "$input" ]; then
                # extension desconocida: intentar como squash
                launch_game "$input" "auto"
            else
                ui_error "No existe el fichero:\n$input"; return 1
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

grid_cols_label() {
    case "${GRID_COLS:-0}" in
        0|"") printf 'automático' ;;
        *)    printf '%s' "$GRID_COLS" ;;
    esac
}

font_label() {
    case "${FONT_SCALE:-1.0}" in
        1.25) printf 'grande' ;;
        1.5)  printf 'muy grande' ;;
        *)    printf 'normal' ;;
    esac
}

dev_dir() {
    local d="$BASE_DIR/capturas"
    mkdir -p "$d" 2>/dev/null
    printf '%s' "$d"
}

dev_herramienta() {
    # Que hay en el sistema para capturar. Se prueban por orden de calidad.
    if [ -n "${WAYLAND_DISPLAY:-}" ] && command -v grim >/dev/null 2>&1; then
        printf 'grim'; return 0; fi
    command -v ffmpeg     >/dev/null 2>&1 && { printf 'ffmpeg';     return 0; }
    command -v import     >/dev/null 2>&1 && { printf 'import';     return 0; }
    command -v spectacle  >/dev/null 2>&1 && { printf 'spectacle';  return 0; }
    command -v gnome-screenshot >/dev/null 2>&1 && { printf 'gnome'; return 0; }
    return 1
}

dev_captura_pantalla() {
    # Captura TODA la pantalla (sirve tambien con un juego delante).
    # $1 = segundos de espera antes de disparar
    local espera="${1:-5}" dst; dst="$(dev_dir)/pantalla_$(date +%Y%m%d_%H%M%S).png"
    local h; h="$(dev_herramienta)" || {
        ui_error "No hay con que capturar.

Instala una de estas: ffmpeg, imagemagick (import), grim (Wayland)
o spectacle."
        return 1; }
    # En SEGUNDO PLANO: WProton vuelve al menu al momento y tu navegas hasta
    # donde quieras mientras corre la cuenta atras. Si esperara aqui, la
    # captura saldria siempre del mismo sitio y no serviria de nada.
    local tam; tam="$(dev_tam)"
    ( sleep "$espera"
      case "$h" in
          grim)      grim "$dst" ;;
          ffmpeg)    ffmpeg -y -f x11grab -video_size "$tam" -i "${DISPLAY:-:0}" \
                         -frames:v 1 "$dst" ;;
          import)    import -window root "$dst" ;;
          spectacle) spectacle -b -n -o "$dst" ;;
          gnome)     gnome-screenshot -f "$dst" ;;
      esac
      if [ -s "$dst" ]; then
          log "[dev] Captura guardada: $dst"
      else
          log "[dev] La captura salio vacia" WARN
      fi
    ) < /dev/null >> "$LOG_FILE" 2>&1 &
    ui_info "Captura programada.

Se disparara dentro de $espera segundos, con $h.

Ve donde quieras: WProton vuelve al menu ahora mismo.
El resultado ira a:
$dst"
    return 0
}

dev_tam() {
    # Tamaño de la pantalla, para ffmpeg
    local t=""
    command -v xrandr >/dev/null 2>&1 && \
        t="$(xrandr 2>/dev/null | awk '/\*/{print $1; exit}')"
    printf '%s' "${t:-1920x1080}"
}

dev_video() {
    # Graba un video corto de la pantalla. $1 = segundos, $2 = espera previa
    local seg="${1:-15}" espera="${2:-5}"
    command -v ffmpeg >/dev/null 2>&1 || {
        ui_error "Para grabar video hace falta ffmpeg."
        return 1; }
    local dst; dst="$(dev_dir)/video_$(date +%Y%m%d_%H%M%S).mp4"
    local tam; tam="$(dev_tam)"
    # En SEGUNDO PLANO y en su propia sesion: la gracia es grabarte navegando
    # por WProton, asi que el programa tiene que seguir funcionando. Antes se
    # quedaba esperando aqui y solo grababa el menu parado.
    ( sleep "$espera"
      if [ -n "${WAYLAND_DISPLAY:-}" ] && command -v wf-recorder >/dev/null 2>&1; then
          timeout $((seg + 5)) wf-recorder -f "$dst" -t "${seg}s"
      else
          ffmpeg -y -f x11grab -framerate 30 -video_size "$tam" \
              -i "${DISPLAY:-:0}" -t "$seg" \
              -c:v libx264 -preset veryfast -pix_fmt yuv420p "$dst"
      fi
      if [ -s "$dst" ]; then
          log "[dev] Video guardado: $dst"
      else
          log "[dev] El video salio vacio" WARN
      fi
    ) < /dev/null >> "$LOG_FILE" 2>&1 &
    ui_info "Grabacion programada.

Empieza dentro de $espera segundos y dura $seg.

Sal de este menu y navega con normalidad: se esta grabando la
pantalla entera. El video ira a:
$dst"
    return 0
}

dev_video_menus() {
    # Graba los MENUS desde dentro de pygame y luego monta el video.
    #
    # ffmpeg leyendo la pantalla desde fuera saca video negro: la ventana de
    # los menus se dibuja con aceleracion y su contenido no llega a la ventana
    # raiz de las X. Desde dentro sale exacto.
    #
    # Contrapartida: solo graba los MENUS. Mientras el juego corre no hay
    # menus que dibujar, asi que para grabar la partida hace falta la otra
    # opcion (pantalla completa con ffmpeg).
    local seg="${1:-30}" espera="${2:-5}"
    command -v ffmpeg >/dev/null 2>&1 || {
        ui_error "Para montar el video hace falta ffmpeg."; return 1; }
    local dir; dir="$(dev_dir)"
    local frames="$dir/.frames_$(date +%H%M%S)"
    local dst="$dir/menus_$(date +%Y%m%d_%H%M%S).mp4"
    rm -rf "$frames"; mkdir -p "$frames"
    # marca que lee el proceso de menus: hasta cuando grabar y donde
    printf '%s\n%s\n' "$(( $(date +%s) + espera + seg ))" "$frames" > "$dir/.rec"
    ( sleep $((espera + seg + 2))
      rm -f "$dir/.rec"
      if [ -n "$(ls -A "$frames" 2>/dev/null)" ]; then
          ffmpeg -y -framerate 10 -i "$frames/f%05d.png" \
              -c:v libx264 -preset veryfast -pix_fmt yuv420p -r 30 "$dst"
          [ -s "$dst" ] && log "[dev] Video de menus: $dst"
      else
          log "[dev] No se capturo ningun fotograma" WARN
      fi
      rm -rf "$frames"
    ) < /dev/null >> "$LOG_FILE" 2>&1 &
    ui_info "Grabacion de los menus programada.

Empieza en $espera segundos y dura $seg.

Sal de aqui y navega por los menus: se graba lo que se ve.
Esta forma NO graba los juegos, solo los menus, pero sale
perfecta (la otra opcion puede salir en negro).

El video ira a:
$dst"
    return 0
}

dev_menu() {
    # Solo aparece con DEV_MODE=1 en settings.conf. No esta documentado.
    local sel
    while :; do
        sel="$(menu "Modo desarrollo" \
            "Captura de pantalla (5 s de margen)" \
            "Captura de pantalla (15 s de margen)" \
            "Grabar los menus - 30 s (recomendado)" \
            "Grabar los menus - 60 s" \
            "Grabar la pantalla entera - 30 s (puede salir en negro)" \
            "Ver la carpeta de capturas" \
            "<< Volver")" || return 0
        case "$sel" in
            "<< Volver") return 0 ;;
            "Captura de pantalla (5"*)   dev_captura_pantalla 5  || true ;;
            "Captura de pantalla (15"*)  dev_captura_pantalla 15 || true ;;
            "Grabar los menus - 30"*)    dev_video_menus 30 5  || true ;;
            "Grabar los menus - 60"*)    dev_video_menus 60 5  || true ;;
            "Grabar la pantalla entera"*) dev_video 30 10 || true ;;
            "Ver la carpeta"*)
                ui_info "Capturas en:
$(dev_dir)

$(ls -1t "$(dev_dir)" 2>/dev/null | head -n 10 | sed 's/^/  /')

Dentro de los menus, F12 guarda la pantalla al momento." ;;
        esac
    done
}

probar_mando() {
    # Escucha el mando durante unos segundos y enseña QUE llega: que
    # dispositivos se leen y con que codigo llega cada boton. Es la forma
    # rapida de saber por que una combinacion no funciona, sin tener que
    # lanzar un juego y mirar el registro despues.
    pygame_available || { ui_error "Hacen falta los menus graficos"; return 1; }
    write_menu_pygame
    local salida; salida="$(mktemp)"
    ui_info "Prueba del mando

Al aceptar, WProton escuchara el mando durante 15 segundos.

Pulsa unos cuantos botones y manten Select un par de segundos.
Despues se te enseñara lo que ha llegado."
    ( PYGAME_HIDE_SUPPORT_PROMPT=1 timeout 15 "$PY_BIN" "$MENU_PYGAME_PY" \
        guardia "$RUNTIME_DIR/.prueba_mando" 2 select ) >"$salida" 2>&1
    rm -f "$RUNTIME_DIR/.prueba_mando" 2>/dev/null
    local visto; visto="$(grep -c 'guardia: boton' "$salida" 2>/dev/null || echo 0)"
    local disp;  disp="$(grep -c 'guardia vigilando' "$salida" 2>/dev/null || echo 0)"
    cat "$salida" >> "$LOG_FILE" 2>/dev/null
    if [ "$disp" = 0 ]; then
        ui_error "No se ha encontrado ningun mando.

WProton no ve ningun dispositivo de tipo joystick. Comprueba
que el mando este conectado y encendido."
    elif [ "$visto" = 0 ]; then
        ui_error "Se ven $disp dispositivo(s), pero NO llega ninguna pulsacion.

Suele ser un problema de permisos de /dev/input.
Prueba: Runners y herramientas -> Arreglar permisos del mando."
    else
        ui_info "El mando funciona.

$(grep 'guardia: boton' "$salida" | sed 's/menu_pygame: guardia: //' | sort -u | head -n 12)

Si el codigo que sale al pulsar Select no es el que espera la
combinacion, cambiala en settings.conf (PAD_EXIT_COMBO)."
    fi
    rm -f "$salida"
    return 0
}

arreglar_permisos_mando() {
    # Los mandos de Sony se leen por /dev/hidraw desde GE-Proton 11-4. Si esos
    # nodos no son legibles, el mando no responde y no hay ajuste que lo
    # arregle: es un permiso del sistema.
    #
    # WProton no puede concederlo (haria falta root), pero si puede dejar el
    # fichero listo y decir EXACTAMENTE que hay que ejecutar, adaptado al
    # sistema: en SteamOS ademas hay que desbloquear el sistema de ficheros.
    local n; n="$(hidraw_sin_permiso)" || true
    # tambien /dev/input: es lo que leen los menus, el guardia y el mapeador
    local ev nin=0
    for ev in /dev/input/event*; do
        [ -e "$ev" ] || continue
        [ -r "$ev" ] || nin=$((nin+1))
    done
    local reglas="$RUNTIME_DIR/70-wproton-mandos.rules"
    mkdir -p "$RUNTIME_DIR" 2>/dev/null
    # La regla cubre USB y Bluetooth: por Bluetooth el fabricante no aparece
    # en la misma ruta, asi que hace falta la segunda linea.
    cat > "$reglas" <<'EOFR'
# Mandos por hidraw (Sony DualSense/DualShock, Nintendo, Valve).
# Sin esto, GE-Proton 11-4 y posteriores no ven el mando.
KERNEL=="hidraw*", ATTRS{idVendor}=="054c", MODE="0660", TAG+="uaccess"
KERNEL=="hidraw*", ATTRS{idVendor}=="057e", MODE="0660", TAG+="uaccess"
KERNEL=="hidraw*", ATTRS{idVendor}=="28de", MODE="0660", TAG+="uaccess"
# Bluetooth: el fabricante no esta en la misma ruta, se casa por el nombre
KERNEL=="hidraw*", KERNELS=="*054C:*", MODE="0660", TAG+="uaccess"
KERNEL=="hidraw*", KERNELS=="*057E:*", MODE="0660", TAG+="uaccess"
# Y los dispositivos de entrada: sin esto los menus y el cierre con el mando
# no reciben nada, porque no pueden leer /dev/input/event*
KERNEL=="event*", SUBSYSTEM=="input", ATTRS{idVendor}=="054c", MODE="0660", TAG+="uaccess"
KERNEL=="event*", SUBSYSTEM=="input", ATTRS{idVendor}=="057e", MODE="0660", TAG+="uaccess"
KERNEL=="event*", SUBSYSTEM=="input", ATTRS{idVendor}=="045e", MODE="0660", TAG+="uaccess"
KERNEL=="event*", SUBSYSTEM=="input", ATTRS{idVendor}=="28de", MODE="0660", TAG+="uaccess"
EOFR
    local pasos=""
    if [ "${IS_STEAMOS:-0}" = 1 ] || [ -f /etc/os-release ] && grep -qi 'steamos' /etc/os-release 2>/dev/null; then
        pasos="sudo steamos-readonly disable
sudo cp \"$reglas\" /etc/udev/rules.d/
sudo udevadm control --reload-rules
sudo udevadm trigger
sudo steamos-readonly enable"
    else
        pasos="sudo cp \"$reglas\" /etc/udev/rules.d/
sudo udevadm control --reload-rules
sudo udevadm trigger"
    fi
    ui_info "Permisos del mando

Sin permiso de lectura:
  /dev/hidraw*      ${n:-0}   (los mandos de Sony con GE-Proton 11-4+)
  /dev/input/event* $nin   (los menus y el cierre con el mando)

El fichero ya esta preparado en:
$reglas

Abre una terminal y ejecuta:

$pasos

Despues desconecta y vuelve a conectar el mando.

Estos comandos funcionan en cualquier terminal (bash, fish o zsh).

Si estas en SteamOS y sudo pide una contraseña que nunca has
puesto, crea una antes con:  passwd"
    say "[i] Reglas de mando preparadas en $reglas"
    return 0
}

hidraw_sin_permiso() {
    # ¿Cuantos nodos /dev/hidraw no podemos leer? GE-Proton 11-4 y siguientes
    # leen ahi los mandos de Sony; sin permiso, no los ven.
    local h n=0
    for h in /dev/hidraw*; do
        [ -e "$h" ] || continue
        [ -r "$h" ] || n=$((n+1))
    done
    printf '%s' "$n"
    [ "$n" -gt 0 ]
}

runner_gestiona_mandos() {
    # ¿Este runner sabe manejar los mandos de Sony por su cuenta?
    #
    # Desde GE-Proton 11-4 ("la version del arreglo de mandos") el soporte de
    # DualSense y DualShock 4 esta rehecho y funciona solo. Lo mejor que
    # podemos hacer es NO ESTORBAR: nuestra opcion "Mando via SDL" pone
    # PROTON_DISABLE_HIDRAW=1, y eso apaga justo el soporte nuevo.
    # $1 = nombre del runner
    local nombre="${1:-}" v mayor menor
    case "$nombre" in
        GE-Proton*|ge-proton*) ;;
        *) return 1 ;;                  # otros runners: como siempre
    esac
    # "GE-Proton11-5-x86_64" -> mayor=11 menor=5
    v="$(printf '%s' "$nombre" | sed -n 's/^[Gg][Ee]-[Pp]roton\([0-9]\+\)-\([0-9]\+\).*/\1 \2/p')"
    [ -n "$v" ] || return 1
    mayor="${v%% *}"; menor="${v##* }"
    [ "$mayor" -gt 11 ] 2>/dev/null && return 0
    [ "$mayor" -eq 11 ] 2>/dev/null && [ "$menor" -ge 4 ] 2>/dev/null && return 0
    return 1
}

pad_sony_label() {
    case "${PAD_SONY:-auto}" in
        1) printf 'ON (como mando de Xbox)' ;;
        0) printf 'OFF' ;;
        *) printf 'AUTO' ;;
    esac
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
# Las horizontales van en SU PROPIA carpeta, no con un sufijo en el nombre:
# asi quien ya tenga una coleccion de caratulas anchas puede copiarla tal
# cual, con los ficheros llamados como el juego.
COVERS_WIDE_DIR="$BASE_DIR/covers_wide"   # panoramica (cabecera de Steam)
COVERS_43_DIR="$BASE_DIR/covers_43"       # 4:3 (640x480)
# Datos de los juegos (ficha de Steam, duracion de HowLongToBeat). Antes
# vivian mezclados con las caratulas; con tres carpetas de caratulas, esto
# pide su propio sitio.
DATOS_DIR="$BASE_DIR/datos"

datos_preparar() {
    # Crea la carpeta y traslada lo que estuviera en covers/. Una sola vez.
    mkdir -p "$DATOS_DIR" 2>/dev/null
    local f n=0
    for f in "$COVERS_DIR"/*.info.json "$COVERS_DIR"/*.hltb; do
        [ -f "$f" ] || continue
        mv -f "$f" "$DATOS_DIR/" 2>/dev/null && n=$((n+1))
    done
    [ "$n" -gt 0 ] && log "Datos de juegos movidos a datos/: $n fichero(s)"
    return 0
}

covers_dir_de() {
    # Carpeta que corresponde a cada forma de caratula.
    case "${1:-vertical}" in
        wide) printf '%s' "$COVERS_WIDE_DIR" ;;
        43)   printf '%s' "$COVERS_43_DIR" ;;
        *)    printf '%s' "$COVERS_DIR" ;;
    esac
}

covers_wide_preparar() {
    # Crea la carpeta y traslada lo que se hubiera guardado con el nombre
    # anterior (covers/<juego>.wide.png). Se hace una sola vez y en silencio.
    mkdir -p "$COVERS_WIDE_DIR" "$COVERS_43_DIR" 2>/dev/null
    local f base
    for f in "$COVERS_DIR"/*.wide.png "$COVERS_DIR"/*.wide.jpg \
             "$COVERS_DIR"/*.wide.jpeg "$COVERS_DIR"/*.wide.webp; do
        [ -f "$f" ] || continue
        base="$(basename "$f")"
        # "Doom.wide.png" -> "Doom.png"
        mv -f "$f" "$COVERS_WIDE_DIR/${base%.wide.*}.${base##*.}" 2>/dev/null \
            && log "Caratula ancha movida a covers_wide/: $base"
    done
    return 0
}
PROGRESS_PID=""

progress_start() {
    # Ventana de progreso con pygame. $1 = titulo
    PROGRESS_PID=""; PROGRESS_FILE=""
    pygame_available || return 0
    pad_bridge_stop
    write_menu_pygame
    PROGRESS_FILE="$(mktemp)"
    printf '0|Preparando...\n' > "$PROGRESS_FILE"
    PYGAME_HIDE_SUPPORT_PROMPT=1 SDL_JOYSTICK_ALLOW_BACKGROUND_EVENTS=1 \
        env -u LD_PRELOAD "$PY_BIN" "$MENU_PYGAME_PY" progress "$1" "$PROGRESS_FILE" < /dev/null >> "$LOG_FILE" 2>&1 &
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

profile_get() {
    # $1 = gid, $2 = clave. Lee UN dato del perfil sin cargarlo entero: asi no
    # se pisan las variables del juego que se este configurando ahora mismo.
    local f="$PROFILE_DIR/$1.conf"
    [ -f "$f" ] || return 1
    sed -n "s/^$2=\"\{0,1\}\([^\"]*\)\"\{0,1\}$/\1/p" "$f" | head -n1
}

cover_nombres() {
    # Nombres con los que puede estar guardada la caratula de un juego.
    #
    # El identificador cambia los espacios por guiones bajos ("Blade Arcus"
    # -> "Blade_Arcus"), que es como las guarda la descarga automatica. Pero
    # quien copia su propia coleccion conserva los espacios, y asi no casaba
    # ninguna. Se prueban las dos formas.
    local gid="$1"
    printf '%s\n' "$gid"
    case "$gid" in
        *_*) printf '%s\n' "$(printf '%s' "$gid" | tr '_' ' ')" ;;
    esac
}

cover_tipo_real() {
    # ¿Existe la caratula de ESA forma, de verdad? ($1 = gid, $2 = forma)
    #
    # Hace falta aparte de cover_for porque aquella, si no encuentra la forma
    # pedida, devuelve la vertical como respaldo: muy comodo para dibujar,
    # pero traicionero para decidir si hay que descargar algo (siempre
    # parecia que ya estaba).
    local e d nom; d="$(covers_dir_de "${2:-vertical}")"
    while IFS= read -r nom; do
        [ -n "$nom" ] || continue
        for e in png jpg jpeg webp; do
            [ -f "$d/$nom.$e" ] && { printf '%s' "$d/$nom.$e"; return 0; }
        done
    done <<EOFCN
$(cover_nombres "$1")
EOFCN
    if [ "${2:-}" = wide ]; then       # nomenclatura anterior
        for e in png jpg jpeg webp; do
            [ -f "$COVERS_DIR/$1.wide.$e" ] && { printf '%s' "$COVERS_DIR/$1.wide.$e"; return 0; }
        done
    fi
    return 1
}

cover_for() {
    # $1 = gid, $2 = "wide" para la carátula horizontal (opcional).
    #
    # Se guardan en carpetas distintas, con el MISMO nombre de fichero:
    #   covers/<juego>.png         vertical (2:3), la de siempre
    #   covers_wide/<juego>.png    panoramica, tipo cabecera de Steam
    #   covers_43/<juego>.png      4:3 (640x480)
    #
    # Si se pide la horizontal y no la hay, se usa la vertical: mejor una
    # caratula deformada que un hueco vacio.
    local e d nom
    if [ -n "${2:-}" ] && [ "${2:-}" != vertical ]; then
        d="$(covers_dir_de "$2")"
        while IFS= read -r nom; do
            [ -n "$nom" ] || continue
            for e in png jpg jpeg webp; do
                [ -f "$d/$nom.$e" ] && { printf '%s' "$d/$nom.$e"; return 0; }
            done
        done <<EOFC2
$(cover_nombres "$1")
EOFC2
        # compatibilidad con la nomenclatura anterior (covers/<juego>.wide.*)
        if [ "$2" = wide ]; then
            for e in png jpg jpeg webp; do
                [ -f "$COVERS_DIR/$1.wide.$e" ] && \
                    { printf '%s' "$COVERS_DIR/$1.wide.$e"; return 0; }
            done
        fi
    fi
    while IFS= read -r nom; do
        [ -n "$nom" ] || continue
        for e in png jpg jpeg webp; do
            [ -f "$COVERS_DIR/$nom.$e" ] && \
                { printf '%s' "$COVERS_DIR/$nom.$e"; return 0; }
        done
    done <<EOFC3
$(cover_nombres "$1")
EOFC3
    return 1
}

urlencode_py() {
    "$PY_BIN" -c 'import sys,urllib.parse;print(urllib.parse.quote(sys.argv[1]))' "$1" 2>/dev/null
}

caratula_manual() {
    # Elegir una imagen del disco como caratula. $1 = gid.
    #
    # Se puede poner la vertical (rejilla clasica) o la horizontal (rejilla
    # de caratulas anchas), y se guardan por separado.
    local gid="$1" tipo destino img ext
    tipo="$(menu "Carátula de $gid" \
        "Vertical (2:3, como las tiendas)" \
        "Panorámica (ancha, tipo Steam)" \
        "Cuadrada 4:3 (640x480)" \
        "<< Volver")" || return 0
    case "$tipo" in
        "Vertical"*)   destino="$(covers_dir_de vertical)" ;;
        "Panorámica"*) destino="$(covers_dir_de wide)" ;;
        "Cuadrada"*)   destino="$(covers_dir_de 43)" ;;
        *) return 0 ;;
    esac
    img="$(browse_for_path "Elige una imagen" "$(browse_start "$HOME")" "image")" || return 0
    [ -f "$img" ] || return 1
    ext="${img##*.}"
    case "$(printf '%s' "$ext" | tr 'A-Z' 'a-z')" in
        png|jpg|jpeg|webp) ext="$(printf '%s' "$ext" | tr 'A-Z' 'a-z')" ;;
        *) ui_error "Eso no parece una imagen (png, jpg o webp)."; return 1 ;;
    esac
    mkdir -p "$destino" 2>/dev/null
    # se quitan las que hubiera de ese tipo, para no dejar dos con distinta
    # extension y que gane la que no toca
    local e
    for e in png jpg jpeg webp; do rm -f "$destino/$gid.$e" 2>/dev/null; done
    if cp -f "$img" "$destino/$gid.$ext" 2>>"$LOG_FILE"; then
        say "[+] Caratula guardada: $(basename "$destino")/$gid.$ext"
        ui_info "Carátula guardada.

Se vera en la biblioteca al volver a la lista."
        return 0
    fi
    ui_error "No se pudo copiar la imagen."
    return 1
}

sgdb_buscar_manual() {
    # Buscar la caratula de UN juego escribiendo el nombre a mano.
    #
    # La busqueda automatica usa el nombre del fichero, que muchas veces trae
    # version, region o el nombre del grupo, y entonces no encuentra nada.
    # Aqui se escribe el titulo de verdad y se elige entre los resultados.
    local gid="$1"
    SGDB_KEY="$(sgdb_key_leer)"
    [ -n "$SGDB_KEY" ] || { ui_error "Falta la API key de SteamGridDB.

Descarga carátulas una vez desde el menú y te la pedirá, o deja
un fichero de texto con la clave junto a wproton.sh."; return 1; }

    local tipo destino dims
    tipo="$(menu "Buscar carátula de: $gid" \
        "Vertical (2:3)" \
        "Panorámica (tipo Steam)" \
        "Cuadrada 4:3" \
        "<< Volver")" || return 0
    case "$tipo" in
        "Vertical"*)   destino="$(covers_dir_de vertical)"; dims="600x900" ;;
        "Panorámica"*) destino="$(covers_dir_de wide)";     dims="920x430,460x215" ;;
        "Cuadrada"*)   destino="$(covers_dir_de 43)";       dims="640x480,512x384" ;;
        *) return 0 ;;
    esac

    local busca; busca="$(ask_text "Nombre del juego para buscar en SteamGridDB" \
                          "$(printf '%s' "$gid" | tr '._' '  ')")"
    [ -n "$busca" ] || return 0

    loading_say "Buscando \"$busca\"..."
    local q; q="$(urlencode_py "$busca")"
    local gjson; gjson="$(curl -fsSL -H "Authorization: Bearer $SGDB_KEY" \
        "https://www.steamgriddb.com/api/v2/search/autocomplete/$q" 2>>"$LOG_FILE")"
    loading_clear
    # nombres e identificadores de los resultados, en paralelo
    local ids nombres
    ids="$(printf '%s' "$gjson" | grep -o '"id": *[0-9]*' | grep -o '[0-9]*')"
    nombres="$(printf '%s' "$gjson" | grep -o '"name": *"[^"]*"' | cut -d'"' -f4)"
    [ -n "$ids" ] || { ui_error "Sin resultados para: $busca"; return 1; }

    # menu con los titulos encontrados
    local opciones="" n=0 nom
    while IFS= read -r nom; do
        [ -n "$nom" ] || continue
        n=$((n+1)); opciones="$opciones$n. $nom
"
        [ "$n" -ge 12 ] && break
    done <<EOFN
$nombres
EOFN
    local elegido
    # shellcheck disable=SC2046
    elegido="$(IFS=$'\n'; set -f; menu "¿Cuál es?" $opciones "<< Volver")" || return 0
    [ "$elegido" = "<< Volver" ] && return 0
    local pos="${elegido%%.*}"
    local gameid; gameid="$(printf '%s' "$ids" | sed -n "${pos}p")"
    [ -n "$gameid" ] || return 1

    loading_say "Descargando carátula..."
    local ujson url ext
    ujson="$(curl -fsSL -H "Authorization: Bearer $SGDB_KEY" \
        "https://www.steamgriddb.com/api/v2/grids/game/$gameid?dimensions=$dims&types=static" \
        2>>"$LOG_FILE")"
    url="$(printf '%s' "$ujson" | grep -o '"url": *"[^"]*"' | head -n1 | cut -d'"' -f4 | sed 's|\\/|/|g')"
    loading_clear
    [ -n "$url" ] || { ui_error "Ese juego no tiene carátula de ese tipo en SteamGridDB.

Prueba con el otro tipo, o pon una imagen tuya desde
'Carátula: elegir una imagen'."; return 1; }
    ext="${url##*.}"; case "$ext" in png|jpg|jpeg|webp) ;; *) ext=png ;; esac
    mkdir -p "$destino" 2>/dev/null
    local e
    for e in png jpg jpeg webp; do rm -f "$destino/$gid.$e" 2>/dev/null; done
    if curl -fsSL "$url" -o "$destino/$gid.$ext" 2>>"$LOG_FILE"; then
        say "[+] Caratula guardada: $(basename "$destino")/$gid.$ext"
        ui_info "Carátula guardada.

Se vera al volver a la lista."
        return 0
    fi
    ui_error "No se pudo descargar la imagen."
    return 1
}

sgdb_download_covers() {
    # Descarga caratulas de SteamGridDB. Se elige que tipo: bajar las dos
    # gasta el doble de peticiones y de tiempo, y mucha gente usa una sola
    # vista.
    local quiere
    quiere="$(menu "¿Qué carátulas quieres descargar?" \
        "Solo verticales (2:3)" \
        "Solo panorámicas (tipo Steam)" \
        "Solo cuadradas (4:3)" \
        "Todas (las tres formas)" \
        "<< Volver")" || return 0
    local tipos
    case "$quiere" in
        "Solo vert"*) tipos="vertical" ;;
        "Solo pano"*) tipos="wide" ;;
        "Solo cuad"*) tipos="43" ;;
        "Todas"*)     tipos="vertical wide 43" ;;
        *) return 0 ;;
    esac
    # la clave puede venir de un fichero aparte
    SGDB_KEY="$(sgdb_key_leer)"
    if [ -z "$SGDB_KEY" ]; then
        local k
        k="$(ask_text "Pega tu API key de SteamGridDB
(gratis en steamgriddb.com -> Profile -> Preferences -> API)

Se guardara en sgdb.key, solo legible por ti, y NO en
settings.conf (que se comparte al pedir ayuda)." "")"
        [ -z "$k" ] && return 1
        SGDB_KEY="$k"
        # en su propio fichero y sin permisos para nadie mas
        if (umask 077; printf '%s\n' "$k" > "$BASE_DIR/sgdb.key") 2>/dev/null; then
            chmod 600 "$BASE_DIR/sgdb.key" 2>/dev/null
            say "[+] Clave guardada en sgdb.key (solo legible por ti)"
        else
            save_settings           # si no se pudo escribir, como antes
        fi
    fi
    mkdir -p "$COVERS_DIR"
    local list total=0 got=0 pend=0 idx=0
    list="$(find "$GAMES_PATH" -maxdepth 3 -type f \( -iname '*.wsquashfs' -o -iname '*.squashfs' -o -iname '*.dwarfs' \) 2>/dev/null | sort)"
    [ -z "$list" ] && { ui_info "No hay juegos en $GAMES_PATH"; return 1; }
    local f gid title q gjson gameid ujson url ext _falta _t
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        # Pendiente si le falta alguna de las que se han pedido
        local _g _falta=0; _g="$(game_id "$f")"
        local _t
        for _t in $tipos; do
            cover_tipo_real "$_g" "$_t" >/dev/null 2>&1 || _falta=1
        done
        [ "$_falta" = 1 ] && pend=$((pend+1))
    done <<EOF0
$list
EOF0
    [ "$pend" -eq 0 ] && { ui_info "No falta ninguna carátula de las pedidas."; return 0; }
    progress_start "Descargando carátulas de SteamGridDB"
    while IFS= read -r f; do
        gid="$(game_id "$f")"
        # Saltar el juego SOLO si ya tiene todas las que se han pedido.
        #
        # Antes se descartaba con solo tener la vertical, asi que al pedir
        # "solo anchas" se ignoraban justamente los juegos que ya tenian
        # caratula: se buscaba unicamente en los que no tenian ninguna.
        _falta=0
        for _t in $tipos; do
            cover_tipo_real "$gid" "$_t" >/dev/null 2>&1 || _falta=1
        done
        [ "$_falta" = 0 ] && continue
        total=$((total+1)); idx=$((idx+1))
        title="$(basename "$f")"; title="${title%.*}"; title="$(printf '%s' "$title" | tr '_.' '  ')"
        progress_set "$(( idx * 100 / pend ))" "($idx/$pend) $title"
        say "[SGDB] Buscando carátula: $title"
        q="$(urlencode_py "$title")"
        gjson="$(curl -fsSL -H "Authorization: Bearer $SGDB_KEY" \
            "https://www.steamgriddb.com/api/v2/search/autocomplete/$q" 2>>"$LOG_FILE")"
        if printf '%s' "$gjson" | grep -q '"success": *false'; then
            progress_stop
            ui_error "SteamGridDB rechazo la peticion (API key invalida?)"; return 1
        fi
        gameid="$(printf '%s' "$gjson" | grep -o '"id": *[0-9]*' | head -n1 | grep -o '[0-9]*')"
        [ -z "$gameid" ] && { say "[SGDB]   sin resultados para: $title"; continue; }
        # Se piden las DOS: la vertical para la rejilla clasica y la
        # horizontal para la vista de carátulas anchas. Cada una se guarda
        # con su nombre, asi que no se pisan.
        local destino dims bajada=0
        for tipo in $tipos; do
            destino="$(covers_dir_de "$tipo")"
            case "$tipo" in
                vertical) dims="600x900" ;;
                wide)     dims="920x430,460x215" ;;
                43)       dims="640x480,512x384" ;;
            esac
            mkdir -p "$destino" 2>/dev/null
            # si ya la tenemos, no se vuelve a pedir
            # No se vuelve a descargar lo que ya hay: la vertical podria ser
            # una que el usuario eligio a mano.
            cover_tipo_real "$gid" "$tipo" >/dev/null 2>&1 && continue
            ujson="$(curl -fsSL -H "Authorization: Bearer $SGDB_KEY" \
                "https://www.steamgriddb.com/api/v2/grids/game/$gameid?dimensions=$dims&types=static" \
                2>>"$LOG_FILE")"
            url="$(printf '%s' "$ujson" | grep -o '"url": *"[^"]*"' | head -n1 | cut -d'"' -f4 | sed 's|\\/|/|g')"
            if [ -z "$url" ]; then
                say "[SGDB]   sin carátula $tipo ($dims) para: $title"
                continue
            fi
            ext="${url##*.}"; case "$ext" in png|jpg|jpeg|webp) ;; *) ext=png ;; esac
            if curl -fsSL "$url" -o "$destino/$gid.$ext" 2>>"$LOG_FILE"; then
                bajada=1
                say "[SGDB]   OK ($tipo) -> $(basename "$destino")/$gid.$ext"
            fi
        done
        [ "$bajada" = 1 ] && got=$((got+1))
    done <<EOF2
$list
EOF2
    progress_stop
    ui_info "Carátulas: $got descargadas de $total pendientes.
(Las que falten: pon un png/jpg a mano en covers/<juego>.png)"
}

browse_start() {
    # Carpeta inicial del navegador: la última visitada. Si ya no existe
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
        menu_server_request browse "$title" "$tmpsel" "$cur" "$mode" ""
        if [ $? = 9 ]; then
            PYGAME_HIDE_SUPPORT_PROMPT=1 SDL_JOYSTICK_ALLOW_BACKGROUND_EVENTS=1 \
                env -u LD_PRELOAD "$PY_BIN" "$MENU_PYGAME_PY" browse "$title" "$tmpsel" "$cur" "$mode" >> "$LOG_FILE" 2>&1
        fi
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
                -o -iname '*.z01' -o -iname '*.exe' -o -iname '*.bat' \
                -o -iname '*.cmd' -o -iname '*.wtgz' \) ! -name '.*' -printf '%f\n' 2>/dev/null | sort)"
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
    # Ordena la lista (rutas relativas, una por linea) según GAMES_SORT.
    # Los favoritos van SIEMPRE primero. Para los criterios descendentes
    # (recientes / más jugados) se INVIERTE la clave numerica en vez de usar
    # "sort -r", que también invertiria la prioridad de los favoritos.
    local rel meta fav last secs n
    while IFS= read -r rel; do
        [ -n "$rel" ] || continue
        meta="$(game_meta "$rel")"
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

discos_sin_montar() {
    # Particiones con sistema de ficheros que NO estan montadas.
    # Formato: dispositivo|etiqueta|tipo|tamaño
    command -v lsblk >/dev/null 2>&1 || return 1
    lsblk -rno PATH,LABEL,FSTYPE,SIZE,MOUNTPOINT 2>/dev/null | awk '
        NF >= 4 && $5 == "" && $3 != "" && $3 != "swap" &&
        $3 != "crypto_LUKS" && $3 != "linux_raid_member" {
            etiqueta = $2; gsub(/\\x20/, " ", etiqueta)
            print $1 "|" etiqueta "|" $3 "|" $4
        }'
    return 0
}

montar_disco() {
    # Monta con udisks2, que es lo que usa el propio escritorio: NO necesita
    # contraseña ni permisos de root, y deja el disco en /run/media/<usuario>.
    # $1 = dispositivo. Imprime el punto de montaje.
    local dev="$1" salida
    MOUNT_ERROR=""
    if ! command -v udisksctl >/dev/null 2>&1; then
        MOUNT_ERROR="no esta instalado udisks2 (udisksctl)"
        log "montar_disco: $MOUNT_ERROR" WARN
        return 1
    fi
    # Sin --no-user-interaction: en el modo Juego no hay ventana donde pedir
    # autorizacion, pero con ella al menos el intento llega hasta el final y
    # udisks dice POR QUE no puede, en vez de rendirse en silencio.
    salida="$(udisksctl mount -b "$dev" 2>&1)" || {
        MOUNT_ERROR="$(printf '%s' "$salida" | tail -n2 | tr '\n' ' ')"
        log "No se pudo montar $dev: $salida" WARN
        return 1
    }
    # "Mounted /dev/sda1 at /run/media/deck/JUEGOS"
    printf '%s' "$salida" | sed -n 's/.* at \(.*\)$/\1/p' | sed 's/\.$//'
    return 0
}

montar_disco_manual() {
    # Montar un disco CUANDO EL USUARIO QUIERE, sin depender de que falte una
    # carpeta. El caso tipico: acaba de conectar un disco externo con juegos y
    # todavia no lo ha añadido a la biblioteca.
    #
    # Al terminar se ofrece añadirlo como carpeta de juegos: montar y no poder
    # usarlo dejaba el trabajo a medias.
    local discos sel dev mp
    discos="$(discos_sin_montar)" || discos=""
    if [ -z "$discos" ]; then
        ui_info "No hay ningun disco pendiente de montar.

Todos los que ve el sistema ya estan montados. Si acabas de
conectar uno, espera unos segundos y vuelve a entrar."
        return 0
    fi
    local opciones="" etq tipo tam d
    while IFS='|' read -r d etq tipo tam; do
        [ -n "$d" ] || continue
        opciones="$opciones${etq:-sin etiqueta}   [$tipo, $tam]   $d
"
    done <<EOFD
$discos
EOFD
    # shellcheck disable=SC2046
    sel="$(IFS=$'\n'; set -f; menu "Discos disponibles para montar" \
          $opciones "<< Volver")" || return 0
    [ "$sel" = "<< Volver" ] && return 0
    dev="${sel##*   }"
    loading_say "Montando $dev..."
    if ! mp="$(montar_disco "$dev")" || [ -z "$mp" ]; then
        ui_error "No se pudo montar $dev.

${MOUNT_ERROR:-sin detalle}

En el modo Juego el sistema puede no permitir montar sin
autorizacion. Dos formas de resolverlo:

  - Montarlo una vez desde el modo Escritorio: muchos sistemas
    lo recuerdan y despues lo montan solos.
  - O desconectar y volver a conectar el disco, para que el
    sistema lo monte al detectarlo."
        return 1
    fi
    loading_clear
    # ¿hay juegos dentro? se mira para no proponer una carpeta vacia
    local cuantos
    cuantos="$(find "$mp" -maxdepth 3 \( -iname '*.wsquashfs' -o -iname '*.squashfs' \
               -o -iname '*.dwarfs' \) 2>/dev/null | wc -l)"
    if ui_ask "Disco montado en:
$mp

Se han encontrado $cuantos juego(s) empaquetado(s).

Quieres añadirlo como carpeta de juegos?"; then
        local destino="$mp"
        # si los juegos estan en una subcarpeta, dejar elegirla
        if [ "$cuantos" = 0 ]; then
            destino="$(pick_dir "Carpeta con los juegos dentro del disco" "$mp")" || destino="$mp"
        fi
        destino="$(abs_path "$destino")"
        if games_paths | grep -qxF "$destino"; then
            ui_info "Esa carpeta ya estaba en la lista."
        else
            GAMES_PATHS_EXTRA="${GAMES_PATHS_EXTRA:+$GAMES_PATHS_EXTRA
}$destino"
            save_settings
            ui_info "Carpeta añadida:
$destino

Ya deberian aparecer sus juegos en la lista."
        fi
    fi
    return 0
}

montar_discos_recordados() {
    # Si una carpeta de juegos no aparece pero SU disco esta conectado, se
    # monta solo. Es el caso de siempre: se dejo configurado un disco externo
    # y al encender el equipo no viene montado.
    #
    # Solo se monta lo que ya estaba configurado como carpeta de juegos: no se
    # toca ningun otro disco del sistema.
    local p faltan="" dev etq tipo tam mp montados=0
    # Se apunta CADA carpeta y si esta o no: sin esto, "todas disponibles"
    # no permitia distinguir entre "el disco ya estaba montado" y "la carpeta
    # del disco externo ni siquiera esta configurada".
    while IFS= read -r p; do
        [ -n "$p" ] || continue
        if [ -d "$p" ]; then
            log "Automontaje: OK  $p"
        else
            log "Automontaje: FALTA  $p"
            faltan="$faltan$p
"
        fi
    done <<EOFCR
$(games_paths)
EOFCR
    if [ -z "$faltan" ]; then
        log "Automontaje: todas las carpetas de juegos estan disponibles"
        return 0
    fi
    log "Automontaje: faltan estas carpetas: $(printf '%s' "$faltan" | tr '\n' ' ')"
    local discos; discos="$(discos_sin_montar)" || discos=""
    if [ -z "$discos" ]; then
        log "Automontaje: no hay ningun disco sin montar que probar" WARN
        return 0
    fi
    log "Automontaje: discos por probar: $(printf '%s' "$discos" | grep -c . || true)"

    # Se prueba a montar y se mira SI APARECE la carpeta que faltaba.
    #
    # Antes se comparaba la etiqueta del disco con la ruta de la carpeta, y
    # eso fallaba en cuanto el disco no tenia etiqueta o se montaba en una
    # ruta que no la incluia. Comprobar el resultado no depende de nombres:
    # o la carpeta aparece, o no.
    while IFS='|' read -r dev etq tipo tam; do
        [ -n "$dev" ] || continue
        mp="$(montar_disco "$dev")" || continue
        [ -n "$mp" ] || continue
        local sirve=0
        while IFS= read -r p; do
            [ -n "$p" ] && [ -d "$p" ] && sirve=1
        done <<EOFCF
$faltan
EOFCF
        if [ "$sirve" = 1 ]; then
            say "[+] Disco ${etq:-$dev} montado solo en $mp"
            montados=$((montados+1))
            # ¿queda alguna carpeta por aparecer? si no, se acabo
            local pendientes=""
            while IFS= read -r p; do
                [ -n "$p" ] && [ ! -d "$p" ] && pendientes="$pendientes$p
"
            done <<EOFCP
$faltan
EOFCP
            faltan="$pendientes"
            [ -n "$faltan" ] || break
        else
            # La carpeta no aparecio, pero puede que el disco SI sea el bueno
            # y udisks lo haya montado en otro sitio que la vez anterior
            # (pasa con NTFS y con etiquetas repetidas). Se busca dentro una
            # carpeta con el mismo nombre y se corrige la ruta guardada.
            local arreglado=0 base nueva
            while IFS= read -r p; do
                [ -n "$p" ] || continue
                base="${p##*/}"
                nueva="$(find "$mp" -maxdepth 2 -type d -name "$base" 2>/dev/null | head -n1)"
                if [ -n "$nueva" ]; then
                    log "Automontaje: la carpeta '$base' ahora esta en $nueva (antes $p)"
                    GAMES_PATHS_EXTRA="$(printf '%s' "${GAMES_PATHS_EXTRA:-}" \
                        | grep -vxF "$p" || true)"
                    [ "$GAMES_PATH" = "$p" ] && GAMES_PATH="$nueva" \
                        || GAMES_PATHS_EXTRA="${GAMES_PATHS_EXTRA:+$GAMES_PATHS_EXTRA
}$nueva"
                    save_settings
                    arreglado=1
                fi
            done <<EOFCA
$faltan
EOFCA
            if [ "$arreglado" = 1 ]; then
                say "[+] Disco ${etq:-$dev} montado en $mp (ruta actualizada)"
                montados=$((montados+1))
                faltan=""
                break
            fi
            log "Automontaje: $dev no contenia ninguna carpeta de juegos; se desmonta"
            udisksctl unmount -b "$dev" --no-user-interaction >/dev/null 2>&1
        fi
    done <<EOFCD
$discos
EOFCD
    [ "$montados" -gt 0 ] && sleep 1
    return 0
}

montar_discos_de_juegos() {
    # Si alguna carpeta de juegos no existe, es muy probable que su disco no
    # este montado: pasa a menudo en el modo Juego de SteamOS con discos
    # externos o una segunda unidad. Se ofrece montarlos aqui mismo, sin
    # tener que salir al escritorio.
    local p faltan="" 
    while IFS= read -r p; do
        [ -n "$p" ] || continue
        [ -d "$p" ] || faltan="$faltan$p
"
    done <<EOFCJ
$(games_paths)
EOFCJ
    [ -n "$faltan" ] || return 0

    local discos; discos="$(discos_sin_montar)" || discos=""
    if [ -z "$discos" ]; then
        # Falta la carpeta pero no hay ningun disco por montar: o el disco no
        # esta conectado, o esta montado en otro sitio. Antes esto se iba en
        # silencio y el usuario no entendia por que no salian sus juegos.
        ui_error "No aparecen estas carpetas de juegos:

$(printf '%s' "$faltan" | sed 's/^/  /')

No hay ningun disco pendiente de montar, asi que puede ser que
el disco no este conectado, o que se haya montado en otra ruta.

Comprueba la carpeta en Biblioteca y preferencias -> Carpetas
de juegos."
        return 1
    fi

    say "Carpetas de juegos que no estan disponibles:"
    printf '%s' "$faltan" | while IFS= read -r p; do [ -n "$p" ] && say "    $p"; done

    local opciones="" d dev etq tipo tam
    while IFS='|' read -r dev etq tipo tam; do
        [ -n "$dev" ] || continue
        opciones="$opciones${etq:-sin etiqueta}   [$tipo, $tam]   $dev
"
    done <<EOFD
$discos
EOFD
    local sel
    sel="$(IFS=$'\n'; set -f; menu "Falta alguna carpeta de juegos.
¿Montar uno de estos discos?" $opciones "No montar nada")" || return 0
    [ "$sel" = "No montar nada" ] && return 0

    dev="${sel##*   }"
    local mp
    if mp="$(montar_disco "$dev")" && [ -n "$mp" ]; then
        ui_info "Disco montado en:
$mp

Si tus juegos están ahí, añade esa carpeta en
Biblioteca y preferencias -> Carpetas de juegos."
        return 0
    fi
    ui_error "No se pudo montar $dev.

${MOUNT_ERROR:-sin detalle}

En el modo Juego, el sistema puede no dejar montar discos sin
autorización. Dos formas de resolverlo:

  - Monta el disco una vez desde el modo Escritorio. Muchos
    sistemas lo recuerdan y lo montan solos al arrancar.
  - O desconecta y vuelve a conectar el disco: SteamOS lo monta
    automáticamente al detectarlo."
    return 1
}

games_paths() {
    # Todas las carpetas de juegos: la principal y las adicionales.
    # Mucha gente tiene los juegos repartidos entre varios discos, asi que
    # GAMES_PATH sigue siendo la de siempre y GAMES_PATHS_EXTRA anade las
    # demas (una por linea).
    printf '%s\n' "$(abs_path "$GAMES_PATH")"
    [ -n "${GAMES_PATHS_EXTRA:-}" ] || return 0
    local p
    while IFS= read -r p; do
        [ -n "$p" ] || continue
        p="$(abs_path "$p")"
        [ -d "$p" ] || continue
        [ "$p" = "$(abs_path "$GAMES_PATH")" ] && continue   # no repetir
        printf '%s\n' "$p"
    done <<EOFGP
$GAMES_PATHS_EXTRA
EOFGP
    return 0
}

es_juego_carpeta() {
    # ¿Esta carpeta es un juego? Se acepta si:
    #   - acaba en .pc (formato de algunos juegos)
    #   - tiene autorun.cmd (estilo Batocera)
    #   - lleva dentro un drive_c (prefijo incluido)
    #   - tiene un lanzador .sh
    #   - contiene algun .exe/.bat (hasta 4 niveles: muchos juegos lo esconden
    #     en Binaries/Win64/ o similar)
    local d="$1"
    case "$(printf '%s' "$d" | tr 'A-Z' 'a-z') " in
        *.pc\ ) return 0 ;;
    esac
    [ -f "$d/autorun.cmd" ] && return 0
    [ -d "$d/drive_c" ] && return 0
    [ -n "$(find "$d" -maxdepth 1 -type f -name '*.sh' 2>/dev/null | head -n1)" ] && return 0
    # OJO con la profundidad: sin limite, una carpeta SIN ejecutable se
    # recorre entera. Con juegos de miles de ficheros y una biblioteca
    # grande, eso son minutos de espera al abrir la lista. Cuatro niveles
    # cubren de sobra los casos reales (Binaries/Win64/... incluido).
    [ -n "$(find "$d" -maxdepth 4 -type f \( -iname '*.exe' -o -iname '*.bat' \) \
            ! -ipath '*/windows/*' ! -ipath '*/system32/*' \
            -print -quit 2>/dev/null)" ] && return 0
    # Ultimo recurso, tambien acotado: si hay contenido que no sean imagenes
    # ni documentos, se ofrece igual. Mas vale que aparezca y no arranque,
    # que no aparecer y que el usuario no lo encuentre.
    [ -n "$(find "$d" -maxdepth 2 -type f ! -iname '*.png' ! -iname '*.jpg' \
            ! -iname '*.jpeg' ! -iname '*.txt' ! -iname '*.pdf' ! -iname '*.md' \
            -print -quit 2>/dev/null)" ] && return 0
    return 1
}

lista_juegos() {
    # Lista de juegos de TODAS las carpetas configuradas. Cada linea es la
    # ruta ABSOLUTA: con varias carpetas, un nombre relativo ya no basta para
    # saber de cual viene.
    local raiz d
    while IFS= read -r raiz; do
        [ -d "$raiz" ] || continue
        # archivos empaquetados
        find "$raiz" -maxdepth 3 -type f \
            \( -iname '*.wsquashfs' -o -iname '*.squashfs' -o -iname '*.dwarfs' \) \
            2>/dev/null
        # Carpetas que son un juego (incluidas las .pc). Solo se miran las
        # de PRIMER nivel: si no, las subcarpetas del propio juego ("bin",
        # "data"...) saldrian tambien como juegos sueltos.
        while IFS= read -r d; do
            [ -n "$d" ] || continue
            es_juego_carpeta "$d" && printf '%s\n' "$d"
        done <<EOFDIR
$(find "$raiz" -mindepth 1 -maxdepth 1 -type d ! -name '.*' 2>/dev/null)
EOFDIR
    done <<EOFRAIZ
$(games_paths)
EOFRAIZ
    return 0
}

juego_etiqueta() {
    # Como se muestra un juego en la lista. Si hay varias carpetas de juegos,
    # se anade de cual viene para poder distinguir dos con el mismo nombre.
    #
    # WP_N_RAICES lo calcula quien recorre la lista, UNA sola vez: antes se
    # contaban las carpetas por cada juego, con varios procesos cada vez.
    local ruta="$1" nom raiz base
    nom="${ruta##*/}"
    # Sin la extension: al usuario le interesa el nombre del juego, no si es
    # un .wsquashfs o un .dwarfs. Las carpetas .pc se dejan como estan, que
    # ahi el ".pc" forma parte del nombre.
    case "$nom" in
        *.wsquashfs|*.squashfs|*.dwarfs) nom="${nom%.*}" ;;
    esac
    if [ "${WP_N_RAICES:-$(games_paths | grep -c .)}" -gt 1 ]; then
        raiz="$(games_paths | while IFS= read -r r; do
                    case "$ruta/" in "$r"/*) printf '%s' "$r"; break ;; esac
                done)"
        base="$(basename "${raiz:-}")"
        [ -n "$base" ] && printf '%s   (%s)' "$nom" "$base" && return 0
    fi
    printf '%s' "$nom"
}

pick_squash() {
    # Elegir un juego. Si dentro se pide cambiar de vista (Select+X), se
    # cambia y se vuelve a abrir AQUI MISMO: quien llama no tiene que saber
    # nada de eso. Antes el marcador salia hacia fuera y se interpretaba como
    # una cancelacion, asi que se volvia al menu principal.
    local elegido
    while :; do
        elegido="$(pick_squash_una_vez)" || return $?
        case "$elegido" in
            "WPACT:VISTA|"*)
                # Tres vistas: lista -> rejilla vertical -> rejilla horizontal
                case "${GAMES_VIEW:-list}" in
                    list)   GAMES_VIEW=grid ;;
                    grid)   GAMES_VIEW=banner ;;
                    banner) GAMES_VIEW=cuadro ;;
                    *)      GAMES_VIEW=list ;;
                esac
                save_settings
                say "[+] Vista: $GAMES_VIEW"
                continue ;;
        esac
        printf '%s' "$elegido"
        return 0
    done
}

pick_squash_una_vez() {
    # Devuelve un wsquashfs de la biblioteca O una carpeta/exe suelto (navegador)
    # Ya no hace falta la entrada "juego suelto": las carpetas de las carpetas
    # de juegos configuradas aparecen solas en la lista.
    local list
    # Rutas absolutas: con varias carpetas de juegos, el nombre relativo ya no
    # identifica al juego. La etiqueta que se MUESTRA se calcula aparte.
    # Se cronometra cada fase. Con bibliotecas grandes abrir la lista puede
    # tardar mucho, y sin medirlo no hay forma de saber que parte es la lenta.
    local _t0 _t1 _n
    WP_N_RAICES="$(games_paths | grep -c . || echo 1)"
    export WP_N_RAICES
    _t0="$(date +%s)"
    local _crudo; _crudo="$(lista_juegos)"
    _t1="$(date +%s)"
    _n="$(printf '%s' "$_crudo" | grep -c . || true)"
    log "Biblioteca: $_n juegos encontrados en $((_t1-_t0))s"
    list="$(printf '%s' "$_crudo" | sort | sort_games)"
    _t0="$(date +%s)"
    log "Biblioteca: ordenada en $((_t0-_t1))s"
    # Biblioteca vacia: antes se volvia al menu principal SIN DECIR NADA, y
    # quien acababa de instalar WProton no entendia por que "Jugar" y
    # "Ajustes de un juego" no hacian nada.
    if [ -z "$(printf '%s' "$list" | tr -d '[:space:]')" ]; then
        ui_info "Todavia no hay juegos.

Tus carpetas de juegos:
$(games_paths | sed 's/^/  /')

Tienes tres formas de añadir juegos:

  - Copiar ahi tus .wsquashfs, o las carpetas de los juegos.
  - Menu principal -> Añadir un juego, para importar un zip, un
    rar, un .exe o una carpeta que este en otro sitio.
  - Si estan en otro disco: Biblioteca y preferencias -> Montar
    un disco, o -> Carpetas de juegos para añadir su ruta."
        return 1
    fi
    local sel
    export WP_ACTION_X=1                 # X = configurar el juego resaltado
    # "banner" es la misma rejilla con las caratulas horizontales
    # El proceso de menus lee la proporcion de la caratula al arrancar, y es
    # persistente: si solo se cambia la variable, la rejilla sigue saliendo
    # como antes. Al cambiar de/hacia la vista ancha hay que reiniciarlo.
    # La proporcion viaja en la peticion, asi que no hace falta reiniciar el
    # proceso de menus al cambiar de vista.
    local _aspecto _es_rejilla; _aspecto="$(vista_forma)"
    export WP_GRID_BANNER="$_aspecto"
    case "${GAMES_VIEW:-list}" in grid|banner|cuadro) _es_rejilla=1 ;; *) _es_rejilla=0 ;; esac
    if [ "$_es_rejilla" = 1 ] && pygame_available && [ -n "$list" ]; then
        pad_bridge_stop
        write_menu_pygame
        local man tmpsel rel gid2 t2 cov
        man="$(mktemp)"; tmpsel="$(mktemp)"
        while IFS= read -r rel; do
            gid2="$(game_id "$rel")"
            t2="$(juego_etiqueta "$rel")"; t2="${t2%.wsquashfs*}"
            t2="${t2%.squashfs}"; t2="${t2%.dwarfs}"
            # con la vista de caratulas anchas se pide la horizontal; si el
            # juego no la tiene, cover_for devuelve la vertical
            cov="$(cover_for "$gid2" "$_aspecto")" || cov=""
            local mt fv sc lp info=""
            mt="$(game_meta "$rel")"
            fv="${mt%%|*}"; mt="${mt#*|}"; lp="${mt%%|*}"; sc="${mt#*|}"
            [ "${sc:-0}" -gt 0 ] 2>/dev/null && info="$info$(fmt_playtime "$sc")"
            # OJO: nada de "|" aquí. El manifiesto usa | como separador de
            # columnas: al jugar aparecia la fecha y partia la linea, con lo
            # que la ruta de la carátula se perdia y el juego salia sin ella.
            [ -n "$lp" ] && info="${info:+$info - }${lp%% *}"
            local t3; t3="$t2$([ -n "$info" ] && printf '   [%s]' "$info")"
            t3="$(printf '%s' "$t3" | tr '|' '/')"     # el separador es sagrado
            printf '%s|%s|%s|%s\n' "$t3" "$cov" "$rel" "${fv:-0}" >> "$man"
        done <<EOF2
$list
EOF2
        # La rejilla tambien va por el SERVIDOR de menus: si no, abre una
        # ventana aparte (parpadeo) y no puede marcar favoritos con R1,
        # porque el fichero de favoritos viaja en la peticion.
        local favfileg; favfileg="$(mktemp)"
        menu_server_request grid "Elige un juego  [$GAMES_PATH]" "$tmpsel" "$man" \
            "" "${WP_ACTION_X:-}" "" "" "$favfileg" "$_aspecto"
        if [ $? = 9 ]; then
            PYGAME_HIDE_SUPPORT_PROMPT=1 SDL_JOYSTICK_ALLOW_BACKGROUND_EVENTS=1 \
                WP_FAV_FILE="$favfileg" \
                env -u LD_PRELOAD "$PY_BIN" "$MENU_PYGAME_PY" grid \
                "Elige un juego  [$GAMES_PATH]" "$tmpsel" "$man" >> "$LOG_FILE" 2>&1
        fi
        # favoritos marcados con R1 sobre la rejilla
        if [ -s "$favfileg" ]; then
            local fjg fgg
            log "Favoritos marcados en la rejilla: $(wc -l < "$favfileg")"
            while IFS= read -r fjg; do
                [ -n "$fjg" ] || continue
                fgg="$(awk -F'|' -v t="$fjg" '$1==t{print $3; exit}' "$man")"
                [ -n "$fgg" ] || { log "Favorito '$fjg' sin ruta en el manifiesto" WARN; continue; }
                fgg="$(game_id "$fgg")"
                load_profile "$fgg"
                FAVORITO=$((1-${FAVORITO:-0}))
                write_full_profile "$fgg"
                log "Favorito de $fgg: ${FAVORITO}"
            done < "$favfileg"
        fi
        sel="$(cat "$tmpsel")"; rm -f "$tmpsel" "$man" "$favfileg"
        unset WP_ACTION_X
        [ -z "$sel" ] && { log "GRID -> cancelado"; return 1; }
        log "GRID -> [$sel]"
        case "$sel" in
            "WPACT:"*)
                local acc="${sel%%|*}" rel="${sel#*|}"
                [ "$rel" = "__LOOSE__" ] && return 1
                printf '%s|%s' "$acc" "$rel"
                return 0 ;;
        esac
        if [ "$sel" = "__LOOSE__" ]; then
            browse_for_path "Juego suelto (carpeta o exe)" "$(browse_start "$HOME")" "play"
            return $?
        fi
        printf '%s' "$sel"
        return 0
    fi
    # Datos para el panel derecho: carátula, favorito, veces jugado, tiempo,
    # y si hay ficha descargada, el año y la nota. Un fichero aparte, para no
    # tocar la lista de nombres que se muestra.
    # Datos por juego. Las FICHAS no se leen aqui: se pasa su ruta y las lee
    # el helper, que es Python y entiende el JSON de Steam de verdad. Ademas
    # asi la lista se abre al momento aunque haya cien juegos con ficha.
    # La lista MUESTRA etiquetas legibles (el nombre del juego, y de que
    # carpeta viene si hay varias), pero por dentro trabaja con rutas
    # absolutas. El mapa guarda la correspondencia.
    local infofile mapfile etiquetas="" etq
    local rel3 gid3 cov3 mt3 fv3 sc3 pc3 fjson fhltb
    infofile="$(mktemp)"; mapfile="$(mktemp)"
    while IFS= read -r rel3; do
        [ -n "$rel3" ] || continue
        etq="$(juego_etiqueta "$rel3")"
        # La etiqueta es la clave para volver a la ruta. Al quitar la
        # extension pueden coincidir dos juegos (el mismo nombre en
        # .wsquashfs y en .dwarfs, por ejemplo): en ese caso se deja el
        # nombre completo del segundo, para no perder ninguno.
        if cut -f1 "$mapfile" 2>/dev/null | grep -qxF "$etq"; then
            etq="${rel3##*/}"
        fi
        printf '%s\t%s\n' "$etq" "$rel3" >> "$mapfile"
        etiquetas="$etiquetas$etq
"
        gid3="$(game_id "$rel3")"
        cov3="$(cover_for "$gid3" "${LIST_COVER:-vertical}")" || cov3=""
        mt3="$(game_meta "$rel3")"
        fv3="${mt3%%|*}"; mt3="${mt3#*|}"; sc3="${mt3#*|}"
        pc3="$(profile_get "$gid3" PLAY_COUNT)" || pc3=""
        fjson="$DATOS_DIR/${gid3}.info.json"; [ -s "$fjson" ] || fjson=""
        fhltb="$DATOS_DIR/${gid3}.hltb";      [ -s "$fhltb" ] || fhltb=""
        printf '%s|%s|%s|%s|%s|%s|%s\n' \
            "$etq" "$cov3" "${fv3:-0}" "${pc3:-0}" "${sc3:-0}" "$fjson" "$fhltb" \
            >> "$infofile"
    done <<EOFINFO
$list
EOFINFO
    local favfile; favfile="$(mktemp)"
    _t1="$(date +%s)"
    log "Biblioteca: datos de los juegos en $((_t1-_t0))s"
    export WP_LIST_INFO="$infofile" WP_FAV_FILE="$favfile"
    # shellcheck disable=SC2046
    local titulo_lista="Elige un juego  [$GAMES_PATH]"
    [ "$(games_paths | wc -l)" -gt 1 ] && \
        titulo_lista="Elige un juego  [$(games_paths | wc -l) carpetas]"
    # shellcheck disable=SC2046
    sel="$(IFS=$'\n'; set -f; menu "$titulo_lista" $(printf '%s' "$etiquetas"))"
    # OJO: $? hay que leerlo INMEDIATAMENTE despues del menu. Al colar aqui la
    # limpieza del fichero temporal, "src" recogia el resultado de "rm" (que
    # siempre es 0), asi que pulsar B parecia una eleccion valida y WProton
    # intentaba lanzar un juego vacio.
    local src=$?
    # Favoritos marcados con R1 durante el menu: el cambio ya se vio en
    # pantalla al instante; aqui solo se guarda en el perfil de cada juego.
    if [ -s "$favfile" ]; then
        local fjuego fgid fruta
        log "Favoritos marcados en el menu: $(wc -l < "$favfile")"
        while IFS= read -r fjuego; do
            [ -n "$fjuego" ] || continue
            fruta="$(awk -F'\t' -v e="$fjuego" '$1==e{print $2; exit}' "$mapfile")"
            if [ -z "$fruta" ]; then
                log "Favorito '$fjuego': no se encontro su ruta en el mapa" WARN
                continue
            fi
            fjuego="$fruta"
            fgid="$(game_id "$fjuego")"
            load_profile "$fgid"
            FAVORITO=$((1-${FAVORITO:-0}))
            write_full_profile "$fgid"
            log "Favorito de $fgid: ${FAVORITO}"
        done < "$favfile"
    fi
    # De etiqueta a ruta real. Tambien cuando viene con marcador de accion
    # (X, L1, R1): el helper devuelve la etiqueta, no la ruta.
    local sel_ruta="" sel_acc="" sel_txt="$sel"
    case "$sel" in
        "WPACT:"*) sel_acc="${sel%%|*}"; sel_txt="${sel#*|}" ;;
    esac
    [ -n "$sel_txt" ] && \
        sel_ruta="$(awk -F'\t' -v e="$sel_txt" '$1==e{print $2; exit}' "$mapfile")"
    rm -f "$infofile" "$favfile" "$mapfile"; unset WP_LIST_INFO WP_FAV_FILE
    if [ "$src" != 0 ]; then unset WP_ACTION_X; return "$src"; fi
    unset WP_ACTION_X
    if [ -n "$sel_acc" ]; then

        printf '%s|%s' "$sel_acc" "${sel_ruta:-$sel_txt}"
        return 0
    fi
    printf '%s' "${sel_ruta:-$sel}"
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

cfg_rendimiento_menu() {
    # Ajustes que casi nunca hay que tocar: se sacaron del menu principal del
    # juego, que habia llegado a 42 lineas y era incomodo de recorrer con el
    # mando. Aqui se guardan igual: al volver, el perfil se escribe entero.
    local gid="$1" squash="${2:-}" sel gs_row bat_row
    while :; do
        gs_row="Gamescope anidado: $(onoff "${NESTED_GAMESCOPE:-0}")"
        bat_row="Wayland nativo: $(onoff "$WAYLAND")"
        sel="$(menu "Rendimiento y compatibilidad - $gid" \
            "MangoHud: $(onoff "$MANGOHUD")" \
            "GameMode: $(onoff "$GAMEMODE")" \
            "Fsync: $(onoff "$FSYNC")" \
            "Esync: $(onoff "$ESYNC")" \
            "DXVK Async + GPL: $(onoff "$DXVK_ASYNC")" \
            "WineD3D (OpenGL, juegos viejos): $(onoff "$WINED3D")" \
            "FSR escalado pantalla completa: $(onoff "$FSR")" \
            "LAA (32bit +2GB RAM): $(onoff "$LAA")" \
            "NTsync (sincronizacion por kernel): $(onoff "${NTSYNC:-0}")$([ -e /dev/ntsync ] || printf ' [sin /dev/ntsync]')" \
            "Arreglo mando SteamOS (Steam Input): $(onoff "${PAD_STEAMFIX:-0}")" \
            "$bat_row" \
            "Gamescope: ${GAMESCOPE:-OFF}" \
            "$gs_row" \
            "DLL overrides: ${DLL_OVERRIDES:-ninguno}" \
            "Idioma del juego: ${GAME_LANG:-sistema}" \
            "Variables extra: ${EXTRA_ENV:-ninguna}" \
            "<< Volver")" || return 0
        case "$sel" in
            "<< Volver") return 0 ;;
            *) cfg_aplicar "$sel" "$gid" "$squash" ;;
        esac
    done
}

cfg_prefijo_menu() {
    # Todo lo que toca el prefijo de Wine, junto y en un sitio logico
    local gid="$1" squash="${2:-}" sel
    while :; do
        sel="$(menu "Herramientas del prefijo - $gid" \
            "Abrir winecfg" \
            "Abrir winetricks" \
            "Instalar dgVoodoo2 (DX1-9/Glide en juegos viejos)" \
            "Configurar dgVoodoo (Cpl)" \
            "Instalar OptiScaler (FSR/DLSS/XeSS upscaling)" \
            "Borrar prefijo (reinstala DLLs)" \
            "<< Volver")" || return 0
        case "$sel" in
            "<< Volver") return 0 ;;
            *) cfg_aplicar "$sel" "$gid" "$squash" ;;
        esac
    done
}

cfg_aplicar() {
    # Aplica UNA opcion elegida en cualquiera de los menus de
    # configuracion del juego (principal, rendimiento o prefijo).
    # Estaba dentro de game_config_menu; se saco fuera para que los
    # submenus pudieran reutilizarlo sin duplicar nada.
    local sel="$1" gid="$2" squash="${3:-}"
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
        "Carátula: elegir"*)
            caratula_manual "$gid" ;;
        "Carátula: buscar en SteamGridDB"*)
            sgdb_buscar_manual "$gid" || true ;;
        "Ficha del juego"*)
            ficha_mostrar "$gid" "$squash" ;;
        "Borrar la configuración de este juego"*)
            if perfil_borrar "$gid"; then
                return 0            # ya no hay nada que configurar aqui
            fi ;;
        "Acceso directo en el escritorio"*)
            acceso_directo_juego "$squash" "$gid" \
                && ui_info "Acceso directo creado en el escritorio.

Si el icono no aparece al momento, actualiza la vista del
escritorio (F5)." ;;
        "Empaquetar con su prefijo"*)
            if [ -d "$squash" ]; then
                package_con_prefijo "$squash" "$gid" "${EXE_PATH:-}"
            elif [ "$MOUNT_OK" = 1 ] && [ -n "$MOUNT_POINT" ]; then
                package_con_prefijo "$MOUNT_POINT" "$gid" "${EXE_PATH:-}"
            else
                ui_error "Para empaquetar con el prefijo hace falta el juego
en carpeta o montado.

Si el juego ya es un .wsquashfs, juégalo una vez y vuelve a
entrar aquí: estará montado y se podrá empaquetar."
            fi ;;
        "Buscar en la base de umu"*)
            if umudb_sugerir "$gid"; then
                write_full_profile "$gid"
            else
                ui_info "No se ha encontrado '$gid' en la base de datos de umu.

Puedes poner el identificador a mano en GAMEID si lo conoces:
https://umu.openwinecomponents.org"
            fi ;;
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
            PAD_STEAMFIX=$((1-${PAD_STEAMFIX:-0})); write_full_profile "$gid" ;;
        "Gamescope anidado"*)
            NESTED_GAMESCOPE=$((1-${NESTED_GAMESCOPE:-0}))
            write_full_profile "$gid"
            [ "${NESTED_GAMESCOPE}" = 1 ] && ui_info "Gamescope anidado activado para este juego.
Ayuda a volver al menu en modo Juego, pero algunos juegos
avisan de 'Hooking has failed' o van a tirones. Si pasa,
desactivalo aquí mismo." ;;
        "Mando Sony"*)
            # Tres estados, igual que el resto de opciones del mando.
            case "${PAD_SONY:-auto}" in
                auto) PAD_SONY=1 ;;
                1)    PAD_SONY=0 ;;
                *)    PAD_SONY=auto ;;
            esac
            write_full_profile "$gid"
            say "[+] Mando Sony: $(pad_sony_label)" ;;
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
La configuración de '$gid' se conserva para el wsquashfs."
                if ui_ask "Jugar ahora desde el wsquashfs?"; then
                    launch_game "$PACKED_OUT" "auto"
                fi
                [ -d "$squash" ] || return 0   # la carpeta ya no existe
            fi ;;
        "Añadir este juego a Steam")
            add_game_to_steam "$squash" "$gid" ;;
        "Favorito:"*)
            FAVORITO=$((1-${FAVORITO:-0})); write_full_profile "$gid" ;;
        "Notas:"*)
            NOTAS="$(ask_text "Notas de este juego (argumentos que necesita, runner recomendado...)" "${NOTAS:-}")"
            write_full_profile "$gid" ;;
        "Partidas guardadas"*) backup_menu "$gid" ;;
        "Comprobar el archivo"*)
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
        "Estadísticas:"*)
            if [ "${PLAY_COUNT:-0}" -gt 0 ]; then
                ui_ask "Partidas: ${PLAY_COUNT:-0}
Tiempo total: $(fmt_playtime "${PLAY_SECONDS:-0}")
Última vez: ${LAST_PLAYED:-nunca}

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
                "Estilo de botones: $([ "${KEYS_ESTILO:-xbox}" = nintendo ] && printf 'Nintendo / Batocera' || printf 'Xbox')" \
                "<< Volver")" || kmenu=""
            case "$kmenu" in
                "Estilo de botones:"*)
                    # Los .keys hechos en Batocera nombran los botones al
                    # estilo Nintendo: su "A" es el de la derecha y su "B" el
                    # de abajo, al reves que en el estilo Xbox. Si en el juego
                    # los botones salen cambiados, se cambia aqui.
                    if [ "${KEYS_ESTILO:-xbox}" = nintendo ]; then
                        KEYS_ESTILO=xbox
                    else
                        KEYS_ESTILO=nintendo
                    fi
                    write_full_profile "$gid"
                    ui_info "Estilo de botones: $KEYS_ESTILO

  Xbox      A abajo, B derecha (mandos de PC)
  Nintendo  A derecha, B abajo (Batocera y consolas portatiles)

Si los botones salen cambiados en el juego, prueba el otro." ;;
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
                return 0
            fi
            local pfx; pfx="$(prefix_path "$gid")"
            ui_ask "Borrar el prefijo $(basename "$pfx")?$([ "$PREFIX_MODE" = shared ] && printf '\nOJO: es el COMPARTIDO, afecta a todos los juegos que lo usan.')" \
                && { rm -rf "$pfx"; ui_info "Prefijo borrado."; } ;;
        "Borrar saves"*)
            if [ -d "$squash" ]; then
                ui_info "Este juego es una carpeta suelta: no usa overlay.
Los saves viven en la propia carpeta o en el prefijo."
                return 0
            fi
            ui_ask "SEGURO? Se borraran las partidas guardadas en el overlay de $gid" \
                && { rm -rf "${OVERLAY_BASE:?}/$gid/upper"; ui_info "Overlay borrado."; } ;;
        "<< Volver") return ;;
    esac

}

game_config_menu() {
    # $1 = juego (wsquashfs o carpeta), $2 = gid explicito (opcional: al venir
    # del flujo de importacion, el perfil es el del nombre limpio del juego)
    local squash="$1"
    local gid; gid="${2:-$(game_id "$squash")}"

    # Juego nuevo: mirar si la base de umu conoce este juego. Su identificador
    # es lo que permite a protonfixes aplicar los arreglos concretos, asi que
    # conviene proponerlo antes que nada.
    # La base de umu YA NO se consulta al abrir la configuracion.
    #
    # Se hacia para proponer el identificador del juego, pero va por red y era
    # lo que hacia que pulsar X sobre un juego nuevo tardara una eternidad. En
    # la practica no acerto ni una vez en las pruebas: los juegos que hacian
    # falta no estaban en la base. Sigue disponible cuando se quiera, en
    # "Buscar en la base de umu" dentro de los ajustes del juego.
    # Si nunca se configuro: mirar si la comunidad ya tiene una configuracion
    # para este juego antes de preguntarle nada al usuario.
    #
    # OJO: antes, si la descarga salia bien, esto hacia "return 0" y cerraba
    # el menu de ajustes. El usuario venia justo a configurar el juego y se
    # encontraba de vuelta en el menu principal. Ahora se sigue adelante y se
    # muestra la configuracion, ya con el perfil de la comunidad cargado.
    if ! profile_exists "$gid"; then
        local _t1; _t1="$(date +%s)"
        loading_say "Buscando un perfil de la comunidad para '$gid'..."
        community_offer_for "$gid" || true
        loading_clear
        log "Configurar $gid: perfiles de la comunidad tardaron $(( $(date +%s) - _t1 ))s"
    fi
    # Si nunca se configuro, pasar por el asistente primero.
    #
    # OJO: si el usuario CANCELA el asistente, antes se volvia al menu
    # principal sin mostrar la configuracion. Y como no quedaba perfil, a la
    # vez siguiente pasaba lo mismo: no habia forma de llegar nunca a la
    # pantalla de ajustes. Ahora, al cancelar, se crea un perfil con los
    # valores por defecto y se entra igualmente: el usuario habia pedido
    # justamente eso, configurar el juego.
    if ! profile_exists "$gid"; then
        acquire_game_root "$squash" "$gid" ro
        local ro="$MOUNT_POINT"
        if ! first_run_wizard "$gid" "$ro"; then
            release_game_root
            profile_defaults
            write_full_profile "$gid"
            say "[i] Asistente cancelado: se entra a los ajustes con los valores por defecto"
        else
            release_game_root
        fi
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
        sel="$(menu "Configuración de: $gid" \
            ">> JUGAR AHORA <<" \
            "Runner (Proton/Wine): ${RUNNER:-auto (último GE-Proton)}" \
            "Ejecutable: ${EXE_OVERRIDE:-auto (autorun.cmd / escaneo)}" \
            "Argumentos: ${ARGS_OVERRIDE:-ninguno}" \
            "Prefijo: $(prefix_label)" \
            "GAMEID (protonfixes): $GAMEID" \
            "Buscar en la base de umu (identificador automático)" \
            "Carátula: elegir una imagen (vertical u horizontal)" \
            "Carátula: buscar en SteamGridDB por nombre" \
            "Ficha del juego (año, editor, notas de la crítica)" \
            "Empaquetar con su prefijo (archivo autosuficiente)" \
            "Acceso directo en el escritorio" \
            "Borrar la configuración de este juego" \
            "Mando via SDL (DualSense como Xbox): $(pad_sdl_label)" \
            "Mando Sony (DualSense/DS4): $(pad_sony_label)" \
            "Mapeador .keys: $kstat" \
            "Rendimiento y compatibilidad >>" \
            "Herramientas del prefijo >>" \
            "Favorito: $(onoff "${FAVORITO:-0}")" \
            "Notas: ${NOTAS:-(ninguna)}" \
            "Estadísticas: $(stats_line)" \
            "Partidas guardadas: copias y restauracion" \
            "Comprobar el archivo y ver cuanto ocupa" \
            "$pack_row" \
            "$([ "${IS_GAMESCOPE:-0}" = 1 ] \
                && printf 'Añadir este juego a Steam (solo en modo Escritorio)' \
                || printf 'Añadir este juego a Steam')" \
            "Repetir asistente de primera ejecucion" \
            "Borrar saves del overlay (upper/)" \
            "<< Volver")" || return

        case "$sel" in
            "<< Volver") write_full_profile "$gid"; return 0 ;;
            "Rendimiento y compatibilidad >>")
                cfg_rendimiento_menu "$gid" "$squash"; continue ;;
            "Herramientas del prefijo >>")
                cfg_prefijo_menu "$gid" "$squash"; continue ;;
        esac
        cfg_aplicar "$sel" "$gid" "$squash"
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
        "Jugar al último:"*)
            play_any "$LAST_GAME" ;;
        "WPACT:CONFIG|"*)
            # X sobre "Jugar al ultimo": configurar ESE juego sin tener que
            # abrir la lista entera, que con muchos juegos tarda.
            local gx="${sel#WPACT:CONFIG|}"
            case "$gx" in
                *"Jugar al último"*)
                    [ -n "$LAST_GAME" ] && [ -e "$LAST_GAME" ] \
                        && game_config_menu "$LAST_GAME" \
                        || ui_error "No hay ningun juego reciente." ;;
                *) : ;;
            esac ;;
        "Jugar"*)
            # Los favoritos se marcan DENTRO del menu (R1) y se guardan al
            # salir: no hay que reabrir nada.
            local g; g="$(pick_squash)" && play_or_config "$g" ;;
        "Añadir un juego"*)
            local imp=""
            if pygame_available; then
                imp="$(browse_for_path "Importar juego (A: entrar/elegir, B: volver)" "$(browse_start "$HOME")" "importar")" || imp=""
            elif [ "$HAS_ZENITY" = 1 ]; then
                pad_bridge_start
                imp="$(zenity --file-selection --title="Elige zip/7z/rar/exe o entra en la carpeta" 2>/dev/null)"
            else
                imp="$(ask_text "Ruta del archivo/carpeta a importar" "")"
            fi
            if [ -n "$imp" ]; then
                case "$imp" in
                    *.exe|*.EXE|*.bat|*.BAT|*.cmd|*.CMD) package_exe "$imp" ;;
                    *) if [ -d "$imp" ]; then package_dir "$imp"; else import_input "$imp"; fi ;;
                esac
            fi ;;
        "Instalar librerias"*) redist_target_menu ;;
        "Ajustes de un juego"*)
            local g2
            if g2="$(pick_squash)"; then
                g2="$(wpact_ruta "$g2")" || return 0
                game_config_menu "$g2"
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
        "Añadir WProton a Steam"*) anadir_wproton_a_steam || true ;;
        "Cambiar las imágenes"*)   cambiar_imagenes_steam || true ;;
        "Probar el mando"*) probar_mando ;;
        "Crear un .keys de ejemplo"*)
            ui_info "Ejemplo creado en:
$(keys_ejemplo_crear)

Trae dos combinaciones:
  Select + Y    -> Alt+Tab (recuperar el foco)
  L3 + R3       -> Alt+F4  (cerrar el juego)

Para usarlo en un juego, copialo junto a el con el mismo nombre
y la extension .keys. Por ejemplo:
  Mi Juego.wsquashfs  ->  Mi Juego.wsquashfs.keys" ;;
        "Arreglar permisos del mando"*) arreglar_permisos_mando ;;
        "Instalar evdev"*)
            if instalar_evdev; then
                ui_info "evdev listo.

Ya puedes usar ficheros .keys para traducir el mando a teclado
en los juegos que no lo soportan."
            else
                ui_error "No se pudo instalar evdev.

Mira el registro. Como ultimo recurso, copia una carpeta
evmapy/ con el modulo ya compilado a la raiz de WProton."
            fi ;;
        "Datos de duración"*) hltb_instalar ;;
        "Descargar herramientas FUSE"*)
            rm -f "$RUNTIME_DIR/.fuse_tools_try"   # permitir reintentar
            SQUASHFUSE_BIN=""; OVERLAYFS_BIN=""
            setup_fuse_tools
            SQUASHFUSE_BIN="$(resolve_tool squashfuse)"
            OVERLAYFS_BIN="$(resolve_tool fuse-overlayfs)"
            ui_info "squashfuse:     ${SQUASHFUSE_BIN:-NO disponible}
$(tool_is_ours "$SQUASHFUSE_BIN" && printf '  (copia propia, portable)' || printf '  (del sistema)')
fuse-overlayfs: ${OVERLAYFS_BIN:-NO disponible}
$(tool_is_ours "$OVERLAYFS_BIN" && printf '  (copia propia, portable)' || printf '  (del sistema)')" ;;
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
            [ -z "$vers" ] && { ui_info "No hay runners instalados."; return 0; }
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
        "Tamaño de la letra:"*)
            local fsz
            fsz="$(menu "Tamaño de la letra en los menus" \
                "Normal" \
                "Grande (recomendado en consolas portatiles)" \
                "Muy grande" \
                "<< Volver")" || fsz=""
            case "$fsz" in
                Normal*)      FONT_SCALE=1.0 ;;
                Grande*)      FONT_SCALE=1.25 ;;
                "Muy grande"*) FONT_SCALE=1.5 ;;
                *) fsz="" ;;
            esac
            if [ -n "$fsz" ]; then
                export WP_FONT_SCALE="$FONT_SCALE"
                save_settings
            menu_server_reiniciar
                ui_info "Tamaño de letra: $(font_label)"
            fi ;;
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
                    save_settings
                    menu_server_reiniciar
                    ui_info "Tema activado: $THEME" ;;
            esac ;;
        "Espacio en disco") disk_menu ;;
        "Copia de tu configuración"*) config_menu ;;
        "Biblioteca y preferencias") library_menu ;;
        "Runners y herramientas"*) tools_menu ;;
        "Carátulas y perfiles"*) media_menu ;;
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
        "Carátulas por fila:"*)
            local gc
            gc="$(menu "Cuántas carátulas por fila en la rejilla" \
                "Automático (según el tamaño de la pantalla)" \
                "4 - carátulas grandes" \
                "5" \
                "6" \
                "7" \
                "8 - carátulas pequeñas, más juegos a la vista" \
                "<< Volver")" || gc=""
            case "$gc" in
                "Automático"*) GRID_COLS=0 ;;
                [0-9]*)        GRID_COLS="${gc%% *}" ;;
                *)             gc="" ;;
            esac
            if [ -n "$gc" ]; then
                export WP_GRID_COLS="$GRID_COLS"
                save_settings
            menu_server_reiniciar
                ui_info "Carátulas por fila: $(grid_cols_label)"
            fi ;;
        "Ordenar juegos por:"*)
            local so
            so="$(menu "Como ordenar la lista de juegos" \
                "nombre - alfabetico" \
                "recientes - los últimos jugados primero" \
                "jugados - los de más tiempo primero" \
                "<< Volver")" || so=""
            case "$so" in
                nombre*|recientes*|jugados*)
                    GAMES_SORT="${so%% *}"; save_settings
                    ui_info "Orden: $GAMES_SORT (los favoritos van siempre primero)" ;;
            esac ;;
        "Carátula en la vista de lista:"*)
            case "${LIST_COVER:-vertical}" in
                vertical) LIST_COVER=wide ;;
                wide)     LIST_COVER=43 ;;
                *)        LIST_COVER=vertical ;;
            esac
            save_settings ;;
        "Vista de juegos:"*)
            case "${GAMES_VIEW:-list}" in
                list)   GAMES_VIEW=grid ;;
                grid)   GAMES_VIEW=banner ;;
                banner) GAMES_VIEW=cuadro ;;
                *)      GAMES_VIEW=list ;;
            esac
            save_settings ;;
        "Perfiles de la comunidad"*) community_menu ;;
        "Perfiles guardados"*)       perfiles_menu ;;
        "Descargar carátulas"*)
            sgdb_download_covers ;;
        "Carpetas de juegos"*) carpetas_juegos_menu ;;
        "Montar un disco"*)    montar_disco_manual || true ;;
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
        "Detener Wine y liberar los juegos montados") kill_all ;;
        "Buscar actualizaciones"*) self_update ;;
        "Ver el registro de la última sesión")
            if [ "$HAS_ZENITY" = 1 ]; then
                zenity --text-info --title="WProton log" --filename="$LOG_FILE" \
                       --width=820 --height=620 2>/dev/null
            elif pygame_available; then
                local loglines
                loglines="$(tail -n 60 "$LOG_FILE" | grep -v '^$')"
                # shellcheck disable=SC2046
                (IFS=$'\n'; set -f; menu "Último log (B para volver)" $loglines) >/dev/null 2>&1 || true
            else
                tail -n 50 "$LOG_FILE" >&2
            fi ;;
        "Salir") exit 0 ;;
    esac
    return 0
}

carpetas_juegos_menu() {
    # Gestion de las carpetas de juegos: la principal y las adicionales, para
    # quien tiene los juegos repartidos entre varios discos.
    local sel p n
    while :; do
        n="$(games_paths | wc -l)"
        sel="$(IFS=$'\n'; set -f; menu "Carpetas de juegos ($n)" \
            "Carpeta principal: $GAMES_PATH" \
            "Añadir otra carpeta..." \
            "Montar un disco..." \
            $(games_paths | tail -n +2 | sed 's/^/Quitar: /') \
            "<< Volver")" || return 0
        case "$sel" in
            "<< Volver") return 0 ;;
            "Carpeta principal:"*)
                p="$(pick_dir "Carpeta principal de juegos" "$GAMES_PATH")" || continue
                [ -d "$p" ] && { GAMES_PATH="$p"; save_settings; } ;;
            "Montar un disco"*) montar_disco_manual || true ;;
            "Añadir otra carpeta"*)
                p="$(pick_dir "Otra carpeta con juegos" "$(browse_start "$HOME")")" || continue
                [ -d "$p" ] || continue
                p="$(abs_path "$p")"
                if games_paths | grep -qxF "$p"; then
                    ui_info "Esa carpeta ya estaba en la lista."
                    continue
                fi
                GAMES_PATHS_EXTRA="${GAMES_PATHS_EXTRA:+$GAMES_PATHS_EXTRA
}$p"
                save_settings
                ui_info "Carpeta añadida:
$p

$(find "$p" -maxdepth 3 \( -iname '*.wsquashfs' -o -iname '*.squashfs' \
   -o -iname '*.dwarfs' \) 2>/dev/null | wc -l) juego(s) empaquetado(s) encontrado(s)." ;;
            "Quitar: "*)
                p="${sel#Quitar: }"
                GAMES_PATHS_EXTRA="$(printf '%s' "$GAMES_PATHS_EXTRA" | grep -vxF "$p" || true)"
                WP_BORRAR_CARPETAS=1 save_settings
                unset WP_BORRAR_CARPETAS
                say "[+] Carpeta quitada de la lista: $p" ;;
        esac
    done
}

list_cover_label() {
    case "${LIST_COVER:-vertical}" in
        wide) printf 'panorámica' ;;
        43)   printf '4:3' ;;
        *)    printf 'vertical (2:3)' ;;
    esac
}

vista_label() {
    case "${GAMES_VIEW:-list}" in
        grid)   printf 'rejilla vertical (2:3)' ;;
        banner) printf 'rejilla panorámica' ;;
        cuadro) printf 'rejilla 4:3' ;;
        *)      printf 'lista' ;;
    esac
}

vista_forma() {
    # Que forma de caratula usa cada vista
    case "${GAMES_VIEW:-list}" in
        banner) printf 'wide' ;;
        cuadro) printf '43' ;;
        grid)   printf 'vertical' ;;
        *)      printf '%s' "${LIST_COVER:-vertical}" ;;
    esac
}

library_menu() {
    # Todo lo que afecta a como se ve y se ordena la biblioteca
    local sel
    while true; do
        sel="$(menu "Biblioteca y preferencias" \
            "Carpetas de juegos ($(games_paths | wc -l))" \
            "Montar un disco (USB, disco externo...)" \
            "Vista de juegos: $(vista_label)" \
            "Carátula en la vista de lista: $(list_cover_label)" \
            "Carátulas por fila: $(grid_cols_label)" \
            "Ordenar juegos por: ${GAMES_SORT:-nombre}" \
            "Formato al empaquetar: ${PACK_FORMAT:-wsquashfs}" \
            "Tema de los menus: $THEME" \
            "Tamaño de la letra: $(font_label)" \
            "Idioma: ${LANGUAGE:-es}" \
            "Copia de tu configuración (exportar / importar)" \
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
            "Actualizar GE-Proton a la última" \
            "Borrar un runner" \
            "Instalar librerias de Windows (vcredist, PhysX...)" \
            "Actualizar umu-launcher" \
            "Instalar/actualizar Python portable + pygame" \
            "Descargar extractores GOG (innoextract + innounp)" \
            "Descargar herramientas FUSE portables (squashfuse, overlayfs)" \
            "Añadir WProton a Steam (con su imagen)" \
            "Cambiar las imágenes de WProton en Steam" \
            "Probar el mando (ver que botones llegan)" \
            "Crear un .keys de ejemplo (Alt+Tab, Alt+F4)" \
            "Arreglar permisos del mando (hidraw)" \
            "Instalar evdev (para los ficheros .keys)" \
            "Datos de duración de partida (HowLongToBeat)" \
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
        sel="$(menu "Carátulas y perfiles de la comunidad" \
            "Descargar carátulas (SteamGridDB)" \
            "Perfiles de la comunidad (juegos que necesitan ajustes)" \
            "Perfiles guardados (ver y borrar)" \
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
            opts+=("Jugar al último: $lg")
        fi
        opts+=("Añadir un juego (zip, rar, exe o carpeta)" \
               "Ajustes de un juego" \
               "Biblioteca y preferencias" \
               "Runners y herramientas [$nrunners runners]" \
               "Carátulas y perfiles de la comunidad" \
               "Espacio en disco" \
               "Detener Wine y liberar los juegos montados" \
               "Ver el registro de la última sesión" \
               "Buscar actualizaciones [v$WPROTON_VERSION]" \
               "Salir")
        local sel
        # Con X se configura el juego de "Jugar al ultimo" sin abrir la lista
        # entera, que con muchos juegos tarda en cargar.
        [ -n "$LAST_GAME" ] && [ -e "$LAST_GAME" ] && export WP_ACTION_X=1
        sel="$(menu "WProton v$WPROTON_VERSION - Menu principal" "${opts[@]}")"
        local mrc=$?
        unset WP_ACTION_X
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
    # $1 = "silencioso" para no mostrar el aviso final (cuando ya estamos
    # dentro de otro flujo que va a informar por su cuenta)
    say "Deteniendo Wine y desmontando todo..."
    pkill -f 'wineserver' 2>/dev/null
    pkill -f 'winedevice' 2>/dev/null
    sleep 1
    sweep_stale_mounts
    [ "${1:-}" = silencioso ] || ui_info "Todo desmontado."
    return 0
}

carpeta_escritorio() {
    # Donde esta el escritorio de este usuario. En español suele ser
    # "Escritorio" y en ingles "Desktop": se pregunta al sistema en vez de
    # adivinar, y si no sabe contestar se prueban los nombres habituales.
    local d
    if command -v xdg-user-dir >/dev/null 2>&1; then
        d="$(xdg-user-dir DESKTOP 2>/dev/null)"
        [ -n "$d" ] && [ -d "$d" ] && [ "$d" != "$HOME" ] && { printf '%s' "$d"; return 0; }
    fi
    for d in "$HOME/Escritorio" "$HOME/Desktop" "$HOME/Àrea de treball" "$HOME/Mahaigaina"; do
        [ -d "$d" ] && { printf '%s' "$d"; return 0; }
    done
    return 1
}

crear_acceso_directo() {
    # $1 = nombre visible, $2 = orden a ejecutar, $3 = icono (opcional),
    # $4 = comentario (opcional)
    local nombre="$1" orden="$2" icono="${3:-}" coment="${4:-}"
    local esc; esc="$(carpeta_escritorio)" || {
        ui_error "No se encontro la carpeta del escritorio."
        return 1; }
    # nombre de fichero sin espacios ni barras
    local base; base="$(printf '%s' "$nombre" | tr ' /' '__' | tr -cd 'A-Za-z0-9._-')"
    local dst="$esc/${base:-wproton}.desktop"
    {
        printf '[Desktop Entry]\n'
        printf 'Type=Application\n'
        printf 'Name=%s\n' "$nombre"
        [ -n "$coment" ] && printf 'Comment=%s\n' "$coment"
        printf 'Exec=%s\n' "$orden"
        printf 'Path=%s\n' "$BASE_DIR"
        [ -n "$icono" ] && [ -f "$icono" ] && printf 'Icon=%s\n' "$icono"
        printf 'Terminal=false\n'
        printf 'Categories=Game;\n'
        printf 'StartupNotify=true\n'
    } > "$dst" || { ui_error "No se pudo escribir el acceso directo"; return 1; }
    chmod +x "$dst" 2>/dev/null
    # KDE y GNOME piden que el fichero este marcado como "de confianza"
    command -v gio >/dev/null 2>&1 && \
        gio set "$dst" metadata::trusted true 2>/dev/null
    say "[+] Acceso directo creado: $dst"
    return 0
}

icono_wproton() {
    # Icono de WProton para el acceso directo. Si no esta descargado se
    # intenta traer; si no hay forma, el acceso se crea sin icono (mejor eso
    # que no crearlo).
    local arte="$RUNTIME_DIR/arte"
    [ -s "$arte/wproton_icono.png" ] || arte_conseguir >/dev/null 2>&1
    [ -s "$arte/wproton_icono.png" ] && printf '%s' "$arte/wproton_icono.png"
    return 0
}

acceso_directo_wproton() {
    local self; self="$(readlink -f "$0")"
    crear_acceso_directo "WProton" "\"$self\"" "$(icono_wproton)" \
        "Lanzador de juegos de Windows para Linux"
}

acceso_directo_juego() {
    # $1 = ruta del juego, $2 = gid
    local juego="$1" gid="$2" nombre icono self
    self="$(readlink -f "$0")"
    nombre="$(basename "$juego")"
    nombre="${nombre%.wsquashfs}"; nombre="${nombre%.squashfs}"; nombre="${nombre%.dwarfs}"
    icono="$(cover_for "$gid")" || icono=""
    crear_acceso_directo "$nombre" "\"$self\" \"$(readlink -f "$juego")\"" \
        "$icono" "Jugar con WProton"
}

first_run_games_path() {
    # Primera vez que se usa WProton: preguntar donde estan los juegos.
    # Dos opciones claras en vez de un si/no, y al elegir "otra carpeta" se
    # abre directamente el navegador de WProton (el que se maneja con mando).
    [ -f "$FIRSTRUN_MARK" ] && return 0
    mkdir -p "$RUNTIME_DIR" 2>/dev/null
    local sel d n
    sel="$(menu "Donde tienes tus juegos?" \
        "Usar la carpeta games/ de WProton" \
        "Elegir otra carpeta..." )" || sel=""
    case "$sel" in
        "Elegir otra carpeta"*)
            d="$(pick_dir "Elige la carpeta con tus juegos" "$(browse_start "$HOME")")" || d=""
            if [ -n "$d" ] && [ -d "$d" ]; then
                GAMES_PATH="$d"
                save_settings
                n="$(find "$GAMES_PATH" -maxdepth 2 -type f \
                     \( -iname '*.wsquashfs' -o -iname '*.squashfs' -o -iname '*.dwarfs' \) \
                     2>/dev/null | wc -l)"
                ui_info "Carpeta de juegos: $(basename "$GAMES_PATH")
${n:-0} juego(s) encontrado(s)"
            fi ;;
    esac
    # Accesos, ahora que ya esta todo listo y el usuario sabe que funciona
    if carpeta_escritorio >/dev/null 2>&1; then
        ui_ask "¿Crear un acceso directo a WProton en el escritorio?" \
            && acceso_directo_wproton
    fi
    # Añadirlo a Steam solo tiene sentido desde el escritorio: en el modo
    # Juego la sesion ES Steam y habria que cerrarlo para escribir en el.
    if [ "${IS_GAMESCOPE:-0}" != 1 ] && find_steam_userdata_config >/dev/null 2>&1; then
        ui_ask "¿Añadir WProton a Steam?

Aparecera en tu biblioteca con su imagen, y podras abrirlo desde
el modo Juego sin salir al escritorio." \
            && { anadir_wproton_a_steam || true; }
    fi
    touch "$FIRSTRUN_MARK" 2>/dev/null
    return 0
}

install_notice_start() {
    # Aviso de "instalando" para la PRIMERA vez. Aqui todavia no existe ni
    # Python ni pygame, asi que se usa lo que haya: una ventana de zenity si
    # el escritorio la tiene, y siempre un mensaje en la terminal. Sin esto,
    # el usuario se queda mirando una pantalla vacia mientras se descargan
    # Python, los runners y las herramientas de montaje.
    # Si ya hay un aviso en pantalla, no se abre otro: el arranque y --setup
    # llamaban aqui los dos y salian DOS ventanas de zenity superpuestas.
    if [ -n "${INSTALL_NOTICE_PID:-}" ] && kill -0 "$INSTALL_NOTICE_PID" 2>/dev/null; then
        return 0
    fi
    INSTALL_NOTICE_PID=""
    printf '\n  WProton: primera puesta en marcha\n' >&2
    printf '  Descargando lo necesario (Python, runners y herramientas).\n' >&2
    printf '  Esto solo pasa la primera vez y tarda unos minutos...\n\n' >&2
    if [ "$HAS_ZENITY" = 1 ]; then
        ( while :; do echo 50; sleep 1; done ) 2>/dev/null \
            | zenity --progress --title="WProton" --pulsate --no-cancel --auto-close \
                     --width=420 \
                     --text="Primera puesta en marcha de WProton

Descargando Python, los runners y las herramientas de montaje.
Esto solo ocurre la primera vez y puede tardar unos minutos." \
              >/dev/null 2>&1 &
        INSTALL_NOTICE_PID=$!
    fi
    return 0
}

install_notice_stop() {
    if [ -n "${INSTALL_NOTICE_PID:-}" ]; then
        # matar el generador y la ventana
        pkill -P "$INSTALL_NOTICE_PID" 2>/dev/null
        kill "$INSTALL_NOTICE_PID" 2>/dev/null
        INSTALL_NOTICE_PID=""
    fi
    return 0
}

instalar_runtime() {
    # PUESTA EN MARCHA, en un solo sitio.
    #
    # Antes esto estaba escrito dos veces: una en bootstrap_if_needed (para el
    # primer arranque) y otra en el manejador de --setup. Al mejorar una, la
    # otra se quedaba atras: asi fue como --setup acabo sin cerrar su aviso y
    # pidiendo "Aceptar" en cada paso. Ahora los dos caminos llaman aqui.
    #
    # $1 = titulo de la ventana de progreso
    local titulo="${1:-Primera puesta en marcha de WProton}"
    local hay_que_instalar="${WP_PRIMERA_VEZ:-0}"
    [ -x "$PY_DIR/bin/python3" ] || hay_que_instalar=1
    [ -x "$UMU_BIN" ] || hay_que_instalar=1
    [ -z "$(runner_names)" ] && hay_que_instalar=1

    # durante la puesta en marcha los pasos informan pero NO piden Aceptar:
    # es un proceso automatico, no una sucesion de dialogos
    WP_INSTALL_SILENCIOSO=1
    [ "$hay_que_instalar" = 1 ] && install_notice_start

    # Python portable primero: umu, menus y extraccion zip dependen de el
    if [ ! -x "$PY_DIR/bin/python3" ]; then
        if [ -n "$SYS_PY" ]; then
            setup_python || say "Aviso: sin Python portable, usando el del sistema"
        else
            setup_python || die "No hay python3 en el sistema ni se pudo instalar el portable"
        fi
    fi
    # Con Python y pygame listos, el aviso pasa a nuestra propia ventana: se
    # ve igual en escritorio y en modo Juego, y con el tema elegido.
    if [ "$hay_que_instalar" = 1 ] && pygame_available; then
        install_notice_stop
        progress_start "$titulo"
        progress_set 40 "Preparando umu-launcher..."
    fi

    [ -x "$UMU_BIN" ] || setup_umu

    # Segundo intento con las herramientas de montaje, ya con menus: si sigue
    # sin poder, se avisa de forma clara (check_deps solo lo apunto en el log)
    if [ -n "${WP_SIN_FUSE:-}" ]; then
        progress_set 60 "Herramientas de montaje..."
        setup_fuse_tools || true
        SQUASHFUSE_BIN="$(resolve_tool squashfuse)"
        OVERLAYFS_BIN="$(resolve_tool fuse-overlayfs)"
        if [ -z "$SQUASHFUSE_BIN" ] || [ -z "$OVERLAYFS_BIN" ]; then
            ui_error "Faltan herramientas de montaje:$WP_SIN_FUSE

Sin ellas no se pueden abrir los juegos empaquetados (.wsquashfs
y .dwarfs). Los juegos en carpeta si funcionan.

Puedes instalarlas con tu gestor de paquetes, o reintentarlo en
Runners y herramientas -> Descargar herramientas FUSE portables."
        else
            WP_SIN_FUSE=""
        fi
    fi

    if [ -z "$(runner_names)" ]; then
        progress_set 70 "Descargando GE-Proton (es el paso mas largo)..."
        setup_proton
        # El runner propio, SOLO en una instalacion nueva. Si se pusiera
        # fuera de este bloque, se reintentaria en cada arranque de quien lo
        # hubiera borrado a proposito o de quien le fallara la descarga.
        # Despues siempre se puede pedir en "Descargar runners".
        if [ -n "${GE_CUSTOM_URL:-}" ]; then
            progress_set 90 "Descargando el runner propio de WProton..."
            setup_proton_custom || say "Se continua sin el runner propio"
        fi
    fi
    progress_set 100 "Listo"
    progress_stop
    install_notice_stop
    WP_INSTALL_SILENCIOSO=0
    return 0
}

bootstrap_if_needed() {
    instalar_runtime
    first_run_games_path      # solo la primera vez
    # Si falta alguna carpeta de juegos, puede ser que su disco no este
    # montado (tipico en el modo Juego con un disco externo o una segunda
    # unidad): se ofrece montarlo sin salir de aqui.
    montar_discos_recordados || true    # los ya configurados, sin preguntar
    montar_discos_de_juegos || true     # y si aun falta alguno, se pregunta
}

# ----------------------------------------------------------------------------
# 17. ENTRADA
# ----------------------------------------------------------------------------
case "${1:-}" in
    --version) printf 'WProton v%s\n' "$WPROTON_VERSION"; exit 0 ;;
esac

rotate_logs() {
    # Conservar solo los logs de los últimos 2 dias (y 40 como maximo)
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

export WP_THEME="${THEME:-moderno}"
export WP_GRID_COLS="${GRID_COLS:-0}"
export WP_LANG="${LANGUAGE:-es}"
export WP_FONT_SCALE="${FONT_SCALE:-1.0}"

# ¿Primera puesta en marcha? Se decide ANTES de tocar nada, porque check_deps
# ya se pone a descargar las herramientas de montaje y el usuario no puede
# quedarse mirando una pantalla vacia.
# Modo desarrollo: se comprueba ANTES de instalar nada, para que "--dev" sin
# activar avise al momento en vez de lanzar una instalacion completa.
if [ "${1:-}" = "--dev" ] && [ "${DEV_MODE:-0}" != 1 ]; then
    printf '\n  El modo desarrollo no esta activado.\n' >&2
    printf '  Pon DEV_MODE=1 en %s\n\n' "$SETTINGS_FILE" >&2
    exit 1
fi

WP_PRIMERA_VEZ=0
if [ ! -x "$PY_DIR/bin/python3" ] || [ ! -x "$UMU_BIN" ] || [ ! -f "$FIRSTRUN_MARK" ]; then
    WP_PRIMERA_VEZ=1
    install_notice_start
fi

covers_wide_preparar    # crea covers_wide/ y traslada lo del nombre viejo
datos_preparar          # crea datos/ y traslada las fichas que hubiera
check_deps
rotate_logs          # no acumular cientos de logs antiguos
sweep_stale_mounts   # limpiar restos de sesiones anteriores (ro/merged llenos)
# Restos de una sesion anterior que no se cerrara bien: si quedo un servidor
# de menus vivo, tendria una ventana en pantalla y se pelearia con el nuevo.
if [ -f "$RUNTIME_DIR/.menusrv.pid" ]; then
    _viejo="$(cat "$RUNTIME_DIR/.menusrv.pid" 2>/dev/null)"
    if [ -n "$_viejo" ] && kill -0 "$_viejo" 2>/dev/null; then
        kill "$_viejo" 2>/dev/null; sleep 0.3; kill -9 "$_viejo" 2>/dev/null
        log "Servidor de menus huerfano de una sesion anterior: cerrado"
    fi
    rm -f "$RUNTIME_DIR/.menusrv.pid" 2>/dev/null
    rm -rf "$RUNTIME_DIR/.menusrv" 2>/dev/null
fi
unset _viejo
pkill -f "$PAD_BRIDGE_PY" 2>/dev/null   # puentes uinput zombis -> fuera
# Y mapeadores .keys huerfanos de una sesion anterior.
#
# El mapeador convierte los botones del mando en TECLAS del sistema. Si
# sobrevive a la partida, sigue haciendolo dentro de los menus de WProton: con
# un .keys que asigne A a la letra "i" y B a la "j", entrar en una carpeta
# escribia "i" en el buscador y volver escribia "j". La pantalla se filtraba
# sola y parecia que los ficheros habian desaparecido.
# Por NOMBRE, no por ruta: puede venir de otra copia de WProton
_huerf="$(pgrep -f 'mapeador\.py' 2>/dev/null | grep -c . || true)"
[ "${_huerf:-0}" -gt 0 ] && log "Arranque: $_huerf mapeador(es) huerfano(s); se cierran" WARN
pkill -f 'mapeador\.py' 2>/dev/null
unset _huerf

case "${1:-}" in
    --setup)
        # El mismo procedimiento que el primer arranque, sin repetirlo aqui.
        WP_PRIMERA_VEZ=1
        instalar_runtime "Preparando WProton"
        ui_info "Todo listo.

Ya puedes lanzar juegos, o abrir WProton sin parametros para
entrar en los menus.
Mas runners: menu principal -> Descargar runners" ;;
    --dev)
        # Modo desarrollo (sin documentar). No hay opcion en los menus a
        # proposito: asi no aparece en las capturas de pantalla.
        # Al salir del menu de desarrollo se abre WProton con normalidad,
        # que es justo lo que hace falta para grabar un video: se arranca la
        # grabacion y se navega mientras corre.
        bootstrap_if_needed
        menu_server_start || canvas_start
        dev_menu
        main_menu ;;
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
            *.exe|*.EXE|*.bat|*.BAT|*.cmd|*.CMD) package_exe "$2" ;;
            *) if [ -d "$2" ]; then package_dir "$2"; else import_input "$2"; fi ;;
        esac ;;
    --menu)
        # Salida de emergencia del modo solo-jugar: menu completo siempre
        bootstrap_if_needed
        menu_server_start || canvas_start
        main_menu ;;
    --play|--games)
        bootstrap_if_needed
        menu_server_start || canvas_start
        direct_play_loop ;;
    "")
        bootstrap_if_needed
        menu_server_start || canvas_start
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
