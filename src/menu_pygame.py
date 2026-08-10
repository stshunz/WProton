#!/usr/bin/env python3
# Menu/explorador de WProton en pygame: mando via hilo evdev (sin foco),
# navegador persistente, y BUSQUEDA: teclado real (type-ahead) o teclado
# virtual en pantalla para el mando (boton Y).
# Modos:
#   list   <titulo> <salida> <fichero_opciones>
#   check  <titulo> <salida> <fichero_opciones>   ("0|Texto"/"1|Texto")
#   browse <titulo> <salida> <dir_inicial> <file|dir|play|keys>
#   grid   <titulo> <salida> <manifiesto>   (lineas "titulo|imagen|payload")
#   progress <titulo> <fichero_estado>     (el fichero lleva "pct|texto")
#   text   <titulo> <salida> <valor_inicial>  (teclado en pantalla)
#   canvas <titulo> <fichero_estado>       (fondo persistente del modo Juego)
import json, os, sys, time

BASE = os.path.dirname(os.path.abspath(__file__))
LIBS = os.path.join(BASE, 'libs_py%d.%d' % sys.version_info[:2])
if os.path.isdir(LIBS):
    sys.path.insert(0, LIBS)

os.environ.setdefault('SDL_JOYSTICK_ALLOW_BACKGROUND_EVENTS', '1')
os.environ.setdefault('PYGAME_HIDE_SUPPORT_PROMPT', '1')
os.environ.setdefault('SDL_VIDEO_CENTERED', '1')
os.environ.setdefault('SDL_VIDEO_MINIMIZE_ON_FOCUS_LOSS', '0')
# Pantalla completa: forzada en Batocera, o recordada entre menus con un
# marcador (cada menu es un proceso nuevo, así que la preferencia va a fichero)
# Pantalla completa POR DEFECTO: se ve mejor y es lo que espera quien juega
# con mando. Si el usuario prefiere ventana, lo cambia con Select+A / F11 y
# queda anotado en este marcador.
WIN_MARK = os.path.join(BASE, '.menu_windowed')
FULLSCREEN = os.environ.get('WP_MENU_FS') == '1' or not os.path.isfile(WIN_MARK)
# Orden de drivers de video a probar. En sesión gamescope (modo Juego de
# SteamOS) va primero Wayland: forzar x11/XWayland deja la ventana detras y
# se ve la pantalla en negro. En escritorio, al reves.
IS_GAMESCOPE_SESS = bool(os.environ.get('GAMESCOPE_WAYLAND_DISPLAY')) or \
    os.environ.get('XDG_CURRENT_DESKTOP') == 'gamescope'

# CLAVE en el modo Juego de SteamOS: el compositor NO se llama "wayland-0"
# sino "gamescope-0" (GAMESCOPE_WAYLAND_DISPLAY). Sin decirselo a SDL, este
# no encuentra Wayland, cae a XWayland... y cuando el juego termina y
# gamescope reinicia su XWayland, Xlib mata el proceso con
# "XIO: fatal IO error" (ese error NO se puede capturar desde Python).
# En sesion gamescope se usa X11 (XWayland) por defecto: es lo que SI se ve
# en el modo Juego de SteamOS. Wayland nativo dibuja pero gamescope no llega
# a mostrar la ventana, y el menu parece colgado. Con WP_FORCE_WAYLAND=1 se
# puede probar Wayland (evita los cuelgues de XWayland al cerrar un juego).
_gsw = os.environ.get('GAMESCOPE_WAYLAND_DISPLAY')
if _gsw and os.environ.get('WP_FORCE_WAYLAND'):
    os.environ['WAYLAND_DISPLAY'] = _gsw
    sys.stderr.write('menu_pygame: sesion gamescope, WAYLAND_DISPLAY=%s\n' % _gsw)
if os.environ.get('SDL_VIDEODRIVER'):
    DRIVER_ORDER = [os.environ['SDL_VIDEODRIVER'], None]
elif IS_GAMESCOPE_SESS and os.environ.get('WP_FORCE_WAYLAND'):
    DRIVER_ORDER = ['wayland', 'x11', None]
elif IS_GAMESCOPE_SESS:
    # X11 primero: es el que se ve en el modo Juego (como hasta la 0.90)
    DRIVER_ORDER = ['x11', 'wayland', None]
elif os.environ.get('DISPLAY'):
    DRIVER_ORDER = ['x11', 'wayland', None]
else:
    DRIVER_ORDER = ['wayland', None]
import pygame

# Parametros de la peticion en curso. En modo servidor cambian con cada
# menu; en modo suelto se fijan una vez desde la linea de ordenes.
MODE = TITLE = OUTFILE = ARG4 = ''
BROWSE_KIND = 'file'
BROWSE_EXTS = ()
LIST_INFO = {}          # datos por juego para el panel derecho de la lista
PRESEL = ''             # juego sobre el que abrir la lista (volver donde estabas)
FAV_FILE = ''           # donde se apuntan los favoritos marcados en el menu
COVER_CACHE = {}

def leer_ficha(ruta):
    # Saca del JSON de la tienda de Steam lo que cabe en el panel
    if not ruta or not os.path.isfile(ruta):
        return {}
    try:
        with open(ruta, encoding='utf-8') as fh:
            d = json.load(fh)
        d = list(d.values())[0].get('data', {})
    except Exception:
        return {}
    def lista(clave, tope=2):
        v = d.get(clave) or []
        if isinstance(v, list):
            v = [x.get('description', '') if isinstance(x, dict) else str(x)
                 for x in v[:tope]]
            return ', '.join(x for x in v if x)
        return str(v)
    fecha = (d.get('release_date') or {}).get('date', '') or ''
    ano = ''
    for trozo in str(fecha).replace(',', ' ').split():
        if trozo.isdigit() and len(trozo) == 4:
            ano = trozo
    return {'nombre': d.get('name', ''),
            'ano': ano,
            'dev': lista('developers'),
            'edi': lista('publishers'),
            'gen': lista('genres'),
            'nota': str((d.get('metacritic') or {}).get('score', '') or '')}

def leer_duracion(ruta):
    # "21.5|44" -> texto para el panel
    if not ruta or not os.path.isfile(ruta):
        return ''
    try:
        with open(ruta, encoding='utf-8') as fh:
            partes = fh.read().strip().split('|')
    except Exception:
        return ''
    try:
        hist = float(partes[0]) if partes and partes[0] else 0
    except ValueError:
        hist = 0
    return ('%g h' % hist) if hist else ''
EXTS_NORMAL = ('.wsquashfs', '.squashfs', '.dwarfs', '.zip', '.7z', '.rar',
               '.001', '.z01', '.exe', '.bat', '.cmd', '.wtgz')

def set_request(mode, title, outfile, arg4=None, browse_kind='file', action_x=None,
                manifiesto=None, preseleccion=None, fav_file=None):
    global MODE, TITLE, OUTFILE, ARG4, BROWSE_KIND, BROWSE_EXTS, ACTION_X
    global LIST_INFO, PRESEL, FAV_FILE
    PRESEL = preseleccion or ''
    FAV_FILE = fav_file or ''
    LIST_INFO = {}
    if manifiesto and os.path.isfile(manifiesto):
        # nombre|caratula|favorito|veces|segundos|ficha.json|duracion
        # La ficha se lee AQUI: el helper es Python y sabe leer el JSON de
        # Steam mucho mejor que bash a base de tuberias.
        try:
            with open(manifiesto, encoding='utf-8') as fh:
                for linea in fh:
                    campos = linea.rstrip('\n').split('|')
                    if not campos or not campos[0].strip():
                        continue
                    while len(campos) < 6:
                        campos.append('')
                    d = {'cov': campos[1], 'fav': campos[2],
                         'veces': campos[3], 'segs': campos[4],
                         'ficha': campos[5], 'hltb': campos[6] if len(campos) > 6 else ''}
                    d.update(leer_ficha(campos[5]))
                    d['dur'] = leer_duracion(d.get('hltb', ''))
                    LIST_INFO[campos[0]] = d
        except Exception:
            LIST_INFO = {}
    MODE, TITLE, OUTFILE = mode, title, outfile
    ARG4 = arg4 if arg4 is not None else outfile
    BROWSE_KIND = browse_kind
    if browse_kind == 'keys':
        BROWSE_EXTS = ('.keys',)
    elif browse_kind == 'image':
        BROWSE_EXTS = ('.png', '.jpg', '.jpeg', '.webp', '.bmp')
    else:
        BROWSE_EXTS = EXTS_NORMAL
    if action_x is not None:
        ACTION_X = action_x
K_HDR, K_UP2, K_CANCEL, K_DIR, K_FILE, K_PLAIN = range(6)
HEADER_KINDS = (K_HDR, K_UP2, K_CANCEL)

items = []          # [tipo, texto, marcado]
view = []           # indices visibles según el filtro de busqueda
cur_path = ''
sel, scroll = 0, 0
FILTER = ''
kb_open = False
kb_r, kb_c = 0, 0

def _match(text, f):
    # Coincidencia por PREFIJO de palabra: "s" -> solo titulos con alguna
    # palabra que empiece por s (no cualquier titulo que contenga una s).
    # Varias palabras ("sil h"): cada trozo debe ser prefijo de alguna palabra.
    words = text.lower().replace('_', ' ').replace('-', ' ').replace('.', ' ').split()
    for tok in f.split():
        if not any(w.startswith(tok) for w in words):
            return False
    return True

def apply_filter():
    global view, sel, scroll
    if FILTER.strip():
        f = FILTER.lower()
        view = [i for i, it in enumerate(items)
                if it[0] in HEADER_KINDS or _match(it[1], f)]
    else:
        view = list(range(len(items)))
    sel = 0
    scroll = 0

def load_options():
    global items
    items = []
    with open(ARG4, encoding='utf-8') as f:
        for l in f:
            l = l.rstrip('\n')
            if not l.strip():
                continue
            if MODE == 'check':
                on, _, txt = l.partition('|')
                items.append([K_PLAIN, txt, on == '1'])
            else:
                items.append([K_PLAIN, l, False])
    apply_filter()

def load_dir(path):
    # Navegacion EN PROCESO: sin relanzar python/ventana por carpeta
    global items, cur_path, FILTER
    cur_path = os.path.realpath(path)
    FILTER = ''
    items = []
    if BROWSE_KIND == 'dir':
        items.append([K_HDR, '>> USAR ESTA CARPETA <<', False])
    elif BROWSE_KIND == 'play':
        items.append([K_HDR, '>> JUGAR ESTA CARPETA <<', False])
    elif BROWSE_KIND not in ('keys', 'image'):
        items.append([K_HDR, '>> IMPORTAR ESTA CARPETA <<', False])
    items.append([K_UP2, '.. (subir)', False])
    items.append([K_CANCEL, '<< Cancelar', False])
    try:
        names = sorted(os.listdir(cur_path), key=str.lower)
    except OSError:
        names = []
    for n in names:
        if not n.startswith('.') and os.path.isdir(os.path.join(cur_path, n)):
            items.append([K_DIR, n + '/', False])
    if BROWSE_KIND in ('file', 'play', 'keys', 'image'):
        for n in names:
            p = os.path.join(cur_path, n)
            if (not n.startswith('.') and os.path.isfile(p)
                    and n.lower().endswith(BROWSE_EXTS)):
                items.append([K_FILE, n, False])
    apply_filter()

GITEMS = []          # (titulo, ruta_imagen, payload)

def load_manifest():
    global GITEMS
    GITEMS = []
    with open(ARG4, encoding='utf-8') as f:
        for l in f:
            l = l.rstrip('\n')
            if not l.strip():
                continue
            parts = l.split('|')
            while len(parts) < 4:
                parts.append('')
            GITEMS.append((parts[0], parts[1], parts[2], parts[3]))

