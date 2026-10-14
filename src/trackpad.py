# WProton - trackpads de la Steam Deck como raton
#
# Copyright (C) 2026  stshunz y colaboradores
#
# Este programa es software libre: puedes redistribuirlo y/o modificarlo bajo
# los terminos de la Licencia Publica General GNU (GPL), version 3 o
# posterior, publicada por la Free Software Foundation.
#
# Se distribuye SIN NINGUNA GARANTIA. Ver <https://www.gnu.org/licenses/>.
#
# POR QUE ESTO EXISTE, Y COMO FUNCIONA DE VERDAD
#
# Esta version esta escrita MIRANDO EL CODIGO DEL DRIVER, drivers/hid/hid-steam.c
# del kernel, en vez de a base de suposiciones. Las dos primeras no funcionaron
# justamente por eso, y los dos errores estan contados aqui abajo para que no se
# repitan.
#
# LOS DOS MODOS DEL MANDO DE LA DECK
#
# El mando tiene dos estados, y los cambia EL USUARIO manteniendo pulsado el
# boton de OPCIONES (el de las tres rayas, que el kernel ve como BTN_START)
# durante 450 ms. Lo hace el propio Steam igual, con su vibracion de aviso:
#
#   modo ESCRITORIO (lo normal, "modo lagarto" encendido)
#       El FIRMWARE del mando emula raton y teclado: el pad derecho mueve el
#       puntero y el izquierdo hace de rueda. A cambio, el driver NO publica
#       nada por evdev: el dispositivo "Steam Deck" existe pero no manda ni un
#       evento. En hid-steam.c:
#           if (!steam->gamepad_mode && lizard_mode)
#                   return;
#
#   modo GAMEPAD (se entra manteniendo opciones)
#       Se apaga la emulacion del firmware -los pads dejan de mover el puntero,
#       que es lo que la gente cuenta como "se han muerto los trackpads"- y el
#       driver EMPIEZA a publicar todo por evdev, los dos trackpads incluidos.
#
# PRIMER ERROR QUE SE COMETIO: creer que lo apagabamos nosotros. El comentario
# de cabecera del driver dice que apaga el modo lagarto al abrir el dispositivo
# de entrada... pero eso NO vale para la Deck, y lo dice su propio codigo:
#
#   /*
#    * Disabling lizard mode automatically is only done on the Steam
#    * Controller. On the Steam Deck, this is toggled manually by holding
#    * the options button instead, handled by steam_mode_switch_cb.
#    */
#   if (!(steam->quirks & (STEAM_QUIRK_DECK | STEAM_QUIRK_IBEX))) {
#
# O sea que en una Deck con kernel 6.8 o mas nuevo, ABRIR el mando -por evdev o
# por SDL- no apaga los trackpads. Si estan apagados, es que el mando esta en
# modo gamepad, o que lo apago un programa por hidraw (Steam lo hace).
#
# SEGUNDO ERROR: decir que los pads "no se pueden leer por evdev". SI se pueden,
# y desde el kernel 6.3. El driver los publica como ejes del propio mando:
#
#   pad IZQUIERDO -> ABS_HAT0X / ABS_HAT0Y      (-32767 .. 32767)
#   pad DERECHO   -> ABS_HAT1X / ABS_HAT1Y      (-32767 .. 32767)
#   clic del izquierdo -> BTN_THUMB   clic del derecho -> BTN_THUMB2
#
# Y cuando el dedo NO esta sobre el pad, el driver publica 0,0 a proposito:
#
#   if (lpad_touched) { input_report_abs(input, ABS_HAT0X, steam_le16(data + 16)); ... }
#   else              { input_report_abs(input, ABS_HAT0X, 0); ... }
#
# Asi que el 0,0 es "dedo levantado" y sale gratis, sin mirar la presion.
#
# COMO SE LEE AQUI
#
# Por EVDEV primero, que es lo correcto: nada de desplazamientos en bytes que
# adivinar, y no hace falta tocar hidraw.
#
# Y por HIDRAW solo de respaldo, para cuando el evdev del driver no existe. Pasa
# de verdad: si un programa abre el nodo hidraw del mando -Steam lo hace-, el
# driver DESREGISTRA su dispositivo de entrada ("it will not send any command to
# the controller" y "this input device will be removed"). En el modo Juego, con
# Steam delante, ese es el estado normal.
#
# OJO con ese respaldo: abrir hidraw nos convierte a nosotros en ese "cliente",
# asi que puede hacer desaparecer el mando del resto del sistema. Por eso va
# SEGUNDO y se avisa en el registro.
#
# TOMAR EL CONTROL: LOS TRACKPADS DE WProton, NO LOS DE VALVE
#
# Lo de arriba sirve si el mando YA esta en modo gamepad, pero eso obliga a
# mantener pulsado OPCIONES, que es el gesto de Steam. Dani lo pidio al
# contrario: que WProton tenga sus propios trackpads y los encienda y apague
# cuando se quiera.
#
# Para eso HAY que escribirle al mando, y aqui esta la unica forma de hacerlo
# con cabeza: mandando EXACTAMENTE los mismos comandos que manda el driver del
# kernel en steam_set_lizard_mode(), copiados de su codigo, no deducidos.
#
#   APAGAR la emulacion del firmware (los pads pasan a ser nuestros):
#       0x81                      ID_CLEAR_DIGITAL_MAPPINGS
#       0x87 06 09 00 00 47 00 00 ID_SET_SETTINGS_VALUES con
#                                   registro 0x09 (SETTING_LIZARD_MODE)       = 0
#                                   registro 0x47 (SETTING_STEAM_WATCHDOG_...) = 0
#
#   ENCENDERLA otra vez (se devuelve el mando a como estaba):
#       0x85                      ID_SET_DEFAULT_DIGITAL_MAPPINGS
#       0x8E                      ID_LOAD_DEFAULT_SETTINGS
#
# El watchdog se apaga porque es lo que hace el driver y por lo que dice su
# propio comentario: "disable watchdog that tests if Steam is active". Sin eso,
# el firmware vuelve a encender la emulacion al rato por su cuenta.
#
# COMO SE MANDAN: son informes de CARACTERISTICA (feature), no escrituras
# normales. El driver usa hid_hw_raw_request(..., HID_FEATURE_REPORT,
# HID_REQ_SET_REPORT); desde espacio de usuario eso es el ioctl HIDIOCSFEATURE
# sobre el fd de /dev/hidrawN. Un write() normal manda un informe de SALIDA, que
# NO es lo mismo y el mando ignora.
#
# Y van SIEMPRE de 65 bytes: 1 de numero de informe (0 en la Deck) + 64 de
# contenido rellenado a ceros, que es lo que hace el driver
# (max(size, 64) + 1).
#
# LO QUE SE DEVUELVE SIEMPRE
#
# Al terminar -tambien si nos matan con una señal, que es como lo para WProton-
# se manda el par de comandos de encender. Dejar el mando con la emulacion
# apagada seria dejarle los trackpads muertos a alguien que no sabe por que.
# Y hay red de seguridad por partida doble: al cerrar nuestro fd de hidraw, el
# driver del kernel vuelve a registrar el mando y el mismo llama a
# steam_set_lizard_mode(steam, lizard_mode), o sea que lo restaura otra vez.
#
# EL PRECIO, QUE HAY QUE SABERLO
#
# Mientras tengamos abierto el hidraw, el driver RETIRA su dispositivo de
# entrada del mando ("this input device will be removed"). Con Steam en marcha
# eso da igual, porque Steam ya lo tiene cogido y publica su propio mando
# virtual. Sin Steam, el mando desaparece para los juegos mientras esto corra,
# asi que se avisa en el registro.
import sys, os, time, struct, glob

