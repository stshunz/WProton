# -*- coding: utf-8 -*-
"""Construye la lista de la biblioteca de UNA sola vez.

Antes esto lo hacia bash llamando a varias funciones por cada juego. Cada
llamada cuesta poco, pero con 141 juegos son miles, y en una Steam Deck eso
eran decenas de segundos de espera al abrir la lista.

Aqui se hace todo en una pasada: se leen los perfiles, se buscan las
caratulas y se compone cada fila. Bash solo lee el resultado.

Uso:
    biblioteca.py <fichero_mapa> <fichero_info> < lista_de_juegos
    biblioteca.py --rejilla <fichero_manifiesto> < lista_de_juegos

Vista de lista, escribe:
    - fichero_mapa:  etiqueta<TAB>ruta       (para volver de la etiqueta a la ruta)
    - fichero_info:  etiqueta|caratula|fav|veces|segundos|ficha|duracion
    - por pantalla:  una etiqueta por linea, en el mismo orden

Vista de rejilla, escribe:
    - manifiesto:    etiqueta|caratula|ruta|fav

La etiqueta de la rejilla lleva dentro el tiempo jugado y la fecha de la
ultima partida, y la forma de la caratula la manda WP_GRID_FORMA en vez de
LIST_COVER (cada vista de rejilla usa una distinta).

Las reglas (identificador, etiqueta, busqueda de caratula) son las mismas que
usa wproton.sh; si se cambian alli, hay que cambiarlas aqui.
"""
import os
import sys

EXTS_IMAGEN = ('png', 'jpg', 'jpeg', 'webp')
EXTS_EMPAQUETADO = ('.wsquashfs', '.squashfs', '.dwarfs')


def entorno(nombre, por_defecto=''):
    return os.environ.get(nombre, por_defecto)


def game_id(ruta):
    """Identificador del juego: como lo calcula wproton.sh."""
    gid = os.path.basename(ruta.rstrip('/'))
    if not os.path.isdir(ruta):
        gid = os.path.splitext(gid)[0]
    return gid.replace(' ', '_').replace('/', '_')


def etiqueta(ruta, raices):
    """Como se ve el juego en la lista: sin la extension del empaquetado.

    Si hay varias carpetas de juegos, se anade de cual viene, para poder
    distinguir dos juegos con el mismo nombre.
    """
    nom = os.path.basename(ruta.rstrip('/'))
    # Distinguiendo mayusculas, igual que el "case" de wproton.sh: un
    # Juego.WSQUASHFS puesto a mano conserva su extension en los dos caminos.
    # Si algun dia se acepta la mayuscula, hay que cambiarlo en los dos sitios.
    for ext in EXTS_EMPAQUETADO:
        if nom.endswith(ext):
            nom = nom[:-len(ext)]
            break
    if len(raices) > 1:
        for r in raices:
            if r and (ruta + '/').startswith(r.rstrip('/') + '/'):
                base = os.path.basename(r.rstrip('/'))
                if base:
                    return '%s   (%s)' % (nom, base)
                break
    return nom


def nombres_posibles(gid):
    """El identificador cambia los espacios por guiones bajos; quien copia su
    coleccion a mano conserva los espacios. Se prueban las dos formas."""
    yield gid
    if '_' in gid:
        yield gid.replace('_', ' ')


def buscar_cover(gid, carpeta, carpeta_vertical, legacy_wide=False):
    """Ruta de la caratula, o cadena vacia."""
    for nom in nombres_posibles(gid):
        for ext in EXTS_IMAGEN:
            p = os.path.join(carpeta, '%s.%s' % (nom, ext))
            if os.path.isfile(p):
                return p
    if legacy_wide:                      # nomenclatura anterior: <juego>.wide.*
        # Solo el identificador, sin la forma con espacios: es lo que hace
        # cover_for. Aqui no se prueban las dos formas a proposito.
        for ext in EXTS_IMAGEN:
            p = os.path.join(carpeta_vertical, '%s.wide.%s' % (gid, ext))
            if os.path.isfile(p):
                return p
    if carpeta != carpeta_vertical:      # respaldo: la vertical de siempre
        for nom in nombres_posibles(gid):
            for ext in EXTS_IMAGEN:
                p = os.path.join(carpeta_vertical, '%s.%s' % (nom, ext))
                if os.path.isfile(p):
                    return p
    return ''


SIN_PERFIL = ('0', '0', '0', '')


def leer_perfiles(carpeta):
    """Todos los perfiles de una vez: gid -> (fav, veces, segundos, ultima)."""
    datos = {}
    try:
        ficheros = [f for f in os.listdir(carpeta) if f.endswith('.conf')]
    except OSError:
        return datos
    for f in ficheros:
        fav, veces, segs, ultima = '0', '0', '0', ''
        try:
            with open(os.path.join(carpeta, f), encoding='utf-8',
                      errors='replace') as fh:
                for linea in fh:
                    if linea.startswith('FAVORITO='):
                        fav = linea.split('=', 1)[1].strip().strip('"')
                    elif linea.startswith('PLAY_COUNT='):
                        veces = linea.split('=', 1)[1].strip().strip('"')
                    elif linea.startswith('PLAY_SECONDS='):
                        segs = linea.split('=', 1)[1].strip().strip('"')
                    elif linea.startswith('LAST_PLAYED='):
                        ultima = linea.split('=', 1)[1].strip().strip('"')
        except OSError:
            continue
        datos[f[:-5]] = (fav or '0', veces or '0', segs or '0', ultima)
    return datos


