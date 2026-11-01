# WProton - montar una imagen de disco SIN TOCAR EL SISTEMA
#
# Copyright (C) 2026  stshunz y colaboradores
#
# Este programa es software libre: puedes redistribuirlo y/o modificarlo bajo
# los terminos de la Licencia Publica General GNU (GPL), version 3 o
# posterior, publicada por la Free Software Foundation.
#
# Se distribuye SIN NINGUNA GARANTIA. Ver <https://www.gnu.org/licenses/>.
#
# ===========================================================================
# POR QUE EXISTE ESTO
# ===========================================================================
#
# Para instalar un juego desde una imagen hay que poder LEERLA. Habia tres
# caminos y los tres tenian pegas:
#
#   fuseiso   bien: monta bajo $HOME y no se entera nadie.
#             mal:  hay que tenerlo, y si no, bajarlo.
#   udisks    bien: lo monta el kernel, entiende todo.
#             mal:  INTERFIERE CON EL SISTEMA. Crea un dispositivo de loop,
#                   registra el montaje en /run/media y la imagen APARECE EN
#                   DOLPHIN como un disco mas. Dani lo vio: "sigue apareciendo
#                   en Dolphin, tendriamos que buscar una alternativa portable
#                   y que no interfiera en el sistema".
#   extraer   bien: siempre funciona.
#             mal:  cuatro u ocho gigas al disco y la espera.
#
# Esto es la alternativa portable: un sistema de ficheros de solo lectura,
# escrito aqui, que monta la imagen BAJO $HOME y se desmonta con fusermount.
# No instala nada, no necesita permisos, no crea dispositivos y no sale en
# ningun gestor de archivos.
#
# ===========================================================================
# COMO FUNCIONA, Y POR QUE NO USA libfuse
# ===========================================================================
#
# Un sistema de ficheros FUSE es un programa que habla con el kernel por
# /dev/fuse. Lo normal es hacerlo con libfuse, pero eso seria otra biblioteca
# que tener -justo lo que se quiere evitar-. Aqui se habla el protocolo del
# kernel directamente, que para una imagen de SOLO LECTURA son nueve
# operaciones contadas.
#
# Lo unico que hace falta de fuera es "fusermount3" (o "fusermount"), que es
# quien tiene permiso para montar. Esta en cualquier equipo que use FUSE, y
# WProton ya depende de el para montar los .wsquashfs: si no estuviera, no
# habria ni biblioteca de juegos.
#
# El reparto de trabajo con fusermount es el de siempre: se le pasa un extremo
# de un socket, el monta y nos devuelve por ahi el descriptor de /dev/fuse.
#
# ===========================================================================
# QUE ENTIENDE DE UNA IMAGEN
# ===========================================================================
#
#   ISO9660        el formato de siempre, el que lleva todo CD.
#   Joliet         los nombres largos y con acentos, de Windows. Si la imagen
#                  lo trae, manda este: es el que vio quien la grabo.
#   Rock Ridge     los nombres largos de Unix. Se usa si no hay Joliet.
#
# Lo que NO entiende es UDF puro -algunos DVD modernos-. Se nota enseguida
# (la imagen monta vacia, o no monta) y ahi WProton tira de extraer con 7zz,
# que si lo entiende. Lo mismo que se hacia con fuseiso, que tampoco lo lee.
#
# ===========================================================================
# TRES MODOS, Y EL TERCERO SALVA LOS MUEBLES
# ===========================================================================
#
#   listar <iso>            escribe el arbol. Sirve para mirar sin montar.
#   extraer <iso> <dest>    saca el contenido SIN 7zz y sin nada instalado.
#   montar <iso> <punto>    lo de arriba.
#
# "extraer" esta porque conviene no depender de una sola cosa: si FUSE no
# estuviera disponible en algun equipo, sigue habiendo forma de abrir la
# imagen sin pedirle nada al sistema.
import os
import sys
import stat
import errno
import struct
import socket
import ctypes
import threading

SECTOR = 2048

# --- Descriptores de volumen -------------------------------------------------
VD_PRIMARIA = 1
VD_SUPLEMENTARIA = 2
VD_FIN = 255

