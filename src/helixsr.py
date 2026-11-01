# WPROTON_HELPER helixsr.py 000000000000
# -*- coding: utf-8 -*-
# WProton - HelixSR (la red de DLSS corriendo como shaders de computo en D3D12)
#
# Copyright (C) 2026  stshunz y colaboradores
#
# Este programa es software libre: puedes redistribuirlo y/o modificarlo bajo
# los terminos de la Licencia Publica General GNU (GPL), version 3 o
# posterior, publicada por la Free Software Foundation.
#
# Se distribuye SIN NINGUNA GARANTIA. Ver <https://www.gnu.org/licenses/>.
# ----------------------------------------------------------------------------
# QUE ES HELIXSR Y POR QUE NO SE PARECE A MAKO
#
# MAKO es una CAPA DE VULKAN: se enciende con variables de entorno y el juego
# no se toca. HelixSR es lo contrario: una DLL DE WINDOWS que se mete DENTRO de
# la carpeta del juego ocupando el sitio de la DLL de FSR 3.1 del propio juego,
# que se guarda al lado como "*.original.dll". Dentro del juego se elige
# "AMD FSR" y lo que responde es la red de DLSS (Model E) compilada como
# shaders de computo de Direct3D 12.
#
# Asi que el camino de WProton es el de OptiScaler y dgVoodoo2 (apartado 14):
# ficheros dentro del juego, que en los .wsquashfs caen en el overlay (upper/)
# y por tanto no tocan el archivo original.
#
# LO QUE NO SE PUEDE REDISTRIBUIR -Y POR QUE ESTO IMPORTA AQUI
#
# La descarga de HelixSR NO TRAE LA RED. Su instalador baja la DLL de DLSS de
# NVIDIA y CONSTRUYE la red en el equipo. Su licencia dice que esa DLL
# resultante es para el PC de quien la construyo y que no se comparta. Un
# .wsquashfs se pasa a otra gente, asi que el empaquetado tiene que SACAR
# HelixSR y devolver la DLL del juego. Eso lo hace helixsr_antes_de_empaquetar
# en bash usando "juego" y "quitar" de aqui.
#
# DE DONDE SALE LO QUE SE SABE DE LOS FICHEROS
#
# Lo de "como se reconoce HelixSR" (la cadena dentro de la DLL, la marca al
# final del fichero cuando la red ya esta dentro, el nombre del respaldo y el
# JSON del instalador oficial) esta tomado del DeckyHelixSRManager de
# PeroTuncay, que es de dominio publico (Unlicense) y es la herramienta que ya
# hace esto en SteamOS. Se mantiene EL MISMO formato a proposito: asi su
# desinstalador entiende lo que instala WProton y al contrario.
#
# QUE SUSTITUYE / QUE SE QUEDA EN BASH
#
# Aqui: elegir el paquete de la release, reconocer la DLL, saber si la red esta
# construida, mirar si un .exe es de Direct3D 12, recorrer la carpeta del juego
# y leer helixsr.log y el registro del instalador.
#
# En bash: descargar, ejecutar el instalador de HelixSR, copiar/renombrar
# ficheros, las etiquetas de menu y los avisos.
# ----------------------------------------------------------------------------

import json
import os
import re
import struct
import sys

VERSION = "1"

# Los dos nombres que puede tener la DLL de FSR 3.1 de un juego. El primero es
# el del upscaler; el segundo lo usan los juegos que no traen el primero.
NOMBRES_FSR = ("amd_fidelityfx_upscaler_dx12.dll", "amd_fidelityfx_dx12.dll")

# El respaldo que deja el instalador oficial: "nombre.original.dll".
SUFIJO_ORIG = ".original.dll"
# Marca del instalador oficial al lado de la DLL.
MARCA_INSTALL = "helixsr-install.json"
# La red, cuando va PEGADA AL FINAL de la DLL: estos 8 bytes a 32 del final.
MAGIA_RED = b"HXSRNET1"
# Antes de la 1.4.0 la red iba en dos ficheros al lado de la DLL.
FICHEROS_RED = ("helixsr_weights.bin", "helixsr_kernels.pak")
# Ficheros que deja HelixSR y que no son del juego.
EXTRAS = (MARCA_INSTALL, "helixsr.log", "helixsr.ini") + FICHEROS_RED

