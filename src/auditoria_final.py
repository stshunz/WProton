# -*- coding: utf-8 -*-
"""Auditoria final de WProton: coherencia entre el .base.sh, los modulos y el build."""
import os, re, subprocess, sys, fnmatch

BASE='wproton.base.sh'; GEN='wproton.sh'; SRC='src'
fallos=[]; avisos=[]
def F(m): fallos.append(m)
def A(m): avisos.append(m)

base=open(BASE,encoding='utf-8').read()
gen=open(GEN,encoding='utf-8').read()
build=open('build.sh',encoding='utf-8').read()
modulos=sorted(f for f in os.listdir(SRC) if f.endswith('.py'))

print("=" * 68)
print("AUDITORIA WProton")
print("=" * 68)

# --- 1. sintaxis ---
print("\n1. SINTAXIS")
for f in (BASE, GEN, 'build.sh', 'auditar.py'):
    # UN FICHERO QUE YA NO ESTA NO ES UN FALLO DE SINTAXIS.
    #
    # 'auditar.py' esta en la lista de siempre y se borro del proyecto. La
    # comprobacion lo daba por "no compila", que manda a buscar un error de
    # Python donde solo hay un fichero ausente. Se dice y se sigue.
    if not os.path.exists(f):
        print("   %-22s (no esta, se salta)" % f)
        continue
    if f.endswith('.py'):
        r=subprocess.run([sys.executable,'-m','py_compile',f],capture_output=True)
    else:
        r=subprocess.run(['bash','-n',f],capture_output=True)
    print("   %-22s %s" % (f, "OK" if r.returncode==0 else "FALLO"))
    if r.returncode: F("%s no compila" % f)
for m in modulos:
    r=subprocess.run([sys.executable,'-m','py_compile',os.path.join(SRC,m)],capture_output=True)
    if r.returncode: F("src/%s no compila" % m)
print("   %-22s %s" % ("los %d modulos"%len(modulos), "OK"))

# --- 2. auto-diagnostico de cada modulo ---
print("\n2. AUTO-DIAGNOSTICO DE LOS MODULOS")
# Solo los modulos que TIENEN auto-diagnostico. Los seis helpers originales
# (menu_pygame, mapeador, ...) no lo llevan y ademas necesitan pygame o evdev:
# lanzarles "comprobar" solo mide que aqui no hay tarjeta grafica.
for m in modulos:
    fuente=open(os.path.join(SRC,m),encoding='utf-8').read()
    if 'def comprobar(' not in fuente:
        print("   %-22s (sin auto-diagnostico)" % m); continue
    r=subprocess.run([sys.executable,os.path.join(SRC,m),'comprobar'],
                     capture_output=True,text=True,timeout=120)
    est="OK" if r.returncode==0 else "FALLO"
    print("   %-22s %s" % (m, est))
    if r.returncode: F("%s: %s" % (m, r.stderr.strip().replace('\n','; ')[:120]))

# --- 3. el build reproduce y cuadra ---
print("\n3. BUILD")
n_esp=re.search(r'\[ "\$n" -eq (\d+) \]', build)
incl=len(re.findall(r'@@INCLUIR:', base))+len(re.findall(r'@@INCLUIR_LANG@@|@@INCLUIR_DEFECTOS@@', base))
print("   marcadores en base: %d   esperados por build.sh: %s" % (incl, n_esp.group(1) if n_esp else '?'))
if n_esp and int(n_esp.group(1))!=incl:
    F("build.sh espera %s inserciones y en base hay %d" % (n_esp.group(1), incl))
for m in modulos:
    if '@@INCLUIR:%s@@'%m not in base: F("%s no se inserta en base" % m)
    if m not in build: F("%s no esta en la lista de build.sh" % m)
    if 'WPROTON_HELPER %s'%m not in gen: F("%s no lleva marca en el generado" % m)
print("   los %d modulos: insertados, en build.sh y con marca" % len(modulos))

# --- 4. python incrustado ---
print("\n4. PYTHON INCRUSTADO EN BASH")
n=lin=0
for mm in re.finditer(r'"\$(?:PY_BIN|SYS_PY)"\s+-c\s+\'(.*?)\'', base, re.S):
    n+=1; lin+=mm.group(1).count('\n')+1
for mm in re.finditer(r'"\$(?:PY_BIN|SYS_PY)"\s+-[^\n]*?<<\'([A-Z0-9_]+)\'', base):
    f=base.find('\n%s\n'%mm.group(1), mm.end())
    if f>0: n+=1; lin+=base[mm.end():f].count('\n')+1
print("   %d bloques / %d lineas  (solo sondas de arranque)" % (n,lin))
if lin>20: A("quedan %d lineas de python incrustado" % lin)

