# WPROTON_MAPEADOR_V60 (fusionado desde mapeador-60.py de DeckStation)
# Rutas dinamicas: libs_pyX.Y del runtime de WProton + evmapy/ (raiz o runtime)
import sys, os
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

# Mapeos de ejes analógicos por defecto para mandos estándar
ABS_ESTANDAR = {
    ecodes.ABS_Y:     ("joystick1up",   "joystick1down"),
    ecodes.ABS_X:     ("joystick1left",  "joystick1right"),
    ecodes.ABS_RY:    ("joystick2up",   "joystick2down"),
    ecodes.ABS_RX:    ("joystick2left",  "joystick2right"),
    ecodes.ABS_HAT0Y: ("up",            "down"),
    ecodes.ABS_HAT0X: ("left",          "right"),
}

PERFILES = {
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
    "SONY_DS4": {
        "match": ["sony", "playstation", "wireless controller", "dualshock 4", "ps4"],
        "ids": {
            "a": 304, "b": 305, "x": 307, "y": 308,
            "start": 313, "select": 312, "hotkey": 312,
            "pageup": 310, "pagedown": 311,
            "l2": 316, "r2": 317, "l3": 318, "r3": 319
        },
        "abs_map": ABS_ESTANDAR, "threshold": 16000, "center": 0
    },
    "SONY_PS5": {
        "match": ["dualsense", "ps5"],
        "ids": {
            "a": 304, "b": 305, "x": 307, "y": 308,
            "start": 313, "select": 312, "hotkey": 312,
            "pageup": 310, "pagedown": 311,
            "l2": 314, "r2": 315, "l3": 317, "r3": 318
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
        "match": ["nintendo", "switch", "pro controller", "joy-con"],
        "ids": {
            "a": 305, "b": 304, "x": 309, "y": 308,
            "start": 313, "select": 312, "hotkey": 312,
            "pageup": 310, "pagedown": 311,
            "l2": 314, "r2": 315, "l3": 317, "r3": 318
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

def get_perfil(dev_name):
    name = dev_name.lower()
    for p in PERFILES.values():
        if any(m in name for m in p["match"]):
            return p
    return PERFILES["GENERIC"]



def launch_teclado_virtual(device):
    try:
        import pygame
    except ImportError:
        print("[!] pygame no disponible"); return
    try:
        _run_teclado(device)
    except Exception as e:
        print(f"[!] Error teclado virtual: {e}")

def _run_teclado(gamepad_device):
    import pygame, evdev as _evdev, select as _sel, time as _tm
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
    _os.environ['SDL_VIDEODRIVER'] = 'x11'  # XWayland
    pygame.init()
    info = pygame.display.Info()
    _os.environ['SDL_VIDEO_WINDOW_POS'] = f'{(info.current_w-total_w)//2},{info.current_h-total_h-30}'
    screen = pygame.display.set_mode((total_w, total_h), pygame.NOFRAME)
    # Aplicar override_redirect=True via XChangeWindowAttributes + unmap/remap
    # override_redirect impide que KWin gestione la ventana → no le da foco de teclado
    # Usamos X11 API directamente porque SDL_VIDEO_X11_OVERRIDE_REDIRECT no es fiable
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
            _x11.XCloseDisplay(_ct.c_void_p(_dpy))
    except: pass
    fk=pygame.font.SysFont('DejaVu Sans',18,bold=True)
    fp=pygame.font.SysFont('DejaVu Sans',20)
    try:
        ui_kb=_evdev.UInput({ec.EV_KEY:list(range(256))},name="TecladoVirtual_DS")
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
        # UInput: el juego tiene foco Wayland (override-redirect + KWin activateWindow)
        # el compositor entrega los eventos al juego directamente
        if shift: ui_kb.write(ec.EV_KEY, ec.KEY_LEFTSHIFT, 1); ui_kb.syn()
        ui_kb.write(ec.EV_KEY, code, 1); ui_kb.syn()
        ui_kb.write(ec.EV_KEY, code, 0); ui_kb.syn()
        if shift: ui_kb.write(ec.EV_KEY, ec.KEY_LEFTSHIFT, 0); ui_kb.syn()
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
    while running:
        dt=clock.tick(60)/1000.0; now=_tm.time()
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
        rr,_,_=_sel.select([gamepad_device],[],[],0)
        if rr:
            try:
                for ev in gamepad_device.read():
                    if ev.type==ec.EV_ABS: ax_val[ev.code]=ev.value
                    elif ev.type==ec.EV_KEY and ev.value==1:
                        if ev.code==304:
                            mr,mc=key_at(cx,cy)
                            if mr is not None: row,col=mr,mc
                            r=do_key(ROWS[row][col],shift)
                            if r=='shift': shift=not shift
                            elif r=='close': running=False
                        elif ev.code==305: press_k(ec.KEY_BACKSPACE,False); preview=preview[:-1]
                        elif ev.code==308: press_k(ec.KEY_SPACE,False); preview+=' '
                        elif ev.code in (315,313): running=False
                        elif ev.code in (314,312): shift=not shift
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
    ui_kb.close(); pygame.quit()

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
    ids            = perfil_actual["ids"]
    abs_map_actual = perfil_actual["abs_map"]
    threshold      = perfil_actual["threshold"]
    center         = perfil_actual["center"]

    map_normal = {}
    map_combos = []
    DIR_KEYS = [
        "up", "down", "left", "right",
        "joystick1up", "joystick1down", "joystick1left", "joystick1right",
        "joystick2up", "joystick2down", "joystick2left", "joystick2right",
    ]
    map_dirs = {k: [] for k in DIR_KEYS}

    for act in data.get('actions_player1', []):
        trig, target = act['trigger'], act['target']
        is_kb = (target == "TECLADO_VIRTUAL")
        t_codes = [] if is_kb else [getattr(ecodes, t)
                   for t in (target if isinstance(target, list) else [target])
                   if hasattr(ecodes, t)]
        if isinstance(trig, list):
            map_combos.append({"req": [ids.get(x, x) for x in trig], "outs": t_codes,
                               "active": False, "kb": is_kb})
        elif trig in map_dirs:
            map_dirs[trig] = t_codes
        elif trig in ids:
            map_normal[ids[trig]] = t_codes

    # ── Teclado virtual para shortcuts ──────────────────────────────────────
    try:
        ui = evdev.UInput(name="Mapeador_KB_Portable")
    except Exception as e:
        print(f"ERROR UInput teclado: {e}")
        return

    import time as _tm
    _mcfg=data.get("mouse",{})
    _MAXIS={"joystick1":(ecodes.ABS_X,ecodes.ABS_Y),"joystick2":(ecodes.ABS_RX,ecodes.ABS_RY)}
    _mabs_x,_mabs_y=_MAXIS.get(_mcfg.get("axis","joystick2"),(ecodes.ABS_RX,ecodes.ABS_RY))
    _mclick=ids.get(_mcfg.get("click_left","r2")) if _mcfg else None
    _mspeed=float(_mcfg.get("speed",900))
    # Mapa de triggers analógicos: en Xbox 360/One el R2 es ABS_RZ, no un botón digital
    _TRIG_ABS = {
        ids.get("r2"): (ecodes.ABS_RZ, ecodes.ABS_GAS),
        ids.get("l2"): (ecodes.ABS_Z,  ecodes.ABS_BRAKE),
    }
    _mclick_abs = _TRIG_ABS.get(_mclick, ()) if _mclick else ()
    _mclick_pressed = False  # Estado previo del trigger analógico
    ui_mouse=None
    if _mcfg:
        try:
            ui_mouse=evdev.UInput({ecodes.EV_REL:[ecodes.REL_X,ecodes.REL_Y],
                                   ecodes.EV_KEY:[ecodes.BTN_LEFT,ecodes.BTN_RIGHT]},
                                  name="Mapeador_Mouse_Portable")
            print(f"[+] Ratón: {_mcfg.get('axis','joystick2')} → mover | {_mcfg.get('click_left','r2')} → click")
        except Exception as e:
            print(f"[!] Sin ratón virtual: {e}"); ui_mouse=None
    _macc_x=0.0; _macc_y=0.0; _mlast=_tm.monotonic(); _msx=center; _msy=center

    pulsados = set()
    ejes_on  = {k: False for k in DIR_KEYS}

    try:
        while True:
            r, _, _ = select.select(pads, [], [], 0.001)
            for _dev in r:
                try:
                    for event in _dev.read():

                        # ── Botones digitales ────────────────────────────────
                        if event.type == ecodes.EV_KEY:
                            if event.value == 1:
                                pulsados.add(event.code)
                            elif event.value == 0:
                                pulsados.discard(event.code)

                            # Combos → teclado / acciones especiales
                            for c in map_combos:
                                all_pressed = all(btn in pulsados for btn in c["req"])
                                if all_pressed and not c["active"] and event.value == 1:
                                    c["active"] = True
                                    if c.get("kb"):
                                        ui.syn()
                                        try: launch_teclado_virtual(device)
                                        except Exception as _e: print(f"[!] {_e}")
                                        pulsados.clear()
                                    else:
                                        # dejar constancia: sin esto no habia
                                        # forma de saber si una combinacion
                                        # habia disparado o no
                                        print("[combo] %s -> %s" % (c["req"], c["outs"]),
                                              flush=True)
                                        for t in c["outs"]: ui.write(ecodes.EV_KEY, t, 1)
                                elif c["active"] and not all_pressed and event.value == 0:
                                    c["active"] = False
                                    if not c.get("kb"):
                                        for t in c["outs"]: ui.write(ecodes.EV_KEY, t, 0)

                            # Botón individual → teclado (solo si no está en combo activo)
                            in_active_combo = any(
                                event.code in c["req"] and c["active"] for c in map_combos
                            )
                            if not in_active_combo and event.code in map_normal:
                                for t in map_normal[event.code]:
                                    ui.write(ecodes.EV_KEY, t, event.value)

                            # Click digital (PS4, bumpers, botones)
                            if ui_mouse and _mclick and not _mclick_abs and event.code == _mclick:
                                ui_mouse.write(ecodes.EV_KEY,ecodes.BTN_LEFT,event.value)
                                ui_mouse.syn()
                            ui.syn()

                        # ── Ejes analógicos ──────────────────────────────────
                        elif event.type == ecodes.EV_ABS:
                            if event.code == _mabs_x: _msx = event.value
                            elif event.code == _mabs_y: _msy = event.value
                            # Click analógico: R2/L2 Xbox 360 mandan ABS_RZ/ABS_Z
                            elif ui_mouse and _mclick_abs and event.code in _mclick_abs:
                                _now_pressed = event.value > 64  # umbral: trigger > 25% de recorrido
                                if _now_pressed != _mclick_pressed:
                                    _mclick_pressed = _now_pressed
                                    ui_mouse.write(ecodes.EV_KEY, ecodes.BTN_LEFT,
                                                   1 if _now_pressed else 0)
                                    ui_mouse.syn()
                            # Mapeo de dirección → teclado
                            if event.code in abs_map_actual:
                                neg_dir, pos_dir = abs_map_actual[event.code]
                                val = event.value - center
                                neg_active = val < -threshold
                                pos_active = val > threshold
                                for direction, active in ((neg_dir, neg_active), (pos_dir, pos_active)):
                                    if active != ejes_on[direction]:
                                        ejes_on[direction] = active
                                        for t in map_dirs[direction]:
                                            ui.write(ecodes.EV_KEY, t, 1 if active else 0)

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
                        return
                    break
            if ui_mouse:
                _n=_tm.monotonic(); _dt=min(_n-_mlast,0.05); _mlast=_n
                _mr=32767.0 if center==0 else 127.0
                _rx=max(-1.0,min(1.0,(_msx-center)/_mr))
                _ry=max(-1.0,min(1.0,(_msy-center)/_mr))
                if abs(_rx)<0.12: _rx=0.0
                if abs(_ry)<0.12: _ry=0.0
                _macc_x+=_rx*_mspeed*_dt; _macc_y+=_ry*_mspeed*_dt
                _ix=int(_macc_x); _iy=int(_macc_y)
                if _ix: ui_mouse.write(ecodes.EV_REL,ecodes.REL_X,_ix); _macc_x-=_ix
                if _iy: ui_mouse.write(ecodes.EV_REL,ecodes.REL_Y,_iy); _macc_y-=_iy
                if _ix or _iy: ui_mouse.syn()
    finally:
        if ui_mouse:
            try: ui_mouse.close()
            except: pass

if __name__ == "__main__":
    main()

