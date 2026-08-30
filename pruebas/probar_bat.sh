#!/usr/bin/env bash
# Prueba: el .bat de instalacion se ejecuta UNA vez.
#
# Copyright (C) 2026  stshunz y colaboradores. GPL v3 o posterior.
# ----------------------------------------------------------------------------
# POR QUE ESTA PRUEBA
#
# Hay .bat que instalan dependencias la primera vez y luego arrancan el juego.
# Si se ejecutan siempre, se reinstala en cada arranque: minutos de espera.
#
# La logica estaba dentro de launch_game, y por ahi NO pasan los juegos en
# carpeta. A esos se les reinstalaba cada vez. Se saco a bat_resolver_instalacion
# para que la usen los dos caminos.
#
# La ultima parte de esta prueba comprueba precisamente eso: que la funcion
# comun se llama desde los DOS caminos de lanzamiento. Sin ella, la prueba
# pasaria igual con el fallo puesto, que es lo que ya paso una vez.
# ----------------------------------------------------------------------------
. "$(cd "$(dirname "$0")" && pwd)/comun.sh"

cargar_funcion bat_juego_real bat_ya_instalado bat_marcar_instalado \
               bat_resolver_instalacion

PROFILE_DIR="$TMP/profiles"
mkdir -p "$PROFILE_DIR" "$TMP/juego"

titulo "Sacar el juego de verdad de la linea START"

cat > "$TMP/juego/instalar.bat" <<'FIN'
@echo off
IF EXIST c:\marca\ ( echo ya ) ELSE ( "dependencies\VC_redist.x64.exe" /quiet )
START "" "Tatsunoko.exe"
FIN
afirmar_igual "$(bat_juego_real "$TMP/juego/instalar.bat")" "Tatsunoko.exe" \
    "START con titulo vacio y exe entre comillas"

printf 'START Juego.exe\r\n' > "$TMP/juego/b2.bat"
afirmar_igual "$(bat_juego_real "$TMP/juego/b2.bat")" "Juego.exe" \
    "START sin comillas y con fin de linea de Windows"

printf 'start "" "bin\\game.exe" -windowed\r\n' > "$TMP/juego/b3.bat"
afirmar_igual "$(bat_juego_real "$TMP/juego/b3.bat")" "bin\\game.exe" \
    "en minusculas, con ruta dentro y argumentos detras"

printf '  START  "Mi Juego"  "run.exe"\r\n' > "$TMP/juego/b4.bat"
afirmar_igual "$(bat_juego_real "$TMP/juego/b4.bat")" "run.exe" \
    "con titulo de verdad, el titulo no se confunde con el exe"

titulo "La ULTIMA linea START es el juego"

cat > "$TMP/juego/b5.bat" <<'FIN'
START "" "instalador.exe"
START "" "ElJuego.exe"
FIN
afirmar_igual "$(bat_juego_real "$TMP/juego/b5.bat")" "ElJuego.exe" \
    "si lanza varias cosas, el juego es lo ultimo que abre"

titulo "Cuando no hay nada que sacar"

printf '@echo off\nsetup.exe /S\n' > "$TMP/juego/b6.bat"
bat_juego_real "$TMP/juego/b6.bat" >/dev/null
afirmar_fallo $? "un .bat sin START no dice cual es el juego"

bat_juego_real "$TMP/juego/no_existe.bat" >/dev/null
afirmar_fallo $? "un .bat que no existe devuelve fallo"

titulo "La marca de instalado"

afirmar_fallo "$(bat_ya_instalado juegoA; echo $?)" "de entrada no esta instalado"
bat_marcar_instalado juegoA
afirmar_ok "$(bat_ya_instalado juegoA; echo $?)" "despues de marcarlo, si"
afirmar_fichero "$PROFILE_DIR/.juegoA.instalado" \
    "la marca vive en profiles/, no dentro del prefijo"
afirmar_fallo "$(bat_ya_instalado ''; echo $?)" "sin gid no se da por instalado"

titulo "La decision completa: primera vez y siguientes"

