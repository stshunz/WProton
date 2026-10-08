# WPROTON_HELPER mako.py 71dbfd484f6e
# -*- coding: utf-8 -*-
# WProton - MAKO Renderer (generacion de fotogramas por capa Vulkan)
#
# Copyright (C) 2026  stshunz y colaboradores
#
# Este programa es software libre: puedes redistribuirlo y/o modificarlo bajo
# los terminos de la Licencia Publica General GNU (GPL), version 3 o
# posterior, publicada por la Free Software Foundation.
#
# Se distribuye SIN NINGUNA GARANTIA. Ver <https://www.gnu.org/licenses/>.
# ----------------------------------------------------------------------------
# QUE SUSTITUYE
#
#   mako_disponible()  -> estado()
#   mako_dll()         -> buscar_dll()
#   mako_asset_de()    -> elegir_asset()
#   mako_informe()     -> informe()
#
# POR QUE EXISTE
#
# Estas cuatro nacieron en bash, y no encajaban con el resto: dll_informe lee
# el registro con dlls.py -Python, con pruebas- y mako_informe hacia lo mismo
# con grep. La eleccion del paquete a descargar era un grep suelto que solo se
# habia probado a mano una vez. Misma tarea, dos criterios distintos.
#
# Lo que se queda en bash es lo que debe: mako_exportar (pone variables de
# entorno en el proceso que va a lanzar el juego), mako_instalar (descarga y
# ejecuta) y las etiquetas de menu.
# ----------------------------------------------------------------------------

import os
import re
import sys

VERSION = "1"

# El directorio PRIVADO de manifiestos. El instalador deja dos juegos: este y
# el estandar (share/vulkan/implicit_layer.d). Se usa el privado porque el
# estandar es justo el que pressure-vessel enmascara para imponer el suyo.
MANIF_REL = "share/mako-render/vulkan/implicit_layer.d"
CAPA = "VK_LAYER_MAKO_render"


def estado(base):
    """Que hay instalado en la carpeta de MAKO. Devuelve un dict.

    claves: ok, manifiestos, capa, lib64, lib32, dll
    """
    r = {"ok": False, "manifiestos": "", "capa": CAPA,
         "lib64": "", "lib32": "", "dll": ""}
    if not base or not os.path.isdir(base):
        return r
    manif = os.path.join(base, MANIF_REL)
    if not os.path.isdir(manif):
        # Un instalador mas nuevo podria mover la carpeta: se busca, pero SIN
        # aceptar la estandar, que dentro del contenedor no sirve.
        for actual, dirs, _f in os.walk(base):
            dirs.sort()
            if actual.endswith(os.path.join("mako-render", "vulkan",
                                            "implicit_layer.d")):
                manif = actual
                break
    if not os.path.isfile(os.path.join(manif, "VkLayer_MAKO_render.json")):
        return r
    r["manifiestos"] = manif

    # El nombre real de la capa sale del manifiesto, no de una constante: si
    # el proyecto lo cambia, VK_INSTANCE_LAYERS tiene que seguirlo o no se
    # inserta nada.
    try:
        import json
        with open(os.path.join(manif, "VkLayer_MAKO_render.json"),
                  encoding="utf-8") as fh:
            d = json.load(fh)
        nombre = (d.get("layer") or {}).get("name") if isinstance(d, dict) else None
        if nombre:
            r["capa"] = nombre
    except (OSError, ValueError, AttributeError):
        pass

    for clave, sub in (("lib64", "lib"), ("lib32", "lib32")):
        p = os.path.join(base, sub, "libmako-render.so")
        if os.path.isfile(p):
            r[clave] = p
    r["ok"] = bool(r["lib64"])
    r["dll"] = buscar_dll(base)
    return r


def buscar_dll(base, extra=()):
    """El Lossless.dll. Primero el de la carpeta portable, luego los de Steam.

    NUNCA se descarga ni se copia: es de pago y es del usuario. WProton puede
    localizarlo, jamas proporcionarlo.
    """
    candidatos = [os.path.join(base, "Lossless.dll"),
                  os.path.join(base, "share", "mako-render", "Lossless.dll")]
    for c in candidatos:
        if os.path.isfile(c):
            return c
    for raiz in extra:
        if not raiz or not os.path.isdir(raiz):
            continue
        for actual, dirs, ficheros in os.walk(raiz):
            dirs.sort()
            if actual.count(os.sep) - raiz.count(os.sep) > 8:
                dirs[:] = []
                continue
            for f in ficheros:
                if f.lower() == "lossless.dll":
                    return os.path.join(actual, f)
    return ""


# ----------------------------------------------------------------------------
# ELECCION DEL PAQUETE A DESCARGAR
# ----------------------------------------------------------------------------

