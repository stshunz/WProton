# WPROTON_HELPER reshade.py 375a8cdb797e
# -*- coding: utf-8 -*-
# WProton - ReShade nativo de Linux (capa Vulkan)
#
# Copyright (C) 2026  stshunz y colaboradores
#
# Este programa es software libre: puedes redistribuirlo y/o modificarlo bajo
# los terminos de la Licencia Publica General GNU (GPL), version 3 o
# posterior, publicada por la Free Software Foundation.
#
# Se distribuye SIN NINGUNA GARANTIA. Ver <https://www.gnu.org/licenses/>.
# ----------------------------------------------------------------------------
# QUE ES ESTO, Y QUE NO ES
#
# Es el ReShade NATIVO de Linux (fork TheForgotten69/reshade, rama
# linux-vulkan): una capa Vulkan de verdad, con su ReShade64.so y su
# manifiesto, que se engancha a aplicaciones Vulkan nativas.
#
# NO ES el ReShade de Windows que WProton ya sabe instalar. Aquel copia una
# DLL junto al .exe y suplanta d3d9/dxgi/opengl32 DENTRO del prefijo. Cubren
# cosas distintas y por eso conviven:
#
#   ReShade (Windows)  D3D8/9/10/11/12 y OpenGL, dentro de Wine.
#                      Maduro. En juegos que solo usan Vulkan NO funciona.
#   ReShade (Linux)    capa Vulkan. Es el unico que puede tocar un juego
#                      que renderice por Vulkan (y eso incluye lo que DXVK
#                      traduce). En beta.
#
# LO QUE DICE SU AUTOR, Y HAY QUE REPETIRLE AL USUARIO
#
#   "The scope is Linux x86-64 + Vulkan + Wayland. OpenGL injection,
#    Wine/Proton integration, Windows add-ons and gamepad navigation are not
#    included."
#
# O sea: solo Wayland, sin navegacion con mando en el editor, y validado
# "primarily with RPCS3 and a small selection of Steam/Proton games". Es una
# beta y se ofrece como tal.
#
# POR QUE ES EL MISMO PATRON QUE MAKO
#
# Los dos son capas Vulkan implicitas, y dentro de umu el descubrimiento
# implicito NO sirve: pressure-vessel oculta esas carpetas para imponer las
# suyas. La receta que ya probamos con MAKO vale igual aqui: VK_LAYER_PATH al
# directorio de manifiestos y VK_INSTANCE_LAYERS con el nombre de la capa.
# ----------------------------------------------------------------------------

import json
import os
import re
import sys

VERSION = "1"

# Rutas dentro del prefijo, tal como las deja su install.sh:
#   $PREFIX/lib/reshade/ReShade64.so
#   $PREFIX/share/vulkan/implicit_layer.d/ReShade64.json
#   $PREFIX/share/reshade/reshade-shaders/{Shaders,Textures}
MANIF_REL = os.path.join("share", "vulkan", "implicit_layer.d")
MANIF_JSON = "ReShade64.json"
LIB_REL = os.path.join("lib", "reshade", "ReShade64.so")
SHADERS_REL = os.path.join("share", "reshade", "reshade-shaders")
CAPA = "VK_LAYER_reshade_64"     # de respaldo; el nombre real sale del JSON


def estado(base):
    """Que hay instalado. Devuelve un dict con ok, manifiestos, capa, lib,
    shaders y addons."""
    r = {"ok": False, "manifiestos": "", "capa": CAPA, "lib": "",
         "shaders": "", "addons": []}
    if not base or not os.path.isdir(base):
        return r

    manif = os.path.join(base, MANIF_REL)
    if not os.path.isfile(os.path.join(manif, MANIF_JSON)):
        # Un instalador mas nuevo podria mover la carpeta: se busca, pero solo
        # el manifiesto de ReShade, no cualquier capa que ande por ahi.
        manif = ""
        for actual, dirs, ficheros in os.walk(base):
            dirs.sort()
            if MANIF_JSON in ficheros:
                manif = actual
                break
        if not manif:
            return r
    r["manifiestos"] = manif

    # EL NOMBRE DE LA CAPA SALE DEL MANIFIESTO, no de una constante.
    #
    # Es lo mismo que se aprendio con MAKO: si el proyecto renombra la capa,
    # un VK_INSTANCE_LAYERS escrito a mano deja de insertar nada y el fallo es
    # mudo -el juego va igual, simplemente sin efectos-.
    try:
        with open(os.path.join(manif, MANIF_JSON), encoding="utf-8") as fh:
            d = json.load(fh)
        nombre = (d.get("layer") or {}).get("name") if isinstance(d, dict) else None
        if nombre:
            r["capa"] = nombre
    except (OSError, ValueError, AttributeError):
        pass

    lib = os.path.join(base, LIB_REL)
    if os.path.isfile(lib):
        r["lib"] = lib
    sh = os.path.join(base, SHADERS_REL)
    if os.path.isdir(sh):
        r["shaders"] = sh
    try:
        r["addons"] = sorted(f for f in os.listdir(os.path.join(base, "share", "reshade"))
                             if f.endswith((".addon", ".addon64")))
    except OSError:
        pass

    # SIN LA BIBLIOTECA NO VALE.
    #
    # Un manifiesto suelto no sirve de nada: el cargador lo lee, intenta abrir
    # el .so y falla. Mejor decir "no esta instalado" que dejar que el juego
    # arranque con una capa rota.
    r["ok"] = bool(r["lib"])
    return r