# Las tres secuencias de escape que declaran Joliet (UCS-2 niveles 1, 2 y 3).
JOLIET_ESC = (b'%/@', b'%/C', b'%/E')


class ErrorISO(Exception):
    pass


class Nodo(object):
    """Un fichero o una carpeta de la imagen."""
    __slots__ = ('nombre', 'lba', 'tam', 'es_dir', 'hijos', 'padre', 'ino')

    def __init__(self, nombre, lba, tam, es_dir):
        self.nombre = nombre
        self.lba = lba
        self.tam = tam
        self.es_dir = es_dir
        self.hijos = None      # se lee cuando hace falta, no al abrir
        self.padre = None
        self.ino = 0


def _nombre_limpio(crudo, joliet):
    """El nombre tal como lo vera el usuario."""
    if joliet:
        try:
            n = crudo.decode('utf-16-be', 'replace')
        except Exception:
            n = crudo.decode('latin-1', 'replace')
    else:
        n = crudo.decode('latin-1', 'replace')
    # "FICHERO.TXT;1" -> "FICHERO.TXT": el ";1" es el numero de version de
    # ISO9660 y no lo quiere ver nadie.
    pos = n.rfind(';')
    if pos > 0:
        n = n[:pos]
    # "LEEME." -> "LEEME": un punto final suelto es relleno del formato.
    if n.endswith('.'):
        n = n[:-1]
    return n


def _rock_ridge_nombre(sistema):
    """El nombre largo de Rock Ridge (entrada "NM"), si lo hay.

    El area de uso del sistema va detras del nombre en cada registro. Rock
    Ridge mete ahi entradas de dos letras con su longitud, y NM es el nombre
    de verdad: sin el, un fichero llamado "Mi Juego.exe" se ve como
    "MI_JUEGO.EXE" en mayusculas y con guiones bajos.
    """
    partes = []
    i = 0
    n = len(sistema)
    while i + 4 <= n:
        etiqueta = sistema[i:i + 2]
        largo = sistema[i + 2]
        if largo < 3 or i + largo > n:
            break
        if etiqueta == b'NM':
            # byte de banderas: el bit 0 dice "sigue en la siguiente entrada"
            banderas = sistema[i + 4] if largo > 4 else 0
            partes.append(sistema[i + 5:i + largo])
            if not (banderas & 0x01):
                break
        i += largo
    if not partes:
        return None
    try:
        return b''.join(partes).decode('utf-8', 'replace')
    except Exception:
        return None