# El nombre ha cambiado entre versiones ("mako-render-v2.0.0" y
# "MAKO-Renderer-v3.1.0"), asi que se aceptan las dos formas.
_ASSET = re.compile(r"mako[-_]?render(er)?-v[0-9][^/]*-linux\.tar\.xz$",
                    re.IGNORECASE)


def elegir_asset(urls):
    """De una lista de URLs, la del Renderer para Linux. "" si no hay.

    AQUI ESTA LA TRAMPA DE ESTE REPOSITORIO: el "latest" es el ZIP de MAKO
    Decky, no el Renderer, y el filtro generico de WProton (filter_assets)
    solo quita arquitecturas y firmas, asi que el ZIP pasa. Bajar ese en vez
    del Renderer instalaria un complemento de Steam Deck que no tiene nada que
    ver, y el error saldria mucho despues y sin relacion aparente.
    """
    for u in urls:
        u = (u or "").strip()
        if u and _ASSET.search(u):
            return u
    return ""


# ----------------------------------------------------------------------------
# INFORME DE LO QUE PASO AL JUGAR
# ----------------------------------------------------------------------------

def informe(ruta_log):
    """Que hizo MAKO de verdad. Devuelve (estado, lineas).

    estado: "ok" | "sin_dll" | "fallo" | "sin_rastro"

    POR QUE HACE FALTA
    ------------------
    MAKO degrada con elegancia: si no puede generar fotogramas lo dice en el
    registro y sigue con la presentacion normal. El juego funciona y el
    usuario no ve nada raro... ni nada mejor. Sin esto, "lo he activado y no
    noto diferencia" no tiene respuesta.
    """
    try:
        with open(ruta_log, encoding="utf-8", errors="replace") as fh:
            texto = fh.read()
    except OSError:
        return "sin_rastro", []

    if "frame-generation context initialization failed" not in texto:
        if "render layer active" in texto:
            return "ok", ["La capa se aplico correctamente."]
        return "sin_rastro", []

    lineas = ["MAKO no pudo generar fotogramas.",
              "El juego fue con la presentacion normal, sin generacion."]

    # El caso mas comun con diferencia: un Lossless Scaling antiguo, cuyo DLL
    # no trae los modelos que MAKO necesita.
    if re.search(r"does not contain LSFG resource|Unable to build shader registry",
                 texto):
        lineas += [
            "",
            "Motivo: tu Lossless.dll no trae los modelos que MAKO necesita.",
            "Suele ser una version antigua de Lossless Scaling.",
            "",
            "Actualizalo en Steam. Si aun asi falla, en Propiedades > Betas",
            "hay una rama 'lsfg-vk' pensada para esta capa.",
        ]
        return "sin_dll", lineas

    # Otro motivo: se enseñan las lineas que da el propio MAKO, que empiezan
    # por "- ". Mas vale un mensaje suyo que uno inventado por nosotros.
    detalle = []
    visto = False
    for l in texto.split("\n"):
        if "frame-generation context initialization failed" in l:
            visto = True
            continue
        if visto:
            l = l.strip()
            if l.startswith("- "):
                detalle.append("  " + l)
                if len(detalle) >= 4:
                    break
            elif l:
                break
    if detalle:
        lineas += ["", "Motivo (del registro):"] + detalle
    return "fallo", lineas


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

    raiz = tempfile.mkdtemp(prefix="wp-mako-")

    # --- eleccion del paquete: LA TRAMPA DEL REPOSITORIO ---
    urls = [
        "https://x/releases/download/plugin-v3.0.0/MAKO-Decky.zip",
        "https://x/releases/download/render-v3.2.0/MAKO-Renderer-v3.2.0-flatpak.tar.xz",
        "https://x/releases/download/render-v3.2.0/MAKO-Renderer-v3.2.0-linux.tar.xz",
    ]
    esperar("elige el de Linux", elegir_asset(urls).split("/")[-1],
            "MAKO-Renderer-v3.2.0-linux.tar.xz")
    esperar("nombre antiguo",
            elegir_asset(["https://x/mako-render-v2.0.0-linux.tar.xz"]).split("/")[-1],
            "mako-render-v2.0.0-linux.tar.xz")
    esperar("solo el ZIP de Decky: nada",
            elegir_asset(["https://x/MAKO-Decky.zip"]), "")
    esperar("lista vacia", elegir_asset([]), "")
    esperar("no cuela el de flatpak",
            elegir_asset(["https://x/MAKO-Renderer-v3.2.0-flatpak.tar.xz"]), "")

    # --- estado ---
    base = os.path.join(raiz, "mako")
    esperar("sin instalar", estado(base)["ok"], False)
    manif = os.path.join(base, MANIF_REL)
    os.makedirs(manif)
    os.makedirs(os.path.join(base, "lib"))
    os.makedirs(os.path.join(base, "lib32"))
    with open(os.path.join(manif, "VkLayer_MAKO_render.json"), "w",
              encoding="utf-8") as fh:
        fh.write('{"layer":{"name":"VK_LAYER_MAKO_render",'
                 '"library_path":"../../../../lib/libmako-render.so"}}')
    esperar("con manifiesto pero sin la biblioteca", estado(base)["ok"], False)
    for sub in ("lib", "lib32"):
        with open(os.path.join(base, sub, "libmako-render.so"), "w") as fh:
            fh.write("x")
    e = estado(base)
    esperar("instalado", e["ok"], True)
    esperar("nombre de la capa", e["capa"], "VK_LAYER_MAKO_render")
    esperar("manifiestos", e["manifiestos"], manif)
    if not e["lib32"]:
        fallos.append("no detecta la capa de 32 bits")
    esperar("sin Lossless.dll", e["dll"], "")

    # el nombre de la capa sale del manifiesto, no de una constante
    with open(os.path.join(manif, "VkLayer_MAKO_render.json"), "w",
              encoding="utf-8") as fh:
        fh.write('{"layer":{"name":"VK_LAYER_OTRO_NOMBRE"}}')
    esperar("sigue al manifiesto", estado(base)["capa"], "VK_LAYER_OTRO_NOMBRE")

    # --- Lossless.dll ---
    with open(os.path.join(base, "Lossless.dll"), "w") as fh:
        fh.write("x")
    esperar("dll en la carpeta portable", os.path.basename(buscar_dll(base)),
            "Lossless.dll")
    os.unlink(os.path.join(base, "Lossless.dll"))
    steam = os.path.join(raiz, "steam", "common", "LosslessScaling")
    os.makedirs(steam)
    with open(os.path.join(steam, "Lossless.dll"), "w") as fh:
        fh.write("x")
    esperar("dll en Steam", buscar_dll(base, [os.path.join(raiz, "steam")]),
            os.path.join(steam, "Lossless.dll"))
    esperar("sin dll en ningun sitio", buscar_dll(base, [raiz + "/no"]), "")

    # --- informe ---
    def log(texto):
        p = os.path.join(raiz, "l.log")
        with open(p, "w", encoding="utf-8") as fh:
            fh.write(texto)
        return p

    est, l = informe(log("MAKO Renderer: render layer active; build=3.2.0\n"))
    esperar("informe ok", est, "ok")
    est, l = informe(log(
        "MAKO Renderer: frame-generation context initialization failed;\n"
        "- failed to create backend instance\n"
        "- Unable to build shader registry\n"
        "- Lossless.dll does not contain LSFG resource 305\n"))
    esperar("informe sin dll", est, "sin_dll")
    if not any("Lossless Scaling" in x for x in l):
        fallos.append("el informe no explica lo del Lossless.dll: %r" % l)
    est, l = informe(log(
        "MAKO Renderer: frame-generation context initialization failed;\n"
        "- algo raro del driver\n"
        "- y otra cosa\n"))
    esperar("informe fallo generico", est, "fallo")
    if not any("algo raro" in x for x in l):
        fallos.append("el informe no enseña el motivo del registro: %r" % l)
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
            "uso: mako.py <orden> [...]\n"
            "  estado  <carpeta>            manifiestos, capa y bibliotecas\n"
            "  dll     <carpeta> [donde...] localiza el Lossless.dll\n"
            "  asset                        elige la URL (lista por stdin)\n"
            "  informe <log>                que paso al jugar\n"
            "  comprobar                    auto-diagnostico\n")
        return 2
    orden = argv[1]

    if orden == "comprobar":
        fallos = comprobar()
        if fallos:
            sys.stderr.write("mako.py: %d fallo(s)\n" % len(fallos))
            for f in fallos:
                sys.stderr.write("  - %s\n" % f)
            return 1
        print("mako.py: todo correcto")
        return 0

    if orden == "asset":
        u = elegir_asset(sys.stdin.read().split("\n"))
        if not u:
            return 1
        sys.stdout.write(u)
        return 0

    if len(argv) < 3:
        sys.stderr.write("mako.py %s: falta la carpeta\n" % orden)
        return 2

    if orden == "estado":
        e = estado(argv[2])
        if not e["ok"]:
            return 1
        # Una linea por clave: bash lo lee con read sin liarse con comillas.
        for k in ("manifiestos", "capa", "lib64", "lib32", "dll"):
            print("%s\t%s" % (k, e[k]))
        return 0

    if orden == "dll":
        d = buscar_dll(argv[2], argv[3:])
        if not d:
            return 1
        sys.stdout.write(d)
        return 0

    if orden == "informe":
        est, lineas = informe(argv[2])
        for l in lineas:
            print(l)
        return 0 if est in ("ok", "sin_rastro") else 1

    sys.stderr.write("mako.py: orden desconocida %r\n" % orden)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