# --- 5. funciones definidas una sola vez y sin huerfanas ---
print("\n5. FUNCIONES")
defs=re.findall(r'^([a-z_][a-z0-9_]*)\(\)', gen, re.M)
dobles=sorted({d for d in defs if defs.count(d)>1})
print("   definidas: %d   duplicadas: %s" % (len(defs), dobles or "ninguna"))
for d in dobles: F("funcion definida dos veces: %s" % d)
llamadas=set(re.findall(r'(?:^|[\s;|&$(`])([a-z_][a-z0-9_]*)\b', gen))
huerf=[c for c in llamadas if c not in defs and re.search(r'(?:^|[\s;&|])%s[\s;&|]'%re.escape(c), gen) is None]
# LOS COMENTARIOS NO CUENTAN COMO USO.
#
# keys_ejemplo_crear se quedo huerfana al quitar su fila del menu y esta
# comprobacion no la vio: dentro de teclas.py hay un comentario que la nombra
# ("keys_ejemplo_crear() -> ejemplo()"), asi que salian dos apariciones y
# parecia usada. Una funcion muerta que nadie detecta se queda ahi para
# siempre, y peor: al leerla se piensa que algo la llama.
gen_sin_com='\n'.join(re.sub(r'(?<!\\)#.*','',l) for l in gen.split('\n'))
sin_uso=[d for d in set(defs)
         if len(re.findall(r'\b%s\b'%re.escape(d), gen_sin_com))<2]
print("   definidas y nunca usadas: %s" % (sorted(sin_uso) or "ninguna"))
for d in sin_uso: A("funcion sin usar: %s" % d)

# --- 6. cfg_aplicar y sus manejadores ---
print("\n6. cfg_aplicar")
def cuerpo(t,fn):
    i=t.index('\n%s() {'%fn); m=re.search(r'\n[a-z_][a-z0-9_]*\(\) \{',t[i+1:])
    return t[i:i+1+m.start()]
def cierre(l):
    j=0;q=None
    while j<len(l):
        ch=l[j]
        if q:
            if ch=='\\': j+=2; continue
            if ch==q: q=None
        elif ch in '"\'': q=ch
        elif ch=='(': return -1
        elif ch==')': return j
        j+=1
    return -1
def pats(t):
    out=[]
    for l in t.split('\n'):
        if not l.startswith('        ') or l.startswith('         '): continue
        if not l.strip() or l.lstrip().startswith('#'): continue
        p=cierre(l)
        if p<0: continue
        for alt in l[:p].strip().split('|'):
            m=re.match(r'^"([^"]*)"(\*?)$', alt.strip())
            if m: out.append(m.group(1)+m.group(2))
    return out
manej=[f for f in defs if f.startswith('cfg_ap_')]
todos=[]
for h in manej: todos += pats(cuerpo(gen,h))
print("   manejadores: %d   patrones: %d" % (len(manej), len(todos)))
for h in manej:
    if 'cfg_ap_%-12s'%'' [:0] or True:
        if h not in cuerpo(gen,'cfg_aplicar'):
            F("el despachador no llama a %s" % h)
# solapes
sol=[(a,b) for a in todos for b in todos if a!=b and fnmatch.fnmatchcase(a.rstrip('*'),b)]
print("   solapes entre patrones: %s" % (sorted(set(sol)) or "ninguno"))
for x in set(sol): F("patrones que se solapan: %r y %r" % x)

# --- 7. opciones de menu sin rama ---
print("\n7. OPCIONES DE MENU SIN RAMA")
def literales(t):
    """Los argumentos del menu, SOLO los del nivel superior.

    Una version anterior partia por comillas sin mirar la anidacion, asi que
    de "NTsync: $(onoff "$X")" sacaba tres trozos y dos de ellos -')' y
    ' in *'- se contaban como opciones de menu sin atender. Veinticinco
    "fallos" que no lo eran. Aqui se lleva la cuenta de $( ... ) y lo de
    dentro forma parte del argumento, no es un argumento aparte.
    """
    out=[];j=0
    while j<len(t):
        if t[j]=='"':
            k=j+1;buf=[];prof=0
            while k<len(t):
                if t[k]=='\\' and k+1<len(t): buf.append(t[k+1]);k+=2; continue
                if t[k]=='$' and k+1<len(t) and t[k+1]=='(': prof+=1;buf.append(t[k]);k+=1;continue
                if t[k]==')' and prof: prof-=1
                if t[k]=='"' and prof==0: break
                buf.append(t[k]);k+=1
            out.append("".join(buf));j=k+1
        elif t[j]=="'":
            k=t.find("'",j+1);j=(k+1) if k>0 else len(t)
        else: j+=1
    return out