# Un juego con anti-cheat de nucleo: cambiarle una DLL puede costar la cuenta.
# HelixSR dice que su Scaler no se use ahi; el drop-in solo cambia el fichero
# de FSR, pero el aviso se da igual y lo decide quien juega.
ANTICHEAT = ("easyanticheat", "battleye", "beclient", "equ8", "faceit",
             "vanguard", "start_protected_game", "anticheatexpert",
             "xigncode", "nprotect", "gameguard")

# Hasta donde se baja al recorrer la carpeta del juego. Diez niveles es lo que
# usa la herramienta de SteamOS y cubre los Engine/Binaries/Win64 mas hondos.
HONDO = 10

# Lineas de helixsr.log que valen para el informe.
LOG_CLAVES = ("network running", "helixsr error", "not running", "summary:",
              "wave size:", "upscaler list:", "create: max render",
              "forwarding", "output: network", "network files:")

# Las fases del instalador, para poder decir por donde va. Construir la red
# lleva minutos y su registro no dice "sigo vivo": lo que hay son estas
# cabeceras y una barra de progreso propia desde la 1.7.
FASES = (
    (r"\[helixsr-setup\] system:", 1, "comprobando el sistema"),
    (r"portable Python|python\.tar\.gz", 2, "bajando Python y numpy"),
    (r"\[helixsr-setup\] python:", 5, "preparando el compilador de shaders"),
    (r"dxc-win\.zip", 5, "bajando el compilador de shaders"),
    (r"shader compiler:", 7, "empezando la construccion"),
    (r"downloading nvngx_dlss", 8, "bajando la DLL de DLSS de NVIDIA"),
    (r"1/5 weights", 10, "1/5 extrayendo los pesos"),
    (r"2/5 PTX", 14, "2/5 extrayendo los nucleos de la red"),
    (r"3/5 fragment tables", 18, "3/5 tablas de fragmentos"),
    (r"4/5 kernel sources", 40, "4/5 generando el codigo de los shaders"),
    (r"5/5 shaders", 50, "5/5 compilando shaders"),
    (r"building the network", 10, "construyendo la red"),
    (r"HelixSR is ready|now carries the network|done: the network is built",
     100, "terminado"),
    (r"looking for games with DLSS", 100, "red construida"),
)
BARRA = re.compile(r"\[[#-]{5,}\]\s+(\d+)%\s+\d+:\d\d\s+(.*?)\s*$")


# --- la release ------------------------------------------------------------

def elegir_asset(entrada):
    """El paquete de HelixSR de una release. Devuelve (url, sha256).

    Acepta las dos cosas que puede dar bash: el JSON entero de la API de
    GitHub (que trae el "digest" con el sha256) o una lista de URLs ya
    extraidas, que es lo que imprimen gh_latest_asset y gh_tag_assets.

    SE ELIGE CON CUIDADO porque una release de HelixSR trae NUEVE ficheros: el
    zip propio, el de HelixSR Scaler, los instaladores de HelixSR Desktop
    (.exe, .AppImage, .deb)... El que queremos es "HelixSR-<version>.zip" y
    solo ese: coger "el primer zip" da el de Scaler la mitad de las veces.
    """
    texto = entrada if isinstance(entrada, str) else "\n".join(entrada)
    pares = []
    if '"browser_download_url"' in texto:
        try:
            datos = json.loads(texto)
        except ValueError:
            datos = None
        if datos is not None:
            if isinstance(datos, dict):
                datos = [datos]
            for rel in datos if isinstance(datos, list) else []:
                if not isinstance(rel, dict):
                    continue
                for a in rel.get("assets") or []:
                    if not isinstance(a, dict):
                        continue
                    url = a.get("browser_download_url") or ""
                    dig = str(a.get("digest") or "")
                    sha = ""
                    if re.fullmatch(r"sha256:[0-9a-fA-F]{64}", dig):
                        sha = dig.split(":", 1)[1].lower()
                    if url:
                        pares.append((url, sha))
    if not pares:
        # Sin JSON: URLs a pelo, una por linea.
        for linea in texto.split("\n"):
            u = linea.strip()
            if u.startswith("http"):
                pares.append((u, ""))
    for url, sha in pares:
        nombre = os.path.basename(url).lower()
        if re.fullmatch(r"helixsr-\d[\w.\-]*\.zip", nombre):
            return url, sha
    return "", ""


# --- reconocer la DLL ------------------------------------------------------