class ImagenISO(object):
    """Lee una imagen ISO9660, con Joliet o Rock Ridge si los trae."""

    def __init__(self, ruta):
        self.ruta = ruta
        self.fh = open(ruta, 'rb', buffering=0)
        self.joliet = False
        self.etiqueta = ''
        self.raiz = None
        self._lock = threading.Lock()
        self._leer_descriptores()

    # -- lectura cruda --------------------------------------------------------
    def _leer(self, desplazamiento, cuantos):
        with self._lock:
            self.fh.seek(desplazamiento)
            return self.fh.read(cuantos)

    def _sector(self, n):
        return self._leer(n * SECTOR, SECTOR)

    def _leer_descriptores(self):
        """Busca la descripcion del volumen y se queda con la mejor.

        Se prefiere Joliet cuando esta: trae los nombres tal como se grabaron,
        con sus mayusculas y sus acentos.
        """
        primaria = None
        joliet = None
        n = 16
        while n < 512:                      # un tope: no se recorre la imagen
            try:
                d = self._sector(n)
            except Exception:
                break
            if len(d) < SECTOR or d[1:6] != b'CD001':
                break
            tipo = d[0]
            if tipo == VD_FIN:
                break
            if tipo == VD_PRIMARIA and primaria is None:
                primaria = d
            elif tipo == VD_SUPLEMENTARIA and joliet is None:
                if d[88:91] in JOLIET_ESC:
                    joliet = d
            n += 1
        descriptor = joliet if joliet is not None else primaria
        if descriptor is None:
            raise ErrorISO('no es una imagen ISO9660 (no aparece "CD001")')
        self.joliet = joliet is not None
        etq = descriptor[40:72]
        if self.joliet:
            self.etiqueta = etq.decode('utf-16-be', 'replace').strip()
        else:
            self.etiqueta = etq.decode('latin-1', 'replace').strip()
        # El registro de la carpeta raiz vive dentro del descriptor, en el 156.
        reg = descriptor[156:156 + 34]
        lba = struct.unpack('<I', reg[2:6])[0]
        tam = struct.unpack('<I', reg[10:14])[0]
        self.raiz = Nodo('', lba, tam, True)
        self.raiz.ino = 1

    # -- arbol ----------------------------------------------------------------
    def hijos(self, nodo):
        """Los hijos de una carpeta. Se leen la primera vez y se guardan."""
        if nodo.hijos is not None:
            return nodo.hijos
        hijos = {}
        if not nodo.es_dir:
            nodo.hijos = hijos
            return hijos
        datos = self._leer(nodo.lba * SECTOR, nodo.tam)
        i = 0
        n = len(datos)
        while i < n:
            largo = datos[i]
            if largo == 0:
                # Un registro no cruza el limite de un sector: cuando queda
                # relleno, se salta al siguiente.
                salto = SECTOR - (i % SECTOR)
                i += salto
                continue
            if i + largo > n:
                break
            reg = datos[i:i + largo]
            i += largo
            if len(reg) < 33:
                continue
            lba = struct.unpack('<I', reg[2:6])[0]
            tam = struct.unpack('<I', reg[10:14])[0]
            banderas = reg[25]
            largo_nombre = reg[32]
            crudo = reg[33:33 + largo_nombre]
            # Las dos entradas especiales: "." y ".." van con un nombre de un
            # solo byte, 0 y 1.
            if largo_nombre == 1 and crudo in (b'\x00', b'\x01'):
                continue
            # El area del sistema empieza detras del nombre, con relleno si el
            # nombre ocupa un numero impar de bytes.
            inicio_sis = 33 + largo_nombre
            if largo_nombre % 2 == 0:
                inicio_sis += 1
            nombre = None
            if not self.joliet and inicio_sis < len(reg):
                nombre = _rock_ridge_nombre(reg[inicio_sis:])
            if not nombre:
                nombre = _nombre_limpio(crudo, self.joliet)
            if not nombre:
                continue
            hijo = Nodo(nombre, lba, tam, bool(banderas & 0x02))
            hijo.padre = nodo
            hijos[nombre] = hijo
        nodo.hijos = hijos
        return hijos

    def buscar(self, ruta):
        """El nodo que hay en esa ruta, o None."""
        nodo = self.raiz
        for parte in ruta.strip('/').split('/'):
            if not parte:
                continue
            hijos = self.hijos(nodo)
            nodo = hijos.get(parte)
            if nodo is None:
                # Las imagenes se graban con las mayusculas que sea y Windows
                # nunca las distinguio: se prueba tambien sin distinguirlas.
                bajo = parte.lower()
                for k, v in hijos.items():
                    if k.lower() == bajo:
                        nodo = v
                        break
            if nodo is None:
                return None
        return nodo

    def leer_fichero(self, nodo, desplazamiento, cuantos):
        if nodo.es_dir:
            return b''
        if desplazamiento >= nodo.tam:
            return b''
        cuantos = min(cuantos, nodo.tam - desplazamiento)
        return self._leer(nodo.lba * SECTOR + desplazamiento, cuantos)

    def recorrer(self, nodo=None, prefijo=''):
        """Todo el arbol, de arriba abajo: (ruta, nodo)."""
        if nodo is None:
            nodo = self.raiz
        for nombre, hijo in sorted(self.hijos(nodo).items()):
            ruta = prefijo + '/' + nombre
            yield ruta, hijo
            if hijo.es_dir:
                for x in self.recorrer(hijo, ruta):
                    yield x

    def cerrar(self):
        try:
            self.fh.close()
        except Exception:
            pass


