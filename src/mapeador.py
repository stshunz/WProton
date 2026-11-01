# WProton - mapeador de mando a teclado
#
# Copyright (C) 2026  stshunz y colaboradores
#
# Este programa es software libre: puedes redistribuirlo y/o modificarlo bajo
# los terminos de la Licencia Publica General GNU (GPL), version 3 o
# posterior, publicada por la Free Software Foundation.
#
# Se distribuye SIN NINGUNA GARANTIA. Ver <https://www.gnu.org/licenses/>.
# WPROTON_MAPEADOR_V60 (fusionado desde mapeador-60.py de DeckStation)
# Rutas dinamicas: libs_pyX.Y del runtime de WProton + evmapy/ (raiz o runtime)
import sys, os
# Lo mismo que en menu_pygame: que SDL no apague el modo lagarto de la Deck.
#
# El teclado virtual de este mapeador usa pygame, o sea SDL, y SDL manda apagar
# la emulacion de raton y teclado del mando en cuanto lo abre por HIDAPI. Si se
# abre el teclado en pantalla una sola vez, los trackpads se quedan muertos a
# partir de ahi. Este mapeador lee el mando por evdev, asi que no necesita el
# camino HIDAPI para nada.
# HIDAPI ENTERA Y CON "=", no solo la de la Deck y con setdefault: lo primero
# no funciono y en menu_pygame.py esta explicado por que (setdefault respeta lo
# que exporte Steam, y la variable de la Deck no existe en las SDL antiguas).
# Aqui tampoco se pierde nada: el mando se lee por evdev, y pygame solo pinta
# el teclado en pantalla.
os.environ['SDL_JOYSTICK_HIDAPI'] = '0'
os.environ['SDL_JOYSTICK_HIDAPI_STEAMDECK'] = '0'
os.environ['SDL_JOYSTICK_HIDAPI_STEAM'] = '0'
_RT = os.path.dirname(os.path.abspath(__file__))          # runtime/
_BASE_DIR = os.path.dirname(_RT)                          # raiz de WProton
sys.path.insert(0, os.path.join(_RT, 'libs_py%d.%d' % sys.version_info[:2]))
for _d in (os.path.join(_BASE_DIR, 'evmapy'), os.path.join(_RT, 'evmapy'),
           os.path.join(_BASE_DIR, 'libs_py%d.%d' % sys.version_info[:2])):
    if os.path.isdir(_d):
        sys.path.insert(0, _d)
import sys
import os


import evdev
from evdev import ecodes
import json
import select
import time


def nombre_ev(codigo):
    """Nombre legible de una tecla o boton del nucleo. SIEMPRE una cadena.

    POR QUE EXISTE, Y POR QUE TIENE QUE USARLA TODO EL MUNDO

    En evdev, un codigo que tiene DOS nombres no devuelve una cadena: devuelve
    una TUPLA o una lista. El 272 es el caso tipico:

        ecodes.BTN[272] == ('BTN_LEFT', 'BTN_MOUSE')

    Y con eso, un simple ", ".join(...) para escribir el mapa en el registro
    revienta el mapeador entero antes de empezar a jugar:

        TypeError: sequence item 0: expected str instance, tuple found
        [keys] Mando liberado

    Paso de verdad, con el .keys de la comunidad del Torrente, que pone el
    raton en los gatillos. El juego se quedaba sin .keys -ni teclas, ni
    cruceta, ni raton- y el registro no lo decia en ningun sitio donde se
    mirara: la unica pista era un Traceback perdido entre lineas de Proton.

    Lo peor del fallo no era el fallo: era que reventaba ESCRIBIENDO EL
    REGISTRO. Escribir una linea de diagnostico no puede tumbar nunca lo que
    esta diagnosticando, asi que esto no vuelve a hacerse a mano en ningun
    sitio: se llama aqui.
    """
    try:
        n = ecodes.KEY.get(codigo)
        if not n:
            n = getattr(ecodes, 'BTN', {}).get(codigo)
        if isinstance(n, (list, tuple)):
            n = n[0] if n else None
        if isinstance(n, str) and n:
            return n
    except Exception:
        pass
    return str(codigo)


# Mapeos de ejes analógicos por defecto para mandos estándar
ABS_ESTANDAR = {
    ecodes.ABS_Y:     ("joystick1up",   "joystick1down"),
    ecodes.ABS_X:     ("joystick1left",  "joystick1right"),
    ecodes.ABS_RY:    ("joystick2up",   "joystick2down"),
    ecodes.ABS_RX:    ("joystick2left",  "joystick2right"),
    ecodes.ABS_HAT0Y: ("up",            "down"),
    ecodes.ABS_HAT0X: ("left",          "right"),
}

# La Deck (y el Steam Controller) con el driver hid-steam del kernel NO sigue
# el reparto de siempre. Segun drivers/hid/hid-steam.c:
#
#     ABS_X  / ABS_Y      stick izquierdo
#     ABS_RX / ABS_RY     stick derecho
#     ABS_HAT0X / HAT0Y   TOUCHPAD IZQUIERDO   <- aqui NO hay cruceta
#     ABS_HAT1X / HAT1Y   touchpad derecho
#     ABS_HAT2Y / HAT2X   gatillo izquierdo / derecho
#
# Dejar HAT0 como cruceta hacia que rozar el touchpad izquierdo disparara las
# teclas de la cruceta. La cruceta de verdad llega como BOTONES (544-547), que
# ya se registran aparte.
ABS_STEAMDECK = {
    ecodes.ABS_Y:  ("joystick1up",   "joystick1down"),
    ecodes.ABS_X:  ("joystick1left", "joystick1right"),
    ecodes.ABS_RY: ("joystick2up",   "joystick2down"),
    ecodes.ABS_RX: ("joystick2left", "joystick2right"),
}

PERFILES = {
    # Va el primero: con el driver hid-steam la Deck se llama "Steam Deck" y
    # antes no casaba con ningun perfil, asi que caia en GENERIC y con el
    # reparto de ejes equivocado. (En modo Juego, cuando es Steam quien crea
    # el mando virtual, se llama "Microsoft X-Box 360 pad N" y sigue usando
    # XBOX_360, que es lo correcto: ese SI es un mando estandar.)
    "STEAM_DECK": {
        "match": ["steam deck", "valve software steam"],
        "ids": {
            "a": 304, "b": 305, "x": 307, "y": 308,
            "start": 315, "select": 314, "hotkey": 314,
            "pageup": 310, "pagedown": 311,
            "l2": 312, "r2": 313, "l3": 317, "r3": 318
        },
        "abs_map": ABS_STEAMDECK, "threshold": 16000, "center": 0
    },
    "XBOX_360": {
        "match": ["microsoft", "xbox 360", "360", "x-box 360"],
        "ids": {
            "a": 304, "b": 305, "x": 307, "y": 308,
            "start": 315, "select": 314, "hotkey": 314,
            "pageup": 310, "pagedown": 311,
            "l2": 312, "r2": 313, "l3": 317, "r3": 318
        },
        "abs_map": ABS_ESTANDAR, "threshold": 16000, "center": 0
    },
    "XBOX_ONE": {
        "match": ["xbox one", "xbox wireless", "xbox gaming", "input joystick", "x-box one"],
        "ids": {
            "a": 304, "b": 305, "x": 307, "y": 308,
            "start": 315, "select": 314, "hotkey": 314,
            "pageup": 310, "pagedown": 311,
            "l2": 312, "r2": 313, "l3": 317, "r3": 318
        },
        "abs_map": ABS_ESTANDAR, "threshold": 16000, "center": 0
    },
    "8BITDO_ULTIMATE": {
        "match": ["últimate", "últimate 2c", "2c"],
        "ids": {
            "a": 304, "b": 305, "x": 307, "y": 308,
            "start": 315, "select": 314, "hotkey": 314,
            "pageup": 310, "pagedown": 311,
            "l2": 312, "r2": 313, "l3": 317, "r3": 318
        },
        "abs_map": ABS_ESTANDAR, "threshold": 40, "center": 127
    },
    # LOS DOS DE SONY: CODIGOS DEL KERNEL, NO LOS QUE TENIAMOS.
    #
    # EL CASO (28/10): un tester con CachyOS y un DualShock 4 (054c:09cc). Un
    # juego con .keys le fallaba lanzando WProton desde el escritorio, y
    # funcionaba perfecto añadiendo WProton a Steam. Mismo equipo, mismo
    # mando, mismo .keys.
    #
    # Los dos registros lo dijeron en una linea. Desde el escritorio:
    #
    #     [keys] Mando: "Sony ... Wireless Controller" -> perfil SONY_DS4
    #     [keys] mapa: select (codigo 312) -> KEY_C
    #     [keys] mapa: start  (codigo 313) -> KEY_LEFT
    #     [keys] Combinacion: 312 + 313        <- SIN NOMBRES
    #
    # Y desde Steam -donde Steam ofrece su mando virtual, que se hace pasar
    # por un Xbox 360 y por tanto cae en el perfil XBOX_360-:
    #
    #     [keys] mapa: select (codigo 314) -> KEY_C
    #     [keys] mapa: start  (codigo 315) -> KEY_LEFT
    #     [keys] Combinacion: Select + Start   <- CON NOMBRES
    #
    # En Linux, un DualShock 4 manda el Share como BTN_SELECT (314) y el
    # Options como BTN_START (315): lo dice el mantenedor de hid-playstation
    # en la lista del kernel ("the DS4 Share button was mapped to 'Select'
    # under the Linux gamepad spec"; "the Options button replaced Start").
    # Nuestros 312 y 313 son BTN_TL2 y BTN_TR2, o sea L2 y R2.
    #
    # O sea que con un mando de Sony: el Share y el Options no hacian NADA, y
    # L2 y R2 mandaban las teclas que les tocaban a ellos. La pista estaba
    # delante: la combinacion se imprimia como "312 + 313" en vez de
    # "Select + Start" porque nuestra propia tabla de nombres -la del kernel-
    # no llama "select" al 312. Dos tablas nuestras diciendo cosas distintas.
    #
    # Y lo mismo el DualSense y el mando de Switch: los tres tenian el mismo
    # error copiado.
    #
    # Hoy esto es ademas una RED, no la via principal: los codigos se le
    # preguntan al mando (ver ids_del_mando). La tabla es el respaldo para un
    # mando que no declare los estandar.
    "SONY_DS4": {
        "match": ["sony", "playstation", "wireless controller", "dualshock 4", "ps4"],
        "ids": {
            "a": 304, "b": 305, "x": 307, "y": 308,
            "start": 315, "select": 314, "hotkey": 314,
            "pageup": 310, "pagedown": 311,
            "l2": 312, "r2": 313, "l3": 317, "r3": 318
        },
        "abs_map": ABS_ESTANDAR, "threshold": 16000, "center": 0
    },
    "SONY_PS5": {
        "match": ["dualsense", "ps5"],
        "ids": {
            "a": 304, "b": 305, "x": 307, "y": 308,
            "start": 315, "select": 314, "hotkey": 314,
            "pageup": 310, "pagedown": 311,
            "l2": 312, "r2": 313, "l3": 317, "r3": 318
        },
        "abs_map": ABS_ESTANDAR, "threshold": 16000, "center": 0
    },
    "8BITDO": {
        "match": ["8bitdo", "8bitdo pro 2", "8bitdo sn30"],
        "ids": {
            "a": 304, "b": 305, "x": 307, "y": 308,
            "start": 315, "select": 314, "hotkey": 314,
            "pageup": 310, "pagedown": 311,
            "l2": 312, "r2": 313, "l3": 317, "r3": 318
        },
        "abs_map": ABS_ESTANDAR, "threshold": 16000, "center": 0
    },
    "NINTENDO_SWITCH": {
        # El cruce de A/B y X/Y es a proposito: es la disposicion de Nintendo.
        # Lo que estaba mal aqui eran select/start, igual que en los de Sony:
        # hid-nintendo manda el "-" como BTN_SELECT (314) y el "+" como
        # BTN_START (315).
        "match": ["nintendo", "switch", "pro controller", "joy-con"],
        "ids": {
            "a": 305, "b": 304, "x": 309, "y": 308,
            "start": 315, "select": 314, "hotkey": 314,
            "pageup": 310, "pagedown": 311,
            "l2": 312, "r2": 313, "l3": 317, "r3": 318
        },
        "abs_map": ABS_ESTANDAR, "threshold": 16000, "center": 0
    },
    "GENERIC": {
        "match": [],
        "ids": {
            "a": 304, "b": 305, "x": 307, "y": 308,
            "start": 315, "select": 314, "hotkey": 314,
            "pageup": 310, "pagedown": 311,
            "l2": 312, "r2": 313, "l3": 317, "r3": 318
        },
        "abs_map": ABS_ESTANDAR, "threshold": 16000, "center": 0
    }
}

# ===========================================================================
# EL PUNTERO EN EL MODO JUEGO: XTEST
# ===========================================================================
#
# EL CASO, TAL CUAL LLEGO
#
# Un juego con lanzador: hay que pulsar "Play" con el raton. En el escritorio
# va bien. En el modo Juego de la Deck, no. Dani encendio "el mando como
# raton" y siguio igual, y conto el detalle que lo resolvio todo: "el puntero
# del raton aparece como una X".
#
# LO QUE DECIA EL REGISTRO
#
# En el modo Juego hay DOS servidores X, no uno. Lo pone WProton mismo:
#
#     -- display :0 <-- ESTE es el de gamescope
#          GAMESCOPE_FOCUSED_APP(CARDINAL) = 3975565157
#          ... Big Picture, steamwebhelper, mangoapp ...
#     -- display :1 (no es el de gamescope)
#          0x600065  "The Last Guardian - PC"       <-- EL LANZADOR
#
# Es como monta gamescope el modo Juego: un XWayland para Steam y OTRO para
# el juego. Y el puntero de los dos estaba clavado en el mismo sitio:
#
#     ahora esta en :1=(1279, 799), :0=(1279, 799)
#
# 1279x799 es la esquina de abajo a la derecha de una pantalla de 1280x800.
# El puntero no es que fuera mal: es que NUNCA SE HABIA MOVIDO de donde nacio.
# Y encima explica la X: el puntero en forma de X es el cursor por defecto de
# la VENTANA RAIZ de un servidor X. Se ve una X porque el puntero nunca ha
# llegado a entrar en ninguna ventana. En la foto sale pegado al boton "Play"
# por pura casualidad: "Play" esta tambien abajo a la derecha.
#
# POR QUE EL RATON VIRTUAL NO SERVIA
#
# El raton del mapeador es un aparato uinput: escribe en EL KERNEL. De ahi lo
# recoge gamescope -el de fuera, el que lleva los mandos y la pantalla- y lo
# reparte. A ese reparto el XWayland del juego no llega. El raton existia, se
# movia, y movia un puntero que el lanzador no tenia delante.
#
# LO QUE SI FUNCIONA: ESCRIBIR DENTRO DEL SERVIDOR X
#
# XTEST es una extension del propio servidor X para inyectar eventos. No pasa
# por el kernel ni por el compositor: entra por dentro, en la pantalla que se
# le diga, y de ahi sale por el reparto normal de X hasta la ventana que haya
# bajo el puntero. Es lo que hace xdotool, y por eso xdotool funciona dentro
# de un XWayland donde un raton de kernel no llega.
#
# Dos detalles que importan:
#
#   - NO es XSendEvent. XSendEvent marca el evento como sintetico y media
#     interfaz grafica lo descarta por eso. XTEST no: para el lanzador es un
#     clic igual que el de un raton de verdad.
#   - Hay que elegir PANTALLA, y la buena es la del juego. Mover el puntero
#     en la de gamescope seria repartir clics por la interfaz de Steam que hay
#     detras del juego. Por eso se descarta la que tiene GAMESCOPE_FOCUSED_APP
#     en su ventana raiz, que es justo como las distingue WProton en el
#     registro de arriba.
#
# EN EL ESCRITORIO NO SE TOCA NADA. Si no hay ninguna pantalla de gamescope,
# se sigue usando el raton uinput de siempre, que lleva funcionando desde la
# 2.01 y que ademas es el bueno para mover la camara en un juego (movimiento
# relativo, que es lo que espera Wine cuando captura el puntero). Se puede
# forzar una cosa u otra con WP_RATON_XTEST=si|no|auto.

import ctypes
import ctypes.util

# Boton de raton de evdev -> numero de boton de X. En X el 1 es el izquierdo,
# el 2 el central y el 3 el derecho (el 4 y el 5 son la rueda).
_X_BOTON = {}
for _nom, _nx in (("BTN_LEFT", 1), ("BTN_MIDDLE", 2), ("BTN_RIGHT", 3)):
    _c = getattr(ecodes, _nom, None)
    if _c is not None:
        _X_BOTON[_c] = _nx


def _raton_fraccion(valor, info, centro_por_defecto):
    """De cuanto esta movido el stick a cuanto corre el puntero: -1.0 a 1.0.

    info = (reposo, recorrido, zona muerta), aprendido del propio mando.

    SE ESCALA DESDE EL BORDE DE LA ZONA MUERTA, no desde el centro. Si no, al
    salir de la zona muerta el puntero pegaria un salto del tamaño de la zona
    -con una zona del 12%, un 12% de la velocidad de golpe- y apuntar a un
    boton seria imposible. Asi sale de cero y sube suave.
    """
    if not info:
        # Todavia no ha llegado ningun evento de ese eje: quieto.
        return 0.0
    centro, recorrido, zona = info
    if not recorrido:
        return 0.0
    v = valor - centro
    if abs(v) <= zona:
        return 0.0
    util = recorrido - zona
    if util <= 0:
        return 0.0
    f = (abs(v) - zona) / float(util)
    if f > 1.0:
        f = 1.0
    return f if v > 0 else -f


def _cargar_lib(*nombres):
    """La primera de estas bibliotecas que se deje cargar."""
    for n in nombres:
        if not n:
            continue
        try:
            return ctypes.CDLL(n)
        except OSError:
            continue
    return None