VENDOR_VALVE = 0x28DE
# 0x1205 = Steam Deck. Se admite tambien el mando de Valve por USB/BT por si
# alguien lo usa en un equipo de sobremesa.
PRODUCTOS = (0x1205, 0x1102, 0x1142)

# --- EL FORMATO DEL INFORME --------------------------------------------------
#
# Informe de estado de la Deck: 64 bytes que empiezan por 01 00 09 40
#   (01 00 = cabecera, 09 = tipo "estado del mando", 40 = 64 bytes de largo)
#
# Y estos son los desplazamientos de lo que nos interesa, todo entero con signo
# de 16 bits y en little endian:
#
#   16..17  pad izquierdo X        20..21  pad derecho X
#   18..19  pad izquierdo Y        22..23  pad derecho Y
#   56..57  presion del izquierdo  58..59  presion del derecho
#
# Los desplazamientos SON LOS DEL DRIVER, copiados de su tabla en hid-steam.c
# ("The size for this message payload is 56"), no una suposicion:
#
#    16-17 | s16   | ABS_HAT0X | left-pad X value
#    18-19 | s16   | ABS_HAT0Y | left-pad Y value
#    20-21 | s16   | ABS_HAT1X | right-pad X value
#    22-23 | s16   | ABS_HAT1Y | right-pad Y value
#    56-57 | u16   | --        | left pad pressure
#    58-59 | u16   | --        | right pad pressure
#
# AQUI ESTABA EL FALLO QUE DEJABA ESTO MUERTO.
#
# La cabecera que se comprobaba era b'\x01\x00\x09\x40': se dio por hecho que el
# cuarto byte era el largo TOTAL del informe, 64 = 0x40. Y no: es el largo del
# CONTENIDO, 56 = 0x38. Asi que el filtro no casaba NUNCA, se descartaban todos
# los informes y el puntero no se movia ni un pixel, sin un solo error en el
# registro.
#
# Ahora se comprueba exactamente lo que comprueba el driver, ni un byte mas:
#
#   if (size != 64 || data[0] != 1 || data[1] != 0)
#           return 0;
#   switch (data[2]) { ... case ID_CONTROLLER_DECK_STATE: ...
#
# O sea: 64 bytes, data[0]=1, data[1]=0 y data[2]=9. El cuarto byte no se mira,
# que es lo que no habia que haber hecho desde el principio.
CAB = b'\x01\x00\x09'
TIPO_DECK = 9
OFF_IZQ_X, OFF_IZQ_Y = 16, 18
OFF_DER_X, OFF_DER_Y = 20, 22
OFF_IZQ_P, OFF_DER_P = 56, 58
LARGO = 64


# --- ESCRIBIRLE AL MANDO ----------------------------------------------------
#
# Los numeros son los del driver (hid-steam.c), contando las posiciones de sus
# enums. No se "parecen" a los del driver: son los mismos.
ID_CLEAR_DIGITAL_MAPPINGS       = 0x81
ID_SET_DEFAULT_DIGITAL_MAPPINGS = 0x85
ID_SET_SETTINGS_VALUES          = 0x87
ID_LOAD_DEFAULT_SETTINGS        = 0x8E
SETTING_LIZARD_MODE             = 0x09   # posicion 9 del enum de ajustes
SETTING_STEAM_WATCHDOG_ENABLE   = 0x47   # posicion 71
LARGO_FEATURE = 64


def _hidiocsfeature(largo):
    """El numero del ioctl HIDIOCSFEATURE para un informe de "largo" bytes.

    Se calcula en vez de llevarlo escrito a mano, que es como se cuelan los
    errores de arquitectura. La macro del kernel es:

        #define HIDIOCSFEATURE(len)  _IOC(_IOC_WRITE|_IOC_READ, 'H', 0x06, len)

    y _IOC empaqueta direccion (2 bits), tamaño (14), tipo (8) y numero (8).
    """
    _IOC_WRITE, _IOC_READ = 1, 2
    direccion = _IOC_WRITE | _IOC_READ
    return (direccion << 30) | (largo << 16) | (ord('H') << 8) | 0x06


def _mandar_feature(fd, carga):
    """Manda un informe de caracteristica al mando. "carga" = el comando.

    Devuelve True si el mando lo acepto.
    """
    import fcntl
    # 1 byte de numero de informe (0 en la Deck) + 64 de contenido a ceros.
    buf = bytearray(1 + LARGO_FEATURE)
    buf[1:1 + len(carga)] = carga
    try:
        fcntl.ioctl(fd, _hidiocsfeature(len(buf)), bytes(buf))
        return True
    except OSError as ex:
        print('trackpad: el mando rechazo el comando %02X (%s)'
              % (carga[0] if carga else 0, ex), file=sys.stderr)
        return False