# ===========================================================================
# EL PROTOCOLO DE /dev/fuse
# ===========================================================================
#
# Las estructuras son las de fuse_kernel.h. Van en el orden y con el tamaño
# que espera el kernel, asi que NO SE TOCAN sin mirar esa cabecera.
FUSE_LOOKUP = 1
FUSE_FORGET = 2
FUSE_GETATTR = 3
FUSE_READLINK = 5
FUSE_OPEN = 14
FUSE_READ = 15
FUSE_STATFS = 17
FUSE_RELEASE = 18
FUSE_FSYNC = 20
FUSE_GETXATTR = 22
FUSE_LISTXATTR = 23
FUSE_FLUSH = 25
FUSE_INIT = 26
FUSE_OPENDIR = 27
FUSE_READDIR = 28
FUSE_RELEASEDIR = 29
FUSE_ACCESS = 34
FUSE_DESTROY = 38
FUSE_BATCH_FORGET = 42
FUSE_READDIRPLUS = 44
FUSE_LSEEK = 46

CAB_ENTRADA = struct.Struct('<IIQQIIII')     # fuse_in_header, 40 bytes
CAB_SALIDA = struct.Struct('<IiQ')           # fuse_out_header, 16 bytes

# fuse_attr: 88 bytes
ATTR = struct.Struct('<QQQQQQIIIIIIIIII')


def _attr(ino, modo, tam, nlink, uid, gid, bloque=SECTOR):
    return ATTR.pack(
        ino, tam, (tam + 511) // 512,       # ino, size, blocks
        0, 0, 0,                            # atime, mtime, ctime
        0, 0, 0,                            # *nsec
        modo, nlink, uid, gid,
        0,                                  # rdev
        bloque,
        0)                                  # flags