mkdir -p "$TMP/paquete"
printf 'START "" "Tatsunoko.exe"\r\n' > "$TMP/paquete/instalar.bat"
: > "$TMP/paquete/Tatsunoko.exe"

EXE_PATH="$TMP/paquete/instalar.bat"
limpiar_say
bat_resolver_instalacion juegoB
afirmar_igual "$EXE_PATH" "$TMP/paquete/instalar.bat" \
    "la primera vez se ejecuta el .bat"
afirmar_contiene "$SALIDA_SAY" "Primera vez" "y se dice que es la primera vez"

EXE_PATH="$TMP/paquete/instalar.bat"
limpiar_say
bat_resolver_instalacion juegoB
afirmar_igual "$EXE_PATH" "$TMP/paquete/Tatsunoko.exe" \
    "la segunda vez se va derecho al juego"
afirmar_contiene "$SALIDA_SAY" "directamente" "y se avisa de que no se repite"

titulo "Casos en los que NO se toca nada"

EXE_PATH="$TMP/paquete/Tatsunoko.exe"
bat_resolver_instalacion juegoC
afirmar_igual "$EXE_PATH" "$TMP/paquete/Tatsunoko.exe" \
    "si el ejecutable no es un .bat, se deja como esta"

EXE_PATH="$TMP/paquete/instalar.bat"
bat_resolver_instalacion ""
afirmar_igual "$EXE_PATH" "$TMP/paquete/instalar.bat" \
    "sin gid no se decide nada"

# El .bat apunta a un exe que no esta: se ejecuta el .bat tal cual y NO se
# marca como instalado, porque no se ha resuelto nada.
printf 'START "" "NoEsta.exe"\r\n' > "$TMP/paquete/roto.bat"
EXE_PATH="$TMP/paquete/roto.bat"
limpiar_say
bat_resolver_instalacion juegoD
afirmar_igual "$EXE_PATH" "$TMP/paquete/roto.bat" \
    "si el juego que anuncia el .bat no esta, se ejecuta el .bat"
afirmar_no_fichero "$PROFILE_DIR/.juegoD.instalado" \
    "y no se marca como instalado: no se ha resuelto nada"

titulo "Los .cmd cuentan igual que los .bat"

cp "$TMP/paquete/instalar.bat" "$TMP/paquete/arranque.cmd"
EXE_PATH="$TMP/paquete/arranque.cmd"
bat_resolver_instalacion juegoE
afirmar_fichero "$PROFILE_DIR/.juegoE.instalado" "un .cmd tambien se resuelve"

# Y con la extension en mayusculas, que en Windows es lo normal.
cp "$TMP/paquete/instalar.bat" "$TMP/paquete/INSTALL.BAT"
EXE_PATH="$TMP/paquete/INSTALL.BAT"
bat_resolver_instalacion juegoF
afirmar_fichero "$PROFILE_DIR/.juegoF.instalado" \
    "INSTALL.BAT en mayusculas se reconoce igual"

titulo "La funcion comun se llama desde los DOS caminos"

# Esto no prueba comportamiento, prueba estructura, y es a proposito: el fallo
# original no era que la logica estuviera mal, era que vivia en un solo camino.
# Una prueba de comportamiento habria pasado con el fallo puesto.
_llamadas="$(grep -c 'bat_resolver_instalacion' "$FUENTE")"
afirmar_distinto "$_llamadas" "1" \
    "bat_resolver_instalacion no esta solo definida: se llama"

_en_launch_game="$(awk '/^launch_game\(\) \{/{d=1} d{print} d&&/^\}/{exit}' \
    "$FUENTE" | grep -c 'bat_resolver_instalacion')"
afirmar_distinto "$_en_launch_game" "0" \
    "launch_game llama a bat_resolver_instalacion"

_en_loose="$(awk '/^launch_loose_exe\(\) \{/{d=1} d{print} d&&/^\}/{exit}' \
    "$FUENTE" | grep -c 'bat_resolver_instalacion')"
afirmar_distinto "$_en_loose" "0" \
    "launch_loose_exe tambien (los juegos en carpeta van por aqui)"

resumen