def es_helixsr(ruta):
    """¿Esta DLL es HelixSR? Devuelve la version, o "" si no lo es.

    Desde la 1.3 la DLL se nombra "HelixSR 1.9.3" dentro; la 1.2.0 solo decia
    "HelixSR (3.1.5)", que era la version de la interfaz de FSR. Se miran los
    primeros 4 MiB, que es donde cae la cadena.
    """
    try:
        with open(ruta, "rb") as f:
            cabeza = f.read(4 << 20)
    except (OSError, IOError):
        return ""
    m = re.search(rb"HelixSR (\d+\.\d+\.\d+|\(3\.1\.\d+\))", cabeza)
    if not m:
        return ""
    v = m.group(1).decode("ascii", "replace")
    return v.strip("()")


def tiene_red(ruta):
    """¿La DLL lleva ya la red dentro (o al lado)?

    IMPORTA MUCHO: una DLL de HelixSR SIN red arranca igual y lo que se ve en
    el juego es un borde rojo y la imagen temblando. O sea que "instalado" no
    es lo mismo que "listo", y el menu tiene que distinguirlo.
    """
    try:
        tam = os.path.getsize(ruta)
        if tam > 32:
            with open(ruta, "rb") as f:
                f.seek(-32, os.SEEK_END)
                if f.read(8) == MAGIA_RED:
                    return True
    except (OSError, IOError):
        return False
    base = os.path.dirname(os.path.abspath(ruta))
    return all(os.path.exists(os.path.join(base, n)) for n in FICHEROS_RED)


def dll_de_release(base):
    """La DLL de HelixSR dentro de la carpeta donde se descomprimio la release.

    Se mira la raiz y la subcarpeta fsr3-drop-in, que es donde el instalador
    deja la DLL con la red dentro bajo LOS DOS nombres de FSR 3.1.
    """
    if not base or not os.path.isdir(base):
        return ""
    candidatas = []
    for sub in ("fsr3-drop-in", ""):
        d = os.path.join(base, sub) if sub else base
        for n in NOMBRES_FSR:
            candidatas.append(os.path.join(d, n))
    # Primero una con la red; si no hay, cualquiera de HelixSR (para poder
    # decir "descargado, falta construir la red" en vez de "no instalado").
    sin_red = ""
    for c in candidatas:
        if os.path.isfile(c) and es_helixsr(c):
            if tiene_red(c):
                return c
            if not sin_red:
                sin_red = c
    return sin_red


def original_de(ruta):
    """El respaldo que se deja al instalar: juego.dll -> juego.original.dll."""
    raiz = ruta[:-4] if ruta.lower().endswith(".dll") else ruta
    return raiz + SUFIJO_ORIG


# --- ¿el juego es de Direct3D 12? ------------------------------------------
#
# HelixSR solo existe en D3D12. Saberlo ANTES de instalar nada evita el caso
# tipico: se instala, no cambia nada y nadie sabe por que. La tabla de
# importaciones del .exe lo dice sin ejecutarlo.

NO_ES_JUEGO = re.compile(
    r"unins|crash|launcher|setup|redist|dxsetup|easyanticheat|eac_|battleye|"
    r"report|helper|unitycrashhandler|vcredist|dotnet", re.I)