def lagarto_apagar(fd):
    """Apaga la emulacion de raton/teclado del firmware: los pads son nuestros.

    Son los dos comandos de la rama "else" de steam_set_lizard_mode().
    """
    ok = _mandar_feature(fd, bytes([ID_CLEAR_DIGITAL_MAPPINGS]))
    # 0x87, longitud 6, y tres bytes por pareja: registro, valor bajo, alto.
    ajustes = bytes([ID_SET_SETTINGS_VALUES, 6,
                     SETTING_LIZARD_MODE, 0, 0,
                     SETTING_STEAM_WATCHDOG_ENABLE, 0, 0])
    ok = _mandar_feature(fd, ajustes) and ok
    if ok:
        print('trackpad: emulacion del firmware APAGADA; los pads son de '
              'WProton', file=sys.stderr)
    return ok


def lagarto_encender(fd):
    """Devuelve el mando a como estaba: el firmware vuelve a mover el puntero.

    Son los dos comandos de la rama "if (enable)" de steam_set_lizard_mode().
    """
    ok = _mandar_feature(fd, bytes([ID_SET_DEFAULT_DIGITAL_MAPPINGS]))
    ok = _mandar_feature(fd, bytes([ID_LOAD_DEFAULT_SETTINGS])) and ok
    if ok:
        print('trackpad: emulacion del firmware devuelta al mando',
              file=sys.stderr)
    return ok


def _s16(buf, off):
    """Entero con signo de 16 bits en little endian."""
    if off + 2 > len(buf):
        return 0
    return struct.unpack_from('<h', buf, off)[0]


def _u16(buf, off):
    if off + 2 > len(buf):
        return 0
    return struct.unpack_from('<H', buf, off)[0]


# --- CUAL DE LOS hidraw ES EL MANDO -----------------------------------------
#
# AQUI ESTABA EL FALLO QUE DEJABA ESTO SIN FUNCIONAR EN LA DECK.
#
# Se buscaba el primer /dev/hidraw* con el fabricante y el modelo de Valve, y
# se daba por hecho que solo habia uno. Y no: la Deck crea CINCO interfaces, y
# las tres que son HID llevan el mismo 28DE:1205. Lo dice el driver:
#
#   Steam Deck:
#     0: raton emulado
#     1: teclado emulado
#     2: el mando de verdad
#     3-4: comunicacion interna (no son HID)
#
# O sea que lo que se cogia era EL RATON EMULADO. Los comandos de caracteristica
# se mandaban ahi -donde no hacen nada- y no llegaba ni un informe de estado,
# porque esa interfaz no los manda. Sin un solo error en el registro: el bucle
# se quedaba leyendo para siempre informes que descartaba.
#
# COMO SE DISTINGUE, con el criterio del propio driver y no con uno inventado:
# el mando de verdad es LA UNICA INTERFAZ CON INFORMES DE CARACTERISTICA
# (steam_is_valve_interface). El raton y el teclado emulados no tienen ninguno.
# Y se mira en el descriptor de informes, que sysfs publica tal cual.


def _descriptor(nodo):
    """El descriptor de informes de ese hidraw, en crudo. b'' si no se puede."""
    ruta = '/sys/class/hidraw/%s/device/report_descriptor' % os.path.basename(nodo)
    try:
        with open(ruta, 'rb') as fh:
            return fh.read()
    except OSError:
        return b''


def tiene_feature(desc):
    """True si el descriptor declara algun informe de CARACTERISTICA.

    Se recorre el descriptor como lo que es -una lista de elementos con su
    cabecera y su tamaño-, no buscando un byte suelto: el 0xB1 de un elemento
    "Feature" puede aparecer igual dentro de los DATOS de otro elemento, y
    buscandolo a pelo cualquier interfaz daria positivo.

    La cabecera de un elemento corto trae el tipo y el tamaño:
        bits 0-1  tamaño de los datos (3 significa 4 bytes)
        bits 2-3  clase (0 = Main)
        bits 4-7  etiqueta (0x0B = Feature)
    """
    i, n = 0, len(desc)
    while i < n:
        pre = desc[i]
        if pre == 0xFE:          # elemento largo: cabecera de 3 + datos
            if i + 1 >= n:
                break
            i += 3 + desc[i + 1]
            continue
        tam = pre & 0x03
        if tam == 3:
            tam = 4
        if ((pre >> 2) & 0x03) == 0 and ((pre >> 4) & 0x0F) == 0x0B:
            return True
        i += 1 + tam
    return False


def _uevent(nodo):
    """Lo que sysfs cuenta de ese hidraw: (vid, pid, donde esta enchufado)."""
    base = '/sys/class/hidraw/%s/device/uevent' % os.path.basename(nodo)
    vid = pid = None
    phys = ''
    try:
        with open(base) as fh:
            txt = fh.read()
    except OSError:
        return None, None, ''
    for linea in txt.splitlines():
        if linea.startswith('HID_ID='):
            # HID_ID=0003:000028DE:00001205
            trozos = linea.strip().split(':')
            if len(trozos) == 3:
                try:
                    vid = int(trozos[1], 16)
                    pid = int(trozos[2], 16)
                except ValueError:
                    pass
        elif linea.startswith('HID_PHYS='):
            phys = linea.split('=', 1)[1].strip()
    return vid, pid, phys


def buscar_decks():
    """TODOS los hidraw que son de Valve, el mando de verdad primero.

    Devuelve una lista de diccionarios para poder enseñarla entera en el
    diagnostico: cuando esto falla, lo primero que hay que ver es cuantos
    habia y por que se eligio uno.
    """
    salida = []
    for nodo in sorted(glob.glob('/dev/hidraw*'),
                       key=lambda r: int(''.join(c for c in os.path.basename(r)
                                                 if c.isdigit()) or 0)):
        vid, pid, phys = _uevent(nodo)
        if vid != VENDOR_VALVE or pid not in PRODUCTOS:
            continue
        desc = _descriptor(nodo)
        try:
            fd = os.open(nodo, os.O_RDONLY | os.O_NONBLOCK)
            os.close(fd)
            legible = True
        except OSError as ex:
            legible = False
            print('trackpad: %s es de Valve pero no se puede leer (%s)'
                  % (nodo, ex), file=sys.stderr)
        salida.append({'nodo': nodo, 'vid': vid, 'pid': pid, 'phys': phys,
                       'descriptor': len(desc), 'feature': tiene_feature(desc),
                       'legible': legible})
    # El criterio del driver primero; el descriptor mas largo como desempate,
    # que es el otro que usa el: "the real controller is the one that has the
    # longest report descriptor".
    salida.sort(key=lambda c: (not c['legible'], not c['feature'],
                               -c['descriptor']))
    return salida


