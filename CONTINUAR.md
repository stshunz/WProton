# CONTINUAR — estado del trabajo y qué hacer a continuación

Traspaso del 13/09/2026, **revisado el mismo día tras una sesión de
correcciones**. Lo de la sesión de correcciones está en el apartado 0 bis; lo
de más abajo se ha dejado como estaba salvo donde se dice lo contrario.

**Lee primero `COMPATIBILIDAD.md`**: ahí están los casos que han costado tiempo
con lo que se comprobó de verdad y —más útil— lo que se probó y NO era.

---

## 0. Cómo se trabaja en este proyecto

```
wproton.base.sh   el fuente. SIEMPRE se edita este.
src/*.py          módulos Python que build.sh inserta en el fuente
build.sh          genera wproton.sh desde base + src. 19 inserciones.
auditoria_final.py   comprobación global
auditar.py        auditoría de bash (la llama la anterior)
```

Ciclo obligatorio tras cada cambio:

```bash
bash -n wproton.base.sh          # sintaxis
./build.sh                       # regenerar wproton.sh
python3 auditoria_final.py       # 0 fallos, 2 avisos conocidos
for m in perfil detectar dlls disco teclas teknoparrot ficha procesos mako reshade; do
    python3 src/$m.py comprobar
done
```

Los 2 avisos conocidos y aceptados: `gh_digest` y `winebus_sdl_quitar` sin usar.

### Preferencias del autor, que hay que respetar

- **Nada de pedir logs de ida y vuelta.** Si hace falta un diagnóstico, se
  automatiza en el código y se deja en el registro.
- **Nada de pedirle que ejecute comandos** en la terminal. Lo comprueba el
  propio script.
- **Ficheros completos**, no parches para aplicar a mano.
- Antes de proponer hipótesis, buscar si alguien lo ha documentado ya.

---

## 0 bis. Lo corregido en la sesión de revisión (13/09/2026, tarde)

**El punto 1 de este documento estaba equivocado.** Decía que los parches
desviados «están ya corregidos». No lo estaban: se habían **añadido** las
copias buenas en `launch_loose_exe` pero **no se habían quitado** las de
`run_in_prefix`, y entretanto habían crecido a cuatro piezas
(`raiz_paquete_detectar "$exe"`, `EXE_PATH="$exe"`, `community_offer_for` y
`dependencias_primera_vez`).

### Lo que eso provocaba

`run_in_prefix` no tiene ninguna variable `exe`. Con `set -u`:

```
dentro de $( )   muere solo la subshell -> valor vacío, ningún error
fuera de $( )    MUERE BASH ENTERO      -> WProton se cierra en seco
```

`EXE_PATH="$exe"` está fuera. Resultado, comprobado:

| acción del usuario | qué pasaba |
|---|---|
| Abrir winecfg o winetricks | WProton se cierra sin decir nada |
| Importar un `.reg` | igual |
| **Escritorio virtual** (`vd=<res>`) | igual |
| Lanzar un `.wsquashfs` con `dependencies/` | igual, y con recursión infinita |

Lo del escritorio virtual explica una cosa que este documento daba por
pendiente: el apartado 4 decía que era lo único sin probar del caso de KOF XII
y que «no se ha probado ni una vez». **No se había probado porque el camino
estaba muerto**: pasa por `run_in_prefix`. Ahora se puede probar de verdad.

### Un segundo matador, en el arreglo de esa misma mañana

La extracción de `preparar_librerias_prefijo` quedó llamada **antes** de
`build_runner_cmd`, y `winetricks_uno_a_uno` usa `RUN_CMD` y `RUNNER_KIND`, que
las pone `build_runner_cmd`. `RUNNER_KIND` no se inicializa en ningún sitio a
nivel de fichero:

- primer juego de la sesión → `RUNNER_KIND` no existe → **muere el script**
- del segundo en adelante → instala con el `RUN_CMD` del juego **anterior**