# ----------------------------------------------------------------------------
# ELECCION DEL PAQUETE
# ----------------------------------------------------------------------------

# Las publicaciones son PRE-RELEASES, asi que "latest" de la API no las
# devuelve: hay que mirar la lista de etiquetas. Y el nombre del asset puede
# cambiar entre betas, de ahi que el patron sea ancho pero exija "linux".
_ASSET = re.compile(r"reshade[^/]*linux[^/]*\.(?:tar\.(?:gz|xz|zst)|tgz|zip)$",
                    re.IGNORECASE)


def elegir_asset(urls):
    """De una lista de URLs, la del paquete de Linux. "" si no hay.

    Se exige "linux" en el nombre a proposito: el repositorio es un fork de
    ReShade y sus publicaciones pueden traer tambien los instaladores de
    Windows (.exe), que aqui no sirven para nada.
    """
    for u in urls:
        u = (u or "").strip()
        if u and _ASSET.search(u):
            return u
    return ""


def es_beta(tag):
    """True si la etiqueta parece una beta. Solo para avisar, no para excluir:
    hoy TODAS lo son."""
    return bool(re.search(r"beta|alpha|rc\d|pre", tag or "", re.IGNORECASE))


# ----------------------------------------------------------------------------
# INFORME
# ----------------------------------------------------------------------------

def informe(ruta_log):
    """Que hizo ReShade al jugar. Devuelve (estado, lineas).

    estado: "ok" | "sin_wayland" | "fallo" | "sin_rastro"

    MISMO MOTIVO QUE EN MAKO: la capa puede cargarse y no hacer nada, y sin
    esto "lo activo y no veo el editor" no tiene respuesta.
    """
    try:
        with open(ruta_log, encoding="utf-8", errors="replace") as fh:
            texto = fh.read()
    except OSError:
        return "sin_rastro", []

    if not re.search(r"reshade", texto, re.IGNORECASE):
        return "sin_rastro", []

    # EL CASO MAS PROBABLE CON DIFERENCIA: no hay Wayland.
    #
    # Esta beta es "Linux x86-64 + Vulkan + Wayland". Bajo gamescope un juego
    # puede acabar en Xwayland, y entonces la capa carga y no pinta nada.
    if re.search(r"wayland.*(not|no |fail|unavailable)|no wayland display|"
                 r"XDG_SESSION_TYPE.*x11", texto, re.IGNORECASE):
        return "sin_wayland", [
            "ReShade cargo pero no encontro Wayland.",
            "",
            "Esta version solo funciona en Wayland; bajo gamescope los juegos",
            "pueden acabar en Xwayland. Para esos usa ReShade (Windows), que",
            "va por DLL dentro del prefijo.",
        ]

    if re.search(r"Loading layer library.*ReShade|ReShade.*initialized|"
                 r"Insert instance layer \"?VK_LAYER_reshade", texto, re.IGNORECASE):
        return "ok", ["La capa de ReShade se cargo correctamente.",
                      "Pulsa Inicio dentro del juego para abrir el editor."]

    fallo = re.search(r"ReShade[^\n]*(error|failed|cannot)[^\n]*", texto,
                      re.IGNORECASE)
    if fallo:
        return "fallo", ["ReShade no pudo arrancar del todo.", "",
                         "  " + fallo.group(0).strip()[:120]]
    return "sin_rastro", []


# ----------------------------------------------------------------------------
# COMPROBACION INTERNA
# ----------------------------------------------------------------------------