def buscar_deck():
    """La ruta del /dev/hidraw* DEL MANDO DE VERDAD, o None."""
    for c in buscar_decks():
        if c['legible'] and c['feature']:
            return c['nodo']
    # Sin ninguno con informes de caracteristica no se elige a ciegas: mandarle
    # comandos al raton emulado es lo que no funcionaba, y hacerlo en silencio
    # otra vez seria repetir el mismo error.
    hay = buscar_decks()
    if hay:
        print('trackpad: hay %d interfaz(es) de Valve pero NINGUNA declara '
              'informes de caracteristica, asi que ninguna es el mando: %s'
              % (len(hay), ', '.join(c['nodo'] for c in hay)), file=sys.stderr)
        print('trackpad: (el mando de verdad es la unica que los tiene; el '
              'raton y el teclado emulados no)', file=sys.stderr)
    return None


def abrir_mando(escribir=False):
    """Abre el hidraw del mando. escribir=True si hay que mandarle comandos.

    Se abre en SOLO LECTURA cuando no hace falta escribir: asi un diagnostico
    no puede tocar el mando ni por error.
    """
    # SE ENSEÑAN TODAS LAS CANDIDATAS, SIEMPRE.
    #
    # Es barato y es justo lo que faltaba: con el mando elegido mal, en el
    # registro no habia nada con que notarlo.
    candidatas = buscar_decks()
    for c in candidatas:
        print('trackpad: %s  %04X:%04X  descriptor %d bytes  %s  %s  [%s]'
              % (c['nodo'], c['vid'], c['pid'], c['descriptor'],
                 'CON feature' if c['feature'] else 'sin feature',
                 'legible' if c['legible'] else 'NO legible',
                 c['phys'] or '?'), file=sys.stderr)
    nodo = buscar_deck()
    if not nodo:
        if not candidatas:
            print('trackpad: no se ha encontrado ningun mando de Valve en '
                  '/dev/hidraw*', file=sys.stderr)
            print('trackpad: si esto ES una Deck, suele ser cosa de permisos:',
                  file=sys.stderr)
            print('trackpad: hacen falta las reglas udev de Steam para hidraw.',
                  file=sys.stderr)
        return None, None
    try:
        fd = os.open(nodo, os.O_RDWR if escribir else os.O_RDONLY)
    except OSError as e:
        print('trackpad: no se pudo abrir %s%s: %s'
              % (nodo, ' para escribir' if escribir else '', e), file=sys.stderr)
        return None, None
    print('trackpad: mando en %s%s (es la unica interfaz con informes de '
          'caracteristica, que es como lo distingue el driver)'
          % (nodo, ' (lectura y escritura)' if escribir else ''),
          file=sys.stderr)
    # SE AVISA DEL PRECIO DE TENER ESTO ABIERTO.
    #
    # Mientras un programa tiene el hidraw del mando abierto, el driver retira
    # su dispositivo de entrada. Con Steam delante da igual -ya lo tenia el- y
    # sin Steam el mando desaparece para los juegos mientras esto corra. No es
    # algo que podamos evitar: es como funciona el driver.
    print('trackpad: (mientras esto lea el mando, el gamepad del kernel no '
          'esta publicado)', file=sys.stderr)
    return fd, nodo


# "Ha llegado algo, pero no es un informe de estado". Es un objeto propio y no
# None a proposito: distinguir "no llega nada" de "llega otra cosa" es lo que
# dice si la interfaz elegida es la del mando o la del raton emulado.
FUERA = object()

# Segundos leyendo sin un solo informe bueno antes de avisar en el registro.
ESPERA_AVISO = 3.0


def leer_informe(fd, espera=1.0):
    """Un informe de estado del mando.

    Devuelve los bytes si es bueno, FUERA si llego algo que no lo es, y None si
    no llego nada a tiempo.
    """
    import select
    r, _, _ = select.select([fd], [], [], espera)
    if not r:
        return None
    try:
        datos = os.read(fd, 128)
    except OSError:
        return None
    if not datos:
        return None
    # EXACTAMENTE lo que comprueba el driver: 64 bytes y 01 00 09 delante.
    if len(datos) != LARGO or not datos.startswith(CAB):
        return FUERA
    return datos


# ---------------------------------------------------------------------------
# EL CAMINO BUENO: LOS PADS POR EVDEV
# ---------------------------------------------------------------------------
# Los codigos los publica el driver (ver la cabecera de este fichero). El pad
# izquierdo son los ejes del "hat 0" y el derecho los del "hat 1", con sus
# clics en BTN_THUMB y BTN_THUMB2.
EJES_PAD = {'izquierdo': ('ABS_HAT0X', 'ABS_HAT0Y'),
            'derecho':   ('ABS_HAT1X', 'ABS_HAT1Y')}


def buscar_pads_evdev():
    """El dispositivo de entrada del mando que publica los trackpads, o None.

    NO se busca por nombre ("Steam Deck"), que cambia entre modelos y entre
    versiones del driver: se busca por lo unico que importa, que el aparato
    declare los ejes de los dos pads. Asi vale igual para el mando nuevo de
    Valve, que el driver trata con el mismo codigo.
    """
    try:
        import evdev
        from evdev import ecodes as e
    except ImportError:
        return None
    for ruta in sorted(evdev.list_devices()):
        try:
            d = evdev.InputDevice(ruta)
        except (OSError, IOError):
            continue
        try:
            caps = d.capabilities().get(e.EV_ABS) or []
            codigos = {c for c, _ in caps}
            # Los cuatro ejes de los dos pads: es la firma del mando de la Deck.
            if {e.ABS_HAT0X, e.ABS_HAT0Y, e.ABS_HAT1X, e.ABS_HAT1Y} <= codigos:
                return d
        except Exception:
            pass
        try:
            d.close()
        except Exception:
            pass
    return None


