#!/usr/bin/env bash
# Prueba: reconocer un prefijo de Wine de 32 bits.
#
# Copyright (C) 2026  stshunz y colaboradores. GPL v3 o posterior.
# ----------------------------------------------------------------------------
# POR QUE ESTA PRUEBA
#
# Hay paquetes con prefijos de 32 bits -PES 6 entre ellos-. Sin declararlo,
# Wine los trata como de 64 y muere con un error que NO menciona la
# arquitectura, asi que parece un juego roto y se pierde la tarde buscando.
#
# Se decide por dos caminos independientes, y con uno basta:
#   1. "#arch=win32" en system.reg, que lo escribe Wine;
#   2. no hay syswow64, que SOLO existe en los prefijos de 64.
#
# Que sean dos importa: hay prefijos sin system.reg legible, y hay prefijos
# donde syswow64 existe por otro motivo. Se prueban los dos por separado para
# que si uno se rompe no lo tape el otro.
# ----------------------------------------------------------------------------
. "$(cd "$(dirname "$0")" && pwd)/comun.sh"

cargar_funcion prefijo_es_32

# ---------------------------------------------------------------------------
# Constructores de prefijos de mentira. Se hacen con funciones porque cada
# prueba necesita uno distinto y a mano seria ilegible.
# ---------------------------------------------------------------------------
prefijo_64() {
    local d="$1"
    mkdir -p "$d/drive_c/windows/system32" "$d/drive_c/windows/syswow64"
    printf 'WINE REGISTRY Version 2\n#arch=win64\n' > "$d/system.reg"
}
prefijo_32() {
    local d="$1"
    mkdir -p "$d/drive_c/windows/system32"
    printf 'WINE REGISTRY Version 2\n#arch=win32\n' > "$d/system.reg"
}

titulo "Los dos casos claros"

prefijo_32 "$TMP/p32"
prefijo_es_32 "$TMP/p32"
afirmar_ok $? "un prefijo de 32 se reconoce"

prefijo_64 "$TMP/p64"
prefijo_es_32 "$TMP/p64"
afirmar_fallo $? "un prefijo de 64 no se confunde"

titulo "Cada camino por separado"

# Solo la marca del registro: syswow64 esta, asi que si acierta es por el .reg.
mkdir -p "$TMP/solo_reg/drive_c/windows/system32" \
         "$TMP/solo_reg/drive_c/windows/syswow64"
printf 'WINE REGISTRY Version 2\n#arch=win32\n' > "$TMP/solo_reg/system.reg"
prefijo_es_32 "$TMP/solo_reg"
afirmar_ok $? "la marca #arch=win32 basta aunque exista syswow64"

# Solo la ausencia de syswow64: sin system.reg, si acierta es por la carpeta.
mkdir -p "$TMP/solo_dir/drive_c/windows/system32"
prefijo_es_32 "$TMP/solo_dir"
afirmar_ok $? "sin syswow64 basta aunque no haya system.reg"

titulo "Detalles del fichero de registro"

# Wine escribe "#arch=win32"; se acepta sin mirar mayusculas, pero tiene que
# ir al principio de la linea: una mencion suelta dentro del registro no vale.
mkdir -p "$TMP/mayus/drive_c/windows/system32" \
         "$TMP/mayus/drive_c/windows/syswow64"
printf 'WINE REGISTRY Version 2\n#ARCH=WIN32\n' > "$TMP/mayus/system.reg"
prefijo_es_32 "$TMP/mayus"
afirmar_ok $? "la marca se lee sin distinguir mayusculas"

mkdir -p "$TMP/mencion/drive_c/windows/system32" \
         "$TMP/mencion/drive_c/windows/syswow64"
printf 'WINE REGISTRY Version 2\n"algo"="#arch=win32"\n' > "$TMP/mencion/system.reg"
prefijo_es_32 "$TMP/mencion"
afirmar_fallo $? "una mencion a win32 dentro de un valor no cuenta como marca"

titulo "El formato de Proton, con pfx/ dentro"

mkdir -p "$TMP/proton32"
prefijo_32 "$TMP/proton32/pfx"
prefijo_es_32 "$TMP/proton32"
afirmar_ok $? "se mira dentro de pfx/ cuando existe"

mkdir -p "$TMP/proton64"
prefijo_64 "$TMP/proton64/pfx"
prefijo_es_32 "$TMP/proton64"
afirmar_fallo $? "y un pfx/ de 64 sigue siendo de 64"

titulo "Cosas que no son un prefijo"

prefijo_es_32 "$TMP/no_existe"
afirmar_fallo $? "una carpeta que no existe no es un prefijo de 32"

prefijo_es_32 ""
afirmar_fallo $? "la ruta vacia tampoco"

# Una carpeta cualquiera: sin drive_c/windows/system32 no se puede decidir por
# la ausencia de syswow64, porque TODAS las carpetas del mundo no lo tienen.
mkdir -p "$TMP/carpeta_boba"
prefijo_es_32 "$TMP/carpeta_boba"
afirmar_fallo $? "una carpeta vacia no se toma por un prefijo de 32"

titulo "Avisar de que Proton no puede con ellos"

# Proton crea y espera siempre prefijos de 64, asi que con uno de 32 falla
# igual. El aviso tiene que existir en el fuente y decir que hay que cambiar
# el runner a uno de tipo Wine, que es la salida de verdad.
_aviso="$(grep -in 'win32\|32 bits' "$FUENTE" | grep -ic 'wine')"
afirmar_distinto "$_aviso" "0" \
    "el fuente relaciona los prefijos de 32 con cambiar a un runner Wine"

resumen