class ServidorFUSE(object):
    """Sirve la imagen por /dev/fuse. Solo lectura y nada mas."""

    def __init__(self, imagen, fd, depurar=False):
        self.img = imagen
        self.fd = fd
        self.depurar = depurar
        self.uid = os.getuid()
        self.gid = os.getgid()
        # El kernel habla de "nodeid"; aqui cada nodo tiene el suyo. El 1 es
        # siempre la raiz, por definicion del protocolo.
        self.por_id = {1: imagen.raiz}
        self.siguiente = 2
        self.tam_max = 128 * 1024
        self.fin = False

    # -- utilidades -----------------------------------------------------------
    def _id_de(self, nodo):
        if nodo.ino:
            return nodo.ino
        nodo.ino = self.siguiente
        self.siguiente += 1
        self.por_id[nodo.ino] = nodo
        return nodo.ino

    def _modo(self, nodo):
        if nodo.es_dir:
            return stat.S_IFDIR | 0o555
        return stat.S_IFREG | 0o444

    def _attr_de(self, nodo):
        return _attr(self._id_de(nodo), self._modo(nodo),
                     0 if nodo.es_dir else nodo.tam,
                     2 if nodo.es_dir else 1, self.uid, self.gid)

    def _responder(self, unico, datos=b'', error=0):
        cab = CAB_SALIDA.pack(len(datos) + CAB_SALIDA.size, error, unico)
        try:
            os.write(self.fd, cab + datos)
        except OSError:
            pass

    def _error(self, unico, err):
        self._responder(unico, b'', -err)

    # -- bucle ----------------------------------------------------------------
    def servir(self):
        while not self.fin:
            try:
                datos = os.read(self.fd, self.tam_max + 4096)
            except OSError as e:
                if e.errno in (errno.EINTR, errno.EAGAIN):
                    continue
                if e.errno == errno.ENODEV:    # desmontado
                    break
                break
            if not datos:
                break
            try:
                self._atender(datos)
            except Exception as e:
                if self.depurar:
                    sys.stderr.write('isofuse: %s\n' % e)

    def _atender(self, datos):
        largo, opcode, unico, nodeid, uid, gid, pid, _ = \
            CAB_ENTRADA.unpack_from(datos, 0)
        cuerpo = datos[CAB_ENTRADA.size:largo]
        f = self._ops.get(opcode)
        if f is None:
            self._error(unico, errno.ENOSYS)
            return
        f(self, unico, nodeid, cuerpo)

    # -- operaciones ----------------------------------------------------------
    def op_init(self, unico, nodeid, cuerpo):
        major, minor = struct.unpack_from('<II', cuerpo, 0)
        # Se contesta con la version del kernel si es menor que la nuestra:
        # asi vale igual con uno viejo que con uno nuevo.
        nuestro_minor = min(minor, 31)
        # fuse_init_out, en su forma larga (minor >= 23). Los campos de mas
        # los ignora un kernel antiguo.
        salida = struct.pack('<IIIIHHIIHHI',
                             7, nuestro_minor,
                             0,          # max_readahead
                             0,          # flags
                             0, 0,       # max_background, congestion_threshold
                             self.tam_max,
                             1,          # time_gran
                             0, 0,       # max_pages, map_alignment
                             0)          # flags2
        salida += b'\x00' * 28           # unused[7]
        self._responder(unico, salida)

    def op_destroy(self, unico, nodeid, cuerpo):
        self.fin = True
        self._responder(unico)

    def op_lookup(self, unico, nodeid, cuerpo):
        padre = self.por_id.get(nodeid)
        if padre is None or not padre.es_dir:
            self._error(unico, errno.ENOENT)
            return
        nombre = cuerpo.split(b'\x00', 1)[0].decode('utf-8', 'replace')
        hijos = self.img.hijos(padre)
        nodo = hijos.get(nombre)
        if nodo is None:
            bajo = nombre.lower()
            for k, v in hijos.items():
                if k.lower() == bajo:
                    nodo = v
                    break
        if nodo is None:
            self._error(unico, errno.ENOENT)
            return
        # fuse_entry_out: nodeid, generation, entry_valid, attr_valid,
        #                 entry_valid_nsec, attr_valid_nsec, attr
        ent = struct.pack('<QQQQII', self._id_de(nodo), 0, 3600, 3600, 0, 0)
        self._responder(unico, ent + self._attr_de(nodo))

    def op_forget(self, unico, nodeid, cuerpo):
        # No se contesta a FORGET: lo dice el protocolo. Y no se olvida nada,
        # porque el arbol de una imagen es pequeño y no cambia.
        pass

    def op_getattr(self, unico, nodeid, cuerpo):
        nodo = self.por_id.get(nodeid)
        if nodo is None:
            self._error(unico, errno.ENOENT)
            return
        # fuse_attr_out: attr_valid, attr_valid_nsec, dummy, attr
        self._responder(unico,
                        struct.pack('<QII', 3600, 0, 0) + self._attr_de(nodo))

    def op_open(self, unico, nodeid, cuerpo):
        nodo = self.por_id.get(nodeid)
        if nodo is None:
            self._error(unico, errno.ENOENT)
            return
        if nodo.es_dir:
            self._error(unico, errno.EISDIR)
            return
        banderas = struct.unpack_from('<I', cuerpo, 0)[0]
        # SOLO LECTURA, y se dice que no: una imagen es el original del juego.
        if banderas & (os.O_WRONLY | os.O_RDWR):
            self._error(unico, errno.EROFS)
            return
        # fuse_open_out: fh, open_flags, padding
        self._responder(unico, struct.pack('<QII', nodeid, 0, 0))

    def op_read(self, unico, nodeid, cuerpo):
        nodo = self.por_id.get(nodeid)
        if nodo is None:
            self._error(unico, errno.ENOENT)
            return
        fh, desp, tam = struct.unpack_from('<QQI', cuerpo, 0)
        self._responder(unico, self.img.leer_fichero(nodo, desp, tam))

    def op_release(self, unico, nodeid, cuerpo):
        self._responder(unico)

    def op_opendir(self, unico, nodeid, cuerpo):
        nodo = self.por_id.get(nodeid)
        if nodo is None or not nodo.es_dir:
            self._error(unico, errno.ENOTDIR)
            return
        self._responder(unico, struct.pack('<QII', nodeid, 0, 0))

    def op_readdir(self, unico, nodeid, cuerpo):
        nodo = self.por_id.get(nodeid)
        if nodo is None or not nodo.es_dir:
            self._error(unico, errno.ENOTDIR)
            return
        fh, desp, tam = struct.unpack_from('<QQI', cuerpo, 0)
        entradas = [('.', nodo), ('..', nodo.padre or nodo)]
        entradas += sorted(self.img.hijos(nodo).items())
        salida = b''
        i = 0
        for nombre, hijo in entradas:
            i += 1
            if i <= desp:              # ya se mando en una vuelta anterior
                continue
            nb = nombre.encode('utf-8')
            # fuse_dirent: ino, off, namelen, type + nombre, en multiplos de 8
            trozo = struct.pack('<QQII', self._id_de(hijo), i, len(nb),
                                4 if hijo.es_dir else 8) + nb
            relleno = (8 - (len(trozo) % 8)) % 8
            trozo += b'\x00' * relleno
            if len(salida) + len(trozo) > tam:
                break
            salida += trozo
        self._responder(unico, salida)

    def op_releasedir(self, unico, nodeid, cuerpo):
        self._responder(unico)

    def op_statfs(self, unico, nodeid, cuerpo):
        total = (os.path.getsize(self.img.ruta) + SECTOR - 1) // SECTOR
        # fuse_kstatfs: blocks, bfree, bavail, files, ffree, bsize, namelen,
        #               frsize, padding, spare[6]
        self._responder(unico,
                        struct.pack('<QQQQQIIII',
                                    total, 0, 0, len(self.por_id), 0,
                                    SECTOR, 255, SECTOR, 0)
                        + b'\x00' * 24)

    def op_nosoportado(self, unico, nodeid, cuerpo):
        self._error(unico, errno.ENOSYS)

    def op_vacio(self, unico, nodeid, cuerpo):
        self._responder(unico)

    _ops = {
        FUSE_INIT: op_init,
        FUSE_DESTROY: op_destroy,
        FUSE_LOOKUP: op_lookup,
        FUSE_FORGET: op_forget,
        FUSE_BATCH_FORGET: op_forget,
        FUSE_GETATTR: op_getattr,
        FUSE_OPEN: op_open,
        FUSE_READ: op_read,
        FUSE_RELEASE: op_release,
        FUSE_OPENDIR: op_opendir,
        FUSE_READDIR: op_readdir,
        FUSE_RELEASEDIR: op_releasedir,
        FUSE_STATFS: op_statfs,
        FUSE_FLUSH: op_vacio,
        FUSE_FSYNC: op_vacio,
        FUSE_ACCESS: op_vacio,
        FUSE_GETXATTR: op_nosoportado,
        FUSE_LISTXATTR: op_nosoportado,
        FUSE_READLINK: op_nosoportado,
        FUSE_READDIRPLUS: op_nosoportado,
        FUSE_LSEEK: op_nosoportado,
    }


