# -*- coding: utf-8 -*-
# WProton - andamio comun de las pruebas de Python
#
# Copyright (C) 2026  stshunz y colaboradores. GPL v3 o posterior.
# ----------------------------------------------------------------------------
# Las mismas afirmaciones que comun.sh, para que las dos mitades del proyecto
# se prueben igual y la salida se lea igual.
#
# Y UN evdev DE MENTIRA.
#
# mapeador.py y mando_virtual.py importan evdev, que es una libreria del
# sistema con acceso a /dev/input. Para probar el reparto de ejes o la eleccion
# de perfil NO hace falta un mando: hace falta que las constantes valgan lo que
# valen en Linux.
#
# Asi que aqui hay un evdev falso con los codigos DE VERDAD (los de
# input-event-codes.h). Si se inventaran, una prueba podria pasar con el
# reparto de ejes equivocado, que es justo el fallo que se busca.
# ----------------------------------------------------------------------------
import os
import sys
import types

_ok = 0
_fallos = 0


# ---------------------------------------------------------------------------
# evdev falso
# ---------------------------------------------------------------------------
# Codigos reales de linux/input-event-codes.h. Solo los que se usan.
_ABS = {
    'ABS_X': 0, 'ABS_Y': 1, 'ABS_Z': 2,
    'ABS_RX': 3, 'ABS_RY': 4, 'ABS_RZ': 5,
    'ABS_HAT0X': 16, 'ABS_HAT0Y': 17,
    'ABS_HAT1X': 18, 'ABS_HAT1Y': 19,
    'ABS_HAT2X': 20, 'ABS_HAT2Y': 21,
}
_BTN = {
    'BTN_A': 304, 'BTN_SOUTH': 304, 'BTN_B': 305, 'BTN_EAST': 305,
    'BTN_C': 306, 'BTN_X': 307, 'BTN_NORTH': 307, 'BTN_Y': 308,
    'BTN_WEST': 308, 'BTN_Z': 309, 'BTN_TL': 310, 'BTN_TR': 311,
    'BTN_TL2': 312, 'BTN_TR2': 313, 'BTN_SELECT': 314, 'BTN_START': 315,
    'BTN_MODE': 316, 'BTN_THUMBL': 317, 'BTN_THUMBR': 318,
    'BTN_DPAD_UP': 544, 'BTN_DPAD_DOWN': 545,
    'BTN_DPAD_LEFT': 546, 'BTN_DPAD_RIGHT': 547,
    'BTN_LEFT': 272, 'BTN_RIGHT': 273, 'BTN_MIDDLE': 274,
    # Los cuatro botones extra que declara el mando virtual. Son los codigos
    # de verdad (0x2c0 y siguientes), no unos inventados.
    'BTN_TRIGGER_HAPPY1': 704, 'BTN_TRIGGER_HAPPY2': 705,
    'BTN_TRIGGER_HAPPY3': 706, 'BTN_TRIGGER_HAPPY4': 707,
}
_EV = {'EV_KEY': 1, 'EV_ABS': 3, 'EV_REL': 2, 'EV_SYN': 0}
_REL = {'REL_X': 0, 'REL_Y': 1, 'REL_WHEEL': 8, 'REL_HWHEEL': 6}

# Teclas: los codigos reales de las que se nombran por su valor en algun sitio,
# y un reparto estable para el resto. Lo que importa es que dos nombres
# distintos NO valgan lo mismo.
_KEY = {
    'KEY_ESC': 1, 'KEY_1': 2, 'KEY_2': 3, 'KEY_3': 4, 'KEY_4': 5,
    'KEY_5': 6, 'KEY_6': 7, 'KEY_7': 8, 'KEY_8': 9, 'KEY_9': 10,
    'KEY_0': 11, 'KEY_MINUS': 12, 'KEY_EQUAL': 13, 'KEY_BACKSPACE': 14,
    'KEY_TAB': 15, 'KEY_Q': 16, 'KEY_W': 17, 'KEY_E': 18, 'KEY_R': 19,
    'KEY_T': 20, 'KEY_Y': 21, 'KEY_U': 22, 'KEY_I': 23, 'KEY_O': 24,
    'KEY_P': 25, 'KEY_ENTER': 28, 'KEY_LEFTCTRL': 29, 'KEY_A': 30,
    'KEY_S': 31, 'KEY_D': 32, 'KEY_F': 33, 'KEY_G': 34, 'KEY_H': 35,
    'KEY_J': 36, 'KEY_K': 37, 'KEY_L': 38, 'KEY_SEMICOLON': 39,
    'KEY_APOSTROPHE': 40, 'KEY_LEFTSHIFT': 42, 'KEY_BACKSLASH': 43,
    'KEY_Z': 44, 'KEY_X': 45, 'KEY_C': 46, 'KEY_V': 47, 'KEY_B': 48,
    'KEY_N': 49, 'KEY_M': 50, 'KEY_COMMA': 51, 'KEY_DOT': 52,
    'KEY_SLASH': 53, 'KEY_RIGHTSHIFT': 54, 'KEY_LEFTALT': 56,
    'KEY_SPACE': 57, 'KEY_F1': 59, 'KEY_F2': 60, 'KEY_F3': 61,
    'KEY_F4': 62, 'KEY_F5': 63, 'KEY_F6': 64, 'KEY_F7': 65, 'KEY_F8': 66,
    'KEY_F9': 67, 'KEY_F10': 68, 'KEY_UP': 103, 'KEY_LEFT': 105,
    'KEY_RIGHT': 106, 'KEY_DOWN': 108, 'KEY_PAGEUP': 104,
    'KEY_PAGEDOWN': 109, 'KEY_HOME': 102, 'KEY_END': 107,
    'KEY_INSERT': 110, 'KEY_DELETE': 111, 'KEY_LEFTMETA': 125,
    'KEY_KPENTER': 96, 'KEY_KPMINUS': 74, 'KEY_KPPLUS': 78,
}


