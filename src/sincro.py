# -*- coding: utf-8 -*-
# WPROTON_HELPER sincro.py PENDIENTE
"""Compartir copias de partidas entre equipos de la misma red.

QUE HACE Y QUE NO HACE

Hace: un equipo COMPARTE su carpeta de copias y otro se TRAE las que le
falten, eligiendo el usuario en que direccion va la cosa.

No hace: sincronizacion automatica en dos direcciones. Y es a proposito. Un
sincronizador generico resuelve los choques guardando los dos ficheros con
nombres distintos; para un documento vale, para una partida no sirve de nada,
porque el juego lee uno solo y tu no sabes cual es el bueno. El caso malo llega
solo: juegas en un equipo sin red, luego en el otro, y al reencontrarse uno
pisa al otro en silencio. Con una direccion explicita eso no puede pasar.

NUNCA SE PISA UNA COPIA MAS NUEVA. Si la de aqui es mas reciente que la de
alla, se salta y se dice. Para forzarlo hay que pedirlo aparte.

SEGURIDAD, LA JUSTA Y PROPORCIONADA

Esto vive en la red de casa y comparte partidas, no cuentas bancarias. Aun asi
no se deja abierto:

  - se sirve SOLO la carpeta de copias, y solo ficheros .zip de dentro; los
    nombres se limpian, asi que no se puede pedir ../../algo
  - hace falta un CODIGO de seis cifras que se enseña en el equipo que comparte
  - se sirve mientras el usuario lo tiene abierto, no como demonio

uso:
    sincro.py servir <carpeta> <puerto> <codigo>
    sincro.py listar <host> <puerto> <codigo>
    sincro.py traer  <host> <puerto> <codigo> <nombre> <destino>
    sincro.py comprobar
"""
import hashlib
import json
import os
import re
import sys
import threading
import time

try:
    from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
    from urllib.parse import urlparse, parse_qs, quote
    from urllib.request import urlopen
    from urllib.error import URLError, HTTPError
except ImportError:  # pragma: no cover
    sys.stderr.write("sincro: hace falta Python 3\n")
    sys.exit(2)

TROZO = 65536


def _limpia(nombre):
    """Deja un nombre de fichero sano: sin rutas ni sorpresas.

    Se quita todo lo que huela a directorio ANTES de mirar nada mas: es la
    unica forma de que un "..%2f..%2fetc%2fpasswd" no llegue a ninguna parte.
    """
    nombre = os.path.basename(nombre or '')
    if not nombre or nombre in ('.', '..'):
        return ''
    if not re.match(r'^[\w .()\[\]@+-]+\.zip$', nombre, re.UNICODE):
        return ''
    return nombre


def _indice(carpeta):
    """Que copias hay aqui: nombre, tamaño y fecha."""
    out = []
    try:
        for n in sorted(os.listdir(carpeta)):
            if not n.lower().endswith('.zip'):
                continue
            r = os.path.join(carpeta, n)
            if not os.path.isfile(r):
                continue
            st = os.stat(r)
            out.append({'nombre': n, 'bytes': st.st_size,
                        'fecha': int(st.st_mtime)})
    except OSError:
        pass
    return out


def _huella(ruta):
    h = hashlib.sha256()
    with open(ruta, 'rb') as fh:
        for t in iter(lambda: fh.read(TROZO), b''):
            h.update(t)
    return h.hexdigest()


VERSIONES = 5          # cuantas copias viejas se guardan de cada juego


def token_de(carpeta):
    """El token del servidor permanente, creado la primera vez.

    UN TOKEN FIJO EN UN FICHERO, NO UN CODIGO DE SEIS CIFRAS.

    El codigo corto vale para compartir un rato: lo lees en pantalla y lo
    tecleas. Un servidor que esta siempre encendido y que ademas ACEPTA
    SUBIDAS es otra cosa: quien llegue al puerto podria escribir en tus
    partidas. Asi que el token es largo, se genera solo y se copia una vez.
    """
    r = os.path.join(carpeta, '.token')
    try:
        with open(r) as fh:
            t = fh.read().strip()
        if t:
            return t
    except OSError:
        pass
    t = hashlib.sha256(os.urandom(32)).hexdigest()[:32]
    try:
        os.makedirs(carpeta, exist_ok=True)
        with open(r, 'w') as fh:
            fh.write(t)
        os.chmod(r, 0o600)
    except OSError:
        pass
    return t


