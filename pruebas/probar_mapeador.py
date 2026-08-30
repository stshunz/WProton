#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# Prueba: perfiles de mando y reparto de ejes del mapeador.
#
# Copyright (C) 2026  stshunz y colaboradores. GPL v3 o posterior.
# ----------------------------------------------------------------------------
# POR QUE ESTA PRUEBA
#
# Lo que sabe el proyecto sobre mandos ha costado muchas horas, y casi todo
# vive en dos diccionarios y una funcion de tres lineas. Son fragiles: un
# nombre añadido a la lista de otro perfil, y la Deck deja de casar con el
# suyo sin que nadie se entere hasta que un tester dice que la cruceta hace
# cosas raras.
#
# Lo que se sujeta aqui:
#
#   - La Deck con el driver hid-steam se llama "Steam Deck" y NO es un mando
#     estandar: HAT0 es el TOUCHPAD IZQUIERDO, no la cruceta. Dejarlo como
#     cruceta hacia que rozar el touchpad disparara las teclas.
#   - En modo Juego, cuando el mando lo crea Steam, se llama "Microsoft X-Box
#     360 pad N" y SI es estandar: ahi HAT0 es la cruceta de verdad.
#   - Los mandos de Nintendo llevan A y B cambiados.
#
# LO QUE NO SE PRUEBA AQUI, Y POR QUE
#
# La lectura del .keys vive dentro del bucle que atiende al mando, y sin un
# mando de verdad no se llega. Sacarla a una funcion aparte solo para poder
# probarla seria cambiar el entregable para que quepan las pruebas, y eso no
# se hace. Lo que si se comprueba, abajo, es que el fichero NO ejecuta nada.
# ----------------------------------------------------------------------------
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from comun import (afirmar_igual, afirmar_cierto, afirmar_falso,  # noqa: E402
                   afirmar_contiene, afirmar_no_contiene, titulo, resumen,
                   SRC)

import mapeador                                                   # noqa: E402
from evdev import ecodes                                          # noqa: E402


titulo("Cada mando cae en su perfil")

casos = [
    ("Steam Deck",                      "STEAM_DECK"),
    ("Valve Software Steam Controller", "STEAM_DECK"),
    ("Microsoft X-Box 360 pad",         "XBOX_360"),
    ("Microsoft X-Box 360 pad 0",       "XBOX_360"),
    ("Sony Interactive Entertainment Wireless Controller", "SONY_DS4"),
    ("Sony Interactive Entertainment DualSense Wireless Controller",
     "SONY_DS4"),
    ("Nintendo Switch Pro Controller",  "NINTENDO_SWITCH"),
    ("8BitDo Pro 2",                    "8BITDO"),
    ("Un mando cualquiera",             "GENERIC"),
]
for nombre, esperado in casos:
    p = mapeador.get_perfil(nombre)
    cual = [k for k, v in mapeador.PERFILES.items() if v is p]
    afirmar_igual(cual[0] if cual else "?", esperado,
                  "'%s' -> %s" % (nombre, esperado))

titulo("El nombre no distingue mayusculas")

afirmar_igual(mapeador.get_perfil("STEAM DECK"),
              mapeador.get_perfil("steam deck"),
              "'STEAM DECK' y 'steam deck' dan el mismo perfil")

titulo("La cruceta llega de DOS formas, segun el mando")

deck = mapeador.PERFILES["STEAM_DECK"]["abs_map"]
x360 = mapeador.PERFILES["XBOX_360"]["abs_map"]

# En un mando estandar la cruceta es un eje: ABS_HAT0.
afirmar_igual(x360.get(ecodes.ABS_HAT0Y), ("up", "down"),
              "en un mando estandar, HAT0Y es arriba/abajo de la cruceta")
afirmar_igual(x360.get(ecodes.ABS_HAT0X), ("left", "right"),
              "y HAT0X es izquierda/derecha")

# En la Deck NO: ahi HAT0 es el touchpad izquierdo, y la cruceta son botones.
afirmar_falso(ecodes.ABS_HAT0X in deck,
              "en la Deck, HAT0X NO es la cruceta (es el touchpad)")
afirmar_falso(ecodes.ABS_HAT0Y in deck,
              "en la Deck, HAT0Y tampoco")
afirmar_falso(ecodes.ABS_HAT1X in deck or ecodes.ABS_HAT2Y in deck,
              "ni el touchpad derecho ni los gatillos entran como ejes")

titulo("Los sticks se reparten igual en los dos")