Y además estaba **dos veces**: `preparar_librerias_prefijo` ya llama por dentro
a `redist_base_compartido` y `redist_base_teknoparrot`. O sea que el arreglo de
«un `.pc` no instala ninguna librería» no podía funcionar.

### Cambios aplicados

Todos anclados por cuerpo de función, nunca por texto suelto.

| función | qué |
|---|---|
| `run_in_prefix` | fuera las 4 piezas desviadas; `export_game_env` restaurado |
| `export_game_env` | usa el runner que recibe, no el `$rdir` del ámbito del llamante |
| `cfg_ap_teclas` | `$kf0` propio, no el de `game_config_menu` |
| `launch_loose_exe` | `trap '' INT TERM` + `WP_JUGANDO=1` (faltaba el blindaje entero) |
| `launch_loose_exe` | `community_offer_for` |
| `launch_loose_exe` | `ensure_runner` |
| `launch_loose_exe` | `detectar_py resolver` + `write_full_profile` |
| `launch_loose_exe` | `preparar_librerias_prefijo` movido tras `build_runner_cmd`, sin duplicar |
| `launch_loose_exe` | `dependencias_primera_vez` |
| `launch_loose_exe` | `menu_server_stop` + `canvas_stop` |
| `partida_fin` (nueva) | levanta el blindaje; se llama en las **13** salidas anticipadas de los dos caminos |

Sobre `ensure_runner`: por el camino de carpeta, si el perfil pedía un runner
que no está instalado, `get_runner_path` se caía al automático **sin decir
nada** y el juego arrancaba con otro runner. Importa más desde ahora, porque
con `community_offer_for` en este camino los perfiles de la comunidad traen el
nombre de *su* runner, que casi nunca está instalado todavía.

Sobre `partida_fin`: el blindaje se ponía en la primera línea y se levantaba al
final, pero las dos funciones tienen seis o siete `return` en medio. Por
cualquiera de ellos se volvía al menú con `WP_JUGANDO=1` y las señales tapadas
para siempre: de ahí el «Hay un juego en marcha» al reparar montajes, los
veinte segundos de espera al cerrar y que WProton no se dejara cerrar con
Ctrl-C. Era un fallo que ya existía en `launch_game`.

### Dos cosas del apartado 2 que eran falsas

- **`HOME_PORTABLE` no existe.** Cero menciones en bash y en los módulos. No se
  ha inventado el campo.
- **`home_portable` sí está** en el camino de carpeta, dentro de
  `lanzar_nativo_suelto`. La tabla de paridad lo daba por perdido porque miraba
  solo las dos funciones grandes.

### Lo que ahora vigila la auditoría

`bash -n` y `auditoria_final.py` daban **verde** con los parches desviados
dentro. Ese era el punto ciego, y por eso se colaron. Hay dos apartados nuevos:

```
10. VARIABLES SIN DEFINIR EN SU FUNCION
    Recorre cada función y busca expansiones en minúsculas que esa función no
    define, distinguiendo lo que muere en una subshell de lo que mata el
    script. Encontró 3 casos reales; ahora da 0.

11. PARIDAD IMAGEN / CARPETA
    a) contrato de llamada DIRECTA: las 62 piezas que hoy llaman los dos
       caminos tienen que seguir llamándolas los dos. Añadir a la lista es
       bueno; quitar hay que justificarlo por escrito.
    b) cierre de lo alcanzable, con la lista de lo que es legítimamente propio
       de un camino (montaje, overlays, prefijo incluido / detección de raíz).
    c) el blindaje: `trap` + `WP_JUGANDO`, y que ninguna salida anticipada se
       vaya sin `partida_fin`.
```

Las dos están probadas **en negativo**: se reintrodujeron los cuatro fallos a
propósito y saltaron los cuatro, mientras `bash -n` seguía en verde. Si se
tocan estos apartados, repetir esa prueba: una comprobación que no se ha visto
fallar no sirve de nada.

Estado del ciclo: **0 fallos, 2 avisos** (los conocidos, `gh_digest` y
`winebus_sdl_quitar`), los 10 módulos en OK.