sin=[]
for fn in ('game_config_menu','cfg_rendimiento_menu','cfg_rarezas_menu','cfg_prefijo_menu'):
    c=cuerpo(gen,fn)
    # Un menu tambien atiende opciones EN SU PROPIO case: las filas que abren
    # un submenu ("Rendimiento y compatibilidad >>") no pasan por cfg_aplicar.
    propios = pats(c) + [p.strip() for p in re.findall(r'^\s{8,20}"([^"]+)"\)', c, re.M)]
    mm=re.search(r'sel="\$\(menu\s',c)
    if not mm: continue
    p=c.index('$(',mm.start())+2; prof=1; e=p; q=None
    while prof>0 and e<len(c):
        ch=c[e]
        if q:
            if ch=='\\': e+=2; continue
            if ch==q: q=None
        elif ch in '"\'': q=ch
        elif ch=='(': prof+=1
        elif ch==')': prof-=1
        e+=1
    for o in literales(c[p:e-1])[1:]:
        b=re.split(r'\$',o)[0].strip()
        if not b or b.startswith('<<'): continue
        if not any(fnmatch.fnmatchcase(o,x) or fnmatch.fnmatchcase(b,x)
                   for x in todos+propios):
            sin.append((fn,o))
print("   opciones sin manejador: %d" % len(sin))
for fn,o in sin: F("%s ofrece %r y nadie la atiende" % (fn,o[:50]))

# --- 8. esquema de perfiles ---
print("\n8. ESQUEMA DE PERFILES")
sys.path.insert(0,SRC); import perfil
enums={n:i["opciones"] for n,i in perfil.CAMPOS.items() if i["opciones"]}
mal=0
for campo,ops in enums.items():
    vals=set()
    # En BASE, no en el generado: el generado lleva dentro el python de los
    # modulos, y sus datos de prueba (PREFIX_MODE="inventado") no son
    # asignaciones del script.
    for mm in re.finditer(r'(?<![A-Z_])%s=(?:"([^"$]*)"|([A-Za-z0-9_]+))(?![=\w])'%campo, base):
        v=mm.group(1) if mm.group(1) is not None else mm.group(2)
        if v and '$' not in v: vals.add(v)
    fuera=sorted(v for v in vals if v not in ops)
    if fuera: mal+=1; F("%s: el script asigna %s y el esquema no lo admite" % (campo,fuera))
print("   %d campos con lista cerrada, %d con valores fuera de lista" % (len(enums),mal))
# NINGUN CAMPO DEL PERFIL SE PUEDE BORRAR CON unset.
#
# POR QUE EXISTE ESTA COMPROBACION
#
# MANGOHUD y DXVK_ASYNC se llaman igual como ajuste del perfil y como variable
# de entorno. Al apagarlas, export_game_env hacia "unset MANGOHUD" creyendo que
# quitaba una variable del entorno: lo que borraba era EL CAMPO DEL PERFIL.
# Catorce lineas mas adelante build_runner_cmd lee "$MANGOHUD" sin proteger y,
# con set -u, eso MATA BASH. WProton se cerraba en seco en cualquier juego con
# MangoHud apagado -o sea, casi todos- y por los dos caminos.
#
# Lo que se quiere es "export -n": fuera del entorno del juego, pero el valor
# se queda en el shell para los menus y el lanzamiento siguiente.
print("   campos del perfil: comprobando que ninguno se borra con unset")
_mal_unset = []
for _k, _l in enumerate(base.split('\n'), 1):
    _s = re.sub(r'(?<!\\)#.*', '', _l)
    for _m in re.finditer(r'\bunset\s+([A-Z][A-Z0-9_ ]*)', _s):
        for _v in _m.group(1).split():
            if _v in perfil.CAMPOS:
                _mal_unset.append((_v, _k))
for _v, _k in _mal_unset:
    F("linea %d: 'unset %s' BORRA el campo del perfil (usa 'export -n %s')"
      % (_k, _v, _v))
print("   %d campo(s) del perfil borrados con unset" % len(_mal_unset))

gb=subprocess.run([sys.executable,os.path.join(SRC,'perfil.py'),'defectos-bash'],
                  capture_output=True,text=True).stdout
campos_bash=set(re.search(r"WP_CAMPOS_PERFIL='([^']*)'",gb).group(1).split())
if campos_bash!=set(perfil.ORDEN): F("los defectos generados no cuadran con el esquema")
print("   defectos generados: %d campos, cuadran con el esquema" % len(campos_bash))

# --- 9. auditar.py del proyecto ---
print("\n9. AUDITORIA DE BASH (auditar.py del proyecto)")
r=subprocess.run([sys.executable,'auditar.py'],capture_output=True,text=True)
graves=[l for l in r.stdout.split('\n') if 'GRAVE' in l or 'FALLO' in l]
print("   %s" % ("sin fallos graves" if not graves else "%d fallos" % len(graves)))
for g in graves: F(g.strip())