def _instalar_evdev_falso():
    """Pone un evdev de mentira en sys.modules, si no esta el de verdad."""
    try:
        import evdev  # noqa: F401
        return False                      # hay uno de verdad: se usa ese
    except ImportError:
        pass

    ecodes = types.ModuleType('evdev.ecodes')
    for d in (_ABS, _BTN, _EV, _REL, _KEY):
        for k, v in d.items():
            setattr(ecodes, k, v)
    # Los dos diccionarios inversos que usa evdev de verdad.
    ecodes.KEY = dict((v, k) for k, v in _KEY.items())
    ecodes.BTN = dict((v, k) for k, v in _BTN.items())
    ecodes.ABS = dict((v, k) for k, v in _ABS.items())
    ecodes.bytype = {}

    evdev = types.ModuleType('evdev')
    evdev.ecodes = ecodes

    class InputDevice(object):
        def __init__(self, *a, **k):
            raise RuntimeError('evdev falso: no hay mandos en una prueba')

    class UInput(object):
        """Recoge lo que se le escribe, para poder comprobarlo."""
        def __init__(self, *a, **k):
            self.eventos = []

        def write(self, tipo, codigo, valor):
            self.eventos.append((tipo, codigo, valor))

        def syn(self):
            pass

        def close(self):
            pass

    evdev.InputDevice = InputDevice
    evdev.UInput = UInput

    class AbsInfo(object):
        """Lo que evdev usa para declarar el rango de un eje."""
        def __init__(self, value=0, min=0, max=0, fuzz=0, flat=0,
                     resolution=0):
            self.value, self.min, self.max = value, min, max
            self.fuzz, self.flat, self.resolution = fuzz, flat, resolution

        def __repr__(self):
            return 'AbsInfo(min=%r, max=%r)' % (self.min, self.max)

    evdev.AbsInfo = AbsInfo
    evdev.categorize = lambda e: e
    evdev.list_devices = lambda: []
    evdev.util = types.ModuleType('evdev.util')

    sys.modules['evdev'] = evdev
    sys.modules['evdev.ecodes'] = ecodes
    sys.modules['evdev.util'] = evdev.util
    return True


EVDEV_ES_FALSO = _instalar_evdev_falso()

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
# WP_SRC es el equivalente de WP_FUENTE en comun.sh: apunta las pruebas a otra
# copia de src/. Sirve para comprobar que una prueba FALLA cuando el codigo se
# rompe, que es la unica forma de saber que prueba algo.
SRC = os.environ.get('WP_SRC') or os.path.join(RAIZ, 'src')
if SRC not in sys.path:
    sys.path.insert(0, SRC)


# ---------------------------------------------------------------------------
# Afirmaciones (las mismas que comun.sh)
# ---------------------------------------------------------------------------
def _bien(que):
    global _ok
    _ok += 1
    print('  ok    %s' % que)


def _mal(que, detalle=''):
    global _fallos
    _fallos += 1
    print('  FALLA %s' % que)
    if detalle:
        print('        %s' % detalle)


def afirmar_igual(obtenido, esperado, que):
    if obtenido == esperado:
        _bien(que)
    else:
        _mal(que, 'esperaba [%r] y ha salido [%r]' % (esperado, obtenido))


def afirmar_distinto(a, b, que):
    if a != b:
        _bien(que)
    else:
        _mal(que, 'no deberia ser [%r]' % (b,))


def afirmar_cierto(cond, que, detalle=''):
    if cond:
        _bien(que)
    else:
        _mal(que, detalle)


def afirmar_falso(cond, que, detalle=''):
    afirmar_cierto(not cond, que, detalle)


def afirmar_contiene(texto, trozo, que):
    if trozo in texto:
        _bien(que)
    else:
        _mal(que, 'no aparece [%s]' % trozo)


def afirmar_no_contiene(texto, trozo, que):
    if trozo in texto:
        _mal(que, 'no deberia aparecer [%s]' % trozo)
    else:
        _bien(que)


def titulo(t):
    print('\n== %s ==' % t)


def resumen(nombre):
    print('\n%s: %d bien, %d mal' % (nombre, _ok, _fallos))
    return 0 if _fallos == 0 else 1