def comprobar():
    import shutil
    import tempfile
    fallos = []

    def esperar(que, visto, esp):
        if visto != esp:
            fallos.append("%s: salio %r y se esperaba %r" % (que, visto, esp))

    raiz = tempfile.mkdtemp(prefix="wp-reshadelx-")

    # --- eleccion del paquete ---
    urls = [
        "https://x/releases/download/v6.8.0-beta.2/ReShade_Setup_6.8.0.exe",
        "https://x/releases/download/v6.8.0-beta.2/reshade-linux-vulkan-6.8.0-beta.2.tar.gz",
    ]
    esperar("elige el de Linux", elegir_asset(urls).split("/")[-1],
            "reshade-linux-vulkan-6.8.0-beta.2.tar.gz")
    esperar("no cuela el .exe de Windows",
            elegir_asset(["https://x/ReShade_Setup_6.8.0.exe"]), "")
    esperar("lista vacia", elegir_asset([]), "")
    esperar("es_beta", es_beta("v6.8.0-beta.2"), True)
    esperar("es_beta en una estable", es_beta("v6.8.0"), False)

    # --- estado ---
    base = os.path.join(raiz, "reshade")
    esperar("sin instalar", estado(base)["ok"], False)
    os.makedirs(os.path.join(base, MANIF_REL))
    os.makedirs(os.path.dirname(os.path.join(base, LIB_REL)))
    os.makedirs(os.path.join(base, SHADERS_REL, "Shaders"))
    with open(os.path.join(base, MANIF_REL, MANIF_JSON), "w", encoding="utf-8") as fh:
        fh.write('{"layer":{"name":"VK_LAYER_reshade_64",'
                 '"library_path":"../../../lib/reshade/ReShade64.so"}}')
    # SOLO EL MANIFIESTO NO BASTA: el cargador lo leeria y no encontraria el .so
    esperar("manifiesto sin biblioteca", estado(base)["ok"], False)
    with open(os.path.join(base, LIB_REL), "w") as fh:
        fh.write("x")
    e = estado(base)
    esperar("instalado", e["ok"], True)
    esperar("capa", e["capa"], "VK_LAYER_reshade_64")
    esperar("manifiestos", e["manifiestos"], os.path.join(base, MANIF_REL))
    if not e["shaders"]:
        fallos.append("no detecta la carpeta de shaders")
    esperar("sin complementos", e["addons"], [])

    # el nombre de la capa sale del manifiesto
    with open(os.path.join(base, MANIF_REL, MANIF_JSON), "w", encoding="utf-8") as fh:
        fh.write('{"layer":{"name":"VK_LAYER_OTRO"}}')
    esperar("sigue al manifiesto", estado(base)["capa"], "VK_LAYER_OTRO")

    # complementos
    with open(os.path.join(base, "share", "reshade", "fps_limit.addon64"), "w") as fh:
        fh.write("x")
    esperar("complemento detectado", estado(base)["addons"], ["fps_limit.addon64"])

    # --- informe ---
    def log(t):
        p = os.path.join(raiz, "l.log")
        with open(p, "w", encoding="utf-8") as fh:
            fh.write(t)
        return p

    esperar("informe ok", informe(log(
        'LAYER: Loading layer library ".../ReShade64.so"\n'))[0], "ok")
    est, l = informe(log("ReShade: no wayland display available\n"))
    esperar("informe sin wayland", est, "sin_wayland")
    if not any("Xwayland" in x for x in l):
        fallos.append("el informe no explica lo de Xwayland: %r" % l)
    esperar("informe fallo", informe(log(
        "ReShade: failed to create swapchain hook\n"))[0], "fallo")
    esperar("sin rastro", informe(log("nada que ver\n"))[0], "sin_rastro")
    esperar("log inexistente", informe(os.path.join(raiz, "no"))[0], "sin_rastro")

    shutil.rmtree(raiz, ignore_errors=True)
    return fallos


# ----------------------------------------------------------------------------
# LINEA DE ORDENES
# ----------------------------------------------------------------------------

def main(argv):
    if len(argv) < 2:
        sys.stderr.write(
            "uso: reshade.py <orden> [...]\n"
            "  estado  <carpeta>   manifiestos, capa, biblioteca y shaders\n"
            "  asset               elige la URL (lista por stdin)\n"
            "  informe <log>       que paso al jugar\n"
            "  comprobar           auto-diagnostico\n")
        return 2
    orden = argv[1]

    if orden == "comprobar":
        fallos = comprobar()
        if fallos:
            sys.stderr.write("reshade.py: %d fallo(s)\n" % len(fallos))
            for f in fallos:
                sys.stderr.write("  - %s\n" % f)
            return 1
        print("reshade.py: todo correcto")
        return 0

    if orden == "asset":
        u = elegir_asset(sys.stdin.read().split("\n"))
        if not u:
            return 1
        sys.stdout.write(u)
        return 0

    if len(argv) < 3:
        sys.stderr.write("reshade.py %s: falta la carpeta\n" % orden)
        return 2

    if orden == "estado":
        e = estado(argv[2])
        if not e["ok"]:
            return 1
        for k in ("manifiestos", "capa", "lib", "shaders"):
            print("%s\t%s" % (k, e[k]))
        print("addons\t%s" % " ".join(e["addons"]))
        return 0

    if orden == "informe":
        est, lineas = informe(argv[2])
        for l in lineas:
            print(l)
        return 0 if est in ("ok", "sin_rastro") else 1

    sys.stderr.write("reshade.py: orden desconocida %r\n" % orden)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
