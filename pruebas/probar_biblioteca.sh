#!/usr/bin/env bash
# Prueba: las DOS bibliotecas dan lo mismo.
#
# Copyright (C) 2026  stshunz y colaboradores. GPL v3 o posterior.
# ----------------------------------------------------------------------------
# POR QUE ESTA PRUEBA
#
# Hay dos implementaciones de la biblioteca: la lenta, en bash, y la rapida, en
# Python. LA QUE SE USA ES LA RAPIDA; la lenta se conserva palabra por palabra
# como referencia y como red de seguridad.
#
# Arreglar solo una es el fallo mas repetido del proyecto. Y es dificil de ver:
# la lenta casi nunca se ejecuta, asi que una diferencia puede vivir meses sin
# que nadie la note, o al reves -un arreglo puesto solo en la lenta no llega
# nunca al usuario-.
#
# Asi que esto NO prueba que la salida sea "correcta": prueba que las dos vias
# dan EXACTAMENTE lo mismo sobre la misma biblioteca. Se montan casos raros a
# proposito -espacios, barras verticales, extensiones dobles, nombres
# repetidos, caratulas en todos los sitios posibles- y se comparan las salidas
# byte a byte.
#
# ----------------------------------------------------------------------------
# AVISO: HOY ESTA PRUEBA FALLA, Y ES A PROPOSITO
#
# En la REJILLA, con las formas "wide" y "43", las dos vias no dicen lo mismo
# cuando un juego tiene:
#
#   - caratula vertical NUESTRA en covers/,
#   - ninguna de la forma pedida en covers_wide/ o covers_43/,
#   - y una de la forma pedida DE VERDAD en el escaneo de al lado.
#
#   bash   -> la del escaneo (rejilla_lenta: forma exacta, escaneo, y solo
#             entonces el apaño de cover_for)
#   Python -> nuestra vertical estirada (buscar_cover ya cae a la vertical
#             antes de mirar el escaneo)
#
# Los dos ficheros llevan escrita una regla, y son contrarias:
#   rejilla_lenta: "LA FORMA EXACTA MANDA, VENGA DE DONDE VENGA".
#   biblioteca.py: "La nuestra manda: quien pone una en covers/ quiere esa".
#
# No se toca ninguna de las dos sin hablarlo: es una decision de producto, no
# un descuido evidente. La prueba se queda fallando para que no se olvide.
# En la vista de LISTA no pasa: alli las dos buscan en el mismo orden.
# ----------------------------------------------------------------------------
. "$(cd "$(dirname "$0")" && pwd)/comun.sh"

cargar_funcion abs_path game_id juego_etiqueta games_paths \
               covers_dir_de cover_nombres cover_exacta cover_escaneo \
               cover_for profile_get game_meta fmt_playtime \
               biblioteca_lenta rejilla_lenta

PY="${PY_BIN:-$(command -v python3)}"
if [ -z "$PY" ]; then
    printf '  AVISO: no hay python3; esta prueba no puede comparar nada\n'
    exit 0
fi
BIB_PY="$RAIZ/src/biblioteca.py"
if [ ! -f "$BIB_PY" ]; then
    printf '  ERROR: no esta %s\n' "$BIB_PY" >&2
    exit 2
fi

# ---------------------------------------------------------------------------
# Una biblioteca de mentira, con los casos que hacen daño.
# ---------------------------------------------------------------------------
GAMES_PATH="$TMP/juegos"
GAMES_PATHS_EXTRA=""
COVERS_DIR="$TMP/covers"
COVERS_WIDE_DIR="$TMP/covers_wide"
COVERS_43_DIR="$TMP/covers_43"
DATOS_DIR="$TMP/datos"
PROFILE_DIR="$TMP/profiles"
mkdir -p "$GAMES_PATH" "$COVERS_DIR" "$COVERS_WIDE_DIR" "$COVERS_43_DIR" \
         "$DATOS_DIR" "$PROFILE_DIR"

img() { mkdir -p "$(dirname "$1")"; printf 'PNG' > "$1"; }