# --- 10. variables que una funcion usa y NO define -------------------------
#
# POR QUE EXISTE ESTE APARTADO
#
# El 13/09/2026 dos parches (que acabaron siendo cuatro piezas) se anclaron por
# un texto que aparece en varias funciones y cayeron en run_in_prefix. Pasaron
# "bash -n" y esta auditoria sin una queja, y estuvieron asi toda una sesion.
#
# Con "set -u" una expansion sin definir NO es un aviso:
#
#   fuera de $( )   -> bash TERMINA. WProton se cierra en seco.
#   dentro de $( )  -> muere solo la subshell: valor vacio y ningun error.
#
# Lo segundo es lo que hace invisible un parche desviado. Esto lo caza.
print("\n10. VARIABLES SIN DEFINIR EN SU FUNCION")

def _globales(txt):
    g = set(); dentro = False
    for l in txt.split('\n'):
        if re.match(r'^[a-z_][a-z0-9_]*\(\) \{', l): dentro = True; continue
        if dentro and l == '}': dentro = False; continue
        if dentro: continue
        for mm in re.finditer(r'^([A-Za-z_][A-Za-z0-9_]*)=', l): g.add(mm.group(1))
    for mm in re.finditer(r'\bexport\s+([A-Za-z_][A-Za-z0-9_]*)', txt): g.add(mm.group(1))
    for mm in re.finditer(r'^\s*(?:declare|typeset)\s+(?:-[a-zA-Z]+\s+)*'
                          r'([A-Za-z_][A-Za-z0-9_]*)', txt, re.M): g.add(mm.group(1))
    return g

_ENTORNO = {'HOME','PATH','PWD','USER','LANG','LC_ALL','SHELL','TERM','DISPLAY',
            'TMPDIR','IFS','REPLY','OPTARG','OPTIND','RANDOM','LINENO','PPID',
            'FUNCNAME','BASH_SOURCE','PIPESTATUS','SECONDS'}
_lin = base.split('\n')
_glob = _globales(base) | _ENTORNO

def _cuerpos():
    # LAS DE UNA SOLA LINEA SE SALTAN.
    #
    # 'log() { printf ...; }' cabe entera en su linea. Al buscar el '}' suelto
    # que la cierra se cogia el de DOS funciones mas abajo, asi que el cuerpo de
    # 'log' incluia el de 'die' y el de 'fallo'... y con ellos sus ui_error. El
    # apartado 12 acusaba a 'log' de abrir dialogos.
    i = 0
    while i < len(_lin):
        mm = re.match(r'^([a-z_][a-z0-9_]*)\(\) \{', _lin[i])
        if mm and '}' not in _lin[i]:
            j = i + 1
            while j < len(_lin) and _lin[j] != '}': j += 1
            yield mm.group(1), i + 1, _lin[i+1:j]
            i = j
        i += 1

def _definidas(cuerpo):
    d = set()
    for l in cuerpo:
        l = re.sub(r'(?:(?<=\s)|^)#.*', '', l)
        # "local x" SIN VALOR NO DEFINE NADA.
        #
        # Con "local pad_auto pad_eff pad_why" las tres quedan marcadas como
        # locales pero SIN ASIGNAR, o sea que siguen sin definir: leer $pad_eff
        # ahi mata el script con set -u igual que si no existiera. Contarlas
        # como definidas es lo que dejo pasar el fallo del 15/09, cuando una
        # rama nueva se salto el bloque que les daba valor.
        #
        # Solo cuenta "local x=..." o un "x=..." posterior en la funcion.
        for mm in re.finditer(r'\blocal\s+(?:-[aAirx]+\s+)?(.*)$', l):
            for nn in re.finditer(r'(?:^|\s)([A-Za-z_][A-Za-z0-9_]*)\s*=',
                                  mm.group(1)): d.add(nn.group(1))
        # EL ')' DE LAS RAMAS DE UN case CUENTA COMO SITIO DE DEFINICION.
        #
        #   *) _quien="..." ;;
        #
        # Sin el, la comprobacion daba por indefinida una variable que se
        # asigna justo ahi -se invento un fallo en diag_ventanas_steam-. Y una
        # comprobacion que da falsos positivos se deja de mirar, con lo cual
        # ya no sirve para nada: no detectar una DEFINICION es lo que produce
        # el falso aviso, asi que aqui conviene pasarse de generoso.
        # El "{" tambien: '{ g="$WP_PICK"; ... }' SI asigna g.
        for mm in re.finditer(r'(?:^|[;&|(){}]|\bthen\b|\bdo\b|\belse\b|\bif\b'
                              r'|\belif\b|\bwhile\b|\buntil\b|\bexport\b)'
                              # El "!" cuenta: 'if ! srv="$(...)"' SI asigna
                              # srv. Sin esto salian ocho falsos positivos, y
                              # una comprobacion que los da se deja de mirar a
                              # las dos semanas.
                              r'\s*(?:!\s*)?([A-Za-z_][A-Za-z0-9_]*)=', l):
            d.add(mm.group(1))
        for mm in re.finditer(r'\bfor\s+([A-Za-z_][A-Za-z0-9_]*)\s+in\b', l): d.add(mm.group(1))
        for mm in re.finditer(r'\bread\s+((?:-[a-zA-Z]+\s+)*)([A-Za-z_][A-Za-z0-9_ ]*)', l):
            d.update(mm.group(2).split())
        for mm in re.finditer(r'\beval\s+"([A-Za-z_][A-Za-z0-9_]*)=', l): d.add(mm.group(1))
        for mm in re.finditer(r'\bunset\s+([A-Za-z_][A-Za-z0-9_]*)', l): d.add(mm.group(1))
    return d