def _guarda_version(carpeta, nombre):
    """Aparta la copia que habia antes de poner una nueva encima.

    POR QUE GUARDAR VIEJAS. Una partida corrupta no se nota el mismo dia: se
    nota tres dias despues, cuando ya la has subido y sobrescrito en todas
    partes. Con las ultimas VERSIONES copias, se vuelve atras.
    """
    act = os.path.join(carpeta, nombre)
    if not os.path.isfile(act):
        return
    vdir = os.path.join(carpeta, 'versiones')
    try:
        os.makedirs(vdir, exist_ok=True)
        base = nombre[:-4] if nombre.lower().endswith('.zip') else nombre
        sello = time.strftime('%Y%m%d-%H%M%S', time.localtime(os.stat(act).st_mtime))
        os.replace(act, os.path.join(vdir, '%s--%s.zip' % (base, sello)))
        viejas = sorted(n for n in os.listdir(vdir)
                        if n.startswith(base + '--') and n.endswith('.zip'))
        for n in viejas[:-VERSIONES]:
            try:
                os.unlink(os.path.join(vdir, n))
            except OSError:
                pass
    except OSError:
        pass


def _crea_handler(carpeta, codigo, permitir_subida=False):
    class H(BaseHTTPRequestHandler):
        protocol_version = 'HTTP/1.1'

        def log_message(self, *a):        # sin ruido en la salida
            pass

        def _no(self, cod, txt):
            cuerpo = txt.encode('utf-8')
            self.send_response(cod)
            self.send_header('Content-Type', 'text/plain; charset=utf-8')
            self.send_header('Content-Length', str(len(cuerpo)))
            self.end_headers()
            self.wfile.write(cuerpo)

        def do_GET(self):
            u = urlparse(self.path)
            q = parse_qs(u.query)
            # EL CODIGO SE MIRA ANTES QUE NADA, incluso antes del nombre: asi
            # no se puede averiguar que ficheros hay probando nombres.
            if (q.get('c', [''])[0] or '') != codigo:
                self._no(403, 'codigo incorrecto')
                return
            if u.path == '/indice':
                cuerpo = json.dumps(_indice(carpeta)).encode('utf-8')
                self.send_response(200)
                self.send_header('Content-Type', 'application/json')
                self.send_header('Content-Length', str(len(cuerpo)))
                self.end_headers()
                self.wfile.write(cuerpo)
                return
            if u.path == '/copia':
                n = _limpia(q.get('n', [''])[0])
                if not n:
                    self._no(400, 'nombre no valido')
                    return
                r = os.path.join(carpeta, n)
                if not os.path.isfile(r):
                    self._no(404, 'no esta')
                    return
                st = os.stat(r)
                self.send_response(200)
                self.send_header('Content-Type', 'application/zip')
                self.send_header('Content-Length', str(st.st_size))
                self.send_header('X-WProton-SHA256', _huella(r))
                self.end_headers()
                with open(r, 'rb') as fh:
                    for t in iter(lambda: fh.read(TROZO), b''):
                        self.wfile.write(t)
                return
            self._no(404, 'no')

        def do_PUT(self):
            if not permitir_subida:
                self._no(405, 'este servidor no acepta subidas')
                return
            u = urlparse(self.path)
            q = parse_qs(u.query)
            if (q.get('c', [''])[0] or '') != codigo:
                self._no(403, 'codigo incorrecto')
                return
            if u.path != '/subir':
                self._no(404, 'no')
                return
            n = _limpia(q.get('n', [''])[0])
            if not n:
                self._no(400, 'nombre no valido')
                return
            try:
                largo = int(self.headers.get('Content-Length', '0'))
            except ValueError:
                largo = 0
            if largo <= 0:
                self._no(400, 'sin contenido')
                return
            # NUNCA SE PISA UNA COPIA MAS NUEVA. Es la misma regla de siempre,
            # y aqui importa mas: al subir, el que se equivoca borra la partida
            # buena del otro sin enterarse.
            fecha_cli = q.get('f', ['0'])[0]
            try:
                fecha_cli = int(fecha_cli)
            except ValueError:
                fecha_cli = 0
            act = os.path.join(carpeta, n)
            if os.path.isfile(act) and fecha_cli:
                if os.stat(act).st_mtime > fecha_cli + 2:
                    self._no(409, 'aqui hay una copia mas nueva')
                    return
            tmp = os.path.join(carpeta, '.' + n + '.subiendo')
            leidos = 0
            try:
                with open(tmp, 'wb') as fh:
                    while leidos < largo:
                        t = self.rfile.read(min(TROZO, largo - leidos))
                        if not t:
                            break
                        fh.write(t)
                        leidos += len(t)
            except OSError as e:
                self._no(500, 'no se pudo escribir: %s' % e)
                return
            if leidos != largo:
                try:
                    os.unlink(tmp)
                except OSError:
                    pass
                self._no(400, 'llego a medias')
                return
            esperada = self.headers.get('X-WProton-SHA256', '')
            if esperada and _huella(tmp) != esperada:
                try:
                    os.unlink(tmp)
                except OSError:
                    pass
                self._no(400, 'llego corrupto')
                return
            _guarda_version(carpeta, n)
            os.replace(tmp, act)
            if fecha_cli:
                try:
                    os.utime(act, (fecha_cli, fecha_cli))
                except OSError:
                    pass
            self._no(200, 'guardada')
    return H


