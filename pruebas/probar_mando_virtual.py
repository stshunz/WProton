#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# Prueba: la aritmetica y las tablas del mando virtual.
#
# Copyright (C) 2026  stshunz y colaboradores. GPL v3 o posterior.
# ----------------------------------------------------------------------------
# POR QUE ESTA PRUEBA
#
# Del mando virtual esta pendiente la prueba en hardware real: que modo sirve
# para cada juego solo lo dice el juego. Lo que SI se puede sujetar aqui es
# todo lo que no depende de tener un mando delante:
#
#   - la conversion de cruceta a stick, incluida la regla de que el stick
#     fisico manda si ya esta movido;
#   - los rangos que se declaran, que son los de un Xbox 360 de verdad para
#     que el juego calibre igual;
#   - el perfil CLASICO, cuya razon de ser es que los gatillos NO sean ejes:
#     un juego de los 90 ve un eje que en reposo esta en un extremo y cree que
#     lo estas empujando;
#   - la tabla del modo escritorio de Steam, donde los botones mandan teclas y
#     un juego que espere un mando no recibe nada.
#
# Que la aritmetica este bien no dice que el modo sirva. Dice que si no sirve,
# no es por la aritmetica, y eso ahorra la mitad de la busqueda.
# ----------------------------------------------------------------------------
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from comun import (afirmar_igual, afirmar_cierto, afirmar_falso,  # noqa: E402
                   titulo, resumen)

import mando_virtual as mv                                        # noqa: E402
from evdev import ecodes                                          # noqa: E402


titulo("De cruceta a stick")

afirmar_igual(mv.cruceta_a_stick(-1, 0), mv.EJE_MIN,
              "cruceta a la izquierda/arriba -> el extremo negativo")
afirmar_igual(mv.cruceta_a_stick(1, 0), mv.EJE_MAX,
              "cruceta a la derecha/abajo -> el extremo positivo")
afirmar_igual(mv.cruceta_a_stick(0, 0), 0,
              "cruceta suelta -> el stick al centro")

titulo("El stick fisico manda si ya esta movido")

# Quien esta usando el stick no quiere que la cruceta le corrija la direccion.
afirmar_igual(mv.cruceta_a_stick(-1, 20000), 20000,
              "con el stick empujado, la cruceta no lo pisa")
afirmar_igual(mv.cruceta_a_stick(1, -20000), -20000,
              "y tampoco en sentido contrario")
afirmar_igual(mv.cruceta_a_stick(0, 20000), 20000,
              "soltar la cruceta no centra un stick que se esta usando")

# Un roce no cuenta: por debajo del umbral gana la cruceta.
afirmar_igual(mv.cruceta_a_stick(-1, 8000), mv.EJE_MIN,
              "justo en el umbral todavia manda la cruceta")
afirmar_igual(mv.cruceta_a_stick(-1, 8001), 8001,
              "un punto por encima ya manda el stick")
afirmar_igual(mv.cruceta_a_stick(-1, -8001), -8001,
              "el umbral vale para los dos lados")

titulo("Los rangos son los de un Xbox 360")

afirmar_igual((mv.EJE_MIN, mv.EJE_MAX), (-32768, 32767),
              "los sticks van de -32768 a 32767")
afirmar_igual((mv.GAT_MIN, mv.GAT_MAX), (0, 255),
              "los gatillos van de 0 a 255")
afirmar_igual(mv.GATILLO_UMBRAL, 127,
              "un gatillo cuenta como pulsado a mitad de recorrido")

ejes = dict(mv.EJES)
afirmar_igual(ejes[ecodes.ABS_HAT0X][:2], (-1, 1),
              "la cruceta como eje vale -1, 0 o 1")
afirmar_igual(ejes[ecodes.ABS_X][:2], (mv.EJE_MIN, mv.EJE_MAX),
              "el stick izquierdo declara el rango completo")

titulo("La cruceta como boton corresponde al eje correcto")

for boton, (eje, valor) in mv.DPAD_BOTON.items():
    afirmar_cierto(eje in (ecodes.ABS_HAT0X, ecodes.ABS_HAT0Y),
                   "el boton %d va a un eje de la cruceta" % boton)
    afirmar_cierto(valor in (-1, 1),
                   "y con un valor de cruceta valido")

afirmar_igual(mv.DPAD_BOTON[ecodes.BTN_DPAD_UP], (ecodes.ABS_HAT0Y, -1),
              "arriba es HAT0Y negativo")
afirmar_igual(mv.DPAD_BOTON[ecodes.BTN_DPAD_DOWN], (ecodes.ABS_HAT0Y, 1),
              "abajo es HAT0Y positivo")
afirmar_igual(mv.DPAD_BOTON[ecodes.BTN_DPAD_LEFT], (ecodes.ABS_HAT0X, -1),
              "izquierda es HAT0X negativo")
afirmar_igual(mv.DPAD_BOTON[ecodes.BTN_DPAD_RIGHT], (ecodes.ABS_HAT0X, 1),
              "derecha es HAT0X positivo")