def _pantallas_candidatas():
    """Las pantallas X donde mirar, la del entorno primero."""
    v = []
    d = (os.environ.get("DISPLAY") or "").strip()
    if d:
        v.append(d)
    for n in (":0", ":1", ":2"):
        if n not in v:
            v.append(n)
    return v


def _tiene_atomo_gamescope(x11, dpy):
    """¿La ventana raiz de esta pantalla lleva GAMESCOPE_FOCUSED_APP?

    Es la misma pregunta que hace WProton al escribir el registro, y la que
    separa la pantalla de Steam de la del juego.
    """
    try:
        x11.XInternAtom.restype = ctypes.c_ulong
        x11.XInternAtom.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_int]
        atomo = x11.XInternAtom(dpy, b"GAMESCOPE_FOCUSED_APP", 1)
        if not atomo:
            return False
        x11.XDefaultRootWindow.restype = ctypes.c_ulong
        x11.XDefaultRootWindow.argtypes = [ctypes.c_void_p]
        raiz = x11.XDefaultRootWindow(dpy)
        x11.XGetWindowProperty.argtypes = [
            ctypes.c_void_p, ctypes.c_ulong, ctypes.c_ulong,
            ctypes.c_long, ctypes.c_long, ctypes.c_int, ctypes.c_ulong,
            ctypes.POINTER(ctypes.c_ulong), ctypes.POINTER(ctypes.c_int),
            ctypes.POINTER(ctypes.c_ulong), ctypes.POINTER(ctypes.c_ulong),
            ctypes.POINTER(ctypes.POINTER(ctypes.c_ubyte))]
        tipo = ctypes.c_ulong(); fmt = ctypes.c_int()
        n = ctypes.c_ulong(); resto = ctypes.c_ulong()
        datos = ctypes.POINTER(ctypes.c_ubyte)()
        rc = x11.XGetWindowProperty(dpy, raiz, atomo, 0, 1, 0, 0,
                                    ctypes.byref(tipo), ctypes.byref(fmt),
                                    ctypes.byref(n), ctypes.byref(resto),
                                    ctypes.byref(datos))
        hay = (rc == 0 and n.value > 0)
        if datos:
            x11.XFree(datos)
        return hay
    except Exception:
        return False


class RatonXTest:
    """Un raton que escribe DENTRO del servidor X con XTEST.

    Imita a propósito a evdev.UInput -write(), syn(), close()- para que el
    mapeador no tenga que saber cual de los dos le ha tocado: en todos los
    sitios donde se mandaba un clic o un movimiento, el codigo es el mismo.
    """

    def __init__(self, display):
        self.x11 = _cargar_lib("libX11.so.6", "libX11.so",
                               ctypes.util.find_library("X11"))
        self.xtst = _cargar_lib("libXtst.so.6", "libXtst.so",
                                ctypes.util.find_library("Xtst"))
        if not self.x11 or not self.xtst:
            raise OSError("faltan libX11 o libXtst")
        x11, xtst = self.x11, self.xtst
        x11.XOpenDisplay.restype = ctypes.c_void_p
        x11.XOpenDisplay.argtypes = [ctypes.c_char_p]
        x11.XDefaultScreen.restype = ctypes.c_int
        x11.XDefaultScreen.argtypes = [ctypes.c_void_p]
        x11.XDisplayWidth.restype = ctypes.c_int
        x11.XDisplayWidth.argtypes = [ctypes.c_void_p, ctypes.c_int]
        x11.XDisplayHeight.restype = ctypes.c_int
        x11.XDisplayHeight.argtypes = [ctypes.c_void_p, ctypes.c_int]
        x11.XFlush.argtypes = [ctypes.c_void_p]
        x11.XCloseDisplay.argtypes = [ctypes.c_void_p]
        xtst.XTestQueryExtension.argtypes = [
            ctypes.c_void_p] + [ctypes.POINTER(ctypes.c_int)] * 4
        xtst.XTestFakeMotionEvent.argtypes = [ctypes.c_void_p, ctypes.c_int,
                                              ctypes.c_int, ctypes.c_int,
                                              ctypes.c_ulong]
        xtst.XTestFakeButtonEvent.argtypes = [ctypes.c_void_p, ctypes.c_uint,
                                              ctypes.c_int, ctypes.c_ulong]
        self.dpy = x11.XOpenDisplay(display.encode() if display else None)
        if not self.dpy:
            raise OSError("no se pudo abrir la pantalla %r" % display)
        # XTEST se pregunta ANTES de usarlo: un servidor compilado sin la
        # extension aceptaria la llamada y no haria nada, y eso es peor que
        # un fallo porque no se nota hasta que el usuario dice que no va.
        a = ctypes.c_int(); b = ctypes.c_int()
        c = ctypes.c_int(); d = ctypes.c_int()
        if not xtst.XTestQueryExtension(self.dpy, ctypes.byref(a), ctypes.byref(b),
                                        ctypes.byref(c), ctypes.byref(d)):
            x11.XCloseDisplay(self.dpy)
            self.dpy = None
            raise OSError("la pantalla %r no tiene XTEST" % display)
        self.display = display
        self.pantalla = x11.XDefaultScreen(self.dpy)
        self.ancho = max(1, x11.XDisplayWidth(self.dpy, self.pantalla))
        self.alto = max(1, x11.XDisplayHeight(self.dpy, self.pantalla))
        # EL PUNTERO EMPIEZA EN EL CENTRO, Y NO ES UN CAPRICHO: donde estaba
        # era la esquina de abajo a la derecha, que es donde nace y donde se
        # queda si nadie lo mueve. Desde el centro se llega a cualquier boton
        # de un instalador con medio empujon de stick.
        self.x = self.ancho // 2
        self.y = self.alto // 2
        self._dx = 0.0
        self._dy = 0.0
        self._cola = []
        self._colocar()

    def _colocar(self):
        self.xtst.XTestFakeMotionEvent(self.dpy, self.pantalla,
                                       int(self.x), int(self.y), 0)
        self.x11.XFlush(self.dpy)

    def write(self, tipo, codigo, valor):
        """Lo mismo que escribirle a un uinput, pero se apunta y no se manda.

        Se manda en syn(), igual que un aparato de verdad: asi un clic que
        venga con un movimiento en el mismo lote sale DESPUES del movimiento
        y cae donde el usuario esta viendo el puntero, no donde estaba.
        """
        if tipo == ecodes.EV_REL:
            if codigo == ecodes.REL_X:
                self._dx += valor
            elif codigo == ecodes.REL_Y:
                self._dy += valor
        elif tipo == ecodes.EV_KEY:
            bot = _X_BOTON.get(codigo)
            if bot:
                self._cola.append((bot, 1 if valor else 0))

    def syn(self):
        if self._dx or self._dy:
            self.x = min(self.ancho - 1, max(0, int(self.x + self._dx)))
            self.y = min(self.alto - 1, max(0, int(self.y + self._dy)))
            self._dx = 0.0
            self._dy = 0.0
            self.xtst.XTestFakeMotionEvent(self.dpy, self.pantalla,
                                           int(self.x), int(self.y), 0)
        for bot, val in self._cola:
            self.xtst.XTestFakeButtonEvent(self.dpy, bot, val, 0)
        self._cola = []
        self.x11.XFlush(self.dpy)

    def close(self):
        try:
            if self.dpy:
                self.x11.XCloseDisplay(self.dpy)
        except Exception:
            pass
        self.dpy = None


def abrir_raton_xtest():
    """Devuelve el raton XTEST si procede, o None para usar el de siempre.

    Procede cuando hay una sesion gamescope -el modo Juego-, que es donde el
    raton uinput no llega al juego. Con WP_RATON_XTEST se puede forzar:
    "si" lo usa siempre que se pueda, "no" nunca, "auto" (lo normal) decide
    como aqui.
    """
    # APAGADO DE SERIE, Y ESTO ES UNA MARCHA ATRAS.
    #
    # Se encendia solo en cuanto olia una sesion gamescope. Dani lo probo en
    # su Deck: "con este cambio fue peor". Y tenia razon, porque la premisa
    # estaba mal: el puntero que se VE en el modo Juego no es el del XWayland
    # del juego, asi que moviendo ese por XTEST se mueve uno que no se ve,
    # mientras el que se veia -el del raton uinput- deja de moverse.
    #
    # El codigo se queda porque sirve para probar (WP_RATON_XTEST=si), pero
    # NO decide nada por su cuenta. La causa de verdad se busca por otro lado:
    # comparando el registro del escritorio con el del modo Juego.
    modo = (os.environ.get("WP_RATON_XTEST") or "no").strip().lower()
    if modo not in ("si", "sí", "1", "on"):
        return None
    x11 = _cargar_lib("libX11.so.6", "libX11.so", ctypes.util.find_library("X11"))
    if not x11:
        return None
    x11.XOpenDisplay.restype = ctypes.c_void_p
    x11.XOpenDisplay.argtypes = [ctypes.c_char_p]
    x11.XCloseDisplay.argtypes = [ctypes.c_void_p]
    # Se mira CADA pantalla y se apunta si es la de gamescope. Se cierra
    # enseguida: aqui solo se esta preguntando, no se toca el puntero.
    vistas = []
    for nombre in _pantallas_candidatas():
        dpy = x11.XOpenDisplay(nombre.encode())
        if not dpy:
            continue
        vistas.append((nombre, _tiene_atomo_gamescope(x11, dpy)))
        x11.XCloseDisplay(dpy)
    if not vistas:
        print("[keys] Raton por XTEST: no hay ninguna pantalla X; "
              "se usa el raton virtual de siempre", flush=True)
        return None
    hay_gamescope = any(g for _, g in vistas)
    print("[keys] Pantallas X: %s"
          % ", ".join("%s%s" % (n, " (gamescope)" if g else "")
                      for n, g in vistas), flush=True)
    # La del juego es la que NO es de gamescope. Si no hay ninguna asi -una
    # sesion con un solo XWayland- se usa la que haya, que sera la del juego
    # de todas formas.
    orden = [n for n, g in vistas if not g] + [n for n, g in vistas if g]
    for nombre in orden:
        try:
            raton = RatonXTest(nombre)
        except Exception as e:
            print("[keys] Raton por XTEST: %s no vale (%s)" % (nombre, e),
                  flush=True)
            continue
        print("[keys] Raton por XTEST en la pantalla %s (%dx%d), puntero al "
              "centro en (%d, %d). PEDIDO A MANO con WP_RATON_XTEST=si: no "
              "se enciende solo, porque en una Deck en modo Juego salio peor."
              % (nombre, raton.ancho, raton.alto, raton.x, raton.y), flush=True)
        return raton
    return None


# LOS CODIGOS DE BOTON, PREGUNTADOS AL MANDO.
#
# POR QUE NO VALE UNA TABLA POR MANDO
#
# Teniamos una tabla de codigos por familia de mando, y la de Sony estaba mal:
# el Share y el Options de un DualShock 4 no hacian nada (ver el comentario de
# SONY_DS4). Y ese fallo no se puede arreglar "de verdad" corrigiendo la tabla,
# porque la tabla se va a volver a equivocar con el proximo mando raro: hay
# cientos, y el nombre con el que se reconocen -"wireless controller"- ni
# siquiera identifica al fabricante.
#
# LO QUE SI ES FIABLE: EL PROPIO MANDO LO DICE
#
# evdev declara QUE codigos de tecla tiene cada aparato, y el kernel los nombra
# segun la "Linux gamepad specification": BTN_SELECT es el Select de cualquier
# mando, lo fabrique quien sea. Asi que en vez de adivinar por el nombre, se le
# pregunta: si el mando declara BTN_SELECT, el select es ESE.
#
# Es exactamente lo que el mapeador ya hacia con los ejes -"Umbral de ABS_Y: 89
# (el perfil decia 16000)", leyendo el rango real del mando-, y por lo mismo:
# el aparato sabe mas de si mismo que nuestra tabla.
#
# La tabla se queda como RESPALDO, para un mando que declare codigos fuera de
# la especificacion.
CODIGOS_ESTANDAR = {
    "a":        ecodes.BTN_SOUTH,    # 304
    "b":        ecodes.BTN_EAST,     # 305
    "x":        ecodes.BTN_NORTH,    # 307
    "y":        ecodes.BTN_WEST,     # 308
    "pageup":   ecodes.BTN_TL,       # 310  L1
    "pagedown": ecodes.BTN_TR,       # 311  R1
    "l2":       ecodes.BTN_TL2,      # 312
    "r2":       ecodes.BTN_TR2,      # 313
    "select":   ecodes.BTN_SELECT,   # 314  Share en un DS4, "-" en un Switch
    "start":    ecodes.BTN_START,    # 315  Options en un DS4, "+" en un Switch
    "l3":       ecodes.BTN_THUMBL,   # 317
    "r3":       ecodes.BTN_THUMBR,   # 318
}


# Los nombres, escritos aqui y no sacados de evdev.
#
# La forma de la tabla de nombres de evdev ha cambiado entre versiones -unas
# dan una cadena, otras una lista- y una linea de registro no merece un
# "if hasattr": lo unico que hace falta son estos trece codigos, y de paso se
# dice a que boton FISICO corresponde cada uno, que es el dato que hacia falta
# para entender el fallo del DualShock 4.
NOMBRES_CODIGO = {
    304: "304 BTN_SOUTH (A / Cross)",
    305: "305 BTN_EAST (B / Circle)",
    306: "306 BTN_C",
    307: "307 BTN_NORTH (X / Triangle)",
    308: "308 BTN_WEST (Y / Square)",
    310: "310 BTN_TL (L1)",
    311: "311 BTN_TR (R1)",
    312: "312 BTN_TL2 (L2)",
    313: "313 BTN_TR2 (R2)",
    314: "314 BTN_SELECT (Share / -)",
    315: "315 BTN_START (Options / +)",
    316: "316 BTN_MODE (PS / Home)",
    317: "317 BTN_THUMBL (L3)",
    318: "318 BTN_THUMBR (R3)",
}


def nombre_codigo(c):
    """El codigo con su nombre, para el registro. Si no se conoce, el numero."""
    return NOMBRES_CODIGO.get(c, str(c))


def ids_del_mando(dev, ids_tabla, nombre_perfil=""):
    """Los codigos de boton de ESTE mando, preguntandoselos a el.

    $dev = el aparato evdev, ids_tabla = lo que dice el perfil.
    Devuelve un diccionario nuevo: la tabla NO se toca.
    """
    ids = dict(ids_tabla)
    try:
        hay = set(dev.capabilities().get(ecodes.EV_KEY, []))
    except Exception as e:
        print("[keys] no se han podido leer los botones que declara el mando"
              " (%s): se usa la tabla del perfil %s" % (e, nombre_perfil),
              flush=True)
        return ids
    if not hay:
        return ids
    # ¿El hotkey iba pegado al select? Entonces lo sigue.
    hotkey_era_select = (ids.get("hotkey") is not None
                         and ids.get("hotkey") == ids.get("select"))
    cambiados, confirmados = [], 0
    for nombre, codigo in CODIGOS_ESTANDAR.items():
        if nombre not in ids:
            continue
        if codigo not in hay:
            # El mando no declara el estandar: manda la tabla, que para eso
            # esta. Un mando raro puede poner el Select donde quiera.
            continue
        if ids[nombre] != codigo:
            cambiados.append((nombre, ids[nombre], codigo))
            ids[nombre] = codigo
        else:
            confirmados += 1
    if hotkey_era_select and "select" in ids:
        ids["hotkey"] = ids["select"]
    # LO QUE SE HA CAMBIADO, DICHO. Y con nombre y numero, porque es justo lo
    # que hacia falta para encontrar el fallo del DualShock 4: el registro
    # decia "mapa: select (codigo 312)" y nadie podia saber que 312 no es el
    # Select de ese mando.
    if cambiados:
        print("[keys] El mando declara sus botones y la tabla del perfil %s no"
              " coincidia:" % (nombre_perfil or "?"), flush=True)
        for nombre, viejo, nuevo in cambiados:
            print("[keys]   %-9s la tabla decia %s, el mando dice %s:"
                  " manda el mando"
                  % (nombre, nombre_codigo(viejo), nombre_codigo(nuevo)),
                  flush=True)
    else:
        print("[keys] Los %d boton(es) del perfil %s coinciden con lo que"
              " declara el mando" % (confirmados, nombre_perfil or "?"),
              flush=True)
    return ids


def get_perfil(dev_name):
    name = dev_name.lower()
    for p in PERFILES.values():
        if any(m in name for m in p["match"]):
            return p
    return PERFILES["GENERIC"]



# Como se teclea un texto: caracter -> (tecla, si hace falta shift)
_TECLAS_TEXTO = {' ': ('KEY_SPACE', False), '-': ('KEY_MINUS', False),
                 '_': ('KEY_MINUS', True),  '.': ('KEY_DOT', False),
                 ',': ('KEY_COMMA', False), '@': ('KEY_2', True),
                 "'": ('KEY_APOSTROPHE', False), '/': ('KEY_SLASH', False)}
for _c in 'abcdefghijklmnopqrstuvwxyz':
    _TECLAS_TEXTO[_c] = ('KEY_%s' % _c.upper(), False)
    _TECLAS_TEXTO[_c.upper()] = ('KEY_%s' % _c.upper(), True)
for _c in '0123456789':
    _TECLAS_TEXTO[_c] = ('KEY_%s' % _c, False)


def teclas_de_texto(texto):
    """Los codigos de tecla que hacen falta para escribir un texto."""
    out = set()
    for ch in texto or '':
        par = _TECLAS_TEXTO.get(ch)
        if not par:
            continue
        c = getattr(ecodes, par[0], None)
        if c is not None:
            out.add(c)
        if par[1]:
            out.add(ecodes.KEY_LEFTSHIFT)
    return out