def servir(carpeta, puerto, codigo, hasta=None, subida=False):
    """Comparte la carpeta hasta que se corte el proceso."""
    if not os.path.isdir(carpeta):
        sys.stderr.write("sincro: no existe la carpeta %s\n" % carpeta)
        return 1
    srv = ThreadingHTTPServer(('0.0.0.0', int(puerto)),
                              _crea_handler(carpeta, codigo, subida))
    srv.daemon_threads = True
    print("sincro: compartiendo %s en el puerto %s" % (carpeta, puerto),
          flush=True)
    if hasta is not None:                 # solo para la autocomprobacion
        hilo = threading.Thread(target=srv.serve_forever, daemon=True)
        hilo.start()
        return srv
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        srv.server_close()
    return 0


def _url(host, puerto, ruta, codigo, extra=''):
    return 'http://%s:%s%s?c=%s%s' % (host, puerto, ruta, quote(codigo), extra)


def listar(host, puerto, codigo):
    try:
        with urlopen(_url(host, puerto, '/indice', codigo), timeout=10) as r:
            return json.loads(r.read().decode('utf-8'))
    except HTTPError as e:
        sys.stderr.write("sincro: el otro equipo dice: %s\n" % e.code)
    except (URLError, OSError, ValueError) as e:
        sys.stderr.write("sincro: no se pudo hablar con %s:%s (%s)\n"
                         % (host, puerto, e))
    return None


def traer(host, puerto, codigo, nombre, destino):
    """Se baja una copia y COMPRUEBA que ha llegado entera.

    Se escribe a un fichero temporal y solo se pone en su sitio si la huella
    cuadra: una copia de partidas a medias es peor que no tenerla, porque
    parece buena hasta que la restauras.
    """
    n = _limpia(nombre)
    if not n:
        sys.stderr.write("sincro: nombre no valido\n")
        return 1
    tmp = os.path.join(destino, '.' + n + '.parcial')
    try:
        os.makedirs(destino, exist_ok=True)
        with urlopen(_url(host, puerto, '/copia', codigo,
                          '&n=' + quote(n)), timeout=30) as r:
            esperada = r.headers.get('X-WProton-SHA256', '')
            with open(tmp, 'wb') as fh:
                while True:
                    t = r.read(TROZO)
                    if not t:
                        break
                    fh.write(t)
    except (HTTPError, URLError, OSError) as e:
        sys.stderr.write("sincro: fallo trayendo %s (%s)\n" % (n, e))
        try:
            os.unlink(tmp)
        except OSError:
            pass
        return 1
    real = _huella(tmp)
    if esperada and real != esperada:
        sys.stderr.write("sincro: %s llego corrupto, se descarta\n" % n)
        try:
            os.unlink(tmp)
        except OSError:
            pass
        return 1
    os.replace(tmp, os.path.join(destino, n))
    print(n, flush=True)
    return 0


