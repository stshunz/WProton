#!/usr/bin/env bash
# Prueba: reconocer un juego de Linux dentro del paquete.
#
# Copyright (C) 2026  stshunz y colaboradores. GPL v3 o posterior.
# ----------------------------------------------------------------------------
# POR QUE ESTA PRUEBA
#
# De esta funcion cuelga que el asistente NO pida Proton ni prefijo a un juego
# nativo (novedad de la 1.49). Si se equivoca hacia un lado, el asistente
# vuelve a preguntar por un runner que no se va a usar; si se equivoca hacia
# el otro, un juego de Windows se intenta lanzar como binario de Linux.
#
# El caso que ya costo un rato: el filtro de .exe era ABSOLUTO ("*/windows/*"),
# asi que con la biblioteca en /GAMES/windows/ casaba con TODO, no se veia ni
# un .exe y cualquier juego de Windows pasaba por nativo. Por eso aqui hay una
# prueba con la carpeta del juego colgando de una ruta con "windows" dentro.
#
# La funcion es CONSERVADORA a proposito: si hay dudas, dice que no es nativo,
# porque el camino de Windows es el que WProton sabe manejar bien hoy.
# ----------------------------------------------------------------------------
. "$(cd "$(dirname "$0")" && pwd)/comun.sh"

cargar_funcion juego_es_nativo

elf_falso() {
    # Un ELF ejecutable de mentira: basta la firma, que es lo que se mira.
    printf '\177ELF\002\001\001\000' > "$1"
    printf 'relleno' >> "$1"
    chmod +x "$1"
}

titulo "Un juego de Linux con lanzador .sh"

mkdir -p "$TMP/n1"
printf '#!/bin/sh\nexec ./bin/juego\n' > "$TMP/n1/start.sh"
chmod +x "$TMP/n1/start.sh"
r="$(juego_es_nativo "$TMP/n1")"
afirmar_igual "$r" "$TMP/n1/start.sh" "se devuelve el lanzador"

titulo "Un juego de Linux con solo un binario ELF"

mkdir -p "$TMP/n2"
elf_falso "$TMP/n2/MiJuego"
r="$(juego_es_nativo "$TMP/n2")"
afirmar_igual "$r" "$TMP/n2/MiJuego" "se devuelve el binario"

titulo "Si hay .exe, es de Windows"

mkdir -p "$TMP/w1"
: > "$TMP/w1/juego.exe"
printf '#!/bin/sh\necho hola\n' > "$TMP/w1/start.sh"
chmod +x "$TMP/w1/start.sh"
juego_es_nativo "$TMP/w1" >/dev/null
afirmar_fallo $? "con .exe y .sh a la vez, gana Windows"

# Los que traen las dos versiones: la de Windows es la que WProton maneja hoy.
mkdir -p "$TMP/w2/bin"
: > "$TMP/w2/bin/juego.exe"
elf_falso "$TMP/w2/juego"
juego_es_nativo "$TMP/w2" >/dev/null
afirmar_fallo $? "un .exe en una subcarpeta tambien cuenta"

titulo "El filtro de .exe es RELATIVO (el fallo del asistente)"

# La carpeta del juego cuelga de una ruta que lleva "windows" dentro, como
# pasa de verdad con la biblioteca en /GAMES/windows/. Un filtro absoluto
# ignoraria el .exe y este juego de Windows pasaria por nativo.
# OJO: el juego lleva ADEMAS un lanzador .sh. Sin el, la funcion diria "no es
# nativo" igualmente -por no encontrar nada que lanzar-, y la prueba pasaria
# con el fallo puesto. Con el lanzador, lo unico que puede decidir es si se ve
# el .exe o no, que es justo lo que se quiere medir.
mkdir -p "$TMP/GAMES/windows/juego"
: > "$TMP/GAMES/windows/juego/juego.exe"
printf '#!/bin/sh\n' > "$TMP/GAMES/windows/juego/jugar.sh"
chmod +x "$TMP/GAMES/windows/juego/jugar.sh"
juego_es_nativo "$TMP/GAMES/windows/juego" >/dev/null
afirmar_fallo $? \
    "un juego dentro de .../windows/ sigue viendose como de Windows"

# Y al reves: la carpeta windows/ DEL PROPIO juego si se ignora, porque ahi
# es donde un prefijo empaquetado guarda sus DLL.
mkdir -p "$TMP/n3/windows/system32"
: > "$TMP/n3/windows/system32/algo.exe"
elf_falso "$TMP/n3/juego"
r="$(juego_es_nativo "$TMP/n3")"
afirmar_igual "$r" "$TMP/n3/juego" \
    "los .exe de la carpeta windows/ interna no lo hacen de Windows"

titulo "Los .sh que no son el juego"