def tecleo_ms():
    """Cuanto se mantiene pulsada una tecla que mandamos NOSOTROS, en ms.

    UN SOLO CRITERIO PARA TODO EL PROGRAMA, Y ESTA FUNCION EXISTE PARA ESO.

    Habia dos sitios que mandan teclas sin que nadie las mantenga: el texto
    rapido (escribir_texto) y las teclas DIFERIDAS -las de un boton que
    tambien forma parte de una combinacion, que se mandan al soltarlo-. El
    primero ya mantenia la tecla 60 ms; el segundo la pulsaba y la soltaba
    seguido, y en un juego que mira el teclado una vez por fotograma eso no se
    ve. Mismo problema, un sitio arreglado y el otro no.

    Se afina con WP_TECLEO_MS. 60 ms son casi cuatro fotogramas a 60 FPS.
    """
    try:
        return max(20, min(500, int(os.environ.get('WP_TECLEO_MS') or 60)))
    except ValueError:
        return 60


def sueltas_vencidas(cola, ahora):
    """Separa la cola de teclas pendientes de soltar.

    Devuelve (vencidas, quedan). La cola son pares (cuando_soltar, [codigos]).

    POR QUE UNA COLA Y NO UN sleep: dormir en el bucle del mapeador lo deja
    SORDO justo mientras alguien juega. Se apunta cuando toca soltar cada
    tecla y se sigue leyendo el mando.
    """
    vencidas, quedan = [], []
    for cuando, codigos in cola or []:
        if cuando <= ahora:
            vencidas.append((cuando, codigos))
        else:
            quedan.append((cuando, codigos))
    return vencidas, quedan


def escribir_texto(ui, texto):
    """Teclea un texto guardado, sin abrir ninguna ventana.

    Es la alternativa al teclado en pantalla, y nacio de una comprobacion de
    un tester: mapear una tecla a un boton escribe perfectamente en el juego,
    pero el teclado en pantalla no. La diferencia no era el dispositivo (es el
    mismo) sino la VENTANA: al abrirla el juego pierde el foco y se minimiza,
    asi que las pulsaciones ya no van a el.

    Sin ventana no hay foco que perder.
    """
    import time as _t
    # CADA TECLA SE MANTIENE PULSADA UN RATO.
    #
    # Antes se pulsaba y se soltaba seguido, con microsegundos de por medio.
    # Un juego que mira el teclado una vez por fotograma (16 ms a 60 FPS) se
    # pierde casi todas: de "DANI" llegaba una letra suelta de milagro. Y por
    # eso mapear una tecla a un boton SI funcionaba: la mantiene el usuario.
    #
    # Se puede afinar con WP_TECLEO_MS si algun juego necesita mas.
    _ms = tecleo_ms()
    _hold = _ms / 1000.0
    escrito = 0
    for ch in texto or '':
        par = _TECLAS_TEXTO.get(ch)
        if not par:
            continue
        code = getattr(ecodes, par[0], None)
        if code is None:
            continue
        if par[1]:
            ui.write(ecodes.EV_KEY, ecodes.KEY_LEFTSHIFT, 1); ui.syn()
            _t.sleep(_hold / 3)          # shift antes que la tecla
        ui.write(ecodes.EV_KEY, code, 1); ui.syn()
        _t.sleep(_hold)                  # <- pulsada, para que la vean
        ui.write(ecodes.EV_KEY, code, 0); ui.syn()
        if par[1]:
            _t.sleep(_hold / 3)
            ui.write(ecodes.EV_KEY, ecodes.KEY_LEFTSHIFT, 0); ui.syn()
        escrito += 1
        _t.sleep(_hold / 2)              # y un hueco entre letras
    # Enter al final, si se ha pedido.
    #
    # No se hace siempre a proposito: hay juegos donde el nombre va en un
    # formulario con varios campos y el Enter salta al siguiente o acepta
    # antes de tiempo. Quien lo quiera, lo marca.
    _enter = (os.environ.get('WP_TEXTO_ENTER') or '0') == '1'
    if _enter and escrito:
        _t.sleep(_hold)                  # que al juego le de tiempo a verlo
        ui.write(ecodes.EV_KEY, ecodes.KEY_ENTER, 1); ui.syn()
        _t.sleep(_hold)
        ui.write(ecodes.EV_KEY, ecodes.KEY_ENTER, 0); ui.syn()
    print("[keys] Texto escrito: %d caracter(es), %d ms cada una%s"
          % (escrito, _ms, " + Enter" if _enter else ""), flush=True)
    return escrito


def launch_teclado_virtual(device, ids=None, ui_kb=None):
    # "device" puede ser UN mando o una LISTA de mandos.
    #
    # Antes solo se le pasaba pads[0], que se elige "para el perfil de botones
    # por defecto". En la Deck, Steam crea varios nodos para el mismo mando y
    # los botones pueden venir por cualquiera de ellos: el teclado salia en
    # pantalla pero no respondia a nada. El bucle principal del mapeador si
    # escucha todos, asi que aqui hay que hacer lo mismo.
    try:
        import pygame
    except ImportError:
        print("[!] pygame no disponible"); return
    try:
        _run_teclado(device, ids, ui_kb)
    except Exception as e:
        print(f"[!] Error teclado virtual: {e}")