def pe_importa(ruta):
    """Los nombres (en minusculas) de las DLL que importa un .exe de Windows.

    Se leen LAS DOS tablas: la normal y la de carga retardada (delay-load),
    porque muchisimos juegos piden d3d12.dll por ahi y mirando solo la primera
    parecen de DirectX 11.
    """
    try:
        with open(ruta, "rb") as f:
            mz = f.read(64)
            if len(mz) < 64 or mz[:2] != b"MZ":
                return None
            f.seek(struct.unpack_from("<I", mz, 0x3C)[0])
            hdr = f.read(24)
            if hdr[:4] != b"PE\0\0":
                return None
            nsec = struct.unpack_from("<H", hdr, 6)[0]
            optsize = struct.unpack_from("<H", hdr, 20)[0]
            opt = f.read(optsize)
            pe32mas = struct.unpack_from("<H", opt, 0)[0] == 0x20B
            dirs = 112 if pe32mas else 96
            if pe32mas:
                base_img = struct.unpack_from("<Q", opt, 24)[0]
            else:
                base_img = struct.unpack_from("<I", opt, 28)[0]
            imp_rva = struct.unpack_from("<I", opt, dirs + 8)[0]
            if len(opt) >= dirs + 14 * 8:
                tardia_rva = struct.unpack_from("<I", opt, dirs + 13 * 8)[0]
            else:
                tardia_rva = 0
            secs = []
            for _ in range(nsec):
                s = f.read(40)
                if len(s) < 40:
                    break
                vsize, va, rawsize, rawptr = struct.unpack_from("<IIII", s, 8)
                secs.append((va, max(vsize, rawsize), rawptr))

            def desplaz(rva):
                for va, tam, raw in secs:
                    if va <= rva < va + tam:
                        return raw + rva - va
                return None

            nombres = set()

            def tabla(rva, tam, donde, tardia):
                ini = desplaz(rva) if rva else None
                if ini is None:
                    return
                for i in range(2000):
                    f.seek(ini + i * tam)
                    d = f.read(tam)
                    if len(d) < tam or d == b"\0" * tam:
                        break
                    valor = struct.unpack_from("<I", d, donde)[0]
                    # EL VALOR PUEDE SER UN RVA O UNA DIRECCION.
                    #
                    # Los descriptores de carga retardada antiguos guardan
                    # DIRECCIONES (ImageBase + rva) y los nuevos RVAs, y lo
                    # dice el bit 0 de los atributos. Pero ese bit se ve mal
                    # en la practica -y en un binario de 64 bits la direccion
                    # ni cabe en los 32 bits del campo-, asi que en vez de
                    # fiarse del bit se PRUEBAN las dos lecturas y se queda la
                    # que cae dentro de una seccion de verdad. Equivocarse
                    # aqui hace que d3d12.dll no salga y que un juego de
                    # Direct3D 12 pase por uno de 11.
                    posibles = [valor]
                    if tardia:
                        posibles.append(valor - base_img)
                        posibles.append(valor - (base_img & 0xFFFFFFFF))
                    at = None
                    for v in posibles:
                        if v > 0:
                            at = desplaz(v)
                            if at is not None:
                                break
                    if at is None:
                        continue
                    f.seek(at)
                    cru = f.read(80).split(b"\0")[0]
                    if cru:
                        nombres.add(cru.decode("ascii", "replace").lower())

            tabla(imp_rva, 20, 12, False)      # IMAGE_IMPORT_DESCRIPTOR
            tabla(tardia_rva, 32, 4, True)     # IMAGE_DELAYLOAD_DESCRIPTOR
            return nombres
    except (OSError, IOError, struct.error, IndexError):
        return None


def nombra(ruta, palabra):
    """¿El fichero menciona esta palabra (ASCII o UTF-16, sin mirar mayusculas)?

    Un juego puede cargar d3d12.dll a mano en tiempo de ejecucion: entonces no
    sale en ninguna tabla de importaciones, pero el nombre esta dentro.
    """
    agujas = [palabra.lower().encode(), palabra.lower().encode("utf-16-le")]
    guarda = max(len(a) for a in agujas) - 1
    try:
        with open(ruta, "rb") as f:
            cola = b""
            while True:
                trozo = f.read(4 * 1024 * 1024)
                if not trozo:
                    return False
                datos = (cola + trozo).lower()
                for a in agujas:
                    if a in datos:
                        return True
                cola = datos[-guarda:]
    except (OSError, IOError):
        return False


def exe_dx(ruta):
    """"dx12", "dx11" o "" para un .exe de Windows."""
    imps = pe_importa(ruta)
    if imps is None:
        return ""
    if "d3d12.dll" in imps:
        return "dx12"
    if "d3d11.dll" in imps or "dxgi.dll" in imps:
        return "dx12" if nombra(ruta, "d3d12") else "dx11"
    return ""


# --- la carpeta del juego --------------------------------------------------

def _andar(raiz, hondo=HONDO):
    raiz = os.path.abspath(raiz)
    corte = raiz.rstrip(os.sep).count(os.sep) + hondo
    for actual, dirs, ficheros in os.walk(raiz):
        dirs.sort()
        if actual.rstrip(os.sep).count(os.sep) >= corte:
            dirs[:] = []
        yield actual, ficheros