perfil() {
    # perfil <gid> <fav> <veces> <segundos> <ultima> <completado>
    cat > "$PROFILE_DIR/$1.conf" <<FIN
FAVORITO="$2"
PLAY_COUNT="$3"
PLAY_SECONDS="$4"
LAST_PLAYED="$5"
COMPLETADO="$6"
FIN
}

# --- Juegos ----------------------------------------------------------------
: > "$GAMES_PATH/Doom.wsquashfs"                 # el caso normal
: > "$GAMES_PATH/Blade Arcus.wsquashfs"          # con espacios
mkdir -p "$GAMES_PATH/Alien Stars.pc"            # carpeta: game_id deja el .pc
: > "$GAMES_PATH/Retro.dwarfs"                   # otro empaquetado
: > "$GAMES_PATH/Otro.squashfs"
: > "$GAMES_PATH/Doom.dwarfs"                    # MISMO nombre que Doom.wsquashfs
: > "$GAMES_PATH/Juego v1.2.wsquashfs"           # punto dentro del nombre
: > "$GAMES_PATH/Sin nada.wsquashfs"             # sin perfil ni caratula
: > "$GAMES_PATH/Raro|Nombre.wsquashfs"          # barra vertical en el nombre
: > "$GAMES_PATH/Suelto.exe"                     # sin extension de empaquetado
# EL CASO QUE DISTINGUE EL ORDEN DE BUSQUEDA DE CARATULA.
#
# Este juego tiene vertical PROPIA en covers/, no tiene panoramica propia, y
# SI tiene una panoramica de verdad en el escaneo de al lado. Al pedir la
# vista panoramica hay dos respuestas posibles:
#
#   - la panoramica del escaneo, que es de la forma pedida;
#   - nuestra vertical estirada, que es el apaño de ultimo recurso.
#
# La decision esta tomada y escrita en rejilla_lenta: primero la forma exacta
# alla donde este, y el apaño solo si no aparece. Sin un juego asi, las dos
# vias pueden discrepar aqui y la prueba no se entera.
: > "$GAMES_PATH/Panoramica.wsquashfs"

# --- Perfiles --------------------------------------------------------------
perfil Doom            1 12 11532 "2026-08-14 21:33" 1
perfil Blade_Arcus     0  3   150 "2026-01-02 10:00" 0
perfil "Alien_Stars.pc" 1 1    30 ""                 0
perfil Retro           0  0     0 "2025-12-30 08:15" 0
perfil "Juego_v1.2"    0  7  3600 ""                 1
perfil "Raro|Nombre"   1  2    90 "2026-02-02 02:02" 0

# --- Caratulas -------------------------------------------------------------
img "$COVERS_DIR/Doom.png"
img "$COVERS_DIR/Blade Arcus.jpg"          # con espacios, no con guion bajo
img "$COVERS_DIR/Alien Stars.png"          # sin el .pc de la carpeta
img "$COVERS_WIDE_DIR/Doom.png"
img "$COVERS_DIR/Retro.wide.png"           # nomenclatura anterior
img "$COVERS_43_DIR/Otro.webp"
# Escaneo de ES-DE junto a los juegos
img "$GAMES_PATH/images/Juego v1.2-image.png"
img "$GAMES_PATH/media/Sin nada-cover.jpg"
# Vertical propia + panoramica SOLO en el escaneo (ver arriba).
img "$COVERS_DIR/Panoramica.png"
img "$GAMES_PATH/images/Panoramica-fanart.png"
# Lo mismo para la forma 4:3, que busca otros sufijos: sin esto la prueba solo
# miraria la panoramica y no se sabria si el desacuerdo es de una forma o de
# todas las que tienen carpeta propia.
img "$GAMES_PATH/images/Panoramica-screenshot.png"

lista_juegos_txt="$(cd "$GAMES_PATH" && ls -1 | sed "s|^|$GAMES_PATH/|" \
                    | grep -v '/images$' | grep -v '/media$')"