# ---------------------------------------------------------------------------
# MODO PROBAR: solo mira, no toca nada
# ---------------------------------------------------------------------------
def estado(segundos=0):
    """EL DIAGNOSTICO: en que estado esta el mando y por donde se puede leer.

    Esto existe porque de este asunto se han hecho dos arreglos a ciegas que no
    funcionaron, y en ninguno de los dos casos habia en el registro con que
    distinguir las cinco cosas que pueden estar pasando. Aqui se miran todas,
    de una vez y sin preguntarle nada a nadie.
    """
    print('--- trackpads de la Steam Deck: estado ---', file=sys.stderr)
    # 1) El parametro del modulo: si esta a 0, el driver no activa nunca la
    #    emulacion del firmware NI deja funcionar el cambio manual.
    lz = None
    try:
        with open('/sys/module/hid_steam/parameters/lizard_mode') as fh:
            lz = fh.read().strip()
    except OSError:
        print('  hid_steam: no esta cargado o no expone lizard_mode', file=sys.stderr)
    if lz is not None:
        print('  lizard_mode (parametro del modulo) = %s' % lz, file=sys.stderr)
        if lz in ('N', '0'):
            print('    OJO: a 0 el driver no enciende la emulacion de raton del', file=sys.stderr)
            print('    firmware, y el cambio manteniendo OPCIONES no hace nada.', file=sys.stderr)
    # 2) El hidraw del mando: si existe pero NO hay evdev, es que alguien lo
    #    tiene abierto (Steam) y el driver ha retirado su dispositivo.
    # 2) TODAS las interfaces de Valve, no solo una.
    #
    # La Deck crea cinco y tres son HID, las tres con el mismo 28DE:1205: la 0
    # es el raton emulado, la 1 el teclado emulado y la 2 el mando de verdad.
    # Coger la primera -que es lo que se hacia- es coger el raton emulado, y
    # ahi ni los comandos hacen nada ni llegan informes de estado. Esta tabla
    # es lo que hacia falta para verlo.
    cands = buscar_decks()
    if not cands:
        print('  interfaces de Valve: NINGUNA', file=sys.stderr)
    else:
        print('  interfaces de Valve (%d), la del mando va primera:' % len(cands),
              file=sys.stderr)
        for c in cands:
            print('    %-14s %04X:%04X  descriptor %4d B  %-12s %-11s %s'
                  % (c['nodo'], c['vid'], c['pid'], c['descriptor'],
                     'CON feature' if c['feature'] else 'sin feature',
                     'legible' if c['legible'] else 'NO legible',
                     c['phys'] or '?'), file=sys.stderr)
        print('    (el mando de verdad es la UNICA con informes de '
              'caracteristica: asi lo distingue el driver)', file=sys.stderr)
    nodo = buscar_deck()
    print('  hidraw del mando: %s' % (nodo or 'no encontrado'), file=sys.stderr)
    if cands and not nodo:
        print('    OJO: hay interfaces de Valve pero ninguna con informes de', file=sys.stderr)
        print('    caracteristica. O faltan permisos para leer el descriptor,', file=sys.stderr)
        print('    o este mando no es de los que trae el driver.', file=sys.stderr)
    # 3) El evdev con los pads.
    dev = buscar_pads_evdev()
    if dev is None:
        print('  evdev con los trackpads: NO HAY', file=sys.stderr)
        if nodo:
            print('    El mando esta ahi, asi que lo mas probable es que otro', file=sys.stderr)
            print('    programa tenga abierto su hidraw -Steam lo hace- y el', file=sys.stderr)
            print('    driver haya retirado su dispositivo de entrada.', file=sys.stderr)
            print('    En ese caso WProton leera por hidraw, de respaldo.', file=sys.stderr)
        else:
            print('    Ni hidraw ni evdev: esto no parece una Steam Deck, o', file=sys.stderr)
            print('    faltan permisos para leer el mando.', file=sys.stderr)
        return 1
    print('  evdev con los trackpads: %s  (%s)' % (dev.path, dev.name), file=sys.stderr)
    # 4) ¿Manda algo? Es lo que distingue modo escritorio de modo gamepad.
    seg = segundos or 6
    print('  escuchando %d s: TOCA LOS DOS TRACKPADS ahora...' % seg, file=sys.stderr)
    try:
        import evdev  # noqa: F401
        from evdev import ecodes as e
        import select as _sel
    except ImportError:
        print('  falta python-evdev', file=sys.stderr)
        return 1
    izq = der = 0
    t0 = time.time()
    try:
        while time.time() - t0 < seg:
            r, _, _ = _sel.select([dev.fd], [], [], 0.3)
            if not r:
                continue
            for ev in dev.read():
                if ev.type != e.EV_ABS or ev.value == 0:
                    continue
                if ev.code in (e.ABS_HAT0X, e.ABS_HAT0Y):
                    izq += 1
                elif ev.code in (e.ABS_HAT1X, e.ABS_HAT1Y):
                    der += 1
    except (OSError, IOError) as ex:
        print('  se perdio el mando: %s' % ex, file=sys.stderr)
    finally:
        try:
            dev.close()
        except Exception:
            pass
    print('  eventos: pad izquierdo %d, pad derecho %d' % (izq, der), file=sys.stderr)
    if izq or der:
        print('  CONCLUSION: el mando esta en MODO GAMEPAD y los pads se leen', file=sys.stderr)
        print('  bien por evdev. "Trackpad como raton" de WProton funcionara.', file=sys.stderr)
        print('  (En este modo el firmware NO mueve el puntero: eso es lo', file=sys.stderr)
        print('   normal, no un fallo.)', file=sys.stderr)
        return 0
    print('  CONCLUSION: el mando esta en MODO ESCRITORIO.', file=sys.stderr)
    print('  El driver no publica nada a proposito, y es el FIRMWARE el que', file=sys.stderr)
    print('  mueve el puntero: pad derecho = raton, pad izquierdo = rueda.', file=sys.stderr)
    print('  Si los trackpads no te responden estando asi, el mando se quedo', file=sys.stderr)
    print('  en modo gamepad o se lo cambio un programa por hidraw.', file=sys.stderr)
    print('  SE ARREGLA manteniendo pulsado OPCIONES (las tres rayas) medio', file=sys.stderr)
    print('  segundo: el mando vibra y cambia de modo. No hace falta WProton', file=sys.stderr)
    print('  ni sudo ni reiniciar.', file=sys.stderr)
    return 2