def fmt_playtime(segundos):
    """segundos -> "3 h 12 min" / "45 min" / "<1 min". Como fmt_playtime()."""
    horas, minutos = segundos // 3600, (segundos % 3600) // 60
    if horas > 0:
        return '%d h %d min' % (horas, minutos)
    if minutos > 0:
        return '%d min' % minutos
    return '<1 min'


def etiqueta_rejilla(ruta, raices):
    """La etiqueta de la rejilla: como la de la lista y, ademas, los tres
    recortes que hacia el bucle de bash por si la extension seguia ahi."""
    t = etiqueta(ruta, raices)
    corte = t.rfind('.wsquashfs')          # "${t2%.wsquashfs*}"
    if corte >= 0:
        t = t[:corte]
    for ext in ('.squashfs', '.dwarfs'):   # "${t2%.squashfs}" y "${t2%.dwarfs}"
        if t.endswith(ext):
            t = t[:-len(ext)]
    return t


def carpetas_de_covers(forma):
    """(carpeta de esa forma, carpeta vertical) para buscar_cover."""
    vertical = entorno('COVERS_DIR')
    carpeta = {
        'wide': entorno('COVERS_WIDE_DIR'),
        '43': entorno('COVERS_43_DIR'),
    }.get(forma, vertical) or vertical
    return carpeta, vertical


def rejilla(f_manifiesto, juegos, raices, perfiles):
    """Una fila por juego: etiqueta|caratula|ruta|fav."""
    forma = entorno('WP_GRID_FORMA', 'vertical')
    carpeta_cover, covers = carpetas_de_covers(forma)
    filas = []
    for ruta in juegos:
        etq = etiqueta_rejilla(ruta, raices)
        gid = game_id(ruta)
        cov = buscar_cover(gid, carpeta_cover, covers,
                           legacy_wide=(forma == 'wide'))
        fav, _veces, segs, ultima = perfiles.get(gid, SIN_PERFIL)

        info = ''
        try:                               # bash: [ "$sc" -gt 0 ] 2>/dev/null
            if int(segs) > 0:
                info = fmt_playtime(int(segs))
        except ValueError:
            pass
        if ultima:
            # Solo la fecha, sin la hora: la hora no cabe y ademas el ' - '
            # separa las dos cosas. OJO con las barras verticales.
            info = (info + ' - ' if info else '') + ultima.split(' ')[0]
        if info:
            etq = '%s   [%s]' % (etq, info)
        # El separador es sagrado: si una fecha o un nombre cuela un '|', la
        # fila se parte y el juego se queda sin caratula.
        etq = etq.replace('|', '/')

        filas.append('%s|%s|%s|%s' % (etq, cov, ruta, fav or '0'))

    with open(f_manifiesto, 'w', encoding='utf-8') as fh:
        fh.write('\n'.join(filas) + ('\n' if filas else ''))
    return 0


def main():
    if len(sys.argv) < 3:
        sys.stderr.write('uso: biblioteca.py <mapa> <info>\n'
                         '     biblioteca.py --rejilla <manifiesto>\n')
        return 2

    perfiles = leer_perfiles(entorno('PROFILE_DIR'))
    raices = [r for r in entorno('WP_RAICES', '').split('\n') if r.strip()]
    juegos = [l.rstrip('\n') for l in sys.stdin if l.strip()]

    if sys.argv[1] == '--rejilla':
        return rejilla(sys.argv[2], juegos, raices, perfiles)

    f_mapa, f_info = sys.argv[1], sys.argv[2]

    forma = entorno('LIST_COVER', 'vertical')
    carpeta_cover, covers = carpetas_de_covers(forma)
    datos_dir = entorno('DATOS_DIR')

    vistas = set()
    lineas_mapa, lineas_info, etiquetas = [], [], []

    for ruta in juegos:
        etq = etiqueta(ruta, raices)
        # dos juegos pueden quedar con la misma etiqueta al quitar la
        # extension: el segundo conserva su nombre completo
        if etq in vistas:
            etq = os.path.basename(ruta.rstrip('/'))
        vistas.add(etq)

        gid = game_id(ruta)
        cov = buscar_cover(gid, carpeta_cover, covers,
                           legacy_wide=(forma == 'wide'))
        fav, veces, segs, _ultima = perfiles.get(gid, SIN_PERFIL)

        ficha = os.path.join(datos_dir, '%s.info.json' % gid)
        ficha = ficha if (datos_dir and os.path.isfile(ficha)
                          and os.path.getsize(ficha) > 0) else ''
        dur = os.path.join(datos_dir, '%s.hltb' % gid)
        dur = dur if (datos_dir and os.path.isfile(dur)
                      and os.path.getsize(dur) > 0) else ''

        lineas_mapa.append('%s\t%s' % (etq, ruta))
        lineas_info.append('%s|%s|%s|%s|%s|%s|%s'
                           % (etq, cov, fav, veces, segs, ficha, dur))
        etiquetas.append(etq)

    with open(f_mapa, 'w', encoding='utf-8') as fh:
        fh.write('\n'.join(lineas_mapa) + ('\n' if lineas_mapa else ''))
    with open(f_info, 'w', encoding='utf-8') as fh:
        fh.write('\n'.join(lineas_info) + ('\n' if lineas_info else ''))
    sys.stdout.write('\n'.join(etiquetas) + ('\n' if etiquetas else ''))
    return 0


if __name__ == '__main__':
    sys.exit(main())