def subir(host, puerto, codigo, ruta):
    """Deja una copia en el servidor. No pisa una mas nueva de alli."""
    n = _limpia(os.path.basename(ruta))
    if not n or not os.path.isfile(ruta):
        sys.stderr.write("sincro: no vale %s\n" % ruta)
        return 1
    st = os.stat(ruta)
    try:
        import urllib.request as _u
        with open(ruta, 'rb') as fh:
            pet = _u.Request(_url(host, puerto, '/subir', codigo,
                                  '&n=' + quote(n) + '&f=%d' % int(st.st_mtime)),
                             data=fh, method='PUT')
            pet.add_header('Content-Length', str(st.st_size))
            pet.add_header('X-WProton-SHA256', _huella(ruta))
            with _u.urlopen(pet, timeout=120) as r:
                r.read()
    except HTTPError as e:
        if e.code == 409:
            # NO ES UN FALLO: el servidor tiene algo mas nuevo. Se dice y se
            # sigue, que es justo lo que queremos que pase.
            print("mas-nueva-alli", flush=True)
            return 2
        sys.stderr.write("sincro: el servidor rechazo %s (%s)\n" % (n, e.code))
        return 1
    except (URLError, OSError) as e:
        sys.stderr.write("sincro: fallo subiendo %s (%s)\n" % (n, e))
        return 1
    print(n, flush=True)
    return 0


def unidad_systemd(carpeta, puerto, destino=None):
    """Escribe la unidad de systemd del servidor permanente.

    ES UNA UNIDAD DE USUARIO, NO DEL SISTEMA. No hace falta root, no toca nada
    fuera del home, y se quita borrando un fichero. Para guardar partidas en el
    ordenador de casa, pedir root seria desproporcionado.
    """
    py = sys.executable or 'python3'
    aqui = os.path.abspath(__file__)
    txt = """[Unit]
Description=WProton - servidor de partidas guardadas
After=network-online.target

[Service]
ExecStart=%s %s servidor %s %s
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
""" % (py, aqui, carpeta, puerto)
    if destino:
        os.makedirs(os.path.dirname(destino), exist_ok=True)
        with open(destino, 'w') as fh:
            fh.write(txt)
        print(destino, flush=True)
    else:
        sys.stdout.write(txt)
    return 0


def comparar(local, remoto):
    """Que traer y que no. Devuelve (traer, ya_estan, mas_nuevas_aqui).

    LA REGLA: se trae lo que aqui no esta, y lo que alla es MAS NUEVO. Lo que
    aqui es mas nuevo NO se toca y se avisa, que es justo el caso en que un
    sincronizador automatico te borraria la partida buena.
    """
    aqui = {e['nombre']: e for e in local}
    traerlas, iguales, nuestras = [], [], []
    for e in remoto:
        m = aqui.get(e['nombre'])
        if m is None:
            traerlas.append(e)
        elif e['fecha'] > m['fecha'] + 2:      # 2 s de margen por los relojes
            traerlas.append(e)
        elif m['fecha'] > e['fecha'] + 2:
            nuestras.append(e)
        else:
            iguales.append(e)
    return traerlas, iguales, nuestras