_sueltas = []
for _fn, _ini, _cuerpo in _cuerpos():
    _d = _definidas(_cuerpo) | _glob
    _protegida = '\n'.join(_cuerpo)
    _vistas = set(); _simple = False
    for _k, _l in enumerate(_cuerpo):
        _s = re.sub(r'(?<!\\)#.*', '', _l)
        if _simple:                      # dentro de '...' bash no expande nada
            if _l.count("'") % 2 == 1: _simple = False
            continue
        if _l.count("'") % 2 == 1:
            _simple = True
            _s = _s[:_s.index("'")] if "'" in _s else _s
        for mm in re.finditer(r'\$\{([A-Za-z_][A-Za-z0-9_]*)\}|\$([A-Za-z_][A-Za-z0-9_]*)', _s):
            _v = mm.group(1) or mm.group(2)
            if _v in _d or _v in _vistas or _v.isupper(): continue
            if re.match(r'\$\{%s[:+\-=?#%%/^,]' % re.escape(_v), _s[mm.start():]): continue
            _ant = _s[:mm.start()]
            if _ant.count('$(') > _ant.count(')'): continue       # solo la subshell
            if re.search(r'\$\{%s[:+\-]' % re.escape(_v), _protegida): continue
            _vistas.add(_v)
            _sueltas.append((_fn, _v, _ini + _k))
print("   %d funcion(es) con una variable cruda que no definen" % len(_sueltas))
for _fn, _v, _n in _sueltas:
    F("%s usa $%s y no la define (linea %d): con set -u MATA el script" % (_fn, _v, _n))

# --- 11. paridad imagen / carpeta -----------------------------------------
#
# El fallo mas repetido del proyecto: launch_game (.wsquashfs) y
# launch_loose_exe (.pc, exe suelto) deberian hacer lo mismo y uno hace menos.
# Se ha arreglado a mano cinco o seis veces y vuelve, porque nada lo vigila.
#
# Se compara lo ALCANZABLE desde cada camino, no solo lo que llama directo:
# asi home_portable cuenta como presente en el camino de carpeta aunque llegue
# por dentro de lanzar_nativo_suelto.
#
# La lista de abajo es lo que de verdad es propio de un camino. Cualquier cosa
# que aparezca fuera de ella es una divergencia nueva y hay que mirarla: o va
# en los dos, o se añade aqui con el motivo escrito.
print("\n13. MODULOS: QUIEN LOS EJECUTA, LOS ESCRIBE")
# CADA MODULO PYTHON SE ESCRIBE ANTES DE EJECUTARLO.
#
# Los modulos viven incrustados en wproton.sh y se vuelcan a runtime/ la
# primera vez. write_X compara la MARCA DE CONTENIDO -un hash que pone
# build.sh- y reescribe solo si ha cambiado: es asi como una version nueva del
# modulo llega al disco.
#
# mando_virtual_start se lo salto: en vez de llamar a write_mando_virtual solo
# comprobaba que el fichero EXISTIERA. Como existia de una version anterior,
# nunca se reescribia y el modulo en disco se quedo congelado. El 17/09 eso dio
# una escena imposible: el bash de la version nueva y el Python de la vieja
# corriendo juntos, con un arreglo que estaba en el fichero entregado y no en
# el que se ejecutaba. Dos dias de pruebas encima de eso.
# EXENTOS, CON EL MOTIVO ESCRITO.
#
# menu_pygame.py lo escriben trece sitios distintos, y ninguno de los menus
# puede pintarse sin el: cuando ver_fichero se ejecuta, el modulo ya esta en
# disco y al dia por fuerza, porque se ha llegado ahi navegando por un menu.
# Exigirle la llamada seria ruido.
MOD_EXENTOS = {("ver_fichero", "menu_pygame")}