def _buscar_fusermount():
    nombres = ('fusermount3', 'fusermount')
    rutas = os.environ.get('PATH', '/usr/bin:/bin').split(':')
    # Y los sitios de siempre, por si PATH viniera recortado.
    rutas += ['/usr/bin', '/bin', '/usr/local/bin', '/sbin', '/usr/sbin']
    for n in nombres:
        for d in rutas:
            p = os.path.join(d, n)
            if os.path.isfile(p) and os.access(p, os.X_OK):
                return p
    return None


def montar_fd(punto, nombre_fs='wproton-iso'):
    """Le pide a fusermount que monte y devuelve el descriptor de /dev/fuse.

    Es el reparto de siempre: fusermount es quien tiene permiso para montar,
    monta, y nos pasa el descriptor por un socket. Asi no hace falta ser root
    ni instalar nada.
    """
    prog = _buscar_fusermount()
    if not prog:
        raise ErrorISO('no se encuentra fusermount (ni fusermount3)')
    padre, hijo = socket.socketpair(socket.AF_UNIX, socket.SOCK_STREAM)
    pid = os.fork()
    if pid == 0:                                   # ---- hijo
        try:
            padre.close()
            fd_hijo = hijo.fileno()
            os.set_inheritable(fd_hijo, True)
            entorno = dict(os.environ)
            entorno['_FUSE_COMMFD'] = str(fd_hijo)
            opciones = ('ro,nosuid,nodev,noatime,fsname=%s,subtype=isofuse'
                        % nombre_fs)
            os.execve(prog, [prog, '-o', opciones, '--', punto], entorno)
        except Exception:
            pass
        os._exit(127)
    # ---- padre
    hijo.close()
    try:
        datos, aux, banderas, _ = padre.recvmsg(1, socket.CMSG_SPACE(4))
        fd = -1
        for nivel, tipo, carga in aux:
            if nivel == socket.SOL_SOCKET and tipo == socket.SCM_RIGHTS:
                fd = struct.unpack('<i', carga[:4])[0]
                break
    finally:
        padre.close()
        try:
            os.waitpid(pid, 0)
        except Exception:
            pass
    if fd < 0:
        raise ErrorISO('fusermount no devolvio el descriptor (¿sin permiso '
                       'para /dev/fuse, o el punto de montaje no existe?)')
    return fd