mkdir -p "$TMP/n4"
for s in install.sh setup.sh uninstall.sh patch.sh; do
    printf '#!/bin/sh\n' > "$TMP/n4/$s"; chmod +x "$TMP/n4/$s"
done
juego_es_nativo "$TMP/n4" >/dev/null
afirmar_fallo $? "install/setup/uninstall/patch no son el juego"

# Pero si ademas hay uno de verdad, ese si vale.
printf '#!/bin/sh\n' > "$TMP/n4/jugar.sh"; chmod +x "$TMP/n4/jugar.sh"
r="$(juego_es_nativo "$TMP/n4")"
afirmar_igual "$r" "$TMP/n4/jugar.sh" "y entre ellos se encuentra el bueno"

titulo "Paquetes con estructura de Batocera"

# Sin nada suelto en la raiz pero con drive_c/, el juego esta ahi dentro.
mkdir -p "$TMP/n5/drive_c"
printf '#!/bin/sh\n' > "$TMP/n5/drive_c/run.sh"
chmod +x "$TMP/n5/drive_c/run.sh"
r="$(juego_es_nativo "$TMP/n5")"
afirmar_igual "$r" "$TMP/n5/drive_c/run.sh" "se mira dentro de drive_c/"

titulo "Cuando no se sabe, no es nativo"

mkdir -p "$TMP/v1"
juego_es_nativo "$TMP/v1" >/dev/null
afirmar_fallo $? "una carpeta vacia no es un juego de Linux"

mkdir -p "$TMP/v2"
printf 'esto no es un ELF\n' > "$TMP/v2/datos.bin"
chmod +x "$TMP/v2/datos.bin"
juego_es_nativo "$TMP/v2" >/dev/null
afirmar_fallo $? "un fichero ejecutable que no es ELF no cuenta"

juego_es_nativo "$TMP/no_existe" >/dev/null
afirmar_fallo $? "una carpeta que no existe tampoco"

titulo "El asistente mira QUE es el juego antes de pedir Proton"

# Esto es estructura, no comportamiento, y es a proposito: el fallo de la 1.48
# no era que la comprobacion estuviera mal, era que llegaba TARDE. El asistente
# abria con "Paso 1/3 - Elige Proton/Wine" antes de mirar el juego, y a uno
# nativo le preguntaba por un runner que no iba a usar. Un tester cancelo ahi.
#
# Asi que no basta con que la comprobacion exista: tiene que ir ANTES de
# wizard_pick_runner y de wizard_prefijo. Se mide por el numero de linea
# dentro de la funcion.
_asis="$(awk '/^first_run_wizard\(\) \{/{d=1} d{print} d&&/^\}/{exit}' "$FUENTE")"

_l_nat="$(printf '%s\n' "$_asis" | grep -n 'juego_es_nativo' | head -n1 | cut -d: -f1)"
_l_run="$(printf '%s\n' "$_asis" | grep -n 'wizard_pick_runner' | head -n1 | cut -d: -f1)"
_l_pfx="$(printf '%s\n' "$_asis" | grep -n 'wizard_prefijo' | head -n1 | cut -d: -f1)"

afirmar_distinto "$_l_nat" "" "el asistente comprueba si el juego es nativo"
afirmar_distinto "$_l_run" "" "y sigue habiendo un paso de runner para Windows"

if [ -n "$_l_nat" ] && [ -n "$_l_run" ] && [ "$_l_nat" -lt "$_l_run" ]; then
    _bien "la comprobacion va ANTES de preguntar por Proton/Wine"
else
    _mal "la comprobacion va ANTES de preguntar por Proton/Wine" \
        "nativo en linea $_l_nat, runner en linea $_l_run"
fi

if [ -n "$_l_nat" ] && [ -n "$_l_pfx" ] && [ "$_l_nat" -lt "$_l_pfx" ]; then
    _bien "y antes de preguntar por el prefijo"
else
    _mal "y antes de preguntar por el prefijo" \
        "nativo en linea $_l_nat, prefijo en linea $_l_pfx"
fi

# La rama nativa se salta runner, prefijo y DLL de Windows, pero NO el resto:
# el ejecutable, los interruptores y el .keys son los mismos pasos.
# Se quitan los comentarios ANTES de mirar: el fuente explica ahi mismo que
# "wizard_dlls tampoco" aplica, y buscar el nombre a pelo casaba con esa frase
# en vez de con una llamada. Una prueba que lee comentarios no prueba nada.
_rama="$(printf '%s\n' "$_asis" | sed -n "/juego_es_nativo/,/^    fi$/p" \
    | sed 's/#.*//')"
afirmar_contiene "$_rama" "wizard_pick_exe" \
    "la rama nativa sigue eligiendo el ejecutable"
afirmar_no_contiene "$_rama" "wizard_dlls" \
    "y no pide DLL de Windows, que no aplican"

resumen