def probar(segundos=20):
    """Enseña los informes EN CRUDO de hidraw mientras tocas los trackpads.

    Es el diagnostico de bajo nivel, para cuando hace falta ver los bytes. Lo
    normal es usar "estado", que mira el camino bueno y dice que esta pasando.
    """
    fd, _ = abrir_mando()
    if fd is None:
        return 1
    print('', file=sys.stderr)
    print('  Mueve el dedo por el trackpad IZQUIERDO y mira si cambian los dos', file=sys.stderr)
    print('  primeros numeros. Luego el DERECHO, para los otros dos.', file=sys.stderr)
    print('  (%s segundos)' % segundos, file=sys.stderr)
    print('', file=sys.stderr)
    t0 = time.time()
    ultimo = None
    n = 0
    try:
        while time.time() - t0 < segundos:
            d = leer_informe(fd)
            if d is None or d is FUERA:
                continue
            izq = (_s16(d, OFF_IZQ_X), _s16(d, OFF_IZQ_Y))
            der = (_s16(d, OFF_DER_X), _s16(d, OFF_DER_Y))
            pres = (_u16(d, OFF_IZQ_P), _u16(d, OFF_DER_P))
            act = (izq, der, pres)
            if act == ultimo:
                continue
            ultimo = act
            n += 1
            # Solo cuando hay algo tocado o moviendose: si no, son cientos de
            # lineas iguales y no se ve nada.
            if izq == (0, 0) and der == (0, 0) and pres == (0, 0):
                continue
            print('izq=%6d,%6d  der=%6d,%6d  presion=%5d,%5d'
                  % (izq[0], izq[1], der[0], der[1], pres[0], pres[1]),
                  file=sys.stderr)
    except KeyboardInterrupt:
        pass
    finally:
        os.close(fd)
    if n == 0:
        print('trackpad: no llego ningun informe. El mando no es el esperado o',
              file=sys.stderr)
        print('trackpad: el formato de sus informes es otro.', file=sys.stderr)
        return 1
    print('', file=sys.stderr)
    print('trackpad: %d informes leidos.' % n, file=sys.stderr)
    return 0


# ---------------------------------------------------------------------------
# MODO RATON: el pad elegido mueve el puntero
# ---------------------------------------------------------------------------
def _mover(ui, e, dx, dy, div, restos):
    """Convierte un desplazamiento del dedo en movimiento del puntero.

    Los restos de la division se ACUMULAN en vez de perderse: sin eso, mover el
    dedo despacio se queda en cero y el puntero no sale hasta dar un aceleron.
    "restos" es una lista de dos para poder cambiarla desde aqui.
    """
    # Un salto enorme entre dos lecturas no es un movimiento: es que el dedo se
    # levanto y volvio a posar sin que nos llegara el 0,0. Se descarta en vez de
    # pegarle un tiron al puntero.
    if abs(dx) > 12000 or abs(dy) > 12000:
        return
    fx = dx / div + restos[0]
    fy = dy / div + restos[1]
    mx, my = int(fx), int(fy)
    restos[0], restos[1] = fx - mx, fy - my
    if mx:
        ui.write(e.EV_REL, e.REL_X, mx)
    if my:
        ui.write(e.EV_REL, e.REL_Y, my)
    if mx or my:
        ui.syn()


def _raton_virtual(evdev, e):
    """El raton por uinput con el que se mueve el puntero."""
    return evdev.UInput(
        {e.EV_REL: [e.REL_X, e.REL_Y],
         e.EV_KEY: [e.BTN_LEFT, e.BTN_RIGHT, e.BTN_MIDDLE]},
        name='WProton_Trackpad')


def raton_evdev(cual='izquierdo', sensibilidad=1.0, segundos=0):
    """El pad mueve el puntero, leyendo el mando por EVDEV. Este es el bueno.

    Devuelve 0 si funciono, 2 si no hay por donde leer -y entonces quien llama
    puede probar el respaldo por hidraw-, 1 si hubo un error de verdad.

    EL DEDO LEVANTADO SALE GRATIS: el driver publica 0,0 cuando el pad no esta
    tocado, asi que no hay que mirar la presion ni inventar umbrales. Eso si,
    un toque EXACTAMENTE en el centro tambien da 0,0; es un caso de un pixel y
    lo unico que pasa es que ese toque empieza a contar un instante despues.
    """
    try:
        import evdev
        from evdev import ecodes as e
    except ImportError:
        print('trackpad: falta python-evdev (va en el runtime de WProton)',
              file=sys.stderr)
        return 1
    dev = buscar_pads_evdev()
    if dev is None:
        print('trackpad: el mando no publica los trackpads por evdev',
              file=sys.stderr)
        return 2
    nx, ny = EJES_PAD.get(cual, EJES_PAD['izquierdo'])
    cx, cy = getattr(e, nx), getattr(e, ny)
    try:
        ui = _raton_virtual(evdev, e)
    except Exception as ex:
        print('trackpad: no se pudo crear el raton virtual: %s' % ex,
              file=sys.stderr)
        return 1
    print('trackpad: el pad %s mueve el puntero por evdev desde %s '
          '(sensibilidad %.2f)' % (cual, dev.path, sensibilidad), file=sys.stderr)
    # El pad va de -32767 a 32767 de lado a lado. Dividir entre 60 deja un
    # recorrido de pantalla comodo con un barrido del dedo.
    div = 60.0 / max(0.05, sensibilidad)
    restos = [0.0, 0.0]
    prev = None
    x = y = 0
    vistos = 0
    t0 = time.time()
    try:
        # SE ESPERA CON select Y NO SE BLOQUEA EN read_loop.
        #
        # Con read_loop, un mando que no manda nada -el caso normal en modo
        # escritorio- deja esto colgado para siempre sin poder ni mirar el
        # reloj ni avisar de que no llega nada.
        import select as _sel
        while True:
            if segundos and (time.time() - t0) > segundos:
                break
            r, _, _ = _sel.select([dev.fd], [], [], 0.5)
            if not r:
                continue
            for ev in dev.read():
                if ev.type == e.EV_ABS:
                    if ev.code == cx:
                        x = ev.value
                    elif ev.code == cy:
                        y = ev.value
                elif ev.type == e.EV_SYN and ev.code == e.SYN_REPORT:
                    vistos += 1
                    if x == 0 and y == 0:
                        prev = None
                        restos[0] = restos[1] = 0.0
                        continue
                    if prev is None:
                        prev = (x, y)
                        continue
                    # La Y del pad crece hacia ARRIBA y la de la pantalla hacia
                    # abajo, asi que va invertida.
                    _mover(ui, e, x - prev[0], -(y - prev[1]), div, restos)
                    prev = (x, y)
    except KeyboardInterrupt:
        pass
    except (OSError, IOError) as ex:
        print('trackpad: se perdio el mando (%s)' % ex, file=sys.stderr)
    finally:
        try:
            ui.close()
        except Exception:
            pass
        try:
            dev.close()
        except Exception:
            pass
    if vistos == 0:
        # Esto NO es un fallo nuestro: es el mando en modo escritorio, donde el
        # driver no publica nada a proposito. Y ahi el firmware YA mueve el
        # puntero con el pad derecho, asi que tampoco hace falta.
        print('trackpad: no llego ni un evento: el mando esta en modo '
              'escritorio', file=sys.stderr)
        print('trackpad: (manten pulsado OPCIONES medio segundo para pasar a '
              'modo gamepad)', file=sys.stderr)
        return 2
    return 0