def juego(raiz):
    """Que hay en la carpeta de un juego, de cara a HelixSR.

    Devuelve un dict con:
      fsr       lista de (ruta, estado) donde estado es:
                  libre       la DLL del juego, sin tocar
                  helixsr     HelixSR instalado (y su respaldo esta)
                  sin_red     HelixSR instalado pero sin la red: borde rojo
                  actualizado la DLL es del juego pero hay respaldo: el juego
                              se actualizo encima de HelixSR
                  rota        HelixSR instalado SIN respaldo, o respaldo sin DLL
      dx        "dx12", "dx11" o "" (lo que diga el .exe mas gordo)
      anticheat lista de nombres encontrados
      extras    ficheros de HelixSR que hay por ahi (helixsr.log, ini, marca)
    """
    r = {"fsr": [], "dx": "", "anticheat": [], "extras": []}
    if not raiz or not os.path.isdir(raiz):
        return r
    exes = []
    bajos_fsr = set(n.lower() for n in NOMBRES_FSR)
    bajos_extra = set(n.lower() for n in EXTRAS)
    for actual, ficheros in _andar(raiz):
        bajo_dir = os.path.basename(actual).lower()
        for a in ANTICHEAT:
            if a in bajo_dir and a not in r["anticheat"]:
                r["anticheat"].append(a)
        for f in ficheros:
            bajo = f.lower()
            ruta = os.path.join(actual, f)
            for a in ANTICHEAT:
                if a in bajo and a not in r["anticheat"]:
                    r["anticheat"].append(a)
            if bajo in bajos_extra:
                r["extras"].append(ruta)
                continue
            if bajo in bajos_fsr:
                r["fsr"].append((ruta, _estado_fsr(ruta)))
                continue
            if bajo.endswith(SUFIJO_ORIG) and bajo[:-len(SUFIJO_ORIG)] + ".dll" in bajos_fsr:
                # El respaldo. Si su DLL no esta, eso es una instalacion rota.
                hermana = ruta[:-len(SUFIJO_ORIG)] + ".dll"
                if not os.path.exists(hermana):
                    r["fsr"].append((hermana, "rota"))
                continue
            if bajo.endswith(".exe") and not NO_ES_JUEGO.search(f):
                try:
                    exes.append((os.path.getsize(ruta), ruta))
                except OSError:
                    pass
    r["fsr"].sort()
    r["extras"].sort()
    # EL .EXE MAS GRANDE es el juego, con mucho. Se miran hasta tres por si el
    # mas gordo es un paquete de datos con extension .exe.
    exes.sort(reverse=True)
    for _t, ruta in exes[:3]:
        dx = exe_dx(ruta)
        if dx == "dx12":
            r["dx"] = "dx12"
            break
        if dx and not r["dx"]:
            r["dx"] = dx
    return r


def _estado_fsr(ruta):
    v = es_helixsr(ruta)
    orig = original_de(ruta)
    if v:
        if not os.path.exists(orig):
            return "rota"
        return "helixsr" if tiene_red(ruta) else "sin_red"
    # NO ES HELIXSR PERO HAY RESPALDO: el juego se actualizo y puso su propia
    # DLL de FSR otra vez en su sitio. Es un estado aparte de "libre" y hay que
    # distinguirlo: si se trata como libre, al instalar se moveria la DLL NUEVA
    # del juego encima del respaldo viejo... o peor, un "mv" que no sobreescribe
    # dejaria el respaldo antiguo y la nueva machacada por HelixSR, o sea el
    # fichero del juego perdido. Lo correcto es que el respaldo pase a ser el
    # fichero NUEVO, que es lo que hace tambien el instalador oficial.
    if os.path.exists(orig):
        return "actualizado"
    return "libre"


# --- informes --------------------------------------------------------------

def informe(log):
    """Que dijo helixsr.log. Devuelve (estado, lineas).

    estado: "ok" (la red corrio), "no" (no corrio: borde rojo), "error",
            "sin_rastro" (no hay fichero, o esta vacio).
    """
    try:
        with open(log, "r", errors="replace") as f:
            crudo = f.read()
    except (OSError, IOError):
        return "sin_rastro", []
    lineas = [l.strip() for l in crudo.split("\n") if l.strip()]
    if not lineas:
        return "sin_rastro", []
    sueltas, visto = [], set()
    for l in lineas:
        bajo = l.lower()
        for c in LOG_CLAVES:
            if c in bajo and l not in visto:
                visto.add(l)
                sueltas.append(l)
                break
    texto = crudo.lower()
    if "helixsr error" in texto:
        est = "error"
    elif "not running" in texto:
        est = "no"
    elif "network running" in texto:
        est = "ok"
    else:
        est = "sin_rastro" if not sueltas else "no"
    return est, sueltas[:40]


