#!/usr/bin/env bash
# Prueba: donde se busca el .keys y cual gana.
#
# Copyright (C) 2026  stshunz y colaboradores. GPL v3 o posterior.
# ----------------------------------------------------------------------------
# POR QUE ESTA PRUEBA
#
# Aqui se han roto ya dos cosas distintas, las dos vistas por testers:
#
#   1. El de profiles/ iba EL ULTIMO. En un juego que ya traia su .keys, el
#      usuario lo editaba -el editor guarda siempre en profiles/-, guardaba, y
#      se seguia usando el original. "Se vuelve loco", dijo el tester.
#
#   2. Solo se miraba FUERA del juego. Batocera pone el .keys dentro cuando el
#      juego va en carpeta .pc, asi que el mismo juego tenia mapeo comprimido
#      y no lo tenia en carpeta.
#
# Las dos son de orden y de sitio, no de logica complicada: justo lo que una
# prueba sujeta bien.
# ----------------------------------------------------------------------------
. "$(cd "$(dirname "$0")" && pwd)/comun.sh"

cargar_funcion find_keys_file keys_copiar_a_profiles

PROFILE_DIR="$TMP/profiles"
mkdir -p "$PROFILE_DIR" "$TMP/juegos"

titulo "El de profiles/ manda sobre todos"

: > "$PROFILE_DIR/juego1.keys"
: > "$TMP/juegos/juego1.keys"
: > "$TMP/juegos/juego1.wsquashfs"
r="$(find_keys_file "$TMP/juegos/juego1.wsquashfs" juego1)"
afirmar_igual "$r" "$PROFILE_DIR/juego1.keys" \
    "con .keys en profiles/ y junto al juego, gana el de profiles/"

titulo "Junto al .wsquashfs, con el nombre del juego"

: > "$TMP/juegos/juego2.wsquashfs"
: > "$TMP/juegos/juego2.keys"
r="$(find_keys_file "$TMP/juegos/juego2.wsquashfs" juego2)"
afirmar_igual "$r" "$TMP/juegos/juego2.keys" \
    "se encuentra el .keys que acompaña al paquete"

# La otra forma: nombre completo + .keys (juego.wsquashfs.keys)
: > "$TMP/juegos/juego3.wsquashfs"
: > "$TMP/juegos/juego3.wsquashfs.keys"
r="$(find_keys_file "$TMP/juegos/juego3.wsquashfs" juego3)"
afirmar_igual "$r" "$TMP/juegos/juego3.wsquashfs.keys" \
    "tambien vale la forma juego.wsquashfs.keys"

titulo "En carpeta, el que va DENTRO (el fallo del tester)"

mkdir -p "$TMP/juegos/juego4.pc"
: > "$TMP/juegos/juego4.pc/padto.keys"
limpiar_say
r="$(find_keys_file "$TMP/juegos/juego4.pc" juego4)"
afirmar_igual "$r" "$PROFILE_DIR/juego4.keys" \
    "el padto.keys de dentro se usa Y se copia a profiles/"
afirmar_fichero "$PROFILE_DIR/juego4.keys" "la copia existe de verdad"
afirmar_fichero "$TMP/juegos/juego4.pc/padto.keys" \
    "el original NO se toca (Batocera lo sigue necesitando)"

titulo "Un .keys suelto dentro de la carpeta"

mkdir -p "$TMP/juegos/juego5.pc"
: > "$TMP/juegos/juego5.pc/loquesea.keys"
r="$(find_keys_file "$TMP/juegos/juego5.pc" juego5)"
afirmar_igual "$r" "$PROFILE_DIR/juego5.keys" \
    "con UN solo .keys dentro, se acepta aunque no se llame padto"

titulo "Con varios .keys dentro no se adivina"

mkdir -p "$TMP/juegos/juego6.pc"
: > "$TMP/juegos/juego6.pc/uno.keys"
: > "$TMP/juegos/juego6.pc/otro.keys"
r="$(find_keys_file "$TMP/juegos/juego6.pc" juego6)" || rc=$?
afirmar_vacio "$r" "con dos .keys sueltos no se elige ninguno"
afirmar_no_fichero "$PROFILE_DIR/juego6.keys" "y no se copia nada a profiles/"

titulo "Sin ningun .keys"

: > "$TMP/juegos/juego7.wsquashfs"
r="$(find_keys_file "$TMP/juegos/juego7.wsquashfs" juego7)"
rc=$?
afirmar_fallo "$rc" "sin .keys por ningun lado, devuelve fallo"
afirmar_vacio "$r" "y no imprime ninguna ruta"

titulo "La copia a profiles/ no pisa la tuya"

mkdir -p "$TMP/juegos/juego8.pc"
printf 'DEL JUEGO\n' > "$TMP/juegos/juego8.pc/padto.keys"
printf 'MIO\n' > "$PROFILE_DIR/juego8.keys"
r="$(find_keys_file "$TMP/juegos/juego8.pc" juego8)"
afirmar_igual "$r" "$PROFILE_DIR/juego8.keys" "gana el tuyo"
afirmar_igual "$(cat "$PROFILE_DIR/juego8.keys")" "MIO" \
    "y su contenido sigue siendo el tuyo, no el del juego"

titulo "keys_copiar_a_profiles por separado"

printf 'ORIGEN\n' > "$TMP/origen.keys"
keys_copiar_a_profiles "$TMP/origen.keys" juego9
afirmar_ok $? "copia cuando no habia nada"
afirmar_igual "$(cat "$PROFILE_DIR/juego9.keys")" "ORIGEN" "con su contenido"

keys_copiar_a_profiles "$TMP/origen.keys" juego9
afirmar_fallo $? "la segunda vez NO copia (el de profiles/ manda)"

keys_copiar_a_profiles "$TMP/no_existe.keys" juego10
afirmar_fallo $? "un origen que no existe no crea nada"

keys_copiar_a_profiles "$TMP/origen.keys" ""
afirmar_fallo $? "sin gid no se copia"

resumen