def raton(cual='izquierdo', sensibilidad=1.0, segundos=0, control=True):
    """El pad mueve el puntero.

    control=True (lo normal): WProton TOMA EL CONTROL del mando -le apaga la
    emulacion del firmware y la devuelve al terminar-, asi que funciona cuando
    uno quiera, sin depender de mantener pulsado OPCIONES. Es lo que se pidio.

    control=False: no se le escribe nada al mando. Entonces solo hay pads que
    leer si el mando YA esta en modo gamepad, y se leen por evdev, que es el
    camino limpio.
    """
    if control:
        rc = raton_hidraw(cual, sensibilidad, segundos, control=True)
        if rc != 2:
            return rc
        # No se pudo ni abrir el mando para escribir: casi siempre permisos.
        # Queda el camino de solo lectura, que al menos funciona si el usuario
        # ha hecho el gesto de OPCIONES.
        print('trackpad: sin control del mando; se prueba a leerlo por evdev',
              file=sys.stderr)
        return raton_evdev(cual, sensibilidad, segundos)
    rc = raton_evdev(cual, sensibilidad, segundos)
    if rc != 2:
        return rc
    print('trackpad: se prueba el respaldo por hidraw, sin tocar el mando',
          file=sys.stderr)
    return raton_hidraw(cual, sensibilidad, segundos, control=False)


def raton_hidraw(cual='izquierdo', sensibilidad=1.0, segundos=0, control=False):
    """Mueve el puntero con un trackpad leyendo hidraw. RESPALDO.

    Solo se usa cuando el driver no publica los pads por evdev, que pasa cuando
    otro programa tiene abierto el hidraw del mando: entonces el driver retira
    su dispositivo de entrada. En el modo Juego, con Steam delante, es lo
    normal.

    OJO: abrir hidraw nos convierte a nosotros en ese "cliente", asi que puede
    hacer desaparecer el mando para el resto del sistema mientras esto corre.
    Por eso es el segundo camino y no el primero.

    COMO SE CONVIERTE UNA POSICION EN UN MOVIMIENTO
    ===============================================
    El trackpad da la posicion ABSOLUTA del dedo, no cuanto se ha movido. Un
    puntero necesita lo segundo, asi que se guarda la posicion anterior y se
    manda la DIFERENCIA, igual que el touchpad de un portatil.

    Y hay que soltar bien el dedo: al levantarlo y volver a posarlo en otro
    sitio, la diferencia seria un salto de media pantalla. Por eso, cuando el
    pad deja de estar tocado, se olvida la posicion anterior y el siguiente
    toque empieza de cero.
    """
    try:
        import evdev
        from evdev import ecodes as e
    except ImportError:
        print('trackpad: falta python-evdev (va en el runtime de WProton)',
              file=sys.stderr)
        return 1
    fd, nodo = abrir_mando(escribir=control)
    if fd is None:
        # 2 = "no he podido", para que quien llama pruebe otro camino.
        return 2
    # SE TOMA EL CONTROL ANTES DE LEER, Y SE DEVUELVE SIEMPRE.
    #
    # El "siempre" es lo importante y hay que montarlo ANTES de entrar al
    # bucle: WProton para esto con una señal (SIGTERM), y sin atenderla el
    # proceso muere sin devolver nada y los trackpads se quedan muertos.
    tomado = False
    if control:
        tomado = lagarto_apagar(fd)
        if not tomado:
            print('trackpad: no se pudo apagar la emulacion del firmware',
                  file=sys.stderr)
    # DESDE AQUI, TODO VA DENTRO DE UN SOLO try/finally.
    #
    # LA PRUEBA QUE LO DESTAPO: antes el camino era "tomar el control, poner
    # los manejadores de señal, crear el raton virtual, y despues un try con el
    # bucle". Los dos pasos del medio pueden fallar -signal.signal() no
    # funciona fuera del hilo principal, y el raton virtual necesita
    # /dev/uinput-, y si fallaban se salia por un return SIN DEVOLVER el mando:
    # trackpads muertos y ni una pista de por que.
    #
    # Ahora el "finally" que devuelve el mando envuelve TODO lo que viene
    # despues de tomarlo. No hay ningun camino de salida que se lo salte.
    try:
        return _raton_hidraw_bucle(fd, evdev, e, cual, sensibilidad, segundos,
                                   control, nodo)
    finally:
        if tomado:
            try:
                lagarto_encender(fd)
            except Exception:
                pass
        try:
            os.close(fd)
        except OSError:
            pass