def _run_teclado(gamepad_device, ids=None, ui_kb=None):
    import pygame, evdev as _evdev, select as _sel, time as _tm
    # una lista siempre, venga uno o venga varios
    _pads = list(gamepad_device) if isinstance(gamepad_device, (list, tuple)) \
            else [gamepad_device]
    _pads = [d for d in _pads if d is not None]
    # LOS BOTONES, DEL PERFIL DEL MANDO.
    #
    # Estaban escritos a pelo (304 pulsar, 305 borrar, 308 espacio...). Eso
    # supone un mando estilo Xbox: con otro perfil, o con el estilo Batocera
    # puesto (que cambia A y B de sitio), los botones del teclado no eran los
    # que el usuario acababa de configurar.
    _i = ids or {}
    B_OK    = _i.get("a", 304)
    B_BORRA = _i.get("b", 305)
    B_ESP   = _i.get("y", 308)
    B_SALIR = [_i.get("start", 315), _i.get("r2", 313)]
    B_MAYUS = [_i.get("select", 314), _i.get("l2", 312)]
    from evdev import ecodes as ec
    ROWS = [
        ['1','2','3','4','5','6','7','8','9','0','-','=','\u232b'],
        ['q','w','e','r','t','y','u','i','o','p','[',']','\\'],
        ['a','s','d','f','g','h','j','k','l',';',"'",'\u21b5'],
        ['z','x','c','v','b','n','m',',','.','/',],
        ['\u21e7','ESPACIO','.com','@','\u2715'],
    ]
    KEY_MAP = {
        '1':ec.KEY_1,'2':ec.KEY_2,'3':ec.KEY_3,'4':ec.KEY_4,'5':ec.KEY_5,
        '6':ec.KEY_6,'7':ec.KEY_7,'8':ec.KEY_8,'9':ec.KEY_9,'0':ec.KEY_0,
        '-':ec.KEY_MINUS,'=':ec.KEY_EQUAL,'q':ec.KEY_Q,'w':ec.KEY_W,'e':ec.KEY_E,
        'r':ec.KEY_R,'t':ec.KEY_T,'y':ec.KEY_Y,'u':ec.KEY_U,'i':ec.KEY_I,
        'o':ec.KEY_O,'p':ec.KEY_P,'[':ec.KEY_LEFTBRACE,']':ec.KEY_RIGHTBRACE,
        '\\':ec.KEY_BACKSLASH,'a':ec.KEY_A,'s':ec.KEY_S,'d':ec.KEY_D,
        'f':ec.KEY_F,'g':ec.KEY_G,'h':ec.KEY_H,'j':ec.KEY_J,'k':ec.KEY_K,
        'l':ec.KEY_L,';':ec.KEY_SEMICOLON,"'":ec.KEY_APOSTROPHE,'z':ec.KEY_Z,
        'x':ec.KEY_X,'c':ec.KEY_C,'v':ec.KEY_V,'b':ec.KEY_B,'n':ec.KEY_N,
        'm':ec.KEY_M,',':ec.KEY_COMMA,'.':ec.KEY_DOT,'/':ec.KEY_SLASH,
        '\u232b':ec.KEY_BACKSPACE,'\u21b5':ec.KEY_ENTER,'ESPACIO':ec.KEY_SPACE,
    }
    SHIFT_MAP = {
        '1':'!','2':'@','3':'#','4':'$','5':'%','6':'^','7':'&','8':'*',
        '9':'(','0':')','-':'_','=':'+','[':'{',']':'}','\\':'|',
        ';':':','\'':'"',',':'<','.':'>','/':'?',
    }
    KW,KH,GAP,PAD=56,48,5,18
    total_w=max(len(r) for r in ROWS)*(KW+GAP)-GAP+PAD*2
    total_h=len(ROWS)*(KH+GAP)-GAP+PAD*2+50
    TH,SPEED,DEAD=14000,280.0,0.12
    import os as _os, ctypes as _ct
    # cuanto se mantiene pulsada cada tecla (ver press_k)
    try:
        _HOLD = max(20, min(500, int(_os.environ.get('WP_TECLEO_MS') or 60))) / 1000.0
    except (ValueError, TypeError):
        _HOLD = 0.060
    _os.environ['SDL_VIDEODRIVER'] = 'x11'  # XWayland
    # Que la ventana del teclado no se lleve el foco NI moleste al juego.
    #
    # Aunque luego se pone override_redirect, SDL puede pedir el foco al
    # crearla, y muchos juegos a pantalla completa se minimizan en cuanto algo
    # aparece delante. Estas dos son las que SDL respeta.
    _os.environ['SDL_VIDEO_X11_NET_WM_BYPASS_COMPOSITOR'] = '0'
    _os.environ.setdefault('SDL_VIDEO_MINIMIZE_ON_FOCUS_LOSS', '0')
    # Que SDL NO pida el foco al crear la ventana.
    #
    # Hasta ahora la ventana se creaba pidiendolo y luego se lo devolviamos al
    # juego. Eso es una pelea que se puede perder: entre que SDL lo coge y
    # nosotros lo devolvemos, el juego ya ha visto que lo perdio y se ha
    # minimizado. Mejor no pedirlo desde el principio.
    _os.environ['SDL_VIDEO_X11_WMCLASS'] = 'wproton-teclado'
    _os.environ['SDL_WINDOW_ALLOW_HIGHDPI'] = '0'
    _os.environ['SDL_HINT_WINDOW_NO_ACTIVATION_WHEN_SHOWN'] = '1'
    _os.environ['SDL_VIDEO_FOREIGN_WINDOW_OPENGL'] = '0'
    pygame.init()
    # EL JOYSTICK DE SDL, CERRADO. Es el que abre el mando de la Deck y le
    # apaga los trackpads, y aqui no se usa: el mando se lee por evdev. No
    # depende de que esta SDL conozca las variables de arriba.
    try:
        pygame.joystick.quit()
    except Exception:
        pass
    info = pygame.display.Info()
    # DONDE SE PONE EL TECLADO.
    #
    # Estaba clavado abajo. Hay juegos que piden el nombre en la parte de
    # abajo de la pantalla y el teclado tapa justo lo que estas escribiendo,
    # asi que se puede elegir con WP_TECLADO_POS: abajo (por defecto), arriba
    # o centro. En horizontal siempre va centrado.
    _pos = (_os.environ.get('WP_TECLADO_POS') or 'abajo').strip().lower()
    _x = (info.current_w - total_w) // 2
    if _pos == 'arriba':
        _y = 30
    elif _pos in ('centro', 'medio'):
        _y = max(0, (info.current_h - total_h) // 2)
    else:
        _y = info.current_h - total_h - 30
    _y = max(0, min(_y, max(0, info.current_h - total_h)))
    _os.environ['SDL_VIDEO_WINDOW_POS'] = f'{_x},{_y}'
    print("[keys] Teclado en pantalla: %s" % _pos, flush=True)
    screen = pygame.display.set_mode((total_w, total_h), pygame.NOFRAME)
    # Aplicar override_redirect=True via XChangeWindowAttributes + unmap/remap
    # override_redirect impide que KWin gestione la ventana → no le da foco de teclado
    # Usamos X11 API directamente porque SDL_VIDEO_X11_OVERRIDE_REDIRECT no es fiable
    # EL FOCO SE LE DEVUELVE AL JUEGO.
    #
    # Esto es lo que de verdad importaba y faltaba. Si nuestra ventana se
    # queda con el foco, X entrega las pulsaciones A ELLA y no al juego: se
    # escribe, la vista previa del teclado se actualiza, y en el juego no
    # aparece nada. Es exactamente lo que veia un tester, y ademas explica que
    # el juego se minimizara al abrir el teclado.
    #
    # No nos hace falta el foco para nada: el mando se lee por evdev, no por
    # la ventana. Asi que se apunta quien lo tenia ANTES y se le devuelve.
    _foco_previo = None
    try:
        _x11 = _ct.cdll.LoadLibrary('libX11.so.6')
        _x11.XOpenDisplay.restype = _ct.c_void_p
        _dpy = _x11.XOpenDisplay(None)
        if _dpy:
            _w = _ct.c_ulong(0); _rev = _ct.c_int(0)
            _x11.XGetInputFocus(_ct.c_void_p(_dpy), _ct.byref(_w), _ct.byref(_rev))
            if _w.value:
                _foco_previo = (_w.value, _rev.value)
            _x11.XCloseDisplay(_ct.c_void_p(_dpy))
    except Exception as _e:
        print("[keys] No se pudo mirar el foco: %s" % _e, flush=True)

    try:
        _x11 = _ct.cdll.LoadLibrary('libX11.so.6')
        _x11.XOpenDisplay.restype = _ct.c_void_p
        _dpy = _x11.XOpenDisplay(None)
        _our = pygame.display.get_wm_info().get('window', 0)
        if _dpy and _our:
            class _XWA(_ct.Structure):
                _fields_ = [('background_pixmap',_ct.c_ulong),
                            ('background_pixel', _ct.c_ulong),
                            ('border_pixmap',    _ct.c_ulong),
                            ('border_pixel',     _ct.c_ulong),
                            ('bit_gravity',      _ct.c_int),
                            ('win_gravity',      _ct.c_int),
                            ('backing_store',    _ct.c_int),
                            ('backing_planes',   _ct.c_ulong),
                            ('backing_pixel',    _ct.c_ulong),
                            ('save_under',       _ct.c_int),
                            ('event_mask',       _ct.c_long),
                            ('do_not_propagate', _ct.c_long),
                            ('override_redirect',_ct.c_int),
                            ('colormap',         _ct.c_ulong),
                            ('cursor',           _ct.c_ulong)]
            _wa = _XWA(); _wa.override_redirect = 1
            _CWOverrideRedirect = _ct.c_ulong(0x200)
            _x11.XUnmapWindow(_ct.c_void_p(_dpy), _ct.c_ulong(_our))
            _x11.XChangeWindowAttributes(_ct.c_void_p(_dpy), _ct.c_ulong(_our),
                                         _CWOverrideRedirect, _ct.byref(_wa))
            _x11.XMapWindow(_ct.c_void_p(_dpy), _ct.c_ulong(_our))
            _x11.XFlush(_ct.c_void_p(_dpy))
            # Y ahora el foco vuelve a quien lo tenia: el juego.
            if _foco_previo:
                _x11.XSetInputFocus(_ct.c_void_p(_dpy),
                                    _ct.c_ulong(_foco_previo[0]),
                                    _ct.c_int(_foco_previo[1]),
                                    _ct.c_ulong(0))
                _x11.XFlush(_ct.c_void_p(_dpy))
                print("[keys] Foco devuelto a la ventana del juego", flush=True)
            else:
                print("[keys] AVISO: no se sabe quien tenia el foco; si el "
                      "juego no recibe lo que escribes, es por esto", flush=True)
            _x11.XCloseDisplay(_ct.c_void_p(_dpy))
    except Exception as _e:
        # Antes esto era un "except: pass": si fallaba, la ventana se quedaba
        # con el foco y no habia forma de saberlo.
        print("[keys] AVISO: no se pudo soltar el foco (%s). El juego puede "
              "no recibir lo que escribas." % _e, flush=True)
    fk=pygame.font.SysFont('DejaVu Sans',18,bold=True)
    fp=pygame.font.SysFont('DejaVu Sans',20)
    # EL TECLADO SE CREA UNA VEZ, AL ARRANCAR EL MAPEADOR, no aqui.
    #
    # Antes se creaba al abrir el teclado en pantalla y se destruia al
    # cerrarlo. Un teclado que aparece a mitad de partida no siempre lo coge
    # el juego: muchos enumeran los dispositivos de entrada al arrancar y ya
    # no vuelven a mirar. Un tester lo describio como "solo reconoce el input
    # de un teclado real", y la diferencia era justo esa: el real ya estaba
    # ahi antes de lanzar el juego.
    #
    # Si por lo que sea no llega uno hecho, se crea aqui como antes.
    _propio = False
    if ui_kb is None:
        try:
            ui_kb=_evdev.UInput({ec.EV_KEY:list(range(256))},name="TecladoVirtual_DS")
            _propio = True
        except Exception as e:
            print(f"[!] UInput: {e}"); pygame.quit(); return
    def build_layout():
        keys=[]
        for ri,rw in enumerate(ROWS):
            if ri==len(ROWS)-1:
                sp={'ESPACIO':KW*5+GAP*4,'.com':KW*2,'@':KW*2}; x=PAD
                for ci,lb in enumerate(rw):
                    w=sp.get(lb,KW)
                    keys.append((ri,ci,lb,pygame.Rect(x,PAD+50+ri*(KH+GAP),w,KH))); x+=w+GAP
            else:
                n=len(rw); rw_w=n*KW+(n-1)*GAP; x0=PAD+(total_w-PAD*2-rw_w)//2
                for ci,lb in enumerate(rw):
                    keys.append((ri,ci,lb,pygame.Rect(x0+ci*(KW+GAP),PAD+50+ri*(KH+GAP),KW,KH)))
        return keys
    layout=build_layout()
    def key_at(mx,my):
        for ri,ci,lb,rect in layout:
            if rect.collidepoint(mx,my): return ri,ci
        return None,None
    def rect_of(r,c):
        for ri,ci,_,rect in layout:
            if ri==r and ci==c: return rect
        return None
    def press_k(code, shift):
        # La tecla se MANTIENE pulsada un rato, no se pulsa y se suelta
        # seguido.
        #
        # Tenia el mismo fallo que el tecleado de textos: la tecla estaba
        # abajo un tiempo casi cero, y un juego que mira el teclado una vez
        # por fotograma (16 ms a 60 FPS) se pierde casi todas. Puede que fuera
        # esto, y no solo el foco, lo que hacia que no se escribiera nada.
        if shift:
            ui_kb.write(ec.EV_KEY, ec.KEY_LEFTSHIFT, 1); ui_kb.syn()
            _tm.sleep(_HOLD / 3)
        ui_kb.write(ec.EV_KEY, code, 1); ui_kb.syn()
        _tm.sleep(_HOLD)
        ui_kb.write(ec.EV_KEY, code, 0); ui_kb.syn()
        if shift:
            _tm.sleep(_HOLD / 3)
            ui_kb.write(ec.EV_KEY, ec.KEY_LEFTSHIFT, 0); ui_kb.syn()
    def do_key(lb,shift):
        nonlocal preview
        if lb=='\u21e7': return 'shift'
        if lb=='\u2715': return 'close'
        if lb=='ESPACIO': press_k(ec.KEY_SPACE,False); preview+=' '
        elif lb=='.com':
            for cd in [ec.KEY_DOT,ec.KEY_C,ec.KEY_O,ec.KEY_M]: press_k(cd,False)
            preview+='.com'
        elif lb=='@': press_k(ec.KEY_2,True); preview+='@'
        elif lb=='\u21b5': press_k(ec.KEY_ENTER,False); preview=''
        elif lb=='\u232b': press_k(ec.KEY_BACKSPACE,False); preview=preview[:-1]
        else:
            real=SHIFT_MAP.get(lb,lb.upper() if shift else lb)
            kc=KEY_MAP.get(lb)
            if kc: press_k(kc,shift and (lb.isalpha() or lb in SHIFT_MAP))
            preview+=real
        return None
    row,col,shift,preview=1,0,False,''
    ax_val={}; cx,cy=float(total_w//2),float(total_h//2)
    last_move=0; move_delay=0.4
    C={'bg':(20,20,30,210),'key':(55,55,75,230),'sel':(80,140,220,255),
       'sh':(220,160,50,255),'txt':(240,240,240),'sel_t':(255,255,255),
       'prev':(180,220,255),'cur':(255,80,80)}
    clock=pygame.time.Clock(); running=True
    def clamp_col(r,c): return max(0,min(c,len(ROWS[r])-1))
    _foco_avisos = {'robado': 0, 'fallo': False}

    def _devolver_foco():
        # Se repite cada pocos segundos: al dibujar, SDL puede volver a pedir
        # el foco, y entonces las teclas dejarian de llegar al juego a mitad
        # de escribir.
        #
        # Y AHORA SE MIRA ANTES: si el foco ya no es del juego, es que alguien
        # nos lo ha quitado y hay una pelea. Sin esto no habia forma de saber
        # si la devolucion periodica servia de algo, porque no decia nada.
        if not _foco_previo:
            return
        try:
            _d = _x11.XOpenDisplay(None)
            if not _d:
                return
            _w = _ct.c_ulong(0); _rev = _ct.c_int(0)
            _x11.XGetInputFocus(_ct.c_void_p(_d), _ct.byref(_w), _ct.byref(_rev))
            if _w.value != _foco_previo[0]:
                _foco_avisos['robado'] += 1
                if _foco_avisos['robado'] in (1, 10, 50):
                    print("[keys] El foco se ha ido de la ventana del juego "
                          "(%d veces); devolviendolo" % _foco_avisos['robado'],
                          flush=True)
                _x11.XSetInputFocus(_ct.c_void_p(_d),
                                    _ct.c_ulong(_foco_previo[0]),
                                    _ct.c_int(_foco_previo[1]),
                                    _ct.c_ulong(0))
                _x11.XFlush(_ct.c_void_p(_d))
            _x11.XCloseDisplay(_ct.c_void_p(_d))
        except Exception as _e:
            if not _foco_avisos['fallo']:
                _foco_avisos['fallo'] = True
                print("[keys] AVISO: no se puede vigilar el foco (%s)" % _e,
                      flush=True)

    _ult_foco = 0.0
    while running:
        dt=clock.tick(60)/1000.0; now=_tm.time()
        if now - _ult_foco > 0.5:
            _ult_foco = now
            _devolver_foco()
        for ev in pygame.event.get():
            if ev.type==pygame.QUIT: running=False
            elif ev.type==pygame.MOUSEMOTION:
                cx,cy=float(ev.pos[0]),float(ev.pos[1])
                mr,mc=key_at(cx,cy)
                if mr is not None: row,col=mr,mc
            elif ev.type==pygame.MOUSEBUTTONDOWN and ev.button==1:
                cx,cy=float(ev.pos[0]),float(ev.pos[1]); mr,mc=key_at(cx,cy)
                if mr is not None:
                    row,col=mr,mc; r=do_key(ROWS[row][col],shift)
                    if r=='shift': shift=not shift
                    elif r=='close': running=False
        rr,_,_=_sel.select(_pads,[],[],0)
        for _d in rr:
            try:
                for ev in _d.read():
                    if ev.type==ec.EV_ABS: ax_val[ev.code]=ev.value
                    elif ev.type==ec.EV_KEY and ev.value==1:
                        if ev.code==B_OK:
                            mr,mc=key_at(cx,cy)
                            if mr is not None: row,col=mr,mc
                            r=do_key(ROWS[row][col],shift)
                            if r=='shift': shift=not shift
                            elif r=='close': running=False
                        elif ev.code==B_BORRA: press_k(ec.KEY_BACKSPACE,False); preview=preview[:-1]
                        elif ev.code==B_ESP: press_k(ec.KEY_SPACE,False); preview+=' '
                        elif ev.code in B_SALIR: running=False
                        elif ev.code in B_MAYUS: shift=not shift
            except: pass
        rx_r=ax_val.get(ec.ABS_RX,0); ry_r=ax_val.get(ec.ABS_RY,0)
        rx_n=max(-1.0,min(1.0,rx_r/32767.0 if rx_r>=0 else rx_r/32768.0))
        ry_n=max(-1.0,min(1.0,ry_r/32767.0 if ry_r>=0 else ry_r/32768.0))
        if abs(rx_n)<DEAD: rx_n=0.0
        if abs(ry_n)<DEAD: ry_n=0.0
        if rx_n or ry_n:
            cx=max(0.0,min(float(total_w-1),cx+rx_n*SPEED*dt))
            cy=max(0.0,min(float(total_h-1),cy+ry_n*SPEED*dt))
            mr,mc=key_at(cx,cy)
            if mr is not None: row,col=mr,mc
        ax=ax_val.get(ec.ABS_X,0); ay=ax_val.get(ec.ABS_Y,0)
        hx=ax_val.get(ec.ABS_HAT0X,0); hy=ax_val.get(ec.ABS_HAT0Y,0)
        dx=(1 if ax>TH else -1 if ax<-TH else 0) or (1 if hx>0 else -1 if hx<0 else 0)
        dy=(1 if ay>TH else -1 if ay<-TH else 0) or (1 if hy>0 else -1 if hy<0 else 0)
        if (dx or dy) and (now-last_move>move_delay):
            row=max(0,min(row+dy,len(ROWS)-1)); col=clamp_col(row,col+dx)
            r2=rect_of(row,col)
            if r2: cx,cy=float(r2.centerx),float(r2.centery)
            last_move=now; move_delay=0.12
        elif not dx and not dy: move_delay=0.4
        surf=pygame.Surface((total_w,total_h),pygame.SRCALPHA); surf.fill(C['bg'])
        surf.blit(fp.render(preview[-40:]+'\u258c',True,C['prev']),(PAD,10))
        for ri,ci,lb,rect in layout:
            sel=(ri==row and ci==col)
            bg=C['sel'] if sel else (C['sh'] if lb=='\u21e7' and shift else C['key'])
            pygame.draw.rect(surf,bg,rect,border_radius=6)
            if sel: pygame.draw.rect(surf,C['sel_t'],rect,2,border_radius=6)
            disp=lb
            if len(lb)==1 and lb.isalpha(): disp=lb.upper() if shift else lb
            elif lb in SHIFT_MAP and shift: disp=SHIFT_MAP[lb]
            t=fk.render(disp,True,C['sel_t'] if sel else C['txt'])
            surf.blit(t,(rect.x+(rect.width-t.get_width())//2,rect.y+(rect.height-t.get_height())//2))
        ix,iy=int(cx),int(cy)
        pygame.draw.circle(surf,(255,255,255),(ix,iy),8)
        pygame.draw.circle(surf,C['cur'],(ix,iy),6)
        pygame.draw.circle(surf,(255,255,255),(ix,iy),2)
        screen.blit(surf,(0,0)); pygame.display.flip()
    # Solo se cierra si lo hemos creado aqui: el de la sesion tiene que
    # seguir vivo para la proxima vez, y sobre todo para que el juego lo
    # siga viendo.
    if _propio:
        ui_kb.close()
    pygame.quit()

def olvidar_botones(pulsados, pendiente, map_combos, map_normal, soltar):
    """Suelta todo y olvida lo pulsado. Para cuando el mando se va.

    HACE FALTA PORQUE EL MANDO SE PRESTA. Mientras el panel de WProton lo tiene
    capturado, al mapeador no le llega ni un evento. Si el usuario soltaba
    SELECT con el panel abierto, ese soltar no se ve, y al recuperar el mando
    SELECT sigue constando como pulsado. Con un .keys que lleve
    SELECT+START -> Alt+F4, el siguiente START cierra el juego sin que nadie
    haya pedido cerrarlo. Paso de verdad el 21/10, jugando a 88 Heroes.

    Y DE PASO SE SUELTAN LAS TECLAS YA MANDADAS: un boton que se solto mientras
    el panel estaba abierto dejaria su tecla pulsada en el juego para siempre.
    Es el mismo fallo por el otro lado, y se arregla en el mismo sitio.

    "soltar" es la funcion que suelta una tecla; se pasa para poder probar esto
    sin un teclado virtual de verdad.
    """
    for boton in sorted(pulsados):
        for tecla in map_normal.get(boton, []):
            soltar(tecla, False)
    pulsados.clear()
    pendiente.clear()
    for c in map_combos:
        c["active"] = False


def resincronizar_botones(dispositivos, pulsados, pendiente, map_combos):
    """Vuelve a leer del mando que botones estan pulsados DE VERDAD.

    Al recuperar el mando no se puede suponer nada: lo ultimo que sabiamos es
    de antes de prestarlo. El nucleo si sabe el estado real -lo da
    active_keys()-, asi que se pregunta en vez de adivinar: un boton que el
    usuario siga apretando sigue constando, y lo que solto, no.

    Devuelve la lista de dispositivos que no supieron contestar, para poder
    decirlo en el registro.
    """
    fallaron = []
    pulsados.clear()
    pendiente.clear()
    for d in dispositivos:
        try:
            for codigo in d.active_keys():
                pulsados.add(codigo)
        except Exception:
            fallaron.append(getattr(d, "path", "?"))
    # UNA COMBINACION CUYOS BOTONES YA ESTEN PULSADOS SE DA POR DISPARADA. Si
    # no, el siguiente boton que se pulse la haria saltar sin que el usuario
    # haya hecho la combinacion, que es justo el fallo que se esta arreglando.
    for c in map_combos:
        c["active"] = bool(c.get("req")) and all(b in pulsados
                                                 for b in c["req"])
    return fallaron


def main():
    try:
        os.nice(-10)
    except:
        pass

    if len(sys.argv) < 2:
        print("Uso: python3 mapeador.py archivo.keys")
        return

    try:
        with open(sys.argv[1], 'r') as f:
            data = json.load(f)
    except Exception as e:
        print(f"Error al cargar .keys: {e}")
        return

    pads = []
    for p in evdev.list_devices():
        try:
            dev = evdev.InputDevice(p)
            dev_name = dev.name.lower()
            if any(x in dev_name for x in ["motion", "accelerometer", "gyro", "touchpad", "mouse", "keyboard", "mapeador"]):
                continue
            if ecodes.EV_ABS in dev.capabilities() and ecodes.EV_KEY in dev.capabilities():
                pads.append(dev)
        except:
            continue

    # UN mando puede aparecer VARIAS veces: el driver xpad crea un nodo por
    # cada "interfaz" del aparato ("Microsoft X-Box 360 pad" y "...pad 0"),
    # y si se elige el equivocado no llega ni un evento. Se quedan solo los
    # nodos distintos de verdad, comparando el aparato fisico, y de cada uno
    # el que tenga botones de mando (BTN_SOUTH) y ejes.
    def _fisico(d):
        # "usb-0000:00:14.0-3/input0" -> "usb-0000:00:14.0-3"
        base = (getattr(d, 'phys', '') or '').split('/')[0]
        return base or (getattr(d, 'uniq', '') or d.path)

    def _puntua(d):
        # cuanto mas parece un mando de verdad, mejor
        try:
            caps = d.capabilities()
            teclas = caps.get(ecodes.EV_KEY, [])
            ejes = [a for a, _ in caps.get(ecodes.EV_ABS, [])]
            n = 0
            if ecodes.BTN_SOUTH in teclas or ecodes.BTN_A in teclas:
                n += 10
            if ecodes.ABS_X in ejes and ecodes.ABS_Y in ejes:
                n += 5
            return n + min(len(teclas), 20) * 0.1
        except Exception:
            return 0

    mejores = {}
    for d in pads:
        k = _fisico(d)
        if k not in mejores or _puntua(d) > _puntua(mejores[k]):
            mejores[k] = d
    if len(mejores) < len(pads):
        print("[+] %d nodos de entrada -> %d mando(s) real(es)"
              % (len(pads), len(mejores)), flush=True)
        for d in pads:
            if d not in mejores.values():
                try:
                    d.close()
                except Exception:
                    pass
    pads = list(mejores.values())

    if not pads:
        print("No se encontró ningún mando válido en el sistema.")
        return

    # NO se elige mando: se escuchan TODOS a la vez.
    #
    # Elegir uno era la causa de que a veces no funcionara nada: había que
    # esperar a una pulsación (y si no llegaba, adivinar), y con mandos que
    # exponen varios nodos de entrada se podía acabar escuchando el que no
    # recibe eventos. Escuchando todos, el mando SIEMPRE responde: no hay
    # nada que acertar. Si hay dos mandos de verdad, los dos valen, que es
    # justo lo que espera quien juega a dobles.
    device = pads[0]          # solo para el perfil de botones por defecto
    print("[+] Mapeador escuchando %d mando(s):" % len(pads), flush=True)
    for d in pads:
        print("      %s" % d.name, flush=True)

    # El perfil de botones se toma del mando con nombre mas reconocible: si
    # se escuchan varios nodos del mismo aparato, uno puede llamarse de forma
    # generica y dar un perfil equivocado.
    _con_perfil = [d for d in pads
                   if get_perfil(d.name) is not PERFILES["GENERIC"]]
    if _con_perfil:
        device = _con_perfil[0]
    print("[+] Perfil de botones segun: %s" % device.name, flush=True)
    perfil_actual = get_perfil(device.name)
    # QUE PERFIL SE HA ELEGIDO, en el registro.
    #
    # El perfil decide de donde se lee cada control, y la CRUCETA es el que
    # mas cambia: en un mando normal llega como eje (ABS_HAT0), en la Deck
    # llega como botones y ese eje es el touchpad. Con el perfil equivocado,
    # la cruceta del .keys no responde y no hay forma de saber por que.
    #
    # Un tester tenia un .keys de solo cruceta y no le funcionaba: sin esta
    # linea no habia manera de saber si el problema era el perfil o el
    # fichero.
    _nom_perfil = next((k for k, v in PERFILES.items() if v is perfil_actual),
                       "?")
    print("[keys] Mando: \"%s\" -> perfil %s" % (device.name, _nom_perfil),
          flush=True)

    # ¿ES EL MANDO VIRTUAL DE STEAM?
    #
    # Steam no le pasa a los juegos el mando fisico: crea uno VIRTUAL y les da
    # ese. Se reconoce por su identificador, 28DE:11FF, que es el unico dato
    # fiable -por el nombre no, porque se hace pasar por un Xbox 360-.
    #
    # Importa saberlo porque ese mando tiene "modos de accion": en el modo
    # ESCRITORIO no manda botones de mando, sino TECLADO Y RATON -la cruceta
    # son flechas, A es Enter, B es Escape-. Un juego que espere un mando no
    # recibe NADA, aunque el mando se vea perfectamente.
    try:
        _info = device.info
        _es_steam = (_info.vendor == 0x28DE and _info.product == 0x11FF)
    except Exception:
        _es_steam = False
    if _es_steam:
        print("[keys] Es el mando VIRTUAL de Steam (28DE:11FF), no el fisico.",
              flush=True)
        print("[keys] Si el juego no responde a ningun boton, puede estar en"
              " el modo", flush=True)
        print("[keys] ESCRITORIO de Steam, donde el mando manda teclas en vez"
              " de botones:", flush=True)
        print("[keys] manten pulsado Start unos segundos para cambiarlo, o"
              " ponle una", flush=True)
        print("[keys] distribucion de MANDO en los ajustes de Steam del juego.",
              flush=True)
    _ejes = perfil_actual.get("abs_map") or {}
    print("[keys] La cruceta se lee %s"
          % ("como eje (ABS_HAT0)"
             if (ecodes.ABS_HAT0X in _ejes or ecodes.ABS_HAT0Y in _ejes)
             else "como botones"), flush=True)
    # LOS CODIGOS, DEL MANDO. Y UNA COPIA, QUE ANTES NO HABIA.
    #
    # "ids" era el diccionario de la tabla TAL CUAL. Mas abajo, el estilo
    # Nintendo intercambia a/b y x/y ahi dentro... o sea que modificaba la
    # tabla global PERFILES de este proceso. Hoy da igual porque el mapeador
    # mapea una vez y muere, pero es una mina: el dia que se mapee dos veces
    # en el mismo proceso, el segundo juego saldria con los botones cruzados
    # sin que nadie lo haya pedido. Con la copia, no.
    ids            = ids_del_mando(device, perfil_actual["ids"], _nom_perfil)
    abs_map_actual = perfil_actual["abs_map"]
    threshold      = perfil_actual["threshold"]
    center         = perfil_actual["center"]

    map_normal = {}
    map_combos = []
    # botones que salen en alguna combinacion: su tecla se manda al SOLTAR
    btn_en_combo = set()
    # los que estan pulsados esperando a ver si forman combinacion
    pendiente = set()
    DIR_KEYS = [
        "up", "down", "left", "right",
        "joystick1up", "joystick1down", "joystick1left", "joystick1right",
        "joystick2up", "joystick2down", "joystick2left", "joystick2right",
    ]
    map_dirs = {k: [] for k in DIR_KEYS}

    # Estilo de nombres del fichero .keys.
    #
    # Hay dos convenciones para los mismos botones fisicos:
    #   Xbox     -> A es el de abajo,  B el de la derecha
    #   Nintendo -> A es el de la derecha, B el de abajo  (lo que usa
    #               Batocera, y por tanto los .keys hechos alli)
    # Con el estilo equivocado, A y B (y a menudo X e Y) salen cruzados.
    # No se puede adivinar mirando el fichero, asi que se elige por juego.
    if os.environ.get('WP_KEYS_ESTILO') == 'nintendo':
        for _p, _q in (('a', 'b'), ('x', 'y')):
            if _p in ids and _q in ids:
                ids[_p], ids[_q] = ids[_q], ids[_p]
        print("[keys] Estilo de botones: Batocera (A y B cambiados)",
              flush=True)

    _saltadas = 0
    _mouse_eje = None          # stick declarado como raton en las acciones

    # SOLO LEIAMOS actions_player1.
    #
    # La documentacion de Batocera dice que un mismo .keys puede traer los
    # perfiles de VARIOS jugadores: actions_player1, actions_player2... Con un
    # fichero de dos jugadores, el segundo se quedaba sin mapeo y sin aviso.
    #
    # WProton mapea UN mando (el jugador 1), asi que las acciones de los demas
    # no se aplican, pero al menos se dice: antes desaparecian en silencio y
    # nadie sabia por que el segundo mando no respondia.
    _otros = [k for k in data
              if k.startswith('actions_player') and k != 'actions_player1']
    if _otros:
        print("[keys] El fichero trae tambien %s. WProton mapea el mando del"
              " jugador 1; el resto no se aplica."
              % ", ".join(sorted(_otros)), flush=True)
    if data.get('actions_gun1'):
        print("[keys] El fichero trae acciones de pistola optica"
              " (actions_gun1): no se aplican.", flush=True)

    for act in data.get('actions_player1', []):
        # UNA ACCION MAL FORMADA NO PUEDE TUMBAR EL MAPEADOR ENTERO.
        #
        # Un .keys real traia una accion sin "target" y el mapeador moria con
        # KeyError nada mas arrancar: el juego se quedaba sin NINGUN boton, no
        # solo sin ese. Y el aviso decia "el mapeador murio al arrancar", sin
        # decir cual era la accion culpable.
        #
        # Ahora se salta la accion, se dice cual, y las demas funcionan.
        if not isinstance(act, dict):
            _saltadas += 1
            continue
        if 'trigger' not in act or 'target' not in act:
            # EL RATON NO ES UNA ACCION ROTA.
            #
            # Batocera admite {"trigger": "joystick2", "type": "mouse"} sin
            # "target": el destino es el raton, y va implicito en el tipo.
            # Yo lo trataba como fichero mal formado y lo cantaba como aviso,
            # asustando por nada. El raton se configura por su bloque
            # "mouse", asi que aqui basta con saltarlo en silencio.
            if str(act.get('type', '')).lower() == 'exec':
                # ORDENES DEL SISTEMA: SE RECONOCEN, NO SE EJECUTAN.
                #
                # Batocera admite {"type":"exec"} para lanzar una orden con un
                # boton (batocera-screenshot y similares). Aqui no se ejecuta,
                # y a proposito:
                #
                #   - esas ordenes son de Batocera y en otro sistema no
                #     existen, asi que fallarian igual;
                #   - y ejecutar lo que ponga un fichero que viene DENTRO de
                #     un juego descargado es correr codigo ajeno sin avisar.
                #
                # Se dice, que es lo que faltaba: antes se contaba como accion
                # rota y el aviso no aclaraba nada.
                print("[keys] Orden del sistema por '%s' (%s): no se ejecuta."
                      % (act.get('trigger'), act.get('target')), flush=True)
                continue
            if str(act.get('type', '')).lower() == 'mouse':
                # EL RATON TAMBIEN SE DECLARA COMO ACCION.
                #
                # Nosotros lo leiamos SOLO del bloque "mouse" del fichero,
                # pero Batocera admite {"trigger":"joystick2","type":"mouse"}
                # dentro de actions_player1. Con esos ficheros el puntero no
                # se movia: los ignorabamos enteros.
                _tr = str(act.get('trigger') or '')
                if _tr in ('joystick1', 'joystick2'):
                    _mouse_eje = _tr
                    print("[keys] Raton: %s movera el puntero" % _tr, flush=True)
                else:
                    print("[keys] Raton por '%s': no se reconoce el trigger"
                          % _tr, flush=True)
                continue
            _saltadas += 1
            print("[keys] AVISO: accion incompleta en el .keys, se ignora: %r"
                  % (act,), flush=True)
            continue
        trig, target = act['trigger'], act['target']
        is_kb = (target == "TECLADO_VIRTUAL")
        is_txt = (target == "ESCRIBIR_TEXTO")
        t_codes = [] if (is_kb or is_txt) else [getattr(ecodes, t)
                   for t in (target if isinstance(target, list) else [target])
                   if hasattr(ecodes, t)]
        if isinstance(trig, list):
            _req = [ids.get(x, x) for x in trig]
            map_combos.append({"req": _req, "outs": t_codes,
                               "active": False, "kb": is_kb, "txt": is_txt})
            # SOLO se difiere el boton que se MANTIENE, no el que completa la
            # combinacion.
            #
            # En "hotkey+start" el hotkey se aguanta y el start se pulsa
            # despues: al pulsar start la combinacion ya se forma, asi que su
            # tecla puede salir al instante sin adelantarse a nada.
            #
            # Diferirlo tambien (que es lo que se hacia) tenia un efecto
            # secundario feo: el juego ve el boton FISICO del mando antes de
            # que llegue nuestra tecla, y se queda con el. Un tester lo vio
            # claro al mapear controles: todos los botones salian como la
            # tecla asignada menos Start, que salia como "1P START BUTTON".
            btn_en_combo.update(_req[:-1])
        elif trig in map_dirs:
            map_dirs[trig] = t_codes
            # Hay mandos (Anbernic, Decktroid y similares) cuya cruceta llega
            # como BOTONES sueltos en vez de como eje. El helper de menus ya
            # los contemplaba; aqui no, y en esos mandos la cruceta no hacia
            # nada. Se registran tambien como botones normales.
            _btn_cruceta = {"up": 544, "down": 545, "left": 546, "right": 547}
            if trig in _btn_cruceta:
                map_normal[_btn_cruceta[trig]] = t_codes
        elif trig in ids:
            map_normal[ids[trig]] = t_codes

    # ── Teclado virtual para shortcuts ──────────────────────────────────────
    #
    # SE DECLARAN LAS TECLAS QUE HACEN FALTA, UNA A UNA.
    #
    # Antes era evdev.UInput(name=...) a secas, dejando que python-evdev
    # eligiera el juego de teclas del dispositivo. Eso es un cheque en blanco:
    # el kernel DESCARTA EN SILENCIO cualquier tecla que el dispositivo no
    # haya declarado. Se escribia KEY_UP, el registro decia que se habia
    # escrito, y al juego no le llegaba nada. Declarandolas no hay duda.
    _necesarias = set()
    for _lista in list(map_normal.values()) + list(map_dirs.values()):
        _necesarias.update(_lista or [])
    for _c in map_combos:
        _necesarias.update(_c["outs"] or [])
    # SI HAY TECLADO EN PANTALLA, SUS TECLAS VAN EN EL MISMO DISPOSITIVO.
    #
    # Antes se creaba uno aparte ("TecladoVirtual_DS") con las 256 teclas. Y
    # ahi estaba el problema: las teclas del .keys SI llegaban al juego (el
    # mapeo de botones funciona) y las del teclado en pantalla NO, con la
    # misma tecnica y en el mismo proceso.
    #
    # En vez de seguir buscando por que ese dispositivo concreto no lo cogia
    # el juego, se usa EL QUE YA SABEMOS QUE FUNCIONA: se le añaden a "ui" las
    # teclas que necesita el teclado en pantalla y se escribe por ahi.
    _texto_rapido = os.environ.get('WP_TEXTO_RAPIDO', '')
    if any(c.get("txt") for c in map_combos) and _texto_rapido:
        _necesarias.update(teclas_de_texto(_texto_rapido))
        _necesarias.add(ecodes.KEY_ENTER)      # por si se pide Enter al final
        print("[keys] Texto rapido listo (%d caracteres), sin ventana"
              % len(_texto_rapido), flush=True)
    if any(c.get("kb") for c in map_combos):
        for _n in ('KEY_SPACE', 'KEY_ENTER', 'KEY_BACKSPACE', 'KEY_LEFTSHIFT',
                   'KEY_MINUS', 'KEY_EQUAL', 'KEY_LEFTBRACE', 'KEY_RIGHTBRACE',
                   'KEY_BACKSLASH', 'KEY_SEMICOLON', 'KEY_APOSTROPHE',
                   'KEY_COMMA', 'KEY_DOT', 'KEY_SLASH'):
            _c = getattr(ecodes, _n, None)
            if _c is not None:
                _necesarias.add(_c)
        for _ch in 'abcdefghijklmnopqrstuvwxyz0123456789':
            _c = getattr(ecodes, 'KEY_%s' % _ch.upper(), None)
            if _c is not None:
                _necesarias.add(_c)
        print("[keys] El teclado en pantalla usa el mismo teclado virtual "
              "que las demas teclas", flush=True)

    # Los botones de raton NO van en este aparato: van al raton virtual, que se
    # crea mas abajo. Se intento declarar aqui EV_REL para que el teclado
    # pareciera tambien un raton y no sirvio de nada, porque el problema no era
    # la clasificacion del aparato sino que el raton no llegaba a existir.
    try:
        if _necesarias:
            ui = evdev.UInput({ecodes.EV_KEY: sorted(_necesarias)},
                              name="Mapeador_KB_Portable")
            print("[keys] Teclado virtual con %d tecla(s) declarada(s): %s"
                  % (len(_necesarias),
                     ", ".join(sorted(nombre_ev(_k)
                                      for _k in _necesarias))), flush=True)
        else:
            ui = evdev.UInput(name="Mapeador_KB_Portable")
    except Exception as e:
        print(f"ERROR UInput teclado: {e}")
        return

    import time as _tm
    _mcfg=data.get("mouse",{})
    _MAXIS={"joystick1":(ecodes.ABS_X,ecodes.ABS_Y),"joystick2":(ecodes.ABS_RX,ecodes.ABS_RY)}
    # El eje del raton: primero lo que digan las ACCIONES, y si no el bloque
    # "mouse". Un fichero puede traer cualquiera de las dos formas.
    _meje = _mouse_eje or _mcfg.get("axis", "joystick2")
    _mabs_x,_mabs_y=_MAXIS.get(_meje,(ecodes.ABS_RX,ecodes.ABS_RY))
    _mouse_activo = bool(_mouse_eje) or bool(_mcfg)
    _mspeed=float(_mcfg.get("speed",900))
    # Mapa de triggers analógicos: en Xbox 360/One el R2 es ABS_RZ, no un botón digital
    _TRIG_ABS = {
        ids.get("r2"): (ecodes.ABS_RZ, ecodes.ABS_GAS),
        ids.get("l2"): (ecodes.ABS_Z,  ecodes.ABS_BRAKE),
    }

    # LOS TRES BOTONES DEL RATON, NO SOLO EL IZQUIERDO.
    #
    # Antes solo se leia "click_left". Un tester lo conto con un juego en el
    # que recargar es el boton derecho: podia mover el puntero con el stick y
    # disparar con el izquierdo, pero no habia forma de recargar.
    #
    # Los tres van por la misma tabla para que el derecho y el central hereden
    # sin copiar nada el manejo del gatillo analogico, que es lo que de verdad
    # tiene miga: en casi todos los mandos R2 y L2 no mandan una pulsacion sino
    # un eje, y hay que traducirlo con un umbral.
    _RATON_NOMBRE = {ecodes.BTN_LEFT: "clic izquierdo",
                     ecodes.BTN_RIGHT: "clic derecho",
                     ecodes.BTN_MIDDLE: "clic central"}
    # EL CLIC IZQUIERDO, EN DOS BOTONES Y NO EN UNO.
    #
    # Era solo "r2". En el registro del 17/10 no aparece ni un clic: el
    # puntero se movia y el boton no salia nunca. Puede que el gatillo no
    # pasara el umbral -eso se arregla mas abajo, preguntandoselo al mando- o
    # puede, sencillamente, que quien lo estaba probando pulsara la A, que es
    # lo que hace cualquiera delante de un boton "Play". Con los dos puestos
    # da igual cual se pulse.
    #
    # Se admite una lista separada por comas en cualquiera de los tres.
    _MCLICK_CAMPOS = (("click_left",   ecodes.BTN_LEFT,   "a,r2"),
                      ("click_right",  ecodes.BTN_RIGHT,  None),
                      ("click_middle", ecodes.BTN_MIDDLE, None))
    _mclicks = {}        # codigo del boton del mando -> boton del raton
    _mclicks_abs = {}    # codigo del eje del gatillo -> (boton del raton, estado)
    if _mcfg:
        for _campo, _btn, _porDefecto in _MCLICK_CAMPOS:
            _val = _mcfg.get(_campo, _porDefecto)
            if not _val:
                continue
            for _uno in str(_val).split(','):
                _uno = _uno.strip()
                if not _uno:
                    continue
                _cod = ids.get(_uno)
                if _cod is None:
                    print("[keys] AVISO: el raton pide '%s' para el %s y este "
                          "mando no tiene ese boton" % (_uno, _campo), flush=True)
                    continue
                _ejes = _TRIG_ABS.get(_cod, ())
                if _ejes:
                    for _e in _ejes:
                        _mclicks_abs[_e] = _btn
                else:
                    _mclicks[_cod] = _btn
    _mclick_pressed = {}   # estado previo de cada gatillo analogico

    # Gatillos L2/R2 como EJE, no como boton.
    #
    # En casi todos los mandos (Xbox, Steam Deck, DualSense) los gatillos no
    # mandan una pulsacion: mandan un eje de 0 al maximo segun lo apretados
    # que esten. Los codigos de boton 312 y 313 no llegan nunca, asi que un
    # .keys con "l2" o "r2" no hacia nada. Aqui se traduce el eje a
    # pulsacion, con un umbral de la cuarta parte del recorrido.
    _gatillo_teclas = {}
    # ABS_HAT2Y y ABS_HAT2X son los gatillos segun la especificacion de mandos
    # de Linux ("lower trigger buttons are reported as BTN_TR2 or ABS_HAT2X
    # (right) and BTN_TL2 or ABS_HAT2Y (left)"), y es lo que usa hid-steam en
    # la Deck. Sin ellos, un .keys con "l2" o "r2" no hacia NADA ahi.
    #
    # Anadirlos no rompe nada: si un mando manda HAT2 como cruceta digital
    # (rango -1..1), el umbral que se calcula mas abajo es 8 como minimo y ese
    # eje no llega nunca a superarlo, asi que no dispara por error.
    # Los gatillos como DIRECCION DE EJE, igual que Batocera.
    #
    # evmapy.py de Batocera traduce cada nombre generico a un eje con
    # direccion: "ABSY:min" para el stick arriba, "ABSZ:max" para el gatillo
    # izquierdo. Todo pasa por LA MISMA maquina.
    #
    # Aqui habia dos caminos distintos: map_dirs para las direcciones y
    # _gatillo_teclas para los gatillos. Y los registros de un tester
    # demostraron que el de las direcciones funcionaba (el stick giraba el
    # coche) y el de los gatillos no, sin que se viera la diferencia leyendo
    # el codigo. Con un solo camino, esa diferencia no puede existir.
    #
    # abs_dirs:     eje -> (nombre hacia el minimo, nombre hacia el maximo)
    # dirs_teclas:  nombre -> teclas
    # _eje_centro:  eje -> valor de reposo (los gatillos reposan en su MINIMO,
    #               no en el centro del recorrido)
    abs_dirs = dict(abs_map_actual)
    dirs_teclas = dict(map_dirs)
    _eje_centro = {}
    for _n, _ejes in (("l2", (ecodes.ABS_Z, ecodes.ABS_BRAKE, ecodes.ABS_HAT2Y)),
                      ("r2", (ecodes.ABS_RZ, ecodes.ABS_GAS, ecodes.ABS_HAT2X))):
        _cod = ids.get(_n)
        if _cod is not None and map_normal.get(_cod):
            _nombre = "__%s" % _n          # "__l2" / "__r2"
            dirs_teclas[_nombre] = map_normal[_cod]
            for _e in _ejes:
                _gatillo_teclas[_e] = map_normal[_cod]
                # el gatillo solo va en un sentido: hacia su maximo
                abs_dirs[_e] = (None, _nombre)
    _eje_umbral = {}     # lo mismo para los sticks, calculado del propio mando
    _gatillo_visto = set()   # ejes de gatillo de los que ya llego algo
    _dir_vista = set()       # (direccion, encendida) ya trazadas
    _avisos_combo = set()    # combinaciones de las que ya se aviso
    # EL MANDO, EN EXCLUSIVA (como hace Batocera).
    #
    # Esta es la pieza que faltaba. evmapy captura el mando ("grab") y pasa a
    # ser el unico que recibe sus eventos, asi que el juego SOLO ve el teclado
    # virtual. Nosotros no lo haciamos: el juego veia el mando Y el teclado, y
    # uno con soporte de mando usa el mando e ignora las flechas.
    #
    # Era el caso del Need for Speed: mandabamos KEY_UP correctamente -esta en
    # el registro- y el coche no aceleraba, porque el juego estaba escuchando
    # al mando.
    #
    # Y de paso valida la idea de "ocultar el mando al juego" que se retiro en
    # la 1.28: la intencion era buena, el mecanismo (una clave del registro de
    # Wine) era el equivocado.
    def _soltar_mandos():
        # Se suelta lo capturado al terminar. Sin esto el mando se quedaria
        # secuestrado y no responderia a nada mas hasta reiniciar.
        for _d in list(_capturados):
            try:
                _d.ungrab()
            except Exception:
                pass
        if _capturados:
            print("[keys] Mando liberado", flush=True)
        del _capturados[:]

    def _hace_falta_capturar():
        """¿Es un esquema de control completo o son solo atajos?

        Lo dice el propio .keys, asi que no hay que preguntarselo a nadie:

          - Si mapea el MOVIMIENTO (sticks, cruceta, gatillos) es un esquema
            completo: el juego esta pensado para jugarse con el teclado y hay
            que capturar el mando, o el juego usara el mando e ignorara las
            teclas.

          - Si solo hay combinaciones o cuatro botones sueltos, son ATAJOS:
            la gente quiere jugar CON el mando y usar el .keys para salir o
            para el teclado en pantalla. Capturarlo le dejaria sin mando.

        Con los ficheros reales que hemos visto:
          Need for Speed III  sticks + cruceta + gatillos -> capturar
          DRIV3R              solo combinaciones          -> no capturar
        """
        # LA CRUCETA SOLA NO SUSTITUYE AL MANDO.
        #
        # Antes bastaba con map_dirs, que incluye la cruceta. Pero hay .keys
        # que mapean SOLO la cruceta para AÑADIRLA a un juego que ya funciona
        # con el stick: capturar ahi le quita el stick, que era lo unico que
        # le iba. Un tester se quedo sin cruceta Y sin stick.
        #
        # Sustituir al mando es mapear los STICKS o los gatillos.
        _sticks = [k for k in map_dirs if k.startswith('joystick') and map_dirs[k]]
        if _sticks:
            return True, "el .keys mapea los sticks"
        for _n in ("l2", "r2"):           # gatillos
            _c = ids.get(_n)
            if _c is not None and map_normal.get(_c):
                return True, "el .keys mapea los gatillos"
        return False, "el .keys solo trae atajos, no un esquema de control"

    _capturados = []
    # LO QUE SE LE DEBE AL PANEL, O LO QUE EL PANEL NOS DEBE.
    #
    # Dos casos, y los dos acaban aqui:
    #   - el panel pidio el mando prestado y se le cedio;
    #   - al arrancar no se pudo capturar PORQUE LO TENIA EL PANEL.
    # En los dos, el mando se coge en cuanto el panel diga "coge". Se declaran
    # arriba del todo porque el segundo caso pasa antes de entrar en el bucle.
    _mando_cedido = []
    _mando_desde = [0.0]
    # Y AL RECIBIR LA SEÑAL DE CIERRE.
    #
    # El mapeador no termina solo: lo mata WProton al acabar el juego. Sin
    # atender la señal, el proceso muere sin soltar el mando.
    #
    # (El kernel lo suelta al cerrarse el descriptor, pero mas vale hacerlo
    # nosotros y dejarlo dicho en el registro: si algun dia el mando se queda
    # sordo, la ultima linea del log dira si se solto o no.)
    import atexit as _atexit
    import signal as _signal
    _atexit.register(lambda: _soltar_mandos())

    def _adios(_sig, _frm):
        _soltar_mandos()
        raise SystemExit(0)

    for _s in (_signal.SIGTERM, _signal.SIGINT, _signal.SIGHUP):
        try:
            _signal.signal(_s, _adios)
        except Exception:
            pass

    # El cierre y el menu de WProton cuando el mando acaba capturado AQUI. Se
    # rellenan mas abajo, y solo si de verdad se captura; se declaran antes
    # para que el bucle pueda preguntar por ellos sin saber como acabo la cosa.
    _ov_marca, _ov_req, _ov_ultimo = '', [], [0.0]
    _modo_grab = (os.environ.get('WP_KEYS_GRAB') or 'auto').strip().lower()
    if _modo_grab in ('auto', ''):
        _capturar, _porque = _hace_falta_capturar()
        print("[keys] Captura del mando: automatico -> %s (%s)"
              % ("SI" if _capturar else "no", _porque), flush=True)
    else:
        _capturar = (_modo_grab == '1')
    if _capturar:
        import errno as _errno
        import time as _t0
        for _d in pads:
            try:
                _d.grab()
                _capturados.append(_d)
            except Exception as _e:
                # OCUPADO NO ES QUE NO: ES "AHORA NO".
                #
                # Si el mando esta ocupado, casi siempre lo tiene EL PANEL de
                # WProton, que es quien lo pide prestado mientras esta abierto.
                # Y el caso normal es justo ese: el panel asigna una tecla, eso
                # reinicia el mapeador, y el mapeador arranca con el panel
                # todavia abierto.
                #
                # Darse por vencido ahi dejaba al juego con el mando crudo Y
                # las teclas para el resto de la partida: el .keys no servia
                # de nada en cuanto se abria el menu una vez. Ahora se apunta
                # el mando como "pendiente" y se coge en cuanto el panel lo
                # devuelva (o solo, a los 180 s, si el panel no lo devuelve).
                if getattr(_e, 'errno', None) == _errno.EBUSY:
                    _mando_cedido.append(_d)
                    print("[keys] %s esta ocupado (lo tiene el panel): se"
                          " cogera en cuanto lo suelte" % _d.path, flush=True)
                else:
                    print("[keys] No se pudo capturar %s: %s" % (_d.path, _e),
                          flush=True)
        if _mando_cedido:
            _mando_desde[0] = _t0.monotonic()
        # PENDIENTE CUENTA COMO CAPTURADO, Y ESTO NO ES UN DETALLE.
        #
        # Todo lo de aqui dentro -la salida de emergencia con Select y la
        # vigilancia de la combinacion del menu- existe porque, con el mando
        # capturado AQUI, el guardian no recibe nada. Si se montara solo
        # cuando el mando ya esta en la mano, un mapeador que arranca con el
        # panel abierto no lo montaria... y en cuanto el panel le devolviera
        # el mando, el guardian se quedaria sordo y NADIE vigilaria ni el
        # cierre ni la combinacion del menu: el menu no se podria volver a
        # abrir en toda la partida.
        if _capturados or _mando_cedido:
            if _capturados:
                print("[keys] Mando capturado en exclusiva (%d): el juego solo"
                      " vera el teclado, como en Batocera" % len(_capturados),
                      flush=True)
            else:
                print("[keys] El mando lo tiene el panel ahora mismo; se coge"
                      " en cuanto lo suelte (%d)" % len(_mando_cedido),
                      flush=True)
            # SALIDA DE EMERGENCIA, PORQUE EL GUARDIAN SE QUEDA SORDO.
            #
            # El guardian (mantener Select 2s para cerrar) es OTRO proceso y
            # lee los mismos dispositivos: con la captura puesta no recibe
            # nada. Si el .keys no trae una combinacion de salida, el usuario
            # se quedaria sin forma de cerrar el juego.
            #
            # Asi que la vigila el propio mapeador, que si tiene los eventos.
            _hot = ids.get("hotkey", ids.get("select"))
            # MANTENER SELECT SIEMPRE CIERRA EL JUEGO. SIN EXCEPCIONES.
            #
            # EL FALLO QUE ESTO ARREGLA
            #
            # Antes esto se desactivaba si el .keys traia "alguna combinacion
            # que usara Select". Y esa comprobacion no distingue nada: un
            # "Select + X abre el teclado en pantalla" la cumple igual, y
            # entonces el usuario se quedaba sin forma de salir del juego.
            # Mantener Select cinco segundos no hacia nada y habia que ir a
            # Alt+F4, que en el modo Juego de la Deck no esta a mano.
            #
            # No hay conflicto real con las combinaciones: una combinacion se
            # pulsa y se suelta en un instante; esto exige CINCO SEGUNDOS
            # sostenidos. Quien no quiera esta salida tiene PAD_EXIT=0.
            _tiene_salida = False
            _salida_marca = os.environ.get('WP_SALIR_MARCA', '')
            # El MISMO tiempo que el guardian, no uno inventado.
            #
            # Yo habia puesto 2 segundos a ojo, pero el guardian usa 5 y
            # ademas es configurable (PAD_EXIT_SEGUNDOS). Dos comportamientos
            # distintos para lo mismo confunden a cualquiera.
            try:
                _salida_seg = float(os.environ.get('WP_SALIR_SEGUNDOS') or 5)
            except ValueError:
                _salida_seg = 5.0
            _salida_seg = max(1.0, min(30.0, _salida_seg))
            print("[keys] Mantener Select %g s cierra el juego (lo vigila el"
                  " mapeador, que es quien tiene el mando capturado)"
                  % _salida_seg, flush=True)
            # Y LO MISMO CON EL MENU DE DENTRO DEL JUEGO, por la misma razon.
            #
            # EL AGUJERO QUE ESTO TAPA: el panel de WProton lo abre el
            # guardian, que lee los mismos dispositivos. Con el mando
            # capturado aqui, el guardian no recibe NADA, asi que la
            # combinacion del menu no funcionaba... justo en los juegos que
            # tienen un .keys propio, que son los que mas falta les hace poder
            # colgarle una tecla a un boton sin salir.
            #
            # No se abre desde aqui -el panel es del guardian, que es quien
            # sabe pintarlo-: se le avisa por un fichero, igual que el cierre.
            _ov_marca = os.environ.get('WP_OVERLAY_MARCA', '')
            _ov_combo = (os.environ.get('WP_OVERLAY_COMBO') or '').strip()
            _ov_req = []
            if _ov_marca and _ov_combo and _ov_combo not in ('no', 'off'):
                # Los mismos nombres que usa el panel, traducidos a los
                # codigos de ESTE mando con su propia tabla de ids: en un
                # mando raro L1 no tiene por que ser 310.
                #
                # OJO CON "guide", QUE AQUI ESTABA MAL: el boton de Steam es
                # el 316 y NINGUN perfil le pone nombre, asi que traducirlo
                # por "hotkey" -como se escribio primero- lo convertia en el
                # 314, que es SELECT. O sea: elegir "el boton Steam" habria
                # hecho que Select a secas abriera el panel en cualquier juego
                # con .keys. Por eso los codigos sueltos van tal cual y solo
                # los que tienen nombre pasan por la tabla del mando.
                _ov_partes = {'select_l1': ('select', 'pageup'),
                              'select_r1': ('select', 'pagedown'),
                              'select_l3': ('select', 'l3'),
                              'select_y': ('select', 'y'),
                              'l3r3': ('l3', 'r3'),
                              'guide': (316,)}.get(_ov_combo, ())
                _ov_req = [(ids[_n] if isinstance(_n, str) else _n)
                           for _n in _ov_partes
                           if not isinstance(_n, str) or _n in (ids or {})]
                if len(_ov_req) != len(_ov_partes):
                    print("[keys] El menu de WProton no se puede vigilar: este"
                          " mando no tiene todos los botones de %s"
                          % _ov_combo, flush=True)
                    _ov_req = []
            if _ov_req:
                print("[keys] %s abre el menu de WProton (lo vigila el"
                      " mapeador, que tiene el mando capturado)"
                      % _ov_combo, flush=True)
        else:
            print("[keys] AVISO: no se pudo capturar ningun mando. Si el juego"
                  " soporta mando, puede que ignore las teclas.", flush=True)

    else:
        print("[keys] Mando NO capturado (WP_KEYS_GRAB=0): el juego lo vera"
              " ademas del teclado", flush=True)
    _gat_trazas = [0]        # cuantas trazas de gatillo se han escrito
    _hot_desde = [0.0]       # cuando se pulso el hotkey (salida de emergencia)
    # Resumen de lo que ha quedado cargado.
    #
    # Antes solo se decia algo CUANDO habia gatillos; si la tabla salia vacia
    # no se escribia ni una linea, asi que ante un "los gatillos no me van" no
    # habia forma de distinguir entre "no se cargaron" y "se cargaron pero no
    # llegan eventos". Ahora se dice siempre, y por su nombre.
    def _nom_eje(_c):
        _n = ecodes.ABS.get(_c, _c)
        return _n if isinstance(_n, str) else str(_c)

    if _saltadas:
        print("[keys] %d accion(es) del .keys ignoradas por estar incompletas"
              % _saltadas, flush=True)
    print("[keys] Botones cargados: %d" % len(map_normal), flush=True)
    # EL MAPA, EN PALABRAS, Y DICIENDO CUAL VA DIFERIDA.
    #
    # "Botones cargados: 3" no sirve para contestar a "lo mapeo y no funciona":
    # no dice QUE boton, ni a QUE tecla, ni -lo que de verdad importaba aqui-
    # si esa tecla se manda al pulsar o se espera a soltar el boton por formar
    # parte de una combinacion. Ahora el registro lo dice antes de jugar.
    _nom_btn_id = {}
    for _n, _c in (ids or {}).items():
        _nom_btn_id.setdefault(_c, _n)
    for _cod in sorted(map_normal):
        _teclas_txt = ", ".join(nombre_ev(_t) for _t in map_normal[_cod])
        print("[keys] mapa: %s (codigo %d) -> %s%s"
              % (_nom_btn_id.get(_cod, "boton"), _cod, _teclas_txt,
                 "  [se manda AL SOLTAR: el boton tambien esta en una combinacion]"
                 if _cod in btn_en_combo else ""),
              flush=True)
    # Las combinaciones, con los CODIGOS que esperan.
    #
    # Sin esto, una combinacion que no casa con lo que pulsa el usuario no se
    # ve por ningun lado: el registro decia "Combinaciones: 3" y nada mas.
    # Paso con "hotkey+a" en estilo Batocera, donde "a" es el boton de la
    # derecha: el usuario pulsaba el de abajo y no ocurria nada.
    # Los botones POR SU NOMBRE, no por su codigo.
    #
    # Antes salia "Combinacion [314, 305]" y hacia falta saberse los numeros
    # para ver que 305 es el de la DERECHA. Un tester estuvo pulsando el de
    # abajo (304) sin entender por que no pasaba nada, y la respuesta estaba
    # en esa linea.
    _POS = {304: "el de ABAJO", 305: "el de la DERECHA",
            307: "307", 308: "308",
            314: "Select", 315: "Start", 310: "L1", 311: "R1"}
    for _c in map_combos:
        _que = "teclado en pantalla" if _c.get("kb") else (
               "escribir texto" if _c.get("txt") else
               ",".join(nombre_ev(_k) for _k in _c["outs"]))
        _btns = " + ".join(_POS.get(_k, str(_k)) for _k in _c["req"])
        print("[keys] Combinacion: %s  (codigos %s)  ->  %s"
              % (_btns, _c["req"], _que), flush=True)
    _dirs = [k for k, v in map_dirs.items() if v]
    print("[keys] Direcciones cargadas: %s"
          % (", ".join(sorted(_dirs)) if _dirs else "NINGUNA"), flush=True)
    if _gatillo_teclas:
        print("[keys] Gatillos analogicos por: %s"
              % ", ".join(sorted(_nom_eje(_e) for _e in _gatillo_teclas)),
              flush=True)
    else:
        print("[keys] Gatillos analogicos: NINGUNO "
              "(el .keys no asigna l2 ni r2, o el perfil no los define)",
              flush=True)
    _ejes_usados = sorted(_nom_eje(_c) for _c in abs_dirs)
    print("[keys] Ejes que se vigilan: %s" % ", ".join(_ejes_usados), flush=True)
    if map_combos:
        print("[keys] Combinaciones: %d (sus botones se envian al soltar)"
              % len(map_combos), flush=True)
    ui_mouse=None
    # El raton se crea si lo pide el bloque "mouse" O una accion con
    # type=mouse. Antes solo lo primero, y los ficheros que usan la segunda
    # forma se quedaban sin puntero.
    # TAMBIEN SI ALGUNA TECLA APUNTA A UN BOTON DE RATON.
    #
    # EL FALLO QUE ESTO ARREGLA
    #
    # Un .keys puede pedir un clic con "type": "key" y "target": "BTN_LEFT",
    # sin bloque mouse ni type=mouse. Eso no encendia _mouse_activo, asi que no
    # se creaba el raton virtual, y al pulsar salia en el registro:
    #
    #   [keys] AVISO: el .keys pide BTN_RIGHT (boton de raton) pero no hay
    #          raton virtual
    #
    # Las teclas funcionaban y los clics no. Caso real: 8bit Killer, con los
    # gatillos mapeados a BTN_LEFT y BTN_RIGHT.
    #
    # El aviso ya estaba y decia la verdad; lo que faltaba era crear el aparato.
    _btn_raton = {getattr(ecodes, _n, None)
                  for _n in ('BTN_LEFT', 'BTN_RIGHT', 'BTN_MIDDLE')} - {None}
    _keys_con_raton = False
    # Las tablas guardan LISTAS de codigos: map_normal por boton, map_dirs por
    # direccion y map_combos con sus "outs". Se miran las tres.
    for _v in list(map_normal.values()) + list(map_dirs.values()) \
            + [_c.get("outs", []) for _c in map_combos]:
        for _cc in (_v if isinstance(_v, (list, tuple, set)) else [_v]):
            if _cc in _btn_raton:
                _keys_con_raton = True
    if _keys_con_raton and not _mouse_activo:
        print("[keys] El .keys manda clics de raton: se crea el raton virtual "
              "aunque no haya modo raton", flush=True)
    if _mouse_activo or _keys_con_raton:
        # PRIMERO XTEST, Y SOLO DONDE HACE FALTA.
        #
        # En el modo Juego el raton uinput no llega al juego (esta contado
        # largo y tendido arriba, en RatonXTest). abrir_raton_xtest devuelve
        # None en el escritorio, asi que ahi no cambia nada: sigue el uinput
        # de siempre.
        #
        # Los dos saben write()/syn()/close(), asi que de aqui para abajo da
        # igual cual sea: no hay ni un "if" mas en todo el bucle.
        try:
            ui_mouse = abrir_raton_xtest()
        except Exception as e:
            print("[keys] Raton por XTEST: no se pudo (%s)" % e, flush=True)
            ui_mouse = None
        try:
            if ui_mouse is None:
                ui_mouse=evdev.UInput({ecodes.EV_REL:[ecodes.REL_X,ecodes.REL_Y],
                                   ecodes.EV_KEY:[ecodes.BTN_LEFT,ecodes.BTN_RIGHT,
                                                  ecodes.BTN_MIDDLE]},
                                  name="Mapeador_Mouse_Portable")
            if _mouse_activo:
                # El registro dice QUE BOTON HACE QUE CLIC, los tres.
                # Con solo "hace clic" no habia forma de saber, leyendo el log
                # de un tester, si el derecho estaba puesto o no.
                _detalle = []
                for _campo, _btn, _porDefecto in _MCLICK_CAMPOS:
                    _v = _mcfg.get(_campo, _porDefecto)
                    if _v:
                        _detalle.append("%s = %s" % (_v, _RATON_NOMBRE.get(_btn, _btn)))
                print("[keys] Raton virtual: %s mueve el puntero%s"
                      % (_meje, (" | " + ", ".join(_detalle)) if _detalle else ""),
                      flush=True)
            else:
                print("[keys] Raton virtual creado solo para los clics "
                      "(el puntero no se mueve)", flush=True)
        except Exception as e:
            print(f"[!] Sin ratón virtual: {e}"); ui_mouse=None
    _macc_x=0.0; _macc_y=0.0; _mlast=_tm.monotonic(); _msx=center; _msy=center
    # Lo que se aprende del mando para el raton: por eje, (reposo, recorrido,
    # zona muerta). Y el umbral de cada gatillo que haga de clic.
    _mabs_info={}
    _mclick_umbral={}
    _mpx=0; _mpy=0; _mlog=_mlast     # cuanto se ha movido, para el registro

    # DOS controles pueden mandar la MISMA tecla. En el .keys de Need for
    # Speed, r2 y joystick1up mandan los dos KEY_UP. Antes cada uno escribia
    # por su cuenta, asi que al soltar el stick se soltaba la tecla aunque el
    # gatillo siguiera apretado: en un juego de coches, dejaba de acelerar y
    # parecia que el gatillo no funcionaba.
    #
    # Ahora se cuenta cuantas fuentes mantienen cada tecla. Se suelta cuando
    # la suelta LA ULTIMA, no la primera.
    _ref = {}
    _avisadas = set()
    _emitidas = set()   # teclas que ya se han mandado alguna vez

    def _nombre_btn(codigo):
        """Nombre legible de una tecla o boton.

        Lo hace nombre_ev(), arriba del todo: aqui habia una segunda copia de
        la misma idea, y la de alla abajo -la que escribia el mapa- era una
        TERCERA que no contemplaba las tuplas y tumbaba el mapeador. Una sola
        regla, en un solo sitio.
        """
        return nombre_ev(codigo)

    def _tecla(codigo, encendida):
        """Pulsa o suelta una tecla que pueden mandar VARIOS controles.

        Un .keys puede asignar la misma tecla a dos sitios a proposito: en
        Need for Speed, el gas (flecha arriba) esta en el gatillo Y en el
        stick, para poder acelerar con cualquiera de los dos.

        Las dos reglas, y hacen falta las dos:

          - Al PULSAR, el juego tiene que enterarse SIEMPRE, aunque otro
            control ya tuviera la tecla cogida. Si no, el segundo control
            parece muerto: no genera ningun evento. Cuando ya esta pulsada
            se suelta y se vuelve a pulsar, para que se vea una pulsacion
            nueva y no un silencio.

          - Al SOLTAR, la tecla se levanta cuando la suelta EL ULTIMO. Si no,
            soltar el stick apagaba el gas aunque el gatillo siguiera a fondo.
        """
        # LOS BOTONES DE RATON VAN AL RATON, NO AL TECLADO.
        #
        # Un .keys puede poner {"trigger":"pagedown","target":"BTN_LEFT"}: es
        # el clic izquierdo. Pero eso se mandaba al teclado virtual, que solo
        # declara teclas KEY_*, y el kernel descarta EN SILENCIO lo que no
        # este declarado. El clic no llegaba nunca y no habia ni un aviso.
        _dst = ui
        if codigo in (ecodes.BTN_LEFT, ecodes.BTN_RIGHT, ecodes.BTN_MIDDLE):
            if ui_mouse is None:
                if codigo not in _emitidas:
                    _emitidas.add(codigo)
                    print("[keys] AVISO: el .keys pide %s (boton de raton)"
                          " pero no hay raton virtual"
                          % _nombre_btn(codigo), flush=True)
                return
            _dst = ui_mouse
        if encendida:
            _ref[codigo] = _ref.get(codigo, 0) + 1
            if _ref[codigo] == 1:
                _dst.write(ecodes.EV_KEY, codigo, 1)
            else:
                _dst.write(ecodes.EV_KEY, codigo, 0)
                _dst.syn()
                _dst.write(ecodes.EV_KEY, codigo, 1)
                if codigo not in _avisadas:
                    _avisadas.add(codigo)
                    print("[keys] %s la mandan varios controles a la vez; "
                          "se repulsa para que el juego lo note"
                          % nombre_ev(codigo), flush=True)
        else:
            n = _ref.get(codigo, 0)
            if n <= 0:
                return            # nadie la tenia: no se manda un soltar suelto
            _ref[codigo] = n - 1
            if _ref[codigo] == 0:
                _dst.write(ecodes.EV_KEY, codigo, 0)
        if _dst is not ui:
            _dst.syn()          # el raton no pasa por el syn del teclado
        if codigo not in _emitidas:
            _emitidas.add(codigo)
            print("[keys] Al %s virtual: %s"
                  % ("raton" if _dst is not ui else "teclado",
                     _nombre_btn(codigo)), flush=True)

    pulsados = set()

    def _olvidar_botones(por_que):
        olvidar_botones(pulsados, pendiente, map_combos, map_normal, _tecla)
        print("[keys] %s: se sueltan las teclas y se olvida lo pulsado"
              % por_que, flush=True)

    def _resincronizar_botones(dispositivos, por_que):
        fallaron = resincronizar_botones(dispositivos, pulsados, pendiente,
                                         map_combos)
        for ruta in fallaron:
            print("[keys] no se pudo releer el estado de %s" % ruta, flush=True)
        print("[keys] %s: pulsados de verdad = %s"
              % (por_que, sorted(pulsados) or "ninguno"), flush=True)

    ejes_on  = {k: False for k in list(DIR_KEYS) + list(dirs_teclas)}
    # CUANTO SE MANTIENE PULSADA UNA TECLA QUE MANDAMOS NOSOTROS.
    #
    # El mismo ajuste que usa escribir_texto (WP_TECLEO_MS), a proposito: dos
    # criterios distintos para lo mismo es lo que hace que una cosa se arregle
    # y la otra se quede atras. 60 ms son casi cuatro fotogramas a 60 FPS.
    import time as _tiempo
    _HOLD_MS = tecleo_ms()
    _soltar_luego = []   # [(cuando_soltar, [codigos])]
    # El fichero por el que el panel de WProton pide "manda esta tecla". Se
    # mira cada 80 ms como mucho: es un fichero que casi nunca esta, y
    # preguntar por el en cada vuelta del bucle seria un stat cada milisegundo.
    _tecla_marca = os.environ.get('WP_TECLA_MARCA', '')
    _tecla_ult = [0.0]
    if _tecla_marca:
        try:
            os.remove(_tecla_marca)      # de una partida anterior, si quedo
        except OSError:
            pass
        print("[keys] el panel puede pedir teclas por %s" % _tecla_marca,
              flush=True)

    # EL MANDO PRESTADO AL PANEL.
    #
    # La captura de evdev es excluyente: la tiene uno o la tiene el otro. Si
    # este mapeador la tiene, el panel de WProton abre SIN MANDO -"overlay
    # ABIERTO (0 de 2 dispositivo(s) capturados)" en el registro de la prueba
    # de Dani- y no se puede ni bajar por el menu. Asi que el panel la pide
    # prestada: escribe "suelta" en este fichero, aqui se suelta, el panel la
    # coge, y al cerrarse escribe "coge" y se recupera.
    #
    # Se mira con el mismo reloj que las teclas (80 ms): es un fichero que casi
    # nunca esta y preguntar por el cada milisegundo seria un stat por vuelta.
    _mando_marca = os.environ.get('WP_MANDO_MARCA', '')
    _mando_ult = [0.0]
    # Lo que se cedio, para saber si hay que recuperarlo y para no recuperar
    # nada si nunca se capturo (un .keys de solo atajos no captura).
    if _mando_marca:
        try:
            os.remove(_mando_marca)      # de una partida anterior, si quedo
        except OSError:
            pass
        print("[keys] el panel puede pedir el mando prestado por %s"
              % _mando_marca, flush=True)

    try:
        while True:
            r, _, _ = select.select(pads, [], [], 0.001)
            # LAS TECLAS QUE TOCA SOLTAR YA. Ver el comentario de
            # "_soltar_luego" mas abajo: se mantienen pulsadas un rato para que
            # un juego que mira el teclado una vez por fotograma las vea, y se
            # sueltan aqui sin parar el bucle.
            if _soltar_luego:
                _vencidas, _quedan = sueltas_vencidas(_soltar_luego,
                                                      _tiempo.monotonic())
                for _cuando, _codigos in _vencidas:
                    for _t in _codigos:
                        _tecla(_t, False)
                    ui.syn()
                _soltar_luego[:] = _quedan
            # ¿NOS PIDE EL PANEL QUE MANDEMOS UNA TECLA?
            #
            # POR QUE ESTO ESTA AQUI Y NO EN EL PANEL. El panel la mandaba por
            # XTEST, y eso funciona -cuando funciona- solo en X11: en Wayland
            # el juego va por XWayland y en la prueba de Dani el registro dijo
            # "mandada, pero el servidor X no la dio por pulsada". Un teclado
            # de kernel (uinput) lo lee el compositor igual en X11 que en
            # Wayland, y aqui ya hay uno abierto. Asi que la tecla la manda
            # quien puede: nosotros.
            #
            # Se mira un fichero y no se abre un socket ni nada parecido
            # porque es lo que ya se hace con el cierre y con el menu: tres
            # ficheros y ninguna sorpresa.
            if _tecla_marca and _tiempo.monotonic() - _tecla_ult[0] > 0.08:
                _tecla_ult[0] = _tiempo.monotonic()
                try:
                    if os.path.exists(_tecla_marca):
                        with open(_tecla_marca) as _fh:
                            _pedida = _fh.read().strip()
                        os.remove(_tecla_marca)
                        _cods = []
                        for _n in _pedida.split('+'):
                            _n = _n.strip()
                            _c = ecodes.ecodes.get(_n) if _n else None
                            if _c is None:
                                print("[keys] el panel pidio '%s' y no se "
                                      "reconoce" % _n, flush=True)
                                _cods = []
                                break
                            _cods.append(_c)
                        if _cods:
                            for _c in _cods:
                                _tecla(_c, True)
                            ui.syn()
                            # Se suelta por la misma cola que todo lo demas:
                            # mantenida el tiempo que un juego necesita para
                            # verla, y sin dormir el bucle.
                            _soltar_luego.append(
                                (_tiempo.monotonic() + _HOLD_MS / 1000.0,
                                 list(reversed(_cods))))
                            print("[keys] el panel pidio %s: mandada por el "
                                  "teclado virtual" % _pedida, flush=True)
                except OSError as _e:
                    print("[keys] no se pudo atender la tecla del panel: %s"
                          % _e, flush=True)
            # ¿NOS PIDE EL PANEL EL MANDO PRESTADO?
            if _mando_marca and _tiempo.monotonic() - _mando_ult[0] > 0.08:
                _mando_ult[0] = _tiempo.monotonic()
                # RED DE SEGURIDAD: SI EL PANEL NO LO DEVUELVE, SE RECUPERA.
                #
                # El panel lo devuelve al cerrarse, y lo hace en un "finally",
                # asi que se devuelve tambien si revienta. Pero si lo matan de
                # golpe (kill -9) no llega a escribir nada, y sin esto el
                # mapeador se quedaria sin mando el resto de la partida. El
                # tope del panel es de 120 s de inactividad: con 180 s no se le
                # quita a nadie que lo este usando.
                if (_mando_cedido
                        and _tiempo.monotonic() - _mando_desde[0] > 180.0):
                    print("[keys] el panel no ha devuelto el mando en 180 s:"
                          " se recupera", flush=True)
                    for _d in list(_mando_cedido):
                        try:
                            _d.grab()
                            _capturados.append(_d)
                        except Exception:
                            pass
                    del _mando_cedido[:]
                    _resincronizar_botones(_capturados,
                                           "mando recuperado por tiempo")
                try:
                    if os.path.exists(_mando_marca):
                        with open(_mando_marca) as _fh:
                            _orden = _fh.read().strip().lower()
                        os.remove(_mando_marca)
                        if _orden == 'suelta':
                            # Se apunta ANTES de soltar: si el ungrab falla en
                            # uno de los dos mandos, el otro ya esta suelto y
                            # hay que recordar que se le debe al mapeador.
                            for _d in list(_capturados):
                                _mando_cedido.append(_d)
                                try:
                                    _d.ungrab()
                                except Exception:
                                    pass
                            del _capturados[:]
                            _mando_desde[0] = _tiempo.monotonic()
                            _olvidar_botones("el panel se lleva el mando")
                            if _mando_cedido:
                                print("[keys] mando cedido al panel de WProton"
                                      " (%d)" % len(_mando_cedido), flush=True)
                            else:
                                print("[keys] el panel pidio el mando y aqui no"
                                      " estaba capturado: no hay nada que"
                                      " ceder", flush=True)
                        elif _orden == 'coge':
                            for _d in list(_mando_cedido):
                                try:
                                    _d.grab()
                                    _capturados.append(_d)
                                except Exception as _e2:
                                    print("[keys] no se pudo recuperar %s: %s"
                                          % (_d.path, _e2), flush=True)
                            if _mando_cedido:
                                print("[keys] mando recuperado del panel (%d de"
                                      " %d)" % (len(_capturados),
                                                len(_mando_cedido)), flush=True)
                            del _mando_cedido[:]
                            _resincronizar_botones(_capturados,
                                                   "mando recuperado")
                        else:
                            print("[keys] el panel pidio '%s' con el mando y no"
                                  " se reconoce" % _orden, flush=True)
                except OSError as _e:
                    print("[keys] no se pudo atender el mando del panel: %s"
                          % _e, flush=True)
            for _dev in r:
                try:
                    for event in _dev.read():

                        # ── Botones digitales ────────────────────────────────
                        if event.type == ecodes.EV_KEY:
                            if event.value == 1:
                                pulsados.add(event.code)
                            elif event.value == 0:
                                pulsados.discard(event.code)

                            # EL MENU DE WPROTON, cuando el mando lo tenemos
                            # capturado nosotros y el guardian no oye nada.
                            #
                            # No se abre desde aqui: se deja una marca y el
                            # guardian -que es quien sabe pintar el panel- la
                            # ve en su siguiente vuelta. Con un tiempo muerto
                            # de dos segundos, porque mientras el panel esta
                            # abierto los botones siguen llegando aqui y
                            # pedirlo otra vez seria pedirlo cien veces.
                            if (_ov_req and _ov_marca and event.value == 1
                                    and all(_b in pulsados for _b in _ov_req)):
                                import time as _t3
                                if _t3.time() - _ov_ultimo[0] > 2.0:
                                    _ov_ultimo[0] = _t3.time()
                                    try:
                                        with open(_ov_marca, 'w') as _fh:
                                            _fh.write('abrir')
                                        print("[keys] combinacion del menu: se"
                                              " le pide al guardian que abra"
                                              " el panel", flush=True)
                                    except OSError as _e:
                                        print("[keys] no se pudo pedir el menu:"
                                              " %s" % _e, flush=True)

                            # Combos → teclado / acciones especiales
                            for c in map_combos:
                                all_pressed = all(btn in pulsados for btn in c["req"])
                                if all_pressed and not c["active"] and event.value == 1:
                                    c["active"] = True
                                    if c.get("txt"):
                                        escribir_texto(ui, _texto_rapido)
                                        for _b in c["req"]: pendiente.discard(_b)
                                        pulsados.clear()
                                    elif c.get("kb"):
                                        ui.syn()
                                        try: launch_teclado_virtual(pads, ids, ui)
                                        except Exception as _e: print(f"[!] {_e}")
                                        for _b in c["req"]: pendiente.discard(_b)
                                        pulsados.clear()
                                    else:
                                        # dejar constancia: sin esto no habia
                                        # forma de saber si una combinacion
                                        # habia disparado o no
                                        print("[combo] %s -> %s" % (c["req"], c["outs"]),
                                              flush=True)
                                        # La combinacion manda:
                                        #  - lo que estuviera esperando a
                                        #    soltarse se descarta
                                        #  - y lo que YA se hubiera mandado se
                                        #    suelta, para no dejar una tecla
                                        #    pegada mientras se sale del juego
                                        #    (pasa al pulsar start antes que
                                        #    el hotkey: su ENTER ya salio)
                                        for _b in c["req"]:
                                            pendiente.discard(_b)
                                            for _t in map_normal.get(_b, []):
                                                _tecla(_t, False)
                                        for t in c["outs"]: _tecla(t, True)
                                elif c["active"] and not all_pressed and event.value == 0:
                                    c["active"] = False
                                    if not c.get("kb"):
                                        for t in c["outs"]: _tecla(t, False)

                            # Boton individual -> teclado.
                            #
                            # Si el boton ADEMAS forma parte de alguna
                            # combinacion, su tecla NO se manda al pulsar: se
                            # espera a soltarlo, y solo se manda si mientras
                            # tanto no disparo ninguna combinacion.
                            #
                            # Sin esto, un .keys con "select -> ESC" y la
                            # combinacion hotkey+start (que WProton pone
                            # siempre, y donde hotkey ES select) mandaba un
                            # ESC cada vez que se usaba Select+Start: el juego
                            # recibia el ESC antes de que la combinacion
                            # llegara a formarse. En un juego de coches eso
                            # abria el menu de pausa al intentar salir.
                            # Peor todavia: mantener Select para cerrar el
                            # juego (la guardia de 2 segundos) dejaba el ESC
                            # pulsado todo ese rato.
                            # SALIDA DE EMERGENCIA: hotkey mantenido 2 s.
                            #
                            # Solo cuando tenemos el mando capturado y el
                            # .keys no trae combinacion de salida: entonces el
                            # guardian no recibe nada y esta es la unica forma
                            # de cerrar el juego.
                            if _capturados and not _tiene_salida and _hot \
                               and event.code == _hot and _salida_marca:
                                import time as _t2
                                if event.value == 1:
                                    _hot_desde[0] = _t2.time()
                                elif event.value == 0:
                                    _hot_desde[0] = 0.0
                            if _capturados and not _tiene_salida and _hot_desde[0] \
                               and _salida_marca:
                                import time as _t2
                                if _t2.time() - _hot_desde[0] > _salida_seg:
                                    _hot_desde[0] = 0.0
                                    try:
                                        with open(_salida_marca, 'w') as _fh:
                                            _fh.write('salir')
                                        print("[keys] Select mantenido: se pide"
                                              " cerrar el juego", flush=True)
                                    except OSError as _e:
                                        print("[keys] No se pudo pedir el cierre:"
                                              " %s" % _e, flush=True)
                            in_active_combo = any(
                                event.code in c["req"] and c["active"] for c in map_combos
                            )
                            # Si se pulsa un boton que sale en una combinacion
                            # pero esta no llega a formarse, se dice UNA vez:
                            # es la pista de que se esta pulsando el boton
                            # equivocado.
                            if event.value == 1 and event.code in btn_en_combo \
                               and not in_active_combo:
                                for _c in map_combos:
                                    if event.code not in _c["req"]:
                                        continue
                                    _falta = [b for b in _c["req"]
                                              if b != event.code and b not in pulsados]
                                    if _falta and tuple(_c["req"]) not in _avisos_combo:
                                        _avisos_combo.add(tuple(_c["req"]))
                                        print("[keys] La combinacion %s espera "
                                              "tambien %s (aun sin pulsar)"
                                              % (_c["req"], _falta), flush=True)
                            if event.code in map_normal and not in_active_combo:
                                if event.code not in btn_en_combo:
                                    for t in map_normal[event.code]:
                                        _tecla(t, event.value == 1)
                                elif event.value == 1:
                                    # se apunta y se decide al soltar
                                    pendiente.add(event.code)
                                elif event.value == 0 and event.code in pendiente:
                                    pendiente.discard(event.code)
                                    # LA TECLA SE MANTIENE PULSADA UN RATO, NO
                                    # SE PULSA Y SE SUELTA SEGUIDO.
                                    #
                                    # ESTE ERA EL FALLO DE "LO MAPEO Y NO
                                    # FUNCIONA". Aqui se mandaba el pulsar y
                                    # el soltar con microsegundos de por medio,
                                    # y un juego que mira el teclado una vez
                                    # por fotograma (16 ms a 60 FPS) no ve
                                    # nada. Es el MISMO fallo que ya estaba
                                    # arreglado en escribir_texto, con su
                                    # mismo comentario: "por eso mapear una
                                    # tecla a un boton SI funcionaba: la
                                    # mantiene el usuario".
                                    #
                                    # Y por este camino NO la mantiene el
                                    # usuario. Por aqui pasa todo boton que
                                    # ADEMAS forme parte de una combinacion...
                                    # o sea Select y Start SIEMPRE, porque
                                    # WProton pone la combinacion hotkey+start
                                    # en todos los juegos y hotkey ES Select.
                                    # Resultado: mapear Select a una tecla no
                                    # funcionaba en juegos antiguos. Lo conto
                                    # un tester con El Torrente, que necesita
                                    # el tabulador.
                                    #
                                    # NO SE DUERME EL BUCLE: se apunta cuando
                                    # hay que soltarla y sigue leyendo el
                                    # mando. Dormir 60 ms aqui dejaria sordo al
                                    # mapeador justo mientras alguien juega.
                                    for t in map_normal[event.code]:
                                        _tecla(t, True)
                                    ui.syn()
                                    _soltar_luego.append(
                                        (_tiempo.monotonic() + _HOLD_MS / 1000.0,
                                         list(map_normal[event.code])))
                            elif event.value == 0:
                                pendiente.discard(event.code)

                            # Click digital (PS4, bumpers, botones)
                            if ui_mouse and event.code in _mclicks:
                                ui_mouse.write(ecodes.EV_KEY, _mclicks[event.code],
                                               event.value)
                                ui_mouse.syn()
                                # Igual que el analogico: que se vea en el
                                # registro si el clic llego a salir.
                                print("[keys] Raton: %s %s (boton %d del mando)"
                                      % (_RATON_NOMBRE.get(_mclicks[event.code],
                                                           _mclicks[event.code]),
                                         "PULSADO" if event.value else "soltado",
                                         event.code), flush=True)
                            ui.syn()

                        # ── Ejes analógicos ──────────────────────────────────
                        elif event.type == ecodes.EV_ABS:
                            if event.code in (_mabs_x, _mabs_y):
                                # EL CENTRO Y LA ZONA MUERTA, PREGUNTANDOSELOS
                                # AL MANDO, UNA VEZ POR EJE.
                                #
                                # Lo de antes era una zona muerta fija del 12%
                                # sobre un centro supuesto. Y en el registro
                                # del modo Juego de Dani el puntero acababa
                                # SIEMPRE en (1279, 799) -la esquina de abajo
                                # a la derecha de 1280x800- y ahi se quedaba:
                                # la firma exacta de un stick que no reposa en
                                # cero. Con el 12% fijo, cualquier mando que
                                # descanse por encima empuja el puntero a una
                                # esquina y ya no hay forma de apuntar a nada.
                                #
                                # Las direcciones ya se calculaban asi desde
                                # hace tiempo ("Umbral de ABS_RX: 11468, el
                                # perfil decia 16000"); el raton se habia
                                # quedado atras.
                                if event.code not in _mabs_info:
                                    _c, _rec, _flat = center, 32767, None
                                    try:
                                        _ai = _dev.absinfo(event.code)
                                        _rec = max(abs(_ai.max - center),
                                                   abs(center - _ai.min)) or 32767
                                        _flat = _ai.flat
                                    except Exception:
                                        pass
                                    # flat es la zona muerta QUE DECLARA EL
                                    # MANDO. Por tres, que es lo que ya se hace
                                    # con las direcciones, y nunca por debajo
                                    # del 12% de siempre.
                                    _dz = max((_flat or 0) * 3, (_rec * 12) // 100)
                                    # Y EL REPOSO DE VERDAD: el primer valor
                                    # que manda el eje. Al arrancar el juego
                                    # nadie esta tocando el stick, asi que ese
                                    # es su cero aunque el mando diga otra cosa.
                                    # Solo se acepta si cae dentro de media
                                    # carrera: si alguien tuviera el stick a
                                    # fondo justo al arrancar, no se le toma
                                    # eso por centro.
                                    if abs(event.value - center) < _rec // 2:
                                        _c = event.value
                                    _mabs_info[event.code] = (_c, _rec, _dz)
                                    print("[keys] Raton %s: reposo %d, "
                                          "recorrido %d, zona muerta %d "
                                          "(el mando declara flat=%s)"
                                          % (ecodes.ABS.get(event.code, event.code),
                                             _c, _rec, _dz,
                                             _flat if _flat is not None else '?'),
                                          flush=True)
                                if event.code == _mabs_x: _msx = event.value
                                else: _msy = event.value
                            # Click analógico: R2/L2 Xbox 360 mandan ABS_RZ/ABS_Z
                            elif ui_mouse and event.code in _mclicks_abs:
                                _btn = _mclicks_abs[event.code]
                                # EL UMBRAL DEL GATILLO, TAMBIEN DEL MANDO.
                                #
                                # Era "> 64" a pelo, que da el 25% en un
                                # gatillo de 0-255. En uno de 0-32767 eso es
                                # practicamente cero: el boton se quedaria
                                # pulsado solo, y con el clic izquierdo
                                # enganchado no se puede pulsar nada.
                                _u = _mclick_umbral.get(event.code)
                                if _u is None:
                                    _u = 64
                                    try:
                                        _ai = _dev.absinfo(event.code)
                                        _u = _ai.min + (abs(_ai.max - _ai.min) * 25) // 100
                                    except Exception:
                                        pass
                                    _mclick_umbral[event.code] = _u
                                    print("[keys] Clic con %s: se pulsa por "
                                          "encima de %d"
                                          % (ecodes.ABS.get(event.code, event.code), _u),
                                          flush=True)
                                _now_pressed = event.value > _u
                                if _now_pressed != _mclick_pressed.get(_btn, False):
                                    _mclick_pressed[_btn] = _now_pressed
                                    ui_mouse.write(ecodes.EV_KEY, _btn,
                                                   1 if _now_pressed else 0)
                                    ui_mouse.syn()
                                    # SE APUNTA CADA CLIC. En el registro del
                                    # 17/10 no habia ni una linea de clic, y
                                    # por eso no se pudo saber si el boton
                                    # llegaba a pulsarse o no.
                                    print("[keys] Raton: %s %s (%s = %d)"
                                          % (_RATON_NOMBRE.get(_btn, _btn),
                                             "PULSADO" if _now_pressed else "soltado",
                                             ecodes.ABS.get(event.code, event.code),
                                             event.value), flush=True)
                            # Los gatillos YA NO tienen camino propio: van
                            # por la tabla de direcciones de aqui abajo, como
                            # en Batocera. Solo queda la traza, para saber que
                            # el eje llega y con que umbral se le mide.
                            if event.code in _gatillo_teclas \
                                    and event.code not in _gatillo_visto:
                                _gatillo_visto.add(event.code)
                                print("[keys] Llega %s (valor %d)"
                                      % (ecodes.ABS.get(event.code, event.code),
                                         event.value), flush=True)

                            # Mapeo de dirección → teclado. EL UNICO camino:
                            # sticks, cruceta y gatillos pasan por aqui.
                            if event.code in abs_dirs:
                                neg_dir, pos_dir = abs_dirs[event.code]
                                # La CRUCETA no es analogica: solo manda -1, 0
                                # o +1. Compararla con el umbral de los sticks
                                # (16000, para no detectar el roce) hacia que
                                # no se activara NUNCA. Para los ejes de
                                # cruceta el centro es 0 y basta con el signo.
                                if event.code in (ecodes.ABS_HAT0X, ecodes.ABS_HAT0Y,
                                                  ecodes.ABS_HAT1X, ecodes.ABS_HAT1Y,
                                                  ecodes.ABS_HAT2X, ecodes.ABS_HAT2Y):
                                    val = event.value
                                    neg_active = val < 0
                                    pos_active = val > 0
                                    _u = 0
                                else:
                                    # El umbral se le pregunta AL MANDO, no se
                                    # da por hecho.
                                    #
                                    # El del perfil es un numero fijo (16000)
                                    # que supone un recorrido de 32767. Con un
                                    # mando de 0-255 eso no se alcanza jamas, y
                                    # aun acertando el recorrido salen casi 49%:
                                    # habia que mover el stick hasta media
                                    # carrera para que respondiera. Los gatillos
                                    # ya se calculaban asi desde hace tiempo;
                                    # los sticks se habian quedado atras.
                                    _u = _eje_umbral.get(event.code)
                                    if _u is None:
                                        _u = threshold
                                        try:
                                            _ai = _dev.absinfo(event.code)
                                            _c = center
                                            if event.code in _gatillo_teclas:
                                                # un gatillo reposa en su MINIMO
                                                # y se aprieta hacia el maximo
                                                _c = _ai.min
                                                _eje_centro[event.code] = _c
                                            _recorrido = max(abs(_ai.max - _c),
                                                             abs(_c - _ai.min))
                                            if _recorrido > 0:
                                                # 35% del recorrido, y nunca por
                                                # debajo del triple de la zona
                                                # muerta que declara el mando
                                                _pc = 25 if event.code in _gatillo_teclas else 35
                                                _u = max(_ai.flat * 3,
                                                         (_recorrido * _pc) // 100)
                                        except Exception:
                                            pass
                                        _eje_umbral[event.code] = _u
                                        print("[keys] Umbral de %s: %d "
                                              "(el perfil decia %d)"
                                              % (ecodes.ABS.get(event.code,
                                                                event.code),
                                                 _u, threshold), flush=True)
                                    _c = _eje_centro.get(event.code, center)
                                    val = event.value - _c
                                    neg_active = val < -_u
                                    pos_active = val > _u
                                for direction, active in ((neg_dir, neg_active),
                                                          (pos_dir, pos_active)):
                                    # un gatillo solo tiene sentido positivo:
                                    # su lado negativo va a None y se salta
                                    if direction is None:
                                        continue
                                    if active != ejes_on.get(direction, False):
                                        ejes_on[direction] = active
                                        # La primera vez que cada direccion se
                                        # enciende y la primera que se apaga.
                                        # Sin esto no se ve si una direccion se
                                        # queda COLGADA: un stick que no suelta
                                        # deja la tecla pulsada para siempre y
                                        # cualquier otro control que use esa
                                        # misma tecla parece muerto.
                                        _marca = (direction, active)
                                        if _marca not in _dir_vista:
                                            _dir_vista.add(_marca)
                                            print("[keys] %s %s (%s = %d, umbral %d)"
                                                  % (direction,
                                                     "ON " if active else "OFF",
                                                     ecodes.ABS.get(event.code,
                                                                    event.code),
                                                     event.value, _u),
                                                  flush=True)
                                        for t in dirs_teclas[direction]:
                                            _tecla(t, active)
                                            # LOS GATILLOS, TRAZADOS SIEMPRE.
                                            #
                                            # El resto de direcciones solo se
                                            # traza la primera vez, para no
                                            # inundar el registro. Pero con los
                                            # gatillos llevamos dos juegos sin
                                            # saber si la tecla llega a salir o
                                            # no, y sin ese dato no se puede
                                            # arreglar nada. Se limita a 20
                                            # apuntes para no pasarse.
                                            if direction in ("__l2", "__r2") \
                                               and _gat_trazas[0] < 20:
                                                _gat_trazas[0] += 1
                                                print("[keys] %s -> %s %s "
                                                      "(la tienen %d control(es))"
                                                      % (direction,
                                                         nombre_ev(t),
                                                         "PULSAR" if active else "soltar",
                                                         _ref.get(t, 0)),
                                                      flush=True)

                            ui.syn()

                except (IOError, OSError):
                    # Ese mando ha desaparecido (desconectado o dormido). Se
                    # descarta ESE y se sigue con el resto: antes un fallo de
                    # un mando tumbaba el mapeador entero.
                    print("[-] Mando desconectado: %s" % _dev.name, flush=True)
                    try:
                        pads.remove(_dev)
                    except ValueError:
                        pass
                    if not pads:
                        print("[-] Sin mandos: el mapeador termina", flush=True)
                        _soltar_mandos()
                        return
                    break
            if ui_mouse:
                _n=_tm.monotonic(); _dt=min(_n-_mlast,0.05); _mlast=_n
                _rx=_raton_fraccion(_msx, _mabs_info.get(_mabs_x), center)
                _ry=_raton_fraccion(_msy, _mabs_info.get(_mabs_y), center)
                _macc_x+=_rx*_mspeed*_dt; _macc_y+=_ry*_mspeed*_dt
                _ix=int(_macc_x); _iy=int(_macc_y)
                if _ix: ui_mouse.write(ecodes.EV_REL,ecodes.REL_X,_ix); _macc_x-=_ix
                if _iy: ui_mouse.write(ecodes.EV_REL,ecodes.REL_Y,_iy); _macc_y-=_iy
                if _ix or _iy:
                    ui_mouse.syn()
                    # EL PUNTERO, EN EL REGISTRO.
                    #
                    # Del caso de Dani solo se sabia que el puntero acababa
                    # en la esquina; no POR QUE. Con esto el registro dice
                    # cuanto se mueve y con que valores crudos del stick, asi
                    # que un mando que no reposa en cero se ve a la primera.
                    # Una linea cada dos segundos: ni una por evento.
                    _mpx += _ix; _mpy += _iy
                    if _n - _mlog >= 2.0:
                        print("[keys] Raton: %+d,%+d px en %.1f s "
                              "(stick en %d,%d; reposo %s,%s)"
                              % (_mpx, _mpy, _n - _mlog, _msx, _msy,
                                 _mabs_info.get(_mabs_x, ('?',))[0],
                                 _mabs_info.get(_mabs_y, ('?',))[0]),
                              flush=True)
                        _mlog = _n; _mpx = 0; _mpy = 0
    finally:
        if ui_mouse:
            try: ui_mouse.close()
            except: pass

if __name__ == "__main__":
    main()