---

## 0 ter. El cierre en seco de las 19:28 — `MANGOHUD`

Registro `wproton_20260913_192803.log`, Steel Assault.pc: WProton se cerró sin
decir nada justo después del entorno. **No era paridad ni un ancla desviada.**

### Cómo se encontró

El registro acaba en el último mensaje de `entorno_batocera` y sigue con
`Observador del cierre: apagado`, que es la **primera línea de `cleanup_all`**.
`cleanup_all` está en `trap ... EXIT`, o sea que bash había muerto. Y como el
blindaje nuevo ya pone `WP_JUGANDO=1`, salió también
`Cierre con el juego aun en marcha`, que confirma que veníamos de
`launch_loose_exe`.

Se reprodujo en banco: se cargan las funciones del `wproton.sh` generado, se
les ponen tapones para lo gráfico y se ejecuta la secuencia real con un
`trap ... EXIT` que imprime `$BASH_COMMAND`. Salió a la primera:

```
=== build_runner_cmd ===
### EXIT: ultima orden = [local _gm_efectivo="$GAMEMODE" _mh_efectivo="$MANGOHUD"]
```

### La causa

`MANGOHUD` y `DXVK_ASYNC` **se llaman igual como campo del perfil y como
variable de entorno**. En `export_game_env`, el arreglo de esa mañana para que
un lanzamiento no contaminara al siguiente hacía:

```bash
if [ "$MANGOHUD" = 1 ]; then export MANGOHUD=1
else unset MANGOHUD; fi
```

Ese `unset` no quitaba una variable del entorno: **borraba el campo del
perfil**. Catorce líneas después, `build_runner_cmd`:

```bash
local _gm_efectivo="$GAMEMODE" _mh_efectivo="$MANGOHUD"
```

sin proteger. Con `set -u` eso **mata bash**. Pasaba en cualquier juego con
MangoHud apagado —o sea, casi todos— y **por los dos caminos, también con los
`.wsquashfs`**. Que Steel Assault fuera `.pc` es casualidad.

### El arreglo

`export -n` en vez de `unset`: saca la variable del entorno que ve el juego y
**deja el valor en el shell**, que es lo que leen los menús y el lanzamiento
siguiente. El arreglo de «un lanzamiento contamina al siguiente» sigue en pie.
`RADV_PERFTEST` no es campo del perfil, así que ésa sí se borra entera.

De paso, `RUNNER_KIND` y `RUN_CMD` se declaran ya **a nivel de fichero**. Las
ponía sólo `build_runner_cmd`, que devuelve 1 si falta `umu-run` **y nadie mira
lo que devuelve**: `winetricks_uno_a_uno` leía `"$RUNNER_KIND"` a pelo y el
script se cerraba en seco al instalar una librería. Salió en la misma prueba de
banco.

### Lo vigila la auditoría

Apartado 8: **ningún campo del perfil se puede borrar con `unset`**. Probado en
negativo (se reintroduce el `unset MANGOHUD` y salta).

### La lección, que es la de siempre en este proyecto

El registro terminaba en `entorno_batocera`, así que las tres primeras
hipótesis miraron ahí: GStreamer, códecs, el runner. **El sitio donde se para
el registro no es el sitio donde está el fallo**, es el último que llegó a
escribir. Con `set -u` puede haber una función entera entre uno y otro. La
prueba de banco —cargar las funciones del generado y ejecutar la secuencia con
un `trap EXIT` que imprima `$BASH_COMMAND`— lo resolvió en un intento. Está en
`/tmp/repro2.sh` del traspaso; merece la pena rehacerla cuando algo se cierre
sin explicación.

---

## 0 quater. El prefijo de TeknoParrot que se queda infinito con runners Wine

Síntoma: con cualquier runner **Wine** (Wine LG, Wine 11, el wine-9.22 de
Aliens) y el prefijo **TeknoParrot**, se queda colgado. Con prefijo propio va,
con el compartido a veces.

### La cadena entera