def comprobar():
    import tempfile
    fallos = [0]

    def chk(c, q):
        if not c:
            print("  FALLO: %s" % q)
            fallos[0] += 1

    d = tempfile.mkdtemp()
    orig = os.path.join(d, 'origen')
    dest = os.path.join(d, 'destino')
    os.makedirs(orig)
    os.makedirs(dest)
    with open(os.path.join(orig, 'Juego A.zip'), 'wb') as fh:
        fh.write(os.urandom(50000))
    with open(os.path.join(orig, 'Juego B.zip'), 'wb') as fh:
        fh.write(os.urandom(1000))
    open(os.path.join(orig, 'no_es_zip.txt'), 'w').write('nada')

    chk(_limpia('Juego A.zip') == 'Juego A.zip', "un nombre normal pasa")
    chk(_limpia('../../etc/passwd') == '', "una ruta hacia arriba se rechaza")
    chk(_limpia('/etc/passwd') == '', "una ruta absoluta se rechaza")
    chk(_limpia('cosa.sh') == '', "algo que no es .zip se rechaza")
    chk(_limpia('') == '', "un nombre vacio se rechaza")

    idx = _indice(orig)
    chk(len(idx) == 2, "el indice trae solo los .zip (salen %d)" % len(idx))

    srv = servir(orig, 0, '123456', hasta=True)
    puerto = srv.server_address[1]
    try:
        chk(listar('127.0.0.1', puerto, 'mal') is None,
            "con el codigo mal no se lista nada")
        rem = listar('127.0.0.1', puerto, '123456')
        chk(rem is not None and len(rem) == 2, "con el codigo bien se lista")
        chk(traer('127.0.0.1', puerto, '123456', 'Juego A.zip', dest) == 0,
            "se trae una copia")
        chk(os.path.isfile(os.path.join(dest, 'Juego A.zip')),
            "la copia esta en su sitio")
        chk(_huella(os.path.join(dest, 'Juego A.zip'))
            == _huella(os.path.join(orig, 'Juego A.zip')),
            "lo que llego es identico a lo que habia")
        chk(traer('127.0.0.1', puerto, '123456', '../../etc/passwd', dest) != 0,
            "no se puede traer algo de fuera de la carpeta")
        chk(traer('127.0.0.1', puerto, 'mal', 'Juego B.zip', dest) != 0,
            "con el codigo mal no se trae nada")
        chk(not os.path.exists(os.path.join(dest, '.Juego B.zip.parcial')),
            "no quedan ficheros a medias")

        # La comparacion, que es donde esta el peligro de perder partidas
        loc = [{'nombre': 'A.zip', 'bytes': 1, 'fecha': 100},
               {'nombre': 'B.zip', 'bytes': 1, 'fecha': 500}]
        rem2 = [{'nombre': 'A.zip', 'bytes': 1, 'fecha': 900},
                {'nombre': 'B.zip', 'bytes': 1, 'fecha': 100},
                {'nombre': 'C.zip', 'bytes': 1, 'fecha': 100}]
        t, ig, nu = comparar(loc, rem2)
        chk([x['nombre'] for x in t] == ['A.zip', 'C.zip'],
            "se trae la mas nueva de alla y la que falta")
        chk([x['nombre'] for x in nu] == ['B.zip'],
            "la que aqui es mas nueva NO se trae")
        t2, ig2, _ = comparar(loc, [{'nombre': 'B.zip', 'bytes': 1,
                                     'fecha': 501}])
        chk(t2 == [] and len(ig2) == 1,
            "un segundo de diferencia no cuenta como mas nueva")
    finally:
        srv.shutdown()
        srv.server_close()

    # ── EL SERVIDOR PERMANENTE: subidas, versiones y el token ───────────────
    alm = os.path.join(d, 'almacen')
    os.makedirs(alm)
    t1 = token_de(alm)
    chk(len(t1) == 32, "el token se crea y es largo")
    chk(token_de(alm) == t1, "el token no cambia entre arranques")

    srv2 = servir(alm, 0, t1, hasta=True, subida=True)
    p2 = srv2.server_address[1]
    try:
        chk(subir('127.0.0.1', p2, 'mal', os.path.join(orig, 'Juego B.zip')) != 0,
            "con el token mal no se sube")
        chk(subir('127.0.0.1', p2, t1, os.path.join(orig, 'Juego B.zip')) == 0,
            "se sube una copia")
        guardada = os.path.join(alm, 'Juego B.zip')
        chk(os.path.isfile(guardada), "la copia esta en el servidor")
        chk(_huella(guardada) == _huella(os.path.join(orig, 'Juego B.zip')),
            "lo subido es identico a lo que habia")

        # Una version mas nueva SI entra, y la vieja se guarda aparte
        nuevo = os.path.join(d, 'Juego B.zip')
        with open(nuevo, 'wb') as fh:
            fh.write(os.urandom(2000))
        os.utime(nuevo, (time.time() + 60, time.time() + 60))
        chk(subir('127.0.0.1', p2, t1, nuevo) == 0, "se sube una mas nueva")
        chk(os.path.getsize(guardada) == 2000, "la nueva sustituye a la vieja")
        vdir = os.path.join(alm, 'versiones')
        chk(os.path.isdir(vdir) and len(os.listdir(vdir)) == 1,
            "la vieja se guarda en versiones/")

        # Y una MAS VIEJA no pisa a la de alli: es la regla que salva partidas
        viejo = os.path.join(d, 'viejo', 'Juego B.zip')
        os.makedirs(os.path.dirname(viejo))
        with open(viejo, 'wb') as fh:
            fh.write(b'x' * 10)
        os.utime(viejo, (time.time() - 9999, time.time() - 9999))
        chk(subir('127.0.0.1', p2, t1, viejo) == 2,
            "una copia mas vieja NO pisa la del servidor")
        chk(os.path.getsize(guardada) == 2000,
            "y la del servidor sigue intacta")

        # EL MODO "COMPARTIR UN RATO" NO ACEPTA SUBIDAS.
        #
        # Se levanta OTRO servidor para esto. La primera version de la prueba
        # reutilizaba el de antes, que ya estaba cerrado: el fallo que media
        # era "conexion rechazada", no el rechazo de la subida. Una prueba que
        # pasa por el motivo equivocado es peor que no tenerla, porque da una
        # seguridad que no existe.
        srv3 = servir(orig, 0, 'abc123', hasta=True)      # sin subida=True
        try:
            chk(subir('127.0.0.1', srv3.server_address[1], 'abc123',
                      os.path.join(orig, 'Juego B.zip')) != 0,
                "el modo 'compartir un rato' rechaza subidas")
            chk(listar('127.0.0.1', srv3.server_address[1], 'abc123') is not None,
                "...pero ese mismo servidor sigue dejando listar")
        finally:
            srv3.shutdown()
            srv3.server_close()
    finally:
        srv2.shutdown()
        srv2.server_close()

    u = unidad_systemd(alm, 8788, os.path.join(d, 'u', 'wproton.service'))
    txt = open(os.path.join(d, 'u', 'wproton.service')).read()
    chk('servidor' in txt and str(8788) in txt, "la unidad de systemd se escribe")
    chk('[Install]' in txt, "la unidad se puede activar")

    import shutil
    shutil.rmtree(d, ignore_errors=True)
    if fallos[0]:
        print("sincro.py: %d fallo(s)" % fallos[0])
        return 1
    print("sincro.py: todo correcto")
    return 0