# Los cuatro botones tienen que dar cuatro parejas distintas: si dos coinciden,
# la cruceta se queda coja en una direccion.
afirmar_igual(len(set(mv.DPAD_BOTON.values())), 4,
              "las cuatro direcciones son distintas entre si")

titulo("El perfil clasico: los gatillos NO son ejes")

# Esta es toda la razon de ser del modo clasico. Un juego de los 90 ve un eje
# que en reposo esta en un extremo y cree que lo estas empujando: se acelera
# solo o el menu se va corriendo hacia un lado.
ejes_clasico = [c for c, _ in mv.EJES_CLASICO]
afirmar_falso(ecodes.ABS_Z in ejes_clasico,
              "el gatillo izquierdo no aparece como eje")
afirmar_falso(ecodes.ABS_RZ in ejes_clasico,
              "ni el derecho")
afirmar_cierto(ecodes.BTN_TL2 in mv.BOTONES_CLASICO
               and ecodes.BTN_TR2 in mv.BOTONES_CLASICO,
               "los gatillos estan, pero como botones")

# Y la cruceta sigue estando: es el POV de toda la vida.
afirmar_cierto(ecodes.ABS_HAT0X in ejes_clasico
               and ecodes.ABS_HAT0Y in ejes_clasico,
               "la cruceta sigue ahi, como POV")

# Muchos juegos viejos solo miran los cuatro primeros ejes y no pasan de doce
# botones.
afirmar_cierto(len(ejes_clasico) <= 6,
               "el perfil clasico no declara mas ejes de los que se manejaban")
afirmar_cierto(len(mv.BOTONES_CLASICO) <= 12,
               "ni mas de doce botones")

titulo("El modo escritorio de Steam, traducido de vuelta")

# La tabla por defecto de Steam esta documentada: A = Enter, B = Escape,
# Y = Espacio, cruceta = flechas, gatillos = clics.
afirmar_igual(mv.TECLA_A_BOTON[ecodes.KEY_ENTER], ecodes.BTN_SOUTH,
              "Enter vuelve a ser A")
afirmar_igual(mv.TECLA_A_BOTON[ecodes.KEY_ESC], ecodes.BTN_EAST,
              "Escape vuelve a ser B")
afirmar_igual(mv.TECLA_A_BOTON[ecodes.KEY_SPACE], ecodes.BTN_NORTH,
              "Espacio vuelve a ser Y")

afirmar_igual(mv.TECLA_A_CRUCETA[ecodes.KEY_UP][:2], (ecodes.ABS_HAT0Y, -1),
              "la flecha arriba vuelve a ser la cruceta arriba")
afirmar_igual(mv.TECLA_A_CRUCETA[ecodes.KEY_UP][2], ecodes.BTN_DPAD_UP,
              "y ademas el boton de cruceta, como todo lo demas")
afirmar_igual(len(mv.TECLA_A_CRUCETA), 4,
              "estan las cuatro flechas")

afirmar_igual(mv.RATON_A_BOTON[ecodes.BTN_LEFT][1], ecodes.BTN_TR2,
              "el clic izquierdo vuelve a ser el gatillo derecho")
afirmar_igual(mv.RATON_A_BOTON[ecodes.BTN_RIGHT][1], ecodes.BTN_TL2,
              "y el derecho, el izquierdo")

titulo("Steam se reconoce por el fabricante, no por el nombre")

# El mando virtual de Steam se hace pasar por un "Microsoft X-Box 360 pad": por
# el nombre no hay forma de distinguirlo del fisico.
afirmar_igual(mv.VENDOR_STEAM, 0x28DE,
              "el fabricante de Valve es 28DE")

titulo("Los nombres que finge el mando virtual")

afirmar_cierto(len(mv.NOMBRES_VIRTUALES) >= 1,
               "hay al menos un nombre de mando que fingir")
afirmar_igual(mv.NOMBRE_VIRTUAL, mv.MANDOS["xbox"][0],
              "el de por defecto es el de Xbox")
afirmar_igual(len(set(mv.NOMBRES_VIRTUALES)), len(mv.NOMBRES_VIRTUALES),
              "y no se repiten entre si")

titulo("Las capacidades que se anuncian")

caps = mv.capacidades(clasico=False)
caps_c = mv.capacidades(clasico=True)
afirmar_cierto(ecodes.EV_KEY in caps and ecodes.EV_ABS in caps,
               "se anuncian botones y ejes")
afirmar_igual(len(caps[ecodes.EV_ABS]), len(mv.EJES),
              "el modo normal anuncia todos sus ejes")
afirmar_igual(len(caps_c[ecodes.EV_ABS]), len(mv.EJES_CLASICO),
              "y el clasico solo los suyos")
afirmar_cierto(len(caps_c[ecodes.EV_KEY]) < len(caps[ecodes.EV_KEY]),
               "el clasico anuncia menos botones que el moderno")

sys.exit(resumen(os.path.basename(__file__)))