_fallos_mod = []
for _fn, _ini, _cuerpo in _cuerpos():
    _txt = '\n'.join(_cuerpo)
    for _m in sorted(set(re.findall(r'\$([A-Z_]+)_PY', _txt))):
        _wr = 'write_' + _m.lower()
        if (_wr + '() {') not in gen:
            continue
        if re.search(r'(?:^|[\s;&|(])%s\b' % _wr, _txt, re.M):
            continue
        # Solo cuenta si de verdad lo EJECUTA
        if re.search(r'(?:PY_BIN|lanzar_suelto)[^\n]*%s_PY' % _m, _txt):
            if (_fn, _m.lower()) in MOD_EXENTOS:
                continue
            _fallos_mod.append((_fn, _m.lower(), _wr))
if _fallos_mod:
    for _fn, _mod, _wr in _fallos_mod:
        F("%s ejecuta %s.py y no llama a %s: el modulo en disco se queda "
          "congelado en la version anterior" % (_fn, _mod, _wr))
else:
    print("   ningun modulo se ejecuta sin escribirlo antes")

print("\n11. PARIDAD IMAGEN / CARPETA")
SOLO_IMAGEN = {
    # montar y desmontar la imagen
    'mount_game', 'mount_image_ro', 'montar_suelto', 'image_format',
    'imagen_valida', 'fallo_montaje_texto', 'limpiar_rotos_si_los_hay',
    'find_dwarfs_tools', 'setup_dwarfs_tools', 'human_size', 'arch_tag',
    # overlays: solo existen sobre un montaje de solo lectura
    'overlay_opacos_avisar', 'overlay_opacos_listar', 'overlay_opacos_prevenir',
    # Lanzar un juego de LINUX es cosa de lanzar_nativo_suelto y
    # lanzar_script_si_existe, a las que se llega desde el camino de carpeta.
    # Un .wsquashfs con un juego de Linux dentro se monta y acaba pasando por
    # lanzar_script_si_existe igual, asi que no es una divergencia real.
    'ejecutar_nativo',
    # prefijo INCLUIDO en el paquete: una carpeta no lo trae
    #
    # prefijo_hacer_portable entra aqui por lo mismo: quita del prefijo las
    # rutas del equipo donde se hizo, y eso solo hace falta cuando el prefijo
    # VIENE DE OTRO SITIO -dentro de un .wsquashfs-. El de un juego en carpeta
    # se crea en la maquina donde se juega, asi que no tiene rutas ajenas que
    # limpiar. Tambien se llama al EMPAQUETAR, que no es un camino de
    # lanzamiento y por eso no cuenta para esta paridad.
    'bundled_prefix_prepare', 'prefijo_hacer_portable', 'prefijo_appdata_enlazar',
    'prefijo_incluido_a_disco', 'prefijo_usuario_enlazar', 'exe_dentro_del_prefijo',
    # buscar el ejecutable dentro del montaje: en carpeta lo hace
    # resolver_exe_carpeta y quien llama ya trae el exe
    'find_exe', 'scan_exes', 'parse_autorun',
}
SOLO_CARPETA = {
    # de donde arranca la carpeta: en una imagen la raiz es el punto de montaje
    'raiz_paquete_detectar', 'raiz_juego_efectiva', 'raiz_unreal',
    # un .sh o un AppImage elegido a mano
    'lanzar_nativo_suelto',
    # el .bat de TeknoParrot que hay que saltarse: viene sin empaquetar
    'teknoparrot_lanzador',
}
_cuerpo_de = {fn: c for fn, _i, c in _cuerpos()}
_ini_de = {fn: _i for fn, _i, _c in _cuerpos()}
# TODOS los nombres definidos, tambien los de una linea. _cuerpo_de solo tiene
# las de varias lineas -las de una no se pueden delimitar bien-, pero para
# RECONOCER una llamada hace falta la lista completa: si no, 'profile_exists'
# no contaba como funcion y el contrato de paridad la daba por perdida.
_nombres = set(re.findall(r'^([a-z_][a-z0-9_]*)\(\) \{', base, re.M))

def _llama(cuerpo):
    s = set()
    for l in cuerpo:
        l = re.sub(r'(?:(?<=\s)|^)#.*', '', l)
        for mm in re.finditer(r'\b([a-z_][a-z0-9_]*)\b', l):
            if mm.group(1) in _nombres: s.add(mm.group(1))
    return s

