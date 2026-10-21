#!/usr/bin/env bash
# ===========================================================================
# Compila la capa de Vulkan de WProton. SIN SUDO Y SIN INSTALAR NADA.
# ===========================================================================
#
# Las dos arquitecturas, porque hacen falta las dos: un juego de 32 bits bajo
# Proton crea su Vulkan de 32 bits, y una capa de 64 no le sirve de nada. El
# cargador intenta las dos y descarta la que no encaja, asi que conviven.
#
# LAS CABECERAS NO SE PIDEN AL SISTEMA. Se traen a vendor/ como en el
# compilar.sh de XPectrum: quien compile esto no tiene por que tener el SDK de
# Vulkan instalado, y pedirselo seria pedirle que ensucie su sistema para
# compilar un .so de 16 KB. Si ya las tiene, se usan las suyas y no se baja
# nada.
#
# Uso:
#   ./compilar.sh              las dos arquitecturas, si se puede
#   ./compilar.sh 64           solo 64 bits
#   ./compilar.sh limpiar      borra lo compilado
set -u
AQUI="$(cd "$(dirname "$0")" && pwd)"
VENDOR="$AQUI/vendor"
CC="${CC:-gcc}"
ok=0; fallos=0

say()  { printf '%s\n' "$*"; }
bien() { printf '[+] %s\n' "$*"; ok=$((ok+1)); }
mal()  { printf '[!] %s\n' "$*"; fallos=$((fallos+1)); }

case "${1:-todo}" in
    limpiar)
        rm -f "$AQUI"/libwproton_capa.*.so
        say "Limpio. Las cabeceras de vendor/ se quedan (no cuesta nada)."
        exit 0 ;;
esac

# --- las cabeceras ---------------------------------------------------------
INC=""
# El orden importa: primero las del sistema -si estan, son las suyas y no hay
# que traer nada-, y despues las dos formas en que pueden acabar en vendor/:
# copiadas a mano, o clonadas por este mismo guion.
for d in /usr/include "$VENDOR/include" "$VENDOR/Vulkan-Headers/include"; do
    [ -f "$d/vulkan/vulkan.h" ] && [ -f "$d/vulkan/vk_layer.h" ] && { INC="$d"; break; }
done
if [ -z "$INC" ]; then
    say "No estan las cabeceras de Vulkan; se traen a vendor/ (una vez)."
    mkdir -p "$VENDOR" || exit 1
    # Si ya estan a medio traer de otra vez, no se vuelve a clonar encima.
    if [ ! -d "$VENDOR/Vulkan-Headers" ] && command -v git >/dev/null 2>&1; then
        git clone --depth 1 https://github.com/KhronosGroup/Vulkan-Headers \
            "$VENDOR/Vulkan-Headers" >/dev/null 2>&1 || true
    fi
    if [ -f "$VENDOR/Vulkan-Headers/include/vulkan/vk_layer.h" ]; then
        INC="$VENDOR/Vulkan-Headers/include"
    else
        say "[!] No se han podido traer las cabeceras."
        say "    Opciones: instala vulkan-headers con tu gestor de paquetes,"
        say "    o copia a mano Vulkan-Headers/include en:"
        say "      $VENDOR/include"
        exit 1
    fi
fi
say "Cabeceras: $INC"

# --- compilar --------------------------------------------------------------
#
# -fvisibility=hidden NO es un adorno: una capa solo puede exportar las dos
# puertas que el cargador busca. Si se exportan mas simbolos -y una .so los
# exporta TODOS por omision- se pisan los del juego o los del propio cargador,
# y eso revienta de formas que no apuntan a la capa.
compila() {
    local marca="$1" arch="$2" extra="$3"
    local salida="$AQUI/libwproton_capa.$arch.so"
    # shellcheck disable=SC2086
    if $CC $extra -O2 -fPIC -shared -fvisibility=hidden \
            -I"$INC" -o "$salida" "$AQUI/wproton_capa.c" 2>"$AQUI/.err.$arch"; then
        # Y SE COMPRUEBA QUE EXPORTE LO QUE TIENE QUE EXPORTAR, ni mas ni
        # menos: un .so que compila pero no exporta las puertas se carga y no
        # hace nada, y eso desde fuera parece "la capa no funciona".
        local n m
        n="$(nm -D --defined-only "$salida" 2>/dev/null | grep -c ' T wproton_Get')"
        # Y LA PUERTA MODERNA: los cargadores de ahora preguntan por aqui en vez
        # de buscar las funciones por su nombre dentro del .so. Sin ella, la capa
        # se carga en un equipo viejo y no en uno nuevo, y eso desde fuera
        # parece "a veces funciona".
        m="$(nm -D --defined-only "$salida" 2>/dev/null | grep -c ' T vkNegotiateLoaderLayerInterfaceVersion')"
        if [ "${n:-0}" = 2 ] && [ "${m:-0}" = 1 ]; then
            bien "$marca: $(basename "$salida")"
            rm -f "$AQUI/.err.$arch"
        else
            mal "$marca: compila pero no exporta las puertas (vio $n de las dos de siempre y $m de la moderna)"
        fi
    else
        mal "$marca: no compila"
        sed 's/^/      /' "$AQUI/.err.$arch" | head -5
        rm -f "$AQUI/.err.$arch"
    fi
}

case "${1:-todo}" in
    64|todo) compila "64 bits" "x86_64" "" ;;
esac
case "${1:-todo}" in
    32|todo)
        if printf 'int main(void){return 0;}' | $CC -m32 -x c - -o /dev/null 2>/dev/null; then
            compila "32 bits" "x86" "-m32"
        else
            say "[i] 32 bits: falta el soporte multilib del compilador."
            say "    En Arch/CachyOS: pacman -S lib32-gcc-libs"
            say "    Sin el, los juegos de 32 bits no tendran menu dentro."
        fi ;;
esac

say ""
say "Listo: $ok compilada(s), $fallos fallo(s)."
[ "$fallos" = 0 ]