# ---------------------------------------------------------------------------
# Ejecutar las dos vias y comparar.
# ---------------------------------------------------------------------------
comparar_lista() {
    # $1 = forma de caratula
    local forma="$1"
    LIST_COVER="$forma"
    WP_N_RAICES="$(games_paths | grep -c .)"

    local bm="$TMP/b.mapa" bi="$TMP/b.info" bs="$TMP/b.salida"
    biblioteca_lenta "$bm" "$bi" "$bs" "$lista_juegos_txt"

    local pm="$TMP/p.mapa" pi="$TMP/p.info" ps="$TMP/p.salida"
    printf '%s\n' "$lista_juegos_txt" | \
        COVERS_DIR="$COVERS_DIR" COVERS_WIDE_DIR="$COVERS_WIDE_DIR" \
        COVERS_43_DIR="$COVERS_43_DIR" DATOS_DIR="$DATOS_DIR" \
        PROFILE_DIR="$PROFILE_DIR" LIST_COVER="$forma" \
        WP_RAICES="$(games_paths)" \
        "$PY" "$BIB_PY" "$pm" "$pi" > "$ps" 2>"$TMP/p.err"

    if diff -u "$bm" "$pm" > "$TMP/d.mapa" 2>&1; then
        _bien "lista/$forma: el mapa etiqueta->ruta coincide"
    else
        _mal "lista/$forma: el mapa etiqueta->ruta coincide" \
            "$(head -n8 "$TMP/d.mapa" | tr '\n' '~')"
    fi
    if diff -u "$bi" "$pi" > "$TMP/d.info" 2>&1; then
        _bien "lista/$forma: la fila de datos coincide"
    else
        _mal "lista/$forma: la fila de datos coincide" \
            "$(head -n8 "$TMP/d.info" | tr '\n' '~')"
    fi
    if diff -u "$bs" "$ps" > "$TMP/d.sal" 2>&1; then
        _bien "lista/$forma: el orden de las etiquetas coincide"
    else
        _mal "lista/$forma: el orden de las etiquetas coincide" \
            "$(head -n8 "$TMP/d.sal" | tr '\n' '~')"
    fi
}

comparar_rejilla() {
    local forma="$1"
    WP_N_RAICES="$(games_paths | grep -c .)"

    local bman="$TMP/b.man"
    rejilla_lenta "$bman" "$lista_juegos_txt" "$forma"

    local pman="$TMP/p.man"
    printf '%s\n' "$lista_juegos_txt" | \
        COVERS_DIR="$COVERS_DIR" COVERS_WIDE_DIR="$COVERS_WIDE_DIR" \
        COVERS_43_DIR="$COVERS_43_DIR" PROFILE_DIR="$PROFILE_DIR" \
        WP_GRID_FORMA="$forma" WP_RAICES="$(games_paths)" \
        "$PY" "$BIB_PY" --rejilla "$pman" 2>"$TMP/p.err"

    if diff -u "$bman" "$pman" > "$TMP/d.man" 2>&1; then
        _bien "rejilla/$forma: el manifiesto coincide"
    else
        _mal "rejilla/$forma: el manifiesto coincide" \
            "$(head -n10 "$TMP/d.man" | tr '\n' '~')"
    fi
}

titulo "Vista de lista, con una sola carpeta de juegos"
comparar_lista vertical
comparar_lista wide
comparar_lista 43

titulo "Vista de rejilla, con una sola carpeta de juegos"
comparar_rejilla vertical
comparar_rejilla wide
comparar_rejilla 43

titulo "Con DOS carpetas de juegos (la etiqueta lleva de cual viene)"

GAMES_PATHS_EXTRA="$TMP/juegos2"
mkdir -p "$TMP/juegos2"
: > "$TMP/juegos2/Doom.wsquashfs"          # el mismo nombre en otra carpeta
: > "$TMP/juegos2/Exclusivo.wsquashfs"
lista_juegos_txt="$lista_juegos_txt
$TMP/juegos2/Doom.wsquashfs
$TMP/juegos2/Exclusivo.wsquashfs"
comparar_lista vertical
comparar_rejilla vertical

titulo "Con la biblioteca vacia"

lista_juegos_txt=""
comparar_lista vertical
comparar_rejilla vertical

resumen