def _alcanzable(raiz, tope=4):
    vis = {raiz}; frente = {raiz}
    for _ in range(tope):
        nue = set()
        # Las de una linea no tienen cuerpo guardado: no se recorren, pero si
        # cuentan como alcanzadas.
        for f in frente: nue |= _llama(_cuerpo_de.get(f, []))
        nue -= vis
        if not nue: break
        vis |= nue; frente = nue
    return vis - {raiz}

# LAS 62 PIEZAS QUE YA ESTAN EN LOS DOS, Y AHI SE QUEDAN.
#
# El cierre de abajo caza lo que no es alcanzable de ninguna forma, pero se le
# escapa lo que sigue alcanzandose por otro sitio: al quitar menu_server_stop
# de launch_loose_exe seguia "presente" porque post_game_resettle la llama al
# terminar la partida... cuando ya no sirve de nada.
#
# Asi que esto es un contrato de LLAMADA DIRECTA: lo que hoy llaman los dos
# caminos lo tienen que seguir llamando los dos. Añadir a la lista es bueno;
# quitar de la lista hay que justificarlo por escrito.
EN_LOS_DOS = {
    'acompanante_start', 'acompanante_stop', 'avisar_64_en_32',
    'bat_resolver_instalacion', 'batocera_play', 'build_runner_cmd',
    'canvas_stop', 'community_offer_for',
    'dependencias_primera_vez', 'detectar_py', 'diag_mando_vigilante',
    'diag_rutas_wine', 'diag_video_informe', 'dll_informe', 'ensure_runner',
    'exe_a_ruta_windows', 'export_game_env', 'fallo_analizar',
    'find_keys_file', 'first_run_wizard', 'game_id', 'gamepad_retrigger',
    # 'log' salio de la lista a proposito: es el registrador general, no una
    # pieza del lanzamiento. Sus unicas llamadas en launch_game estaban en el
    # bloque del wineserver, que ahora vive en wineserver_cerrar_prefijo.
    'get_runner_path', 'guardia_salida_start', 'guardia_salida_stop',
    'instalar_una_vez', 'juego_en_c_preparar', 'juego_es_nativo',
    'keys_ocultar_mando_decidir', 'load_profile', 'loading_say',
    'log_input_devices', 'mako_informe', 'mando_virtual_start',
    'mando_virtual_stop', 'mapeador_start', 'mapeador_stop',
    'matar_con_hijos', 'menu_server_stop', 'pad_bridge_stop',
    'pad_sdl_prefix_setup', 'paquete_drive_c_enlazar', 'partida_fin',
    'post_game_resettle',
    'preparar_librerias_prefijo', 'profile_exists', 'proton_marcar_prefijo',
    'reshade_lx_informe', 'run_args_for', 'save_settings', 'saves_detect_end',
    'saves_detect_start', 'stats_record', 'teknoparrot_detectar',
    'teknoparrot_restaurar', 'teknoparrot_rutas', 'unidad_auto_juego',
    'unidad_juego_preparar', 'unidad_juego_reaplicar',
    'unidad_juego_reaplicar_stop', 'wineserver_cerrar_prefijo',
    'cierre_desde_fuera', 'matar_con_hijos',
    'write_full_profile',
}

def _directas(fn):
    s = set()
    for l in _cuerpo_de[fn]:
        l = re.sub(r'(?:(?<=\s)|^)#.*', '', l)
        for mm in re.finditer(r'(?:^|[\s;&|(`]|\$\()([a-z_][a-z0-9_]*)'
                              r'(?=[\s;&|)"\']|$)', l):
            if mm.group(1) in _nombres: s.add(mm.group(1))
    return s

_dir_img = _directas('launch_game')
_dir_carp = _directas('launch_loose_exe')
for _x in sorted(EN_LOS_DOS - _dir_img):
    F("paridad: launch_game ha dejado de llamar a %s" % _x)
for _x in sorted(EN_LOS_DOS - _dir_carp):
    F("paridad: launch_loose_exe ha dejado de llamar a %s" % _x)
print("   contrato de llamada directa: %d piezas, %d ausencia(s)"
      % (len(EN_LOS_DOS), len(EN_LOS_DOS - _dir_img) + len(EN_LOS_DOS - _dir_carp)))