def progreso(log):
    """Por donde va el instalador. Devuelve (porcentaje, etiqueta)."""
    try:
        with open(log, "r", errors="replace") as f:
            lineas = f.read().split("\n")
    except (OSError, IOError):
        return 0, "empezando"
    pct, etiq = 0, "empezando"
    for l in lineas:
        for pat, p, e in FASES:
            if p >= pct and re.search(pat, l):
                pct, etiq = p, e
        m = BARRA.search(l)
        if m and pct < 100:
            barra = int(m.group(1))
            pct = 10 + int(barra * 0.89)
            etiq = "construyendo la red: %s (%d%%)" % (m.group(2), barra)
    return pct, etiq


# --- helixsr.ini -----------------------------------------------------------

def ini_poner(texto, seccion, clave, valor):
    """Cambia una clave del helixsr.ini SIN reescribir el resto del fichero.

    Se respetan el orden, los comentarios y los espacios: el fichero lo puede
    haber editado quien juega, y volvera a mirarlo.
    """
    lineas = texto.split("\n")
    dentro = False
    fin_seccion = -1
    for i, l in enumerate(lineas):
        s = l.strip()
        if s.startswith("[") and s.endswith("]"):
            if dentro:
                break
            dentro = s[1:-1].strip().lower() == seccion.lower()
            if dentro:
                fin_seccion = i
            continue
        if not dentro:
            continue
        m = re.match(r"(\s*)(%s)(\s*)=(\s*)(.*)$" % re.escape(clave), l, re.I)
        if m:
            lineas[i] = "%s%s%s=%s%s" % (m.group(1), m.group(2), m.group(3),
                                         m.group(4) or " ", valor)
            return "\n".join(lineas)
        if s:
            fin_seccion = i
    if fin_seccion >= 0:
        lineas.insert(fin_seccion + 1, "%s = %s" % (clave, valor))
        return "\n".join(lineas)
    cola = "" if texto.endswith("\n") or not texto else "\n"
    return "%s%s[%s]\n%s = %s\n" % (texto, cola, seccion, clave, valor)


# --- auto-diagnostico ------------------------------------------------------