def main(argv):
    if len(argv) >= 2 and argv[1] == 'comprobar':
        return comprobar()
    if len(argv) >= 5 and argv[1] == 'servir':
        return servir(argv[2], argv[3], argv[4])
    if len(argv) >= 4 and argv[1] == 'servidor':
        # Permanente: token de fichero y subidas permitidas.
        c = token_de(argv[2])
        print("sincro: token %s" % c, flush=True)
        return servir(argv[2], argv[3], c, subida=True)
    if len(argv) >= 3 and argv[1] == 'token':
        print(token_de(argv[2]))
        return 0
    if len(argv) >= 4 and argv[1] == 'unidad':
        return unidad_systemd(argv[2], argv[3],
                              argv[4] if len(argv) > 4 else None)
    if len(argv) >= 6 and argv[1] == 'subir':
        return subir(argv[2], argv[3], argv[4], argv[5])
    if len(argv) >= 5 and argv[1] == 'listar':
        r = listar(argv[2], argv[3], argv[4])
        if r is None:
            return 1
        for e in r:
            print("%s\t%d\t%d" % (e['nombre'], e['bytes'], e['fecha']))
        return 0
    if len(argv) >= 7 and argv[1] == 'traer':
        return traer(argv[2], argv[3], argv[4], argv[5], argv[6])
    sys.stderr.write(__doc__.split('uso:')[-1].strip() + "\n")
    return 2


if __name__ == '__main__':
    sys.exit(main(sys.argv))