1. `launch_loose_exe` **no cerraba el wineserver al terminar**. El bloque que
   lo hace —cuarenta líneas— estaba escrito *dentro* de `launch_game`, y por
   ahí no pasan los juegos en carpeta. Otra vez el fallo recurrente.
2. Los juegos de TeknoParrot van en **carpeta**, o sea que salen por ahí. Al
   terminar dejaban vivos `wineserver`, `services.exe` y `winedevice` de un
   prefijo que además **comparten todos ellos**. (En el registro de las 19:28
   ya se veía: `activos de Steam/Wine (NO se tocan): winedevice services.exe`.)
3. Al siguiente lanzamiento con un runner **Wine**, `build_runner_cmd` llama a
   `prefijo_wine_reparar`, que hace `wineboot -u` sobre ese prefijo ocupado por
   un wineserver **de otra versión de Wine**. Eso cuelga. No es cosa nuestra:
   está documentado en wine-tkg [#387](https://github.com/Frogging-Family/wine-tkg-git/issues/387)
   y [#393](https://github.com/Frogging-Family/wine-tkg-git/issues/393), donde
   la única salida es matar los procesos de Wine antes de reintentar.
4. Después venía `wineserver -w`, que **espera hasta que todos los procesos del
   prefijo terminen** (lo dice su manual). Si no se van a ir, se espera para
   siempre.
5. La marca `.wp_wine_listo` sólo se escribe al final, así que el cuelgue se
   **repetía en cada intento**. De ahí «infinito».

Por qué sólo con Wine: `prefijo_wine_reparar` se llama **únicamente** en la
rama `kind = wine` de `build_runner_cmd`. Con Proton no se toca. Por qué el
propio va: es de un solo juego, no acumula restos. Por qué el compartido «a
veces»: depende de si quedó algo vivo.

### Arreglado

- **`wineserver_cerrar_prefijo`** (y `wineserver_buscar`): una sola copia, que
  llaman los dos caminos. `launch_loose_exe` ya cierra su prefijo al terminar.
- `prefijo_wine_reparar` **cierra el prefijo ANTES** de `wineboot -u`, que es
  el remedio documentado, y ya no hace `-w` a secas.
- **Los plazos se respetan y se cuentan.** Antes, si `wineboot -u` se pasaba de
  tiempo se seguía con `|| true` y **se escribía la marca igual**: el prefijo
  quedaba a medias y nadie lo sabía. Ahora se detecta el 124, se avisa con qué
  hacer y **no se escribe la marca**, así que el siguiente intento vuelve a
  probar. Y si no hay `timeout` en el sistema, no se lanza a pelo: se dice.
- **Plazos acotados**: 20 s por cada espera de wineserver y 180 s para
  `wineboot`, ajustables con `WP_WINESERVER_TIMEOUT` y `WP_WINEBOOT_TIMEOUT`.
  El peor caso sumaba **nueve minutos** de pantalla quieta; ahora la pantalla
  dice además cuánto puede tardar.

Probado en el banco con un `wineserver` de mentira que se cuelga a propósito:
antes se quedaba ahí, ahora corta, avisa y no marca el prefijo como listo.

### Lo que queda por mirar de este caso

El prefijo de TeknoParrot lleva un enlace `pfx -> .` (lo pone
`prefijo_enlace_pfx` para que Proton lo encuentre). Es un **enlace a sí mismo**:
cualquier cosa que recorra el árbol siguiendo enlaces —`find -L`, `du`, `cp -r`,
`rsync`— entra en bucle. `find` sin `-L` no lo sigue, así que hoy no molesta,
pero conviene no añadir nunca un recorrido que siga enlaces sobre un prefijo.

---

## 1. Los cambios de aquella mañana (ya verificados: ver 0 bis)

**Se metieron dos parches en la función equivocada y pasaron la sintaxis y la
auditoría sin quejarse.** El ancla de texto que usé (`EXE_PATH="$exe"`) aparece
en varias funciones y cogió la primera. **NO estaban corregidos**: se
corrigieron en la sesión de revisión, y acabaron siendo cuatro piezas, no dos.
Ver el apartado 0 bis. La lección de anclar por función sigue valiendo entera.

### Cómo verificar que una pieza está donde toca

NO basta con `grep` del nombre. Hay que comprobar **en qué función** cae:

```bash
cd wproton && python3 - <<'PY'
import re
lin = open('wproton.base.sh', encoding='utf-8').read().split('\n')
def func_de(n):
    f = '?'
    for l in lin[:n]:
        m = re.match(r'^([a-z_][a-z0-9_]*)\(\) \{', l)
        if m: f = m.group(1)
    return f
for pat in ('raiz_paquete_detectar "$exe"', 'EXE_PATH="$exe"',
            'preparar_librerias_prefijo "$rdir"'):
    for k, l in enumerate(lin, 1):
        if pat in l:
            print('%-36s linea %5d -> %s' % (pat, k, func_de(k)))
PY
```

Debe salir, como mínimo:

```
raiz_paquete_detectar "$exe"         -> launch_loose_exe
EXE_PATH="$exe"                      -> launch_loose_exe   (ANTES de export_game_env)
preparar_librerias_prefijo "$rdir"   -> launch_game
preparar_librerias_prefijo "$rdir"   -> launch_loose_exe
```

Y **`EXE_PATH="$exe"` debe aparecer antes que `export_game_env` dentro de
`launch_loose_exe`**, no después. Es el arreglo del que dependía que los juegos
.NET arranquen.

### Regla para futuras extracciones

Anclar por **número de línea dentro del cuerpo de la función**, no por texto
suelto. El patrón que funciona:

```python
ini = next(k for k, l in enumerate(lin) if l == 'launch_loose_exe() {')
fin = next(k for k in range(ini+1, len(lin)) if lin[k] == '}')
# buscar el ancla SOLO entre ini y fin
```

---

## 2. Lo que queda pendiente: paridad imagen / carpeta

El fallo recurrente del proyecto: **`launch_game` (imágenes .wsquashfs) y
`launch_loose_exe` (carpetas .pc y exe sueltos) deberían hacer lo mismo y uno
hace menos.** Hoy se igualó lo más grave; quedan cinco piezas.

Estado verificado hoy:

| pieza | imagen | carpeta |
|---|---|---|
| `preparar_librerias_prefijo` | sí | **sí** (se extrajo hoy) |
| `mando_virtual_start` | sí | sí |
| `log_input_devices` | sí | sí |
| `diag_mando_vigilante` | sí | sí |
| `home_portable` / `home_portable_exportar` | sí | sí (por `lanzar_nativo_suelto`) |
| `dependencias_primera_vez` | sí | **sí** (13/09 tarde) |
| `community_offer_for` | sí | **sí** (13/09 tarde) |
| `write_full_profile` | sí | **sí** (13/09 tarde) |
| `menu_server_stop` / `canvas_stop` | sí | **sí** (13/09 tarde) |
| `ensure_runner` | sí | **sí** (13/09 tarde) |
| blindaje (`trap` + `WP_JUGANDO`) | sí | **sí** (13/09 tarde) |

**Las cinco piezas que quedaban están hechas.** Lo que sigue de este apartado
se deja como referencia de por qué importaba cada una. Lo vigila ahora el
apartado 11 de la auditoría, así que no hace falta repasarlo a mano.

### Orden sugerido y qué hace cada una

**1. `menu_server_stop` + `canvas_stop`** — las más fáciles y se notan al jugar.
En `launch_game` van juntas justo antes de `log_input_devices`, con este
motivo escrito: si la ventana de menús sigue abierta, los eventos del mando no
llegan al juego y los juegos en ventana parecen esconderse detrás.

**2. `home_portable` + `home_portable_exportar`** — hacen que el juego escriba
en SU carpeta en vez de en la del usuario. En `launch_game` está sobre la línea
266 (`if _h="$(home_portable "$gid")"`) y se exporta más abajo. Ojo: el campo
del perfil es `HOME_PORTABLE` y **no se usa en ninguno de los dos** ahora mismo
(comprobado: 0 menciones en las dos funciones), así que hay que mirar cómo
llega de verdad.

**3. `dependencias_primera_vez`** — instala las dependencias que trae el propio
paquete, preguntando una vez y apuntando la respuesta en el perfil. En
`launch_game` se llama con `"$gid" "$merged" "$squash"`; en el camino de carpeta
el equivalente de `$merged` es `$_raiz_pk`.

**4. `write_full_profile`** — guardar lo que se decida al vuelo. Sin esto, en un
.pc los cambios hechos durante el lanzamiento no se conservan.

**5. `community_offer_for`** — ofrecer perfiles de la comunidad la primera vez.
En `launch_game` es la línea 21: `profile_exists "$gid" || community_offer_for "$gid" || true`.

### Lo ideal, si hay margen

El autor pidió que **todo funcione igual**, y la forma de que no vuelva a
divergir es extraer el tronco común a funciones que llamen los dos caminos,
como se hizo hoy con `preparar_librerias_prefijo`. Hacerlo **de una en una**,
con el ciclo de comprobación completo entre cada una.

La línea de órdenes **ya es consistente**: `import_input` reparte y acaba en las
mismas funciones que el menú (`play_folder` → `launch_loose_exe`, imagen →
`launch_game`). No hay una tercera forma de hacer las cosas. Verificado hoy.

---

## 3. El caso abierto: Steel Assault y TMNT (MonoGame/C#)

Dos juegos de Tribute Games, los dos en MonoGame/C#, que **fallan como carpeta
`.pc` y funcionan como `.wsquashfs`**. Da igual la unidad (interna o externa) y
da igual el equipo (CachyOS y Steam Deck).

### El error exacto

```
err:module:fixup_imports_ilonly mscoree.dll not found,
    IL-only binary L"SteelAssaultCs.exe" cannot be loaded
err:module:loader_init Importing dlls failed, status c0000135
```

`mscoree.dll` **sí está** en el prefijo y Wine lo abre (`ret 0` en
`C:\windows\system32\mscoree.dll`). El prefijo `default` lo trae de serie.

### La causa encontrada hoy, y el arreglo

`WINEDLLOVERRIDES` se exportaba **condicionalmente** y nunca se borraba. WProton
es un solo proceso que lanza varios juegos seguidos:

```
1er lanzamiento: WINEDLLOVERRIDES=mscoree=d   (por el EXE_PATH vacío)
2º  lanzamiento: _dllov vacío -> no se exportaba -> HEREDABA el mscoree=d
```

Arreglado de dos formas: `export_game_env` ahora **limpia todo al entrar** (15
variables), y `EXE_PATH` se pone antes de decidir. Hay que comprobar que el
arreglo del `EXE_PATH` está de verdad en `launch_loose_exe` (punto 1).

### Lo que está DESCARTADO con prueba — no repetirlo

| hipótesis | qué la tumba |
|---|---|
| la ruta externa / la tarjeta SD | lleva semanas funcionando con otros `.pc` |
| los espacios o el apóstrofo en el nombre | TMNT los tiene |
| montar la carpeta con overlay bajo `$HOME` | se probó, se revirtió: cambia dónde van las partidas |
| `STEAM_COMPAT_MOUNTS` | se probó, el error seguía |
| `STEAM_COMPAT_LIBRARY_PATHS` | puesto, sin confirmar que sirva |
| falta Mono en el prefijo | el DLL está y se abre (`ret 0`) |
| `mscoree=d` grabado en el registro del prefijo | WProton NO escribe overrides en el registro de Wine |
| Proton frente a Wine | los demás `.pc` van con Proton sin problema |
| el error `unable to use parent for game drive` | sale también en los que funcionan; es ruido |

### Lo siguiente a probar

1. **Lanzar un `.pc` .NET en una sesión limpia**, siendo el primer juego de esa
   sesión. Con la limpieza de `export_game_env` ya no debería heredar nada.
   **Ahora sí se puede probar de verdad**: el arreglo del `EXE_PATH` está
   confirmado dentro de `launch_loose_exe` y antes de `export_game_env`, y el
   camino ya no muere por lo de `run_in_prefix` (ver 0 bis). Antes, un `.pc`
   con `dependencies/` cerraba WProton antes de llegar al juego, así que un
   «no arranca» de esa época puede no ser este caso.
2. Si sigue: comparar los dos registros del **mismo juego el mismo día** (uno
   `.pc`, otro `.wsquashfs`) quitando todo lo que coincide. Fue lo que encontró
   la causa esta vez. El comando:

```bash
for f in log_wsquashfs.log log_pc.log; do
  grep -E "^[0-9]{2}:[0-9]{2}:[0-9]{2} \[INFO\]" "$f" \
    | sed "s/^[0-9:]* \[INFO\] //" \
    | grep -viE "MENU |Perfil |comunidad" | sed "s/[0-9]\{4,\}//g" \
    | sort -u > /tmp/$(basename $f .log).txt
done
comm -3 /tmp/log_wsquashfs.txt /tmp/log_pc.txt
```

3. La hipótesis del autor que **no está descartada**: las capas de profundidad.
   Se añadió `raiz_paquete_detectar` para que la raíz sea el `.pc` y no la
   subcarpeta del exe, pero **el parche estuvo en la función equivocada hasta el
   final de la sesión**, así que no se ha probado nunca de verdad.

---

## 4. Otro caso abierto: King of Fighters XII (Taito Type X2)

Los vídeos no se ven. **Está documentado en `COMPATIBILIDAD.md`** con siete
hipótesis descartadas. El dato duro: el juego avanza el vídeo fotograma a
fotograma por `IVideoFrameStep::Step`, que en Wine es un **stub**, y se llama
601 veces. No es un fallo de WProton y no hay variable que lo arregle.

Lo único sin probar de ese caso: el **escritorio virtual** (Batocera lo aplica
por juego con `explorer /desktop=Wine,<res>`, y WProton lo tiene en Casos
especiales). No se había probado ni una vez, y ahora se sabe por qué: WProton
lo aplica con `run_in_prefix "$squash" "$gid" winetricks -q "vd=$vres"`, y
`run_in_prefix` **cerraba WProton en seco** (ver 0 bis). Corregido: **es lo
primero que hay que probar de este caso.**

---

## 5. Lo que SÍ quedó resuelto y verificado hoy

Por si alguien duda de si tocarlo:

- **`prefijo_wine_reparar`** — `wineboot -u` automático cuando un runner Wine se
  encuentra un prefijo hecho por Proton. Probado en 6 escenarios.
- **`proton_marcar_prefijo`** — ahora busca el fichero `version` en
  `dist/`, `files/` y la raíz, porque **no siempre dicen lo mismo**: un caso real
  tenía `6.21-GE-2` arriba y `6.21-GE-1` en `dist/`, y el desajuste colgaba el
  cambio de runner con el prefijo de TeknoParrot.
- **`entorno_batocera`** — replica las variables de `batocera-wine`. Y un fallo
  gordo arreglado: el bloque de la etapa 3 estaba **dentro de un heredoc**, así
  que con `set -u` la función **moría entera** y no se aplicaba nada del entorno.
  No se vio porque las pruebas la llamaban con `| grep` y la tubería se comía la
  muerte de la subshell. **Lección: probar también sin tubería.**
- **`gst_buscar_prestado`** — una sola fuente de plugins de GStreamer de 32 bits,
  la mejor disponible, en vez de las siete que salían antes mezclando el núcleo
  de un Proton con los plugins de otro. En la Steam Deck es la única vía posible
  porque SteamOS no trae `/usr/lib32/gstreamer-1.0` y es inmutable.
- **`gst_runner_usa_gstreamer`** — no prestar plugins a un runner que usa
  winedmo/FFmpeg (Proton 11+), porque metía el `libavcodec` de otro Proton en su
  `LD_LIBRARY_PATH`.
- **El teclado en pantalla ya no arranca vacío.** `menu_pygame.py` miraba
  `len(sys.argv) > 4`, que es el argv del PROCESO, y el servidor de menús es
  persistente: la condición era falsa siempre y había que reescribir el texto
  entero cada vez. Afectaba a las 18 cajas de texto.
- **R3 y L3 como clic del ratón**, primeros en la lista y recomendados.
- **`dll_over_sistema`** y el selector de modo — la pestaña Librerías de winecfg,
  incluido desactivar una DLL.
- **ReShade (Linux/Vulkan)** como capa Vulkan, junto al de Windows.
- **Prefijo compartido**: `vcrun2022 d3dx9 d3dcompiler_43 d3dcompiler_47 xact
  openal mfc42 corefonts`. Fuera `wmp11`. Y la marca `.wp_redist_base` ahora
  guarda la lista, así que al añadir librerías los prefijos existentes las
  reciben.
- **`DIAG_VIDEO=1`** en `settings.conf` — `+file,+quartz,+winegstreamer` y un
  resumen al salir con las cuatro causas de que no se vea un vídeo.
- **Aliens Armageddon funciona**: `wine-9.22-amd64` (Kron4ek), prefijo de 32 bits
  incluido, LAA. Receta verificada en `COMPATIBILIDAD.md`.

---

## 6. Cosas que se probaron y se revirtieron — no reintentar

- **Overlay sobre la carpeta del juego** cuando está fuera de `$HOME`. Revertido:
  cambia dónde van las partidas y trata como imagen lo que es una carpeta.
  Batocera no hace nada de eso: entra en la carpeta con `cd` y lanza desde
  dentro, con Wine puro.
- **Bundle de GStreamer de Wine-GE.** No carga: está compilado contra
  `libxml2.so.2`, `libcrypto.so.1.1`, `libvpx.so.6`... que ya no existen.
  GStreamer descarta los plugins **en silencio**. De ahí la regla: un pack de
  códecs no se da por bueno por estar copiado; se comprueban sus `DT_NEEDED`.
- **Overrides de WMP nativo** (`wmp11`, `quartz`, `wmvcore`...) en Casos
  especiales. Quitados: el prefijo de Batocera donde el juego SÍ funciona no
  tiene ni un override de vídeo.
- **`mf-install`** (las DLL de Media Foundation). No integrar: son de Microsoft y
  no redistribuibles, su instalador escribe **a través de los enlaces
  simbólicos** y corrompe la instalación del runner entero, y KOF XII no usa
  Media Foundation (`mfreadwrite` y `msmpeg2vdec` aparecen 0 veces en su
  registro).

---

## 7. Errores que cometí y de los que conviene aprender

Los apunto porque son patrones, no descuidos aislados:

1. **Anclar parches por texto** que aparece en varias funciones. Dos parches
   acabaron en `run_in_prefix`. Anclar por función, siempre.
2. **Probar con `| grep`**, que crea una subshell y esconde que la función se
   está muriendo. Probar también sin tubería.
3. **Inventar nombres de variable** en vez de comprobarlos: escribí
   `OVERLAY_BIN` y era `OVERLAYFS_BIN`, así que una función entera nunca se
   ejecutó y parecía que la idea no servía.
4. **Duplicar lo que ya existe.** Empecé a escribir en `detectar.py` una
   detección de .NET que ya estaba en bash (`exe_es_dotnet`). Buscar antes.
5. **Construir sobre hipótesis sin verificar.** Cinco teorías seguidas sobre el
   caso del `.pc`, cada una encima de la anterior.
6. **Fiarse de que la auditoría en verde significa que el cambio funciona.** Los
   dos parches desviados pasaron sintaxis y auditoría sin una queja.

La auditoría del proyecto sí cazó un fallo real mío —`local gid="${2:-${gid:-}}"`,
que crea la local vacía antes de evaluar la asignación— así que **merece la pena
hacerle caso**.