def grid_apply_filter():
    global view, sel, scroll
    if FILTER.strip():
        f = FILTER.lower()
        view = [i for i, it in enumerate(GITEMS) if _match(it[0], f)]
    else:
        view = list(range(len(GITEMS)))
    sel = 0
    scroll = 0

def colocar_en_preseleccion():
    # Abrir la lista SOBRE el juego indicado. Se usa al marcar un favorito:
    # sin esto, la lista volveria a empezar por arriba y habria que buscar
    # otra vez donde estabas.
    global sel, scroll
    if not PRESEL or not view:
        return
    for i, idx in enumerate(view):
        nombre = GITEMS[idx][0] if MODE == 'grid' else items[idx][1]
        if nombre == PRESEL:
            sel = i
            vis = max(1, VIS_FULL if not kb_open else VIS_KB)
            scroll = max(0, sel - vis // 2)
            return

def load_request_data():
    # Carga lo que necesite el modo actual (opciones, carpeta o manifiesto)
    global FILTER, sel, scroll, kb_open, kb_r, kb_c
    FILTER = ''
    sel = scroll = 0
    kb_open = False
    kb_r = kb_c = 0
    if MODE in ('progress', 'text', 'canvas'):
        return
    if MODE == 'browse':
        load_dir(ARG4 if os.path.isdir(ARG4) else os.path.expanduser('~'))
    elif MODE == 'grid':
        load_manifest()
        grid_apply_filter()
        colocar_en_preseleccion()
    else:
        load_options()
        colocar_en_preseleccion()

def init_video():
    # pygame.init() NO lanza excepcion si solo falla el video: devuelve el
    # numero de subsistemas fallidos y sigue, y luego revienta el primer uso
    # ("video system not initialized"). Hay que inicializar el video aparte
    # y probar los drivers uno a uno.
    for drv in DRIVER_ORDER:
        if drv:
            os.environ['SDL_VIDEODRIVER'] = drv
        else:
            os.environ.pop('SDL_VIDEODRIVER', None)
        try:
            pygame.display.quit()
        except Exception:
            pass
        try:
            pygame.display.init()
            sys.stderr.write('menu_pygame: video OK con driver %s\n' % (drv or 'auto'))
            return True
        except Exception as e:
            sys.stderr.write('menu_pygame: driver %s no vale (%s)\n' % (drv or 'auto', e))
    return False

pygame.init()          # el resto de subsistemas (no falla aunque el video si)
if not init_video():
    sys.stderr.write('menu_pygame: sin video utilizable; se usaran menus de texto\n')
    sys.exit(2)
pygame.key.set_repeat(400, 120)

# --- hilo evdev: unico camino del mando (funciona sin foco de ventana) ---
import struct, threading, select as _select

EV_KEY_RAW, EV_ABS_RAW = 1, 3
IE_FMT = 'llHHi'
IE_SZ = struct.calcsize(IE_FMT)
# A/Start=Enter | B=Esc | X=Espacio | Y=Tab (teclado de busqueda)
# L1=F1 (ficha del juego) | R1=F2 (marcar favorito)
RAW_BTN = {304: pygame.K_RETURN, 315: pygame.K_RETURN,
           305: pygame.K_ESCAPE, 307: pygame.K_SPACE,
           308: pygame.K_TAB,
           310: pygame.K_F1, 311: pygame.K_F2}
SELECT_BTN = 314          # BTN_SELECT: con A pulsa pantalla completa
# Crucetas que reportan BOTONES (Anbernic/Decktroid...) en vez de hat:
DPAD_BTN = {544: pygame.K_UP, 545: pygame.K_DOWN,
            546: pygame.K_LEFT, 547: pygame.K_RIGHT}

def parse_input_chunk(data):
    out = []
    for off in range(0, len(data) - IE_SZ + 1, IE_SZ):
        _, _, t, c, v = struct.unpack_from(IE_FMT, data, off)
        out.append((t, c, v))
    return out

BAD_DEV = ('accel', 'gyro', 'imu', 'motion', 'sensor')
def find_raw_pads():
    # Solo mandos de verdad: fuera acelerometros/giroscopos que Batocera y los
    # handhelds exponen como joystick (movian el menu al inclinar la consola)
    pads = []
    try:
        blocks = open('/proc/bus/input/devices').read().split('\n\n')
    except OSError:
        return pads
    for b in blocks:
        name, ev, has_js = '', None, False
        for line in b.split('\n'):
            if line.startswith('N:'):
                name = line.lower()
            elif line.startswith('H:'):
                l2 = line.replace('=', ' ')
                if ' js' in l2:
                    has_js = True
                for tok in l2.split():
                    if tok.startswith('event'):
                        ev = tok
        if has_js and ev and not any(k in name for k in BAD_DEV):
            pads.append('/dev/input/' + ev)
    return pads

def post_key(k):
    try:
        pygame.event.post(pygame.event.Event(pygame.KEYDOWN, key=k))
    except Exception:
        pass

AXIS_KEYS = {17: (pygame.K_UP, pygame.K_DOWN),      # dpad vertical
             16: (pygame.K_LEFT, pygame.K_RIGHT),   # dpad horizontal
             1:  (pygame.K_UP, pygame.K_DOWN),      # stick izq vertical
             0:  (pygame.K_LEFT, pygame.K_RIGHT)}   # stick izq horizontal

_noaccess = set()

def evdev_thread():
    fds, held, ax = {}, {}, {}
    sel_held = [False]
    last_scan = 0.0
    REP_FIRST, REP_NEXT = 0.40, 0.15
    TH_ON, TH_OFF = 18000, 12000
    sys.stderr.write('menu_pygame: fallback evdev ACTIVO (leyendo /dev/input)\n')
    while True:
        now = time.time()
        if now - last_scan > 2:
            last_scan = now
            for p in find_raw_pads():
                if p not in fds:
                    try:
                        fds[p] = os.open(p, os.O_RDONLY | os.O_NONBLOCK)
                        sys.stderr.write('menu_pygame: mando via evdev: %s\n' % p)
                    except OSError as e:
                        # avisar UNA vez por dispositivo: el reintento cada 2s
                        # llenaba el log con cientos de lineas identicas
                        if p not in _noaccess:
                            _noaccess.add(p)
                            sys.stderr.write('menu_pygame: sin acceso a %s (%s)\n' % (p, e))
        try:
            r, _, _ = _select.select(list(fds.values()), [], [], 0.05 if held else 0.5)
        except OSError:
            r = []
        for fd in r:
            try:
                data = os.read(fd, IE_SZ * 64)
            except OSError:
                for p, f in list(fds.items()):
                    if f == fd:
                        try: os.close(f)
                        except OSError: pass
                        del fds[p]
                continue
            for t, c, v in parse_input_chunk(data):
                if t == EV_KEY_RAW and c in DPAD_BTN:
                    k = DPAD_BTN[c]
                    if v == 1:
                        post_key(k); held[k] = time.time() + REP_FIRST
                    else:
                        held.pop(k, None)
                elif t == EV_KEY_RAW and c == SELECT_BTN:
                    sel_held[0] = (v != 0)
                elif t == EV_KEY_RAW and c in RAW_BTN and v == 1:
                    if c == 304 and sel_held[0]:
                        post_key(pygame.K_F11)      # Select + A
                    else:
                        post_key(RAW_BTN[c])
                elif t == EV_ABS_RAW and c in (16, 17):
                    neg, pos = AXIS_KEYS[c]
                    for n in (neg, pos):
                        held.pop(n, None)
                    if v != 0:
                        k = pos if v > 0 else neg
                        post_key(k); held[k] = time.time() + REP_FIRST
                elif t == EV_ABS_RAW and c in (0, 1):
                    st = ax.get((fd, c), 0)
                    new = st
                    if st == 0 and abs(v) > TH_ON: new = 1 if v > 0 else -1
                    elif st != 0 and abs(v) < TH_OFF: new = 0
                    if new != st:
                        ax[(fd, c)] = new
                        neg, pos = AXIS_KEYS[c]
                        for n in (neg, pos):
                            held.pop(n, None)
                        if new != 0:
                            k = pos if new > 0 else neg
                            post_key(k); held[k] = time.time() + REP_FIRST
        now = time.time()
        for k, t_ in list(held.items()):
            if now >= t_:
                post_key(k); held[k] = now + REP_NEXT

# El hilo del mando siempre activo: con el servidor hay UN solo proceso, asi
# que no hay dos lectores compitiendo por /dev/input (que era el motivo de
# desactivarlo en el antiguo lienzo, que era un proceso aparte).
if sys.argv[1] != 'canvas':
    threading.Thread(target=evdev_thread, daemon=True).start()

W, H = 960, 680
def _open_window():
    if FULLSCREEN:
        return pygame.display.set_mode((0, 0), pygame.FULLSCREEN)
    return pygame.display.set_mode((W, H))
try:
    screen = _open_window()
except Exception as e:
    sys.stderr.write('menu_pygame: no se pudo abrir la ventana (%s)\n' % e)
    if FULLSCREEN:                      # reintentar en ventana
        FULLSCREEN = False
        screen = _open_window()
    else:
        raise
if FULLSCREEN:
    W, H = screen.get_size()
pygame.display.set_caption('WProton')
sys.stderr.write('menu_pygame: video driver = %s | ventana %dx%d | fullscreen=%s\n'
                 % (pygame.display.get_driver(), W, H, FULLSCREEN))

_last_frame = [time.time()]

def frame_watchdog():
    # En Wayland, flip() espera la confirmacion del compositor. Si gamescope
    # deja de mandarla (la ventana no llega a mostrarse), el proceso se queda
    # colgado PARA SIEMPRE y parece que WProton "no carga". Este hilo vigila
    # que sigan pintandose fotogramas; si se para, salimos con codigo 3 para
    # que WProton reintente con X11.
    def _vigila():
        n = 0
        while True:
            time.sleep(1.0)
            n += 1
            if n % 5 == 0:
                # rastro periodico: si esto aparece, el menu SI se esta
                # dibujando y el problema es que no llega a verse
                sys.stderr.write('menu_pygame: dibujando (ultimo fotograma hace %.1fs)\n'
                                 % (time.time() - _last_frame[0]))
            parado = time.time() - _last_frame[0]
            if parado > 6.0:
                sys.stderr.write('menu_pygame: %s lleva %.0fs sin dibujar; '
                                 'se reintentara con otro driver\n'
                                 % (pygame.display.get_driver(), parado))
                os._exit(3)
    threading.Thread(target=_vigila, daemon=True).start()

frame_watchdog()

if IS_GAMESCOPE_SESS:
    try:
        pygame.event.set_grab(False)
    except Exception:
        pass

def apply_layout():
    global W, H, VIS_FULL, VIS_KB, GCOLS, LIST_X, LIST_Y, LIST_W, LIST_H, SIDE_X, SIDE_W
    W, H = screen.get_size()
    make_bg()
    make_scan()
    if PANEL_UI and MODE == 'grid':
        # en rejilla no hay panel lateral: todo el ancho para las carátulas
        LIST_X, LIST_Y = 20, HEAD + 16
        LIST_H = H - LIST_Y - 76
        LIST_W = W - 40
        SIDE_W, SIDE_X = 0, 0
    elif PANEL_UI:
        # Interfaz de dos paneles: lista a la izquierda, detalles a la derecha
        foot = 62
        LIST_X, LIST_Y = 20, HEAD + 16
        LIST_H = H - LIST_Y - foot - 14
        if MODE in ('list', 'check', 'browse'):
            SIDE_W = max(240, int(W * 0.34))
            SIDE_X = W - SIDE_W - 20
            LIST_W = SIDE_X - LIST_X - 16
        else:
            SIDE_W, SIDE_X = 0, 0
            LIST_W = W - 40
    else:
        LIST_X, LIST_Y = 16, TOP
        LIST_W, LIST_H = W - 32, H - TOP - 60
    VIS_FULL = max(1, LIST_H // ROW)
    VIS_KB = max(1, (LIST_H - KB_H) // ROW)
    grid_metrics()

def toggle_fullscreen():
    global screen, FULLSCREEN, scroll
    FULLSCREEN = not FULLSCREEN
    try:
        screen = _open_window()
    except Exception:
        FULLSCREEN = not FULLSCREEN
        screen = _open_window()
    try:
        if FULLSCREEN:
            # vuelve a pantalla completa: se borra la preferencia de ventana
            if os.path.isfile(WIN_MARK):
                os.remove(WIN_MARK)
        else:
            open(WIN_MARK, 'w').close()
    except Exception:
        pass
    apply_layout()
    scroll = 0
    sys.stderr.write('menu_pygame: pantalla completa = %s\n' % FULLSCREEN)
clock = pygame.time.Clock()
# Escala de letra: 1.0 normal, 1.25 grande, 1.5 muy grande (WP_FONT_SCALE).
# Pensado sobre todo para consolas portatiles, donde 24 px se leen mal.
try:
    FSCALE = float(os.environ.get('WP_FONT_SCALE', '1') or '1')
except ValueError:
    FSCALE = 1.0
FSCALE = max(0.8, min(2.0, FSCALE))
def FS(px):
    return max(14, int(px * FSCALE))
f_tit = pygame.font.Font(None, FS(34))
f_it  = pygame.font.Font(None, FS(30))
f_sm  = pygame.font.Font(None, FS(24))
f_kb  = pygame.font.Font(None, FS(28))

# ---------------------------------------------------------------------------
# TEMAS: "clasico" (el de siempre, sobrio) y "moderno" (paneles y acento neon).
# Se elige con WP_THEME; para añadir uno nuevo basta con copiar un bloque y
# cambiar los colores: el resto del helper se adapta solo.
# ---------------------------------------------------------------------------
THEMES = {
    'clasico': {
        'bg': (24, 26, 32), 'bg2': (24, 26, 32),
        'fg': (225, 228, 235), 'dim': (140, 145, 155),
        'sel_bg': (38, 92, 170), 'sel_fg': (255, 255, 255),
        'acc': (120, 200, 130), 'dir': (150, 190, 240),
        'warn': (230, 180, 90), 'kb_bg': (34, 37, 46),
        'panel': None, 'border': (60, 64, 74), 'card': (44, 48, 60),
        'radius': 6, 'pill': False, 'rule': True, 'glow': False,
        'layout': 'simple', 'row': 40,
    },
    'moderno': {
        'bg': (14, 17, 26), 'bg2': (24, 30, 46),
        'fg': (232, 240, 252), 'dim': (128, 142, 168),
        'sel_bg': (26, 60, 82), 'sel_fg': (150, 240, 255),
        'acc': (56, 214, 224), 'dir': (124, 200, 255),
        'warn': (250, 196, 106), 'kb_bg': (20, 26, 40),
        'panel': (22, 28, 42), 'border': (44, 60, 88), 'card': (26, 33, 50),
        'radius': 12, 'pill': True, 'rule': False, 'glow': True,
        'layout': 'panel', 'row': 48,
        'acc2': (168, 120, 255), 'ok': (86, 226, 160),
        'btn': True, 'labelcolor': True, 'shape': 'notch',
    },
    # Arcade synthwave: rejilla en perspectiva, escaneado CRT, marcador de
    # seleccion y esquinas de HUD. Nada minimalista, a proposito.
    'arcade': {
        'bg': (12, 4, 30), 'bg2': (58, 12, 74),
        'fg': (255, 244, 252), 'dim': (170, 130, 200),
        'sel_bg': (92, 12, 96), 'sel_fg': (255, 255, 255),
        'acc': (255, 46, 147), 'dir': (94, 234, 255),
        'warn': (255, 214, 84), 'kb_bg': (24, 8, 44),
        'panel': (26, 8, 48), 'border': (120, 40, 140), 'card': (36, 12, 60),
        'radius': 0, 'pill': True, 'rule': False, 'glow': True,
        'layout': 'arcade', 'row': 48,
        'acc2': (94, 234, 255), 'ok': (120, 255, 170),
        'scan': True, 'gridbg': True, 'brackets': True,
        'marker': True, 'numbered': True, 'shadow': True,
        'btn': True, 'labelcolor': True, 'shape': 'rect',
    },
}
# Accion secundaria: con WP_ACTION_X=1, la X devuelve la seleccion marcada
# para que quien llame abra la configuración en vez de jugar.
SERVER_MODE = False
ACTION_X = os.environ.get('WP_ACTION_X') == '1'
LANG = os.environ.get('WP_LANG', 'es')
# El helper lee el MISMO lang/<codigo>.json que el script: así los textos
# propios (SELECCION, chips, teclado) se traducen a cualquier idioma nuevo
# sin tocar el codigo.
_LANGMAP = {}
if LANG != 'es':
    try:
        import json as _json
        with open(os.path.join(os.path.dirname(BASE), 'lang', LANG + '.json'),
                  encoding='utf-8') as _fh:
            _LANGMAP = {k: v for k, v in _json.load(_fh).items()
                        if isinstance(v, str) and v and k != '__version__'}
    except Exception:
        _LANGMAP = {}

def L(es, en=None):
    # busca en el json; si no esta, usa el ingles de respaldo (si se paso)
    if LANG == 'es':
        return es
    if es in _LANGMAP:
        return _LANGMAP[es]
    return en if en is not None else es
THEME_NAME = os.environ.get('WP_THEME', 'moderno')
if THEME_NAME not in THEMES:
    THEME_NAME = 'moderno'
TH = THEMES[THEME_NAME]

BG   = TH['bg']
FG   = TH['fg']
HIBG = TH['sel_bg']
DIM  = TH['dim']
ACC  = TH['acc']
DIRC = TH['dir']
KBBG = TH['kb_bg']
WARN = TH['warn']
RAD  = TH['radius']

BGSURF = None
SCANSURF = None
def make_scan():
    # Velo de lineas de escaneo (CRT): se dibuja una vez y se superpone
    global SCANSURF
    if not TH.get('scan'):
        SCANSURF = None
        return
    try:
        surf = pygame.Surface((W, H), pygame.SRCALPHA)
    except Exception:
        SCANSURF = None
        return
    for y in range(0, H, 3):
        pygame.draw.rect(surf, (0, 0, 0, 46), (0, y, W, 1))
    SCANSURF = surf

def make_bg():
    # Fondo: liso en clasico, degradado vertical suave en moderno
    global BGSURF
    surf = pygame.Surface((W, H))
    if TH.get('gridbg'):
        # Cielo degradado + horizonte con rejilla en fuga (synthwave)
        c1, c2 = TH['bg2'], TH['bg']
        hz = int(H * 0.42)
        for i in range(hz):
            f = i / float(max(1, hz - 1))
            col = tuple(int(c1[k] + (c2[k] - c1[k]) * f) for k in range(3))
            pygame.draw.rect(surf, col, (0, i, W, 1))
        pygame.draw.rect(surf, TH['bg'], (0, hz, W, H - hz))
        pygame.draw.rect(surf, TH['acc'], (0, hz - 2, W, 2))
        gcol = (TH['border'][0], TH['border'][1], TH['border'][2])
        vp = W // 2
        for k in range(-14, 15):          # verticales que convergen
            pygame.draw.line(surf, gcol, (vp + k * 46, hz), (vp + k * 300, H), 1)
        yy, step = hz + 6, 6              # horizontales cada vez más separadas
        while yy < H:
            pygame.draw.line(surf, gcol, (0, yy), (W, yy), 1)
            step = int(step * 1.42) + 1
            yy += step
    elif TH['bg'] == TH['bg2']:
        surf.fill(TH['bg'])
    else:
        c1, c2 = TH['bg'], TH['bg2']
        steps = 48
        bh = H // steps + 1
        for i in range(steps):
            f = i / float(steps - 1)
            col = tuple(int(c1[k] + (c2[k] - c1[k]) * f) for k in range(3))
            pygame.draw.rect(surf, col, (0, i * bh, W, bh))
    BGSURF = surf

def draw_panel(rect):
    if TH['panel'] is None:
        return
    x, y, w, h = rect
    pygame.draw.rect(screen, TH['panel'], rect, border_radius=RAD)
    if TH.get('brackets'):
        # Marco de HUD: solo las esquinas, en color de acento
        c, L, t = ACC, 26, 3
        for (cx, cy, dx, dy) in ((x, y, 1, 1), (x + w, y, -1, 1),
                                 (x, y + h, 1, -1), (x + w, y + h, -1, -1)):
            pygame.draw.rect(screen, c, (min(cx, cx + dx * L), cy - (t if dy < 0 else 0), L, t))
            pygame.draw.rect(screen, c, (cx - (t if dx < 0 else 0), min(cy, cy + dy * L), t, L))
        pygame.draw.rect(screen, TH['border'], rect, 1)
    else:
        pygame.draw.rect(screen, TH['border'], rect, 1, border_radius=RAD)

def hbar(rect, c1, c2):
    # Barra con degradado horizontal (cabecera y seleccion del tema moderno)
    x, y, w, h = rect
    if w <= 0:
        return
    steps = 26
    sw = max(1, w // steps + 1)
    for i in range(steps):
        f = i / float(steps - 1)
        col = tuple(int(c1[k] + (c2[k] - c1[k]) * f) for k in range(3))
        pygame.draw.rect(screen, col, (x + i * sw, y, sw, h))

def vbar(rect, c1, c2):
    # Degradado vertical: da relieve de boton a las filas
    x, y, w, h = rect
    if h <= 0 or w <= 0:
        return
    steps = 12
    sh = max(1, h // steps + 1)
    for i in range(steps):
        f = i / float(steps - 1)
        col = tuple(int(c1[k] + (c2[k] - c1[k]) * f) for k in range(3))
        pygame.draw.rect(screen, col, (x, y + i * sh, w, sh))

def notch_points(x, y, w, h, n=15):
    # Cantos cortados en diagonal (arriba-derecha y abajo-izquierda)
    return [(x, y), (x + w - n, y), (x + w, y + n),
            (x + w, y + h), (x + n, y + h), (x, y + h - n)]

def draw_button_notch(rect, active):
    # Moderno: cápsula achaflanada, relleno plano y pestana de acento
    x, y, w, h = rect
    pts = notch_points(x, y, w, h)
    fill = TH['card'] if not active else tuple(min(255, int(c * 0.34) + 18) for c in ACC)
    try:
        pygame.draw.polygon(screen, fill, pts)
        pygame.draw.polygon(screen, ACC if active else TH['border'], pts, 2 if active else 1)
    except Exception:
        pygame.draw.rect(screen, fill, rect)
    # pestana lateral: fina si esta en reposo, gruesa y luminosa al elegir
    pygame.draw.rect(screen, ACC if active else TH['border'],
                     (x, y + (0 if active else 8), 6 if active else 3,
                      h - (0 if active else 16)))
    if active:
        pygame.draw.rect(screen, TH.get('acc2', ACC), (x + w - 15, y, 15, 3))

def draw_button(rect, active):
    # Fila con aspecto de boton: relieve, borde y brillo superior
    if TH.get('shape') == 'notch':
        draw_button_notch(rect, active)
        return
    x, y, w, h = rect
    if active:
        base = tuple(min(255, int(c * 0.42)) for c in ACC)
        vbar((x, y, w, h), base, TH['panel'])
        pygame.draw.rect(screen, ACC, (x, y, w, h), 2, border_radius=RAD)
        pygame.draw.rect(screen, ACC, (x + 2, y + 4, 5, h - 8), border_radius=2)
    else:
        c1 = tuple(min(255, c + 14) for c in TH['card'])
        vbar((x, y, w, h), c1, TH['card'])
        pygame.draw.rect(screen, TH['border'], (x, y, w, h), 1, border_radius=RAD)
    # brillo sutil en el borde superior
    hl = tuple(min(255, c + (46 if active else 22)) for c in TH['card'])
    pygame.draw.rect(screen, hl, (x + 3, y + 1, w - 6, 1))

def draw_chip(x, y, key, text, font):
    # "Pastilla" de ayuda: [A] elegir
    kw = rtext(font, key, TH['bg'])
    tw = rtext(font, text, TH['dim'])
    bw = kw.get_width() + 16
    pygame.draw.rect(screen, ACC, (x, y, bw, 24), border_radius=(0 if ARCADE else 8))
    if ARCADE:
        pygame.draw.rect(screen, TH['acc2'], (x, y, bw, 24), 1)
    screen.blit(kw, (x + 8, y + 3))
    screen.blit(tw, (x + bw + 8, y + 3))
    return x + bw + 16 + tw.get_width()

def draw_header():
    # Cabecera de marca a todo lo ancho, con acento y contador
    hh = HEAD - 6
    pygame.draw.rect(screen, TH['panel'], (0, 0, W, hh))
    hbar((0, hh - 3, W, 3), ACC, TH.get('acc2', ACC))
    if ARCADE:
        for _o, _c in (((3, 3), TH['acc2']), ((0, 0), ACC)):
            screen.blit(f_tit.render('WPROTON', True, _c), (24 + _o[0], 16 + _o[1]))
        brand = f_tit.render('WPROTON', True, ACC)
    else:
        brand = f_tit.render('WPROTON', True, ACC)
        screen.blit(brand, (24, 16))
    bx = 24 + brand.get_width() + 16
    pygame.draw.rect(screen, TH['border'], (bx - 8, 14, 2, hh - 34))
    for i, tl in enumerate(TITLE_LINES):
        screen.blit(f_it.render(fit_label(tl, f_it, W - bx - 150), True, FG),
                    (bx, 16 + i * 26))
    if view:
        badge = f_sm.render('%d/%d' % (sel + 1, len(view)), True, TH['bg'])
        bwd = badge.get_width() + 18
        pygame.draw.rect(screen, ACC, (W - bwd - 20, 18, bwd, 24), border_radius=12)
        screen.blit(badge, (W - bwd - 11, 21))

def cover_surface(ruta, ancho):
    # Carátula escalada, guardada en memoria: sin esto se recargaria del disco
    # 60 veces por segundo al mover la seleccion.
    if not ruta or not os.path.isfile(ruta):
        return None
    clave = (ruta, ancho)
    if clave in COVER_CACHE:
        return COVER_CACHE[clave]
    try:
        img = pygame.image.load(ruta)
        w0, h0 = img.get_size()
        if w0 <= 0 or h0 <= 0:
            return None
        alto = int(ancho * h0 / w0)
        img = pygame.transform.smoothscale(img, (ancho, alto))
    except Exception:
        img = None
    if len(COVER_CACHE) > 40:
        COVER_CACHE.clear()
    COVER_CACHE[clave] = img
    return img

def fmt_horas(seg):
    try:
        seg = int(seg)
    except Exception:
        return ''
    if seg < 60:
        return ''
    if seg < 3600:
        return '%d min' % (seg // 60)
    return '%d h %d min' % (seg // 3600, (seg % 3600) // 60)

def draw_side_panel():
    # Panel derecho: detalle de lo seleccionado. En la lista de juegos muestra
    # ademas la CARATULA y los datos del juego, para que la lista no sea solo
    # una columna de nombres.
    if SIDE_W <= 0:
        return
    rect = (SIDE_X, LIST_Y, SIDE_W, LIST_H)
    draw_panel(rect)
    px, py = SIDE_X + 16, LIST_Y + 14
    screen.blit(f_sm.render(L('SELECCION', 'SELECTION'), True, TH.get('acc2', ACC)), (px, py))
    py += 26
    pygame.draw.rect(screen, TH['border'], (px, py, SIDE_W - 32, 1))
    py += 14
    if view:
        txt = items[view[sel]][1] if MODE != 'grid' else GITEMS[view[sel]][0]
        datos = LIST_INFO.get(txt)
        # el nombre del fichero no aporta nada en el panel
        titulo_panel = (datos or {}).get('nombre') or txt
        for _ext in ('.wsquashfs', '.squashfs', '.dwarfs'):
            if titulo_panel.lower().endswith(_ext):
                titulo_panel = titulo_panel[:-len(_ext)]
                break
        # Carátula: ocupa como mucho la mitad del alto del panel, para que
        # siempre quede sitio para el nombre y los datos.
        if datos and MODE == 'list':
            cov = cover_surface(datos.get('cov'), min(SIDE_W - 32, 170))
            if cov is not None:
                ch = cov.get_height()
                if ch > LIST_H // 2:
                    cov = cover_surface(datos.get('cov'),
                                        int((SIDE_W - 32) * (LIST_H // 2) / ch))
                    ch = cov.get_height() if cov is not None else 0
                if cov is not None:
                    cx = SIDE_X + (SIDE_W - cov.get_width()) // 2
                    pygame.draw.rect(screen, TH['border'],
                                     (cx - 2, py - 2, cov.get_width() + 4, ch + 4), 1)
                    screen.blit(cov, (cx, py))
                    py += ch + 14
        for ln in wrap_title(titulo_panel, f_it, SIDE_W - 34, 3 if datos else 6):
            screen.blit(rtext(f_it, ln, FG), (px, py))
            py += 28
        if datos and MODE == 'list':
            py += 6
            filas = []
            # El favorito NO se repite aqui: su estrella ya se ve en la fila
            # de la lista, y en el panel solo gastaba una linea.
            if datos.get('ano'):
                filas.append((L('Año', 'Year'), datos['ano']))
            if datos.get('dev'):
                filas.append((L('Desarrollo', 'Developer'), datos['dev']))
            if datos.get('edi') and datos.get('edi') != datos.get('dev'):
                filas.append((L('Edición', 'Publisher'), datos['edi']))
            if datos.get('gen'):
                filas.append((L('Género', 'Genre'), datos['gen']))
            if datos.get('nota'):
                filas.append((L('Nota', 'Score'), '%s/100' % datos['nota']))
            if datos.get('dur'):
                filas.append((L('Duración', 'Length'), datos['dur']))
            if datos.get('veces') and datos['veces'] != '0':
                filas.append((L('Jugado', 'Played'),
                              L('%s veces', '%s times') % datos['veces']))
            t = fmt_horas(datos.get('segs'))
            if t:
                filas.append((L('Tiempo', 'Time'), t))
            for etiqueta, valor in filas:
                if py > LIST_Y + LIST_H - 26:
                    break
                se = rtext(f_sm, etiqueta, DIM)
                screen.blit(se, (px, py))
                # el valor va a la derecha; si no cabe, se recorta con puntos
                hueco = SIDE_W - 32 - se.get_width() - 10
                v = str(valor)
                sv = rtext(f_sm, v, TH.get('acc2', ACC))
                while sv.get_width() > hueco and len(v) > 4:
                    v = v[:-2]
                    sv = rtext(f_sm, v + '...', TH.get('acc2', ACC))
                screen.blit(sv, (SIDE_X + SIDE_W - 16 - sv.get_width(), py))
                py += 22
    else:
        screen.blit(f_it.render(L('(vacio)', '(empty)'), True, DIM), (px, py))
        py += 28
    if MODE == 'browse':
        py += 8
        screen.blit(f_sm.render(L('CARPETA', 'FOLDER'), True, TH.get('acc2', ACC)), (px, py))
        py += 22
        for ln in wrap_title(cur_path, f_sm, SIDE_W - 34, 4):
            screen.blit(rtext(f_sm, ln, DIM), (px, py))
            py += 20
    if FILTER:
        py += 10
        screen.blit(f_sm.render('BUSCANDO: %s' % FILTER, True, WARN), (px, py))

def draw_footer(chips):
    fy = H - 46
    pygame.draw.rect(screen, TH['panel'], (0, fy - 8, W, 54))
    hbar((0, fy - 10, W, 2), TH.get('acc2', ACC), ACC)
    x = 24
    for k, t in chips:
        x = draw_chip(x, fy + 6, k, t, f_sm)
        if x > W - 160:
            break

def draw_selection(rect):
    # clasico: barra plana | moderno: tarjeta | arcade: barra con marcador
    x, y, w, h = rect
    if TH.get('marker'):
        hbar((x, y, w, h), TH['sel_bg'], TH['bg'])
        pulse = 0.55 + 0.45 * abs(((time.time() * 1.6) % 2.0) - 1.0)
        col = tuple(int(c * pulse) for c in ACC)
        pygame.draw.rect(screen, col, (x, y, w, h), 2)
        pygame.draw.rect(screen, ACC, (x, y, 6, h))
        tri = [(x + 14, y + h // 2), (x + 4, y + 8), (x + 4, y + h - 8)]
        try:
            pygame.draw.polygon(screen, ACC, tri)
        except Exception:
            pass
        return
    if TH['pill']:
        hbar((x, y, w, h), TH['sel_bg'], TH['panel'])
        pygame.draw.rect(screen, ACC, (x, y, w, h), 1, border_radius=RAD)
        pygame.draw.rect(screen, ACC, (x + 2, y + 5, 5, h - 10), border_radius=3)
    else:
        pygame.draw.rect(screen, TH['sel_bg'], (x, y, w, h), border_radius=RAD)

_rcache = {}
def rtext(font, txt, color):
    # font.render cacheado: mismo texto+color+fuente -> misma superficie
    k = (id(font), txt, color)
    surf = _rcache.get(k)
    if surf is None:
        surf = font.render(txt, True, color)
        if len(_rcache) > 900:
            _rcache.clear()
        _rcache[k] = surf
    return surf

def wrap_title(text, font, maxw, maxlines=6):
    # Respeta los saltos de linea y ajusta al ancho; las rutas largas se
    # parten por caracteres (antes se cortaba el titulo y se perdia la pregunta)
    out = []
    for para in text.split('\n'):
        para = para.rstrip()
        if not para:
            out.append('')
            continue
        words, line = para.split(' '), ''
        for wd in words:
            probe = (line + ' ' + wd).strip()
            if rtext(font, probe, FG).get_width() <= maxw:
                line = probe
                continue
            if line:
                out.append(line)
                line = ''
            while rtext(font, wd, FG).get_width() > maxw:
                cut = len(wd)
                while cut > 1 and rtext(font, wd[:cut], FG).get_width() > maxw:
                    cut -= 1
                out.append(wd[:cut])
                wd = wd[cut:]
            line = wd
        if line:
            out.append(line)
    if len(out) > maxlines:
        out = out[:maxlines - 1] + ['\u2026']
    return out or ['']

# Valores que dependen del TITULO y del MODO: se recalculan en cada peticion
TITLE_LINES = ['']
T_FONT = None
T_LH = 30
HEAD = 70
ROW = 40
PANEL_UI = False
ARCADE = False
TOP = HEAD
LIST_X, LIST_Y, LIST_W, LIST_H = 16, TOP, 900, 480
SIDE_X, SIDE_W = 0, 0
VIS_FULL = 10
KB_H = 200
VIS_KB = 6

def compute_layout():
    # Recalcula todo lo que depende del titulo y del modo de esta peticion
    global TITLE_LINES, T_FONT, T_LH, HEAD, ROW, PANEL_UI, ARCADE, TOP
    global LIST_X, LIST_Y, LIST_W, LIST_H, SIDE_X, SIDE_W, VIS_FULL, VIS_KB
    T_FONT = f_tit if len(TITLE) < 60 else f_it
    TITLE_LINES = wrap_title(TITLE, T_FONT, 912)
    T_LH = FS(34) if T_FONT is f_tit else FS(30)
    HEAD = int(22 * FSCALE) + len(TITLE_LINES) * T_LH + 14
    ROW = max(TH['row'], int(TH['row'] * FSCALE))
    PANEL_UI = TH.get('layout') in ('panel', 'arcade')
    ARCADE = TH.get('layout') == 'arcade'
    TOP = (HEAD + 30) if MODE == 'browse' else HEAD
    LIST_X, LIST_Y = 16, TOP
    VIS_FULL = max(1, (H - TOP - 60) // ROW)
    VIS_KB = max(1, (H - TOP - 60 - KB_H) // ROW)
    apply_layout()

# --- teclado virtual (rejilla navegable con el dpad) ---
KB_ROWS = ['ABCDEFGHIJ',
           'KLMNOPQRST',
           'UVWXYZ0123',
           '456789 .-_']
KB_ACTIONS = ['BORRAR', 'LIMPIAR', 'LISTO'] if LANG != 'en' else ['DELETE', 'CLEAR', 'DONE']

def kb_cols(r):
    return len(KB_ACTIONS) if r == len(KB_ROWS) else len(KB_ROWS[r])

def shorten(p, n=82):
    return p if len(p) <= n else '\u2026' + p[-(n - 1):]

def write_out(text):
    with open(OUTFILE, 'w', encoding='utf-8') as f:
        f.write(text)

def _mark_clean_exit():
    # marca de "cierre ordenado": si falta, es que el proceso murio de golpe
    try:
        with open(OUTFILE + '.done', 'w') as _fh:
            _fh.write('ok')
    except Exception:
        pass

class SessionEnd(Exception):
    # Fin de UNA peticion. En modo servidor no se cierra la ventana: se
    # vuelve al reposo esperando la siguiente.
    def __init__(self, code):
        Exception.__init__(self, code)
        self.code = code

def safe_quit(code):
    # el texto ya esta escrito: pase lo que pase al cerrar, el llamador
    # recibe el codigo correcto
    _mark_clean_exit()
    if SERVER_MODE:
        raise SessionEnd(code)
    try:
        pygame.quit()
    except Exception:
        pass
    sys.exit(code)

def vis():
    return VIS_KB if kb_open else VIS_FULL

def move(d):
    global sel, scroll
    if not view:
        return
    sel = (sel + d) % len(view)
    if sel < scroll:
        scroll = sel
    if sel >= scroll + vis():
        scroll = sel - vis() + 1

def toggle():
    if MODE == 'check' and view:
        it = items[view[sel]]
        it[2] = not it[2]

# Rejilla adaptativa: en pantallas de portatil/consola (Steam Deck, Legion Go)
# menos columnas y carátulas MAS GRANDES; en monitores grandes, más columnas.
# WP_GRID_COLS fuerza un numero concreto de columnas (0 = automático).
GCOLS = 5
GCW, GCH = 176, 268
GIMG_W, GIMG_H = 150, 225
_imgcache = {}

def grid_metrics():
    # Tamaño de carátula según la pantalla. La regla que manda es la ALTURA:
    # la caratura debe caber en su fila con holgura (2 filas en monitores,
    # 1 fila grande en consolas portatiles). Antes solo se repartia el ancho
    # y en un monitor de sobremesa salian gigantes.
    global GCOLS, GCW, GCH, GIMG_W, GIMG_H
    avail_w = (LIST_W if PANEL_UI else (W - 40))
    avail_h = max(120, LIST_H - 16)
    forced = 0
    try:
        forced = int(os.environ.get('WP_GRID_COLS', '0'))
    except ValueError:
        forced = 0
    if forced > 0:
        rows = 1 if avail_h < 620 else 2
    elif avail_h < 620:          # Steam Deck, Legion Go, ventana baja
        rows = 1
    else:                        # monitor: dos filas de carátulas
        rows = 2
    # altura por fila (incluye el hueco del titulo): así las filas CABEN
    h_max = int(avail_h / rows) - 48
    w_from_h = int(h_max / 1.5)
    # ancho maximo razonable por carátula según el tamaño de pantalla
    w_cap = 190 if W <= 1400 else (210 if W <= 1920 else 240)
    if forced > 0:
        # columnas fijadas por el usuario: el tamaño de la carátula se calcula
        # para que QUEPAN esas columnas (antes se mantenía el tamaño y con
        # muchas columnas se salían de la pantalla)
        GCOLS = forced
        GCW = max(80, avail_w // forced)
        GIMG_W = max(90, GCW - 26)
        # y que la fila siga cabiendo de alto
        if int(GIMG_W * 1.5) + 48 > int(avail_h / rows):
            GIMG_W = max(90, int((int(avail_h / rows) - 48) / 1.5))
        GIMG_H = int(GIMG_W * 1.5)
        GCH = GIMG_H + 48
    else:
        GIMG_W = max(120, min(w_from_h, w_cap))
        GIMG_H = int(GIMG_W * 1.5)
        GCW = GIMG_W + 26
        GCH = GIMG_H + 48
        GCOLS = max(3, min(9, avail_w // GCW))
    _imgcache.clear()          # las imagenes se reescalan al nuevo tamaño

def grid_rows_vis():
    area = H - TOP - 60 - (KB_H if kb_open else 0)
    return max(1, area // GCH)

def grid_move(dx, dy):
    global sel, scroll
    if not view:
        return
    n = len(view)
    if dy == 0:
        sel = (sel + dx) % n
    else:
        s2 = sel + dy * GCOLS
        if 0 <= s2 < n:
            sel = s2
        elif dy > 0 and (sel // GCOLS) < ((n - 1) // GCOLS):
            sel = n - 1          # bajar a una fila incompleta: último juego
        # en los bordes verticales: quieto (el horizontal si envuelve)
    row = sel // GCOLS
    first = scroll // GCOLS
    vis_r = grid_rows_vis()
    if row < first:
        scroll = row * GCOLS
    elif row >= first + vis_r:
        scroll = (row - vis_r + 1) * GCOLS

def row_segments(label, base_color):
    # "Prefijo: compartido" -> etiqueta en color de acento, valor en blanco.
    # "MangoHud: ON" -> ON en verde, OFF apagado.
    if not TH.get('labelcolor') or ':' not in label:
        return [(label, base_color)]
    k, _, v = label.partition(':')
    # "arcade - synthwave: ..." no es etiqueta+valor, es una descripcion
    if ' - ' in k or len(k) > 36:
        return [(label, base_color)]
    segs = [(k + ':', TH.get('acc2', ACC))]
    v = v.strip()
    if v:
        low = v.lower()
        if low in ('on', 'si'):
            segs.append((' ' + v, TH.get('ok', ACC)))
        elif low in ('off', 'no'):
            segs.append((' ' + v, DIM))
        else:
            segs.append((' ' + v, base_color))
    return segs

def draw_segments(segs, font, x, y, maxw, active):
    # Pinta varios trozos de texto con colores distintos, con marquesina si
    # el conjunto no cabe (solo en la fila seleccionada) y recorte estricto.
    surfs = [(rtext(font, t, c), t, c) for t, c in segs if t]
    total = sum(sf.get_width() for sf, _, _ in surfs)
    if total <= maxw:
        cx = x
        for sf, _, _ in surfs:
            screen.blit(sf, (cx, y))
            cx += sf.get_width()
        return
    if not active:
        cx, rest = x, maxw
        for sf, t, c in surfs:
            wsf = sf.get_width()
            if wsf <= rest:
                screen.blit(sf, (cx, y)); cx += wsf; rest -= wsf
            else:
                screen.blit(rtext(font, fit_label(t, font, rest), c), (cx, y))
                break
        return
    over = total - maxw
    period = 2.2 + over / 70.0
    tt = (time.time() % (period * 2)) / period
    f = tt if tt <= 1.0 else 2.0 - tt
    f = max(0.0, min(1.0, (f - 0.14) / 0.72))
    old = None
    try:
        old = screen.get_clip()
        screen.set_clip((x, y - 2, maxw, ROW))
    except Exception:
        pass
    cx = x - int(over * f)
    for sf, _, _ in surfs:
        screen.blit(sf, (cx, y))
        cx += sf.get_width()
    try:
        screen.set_clip(old)
    except Exception:
        pass

def draw_estrella(cx, cy, r, color):
    # Estrella de cinco puntas dibujada a mano: el simbolo tipografico no
    # existe en la fuente por defecto, y un asterisco quedaba pobre.
    import math
    pts = []
    for i in range(10):
        ang = math.pi / 2 + i * math.pi / 5
        rad = r if i % 2 == 0 else r * 0.45
        pts.append((cx + rad * math.cos(ang), cy - rad * math.sin(ang)))
    try:
        pygame.draw.polygon(screen, color, pts)
    except Exception:
        pass

def draw_row_text(text, font, color, x, y, maxw, active):
    # Si el texto no cabe: en la fila seleccionada se desplaza (marquesina),
    # en las demás se recorta. Antes se salia de la tarjeta e invadia el panel.
    surf = rtext(font, text, color)
    w = surf.get_width()
    if w <= maxw:
        screen.blit(surf, (x, y))
        return
    if not active:
        screen.blit(rtext(font, fit_label(text, font, maxw), color), (x, y))
        return
    over = w - maxw
    period = 2.2 + over / 70.0          # cuanto más larga, más despacio
    tt = (time.time() % (period * 2)) / period
    f = tt if tt <= 1.0 else 2.0 - tt   # ida y vuelta
    f = max(0.0, min(1.0, (f - 0.14) / 0.72))   # pausa en los extremos
    old = None
    try:
        old = screen.get_clip()
        screen.set_clip((x, y - 2, maxw, ROW))
    except Exception:
        pass
    screen.blit(surf, (x - int(over * f), y))
    try:
        screen.set_clip(old)
    except Exception:
        pass

_fitcache = {}
def fit_label(txt, font, maxw):
    # Recorta midiendo el ancho renderizado (por caracteres se solapaban)
    k = (txt, maxw)
    if k in _fitcache:
        return _fitcache[k]
    if rtext(font, txt, FG).get_width() <= maxw:
        _fitcache[k] = txt
        return txt
    t = txt
    while t and rtext(font, t + '\u2026', FG).get_width() > maxw:
        t = t[:-1]
    t = (t.rstrip() + '\u2026') if t else '\u2026'
    _fitcache[k] = t
    return t

def grid_img(path):
    if not path or not os.path.isfile(path):
        return None
    if path not in _imgcache:
        try:
            img = pygame.image.load(path)
            _imgcache[path] = pygame.transform.smoothscale(img, (GIMG_W, GIMG_H))
        except Exception:
            _imgcache[path] = None
    return _imgcache[path]

def draw_grid():
    gx0 = LIST_X + max(0, (LIST_W - GCOLS * GCW) // 2) + (GCW - GIMG_W) // 2
    vis_r = grid_rows_vis()
    first = scroll
    for i in range(first, min(first + vis_r * GCOLS, len(view))):
        col = (i - first) % GCOLS
        rowi = (i - first) // GCOLS
        x = gx0 + col * GCW
        y = LIST_Y + 8 + rowi * GCH
        _cell = (x - 6, y - 6, GIMG_W + 12, GCH - 18)
        if TH['panel'] is not None:
            pygame.draw.rect(screen, TH['card'], _cell, border_radius=RAD)
        if i == sel and not kb_open:
            draw_selection(_cell)
        title, ipath, _pay = GITEMS[view[i]][:3]
        is_fav = len(GITEMS[view[i]]) > 3 and GITEMS[view[i]][3] == '1' 
        img = grid_img(ipath)
        if img:
            screen.blit(img, (x, y))
        else:
            pygame.draw.rect(screen, TH['card'], (x, y, GIMG_W, GIMG_H), border_radius=RAD)
            pygame.draw.rect(screen, TH['border'], (x, y, GIMG_W, GIMG_H), 1, border_radius=RAD)
            line, yy = '', y + 16
            for wd in title.split() + ['']:
                t2 = (line + ' ' + wd).strip()
                if wd and f_sm.render(t2, True, FG).get_width() < GIMG_W - 12:
                    line = t2
                    continue
                if line and yy < y + GIMG_H - 20:
                    screen.blit(f_sm.render(fit_label(line, f_sm, GIMG_W - 12), True, FG), (x + 6, yy))
                    yy += 22
                line = wd
        if is_fav:
            # cinta diagonal en la esquina superior derecha de la carátula
            rb = max(26, GIMG_W // 5)
            try:
                pygame.draw.polygon(screen, TH.get('acc2', ACC),
                                    [(x + GIMG_W - rb, y), (x + GIMG_W, y),
                                     (x + GIMG_W, y + rb)])
                pygame.draw.line(screen, FG, (x + GIMG_W - rb, y),
                                 (x + GIMG_W, y + rb), 2)
            except Exception:
                pygame.draw.rect(screen, TH.get('acc2', ACC),
                                 (x + GIMG_W - rb, y, rb, 8))
        draw_row_text(title, f_sm, FG if i == sel else DIM,
                      x, y + GIMG_H + 8, GIMG_W, i == sel)

def action_sobre_juego(accion):
    # Devuelve "WPACT:<accion>|<lo elegido>" y cierra el menu. WProton hace lo
    # suyo y vuelve a abrir la lista donde estaba.
    #   CONFIG -> configurar (X)      INFO -> ficha (L1)      FAV -> favorito (R1)
    global running, done
    if not view:
        return
    if MODE == 'grid':
        payload = GITEMS[view[sel]][2]
    else:
        payload = items[view[sel]][1]
    write_out('WPACT:%s|%s' % (accion, payload))
    running = False; done = True

def action_x():
    action_sobre_juego('CONFIG')

def marcar_favorito():
    # Cambia el favorito en el acto (sin cerrar el menu) y lo apunta para que
    # WProton lo guarde en el perfil cuando el menu termine.
    if not view:
        return
    nombre = GITEMS[view[sel]][0] if MODE == 'grid' else items[view[sel]][1]
    datos = LIST_INFO.get(nombre)
    if datos is None:
        datos = {'fav': '0'}
        LIST_INFO[nombre] = datos
    datos['fav'] = '0' if datos.get('fav') == '1' else '1'
    if not FAV_FILE:
        return
    try:
        # se apunta cada pulsacion: WProton alterna una vez por cada una
        with open(FAV_FILE, 'a', encoding='utf-8') as fh:
            fh.write(nombre + '\n')
    except Exception:
        pass

def on_enter():
    global running, done
    if MODE == 'grid':
        if not view:
            return
        write_out(GITEMS[view[sel]][2])
        running = False; done = True
        return
    if not view:
        return
    kind, txt, _ = items[view[sel]]
    if MODE == 'check':
        write_out('|'.join(t for k, t, on in items if on))
        running = False; done = True
    elif MODE == 'browse':
        if kind == K_HDR:
            write_out(cur_path); running = False; done = True
        elif kind == K_UP2:
            load_dir(os.path.dirname(cur_path))
        elif kind == K_CANCEL:
            running = False
        elif kind == K_DIR:
            load_dir(os.path.join(cur_path, txt[:-1]))
        else:
            write_out(os.path.join(cur_path, txt)); running = False; done = True
    else:
        write_out(txt); running = False; done = True

def on_escape():
    global running, FILTER
    if FILTER:
        FILTER = ''
        _refilter()
        return
    if MODE == 'browse':
        parent = os.path.dirname(cur_path)
        if parent != cur_path:
            load_dir(parent)
    else:
        running = False

def _refilter():
    if MODE == 'grid':
        grid_apply_filter()
    else:
        apply_filter()

def filter_add(ch):
    global FILTER
    FILTER += ch
    _refilter()

def filter_back():
    global FILTER
    if FILTER:
        FILTER = FILTER[:-1]
        _refilter()

def kb_press():
    global kb_open
    if kb_r == len(KB_ROWS):
        act = KB_ACTIONS[kb_c]
        if act in ('BORRAR', 'DELETE'):
            filter_back()
        elif act in ('LIMPIAR', 'CLEAR'):
            global FILTER
            FILTER = ''
            _refilter()
        else:                       # LISTO
            kb_open = False
    else:
        filter_add(KB_ROWS[kb_r][kb_c].lower())

def run_session():
    # Ejecuta UNA peticion (un menu, un teclado, una barra de progreso)
    # y devuelve su codigo de salida. En modo servidor se llama muchas
    # veces sobre la MISMA ventana; en modo suelto, una sola vez.
    global MODE, TITLE, OUTFILE, ARG4, BROWSE_KIND, items
    global view, cur_path, sel, scroll, FILTER, kb_open
    global kb_r, kb_c, GITEMS, running, done, screen
    global FULLSCREEN, TITLE_LINES, T_FONT, T_LH, HEAD, ROW
    global PANEL_UI, ARCADE, TOP, LIST_X, LIST_Y, LIST_W
    global LIST_H, SIDE_X, SIDE_W, VIS_FULL, VIS_KB
    # estado del teclado virtual: sus funciones internas lo declaran global,
    # asi que run_session tiene que declararlo tambien o quedaria como local
    global TXT, shift, tr_r, tr_c

    if MODE == 'canvas':
        # Fondo persistente para el MODO JUEGO de SteamOS.
        #
        # El problema: cada menu abria y cerraba su ventana. Al salir de un juego,
        # gamescope se quedaba sin ninguna superficie nuestra y no sabia a quien
        # devolver el foco: el menu siguiente nacia detras y parecia que WProton
        # no volvia. Con esta ventana SIEMPRE viva, el compositor siempre tiene a
        # donde volver, y los menus se dibujan encima de ella.
        #
        # Se cierra sola cuando el fichero de estado dice STOP (o desaparece).
        clockC = pygame.time.Clock()
        status = ''
        misses = 0
        while True:
            for ev in pygame.event.get():
                if ev.type == pygame.QUIT:
                    safe_quit(0)
            try:
                with open(ARG4, encoding='utf-8') as fh:
                    status = fh.readline().strip()
                misses = 0
            except Exception:
                misses += 1
                if misses > 40:            # el fichero ya no esta: nos vamos
                    safe_quit(0)
            if status.startswith('STOP'):
                safe_quit(0)
            screen.blit(BGSURF, (0, 0))
            if PANEL_UI:
                draw_header()
            # marca centrada
            big = pygame.font.Font(None, max(48, W // 14))
            # Composicion vertical a partir de la ALTURA REAL de la marca: antes
            # se usaban distancias fijas y con la letra grande el texto de estado
            # se montaba encima de "WPROTON".
            brand = big.render('WPROTON', True, ACC)
            try:
                bh = brand.get_height()
            except Exception:
                bh = FS(96)
            by = H // 2 - bh
            screen.blit(brand, ((W - brand.get_width()) // 2, by))
            _y = by + bh + FS(28)          # el estado empieza DEBAJO de la marca
            if status:
                for _ln in wrap_title(status, f_it, W - 120, 3):
                    sf = rtext(f_it, _ln, FG)
                    screen.blit(sf, ((W - sf.get_width()) // 2, _y))
                    _y += FS(34)
            # punto animado, para que se vea que sigue vivo
            _p = int(time.time() * 2) % 4
            dots = rtext(f_sm, '.' * _p, DIM)
            screen.blit(dots, ((W - dots.get_width()) // 2, _y + FS(16)))
            if SCANSURF is not None:
                screen.blit(SCANSURF, (0, 0))
            pygame.display.flip()
            _last_frame[0] = time.time()
            clockC.tick(15)          # muy poco consumo: no compite con el juego

    if MODE == 'progress':
        # Ventana de espera: lee "pct|texto" del fichero de estado hasta DONE
        bar_pct, bar_txt = 0, L('Preparando...', 'Preparing...')
        clock2 = pygame.time.Clock()
        while True:
            for ev in pygame.event.get():
                if ev.type == pygame.QUIT:
                    pygame.quit(); sys.exit(0)
            try:
                with open(ARG4, encoding='utf-8') as fh:
                    raw = fh.readline().rstrip('\n')
                if raw.startswith('DONE'):
                    break
                p, _, t = raw.partition('|')
                bar_pct = max(0, min(100, int(p or 0)))
                bar_txt = t or bar_txt
            except Exception:
                pass
            screen.blit(BGSURF, (0, 0))
            for _i, _tl in enumerate(TITLE_LINES):
                screen.blit(rtext(T_FONT, _tl, FG), (24, 22 + _i * T_LH))
            pygame.draw.line(screen, (60, 64, 74), (24, HEAD - 8), (W - 24, HEAD - 8), 1)
            screen.blit(f_it.render(fit_label(bar_txt, f_it, W - 60), True, FG), (30, HEAD + 24))
            bx, by, bw, bh = 30, HEAD + 74, W - 60, 26
            pygame.draw.rect(screen, TH['card'], (bx, by, bw, bh), border_radius=RAD)
            if TH['panel'] is not None:
                pygame.draw.rect(screen, TH['border'], (bx, by, bw, bh), 1, border_radius=RAD)
            if bar_pct > 0:
                pygame.draw.rect(screen, ACC if TH['glow'] else HIBG,
                                 (bx, by, int(bw * bar_pct / 100.0), bh), border_radius=RAD)
            else:
                t0 = (time.time() * 220) % (bw * 2)
                xx = t0 if t0 < bw else (bw * 2 - t0)
                pygame.draw.rect(screen, ACC if TH['glow'] else HIBG,
                                 (bx + max(0, min(bw - 140, xx - 70)), by, 140, bh), border_radius=RAD)
            if bar_pct:
                screen.blit(f_sm.render('%d%%' % bar_pct, True, DIM), (bx, by + bh + 8))
            screen.blit(f_sm.render(L('Espera, esto puede tardar...', 'Please wait, this may take a while...'), True, DIM), (24, H - 40))
            if SCANSURF is not None:
                screen.blit(SCANSURF, (0, 0))
            pygame.display.flip()
            _last_frame[0] = time.time()
            clock2.tick(30)
        pygame.quit()
        sys.exit(0)

    if MODE == 'text':
        # Editor de una linea con teclado en pantalla: para argumentos, DLL
        # overrides, notas... Se maneja con el mando (o el teclado real).
        TXT = ARG4 if len(sys.argv) > 4 else ''
        TROWS = ['1234567890-=',
                 'qwertyuiop[]',
                 'asdfghjkl;\'',
                 'zxcvbnm,./\\',
                 ' _:"|+*@#$%&']
        TACT = [L('MAYUS', 'SHIFT'), L('BORRAR', 'DELETE'),
                L('LIMPIAR', 'CLEAR'), L('ACEPTAR', 'ACCEPT'), L('CANCELAR', 'CANCEL')]
        tr_r, tr_c, shift = 0, 0, False
        clockT = pygame.time.Clock()
        t_open2 = time.time()

        def tcols(r):
            return len(TACT) if r == len(TROWS) else len(TROWS[r])

        def t_press():
            global TXT, shift, tr_r, tr_c
            if tr_r == len(TROWS):
                act = TACT[tr_c]
                if act in ('MAYUS', 'SHIFT'):
                    shift = not shift
                elif act in ('BORRAR', 'DELETE'):
                    TXT = TXT[:-1]
                elif act in ('LIMPIAR', 'CLEAR'):
                    TXT = ''
                elif act in ('ACEPTAR', 'ACCEPT'):
                    return 'ok'
                else:
                    return 'cancel'
            else:
                ch = TROWS[tr_r][tr_c]
                TXT += ch.upper() if shift else ch
            return None

        while True:
            for ev in pygame.event.get():
                if ev.type == pygame.QUIT:
                    safe_quit(1)
                if ev.type != pygame.KEYDOWN:
                    continue
                if time.time() - t_open2 < 0.35:
                    continue
                if ev.key == pygame.K_UP:
                    tr_r = (tr_r - 1) % (len(TROWS) + 1); tr_c = min(tr_c, tcols(tr_r) - 1)
                elif ev.key == pygame.K_DOWN:
                    tr_r = (tr_r + 1) % (len(TROWS) + 1); tr_c = min(tr_c, tcols(tr_r) - 1)
                elif ev.key == pygame.K_LEFT:
                    tr_c = (tr_c - 1) % tcols(tr_r)
                elif ev.key == pygame.K_RIGHT:
                    tr_c = (tr_c + 1) % tcols(tr_r)
                elif ev.key in (pygame.K_RETURN, pygame.K_KP_ENTER):
                    r = t_press()
                    if r == 'ok':
                        write_out(TXT); safe_quit(0)
                    if r == 'cancel':
                        safe_quit(1)
                elif ev.key == pygame.K_SPACE:      # X del mando: borrar
                    TXT = TXT[:-1]
                elif ev.key == pygame.K_BACKSPACE:
                    TXT = TXT[:-1]
                elif ev.key == pygame.K_TAB:        # Y: aceptar rapido
                    write_out(TXT); safe_quit(0)
                elif ev.key == pygame.K_ESCAPE:
                    safe_quit(1)
                else:
                    ch = getattr(ev, 'unicode', '')
                    if ch and ch.isprintable():
                        TXT += ch

            screen.blit(BGSURF, (0, 0))
            if PANEL_UI:
                draw_header()
            else:
                for _i, _tl in enumerate(TITLE_LINES):
                    screen.blit(rtext(T_FONT, _tl, FG), (24, 22 + _i * T_LH))
                pygame.draw.line(screen, TH['border'], (24, HEAD - 8), (W - 24, HEAD - 8), 1)
            # caja de texto
            bx, by, bw, bh = 30, HEAD + 20, W - 60, 54
            pygame.draw.rect(screen, TH['card'], (bx, by, bw, bh), border_radius=RAD)
            pygame.draw.rect(screen, ACC, (bx, by, bw, bh), 2, border_radius=RAD)
            cursor = '_' if int(time.time() * 2) % 2 == 0 else ' '
            shown = TXT
            while f_it.render(shown + cursor, True, FG).get_width() > bw - 24 and shown:
                shown = shown[1:]
            screen.blit(f_it.render(shown + cursor, True, FG), (bx + 12, by + 14))
            # teclado
            ky0 = by + bh + 26
            cw = (W - 80) // 12
            for r, row in enumerate(TROWS):
                for c, ch in enumerate(row):
                    x = 40 + c * cw
                    y = ky0 + r * 44
                    if r == tr_r and c == tr_c:
                        draw_selection((x - 8, y - 6, cw - 6, 38))
                    lab = ch.upper() if shift else ch
                    if ch == ' ':
                        lab = L('ESP', 'SPC')
                    screen.blit(f_it.render(lab, True, FG), (x, y))
            aw = (W - 80) // len(TACT)
            for c, act in enumerate(TACT):
                x = 40 + c * aw
                y = ky0 + len(TROWS) * 44
                if tr_r == len(TROWS) and c == tr_c:
                    draw_selection((x - 8, y - 6, aw - 14, 38))
                col = ACC if act in ('ACEPTAR', 'ACCEPT') else (
                      WARN if act in ('MAYUS', 'SHIFT') and shift else FG)
                screen.blit(f_it.render(act, True, col), (x, y))
            hint2 = L('Dpad: moverse   A: pulsar   X: borrar   Y: aceptar   B: cancelar',
                      'Dpad: move   A: press   X: delete   Y: accept   B: cancel')
            if PANEL_UI:
                draw_footer([('A', L('pulsar', 'press')), ('X', L('borrar', 'delete')),
                             ('Y', L('aceptar', 'accept')), ('B', L('cancelar', 'cancel'))])
            else:
                screen.blit(f_sm.render(hint2, True, DIM), (24, H - 40))
            if SCANSURF is not None:
                screen.blit(SCANSURF, (0, 0))
            pygame.display.flip()
            _last_frame[0] = time.time()
            clockT.tick(30)

    running, done = True, False
    GRACE = 0.35
    t_open = time.time()
    def ready():
        return time.time() - t_open >= GRACE

    _last_key = [None, 0.0]
    DEBOUNCE = 0.08
    while running:
        for ev in pygame.event.get():
            if ev.type == pygame.QUIT:
                running = False
            elif ev.type == pygame.KEYDOWN:
                t_now = time.time()
                if ev.key == _last_key[0] and (t_now - _last_key[1]) < DEBOUNCE:
                    continue
                _last_key[0], _last_key[1] = ev.key, t_now
                if ev.key == pygame.K_F11:
                    toggle_fullscreen()
                    continue
                if kb_open:
                    # --- navegacion del teclado virtual ---
                    if ev.key == pygame.K_UP:
                        kb_r = (kb_r - 1) % (len(KB_ROWS) + 1)
                        kb_c = min(kb_c, kb_cols(kb_r) - 1)
                    elif ev.key == pygame.K_DOWN:
                        kb_r = (kb_r + 1) % (len(KB_ROWS) + 1)
                        kb_c = min(kb_c, kb_cols(kb_r) - 1)
                    elif ev.key == pygame.K_LEFT:
                        kb_c = (kb_c - 1) % kb_cols(kb_r)
                    elif ev.key == pygame.K_RIGHT:
                        kb_c = (kb_c + 1) % kb_cols(kb_r)
                    elif ev.key in (pygame.K_RETURN, pygame.K_KP_ENTER):
                        if ready(): kb_press()
                    elif ev.key == pygame.K_SPACE:
                        if ready(): filter_back()          # X = borrar
                    elif ev.key in (pygame.K_ESCAPE, pygame.K_TAB):
                        if ready(): kb_open = False        # B / Y = cerrar
                    elif ev.key == pygame.K_BACKSPACE:
                        filter_back()
                    else:
                        ch = getattr(ev, 'unicode', '')
                        if ch and ch.isprintable():
                            filter_add(ch)
                else:
                    if ev.key == pygame.K_ESCAPE:
                        if ready(): on_escape()
                    elif ev.key in (pygame.K_RETURN, pygame.K_KP_ENTER):
                        if ready(): on_enter()
                    elif ev.key == pygame.K_UP:
                        if MODE == 'grid': grid_move(0, -1)
                        else: move(-1)
                    elif ev.key == pygame.K_DOWN:
                        if MODE == 'grid': grid_move(0, 1)
                        else: move(1)
                    elif ev.key == pygame.K_LEFT:
                        if MODE == 'grid': grid_move(-1, 0)
                    elif ev.key == pygame.K_RIGHT:
                        if MODE == 'grid': grid_move(1, 0)
                    elif ev.key == pygame.K_TAB:
                        # Y del mando (o Tab): abrir teclado de busqueda
                        if ready() and MODE != 'check':
                            kb_open = True
                            kb_r, kb_c = 0, 0
                            scroll = max(0, min(scroll, max(0, len(view) - VIS_KB)))
                    elif ev.key == pygame.K_BACKSPACE:
                        filter_back()
                    elif ev.key == pygame.K_F1:
                        # L1: ficha del juego, sin pasar por configuracion
                        if ready() and ACTION_X and MODE in ('list', 'grid'):
                            action_sobre_juego('INFO')
                    elif ev.key == pygame.K_F2:
                        # R1: marcar o quitar favorito AQUI MISMO. Antes se
                        # cerraba el menu, lo aplicaba WProton y se volvia a
                        # abrir: funcionaba, pero se notaba el parpadeo. Ahora
                        # el cambio se ve al instante y se apunta en un fichero
                        # que WProton aplica al salir del menu.
                        if ready() and ACTION_X and MODE in ('list', 'grid'):
                            marcar_favorito()
                    elif ev.key == pygame.K_SPACE:
                        if ready():
                            if MODE == 'check':
                                toggle()
                            elif ACTION_X and MODE in ('list', 'grid'):
                                action_x()
                            else:
                                on_enter()
                    else:
                        # TYPE-AHEAD con teclado real: filtra al escribir
                        if MODE != 'check':
                            ch = getattr(ev, 'unicode', '')
                            if ch and ch.isprintable():
                                filter_add(ch)

        screen.blit(BGSURF, (0, 0))
        if PANEL_UI:
            draw_header()
            draw_panel((LIST_X - 6, LIST_Y, LIST_W + 12, LIST_H))
            draw_side_panel()
        else:
            for _i, _tl in enumerate(TITLE_LINES):
                screen.blit(rtext(T_FONT, _tl, FG), (24, 22 + _i * T_LH))
            if MODE == 'browse':
                screen.blit(f_sm.render(shorten(cur_path), True, DIM), (24, HEAD - 8))
                _ry = HEAD + 20
            else:
                _ry = HEAD - 8
            pygame.draw.line(screen, TH['border'], (24, _ry), (W - 24, _ry), 1)

        if MODE == 'grid':
            draw_grid()
        for i in ([] if MODE == 'grid' else range(scroll, min(scroll + vis(), len(view)))):
            y = LIST_Y + 8 + (i - scroll) * ROW
            _rect = (LIST_X, y - 4, LIST_W, ROW - 6)
            if TH.get('btn'):
                draw_button(_rect, i == sel and not kb_open)
                if i == sel and not kb_open and TH.get('marker'):
                    try:
                        pygame.draw.polygon(screen, ACC,
                            [(LIST_X + 20, y + ROW // 2 - 4), (LIST_X + 10, y + 2),
                             (LIST_X + 10, y + ROW - 14)])
                    except Exception:
                        pass
            else:
                if PANEL_UI and i != sel:
                    pygame.draw.rect(screen, TH['card'], _rect, border_radius=RAD)
                if i == sel and not kb_open:
                    draw_selection(_rect)
            kind, txt, on = items[view[i]]
            favorito_aqui = False
            if MODE == 'check':
                label = ('[x] ' if on else '[  ] ') + txt
                color = ACC if on else FG
            elif kind == K_DIR:
                label, color = txt, DIRC
            elif kind in HEADER_KINDS:
                label, color = txt, (ACC if kind == K_HDR else DIM)
            else:
                label, color = txt, FG
                # Marca de favorito en la propia lista: al pulsar R1 se ve al
                # momento cual esta marcado, sin tener que mirar el panel.
                if MODE == 'list' and LIST_INFO.get(txt, {}).get('fav') == '1':
                    favorito_aqui = True
            _tx = LIST_X + (18 if PANEL_UI else 14)
            if TH.get('numbered'):
                _tx += 46
                screen.blit(f_sm.render('%02d' % (i + 1), True, ACC if i == sel else TH['border']),
                            (LIST_X + 28, y + 12))
            _ty = y + (6 if PANEL_UI else 0)
            _tw = LIST_X + LIST_W - _tx - 18     # ancho util hasta el borde
            if TH.get('shadow'):
                draw_row_text(label, f_it, (0, 0, 0), _tx + 2, _ty + 2, _tw, i == sel)
            if favorito_aqui:
                # Estrella a la DERECHA de la fila: delante quedaba pegada al
                # nombre y descuadrada. Se reserva su hueco para que el texto
                # largo no la pise.
                _tw -= FS(26)
                draw_estrella(LIST_X + LIST_W - FS(24), y + ROW // 2,
                              FS(8), TH.get('acc2', ACC))
            if kind in HEADER_KINDS or MODE == 'check':
                draw_row_text(label, f_it, color, _tx, _ty, _tw, i == sel)
            else:
                draw_segments(row_segments(label, color), f_it, _tx, _ty, _tw, i == sel)
        if not view and FILTER:
            screen.blit(f_it.render("(sin coincidencias para '%s')" % FILTER, True, WARN),
                        (LIST_X + 14, LIST_Y + 14))

        # Barra lateral: avisa de que hay más opciones de las que caben en pantalla
        _total = len(view)
        _vis = (grid_rows_vis() * GCOLS) if MODE == 'grid' else vis()
        if _total > _vis:
            _tr_x = (LIST_X + LIST_W + 2) if PANEL_UI else (W - 14)
            _tr_y = LIST_Y + 8
            _tr_h = LIST_H - 16
            pygame.draw.rect(screen, TH['card'], (_tr_x, _tr_y, 6, _tr_h), border_radius=3)
            _kh = max(28, int(_tr_h * _vis / float(_total)))
            _maxoff = max(1, _total - _vis)
            _ky = _tr_y + int((_tr_h - _kh) * min(1.0, scroll / float(_maxoff)))
            pygame.draw.rect(screen, ACC if TH['glow'] else (120, 130, 150),
                             (_tr_x, _ky, 6, _kh), border_radius=3)
        if view and not PANEL_UI:
            pos = f_sm.render('%d/%d' % (sel + 1, len(view)), True, DIM)
            screen.blit(pos, (W - 24 - pos.get_width(), max(4, HEAD - 30)))
        if (FILTER or kb_open) and not PANEL_UI:
            ft = f_sm.render('Buscar: %s_' % FILTER, True, WARN)
            screen.blit(ft, (W - 24 - ft.get_width(), max(24, HEAD - 30)))

        if kb_open:
            ky0 = H - KB_H - 44
            pygame.draw.rect(screen, KBBG, (12, ky0 - 8, W - 24, KB_H + 8), border_radius=RAD)
            if TH['panel'] is not None:
                pygame.draw.rect(screen, TH['border'], (12, ky0 - 8, W - 24, KB_H + 8), 1, border_radius=RAD)
            cw = (W - 60) // 10
            for r, row in enumerate(KB_ROWS):
                for c, ch in enumerate(row):
                    x = 30 + c * cw
                    y = ky0 + r * 36
                    if r == kb_r and c == kb_c:
                        draw_selection((x - 6, y - 4, cw - 6, 32))
                    lab = 'ESP' if ch == ' ' else ch
                    screen.blit(f_kb.render(lab, True, FG), (x, y))
            aw = (W - 60) // len(KB_ACTIONS)
            for c, act in enumerate(KB_ACTIONS):
                x = 30 + c * aw
                y = ky0 + len(KB_ROWS) * 36
                if kb_r == len(KB_ROWS) and c == kb_c:
                    draw_selection((x - 6, y - 4, aw - 12, 32))
                screen.blit(f_kb.render(act, True, ACC if act == 'LISTO' else FG), (x, y))

        if kb_open:
            hint = 'Dpad: moverse   A: pulsar   X: borrar   B/Y: cerrar teclado'
        elif MODE == 'check':
            hint = 'X/Espacio: marcar   A/Enter: aceptar   B/Esc: cancelar'
        elif MODE == 'browse':
            hint = 'A: entrar/elegir   B: subir   Y: buscar   (o escribe para filtrar)'
        elif MODE == 'grid':
            hint = ('A: jugar  X: configurar  L1: ficha  R1: favorito  B: volver' if ACTION_X
                    else 'Dpad: moverse   A: jugar   B: volver   Y: buscar   Select+A/F11: pantalla')
        else:
            hint = 'A: elegir   B: volver   Y: buscar   Select+A/F11: pantalla completa'
        if PANEL_UI:
            if kb_open:
                _chips = [('Dpad', L('moverse', 'move')), ('A', L('pulsar', 'press')),
                          ('X', L('borrar', 'delete')), ('B/Y', L('cerrar', 'close'))]
            elif MODE == 'check':
                _chips = [('X', L('marcar', 'toggle')), ('A', L('aceptar', 'accept')),
                          ('B', L('cancelar', 'cancel'))]
            elif MODE == 'browse':
                _chips = [('A', L('entrar', 'enter')), ('B', L('subir', 'up')),
                          ('Y', L('buscar', 'search')), ('Sel+A', L('pantalla', 'screen'))]
            elif MODE == 'grid':
                _chips = [('A', L('jugar', 'play')), ('X', L('config', 'config')),
                          ('Y', L('buscar', 'search')), ('L1', L('ficha', 'info')),
                          ('R1', L('favorito', 'favourite')),
                          ('B', L('volver', 'back'))] if ACTION_X else \
                         [('Dpad', L('moverse', 'move')), ('A', L('jugar', 'play')),
                          ('B', L('volver', 'back')), ('Y', L('buscar', 'search'))]
            else:
                _chips = [('A', L('jugar', 'play')), ('X', L('config', 'config')),
                          ('Y', L('buscar', 'search')), ('L1', L('ficha', 'info')),
                          ('R1', L('favorito', 'favourite')),
                          ('B', L('volver', 'back'))] if ACTION_X else \
                         [('A', L('elegir', 'choose')), ('B', L('volver', 'back')),
                          ('Y', L('buscar', 'search')), ('Sel+A', L('pantalla', 'screen'))]
            draw_footer(_chips)
        else:
            screen.blit(f_sm.render(hint, True, DIM), (24, H - 40))
        if SCANSURF is not None:
            screen.blit(SCANSURF, (0, 0))
        try:
            pygame.display.flip()
            _last_frame[0] = time.time()
        except Exception as _e:
            # El servidor X de gamescope puede desaparecer al cerrarse un juego
            # ("XIO: fatal IO error"). Salimos con codigo 2 para que WProton
            # reabra el menu, en vez de morir con un traceback.
            sys.stderr.write('menu_pygame: se perdio la pantalla (%s)\n' % _e)
            safe_quit(2)
        clock.tick(60)

    _mark_clean_exit()
    return 0 if done else 1


# ---------------------------------------------------------------------------
# PUNTO DE ENTRADA
#
#   menu_pygame.py <modo> <titulo> <salida> [arg4] [tipo]   -> una peticion
#   menu_pygame.py server <carpeta>                         -> servidor
#
# En modo SERVIDOR el proceso (y su ventana) NO se cierran entre menus: se
# queda en reposo esperando la siguiente peticion. Eso quita el parpadeo al
# cambiar de menu y, en el modo Juego de SteamOS, evita que el compositor se
# quede sin ninguna ventana nuestra al salir de un juego.
#
# Protocolo, deliberadamente simple (ficheros, sin dependencias):
#   <carpeta>/req      peticion: una linea por campo
#   <carpeta>/req.ready  marca de "peticion lista"
#   <carpeta>/resp     codigo de salida de la sesion
#   <carpeta>/stop     si aparece, el servidor termina
# ---------------------------------------------------------------------------

def draw_idle(status=''):
    # Pantalla de reposo entre peticiones: la ventana sigue viva.
    # Se vacia la cola de eventos para que las pulsaciones hechas mientras
    # no habia menu no se apliquen de golpe al abrir el siguiente.
    try:
        pygame.event.clear()
    except Exception:
        pass
    if BGSURF is not None:
        screen.blit(BGSURF, (0, 0))
    else:
        screen.fill(TH['bg'])
    big = pygame.font.Font(None, max(48, W // 14))
    brand = big.render('WPROTON', True, ACC)
    try:
        bh = brand.get_height()
    except Exception:
        bh = FS(96)
    by = H // 2 - bh
    screen.blit(brand, ((W - brand.get_width()) // 2, by))
    if status:
        sf = rtext(f_it, status, FG)
        screen.blit(sf, ((W - sf.get_width()) // 2, by + bh + FS(24)))
    if SCANSURF is not None:
        screen.blit(SCANSURF, (0, 0))
    try:
        pygame.display.flip()
        _last_frame[0] = time.time()
    except Exception:
        pass

def serve(dirpath):
    global SERVER_MODE
    SERVER_MODE = True
    # El fondo (BGSURF) se construye al calcular la disposicion. En modo
    # servidor la primera pantalla es el reposo, ANTES de cualquier peticion,
    # asi que hay que prepararlo aqui o no habria nada que dibujar.
    set_request('list', '', '')
    compute_layout()
    req = os.path.join(dirpath, 'req')
    ready = os.path.join(dirpath, 'req.ready')
    resp = os.path.join(dirpath, 'resp')
    stop = os.path.join(dirpath, 'stop')
    idle = pygame.time.Clock()
    sys.stderr.write('menu_pygame: servidor de menus en %s\n' % dirpath)
    status = ''
    while True:
        if os.path.isfile(stop):
            try:
                os.remove(stop)
            except Exception:
                pass
            break
        if os.path.isfile(ready):
            try:
                with open(req, encoding='utf-8') as fh:
                    campos = fh.read().split('\n')
            except Exception:
                campos = []
            try:
                os.remove(ready)
            except Exception:
                pass
            while len(campos) < 9:
                campos.append('')
            # Los campos vienen con los saltos de linea escapados como \n:
            # el protocolo es una linea por campo y los titulos tienen varias.
            def _desescapa(v):
                out = []
                i = 0
                while i < len(v):
                    if v[i] == '\\' and i + 1 < len(v):
                        if v[i + 1] == 'n':
                            out.append('\n'); i += 2; continue
                        if v[i + 1] == '\\':
                            out.append('\\'); i += 2; continue
                    out.append(v[i]); i += 1
                return ''.join(out)
            campos = [_desescapa(c) for c in campos[:9]]
            (modo, titulo, salida, arg4, kind, ax,
             manif, presel, favf) = campos
            if modo == 'idle':
                # sin menu: solo actualizar el texto del reposo
                status = titulo
            elif modo:
                set_request(modo, titulo, salida, arg4 or None,
                            kind or 'file', ax == '1', manif or None,
                            presel or None, favf or None)
                load_request_data()
                compute_layout()
                try:
                    rc = run_session()
                except SessionEnd as e:
                    rc = e.code
                except SystemExit as e:
                    rc = e.code if isinstance(e.code, int) else 0
                except Exception as e:
                    sys.stderr.write('menu_pygame: fallo en la peticion (%s)\n' % e)
                    rc = 2
                try:
                    with open(resp, 'w', encoding='utf-8') as fh:
                        fh.write(str(rc))
                except Exception:
                    pass
                # limpiar el estado visible entre menus
                pygame.event.clear()
            continue
        try:
            draw_idle(status)
        except Exception as e:
            # un fallo dibujando el reposo no puede tumbar el servidor:
            # se anota y se sigue, que el usuario aun tiene sus menus
            sys.stderr.write('menu_pygame: reposo: %s\n' % e)
            time.sleep(1.0)
        idle.tick(15)
    sys.stderr.write('menu_pygame: servidor detenido\n')
    try:
        pygame.quit()
    except Exception:
        pass
    sys.exit(0)

if sys.argv[1] == 'server':
    serve(sys.argv[2])
else:
    set_request(sys.argv[1], sys.argv[2], sys.argv[3],
                sys.argv[4] if len(sys.argv) > 4 else None,
                sys.argv[5] if len(sys.argv) > 5 else 'file',
                os.environ.get('WP_ACTION_X') == '1',
                os.environ.get('WP_LIST_INFO') or None,
                os.environ.get('WP_PRESEL') or None,
                os.environ.get('WP_FAV_FILE') or None)
    load_request_data()
    compute_layout()
    rc = run_session()
    pygame.quit()
    sys.exit(rc)
