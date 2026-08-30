#!/usr/bin/env bash
# WProton - andamio comun de las pruebas
#
# Copyright (C) 2026  stshunz y colaboradores
# Software libre bajo la GPL v3 o posterior. SIN NINGUNA GARANTIA.
# ----------------------------------------------------------------------------
# Lo que resuelve este fichero
#
# wproton.base.sh NO se puede sourcear: no tiene guarda, y al final hay un
# "case" que arranca el programa de verdad -crea carpetas, mira actualizaciones
# y se queda en un menu-. Sourcearlo para probar una funcion arrancaria WProton.
#
# Asi que se extrae SOLO la funcion que la prueba pide, por su nombre, y se
# evalua aqui. Ventajas:
#
#   - no hay que tocar el fuente para que sea probable (una guarda de source
#     seria codigo que existe solo para las pruebas, y que puede romperse);
#   - cada prueba declara que funciones usa, asi que se ve de un vistazo que
#     esta cubierto;
#   - si alguien renombra una funcion, la prueba falla en el acto con un
#     mensaje claro, en vez de pasar sin probar nada.
#
# LAS PRUEBAS NO TOCAN NADA DE FUERA. Cada una trabaja en su carpeta temporal
# y la borra al salir.
# ----------------------------------------------------------------------------
set -u

PRUEBAS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RAIZ="$(dirname "$PRUEBAS_DIR")"
FUENTE="${WP_FUENTE:-$RAIZ/wproton.base.sh}"

_ok=0
_fallos=0
_nombre_prueba="$(basename "${0}")"

# ---------------------------------------------------------------------------
# Carpeta de trabajo: propia de cada prueba y se borra siempre.
# ---------------------------------------------------------------------------
TMP="$(mktemp -d "${TMPDIR:-/tmp}/wp_prueba_XXXXXX")"
_limpiar() { [ -n "${TMP:-}" ] && rm -rf "$TMP"; }
trap _limpiar EXIT

# ---------------------------------------------------------------------------
# Extraer una funcion del fuente por su nombre.
#
# Las funciones se declaran en columna 0 como "nombre() {" y cierran con "}"
# tambien en columna 0. Las de una linea -log, die, onoff...- abren y cierran
# en la misma, y se detectan porque esa linea termina en "}".
# ---------------------------------------------------------------------------
_extraer_funcion() {
    local f="$1"
    awk -v f="$f" '
        !dentro && $0 ~ "^"f"\\(\\)[ \t]*\\{" {
            dentro = 1
            print
            # De una linea: abre y cierra en la misma.
            if ($0 ~ /\}[ \t]*$/) exit
            next
        }
        dentro { print }
        dentro && /^\}[ \t]*$/ { exit }
    ' "$FUENTE"
}

cargar_funcion() {
    # Trae una o mas funciones del fuente al shell de la prueba.
    local f cuerpo
    for f in "$@"; do
        # say/log/die/ui_* tienen sustituto aqui abajo a proposito. Cargar el
        # de verdad pisaria el sustituto -y die() ademas mata el proceso-, con
        # lo que la prueba se iria a tomar viento sin decir por que.
        case "$f" in
            say|log|die|ui_error|ui_info)
                printf '  ERROR: %s() no se carga: hay un sustituto en comun.sh\n' \
                    "$f" >&2
                exit 2 ;;
        esac
        cuerpo="$(_extraer_funcion "$f")"
        if [ -z "$cuerpo" ]; then
            printf '  ERROR: no se encuentra la funcion %s() en %s\n' \
                "$f" "$(basename "$FUENTE")" >&2
            printf '  (¿se ha renombrado? la prueba no puede seguir)\n' >&2
            exit 2
        fi
        eval "$cuerpo" || {
            printf '  ERROR: %s() no se puede evaluar\n' "$f" >&2
            exit 2
        }
    done
}

# ---------------------------------------------------------------------------
# Sustitutos de las funciones de aviso.
#
# say/log/die escriben en el log y en la pantalla, y die ademas mata el
# proceso. En una prueba eso sobra, pero lo que dicen SI interesa: se guarda
# en SALIDA_SAY para poder comprobar que se avisa de lo que hay que avisar.
#
# Se definen AQUI, antes de nada, para que ninguna prueba cargue las de
# verdad por descuido.
# ---------------------------------------------------------------------------
SALIDA_SAY=""
say()  { SALIDA_SAY="$SALIDA_SAY$1"$'\n'; }
log()  { :; }
die()  { SALIDA_SAY="$SALIDA_SAY""ERROR: $1"$'\n'; return 1; }
ui_error() { :; }
ui_info()  { :; }

limpiar_say() { SALIDA_SAY=""; }

# ---------------------------------------------------------------------------
# Afirmaciones
# ---------------------------------------------------------------------------
_bien() { _ok=$((_ok + 1)); printf '  ok    %s\n' "$1"; }
_mal()  {
    _fallos=$((_fallos + 1))
    printf '  FALLA %s\n' "$1"
    [ $# -gt 1 ] && printf '        %s\n' "$2"
    return 0
}

afirmar_igual() {
    # $1 = obtenido, $2 = esperado, $3 = que se estaba probando
    if [ "$1" = "$2" ]; then
        _bien "$3"
    else
        _mal "$3" "esperaba [$2] y ha salido [$1]"
    fi
}

afirmar_distinto() {
    if [ "$1" != "$2" ]; then
        _bien "$3"
    else
        _mal "$3" "no deberia ser [$2]"
    fi
}

afirmar_ok() {
    # $1 = codigo de salida, $2 = que se probaba
    if [ "$1" = 0 ]; then
        _bien "$2"
    else
        _mal "$2" "esperaba exito y ha devuelto $1"
    fi
}

afirmar_fallo() {
    if [ "$1" != 0 ]; then
        _bien "$2"
    else
        _mal "$2" "esperaba fallo y ha devuelto 0"
    fi
}

afirmar_contiene() {
    # $1 = texto, $2 = trozo que debe aparecer, $3 = que se probaba
    case "$1" in
        *"$2"*) _bien "$3" ;;
        *) _mal "$3" "no aparece [$2] en: $(printf '%s' "$1" | tr '\n' '|')" ;;
    esac
}

afirmar_no_contiene() {
    case "$1" in
        *"$2"*) _mal "$3" "no deberia aparecer [$2]" ;;
        *) _bien "$3" ;;
    esac
}

afirmar_vacio() {
    if [ -z "$1" ]; then
        _bien "$2"
    else
        _mal "$2" "esperaba vacio y ha salido [$1]"
    fi
}

afirmar_fichero() {
    if [ -f "$1" ]; then
        _bien "$2"
    else
        _mal "$2" "no existe el fichero $1"
    fi
}

afirmar_no_fichero() {
    if [ -f "$1" ]; then
        _mal "$2" "no deberia existir el fichero $1"
    else
        _bien "$2"
    fi
}

# ---------------------------------------------------------------------------
# Cabecera y resumen
# ---------------------------------------------------------------------------
titulo() { printf '\n%s\n' "== $1 =="; }

resumen() {
    printf '\n%s: %d bien, %d mal\n' "$_nombre_prueba" "$_ok" "$_fallos"
    [ "$_fallos" = 0 ] || return 1
    return 0
}
