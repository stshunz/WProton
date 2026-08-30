#!/usr/bin/env bash
# Prueba: las librerias de un juego se recuerdan (novedad de la 1.49).
#
# Copyright (C) 2026  stshunz y colaboradores. GPL v3 o posterior.
# ----------------------------------------------------------------------------
# POR QUE ESTA PRUEBA
#
# Lo que se instalaba en el prefijo propio de un juego vivia SOLO dentro del
# prefijo. Si ese prefijo se rehacia -o se borraba, o el juego se llevaba a
# otro equipo- las librerias desaparecian en silencio: el juego dejaba de
# arrancar y habia que acordarse de que un dia se le instalo algo.
#
# Ahora quedan apuntadas en el perfil y se reponen solas. Tres piezas:
#   - apuntar: acumula sin repetir y limpia los espacios de los extremos;
#   - pendientes: que falta en ESTE prefijo (la marca vive dentro, asi que si
#     el prefijo se rehace vuelve a estar todo pendiente, que es lo que se
#     quiere);
#   - marcar: dejar constancia de lo ya puesto.
#
# Lo de los espacios no es capricho: la primera version dejaba " d3dx9 xact"
# con el espacio delante escrito en el perfil.
# ----------------------------------------------------------------------------
. "$(cd "$(dirname "$0")" && pwd)/comun.sh"

cargar_funcion redist_juego_apuntar redist_juego_pendientes redist_juego_marcar

# write_full_profile escribe el perfil entero en disco y arrastra media
# configuracion. Aqui solo interesa SI se ha llamado y con que quedaba
# REDIST_JUEGO, asi que se sustituye.
ESCRITURAS=0
PERFIL_ESCRITO=""
write_full_profile() {
    ESCRITURAS=$((ESCRITURAS + 1))
    PERFIL_ESCRITO="$REDIST_JUEGO"
    return 0
}

titulo "Apuntar la primera libreria"

REDIST_JUEGO=""
limpiar_say
redist_juego_apuntar juego1 "d3dx9"
afirmar_igual "$REDIST_JUEGO" "d3dx9" "queda apuntada"
afirmar_igual "$ESCRITURAS" "1" "y se guarda el perfil"
afirmar_igual "$PERFIL_ESCRITO" "d3dx9" "sin espacios sueltos alrededor"
afirmar_contiene "$SALIDA_SAY" "Apuntado en el perfil" "y se dice"

titulo "Se acumulan, no se sustituyen"

redist_juego_apuntar juego1 "xact"
afirmar_igual "$REDIST_JUEGO" "d3dx9 xact" \
    "quien instala d3dx9 hoy y xact mañana quiere las dos"

redist_juego_apuntar juego1 "openal wmp11"
afirmar_igual "$REDIST_JUEGO" "d3dx9 xact openal wmp11" \
    "varias de golpe se añaden todas"

titulo "No se repiten"

ESCRITURAS=0
redist_juego_apuntar juego1 "xact"
afirmar_igual "$REDIST_JUEGO" "d3dx9 xact openal wmp11" "la lista no cambia"
afirmar_igual "$ESCRITURAS" "0" \
    "y no se reescribe el perfil si no ha cambiado nada"

redist_juego_apuntar juego1 "xact d3dcompiler_47"
afirmar_igual "$REDIST_JUEGO" "d3dx9 xact openal wmp11 d3dcompiler_47" \
    "de una lista mezclada solo entra lo nuevo"

titulo "Los espacios de los extremos (el fallo que ya paso)"

REDIST_JUEGO=""
redist_juego_apuntar juegoX "d3dx9 xact"
afirmar_igual "$REDIST_JUEGO" "d3dx9 xact" "ni delante ni detras"
case "$REDIST_JUEGO" in
    " "*) _mal "sin espacio delante" ;;
    *" ") _mal "sin espacio detras" ;;
    *) _bien "la lista guardada esta limpia" ;;
esac

titulo "Lo que no se apunta"

REDIST_JUEGO="d3dx9"
ESCRITURAS=0
redist_juego_apuntar "" "xact"
afirmar_igual "$REDIST_JUEGO" "d3dx9" "sin gid no se apunta nada"
redist_juego_apuntar juego1 ""
afirmar_igual "$REDIST_JUEGO" "d3dx9" "sin librerias tampoco"
afirmar_igual "$ESCRITURAS" "0" "y no se escribe el perfil en ninguno de los dos"

titulo "Que falta en este prefijo"

mkdir -p "$TMP/pfx"
REDIST_JUEGO="d3dx9 xact openal"

r="$(redist_juego_pendientes "$TMP/pfx")"
afirmar_igual "$r" "d3dx9 xact openal" \
    "en un prefijo recien hecho falta todo"

printf 'd3dx9\n' > "$TMP/pfx/.wp_redist_juego"
r="$(redist_juego_pendientes "$TMP/pfx")"
afirmar_igual "$r" "xact openal" "con d3dx9 ya puesta, faltan las otras dos"

printf 'd3dx9 xact openal\n' > "$TMP/pfx/.wp_redist_juego"
redist_juego_pendientes "$TMP/pfx" >/dev/null
afirmar_fallo $? "con todas puestas, no hay nada pendiente"

titulo "Un prefijo rehecho vuelve a necesitarlo todo"

# Esto es el corazon de la novedad: la marca vive DENTRO del prefijo, asi que
# borrarlo devuelve todo a pendiente y las librerias se reponen solas.
rm -rf "$TMP/pfx"
mkdir -p "$TMP/pfx"
r="$(redist_juego_pendientes "$TMP/pfx")"
afirmar_igual "$r" "d3dx9 xact openal" \
    "borrado el prefijo, vuelve a faltar todo (que es lo que se queria)"

titulo "Marcar lo ya puesto"

redist_juego_marcar "$TMP/pfx"
afirmar_ok $? "se puede marcar"
afirmar_igual "$(cat "$TMP/pfx/.wp_redist_juego")" "d3dx9 xact openal" \
    "queda escrito dentro del prefijo"
redist_juego_pendientes "$TMP/pfx" >/dev/null
afirmar_fallo $? "y despues de marcar ya no falta nada"

redist_juego_marcar "$TMP/no_existe"
afirmar_fallo $? "no se marca un prefijo que no existe"

titulo "Sin nada apuntado no hay nada que reponer"

REDIST_JUEGO=""
redist_juego_pendientes "$TMP/pfx" >/dev/null
afirmar_fallo $? "un juego sin librerias apuntadas no pide nada"

REDIST_JUEGO="d3dx9"
redist_juego_pendientes "" >/dev/null
afirmar_fallo $? "sin prefijo no se puede saber que falta"

titulo "Solo con prefijo propio"

# En el compartido lo instalado vale para todos los juegos, asi que apuntarlo
# en uno concreto seria mentir. La regla esta escrita en el codigo; aqui se
# comprueba que sigue estando, porque es una decision del usuario.
_ctx="$(grep -n 'redist_juego_apuntar' "$FUENTE" | grep -v '^[0-9]*:redist_juego_apuntar()')"
afirmar_distinto "$_ctx" "" "redist_juego_apuntar se llama desde algun sitio"

resumen
