#!/usr/bin/env bash
# WProton - lanzador de las pruebas
#
# Copyright (C) 2026  stshunz y colaboradores. GPL v3 o posterior.
# ----------------------------------------------------------------------------
#   ./pruebas/ejecutar.sh            todas, dos veces seguidas
#   ./pruebas/ejecutar.sh keys bat   solo esas (vale el nombre corto)
#   ./pruebas/ejecutar.sh --una-vez  una sola pasada (para ir depurando)
#
# DOS VECES SEGUIDAS, Y NO ES MANIA.
#
# Una prueba que pasa la primera vez y falla la segunda es una prueba que deja
# suciedad: un fichero en profiles/, una marca dentro de un prefijo, una
# variable que se queda puesta. Ese tipo de fallo no lo ve nadie hasta que un
# dia una prueba empieza a depender de otra y el orden importa.
#
# La segunda pasada se hace con las MISMAS pruebas y tiene que dar el mismo
# resultado. Si no lo da, la prueba esta mal, aunque el codigo este bien.
# ----------------------------------------------------------------------------
set -u

AQUI="$(cd "$(dirname "$0")" && pwd)"
cd "$AQUI" || exit 2

rojo()  { printf '\033[31m%s\033[0m\n' "$1"; }
verde() { printf '\033[32m%s\033[0m\n' "$1"; }

VECES=2
LISTA=""
for a in "$@"; do
    case "$a" in
        --una-vez) VECES=1 ;;
        -h|--ayuda|--help)
            sed -n '5,9p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) LISTA="$LISTA $a" ;;
    esac
done

# Sin lista, todas. Con lista, se admite "keys" o "probar_keys.sh".
suites() {
    local n
    if [ -z "$LISTA" ]; then
        ls probar_*.sh 2>/dev/null
        return
    fi
    for n in $LISTA; do
        case "$n" in
            probar_*) printf '%s\n' "$n" ;;
            *) printf 'probar_%s.sh\n' "$n" ;;
        esac
    done
}

TOTAL_MAL=0
FALLAN=""
PASADA=1

while [ "$PASADA" -le "$VECES" ]; do
    printf '\n############ PASADA %d de %d ############\n' "$PASADA" "$VECES"
    for s in $(suites); do
        if [ ! -f "$s" ]; then
            rojo "  no existe: $s"
            TOTAL_MAL=$((TOTAL_MAL + 1))
            FALLAN="$FALLAN $s"
            continue
        fi
        if bash "$s"; then
            :
        else
            TOTAL_MAL=$((TOTAL_MAL + 1))
            case " $FALLAN " in *" $s "*) ;; *) FALLAN="$FALLAN $s" ;; esac
        fi
    done
    PASADA=$((PASADA + 1))
done

printf '\n========================================\n'
if [ "$TOTAL_MAL" = 0 ]; then
    verde "TODO BIEN ($VECES pasada(s))"
    exit 0
fi
rojo "HAY FALLOS en:$FALLAN"
exit 1