for eje, nombre in ((ecodes.ABS_X, "izquierdo horizontal"),
                    (ecodes.ABS_Y, "izquierdo vertical"),
                    (ecodes.ABS_RX, "derecho horizontal"),
                    (ecodes.ABS_RY, "derecho vertical")):
    afirmar_igual(deck.get(eje), x360.get(eje),
                  "el stick %s se lee igual en la Deck y en un estandar"
                  % nombre)

titulo("Los mandos de Nintendo llevan A y B cambiados")

sw = mapeador.PERFILES["NINTENDO_SWITCH"]["ids"]
xb = mapeador.PERFILES["XBOX_360"]["ids"]
afirmar_igual(sw["a"], xb["b"], "la A de Switch es la B de Xbox")
afirmar_igual(sw["b"], xb["a"], "y al reves")

titulo("Todos los perfiles estan completos")

# Si a un perfil le falta una tecla, el .keys que la use muere con KeyError
# nada mas arrancar y el juego se queda SIN NINGUN boton.
esperadas = ("a", "b", "x", "y", "start", "select", "hotkey",
             "pageup", "pagedown", "l2", "r2", "l3", "r3")
for nombre, p in mapeador.PERFILES.items():
    faltan = [k for k in esperadas if k not in p["ids"]]
    afirmar_igual(faltan, [], "%s tiene todos los botones" % nombre)
    afirmar_cierto("abs_map" in p and "threshold" in p and "center" in p,
                   "%s tiene ejes, umbral y centro" % nombre)

titulo("Cada perfil manda dos botones distintos a cada sitio")

for nombre, p in mapeador.PERFILES.items():
    ids = p["ids"]
    # hotkey y select comparten codigo a proposito en todos los perfiles.
    sin_hotkey = dict((k, v) for k, v in ids.items() if k != "hotkey")
    repes = len(sin_hotkey) - len(set(sin_hotkey.values()))
    afirmar_igual(repes, 0,
                  "%s no repite el mismo codigo en dos botones" % nombre)
    afirmar_igual(ids["hotkey"], ids["select"],
                  "%s: el hotkey es el select" % nombre)

titulo("Escribir texto")

t = mapeador.teclas_de_texto("abc")
afirmar_cierto(ecodes.KEY_A in t and ecodes.KEY_B in t and ecodes.KEY_C in t,
               "las minusculas salen como su tecla")
afirmar_falso(ecodes.KEY_LEFTSHIFT in t, "y sin shift")

t = mapeador.teclas_de_texto("A")
afirmar_cierto(ecodes.KEY_LEFTSHIFT in t, "una mayuscula pide shift")

t = mapeador.teclas_de_texto("a b")
afirmar_cierto(ecodes.KEY_SPACE in t, "el espacio tiene su tecla")

t = mapeador.teclas_de_texto("añ€")
afirmar_cierto(ecodes.KEY_A in t, "de un texto con acentos se saca lo que hay")
afirmar_igual(mapeador.teclas_de_texto(""), set(), "un texto vacio no da nada")
afirmar_igual(mapeador.teclas_de_texto(None), set(), "y None tampoco revienta")

titulo("El mando virtual de Steam se reconoce por su identificador")

# Steam nunca pasa el mando fisico a los juegos: crea uno virtual que se hace
# pasar por un "Microsoft X-Box 360 pad". Por el NOMBRE no hay forma de
# distinguirlo; por el identificador 28DE:11FF, si.
# Se lee de SRC, no de la raiz: asi WP_SRC tambien vale para las
# comprobaciones de estructura.
fuente = open(os.path.join(SRC, "mapeador.py"), encoding="utf-8").read()
afirmar_contiene(fuente.upper(), "28DE", "el mapeador conoce el fabricante 28DE")
afirmar_contiene(fuente.upper(), "11FF", "y el producto 11FF")

titulo("Las ordenes del sistema del .keys NO se ejecutan")

# Batocera admite {"type":"exec"} para lanzar una orden con un boton. Ejecutar
# lo que ponga un fichero que viene DENTRO de un juego descargado es correr
# codigo ajeno sin avisar, asi que se reconoce y se dice, pero no se ejecuta.
#
# Esto se comprueba sobre el FUENTE porque el bucle que lee el .keys necesita
# un mando de verdad. Es una prueba de estructura, y aqui vale: lo que hay que
# garantizar es que no exista la llamada, no que no se llegue a ella.
afirmar_contiene(fuente, "no se ejecuta",
                 "el mapeador dice que no ejecuta las ordenes del sistema")
for peligro in ("os.system(", "subprocess.call(", "subprocess.run(",
                "subprocess.Popen(", "os.popen(", "eval(", "exec("):
    afirmar_no_contiene(fuente, peligro,
                        "el mapeador no usa %s en ningun sitio" % peligro)

sys.exit(resumen(os.path.basename(__file__)))