def _raton_hidraw_bucle(fd, evdev, e, cual, sensibilidad, segundos, control,
                        nodo=None):
    """El bucle de lectura. Quien llama se encarga de devolver el mando."""

    def _devolver(*_):
        # Al recibir la señal se sale ORDENADAMENTE: el SystemExit sube hasta
        # el try/finally de arriba, que es el que devuelve el mando. Asi no hay
        # dos sitios haciendo lo mismo.
        raise SystemExit(0)

    if control:
        try:
            import signal as _sig
            _sig.signal(_sig.SIGTERM, _devolver)
            _sig.signal(_sig.SIGINT, _devolver)
            _sig.signal(_sig.SIGHUP, _devolver)
        except (ValueError, OSError) as ex:
            # No es motivo para abandonar: se sigue, y el mando se devolvera
            # igual por el camino normal o al cerrarse el fd.
            print('trackpad: no se pudieron atender las señales (%s)' % ex,
                  file=sys.stderr)
    ox, oy = (OFF_IZQ_X, OFF_IZQ_Y) if cual == 'izquierdo' else (OFF_DER_X, OFF_DER_Y)
    op = OFF_IZQ_P if cual == 'izquierdo' else OFF_DER_P
    try:
        ui = _raton_virtual(evdev, e)
    except Exception as ex:
        print('trackpad: no se pudo crear el raton virtual: %s' % ex,
              file=sys.stderr)
        return 1
    print('trackpad: el pad %s mueve el puntero por hidraw (sensibilidad %.2f)'
          % (cual, sensibilidad), file=sys.stderr)
    prev = None
    t0 = time.time()
    # El pad va de -32767 a 32767 de lado a lado. Dividir entre 60 deja un
    # recorrido de pantalla comodo con un barrido del dedo.
    div = 60.0 / max(0.05, sensibilidad)
    # LAS CUENTAS SON LAS MISMAS QUE EN EL CAMINO DE EVDEV, y se hacen en el
    # mismo sitio (_mover) a proposito: dos copias de esto acabarian
    # comportandose distinto, y entonces "el puntero va raro" dependeria de por
    # donde se este leyendo el mando, que es lo peor para diagnosticar.
    restos = [0.0, 0.0]
    # CUANTOS INFORMES BUENOS HAN LLEGADO.
    #
    # Sin esto, elegir mal la interfaz del mando era invisible: se leia para
    # siempre, se descartaba todo por no casar la cabecera y el puntero no se
    # movia ni un pixel, SIN UN SOLO ERROR EN EL REGISTRO. Eso es justo lo que
    # pasaba, y lo que hacia falta para notarlo es contar y avisar.
    buenos = 0
    sueltos = 0
    avisado = False
    try:
        while True:
            if segundos and (time.time() - t0) > segundos:
                break
            d = leer_informe(fd)
            if d is None:
                if (not avisado and not buenos
                        and (time.time() - t0) > ESPERA_AVISO):
                    avisado = True
                    print('trackpad: AVISO: %.0f s leyendo %s y no ha llegado '
                          'NI UN informe de estado del mando (se han '
                          'descartado %d trozos por no tener la cabecera '
                          '01 00 09). Casi seguro que la interfaz elegida no '
                          'es la del mando.'
                          % (ESPERA_AVISO, nodo or '?', sueltos),
                          file=sys.stderr)
                continue
            if d is FUERA:
                sueltos += 1
                continue
            buenos += 1
            x, y = _s16(d, ox), _s16(d, oy)
            p = _u16(d, op)
            tocado = (p > 0) or (x != 0) or (y != 0)
            if not tocado:
                prev = None
                restos[0] = restos[1] = 0.0
                continue
            if prev is None:
                prev = (x, y)
                continue
            # La Y del pad crece hacia ARRIBA y la de la pantalla hacia abajo.
            _mover(ui, e, x - prev[0], -(y - prev[1]), div, restos)
            prev = (x, y)
    except KeyboardInterrupt:
        pass
    finally:
        try:
            ui.close()
        except Exception:
            pass
    if not buenos:
        # 2 = "no he podido": quien llama probara el camino de evdev.
        print('trackpad: no llego ni un informe de estado por hidraw (%d '
              'trozos descartados); se deja este camino' % sueltos,
              file=sys.stderr)
        return 2
    print('trackpad: %d informes de estado leidos por hidraw' % buenos,
          file=sys.stderr)
    return 0


def main():
    args = sys.argv[1:]
    modo = args[0] if args else 'estado'
    if modo == 'estado':
        seg = int(args[1]) if len(args) > 1 else 0
        return estado(seg)
    if modo == 'probar':
        seg = int(args[1]) if len(args) > 1 else 20
        return probar(seg)
    if modo == 'raton':
        cual = args[1] if len(args) > 1 else 'izquierdo'
        sens = float(args[2]) if len(args) > 2 else 1.0
        seg = int(args[3]) if len(args) > 3 else 0
        # El cuarto argumento apaga el tomar el control, para quien NO quiera
        # que WProton le escriba al mando.
        ctl = (args[4] if len(args) > 4 else '1') not in ('0', 'no')
        return raton(cual, sens, seg, ctl)
    if modo == 'lagarto':
        # Encender y apagar la emulacion del firmware A MANO, sin mover el
        # puntero: es el "activarlos y desactivarlos cuando queramos" en su
        # forma mas simple.
        #
        # OJO: esto deja el mando como se le diga y sale. Nadie lo devuelve
        # despues, que es justo lo que se pide aqui; el camino de "raton" si
        # lo devuelve al terminar.
        que = args[1] if len(args) > 1 else 'estado'
        if que not in ('on', 'off'):
            print('uso: trackpad.py lagarto on|off', file=sys.stderr)
            return 2
        fd, _ = abrir_mando(escribir=True)
        if fd is None:
            return 1
        try:
            ok = lagarto_encender(fd) if que == 'on' else lagarto_apagar(fd)
        finally:
            os.close(fd)
        return 0 if ok else 1
    if modo == 'buscar':
        n = buscar_deck()
        if n:
            print(n)
            return 0
        return 1
    print('uso: trackpad.py [estado [seg] | probar [seg] | lagarto on|off '
          '| raton [izquierdo|derecho] [sens] [seg] [control] | buscar]',
          file=sys.stderr)
    return 2


if __name__ == '__main__':
    sys.exit(main())