# EL BLINDAJE DE SENALES, que no es una llamada sino un trap y una variable.
# Faltaba entero en launch_loose_exe: un TERM de Steam durante un .pc disparaba
# cleanup_all con la partida en marcha, sin la red de "espera a que el juego
# suelte sus procesos" que solo entra si WP_JUGANDO vale 1.
for _fn in ('launch_game', 'launch_loose_exe'):
    _c = '\n'.join(_cuerpo_de[_fn])
    if 'trap cierre_desde_fuera INT TERM' not in _c or 'WP_JUGANDO=1' not in _c:
        F("%s no pone el blindaje (trap cierre_desde_fuera + WP_JUGANDO=1)" % _fn)
    if 'partida_fin' not in _c:
        F("%s no levanta el blindaje al terminar (partida_fin)" % _fn)
    # Y CADA SALIDA ANTICIPADA TAMBIEN.
    #
    # El blindaje se pone en la primera linea y se levanta al final, pero estas
    # funciones tienen seis o siete "return" en medio: imagen invalida, sin
    # runner, asistente cancelado, juego de Linux... Por cualquiera de esos se
    # volvia al menu con WP_JUGANDO=1 y las senales tapadas para siempre.
    _cl = _cuerpo_de[_fn]
    _tr = next((k for k, l in enumerate(_cl)
                if 'trap cierre_desde_fuera INT TERM' in l), None)
    # EL ULTIMO, no el primero: el del final de la partida. Con el primero, el
    # tramo a revisar se quedaba en las primeras lineas y no se veia nada.
    _fin_s = [k for k, l in enumerate(_cl) if l.strip().startswith('partida_fin')]
    _fi = _fin_s[-1] if _fin_s else None
    if _tr is not None and _fi is not None:
        for _k in range(_tr, _fi):
            _l = _cl[_k]
            if _l.strip().startswith('#') or not re.search(r'\breturn\b', _l):
                continue
            if 'partida_fin' in _l or 'partida_fin' in _cl[_k - 1]:
                continue
            F("%s sale en la linea %d con el blindaje puesto: falta partida_fin"
              % (_fn, _ini_de[_fn] + _k + 1))

_img = _alcanzable('launch_game')
_carp = _alcanzable('launch_loose_exe')
_falta_carp = sorted((_img - _carp) - SOLO_IMAGEN)
_falta_img = sorted((_carp - _img) - SOLO_CARPETA)
print("   alcanzable: %d desde la imagen, %d desde la carpeta" % (len(_img), len(_carp)))
print("   divergencias nuevas: %d" % (len(_falta_carp) + len(_falta_img)))
for _x in _falta_carp:
    F("paridad: %s se hace con la imagen y NO en carpeta (launch_loose_exe)" % _x)
for _x in _falta_img:
    F("paridad: %s se hace en carpeta y NO con la imagen (launch_game)" % _x)

# --- 12. el camino de descarga no puede quedarse esperando -----------------
#
# POR QUE EXISTE
#
# En dl_bruto habia pegado el bloque de los codecs de 32 bits, que es de la
# primera puesta en marcha. dl_bruto la usan 22 funciones, la URL del pack es
# todavia un marcador PENDIENTE, y esa rama llama a ui_error. Resultado: con la
# barra de progreso ya en pantalla, CUALQUIER descarga -un runner, el prefijo
# de TeknoParrot- se clavaba en el 95% esperando un dialogo que no se ve.
#
# La regla: mientras la barra de progreso esta puesta, nada de preguntar.
print("\n12. EL CAMINO DE DESCARGA NO PREGUNTA NADA")
INTERACTIVAS = {'ui_error', 'ui_info', 'ui_ask', 'menu'}
# Estas son parte del propio dialogo o lo envuelven: no cuentan como llamada.
EXENTAS = {'ui_error', 'ui_info', 'ui_ask', 'menu', 'menu_grafico_disponible',
           'fallo', 'die'}

def _alcanzable_desde(raiz, tope=4):
    if raiz not in _cuerpo_de:
        return set()
    vis = {raiz}; frente = {raiz}
    for _ in range(tope):
        nue = set()
        for f in frente:
            if f in EXENTAS:
                continue
            nue |= _llama(_cuerpo_de.get(f, []))
        nue -= vis
        if not nue:
            break
        vis |= nue; frente = nue
    return vis

_sospechosas = []
for _raiz in ('dl_bruto',):
    for _f in sorted(_alcanzable_desde(_raiz) - {_raiz}):
        if _f in EXENTAS or _f not in _cuerpo_de:
            continue
        _usa = _llama(_cuerpo_de[_f]) & INTERACTIVAS
        if _usa:
            _sospechosas.append((_raiz, _f, sorted(_usa)))
print("   %d funcion(es) del camino de descarga que abren un dialogo"
      % len(_sospechosas))
for _r, _f, _u in _sospechosas:
    F("%s puede llegar a %s, que llama a %s: la descarga se quedaria esperando"
      % (_r, _f, ", ".join(_u)))


print("\n" + "="*68)
print("RESULTADO: %d fallo(s), %d aviso(s)" % (len(fallos),len(avisos)))
for f in fallos: print("  FALLO  %s" % f)
for a in avisos: print("  aviso  %s" % a)
print("="*68)
sys.exit(1 if fallos else 0)