def comprobar():
    """Se prueba a si mismo con ficheros inventados. Sin red y sin GPU."""
    import shutil
    import tempfile
    fallos = []

    def dice(cond, que):
        if not cond:
            fallos.append(que)

    tmp = tempfile.mkdtemp(prefix="helixsr-comp-")
    try:
        # 1. elegir el paquete entre los NUEVE de una release
        urls = [
            "https://x/HelixSR-Scaler-1.0.6.zip",
            "https://x/HelixSR-Desktop-1.0.3.AppImage",
            "https://x/HelixSR-1.9.3.zip",
            "https://x/helixsr-desktop_1.0.3_amd64.deb",
        ]
        u, sha = elegir_asset(urls)
        dice(u.endswith("HelixSR-1.9.3.zip"), "elegir_asset coge el zip propio")
        dice(sha == "", "elegir_asset sin JSON no inventa sha256")
        js = json.dumps([{"tag_name": "v1.9.3", "assets": [
            {"browser_download_url": "https://x/HelixSR-Scaler-1.0.6.zip",
             "digest": "sha256:" + "a" * 64},
            {"browser_download_url": "https://x/HelixSR-1.9.3.zip",
             "digest": "sha256:" + "b" * 64}]}])
        u, sha = elegir_asset(js)
        dice(u.endswith("HelixSR-1.9.3.zip"), "elegir_asset con JSON")
        dice(sha == "b" * 64, "elegir_asset saca el sha256 del digest")
        dice(elegir_asset(["https://x/otracosa.zip"]) == ("", ""),
             "elegir_asset no coge un zip cualquiera")

        # 2. reconocer la DLL y la red
        dll = os.path.join(tmp, "amd_fidelityfx_dx12.dll")
        with open(dll, "wb") as f:
            f.write(b"MZ" + b"\0" * 100 + b"\x00HelixSR 1.9.3\x00" + b"\0" * 100)
        dice(es_helixsr(dll) == "1.9.3", "es_helixsr lee la version")
        dice(not tiene_red(dll), "una DLL sin red no cuela por lista")
        with open(dll, "ab") as f:
            f.write(MAGIA_RED + b"\0" * 24)
        dice(tiene_red(dll), "tiene_red ve la marca del final")
        vieja = os.path.join(tmp, "vieja.dll")
        with open(vieja, "wb") as f:
            f.write(b"HelixSR (3.1.5)")
        dice(es_helixsr(vieja) == "3.1.5", "es_helixsr con la 1.2.0")
        juego_dll = os.path.join(tmp, "limpia.dll")
        with open(juego_dll, "wb") as f:
            f.write(b"MZ cosas de AMD")
        dice(es_helixsr(juego_dll) == "", "una DLL del juego no es HelixSR")
        dice(original_de("/a/b/amd_fidelityfx_dx12.dll")
             == "/a/b/amd_fidelityfx_dx12.original.dll", "original_de")
        # Un fichero que no es un PE no puede dar un veredicto: ni "dx11" ni
        # "dx12". Lo de leer un PE de verdad se prueba en prueba_helix2.py,
        # que se forja uno con su tabla de importaciones.
        dice(exe_dx(juego_dll) == "", "exe_dx con algo que no es un .exe")
        dice(pe_importa(juego_dll) is None, "pe_importa no se inventa nada")

        # 3. la carpeta de la release
        rel = os.path.join(tmp, "rel")
        os.makedirs(os.path.join(rel, "fsr3-drop-in"))
        dice(dll_de_release(rel) == "", "release vacia: no hay DLL")
        suelta = os.path.join(rel, "amd_fidelityfx_dx12.dll")
        shutil.copyfile(vieja, suelta)
        dice(dll_de_release(rel) == suelta, "DLL en la raiz de la release")
        dice(not tiene_red(suelta), "y se ve que le falta la red")
        buena = os.path.join(rel, "fsr3-drop-in",
                             "amd_fidelityfx_upscaler_dx12.dll")
        shutil.copyfile(dll, buena)
        dice(dll_de_release(rel) == buena,
             "se prefiere la que YA tiene la red")

        # 4. la carpeta del juego
        g = os.path.join(tmp, "g", "Engine", "Binaries", "Win64")
        os.makedirs(g)
        destino = os.path.join(g, "amd_fidelityfx_upscaler_dx12.dll")
        shutil.copyfile(juego_dll, destino)
        info = juego(os.path.join(tmp, "g"))
        dice(info["fsr"] == [(destino, "libre")], "juego(): FSR del juego libre")
        dice(info["anticheat"] == [], "juego(): sin anti-cheat")
        # instalado a mano, como lo deja WProton
        os.replace(destino, original_de(destino))
        shutil.copyfile(dll, destino)
        info = juego(os.path.join(tmp, "g"))
        dice(info["fsr"] == [(destino, "helixsr")], "juego(): instalado")
        # sin red -> el caso del borde rojo
        shutil.copyfile(vieja, destino)
        info = juego(os.path.join(tmp, "g"))
        dice(info["fsr"] == [(destino, "sin_red")], "juego(): sin la red")
        # el juego se actualizo: su DLL otra vez en su sitio, y el respaldo ahi
        shutil.copyfile(juego_dll, destino)
        info = juego(os.path.join(tmp, "g"))
        dice(info["fsr"] == [(destino, "actualizado")],
             "juego(): el juego se actualizo encima")
        # respaldo sin DLL -> rota
        os.remove(destino)
        info = juego(os.path.join(tmp, "g"))
        dice(info["fsr"] == [(destino, "rota")], "juego(): instalacion rota")
        # anti-cheat y extras
        os.makedirs(os.path.join(tmp, "g", "EasyAntiCheat"))
        open(os.path.join(g, "helixsr.log"), "w").close()
        info = juego(os.path.join(tmp, "g"))
        dice(info["anticheat"] == ["easyanticheat"], "juego(): anti-cheat")
        dice(any(x.endswith("helixsr.log") for x in info["extras"]),
             "juego(): extras")

        # 5. los informes
        log = os.path.join(tmp, "helixsr.log")
        with open(log, "w") as f:
            f.write("[helixsr] wave size: 32\n[helixsr] network running\n")
        est, lin = informe(log)
        dice(est == "ok", "informe(): la red corrio")
        dice(len(lin) == 2, "informe(): saca las lineas que importan")
        with open(log, "w") as f:
            f.write("[helixsr] HelixSR ERROR: no network files\n")
        dice(informe(log)[0] == "error", "informe(): error")
        with open(log, "w") as f:
            f.write("[helixsr] network NOT RUNNING\n")
        dice(informe(log)[0] == "no", "informe(): no corrio")
        dice(informe(os.path.join(tmp, "nada.log"))[0] == "sin_rastro",
             "informe(): sin fichero")

        slog = os.path.join(tmp, "setup.log")
        with open(slog, "w") as f:
            f.write("[helixsr-setup] system: ok\n"
                    "[helixsr-setup] 4/5 kernel sources\n")
        p, e = progreso(slog)
        dice(p == 40, "progreso(): va por el paso 4")
        with open(slog, "a") as f:
            f.write("[helixsr-setup] [########------------]  42%  1:23 "
                    " shaders 12/72\n")
        p, e = progreso(slog)
        dice(p == 10 + int(42 * 0.89), "progreso(): la barra manda")
        dice("12/72" in e, "progreso(): dice cuantos shaders")
        with open(slog, "a") as f:
            f.write("[helixsr-setup] done: the network is built\n")
        dice(progreso(slog)[0] == 100, "progreso(): terminado")

        # 6. helixsr.ini
        t = "# mio\n[Sharpening]\nSharpener = off\nSharpness = 0.1\n"
        n = ini_poner(t, "Sharpening", "Sharpener", "rcas")
        dice("Sharpener = rcas" in n, "ini_poner cambia el valor")
        dice("# mio" in n and "Sharpness = 0.1" in n,
             "ini_poner no se come el resto")
        n = ini_poner(t, "Compatibility", "WaveSize", "64")
        dice("[Compatibility]" in n and "WaveSize = 64" in n,
             "ini_poner crea la seccion que falta")
        n = ini_poner(t, "Sharpening", "MotionAdaptive", "true")
        dice("MotionAdaptive = true" in n, "ini_poner anade la clave")
        dice(ini_poner("", "Log", "Enabled", "false").startswith("[Log]"),
             "ini_poner con fichero vacio")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    if fallos:
        sys.stderr.write("helixsr.py: %d fallo(s)\n" % len(fallos))
        for f in fallos:
            sys.stderr.write("  - %s\n" % f)
        return 1
    print("helixsr.py: todo correcto")
    return 0