def desmontar(punto):
    """Lo contrario. No hace falta para nada mas que para limpiar a mano."""
    prog = _buscar_fusermount()
    if not prog:
        return False
    return os.spawnv(os.P_WAIT, prog, [prog, '-u', punto]) == 0


def montar(ruta_iso, punto, depurar=False):
    img = ImagenISO(ruta_iso)
    if not os.path.isdir(punto):
        os.makedirs(punto, exist_ok=True)
    fd = montar_fd(punto, os.path.basename(ruta_iso)[:60] or 'iso')
    # Se avisa de que ya esta montada ANTES de ponerse a servir: quien nos
    # lanzo esta esperando para seguir, y si no, se queda mirando.
    sys.stdout.write('MONTADA %s\n' % punto)
    sys.stdout.flush()
    srv = ServidorFUSE(img, fd, depurar)
    try:
        srv.servir()
    finally:
        try:
            os.close(fd)
        except Exception:
            pass
        img.cerrar()
    return 0


def extraer(ruta_iso, destino):
    """Saca el contenido sin montar nada y sin 7zz."""
    img = ImagenISO(ruta_iso)
    n_fich = 0
    n_dir = 0
    os.makedirs(destino, exist_ok=True)
    for ruta, nodo in img.recorrer():
        fuera = os.path.join(destino, ruta.lstrip('/'))
        if nodo.es_dir:
            os.makedirs(fuera, exist_ok=True)
            n_dir += 1
            continue
        os.makedirs(os.path.dirname(fuera), exist_ok=True)
        with open(fuera, 'wb') as fh:
            desp = 0
            while desp < nodo.tam:
                trozo = img.leer_fichero(nodo, desp, 1024 * 1024)
                if not trozo:
                    break
                fh.write(trozo)
                desp += len(trozo)
        n_fich += 1
    img.cerrar()
    sys.stdout.write('EXTRAIDO %d fichero(s), %d carpeta(s)\n' % (n_fich, n_dir))
    return 0


def listar(ruta_iso):
    img = ImagenISO(ruta_iso)
    sys.stdout.write('etiqueta: %s\n' % img.etiqueta)
    sys.stdout.write('nombres: %s\n' % ('Joliet' if img.joliet else 'ISO9660/RockRidge'))
    for ruta, nodo in img.recorrer():
        sys.stdout.write('%s%s%s\n' % (ruta, '/' if nodo.es_dir else '',
                                       '' if nodo.es_dir else '  (%d)' % nodo.tam))
    img.cerrar()
    return 0


def main():
    if len(sys.argv) < 3:
        sys.stderr.write(
            'uso: isofuse.py montar <imagen> <punto>\n'
            '     isofuse.py extraer <imagen> <carpeta>\n'
            '     isofuse.py listar <imagen>\n'
            '     isofuse.py comprobar\n')
        return 2
    orden = sys.argv[1]
    try:
        if orden == 'listar':
            return listar(sys.argv[2])
        if orden == 'extraer':
            return extraer(sys.argv[2], sys.argv[3])
        if orden == 'montar':
            return montar(sys.argv[2], sys.argv[3],
                          os.environ.get('WP_ISOFUSE_DEPURAR') == '1')
    except ErrorISO as e:
        sys.stderr.write('isofuse: %s\n' % e)
        return 1
    except Exception as e:
        sys.stderr.write('isofuse: %s\n' % e)
        return 1
    sys.stderr.write('isofuse: orden desconocida: %s\n' % orden)
    return 2


if __name__ == '__main__':
    sys.exit(main())