# --- linea de ordenes ------------------------------------------------------

def main(argv):
    orden = argv[1] if len(argv) > 1 else ""

    if orden in ("", "-h", "--help"):
        sys.stderr.write(
            "uso: helixsr.py {comprobar|asset|es|red|dx|juego|informe|"
            "progreso|ini} ...\n")
        return 2

    if orden == "comprobar":
        return comprobar()

    if orden == "asset":
        u, sha = elegir_asset(sys.stdin.read())
        if not u:
            return 1
        print("%s\t%s" % (u, sha))
        return 0

    if len(argv) < 3:
        sys.stderr.write("helixsr.py %s: falta la ruta\n" % orden)
        return 2

    if orden == "es":
        v = es_helixsr(argv[2])
        if not v:
            return 1
        sys.stdout.write(v)
        return 0

    if orden == "red":
        return 0 if tiene_red(argv[2]) else 1

    if orden == "release":
        d = dll_de_release(argv[2])
        if not d:
            return 1
        print("%s\t%s" % (d, "si" if tiene_red(d) else "no"))
        return 0

    if orden == "dx":
        d = exe_dx(argv[2])
        if not d:
            return 1
        sys.stdout.write(d)
        return 0

    if orden == "juego":
        info = juego(argv[2])
        # Una linea por cosa, con tabulador: bash lo lee con read sin comillas.
        for ruta, est in info["fsr"]:
            print("fsr\t%s\t%s" % (ruta, est))
        if info["dx"]:
            print("dx\t%s" % info["dx"])
        for a in info["anticheat"]:
            print("anticheat\t%s" % a)
        for e in info["extras"]:
            print("extra\t%s" % e)
        return 0 if info["fsr"] else 1

    if orden == "informe":
        est, lineas = informe(argv[2])
        print("estado\t%s" % est)
        for l in lineas:
            print("linea\t%s" % l)
        return 0 if est == "ok" else 1

    if orden == "progreso":
        p, e = progreso(argv[2])
        print("%d\t%s" % (p, e))
        return 0

    if orden == "ini":
        if len(argv) < 6:
            sys.stderr.write("helixsr.py ini: fichero seccion clave valor\n")
            return 2
        fich, sec, clave, valor = argv[2], argv[3], argv[4], argv[5]
        try:
            with open(fich, "r", errors="replace") as f:
                texto = f.read()
        except (OSError, IOError):
            texto = ""
        nuevo = ini_poner(texto, sec, clave, valor)
        try:
            with open(fich, "w") as f:
                f.write(nuevo)
        except (OSError, IOError) as e:
            sys.stderr.write("helixsr.py ini: %s\n" % e)
            return 1
        return 0

    sys.stderr.write("helixsr.py: orden desconocida %r\n" % orden)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
