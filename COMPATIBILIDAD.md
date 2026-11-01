# Compatibilidad — recetas verificadas y casos conocidos

Notas de juegos que han costado tiempo, con lo que **se comprobó de verdad** y
lo que no. El objetivo es no volver a recorrer el mismo camino dentro de seis
meses.

Cada entrada dice si la receta está **verificada** (funcionó y hay registro) o
es una **hipótesis** (razonable pero sin confirmar). La diferencia importa: en
este documento han acabado varias hipótesis que resultaron falsas, y están
anotadas a propósito para que nadie las repita.

---

## Pintar una ventana nuestra encima del juego — HIPÓTESIS (el overlay, 20/10)

Tres cosas **verificadas en su día** (están en el código, salieron del teclado
en pantalla) y una **sin confirmar**, que es la del overlay nuevo.

**Verificado, y por eso el overlay no se hace así:**

1. Una ventana nuestra a pantalla completa delante del juego **le roba el foco
   del teclado**: las teclas del mapeador y las del teclado real dejan de
   llegarle, y un juego en ventana parece esconderse detrás. Fue lo que mató al
   teclado en pantalla, sustituido por el «texto rápido» (sin ventana).
2. **Mantener una conexión gráfica abierta durante la partida** acaba en
   `XIO: fatal IO error` cuando gamescope reconfigura su XWayland. Se lleva el
   proceso por delante, y el proceso es el que cierra el juego con Select.
3. **Leer el mando por evdev sí funciona sin foco de ventana.** Es lo que hace
   el vigilante de Select desde siempre, y es lo que permite que un panel se
   pueda manejar aunque nunca reciba el foco.

**Hipótesis, pendiente de un equipo de verdad:** que marcando la ventana con
`_NET_WM_WINDOW_TYPE_NOTIFICATION` + `_NET_WM_STATE_ABOVE` + `WM_HINTS
input = False` y pidiendo `GAMESCOPE_EXTERNAL_OVERLAY = 1` se vea encima del
juego **sin** robarle el teclado, en el escritorio **y** en el modo Juego.

La parte de EWMH es la vía estándar de los avisos del escritorio y es razonable
dar por bueno que funciona en KDE/GNOME. La de gamescope es la documentada para
que una aplicación de fuera pinte encima ([gamescope
#288](https://github.com/ValveSoftware/gamescope/issues/288), [electron
#45387](https://github.com/electron/electron/pull/45387)), **pero esa capa la
coge mangoapp y no la suelta** ([MangoHud
#775](https://github.com/flightlessmango/MangoHud/issues/775)), y en los
volcados de ventanas de la Deck aparece su ventana. Así que en el modo Juego
puede estar ocupada.

**Cómo comprobarlo sin adivinar:** el registro escribe
`overlay: ventana NNNxNNN, puesto: ...` con la lista de lo que se consiguió
poner. Si falta `capa de gamescope`, o si el panel no se ve, **antes de tocar
nada** hay que probar con MangoHud apagado: eso separa «nuestra propiedad no
vale» de «la capa está ocupada». Los pasos están en `CONTINUAR.md`, apartado
0 quindecies.

**Lo que ya se sabe que NO se puede hacer desde ahí:** encender MAKO o HelixSR
en un juego ya arrancado. MAKO es una capa de Vulkan que se inyecta con
variables de entorno **al lanzar**, y HelixSR es una DLL que el juego carga al
arrancar. No es una limitación nuestra y no tiene vuelta: el overlay solo puede
dejarlo puesto para la próxima partida.

---

## Aliens Armageddon (Raw Thrills, BudgieLoader) — VERIFICADA

Funciona. Registro `wproton_20260913_013605.log`, 13/09/2026: siete minutos de
partida y cierre limpio.

| | |
|---|---|
| runner | **`wine-9.22-amd64`** (builds de Kron4ek), tipo **wine**, NO Proton |
| prefijo | el **incluido en el `.wsquashfs`**, de **32 bits** |
| LAA | **activado** (memoria 4 GB para 32 bits) |
| usuarios | `steamuser` → `root` y `<usuario>` → `root`, que WProton remapea solo |

Con ese runner desaparece el `glError(1285): out of memory` que daba antes.

**Por qué NO servían los intentos anteriores:**

- El agotamiento de memoria **no era de la VRAM de la tarjeta**, sino del
  espacio de direcciones de 32 bits que el driver de AMD reparte entre texturas
  y código de shaders. Subir `videomemorysize` de Wine no podía arreglarlo: esa
  clave solo cambia el número que Wine *declara*, no crea direcciones. Además
  los errores eran de OpenGL (`glError`), no de Direct3D, y `videomemorysize`
  es de wined3d.
- Con Proton el prefijo de 32 bits no se monta: su script `proton` solo hace
  prefijos de 64. Hay que usar el `wine` de dentro del runner con
  `WINEARCH=win32`, que es lo que WProton hace ahora.

**Aviso que sale en el registro y aquí no estorba:** faltan `libvkd3d-1.dll`,
`libvkd3d-utils-1.dll` y `libvkd3d-shader-1.dll` en el prefijo incluido. Este
juego es OpenGL y le da igual; en uno de D3D12 sería un fallo de verdad.

**Otra cosa de la familia BudgieLoader**, documentada por la comunidad y
confirmada en el código de WProton: **BudgieLoader y ElfLdr2 se cierran si ven
GameMode o MangoHud**, porque interpretan sus avisos como errores fatales. El
runner de estos juegos no debe llevar ninguno de los dos.

---

## King of Fighters XII (Taito Type X2) — SIN RESOLVER

El juego arranca pero **los vídeos no se ven**. Dos días de diagnóstico y no se
resolvió. Se deja lo descartado, que es lo que ahorra tiempo.

**El fallo cambia según el runner, y son fallos DISTINTOS:**

| runner | qué pasa |
|---|---|
| GE-Proton 11-6 | el grafo se monta, **el audio suena y el vídeo no**. `fixme:quartz:VideoFrameStep_Step` ×601 |
| Wine puro | se atasca antes, abriendo `gamediskimg.arc`. No llega ni a `quartz` |

**El dato duro:** `IVideoFrameStep::Step` es un **stub** en Wine. El juego no
reproduce el vídeo, lo **avanza fotograma a fotograma** por esa interfaz, y
Wine se la ofrece vacía. Ofrecerla mal es peor que no ofrecerla: si `CanStep()`
dijera "no soportado", el juego caería a reproducción normal.

**Descartado, con prueba:**

- **No son los códecs.** El prefijo de Batocera donde SÍ funciona no tiene ni
  un override de vídeo: cero menciones de `quartz`, `wmv`, `wmp` o `DirectShow`
  en su `user.reg`. Su `winetricks.log` son `vcrun*`, `d3dx*`, fuentes,
  `mfc42`, `openal`, `physx`, `nocrashdialog`, `isolate_home` y `sandbox`.
- **No es el prefijo ni el runner.** Se probaron los dos de Batocera (GE 9.25
  modificado) en WProton y falla igual.
- **No es FUSE.** El juego estuvo primero en carpeta y luego en `.wsquashfs`,
  con el mismo resultado.
- **No es DXVK ni WineD3D.** Probados los dos.
- **No es la longitud de la ruta.** 58 caracteres, lejos de `MAX_PATH`.
- **No es GStreamer en Proton 11.** Desde GE-Proton 11-1 el vídeo va por
  `winedmo→ffmpeg` y GStreamer se eliminó del build entero; `winegstreamer` no
  se carga ni una vez.
- **No es el cifrado.** Con Proton el audio SÍ suena, del mismo fichero: se
  encuentra, se descifra y se demultiplexa bien.

**Sin comprobar todavía** (las tres diferencias que quedan frente a Batocera):

1. **Escritorio virtual.** Batocera lo aplica por juego con
   `explorer /desktop=Wine,<resolución>`. El renderizador de vídeo de
   DirectShow se comporta distinto dentro de una ventana que a pantalla
   completa. WProton lo tiene en *Casos especiales* y **no se ha probado**.
2. **X11 frente a Wayland.** Batocera corre en X11; el wine-tkg de las pruebas
   se fue a `winewayland.drv` solo.
3. **El `cd` y el `CMD` relativo.** Batocera entra en la carpeta del juego y
   lanza por nombre; WProton lanza por ruta absoluta `Z:`.

**Contexto de la comunidad:** dos usuarios reportan que KOF XII usa
*cryptserver* y está roto en Wine, con un bug abierto en el Bugzilla. Comparten
causa Darius, KOF XIII Climax, Persona 4 y los BlazBlue.

---

## Prefijo de TeknoParrot con un runner Wine — VERIFICADO (v1.76)

Síntoma: con **cualquier** runner Wine (Wine LG, Wine 11, wine-9.22) y el
prefijo **TeknoParrot**, se queda colgado sin llegar a lanzar. Con prefijo
propio va; con el compartido, a veces.

**Causa, la cadena entera:**

1. `launch_loose_exe` no cerraba el wineserver al terminar: ese bloque estaba
   escrito dentro de `launch_game`, y por ahí no pasan los juegos en carpeta.
2. Los de TeknoParrot van en carpeta y **comparten** el prefijo, así que
   dejaban vivos `wineserver`, `services.exe` y `winedevice` en él.
3. Al siguiente lanzamiento con Wine, `prefijo_wine_reparar` hace `wineboot -u`
   sobre ese prefijo, cuyo wineserver sigue vivo **y es de otra versión**. Eso
   cuelga; está documentado en wine-tkg (#387, #393) y el único remedio es
   matar los procesos de Wine antes de reintentar.
4. `wineserver -w` espera hasta que **todos** los procesos del prefijo
   terminen. Si no se van a ir, espera para siempre.
5. La marca `.wp_wine_listo` sólo se escribía al final, así que se repetía en
   cada intento.

**Por qué sólo con Wine:** `prefijo_wine_reparar` se llama únicamente en la
rama `kind = wine` de `build_runner_cmd`. Con Proton no se toca.

**Qué hace WProton ahora:** `wineserver_cerrar_prefijo` es una sola función que
llaman los dos caminos, así que el prefijo se cierra siempre al terminar la
partida; `prefijo_wine_reparar` lo cierra además **antes** de `wineboot -u`; el
plazo se respeta de verdad (si se agota se avisa y **no** se marca el prefijo
como listo, para que el siguiente intento vuelva a probar); y los plazos están
acotados en `WP_WINESERVER_TIMEOUT` (20 s) y `WP_WINEBOOT_TIMEOUT` (180 s).

**Aviso para el futuro:** este prefijo lleva un enlace `pfx -> .`, o sea a sí
mismo, que `prefijo_enlace_pfx` pone para que Proton lo encuentre. `find` sin
`-L` no lo sigue y hoy no estorba, pero **nada que recorra el árbol siguiendo
enlaces** (`find -L`, `du`, `cp -r`, `rsync`) debe tocar un prefijo.

---

## Vídeos WMV en juegos de 32 bits — VERIFICADO (el diagnóstico)

Síntoma: **el juego se oye pero no se ve**, y algunos se caen al llegar al
vídeo.

**Causa:** un juego de 32 bits descodifica su vídeo en el proceso de 32 bits y
necesita plugins de GStreamer **de 32 bits**. En Arch y CachyOS la multilib trae
el núcleo y `gst-plugins-base`, pero **no los descodificadores**: `gst-libav`
(que es quien trae `avdec_wmv3`) y `gst-plugins-ugly` están solo en la AUR.

Sin ellos `quartz` no puede montar el grafo y devuelve **`VFW_E_CANNOT_RENDER`
(0x80040218)**. Los juegos que no comprueban ese HRESULT desreferencian el
puntero nulo y se caen.

Cómo se vio en un volcado real: solo cargaban `libgstcoreelements`,
`libgstplayback` y `libgsttypefindfunctions` —núcleo y base— y en la pila
aparecía `80040218` cuatro palabras antes del `EAX:00000000`.

**Qué hace WProton ahora, solo:** busca plugins de 32 bits en cualquier Proton
instalado y se los presta al runner en uso, con sus librerías en
`LD_LIBRARY_PATH`. Una sola fuente, la mejor, nunca varias mezcladas.

**En la Steam Deck esta es la ÚNICA vía**: SteamOS no trae
`/usr/lib32/gstreamer-1.0` y, siendo inmutable, no se pueden instalar los
`lib32-*`.

### Pendiente de probar: GE-Proton 11-7 puede hacer esto innecesario

GE-Proton 11-7 (16/09/2026) implementa el **conversor de espacio de color RGB de
Quartz** y permite que **QASF negocie audio y vídeo ASF comprimido con los DMO
descodificadores de WMA/WMV**. Eso ataca exactamente este caso, pero por dentro
de Wine y sin GStreamer de por medio.

Si se confirma, el pack de códecs de 32 bits deja de hacer falta con 11-7 y
posteriores — y el préstamo de plugins que hace WProton se queda como red para
los runners anteriores.

**Cómo comprobarlo:** un juego de los que se oían y no se veían, con 11-7 y
**sin** el pack de códecs instalado. Si se ve, caso cerrado. Apuntar aquí el
resultado, en un sentido o en otro.

> Ojo al confundir vías: el mismo 11-7 rebasa FFmpeg/winedmo, Media Foundation,
> DirectShow, audio y HLS **sin reinstaurar Wine-GStreamer**. O sea que la
> detección de WProton («este runner reproduce vídeo por FFmpeg, no por
> GStreamer») sigue siendo correcta; lo que cambia es que ahora hay un camino
> alternativo dentro de Quartz.

### Lo que NO funciona, probado

**Reaprovechar un bundle de Wine-GE.** Está descontinuado y viene compilado
contra librerías de su época — `libxml2.so.2`, `libcrypto.so.1.1`,
`libvpx.so.6`, `libwebp.so.6`, `libopus.so.0`. Un sistema al día ya no las
tiene, **GStreamer descarta esos plugins en silencio** y el resultado es
idéntico a no tener nada. En un registro real fallaron 18 plugins, y uno era
justo `libgstlibav.so`.

De ahí la regla: **un pack de códecs no se da por bueno por estar copiado**.
WProton comprueba los `DT_NEEDED` de cada plugin y descarta el pack entero si
alguno no resuelve — porque al ir primero, taparía a los que sí funcionan.

---

## Cambiar de runner con un prefijo compartido — VERIFICADO

Síntoma: cambias de runner y el juego **se queda colgado sin cambiar**.

```
Proton: Upgrading prefix from 6.21-GE-2 to 6.21-GE-1
Proton: Prefix has an invalid version?!
```

**Causa:** el fichero `version` puede estar en tres sitios y **no siempre dicen
lo mismo**:

```
<runner>/version        el de la envoltura
<runner>/dist/version   la carga util en los Proton-GE de la serie 6/7
<runner>/files/version  idem en los modernos
```

Proton se compara contra el de **su carga útil**. Marcando el prefijo con el
nombre de otro fichero, lo da por viejo, intenta actualizarlo y se cuelga.
`proton_marcar_prefijo` prefiere ahora el de `dist/` o `files/` y deja los tres
en el registro.

Se nota sobre todo con el prefijo de **TeknoParrot**, que es compartido y por
tanto el único que arrastra la marca de un runner a otro.

---

## `lsteamclient` en los lanzamientos por umu — GE-Proton 11-7

**No es un fallo, es un cambio de comportamiento que nos toca de lleno**, porque
WProton lanza todo por `umu-run`.

GE-Proton 11-7 **desactiva `lsteamclient` para los lanzamientos por UMU** salvo
que se ponga `UMU_USE_STEAM=1` explícitamente. Antes el comportamiento estaba
invertido, o sea que se cargaba cuando no debía.

**Para lo que hace WProton el valor nuevo es el correcto:** los juegos que
lanzamos no son de Steam y no necesitan su API. Un juego que se confundía con
`lsteamclient` cargado debería ir mejor a partir de 11-7.

**Si algún día un juego SÍ la necesita**, se le pone por perfil sin tocar el
script: *Ajustes del juego → Rendimiento y compatibilidad → Variables extra*,
con

```
UMU_USE_STEAM=1
```

No hace falta un campo nuevo: `ENV_EXTRA` ya lo cubre.

De la misma versión, y en una ruta que sí usamos: ahora **devuelve un fallo
normal de inicialización si no se puede cargar el steamclient nativo, en vez de
abortar**, incluyendo las rutas de creación de prefijo de Faugus y **Winetricks**.
WProton crea prefijos con winetricks, así que eso nos quita de encima un fallo de
los que cierran el proceso.

---

## GE-Proton 11-7: qué vigilar antes de darlo por bueno

La serie de renderizado de procesos hijo son **85 parches numerados**, más un
rebase de Wine, DXVK, VKD3D-Proton y FEX. Es mucho movimiento en la parte
gráfica para una sola versión.

El propio autor marca varias cosas como **pendientes de reprobar**: el swapchain
de Marvel Rivals ante `VK_NOT_READY`/`VK_TIMEOUT`, y el HDR de DOOM Eternal. Y
en la mejora de scanout directo advierte de que no se dé por verificada toda
configuración: hay un informe posterior de ventana que desaparece.

**Regla práctica:** si un juego empieza a dar pantallas negras, ventanas
diminutas o cursor raro con 11-7, **no perseguirlo — probar primero con 11-6**.
Con el menú por series, bajar el 11-6 son dos pulsaciones.

Lo bueno del 11-7 para nosotros, además de lo de arriba:

- **Mando:** Grandia, Grandia II y Lunar pasan de falsear identidad DS4 a **Sony
  XInput más el Steam Input fallback**. O sea que GE usa el fallback como
  solución, lo mismo que hace WProton con `PROTON_STEAMINPUT_XINPUT_FALLBACK`.
  Y `runner_gestiona_mandos` ya cubre 11-7: la puerta es GE-Proton ≥ 11-4.
- **Sony a XInput de serie** en Capcom Fighting Collection 1 y 2, MARVEL vs.
  CAPCOM Fighting Collection, Street Fighter 30th Anniversary Collection y
  Tetris Effect: Connected.
- **`vcrun2008`:** las DLL de WinSxS pasan a ser reemplazables en vez de quedarse
  como enlaces de solo lectura, lo que arregla su instalación. Va por donde
  instalamos redistribuibles.
- **Mono sin el .NET 4.8 de Winetricks:** se enseña a Mono a distinguir entradas
  FieldRVA a cero de datos ausentes. Puede que algún juego que exigía `dotnet48`
  vaya ya con el Mono de serie — toca nuestra historia de `MONO_PEDIR`.

---

## Falso positivo: «Este programa es .NET y Mono está desactivado» — CORREGIDO (v1.76)

**Síntoma:** un juego que se ejecuta perfectamente muestra al salir un diálogo
de error diciendo que es .NET, que Mono está desactivado y que hay que instalar
`dotnet48`. El juego no necesita .NET para nada.

**Causa: la regla se autoengañaba.** Pedía encontrar `mscoree=d` en el registro
y además que apareciera la palabra `mscoree`, `.NET`, `Wine Mono` o `CLR`. Pero
`mscoree=d` **es la anulación que pone WProton** cuando Mono está desactivado en
el perfil, y esa misma cadena contiene `mscoree`: la segunda condición casaba
siempre que se cumpliera la primera. Cualquier juego con Mono apagado —que es lo
normal y lo que le conviene a casi todos— salía acusado.

**Arreglo:** ahora hace falta que **Wine se queje de verdad** (`mscoree.dll not
found`, `failed to load … CLR`, `err:…mscoree`, o el `fixup_imports_ilonly` del
binario IL-only). La presencia de nuestra propia anulación ya no es prueba de
nada.

**Y un segundo fallo en el mismo diálogo.** El aviso de «repite la misma línea
miles de veces» llamaba al analizador con **el registro entero**, así que el
diagnóstico podía no tener relación con la línea repetida: se juntaban dos
hechos sin relación y se presentaban como causa y efecto. Ahora el diálogo solo
sale si la línea repetida **parece un error**; si no, se queda anotada en el
registro y no se interrumpe a nadie. Un juego que ha funcionado no merece un
diálogo de error al salir.

---

## Cómo saber si Steam Input está activo (y por qué importa)

Steam no ofrece ninguna forma de consultarlo, pero **deja una huella en el
entorno**. Comparando dos registros del mismo juego el 17/09 —uno sin mando y
otro funcionando— los entornos tenían 37 variables cada uno y solo diferían en
dos. Una era ruido. La otra:

```
21:51  Steam Input encendido, el juego sin mando   -> SDL_GAMECONTROLLER_USE_BUTTON_LABELS presente
21:55  Steam Input apagado, funcionando            -> AUSENTE
```

Esa variable la pone Steam como parte del entorno de Steam Input: le dice a SDL
que use las etiquetas del mando que está emulando. Si Steam Input está apagado
para el atajo, Steam no la pone.

WProton lo dice ahora en cada lanzamiento:

```
Steam Input: ACTIVO para este atajo (SDL_GAMECONTROLLER_USE_BUTTON_LABELS presente)
[i] Steam Input esta ACTIVO y el unico mando es el que el ofrece.
```

o bien:

```
[+] Steam Input no esta activo: el juego recibe tu mando tal cual.
```

**Es una señal, no una certeza:** sale de una sola comparación, así que no se
usa para decidir nada, solo para dejarlo dicho. Media semana de pruebas se fue
en no saber si una sesión se había hecho con Steam Input puesto o quitado.

**Lo importante del hallazgo:** los dos entornos eran por lo demás idénticos.
`PROTON_PREFER_SDL`, `PROTON_USE_SDL`, la lista de ignorados borrada,
`SDL_GAMECONTROLLER_ALLOW_STEAM_VIRTUAL_GAMEPAD`… todo igual en el que funciona
y en el que no. **Ninguna variable de entorno arregla este caso**: o Steam
suelta el mando físico, o el juego no lo ve.

---

## El mando virtual se llamaba igual que el de Steam — CORREGIDO (v1.76)

**Síntoma:** después de activar el mando virtual en un juego, al entrar en otro
parecía que el ajuste se había quedado pegado: se veía «mando Xbox 360».

**No era el ajuste.** Los perfiles no arrastran valores entre juegos —
comprobado: se guarda `xbox` en el juego A, se carga el perfil del juego B y
sale `0`, y si se guarda B queda `0`.

**Era el nombre.** Nuestro mando virtual se llamaba exactamente `Microsoft
X-Box 360 pad`, y el mando virtual **de Steam Input** se llama `Microsoft X-Box
360 pad 0`. En un registro o en un menú son indistinguibles.

Ahora el nuestro se llama **`WProton Xbox 360 pad`**. El fabricante/modelo no se
toca (`045e:028e`), así que SDL lo sigue reconociendo como un Xbox 360 de verdad
y los botones salen bien; lo único que cambia es cómo se lee.

Y los mandos se vuelven a enumerar **después** de crear el virtual: antes
`log_input_devices` corría solo antes, así que en el registro únicamente salía
el de Steam y no había forma de saber si el nuestro había aparecido.

---

## TMNT Shredder's Revenge — sin mando en modo Juego — CERRADO (17-18/09/2026)

**Síntoma:** en el modo Juego de SteamOS el juego solo reconoce el teclado. En
el modo escritorio va bien.

**Solución que funciona:** desactivar Steam Input para el atajo de WProton
desde el menú de Steam (*Mando → Desactivar Steam Input*). Verificado.

**Y nada más funciona.** Esto está probado por descarte, no por sospecha:

| Probado | Resultado |
|---|---|
| Superposición de Steam quitada | sin efecto (el 1.60 ya lo hacía y los juegos salían) |
| Identidad de Steam quitada (`SteamAppId`, `SteamGameId`…) | sin efecto |
| Etiqueta `STEAM_GAME` borrada de las ventanas (5 quitadas) | sin efecto |
| `PROTON_PREFER_SDL` + `PROTON_USE_SDL` | sin efecto |
| Puente `PROTON_STEAMINPUT_XINPUT_FALLBACK` | sin efecto |
| Lista de 759 ignorados de SDL borrada | sin efecto |
| Las dos anteriores **juntas** | sin efecto |
| Mando virtual propio (`WProton Xbox 360 pad`) | sin efecto |
| 8BitDo físico conectado además | sin efecto |

**La prueba decisiva** (registro del 18/09, 00:13). Con el 8BitDo conectado
había **cuatro** mandos en `/dev/input`:

```
mando 1: "8BitDo Ultimate 2C Wireless Controller"  [2dc8:301c]   el físico
mando 2: "Microsoft X-Box 360 pad 0"               [28de:11ff]   virtual de Steam
mando 3: "Microsoft X-Box 360 pad 1"               [28de:11ff]   otro de Steam
mando 4: "WProton Xbox 360 pad"                    [045e:028e]   el nuestro
```

De ellos, el 1 lo tiene cogido Steam Input y el 2 lo cogimos nosotros como
origen del virtual — pero el **3 y el 4 estaban libres**, y el juego no vio
ninguno.

**Conclusión:** no es cuestión de qué mando se le ofrece al juego ni de qué
variables recibe. Con Steam Input activo, **Wine no enumera ningún mando de
evdev** en esta configuración. Eso está fuera de WProton: o Steam suelta el
mando, o no hay mando.

**Comparación de entornos** (17/09, 21:51 fallando vs 21:55 funcionando): 37
variables cada uno, idénticas salvo `SDL_GAMECONTROLLER_USE_BUTTON_LABELS`
—presente solo con Steam Input activo— y una de MangoApp. Ninguna variable de
entorno arregla este caso.

**Lo que sí salió de todo esto**, y se queda:

- El mando virtual **funciona por fin**: su módulo no se había ejecutado nunca
  (`import evdev` sin las rutas de `libs_pyX.Y`, y `mando_virtual_start` que no
  llamaba a `write_mando_virtual`, así que el fichero en disco estaba congelado).
- Se detecta y se dice si Steam Input está activo en cada lanzamiento.
- Los mandos se enumeran también **después** de crear el virtual.
- Apartado 13 de la auditoría: quien ejecuta un módulo, lo escribe.

---

## Juegos fantasma con nombres tipo `$I7E176E` — CORREGIDO (v1.76)

**Síntoma:** en un disco con NTFS o exFAT aparecen en la biblioteca entradas con
nombres como `$I7E176E`, `$RZJNUDM` o `$RECYCLE.BIN`, sin carátula ni ficha. En
Dolphin no se ven.

**Qué son:** la **papelera de Windows**. Al borrar, Windows guarda el contenido
en `$R<6 letras>` y sus metadatos en `$I<6 letras>`, **conservando la
extensión**. Así que un `Juego.wsquashfs` borrado desde Windows se queda como
`$RZJNUDM.wsquashfs` dentro de `$RECYCLE.BIN/<usuario>/`. El escaneo baja tres
niveles, los encontraba y los ofrecía como juegos.

Dolphin no los enseña porque están marcados como ocultos; `find` no mira ese
atributo.

**Arreglo:** los siete escaneos pasan ahora por `find_paquetes`, que poda las
carpetas de sistema: `$RECYCLE.BIN`, `RECYCLER`, `System Volume Information`,
`lost+found`, `.Trash-*`, `found.???`, `.Spotlight-V100`, `.fseventsd` y
`.TemporaryItems`. Las carpetas de primer nivel se filtran igual, así que
tampoco sale `$RECYCLE.BIN` como si fuera un juego en carpeta.

> **Un aviso para quien toque esto:** el primer intento metía toda la expresión
> de poda en una variable y la expandía sin comillas. Con `System Volume
> Information` eso se parte en tres palabras, la expresión de `find` queda
> inválida, y como el error iba a `/dev/null` la búsqueda devolvía **cero
> resultados en silencio** — te quedabas sin biblioteca y sin saber por qué. La
> poda va con argumentos sueltos.

---

## Un prefijo hecho en otro equipo no arranca en la Deck — CORREGIDO (v1.76)

**Síntoma:** un `.wsquashfs` con su prefijo dentro, creado y probado en otro
equipo (CachyOS), funciona allí y en SteamOS falla. El registro se llena de:

```
err:setupapi:create_dest_file failed to create L"C:\\windows\\explorer.exe" (error=80)
err:setupapi:create_dest_file failed to create L"C:\\windows\\system32\\wbem\\mofcomp.exe" (error=80)
...
```

y el juego termina con `rc=1`.

**Causa:** un prefijo de Proton guarda los ficheros de Windows como **enlaces al
runner**. Al traerlo a otro equipo esos enlaces apuntan a rutas que allí no
existen —en el caso real, 1207 apuntando a
`/home/dani/Descargas/DeckStation/…`—. WProton ya los limpiaba, **pero solo en
`system32` y `syswow64`, y con `-maxdepth 1`**. Los que quedaban colgados
estaban justo fuera de ahí:

```
drive_c/windows/explorer.exe, notepad.exe, regedit.exe      la raíz
drive_c/windows/system32/wbem/, drivers/, Speech/, gecko/   subcarpetas
drive_c/windows/winsxs/…, resources/themes/…
```

Y **un enlace colgado sigue «existiendo»** para quien intenta crear el fichero:
`wineboot` los encontraba y fallaba con `error=80`, que es `ERROR_FILE_EXISTS`.

**Arreglo, y en el sitio correcto: el archivo nace portátil.**

`prefijo_hacer_portable` quita del prefijo toda ruta del equipo donde se hizo, y
se llama **al empaquetar** —para que el `.wsquashfs` valga en cualquier
máquina— y también **al usarlo**, para los archivos que ya estaban hechos con
versiones anteriores.

La regla no es «quitar los enlaces rotos» sino **quitar los que dependen de la
máquina**: todo enlace cuyo destino sea absoluto y caiga fuera del prefijo. Un
enlace a `/home/dani/…` puede resolver en otro equipo por casualidad y seguir
siendo basura. Los relativos se quedan: son portátiles por definición.

**Solo se toca `drive_c/windows` y `dosdevices`. Nada más.**

| Qué | Qué se hace |
|---|---|
| Enlaces absolutos de `drive_c/windows` que salen del prefijo | Se borran: son del runner del otro equipo |
| `dosdevices/c:` | Se rehace como `../drive_c`, relativo |
| `dosdevices/z:` | Se rehace como `/` |
| Otras letras (`d:`, `e:`…) | Se quitan: son unidades montadas del otro equipo |
| **Todo lo demás, incluido `drive_c/users`** | No se toca |

> **Por qué ese límite, y a costa de qué se aprendió.** La primera versión
> barría el prefijo entero quitando todo enlace absoluto que saliera de él, y se
> llevó por delante algo que WProton pone a propósito:
> `drive_c/users/steamuser/AppData` es un **enlace al archivo montado**, para no
> duplicar cientos de megas. Al convertirlo en carpeta vacía, el juego arrancaba
> **pero sin sus datos** — justo lo contrario de lo que se buscaba, y en un
> juego que lleva prefijo propio precisamente por lo que hay en
> `AppData/Local`.
>
> Los enlaces problemáticos están todos en `drive_c/windows` y en `dosdevices`.
> Fuera de ahí no hay nada que arreglar y sí mucho que romper.

**Y quitar los enlaces NO BASTA.** Un prefijo de Proton guarda medio Windows
como enlaces al runner; si se quitan y nadie los repone, se queda sin
`kernel32.dll` y `wineboot` ni arranca:

```
1294 enlace(s) a rutas de otro equipo eliminados
wine: could not load kernel32.dll, status c0000135
...y el juego termina con rc=53
```

Quien sabe reponer todo eso es **Proton**, que rehace el prefijo cuando la
versión no le cuadra. Pero WProton le decía lo contrario: marcaba el prefijo
como «ya al día para este runner» y Proton se lo saltaba. Así que **al quitar
enlaces se borra esa marca** (`version`, `pfx/version`, `.update-timestamp`) y
Proton lo rehace. Cuesta un arranque más lento la primera vez.

Al empaquetar lo dice:

```
[+] Prefijo hecho portatil: 1207 enlace(s) a este equipo quitados,
    3 carpeta(s) de usuario rehechas, 1 unidad(es) de dosdevices
    (asi el archivo vale en cualquier maquina, no solo en esta)
```

---

## Los clics de raton de un `.keys` no llegaban al juego - CORREGIDO (v1.76)

**Sintoma:** un `.keys` que mapea teclas **y** botones de raton (`BTN_LEFT`,
`BTN_RIGHT`) funciona con las teclas, pero los clics no hacen nada. Caso real:
8bit Killer, con los gatillos mapeados a `BTN_LEFT` y `BTN_RIGHT`.

**Causa:** el raton virtual **no se creaba**. Solo se creaba si el `.keys` traia
un bloque `mouse` o una accion `type: mouse`; un fichero que pide el clic con
`"type": "key"` y `"target": "BTN_LEFT"` no lo encendia. Sin raton virtual, los
clics no tienen por donde salir.

**El aviso ya estaba y decia la verdad**, en el registro del juego:

```
[keys] AVISO: el .keys pide BTN_RIGHT (boton de raton) pero no hay raton virtual
```

**Arreglo:** el raton virtual se crea tambien cuando alguna tecla, direccion o
combinacion apunta a un boton de raton. En ese caso solo sirve para los clics:
el puntero no se mueve, y se dice asi en el registro.

> **Un intento fallido antes de dar con esto:** declarar `EV_REL` en el teclado
> virtual para que el aparato pareciera tambien un raton. La teoria era razonable
> -X11 no clasifica como raton lo que no tiene ejes relativos- pero el problema
> era otro y mas simple: el raton no llegaba a existir. La pista estaba en el
> registro desde el primer momento, en una linea que no se llego a leer.

---

## Restaurar una copia de partidas en otro equipo no hacia nada - CORREGIDO (v1.76)

**Sintoma:** se hace copia de las partidas en un equipo (la Deck), se lleva el
zip a otro (CachyOS) y al restaurar dice que ha ido bien, pero el juego sigue
sin la partida.

**Causa:** el manifiesto de la copia guarda **rutas absolutas del equipo donde
se hizo**:

```
NEON INFERNO|/home/deck/wptoton/prefixes/default/drive_c/users/dani/...
```

En el otro equipo ese `/home/deck/...` no existe. El restaurador hacia `mkdir -p`
de esa ruta tan ricamente -creando un arbol vacio donde no lo ve nadie- y
copiaba las partidas ahi. Decia "Restauradas 6 carpetas" y era verdad: en un
sitio que el juego no mira.

Es el mismo fallo que tenian los prefijos: rutas de una maquina metidas en algo
hecho para viajar.

**Arreglo:** al restaurar, de la ruta guardada se toma desde `prefixes/` en
adelante y se le pone delante la carpeta de **este** equipo. Funciona con las
copias ya hechas, que es lo que importa: nadie va a rehacer sus copias de
seguridad.

Y si una ruta no pasa por `prefixes/` y aqui no existe, **ya no se crea a
ciegas**: se avisa y se salta. Crear arboles donde no los hay es lo que hacia
que esto fallara en silencio.

```
[restaurar] ruta rehecha para este equipo:
            /home/deck/wptoton/prefixes/default/drive_c/users/dani/...
         -> /home/dani/…/wproton/prefixes/default/drive_c/users/dani/...
```

---

## Un juego que se cierra solo: como se averigua

**No te fies del codigo de salida.** El `rc` que sale en el registro lo da el
ENVOLTORIO (umu/proton), no el juego: un juego puede reventar por dentro y
dejar un `rc=0`. Esto costo un diagnostico equivocado el 27/09 con Crazy Taxi 3,
donde se dio por bueno que "rc=0, luego no es un cuelgue".

Cuando una partida acaba antes de diez minutos o con error, WProton mira ahora
en tres sitios:

1. **Lo ultimo que escribio el juego**, filtrando lo nuestro (menus, mapeador,
   volcado de ventanas). Ahi salen los `err:seh`, los page fault o el mensaje
   propio del juego, si los hubo.
2. **Los volcados de fallo del sistema** (`coredumpctl`). Si el juego se fue por
   SIGSEGV, systemd lo tiene aunque nuestro registro no tenga nada.
3. **La falta de memoria** (`journalctl -k` o `dmesg`), mas cuanta memoria y
   swap quedaban al acabar.

```
---- el sistema registro VOLCADOS DE FALLO en los ultimos 5 min ----
Sat 2026-09-27 16:38:45 CEST  9178  1000  1000 SIGSEGV present  /…/CrazyTaxi3.exe
  Si ahi sale el .exe del juego o wine, ES UN CUELGUE.
  Para ver el detalle: coredumpctl info <PID de esa lista>
```

Si no estan `coredumpctl` ni `journalctl`, se dice y se sigue: son fuentes de
informacion, no dependencias.

---

## Un juego de Linux se cerraba nada mas arrancar - CORREGIDO

**Sintoma:** un `.wsquashfs` con un juego de Linux (`.sh` o AppImage) se
detecta, arranca y se cierra en el acto. En el registro, todo en el mismo
segundo:

```
19:10:14  Lanzando juego de Linux: Crazy Taxi 3 High Roller.sh
19:10:14  Cierre con el juego aun en marcha: se espera un poco
19:10:14  Cierre: desmontando
```

**Causa:** un lanzador `.sh` casi nunca ES el juego. Prepara el entorno y
arranca el binario de verdad, muchas veces dejandolo de fondo, y termina en
medio segundo. WProton daba la partida por acabada, **desmontaba el archivo con
el juego arrancando** y el juego se quedaba sin sus propios ficheros.

Con un juego de Windows no pasaba porque ahi se espera a que no quede ningun
proceso del prefijo.

**Arreglo:** tras lanzar, se espera a que no quede **ningun proceso usando la
carpeta del juego**. Se mira en `/proc` -el ejecutable, el directorio de trabajo
y el mapa de memoria de cada proceso-, sin `lsof` ni `fuser`, que pueden no
estar. No vale buscar por nombre: el binario real suele llamarse distinto que el
`.sh`.

> **Un detalle que costo una prueba fallida:** al comparar rutas hay que aceptar
> la carpeta EXACTA, no solo lo que cuelga de ella. Un lanzador hace `cd` a la
> carpeta del juego, asi que el directorio de trabajo del proceso es la carpeta
> a secas. Comparando solo con `$raiz/*`, ese proceso no casaba y se dejaba de
> esperar: en la prueba, el juego duraba 6 segundos y se volvia a los 2.

---

## WProton se colgaba al lanzar un juego de Linux - CORREGIDO

**Sintoma:** un juego de Linux (`.sh` o AppImage) arranca y WProton se queda
colgado detras. En el modo Juego de SteamOS, Steam acaba matandolo y parece que
"WProton se cierra solo"; en escritorio se nota menos.

**Causa: la espera se contaba a si misma.** Tras lanzar, WProton espera a que no
quede ningun proceso usando la carpeta del juego. Pero esa espera se ejecuta CON
EL DIRECTORIO DE TRABAJO DENTRO de esa misma carpeta, asi que se contaba ella
misma y la cuenta no bajaba de uno jamas.

Fueron **tres capas del mismo error**, y cada una tapaba a la siguiente:

1. El propio proceso que espera, y toda su cadena de padres.
2. El `sleep` del bucle de espera, que hereda el directorio de trabajo.
3. El `grep -c` con el que se contaba: un proceso hermano, tambien dentro de la
   carpeta, que se contaba a si mismo.

**Arreglo:** se descartan el proceso propio y sus padres, el `sleep` se lanza
aparte para conocer su PID y descartarlo tambien, y la cuenta se hace **en el
propio bash** (`contar_lineas`) sin crear ningun proceso auxiliar.

> **La leccion:** medir quien usa una carpeta desde dentro de esa carpeta falsea
> la medida. Cualquier proceso que se lance para medir -aunque sea un `grep`-
> entra en lo medido.

**Como se encontro:** ejecutando el camino de lanzamiento en un banco de pruebas
con un juego de mentira, en vez de seguir añadiendo diagnosticos al registro y
pedir otra partida. Los registros decian "salida normal" y "ultima orden: kill",
las dos pistas falsas.

---

## Salir con Select no funcionaba en los juegos de Linux - CORREGIDO

**Sintoma:** mantener Select cinco segundos cierra los juegos de Windows pero no
los de Linux.

**Dos fallos encadenados:**

1. El vigilante corre en un **subshell creado ANTES de lanzar el juego**, asi
   que su copia de `WP_PID_JUEGO` esta vacia para siempre: esa variable se
   asigna casi 200 lineas mas abajo, en el proceso padre. Siempre caia en "no
   se sabe que proceso cerrar".
2. Y aunque lo supiera, no bastaria: ese PID es el del subshell de lanzamiento,
   y **un lanzador `.sh` arranca el juego de fondo y termina**. El juego de
   verdad ya no es hijo nuestro -lo adopta init-, asi que matar al subshell con
   sus hijos no le alcanza.

**Arreglo:** se cierra **por la carpeta**, que es lo que de verdad identifica al
juego. La raiz se deja escrita en un fichero al arrancar el vigilante -una
variable no cruza al subshell- y al pedir salir se manda TERM a todo lo que este
usando esa carpeta, y KILL dos segundos despues a lo que quede.

Probado con un lanzador que se va en medio segundo y un juego que queda
huerfano: dos procesos cerrados, cero restantes.

---

## "BUG in get_virt_disk" al empaquetar - RODEADO (no es nuestro)

**Sintoma:** al empaquetar una carpeta a `.wsquashfs`, la compresion se corta a
medias con:

```
FATAL ERROR: BUG in get_virt_disk, 1817091580 not found
```

**No es de WProton.** Es un fallo de `mksquashfs` (squashfs-tools), reportado
como el [issue 360](https://github.com/plougher/squashfs-tools/issues/360), que
su autor marca como duplicado del 362 y da por corregido en el codigo mas
reciente. Se ha visto en la version 4.7.5 (marzo de 2026).

No tiene relacion con el contenido de la carpeta: en el caso real era un juego
de Linux con un `.sh`, pero le pasa igual con cualquier cosa.

**Que hace WProton:** al detectar ESE mensaje concreto en el registro, reintenta
solo con `-no-duplicates`, que es donde aparece el fallo. El archivo sale un
poco mas grande y a cambio se crea. Si tambien falla, se explica y se ofrecen
las dos salidas reales: actualizar squashfs-tools, o empaquetar en **DwarFS**,
que comprime mas y no usa mksquashfs.

Se reintenta solo ante ese mensaje: reintentar a ciegas ante cualquier error
haria esperar el doble para volver a fallar por lo mismo.

---

## "El empaquetado fallo" con mksquashfs - SORTEADO

**Sintoma:** al empaquetar una carpeta a `.wsquashfs`, mksquashfs se corta a
media compresion con:

```
FATAL ERROR: BUG in get_virt_disk, 1817091580 not found
```

**No es un fallo de WProton.** Es una condicion de carrera de squashfs-tools,
reportada como el issue 360 del proyecto y explicada en el 362: al comprobar
ficheros duplicados, si un fichero es demasiado grande para el buffer hay que
volcar bloques a disco, y con ficheros que tienen huecos (sparse) el codigo
puede intentar leerlos antes de que esten escritos. Se ve en la version 4.7.5.

**Como lo sortea WProton:** al fallar, reintenta solo con `-no-duplicates`, que
es el camino donde esta el fallo. El archivo sale algo mas grande y a cambio se
crea. Si tambien falla, propone actualizar squashfs-tools o empaquetar en
DwarFS, que no usa mksquashfs.

> **Y una espera de un segundo antes de mirar el registro**, que es lo que hacia
> que el reintento no saltara: mksquashfs escribe su `FATAL ERROR` por una
> tuberia y esa linea puede aterrizar en el fichero DESPUES de que nosotros la
> busquemos. El usuario veia "El empaquetado fallo" a secas y el motivo aparecia
> en el registro justo despues.

Ademas, si el registro no acusa a nada concreto -sin espacio, sin permisos- se
reintenta igualmente: la deteccion de duplicados es de donde salen los fallos
raros de mksquashfs, y un segundo intento cuesta menos que quedarse sin el
archivo.

---

## El empaquetado falla con "BUG in get_virt_disk"

**No es cosa de WProton:** es un fallo conocido de `mksquashfs`
([issue #360](https://github.com/plougher/squashfs-tools/issues/360), duplicado
del #362), presente en la 4.7.5 y corregido aguas arriba. Lo dispara su
deteccion de duplicados.

WProton lo detecta y **reintenta solo, sin buscar duplicados** — el archivo sale
algo mas grande y se crea. Si el segundo intento tambien falla, sugiere
actualizar `squashfs-tools` o empaquetar en DwarFS.

> **Por que a veces no reintentaba.** La deteccion buscaba en el registro
> ENTERO, que es acumulativo: un `Permission denied` de hace media hora -de
> montar un disco, de cualquier cosa- le hacia creer que el fallo era de
> permisos y se rendia sin reintentar. Ahora se mira solo lo que escribio ese
> intento, y el motivo detectado queda anotado en el registro.

---

## Salir con Select no funcionaba en los juegos de Linux - CORREGIDO (2)

Ademas de los dos fallos ya descritos, habia un tercero: el vigilante decidia si
el juego era de Linux mirando `WP_NATIVO`, **una variable que solo se asigna en
el camino de imagen**. En el camino de carpeta no existe, asi que creia que era
un juego de Windows y llamaba a `wine_matar_prefijo`, que ahi no cierra nada.

Ahora la decision no depende de esa variable: quien lanza deja escrita la
carpeta del juego en un fichero -mirando la extension del lanzador, que no
miente en ninguno de los dos caminos- y el vigilante cierra por carpeta si ese
fichero existe.

---

## La auditoria vigila los cuatro lanzadores (apartado 14)

Hay **cuatro** funciones que arrancan un juego —`launch_game`,
`launch_loose_exe`, `lanzar_script_si_existe` y `lanzar_nativo_suelto`— y cuatro
veces seguidas paso lo mismo: se arreglaba algo en unas y se olvidaba en otras.
El caso que colmo el vaso fue el vigilante de salida, que estaba en dos de las
cuatro: los juegos de Linux elegidos desde la lista iban por un tercer camino,
mantener Select no hacia nada y habia que cerrar con Alt+F4.

El apartado 14 comprueba una lista corta de cosas que **cualquiera que arranque
un juego** tiene que hacer:

| Obligatorio en | Funcion | Si falta |
|---|---|---|
| Los cuatro | `guardia_salida_start` | Mantener Select no cierra el juego por ese camino |
| Los cuatro | `stats_record` | El juego no cuenta como jugado: no sale como ultimo lanzado ni suma tiempo |
| Los cuatro | `load_profile` | `stats_record` escribe el perfil ENTERO desde memoria: sin cargarlo antes se borran todos los ajustes del juego |
| Los de Linux | `ejecutar_nativo` | No se pone el permiso, no se espera al juego ni se mete en su grupo |
| Los de Linux | `home_portable` | Se ignora la carpeta `.home` que traiga el juego |

**No se comparan todas las llamadas entre lanzadores**: seria ruido, porque los
dos pequeños no hacen nada de Wine a proposito. La lista crece cuando aparezca
otro caso.

Probado en negativo: al quitar el vigilante de un lanzador, la auditoria lo caza
con el motivo escrito.

---

## Un juego de Linux funciona en un equipo y en otro no

**Sintoma:** empaquetas un juego de Linux en un PC y en la Steam Deck no
arranca. En el registro:

```
./halo: error while loading shared libraries: libSDL3.so.0:
cannot open shared object file: No such file or directory
```

**Causa:** el `.wsquashfs` lleva el juego, pero **no las librerias del
sistema**. `libSDL3.so.0` esta en CachyOS y no en SteamOS. No es cosa de
WProton: le pasaria igual al juego lanzado a mano.

**Solucion: la carpeta `lib/` del juego.** Copia el `.so` que falte a una
carpeta `lib/` (o `lib64/`) **dentro** del juego y vuelve a empaquetarlo.
WProton la añade sola a `LD_LIBRARY_PATH` al lanzar, asi que el paquete pasa a
ser portatil de verdad.

Para saber de donde sacarla, en el equipo donde SI funciona:

```
ldd <el ejecutable del juego> | grep libSDL3
```

WProton detecta este error y lo dice con el nombre de la libreria y la ruta
exacta donde ponerla, en vez de dejar el mensaje perdido en el registro.

---

## MAKO y ReShade (Linux) no se pueden usar a la vez

Desde **MAKO Renderer v4.0.0** (28/09/2026), MAKO trae **su propio fork de
vkBasalt** y coloca sus capas por delante. ReShade (Linux) ES vkBasalt, asi que
las dos se pisan. El propio autor de MAKO lo dice: no combinar MAKO con otro
envoltorio Vulkan de generacion de fotogramas o escalado en el mismo juego.

Lo que se ve no es un error claro -artefactos, tirones o que el juego no
arranca-, y por registro es dificilisimo de atar. Asi que WProton lo corta
antes: al encender uno, si el otro esta puesto, avisa y ofrece apagarlo.

Si se cancela, no se toca nada.

> La descarga de MAKO no se ve afectada por la v4.0.0: el filtro sigue
> eligiendo `MAKO-Renderer-vX.Y.Z-linux.tar.xz` y descarta los nombres nuevos
> (`-flatpaks.tar.xz` en plural y el paquete de Arch `mako-renderer-bin`).

---

## Los .keys dejaron de cargarse en 1.76 - CORREGIDO

**Sintoma:** ningun mapeo de mando funciona, ni los que llevaban meses bien.
En el registro:

```
[+] Engranando mapeador para: Grand_Theft_Auto_Max_Pack.keys
Error al cargar .keys: Expecting value: line 1 column 1 (char 0)
```

**Causa:** al marcar de que juego es cada `.keys`, WProton escribia una linea
`# wproton-para: X` al principio del fichero. **Un `.keys` es JSON, y el JSON
no admite comentarios**: ese `#` lo invalidaba entero y el mapeador no podia
abrir ninguno.

**Arreglo:** la marca es ahora un campo mas DENTRO del JSON
(`"wproton_para": "..."`), y la leen y escriben `teclas.py`, que es el modulo
que entiende el formato. Tratarlo desde fuera fue justo lo que llevo al fallo.

**Los ficheros ya estropeados se reparan solos:** la primera vez que se lee uno
con esa linea, se le quita y vuelve a ser JSON valido. No hay que hacer nada.

> Habia ademas un segundo fallo en el mismo cambio: tras un `if orden; then ...
> fi`, el `$?` vale 0 -el resultado DEL IF-, no el de la condicion. Un `case $?`
> escrito despues no entraba en ninguna rama y la funcion terminaba sin
> devolver nada, asi que ningun `.keys` de `profiles/` se cargaba aunque
> estuviera perfecto.

---

## Un juego con prefijo incluido no encuentra sus guardados ni su DLC

**Sintoma:** el juego arranca perfectamente, pero no carga el DLC, o no ve las
partidas guardadas que el prefijo traia dentro. Ningun error en el registro.

**Causa:** el prefijo se empaqueto en un sistema donde Wine corre como **root**
-Batocera, por ejemplo-, asi que las cosas del usuario viven en
`drive_c/users/root`. Proton siempre trabaja como **`steamuser`**, y mira en
`drive_c/users/steamuser`, que esta vacio.

Caso real: un Dante's Inferno cuyos ficheros de DLC estaban en
`drive_c/users/root/Documents`. El juego iba bien y simplemente no habia DLC.

En el registro se reconoce por:

```
[+] Prefix incluido: se usa tal cual (no trae users/steamuser, ...)
```

**Arreglo:** WProton crea `users/steamuser` como enlace al usuario con el que se
empaqueto el prefijo. Las dos rutas llevan a los mismos ficheros, asi que da
igual con que nombre los busque el juego. El enlace es **relativo**, para que el
prefijo siga siendo portatil entre equipos.

Se descartan las carpetas que no son de un usuario real (`Public`,
`All Users`, `Default`), y si ya existe `steamuser` no se toca nada.

---

## El mismo juego va en carpeta y no va empaquetado — ARREGLO RETIRADO (regresion 18/10)

> **OJO: ESTE ARREGLO NO ESTA EN LA VERSION QUE SE ENTREGA.** Se saco en la
> regresion del 18/10 por la noche: algo del trabajo de ese dia sobre los
> prefijos hacia que muchos juegos no funcionaran, no se sabia cual, y se volvio
> a la 2.11 publicada en todo lo que toca prefijos. Lo de abajo sigue siendo
> cierto como diagnostico -el mecanismo esta medido- y es la especificacion de
> lo que hay que volver a meter, una pieza a la vez. Ver PENDIENTE-PREFIJOS.md.


**Caso real:** The Witcher 3 Wild Hunt Remastered, registro
`wproton_20261018_092305.log`. En carpeta con su prefijo, perfecto. El mismo
juego empaquetado en `.wsquashfs` con ese mismo prefijo dentro: arranca, pinta,
y se queda dando vueltas en la pantalla de carga.

**Causa (VERIFICADA en el registro): Proton no mira `WINEPREFIX`.** El prefijo
que usa sale de **`STEAM_COMPAT_DATA_PATH`**; umu-launcher solo copia ahí
`WINEPREFIX` *cuando esa variable viene vacía*, y si trae valor manda el valor.

En el mismo lanzamiento, a cuarenta líneas de distancia en el volcado del
entorno:

```
WINEPREFIX=/home/deck/WProton/prefixes/The_Witcher_3_Wild_Hunt_Remastered
STEAM_COMPAT_DATA_PATH=/home/deck/WProton/wsquashfs/tmp_mount/The_Witcher_3_...
```

Un `.wsquashfs` con prefijo dentro se prepara en dos tiempos: primero se apunta
la variable al montaje (correcto, el prefijo está ahí) y después se **saca** el
prefijo a disco, que cambia `WINEPREFIX`. Nadie volvía a tocar la variable del
primer paso, así que todo el arreglo del prefijo se hacía en `prefixes/<juego>`
y el juego arrancaba con el del montaje, al que le faltan las DLL del runner.

**Cómo se reconoce en el registro.** No hay ningún error nuestro. Lo que hay son
estas líneas, de Wine y por lo bajo, al preparar el prefijo:

```
Auto-start service L"MountMgr" failed to start: 2      (y PlugPlay, winebus, wineusb...)
wine: could not load kernel32.dll, status c0000135
proton_marcar_prefijo: sin centinela; system.reg=si kernel32=NO
[+] Prefijo: ya marcado como 'GE-Proton11-9' (al dia)
```

Sin `MountMgr` no hay unidades y sin `PlugPlay` no hay mando: el juego corre
sobre medio Windows. Y las dos últimas líneas dicen cada una lo contrario de la
otra.

**Por qué el prefijo llega sin `kernel32.dll`, que no es un fallo:** un prefijo
de Proton guarda medio `system32` como **enlaces absolutos al runner** del
equipo donde se hizo (1294 en el registro de un tester). Al empaquetar hay que
quitarlos, así que **todo** `.wsquashfs` con prefijo de Proton dentro nace
incompleto a propósito. Lo completa Proton en el equipo donde se juegue… si se
le deja.

**Arreglo (2.11), cuatro piezas:**

1. `STEAM_COMPAT_DATA_PATH` se **alinea** cada vez que el prefijo puede haber
   cambiado: con prefijo incluido se fija al prefijo, y con cualquier otro
   —propio, compartido, sacado del archivo— **se quita** y la deduce umu.
   Fijarla a mano en esos casos rompió un juego con prefijo compartido
   (`unable to use parent for game drive, path /home`).
2. Se **limpia al empezar cada lanzamiento**, también si viene heredada de
   Steam o de un juego anterior de la misma sesión.
3. Las tres marcas de «ya estoy listo» —`version`, `.update-timestamp` y
   `creation_sync_guard`— van juntas y con la misma regla: solo las lleva un
   prefijo que se sostiene solo (registro y `kernel32.dll`). Antes se quitaba
   el centinela pero no la `version`, y la `version` sola basta para que Proton
   no reponga nada.
4. Al **empaquetar**, si el prefijo sale incompleto, el archivo nace sin esas
   marcas. Si sale entero (los de Wine a secas) se quedan: quitárselas
   provocaría el `FileExistsError` de Grandia.

Y en el diagnóstico de antes de lanzar, `prefijo=` y `compatdata=` van ahora una
debajo de la otra, con aviso si no coinciden.

**Lo que se probó y NO era:**

- *El `wineboot` que falla con `could not load kernel32.dll`.* Es consecuencia,
  no causa: `wineboot` no repone ese fichero, no es suyo. Ya no se le llama
  sobre un prefijo a medias.
- *Que la carpeta del juego fuera de solo lectura.* No lo es: el montaje lleva
  `fuse-overlayfs` encima, con capa de escritura en
  `wsquashfs/overlays/<juego>/upper`.
- *Que `AppData` quedara enlazado al archivo y no se pudiera escribir.* El
  enlace existe —para no duplicar gigas— pero apunta al montaje **con**
  overlay, así que se escribe bien.
- *Que faltara el descodificador de H.264 para el vídeo de presentación.* El
  registro lo avisa, y conviene instalarlo (`gst-libav`), pero no es esto: en
  carpeta el juego iba perfecto en el mismo equipo y con el mismo aviso.

**No hace falta volver a empaquetar el juego:** el arreglo actúa al lanzar, así
que los `.wsquashfs` que ya estén hechos funcionan igual. Lo que cambia al
reempaquetar es que el archivo nuevo ya no lleva marcas que mientan.

---

## Un prefijo que funciona en carpeta deja de funcionar empaquetado — ARREGLO RETIRADO (regresion 18/10)

> **OJO: ESTE ARREGLO NO ESTA EN LA VERSION QUE SE ENTREGA.** Se saco en la
> regresion del 18/10 por la noche: algo del trabajo de ese dia sobre los
> prefijos hacia que muchos juegos no funcionaran, no se sabia cual, y se volvio
> a la 2.11 publicada en todo lo que toca prefijos. Lo de abajo sigue siendo
> cierto como diagnostico -el mecanismo esta medido- y es la especificacion de
> lo que hay que volver a meter, una pieza a la vez. Ver PENDIENTE-PREFIJOS.md.


**Síntoma, en palabras de Dani:** *«el juego funciona en modo carpeta con el
prefijo propio, pero cuando haces el wsquashfs con el prefijo propio que
funciona deja de funcionar»*.

**Causa (VERIFICADA, y es del empaquetado):** un prefijo de Proton tiene medio
Windows como **enlaces absolutos al runner**. Está en el código de Proton
(`pfx_copy` los hace absolutos a propósito cuando apuntan a
`lib/wine/x86_64-windows`). En el prefijo del Witcher eran **1278**, y el
empaquetado los borraba todos:

```
[+] Prefijo hecho portatil: 1278 enlace(s) al runner de este equipo quitados
```

El archivo salía con un Windows a medias, contando con que Proton lo
reconstruyera al abrirlo. El mismo prefijo, sin tocar, funcionaba en carpeta.

**Arreglo:** al empaquetar, un enlace que **lleva** a un fichero se sustituye
por **el fichero de verdad** (el archivo se lleva su Windows dentro); el que no
lleva a ningún sitio se quita, que es el que rompe `wineboot` con `error=80`.
Y al **lanzar** ya no se borran los enlaces que funcionan: apuntan al runner de
ese equipo, que es lo correcto, y borrarlos dejaba el prefijo a medias en cada
arranque.

**Por qué no ata el archivo a un runner:** una DLL de Wine copiada sigue siendo
una DLL de Wine —marca `Wine builtin DLL` en el byte `0x40`, que es lo que mira
`file_is_wine_builtin_dll`—, así que un Proton más nuevo la reconoce y la
sustituye por la suya al actualizar el prefijo.

**Y un aviso para quien toque la limpieza del empaquetado:** `tracked_files`
**no** se puede quitar del prefijo. `update_builtin_libs` lo abre con
`open(..., "r")` sin comprobar que exista, y se ejecuta justo cuando el prefijo
viene de otro equipo: sin el fichero, Proton muere con `FileNotFoundError`
antes de lanzar.

---

## The Witcher 3 Remastered desde un `.wsquashfs` — SIN RESOLVER (medido, 18/10/2026)

**Estado: hipótesis con datos, no verificada.** Lo que sí está verificado es
que las tres causas que se arreglaron antes (la versión del prefijo, el
`STEAM_COMPAT_DATA_PATH` y el `wineboot` inútil) ya no se dan: el registro del
18/10 a las 11:26 muestra la cadena nueva funcionando entera.

**Lo que dicen los registros, uno al lado del otro.** El mismo juego, el mismo
equipo, la misma sesión:

| | carpeta (10:57, «va perfecto») | archivo (11:26, «no va») |
|---|---|---|
| prefijo | `Upgrading prefix from None` | marcas quitadas → Proton lo completa |
| cadenas de intercambio | 4 | 4 |
| bloques de HDR | 2 | 2 |
| duración | 80 s, **cerrado a mano** | 98 s, **cerrado a mano** |

Son **idénticos línea por línea**. O sea que el registro no distinguía *«está
roto»* de *«está leyendo 60 GB comprimidos»*, y en los dos casos el juego se
cerró antes de llegar a ninguna parte.

**ACTUALIZACIÓN (misma tarde):** la causa apareció y era del empaquetado —los
1278 enlaces al runner que se borraban; está en la entrada de arriba—. Lo que
sigue valía mientras no se sabía, y el instrumento que se hizo para medirlo
sigue sirviendo.

**La hipótesis que quedaba entonces, y por qué era razonable:** un `.wsquashfs` con zstd se
descomprime en un solo hilo. 45 GB de juego leídos a través de FUSE, en una
Deck, son varias veces más lentos que la carpeta. 90 segundos pueden no dar ni
para la pantalla de presentación.

**Y el prefijo ya no es una incógnita:** desde la 2.11 WProton **prueba** el
prefijo antes de lanzar —ejecuta un programa de Windows dentro con la misma
cadena del juego, comprueba que Wine no se queje de los servicios y que no le
falten piezas del runner, y si hace falta lo repara— así que cuando el registro
dice `[+] Prefijo comprobado: Windows arranca dentro`, el prefijo está
**descartado con pruebas** y no por suposición. Si no arranca, lo dice antes de
lanzar y no se pierde el tiempo mirando el juego.

**Cómo se comprueba lo demás sin adivinar:** `diag_carga_juego` toma tres muestras
(20, 60 y 120 s) de lo que el montaje lee de verdad (`rchar` de squashfuse) y
del tiempo de CPU y el estado del proceso del juego, y escribe la conclusión en
el registro:

```
[carga] 20s de partida: leidos 612 MB del archivo (30 MB/s) | CPU del juego 94% | estado RS
[carga] ESTA CARGANDO del archivo. Si la pantalla sigue en negro, dale tiempo
```

Si dice **ESTA CARGANDO**, es lentitud del formato y la respuesta es el formato
**carpeta** para ese juego. Si dice **está PARADO**, entonces sí hay un fallo
que buscar, y ya se sabe que no es la velocidad.

**Lo que NO es:**

- *El prefijo.* Las tres causas de esa familia están cerradas, el registro del
  11:26 las muestra funcionando, y desde la 2.11 además se comprueba ejecutando
  algo dentro: si el registro dice que arranca, no es el prefijo.
- *`WARNING: Executable not found: C:\...` y `Proton: Executable is inside wine
  prefix`.* Aparecieron el 18/10 y parecen la causa, pero son consecuencia de
  que la conversión a ruta de Windows ahora **sí** se hace (antes `winepath`
  fallaba porque el prefijo estaba a medias). Lo único que Proton se salta por
  ahí es montar su unidad para el juego, y esa la crea WProton (`D:`).
- *El códec H.264.* El registro lo avisa en los dos casos, carpeta incluida.

---

## El juego arranca «recién instalado» (sin idioma ni partidas) — ARREGLO RETIRADO (regresion 18/10)

> **OJO: ESTE ARREGLO NO ESTA EN LA VERSION QUE SE ENTREGA.** Se saco en la
> regresion del 18/10 por la noche: algo del trabajo de ese dia sobre los
> prefijos hacia que muchos juegos no funcionaran, no se sabia cual, y se volvio
> a la 2.11 publicada en todo lo que toca prefijos. Lo de abajo sigue siendo
> cierto como diagnostico -el mecanismo esta medido- y es la especificacion de
> lo que hay que volver a meter, una pieza a la vez. Ver PENDIENTE-PREFIJOS.md.


**Síntoma:** el juego funciona, pero sale en inglés, con la configuración a
cero y sin las partidas que tenía. **Ningún error en el registro.**

**Causa:** un enlace del prefijo que ya no lleva a ningún sitio. El de siempre
es `drive_c/users/<nombre>/AppData`, que en un prefijo sacado de un
`.wsquashfs` apunta al montaje —a propósito, para no duplicar cientos de
megas— y se queda colgado en cuanto el juego se convierte a carpeta, se borra
el archivo o se lanza sin montar nada. Para el sistema ahí no hay ningún
fallo: hay un enlace, y punto.

Y había tres formas distintas de llegar al mismo sitio, las tres silenciosas:

1. **`find` no entra por un enlace.** Sin `-L`, ni siquiera cuando el enlace es
   el punto de partida: devuelve el enlace y no baja. Las dos funciones que
   enlazan el usuario del archivo al que espera el runner decidían con un
   `find … -type f`, así que veían `AppData` «vacía» y no enlazaban nada.
   Comprobado:

   ```
   find users/deck/AppData -type f      -> nada
   find -L users/deck/AppData -type f   -> los ficheros
   ```

2. **Al empaquetar se vaciaba.** `cp -a` copia los enlaces, no lo que hay
   detrás, y la limpieza previa vaciaba todos los que apuntaran fuera del
   prefijo: el archivo nuevo salía sin `AppData`.

3. **Un enlace colgado se daba por bueno.** `[ -e ]` sigue el enlace, así que
   decía «no existe»… pero para `ln -s` sí existe y falla con *File exists*.
   De ahí salían avisos de «no se pudo crear el enlace» sobre prefijos que ya
   lo tenían.

**Arreglo:** la comprobación de «hay ficheros» está en un solo sitio y va con
`-L` (`hay_ficheros`); al empaquetar, lo enlazado a la zona de WProton **se
trae dentro del archivo** y lo enlazado al equipo se vacía
(`prefijo_enlaces_fuera`, que además **mide** lo que va a traer para pedir
sitio, porque `du` tampoco sigue los enlaces); y antes de lanzar se recorren
todos, se escriben en el registro con su destino y los colgados se arreglan
—carpeta de verdad en el perfil del usuario, fuera en la raíz de `C:`—.

**Cómo se reconoce en el registro:**

```
enlaces del prefijo: drive_c/users/deck/AppData -> /...  [COLGADO]
enlaces del prefijo: 14 revisado(s), 1 colgado(s)
```

**Lo que NO era:** permisos (el montaje lleva `fuse-overlayfs` encima, con capa
de escritura), ni el usuario del prefijo (`steamuser` contra el del archivo),
que es un caso distinto y está documentado más arriba.

---

## El prefijo del archivo y las carpetas del usuario — ARREGLO RETIRADO (regresion 18/10)

> **OJO: ESTE ARREGLO NO ESTA EN LA VERSION QUE SE ENTREGA.** Se saco en la
> regresion del 18/10 por la noche: algo del trabajo de ese dia sobre los
> prefijos hacia que muchos juegos no funcionaran, no se sabia cual, y se volvio
> a la 2.11 publicada en todo lo que toca prefijos. Lo de abajo sigue siendo
> cierto como diagnostico -el mecanismo esta medido- y es la especificacion de
> lo que hay que volver a meter, una pieza a la vez. Ver PENDIENTE-PREFIJOS.md.


**El cierre de "en carpeta va y empaquetado no".** La causa estaba en lo que
Proton hace DESPUES, con el prefijo que le dejabamos.

**El mecanismo.** `fuse-overlayfs` no puede **renombrar** un directorio de la
capa inferior. Y `migrate_user_paths` de Proton, que corre en **cada**
lanzamiento, renombra carpetas del usuario:

```
drive_c/users/steamuser/Local Settings/Application Data
  - si es un DIRECTORIO de verdad -> merge_user_dir + os.rename(... " BACKUP")
  - si no existe                  -> os.symlink("../AppData/Local")
  - si es un enlace a otro sitio  -> os.remove + os.symlink
drive_c/users/steamuser/Application Data   -> "./AppData/Roaming"
drive_c/users/steamuser/My Documents       -> "./Documents"
```

`prefijo_incluido_a_disco` saca el prefijo del montaje **por este motivo** -lo
dice su propio comentario- y despues volvia a meter dentro del montaje
`AppData`, `Local Settings` y `Application Data`: las tres rutas que Proton
toca.

**Por que a uno le falla y al otro no.** Si en el prefijo de quien empaqueta
esas rutas ya eran **enlaces**, Proton no renombra nada y pasa de largo. Si en
el otro equipo son **directorios de verdad**, Proton intenta renombrarlos
dentro del archivo, el `os.rename` falla y muere antes de lanzar. Mismo
archivo, dos equipos, dos resultados — y de ahi que el registro de quien
empaqueto parezca normal.

**El arreglo.** El prefijo que sale del archivo tiene que ser **indistinguible
de uno hecho en ese equipo**. Dentro del montaje se queda solo lo que no cabe
copiar -el juego- y eso se decide **por tamaño** (256 MB,
`WP_PREFIJO_ENLACE_MIN_MB`), no por el nombre de la carpeta. Y al empaquetar se
normalizan esas rutas y se **revisa** el prefijo antes de comprimir; si algo no
cuadra, no se comprime.

**Lo que NO era, y se descarto con los registros delante:** el entorno (se
comparo var por var entre el lanzamiento en carpeta y el del archivo: solo
cambiaba `STEAM_COMPAT_INSTALL_PATH`), el `Proton: Error: unable to use parent
for game drive` (sale **tambien** en los lanzamientos en carpeta que funcionan),
y la version del archivo (el tester empaqueto de cero con la ultima).

**Como se vigila:** `prueba_prefijo.sh` apartados 32 y 33, y sobre todo
`prueba_quirurgico.py`, que lleva el `migrate_user_paths` de Proton **copiado de
su fuente** y lo ejecuta contra el prefijo preparado, con el montaje en solo
lectura de verdad. Si algun dia cambia esa funcion de Proton, esa prueba se
cambia **mirando su fuente**.

---

## Un archivo con prefijo que no va: lo PRIMERO que hay que mirar — PENDIENTE (regresion 18/10)

> **OJO: ESTE ARREGLO NO ESTA EN LA VERSION QUE SE ENTREGA.** Se saco en la
> regresion del 18/10 por la noche: algo del trabajo de ese dia sobre los
> prefijos hacia que muchos juegos no funcionaran, no se sabia cual, y se volvio
> a la 2.11 publicada en todo lo que toca prefijos. Lo de abajo sigue siendo
> cierto como diagnostico -el mecanismo esta medido- y es la especificacion de
> lo que hay que volver a meter, una pieza a la vez. Ver PENDIENTE-PREFIJOS.md.


**La pregunta, antes que cualquier teoria: ¿ese archivo se hizo con la 2.11 o
es de antes?** Un archivo empaquetado con prefijo por una version anterior al
18/10 lleva medio `system32` en enlaces a un runner que en otro equipo no
existe, y eso **no se arregla actualizando WProton**: hay que rehacer el
archivo. El 18/10 se fue una tarde en esto con The Witcher 3.

Desde la 2.11, al abrir un archivo con prefijo se dice solo:

```
[+] Este archivo lo hizo:
    WProton 2.11
    el 2026-10-18 17:40:12
    runner GE-Proton11-9
    el prefijo trae su Windows dentro [OK]
```

Y si no lo lleva:

```
[i] Este archivo no lleva marca: lo hizo una version anterior a la 2.11.
[!] EL PREFIJO DE ESTE ARCHIVO NO TRAE SU WINDOWS:
    system32 tiene 120 DLL de verdad y 400 enlace(s) colgado(s)
```

**Lo que se mira para decidirlo:** `drive_c/windows/system32` del prefijo del
archivo. Un `system32` de Proton pasa de **600** DLL; con menos de 200, o con
**un solo** enlace colgado, ese prefijo depende de un runner ajeno.

**Y si el archivo esta a medias, el juego deberia arrancar igual**: WProton
repone del runner de este equipo (`prefijo_asegurar`, DXVK y las DLL de Wine que
piden las de DirectX). Lo que no se puede es dar por bueno el archivo.

**Al revisar un registro de estos, en este orden:**

```
grep 'Este archivo lo hizo' -A4     con que version se hizo
grep 'NO TRAE SU WINDOWS'           si su system32 esta a medias
grep 'Windows del prefijo traido'   si al empaquetarlo se trajo el Windows
grep '\[carga\]'                    si estaba cargando o estaba parado
grep 'Prefijo comprobado'           si Windows arranca dentro del prefijo
grep 'a peticion del usuario'       si lo cerro una persona (¡no es un fallo!)
```

Esa ultima linea importa mas de lo que parece: en el registro del 18/10 a las
16:17 el juego **no se cayo**, lo cerro alguien con Select a los 40 s. Un
registro que acaba en `rc=0` a los 40 s puede ser un fallo o puede ser
impaciencia, y se escriben casi igual.

---

## HelixSR: lo que hay que saber antes de perseguir un fallo con el

No es un caso cerrado: es lo averiguado al integrarlo (18/10/2026, version
**1.9.3 experimental**), para no volver a investigarlo.

**Que es.** La red de DLSS (Model E) corriendo como shaders de computo de
Direct3D 12. Sustituye la DLL de FSR 3.1 **del juego** -
`amd_fidelityfx_upscaler_dx12.dll`, o `amd_fidelityfx_dx12.dll` en los juegos
que no traen la primera-, y la del juego se guarda como `*.original.dll`.

**Las tres condiciones. Si falla una, no hay nada que perseguir:**

1. **Direct3D 12.** En Vulkan y en D3D11 no existe. Se comprueba leyendo la
   tabla de importaciones del `.exe`.
2. **El juego tiene que traer FSR 3.1.** Si no, no hay DLL que sustituir. Para
   juegos con DLSS o XeSS hace falta el camino de OptiScaler / HelixSR Scaler.
3. **Dentro del juego hay que elegir «AMD FSR».** Es por donde entra. Con DLSS
   o XeSS seleccionado, HelixSR no recibe nada.

**GPUs:** RDNA 1 y posteriores. La **Deck (gfx1033, RDNA 2) entra**, y usa el
camino int8, unos 15% mas rapido. Vega es experimental y sin probar en hardware
real; Pascal (GTX 10) "deberia ir" y tampoco esta probado. Lo desarrollan y
prueban en una **BC-250 (gfx1013) con RADV**.

**La firma de que la red NO corrio:** en el juego se ve **un borde rojo y la
imagen temblando**. Eso NO es "no hace nada": es que la DLL esta y la red no.
Lo dice su `helixsr.log`, al lado de la DLL, y WProton lo saca al registro de
la sesion.

**Lo que no se puede repartir.** La descarga no trae la red: su instalador baja
la DLL de DLSS de NVIDIA, la construye en el equipo y borra la de NVIDIA. La
DLL resultante es para ese PC. Por eso WProton la **saca al empaquetar** a
`.wsquashfs` y la vuelve a poner al jugar. Si alguna vez aparece un
`amd_fidelityfx_*.dll` con la cadena `HelixSR` dentro de un archivo que se ha
repartido, eso es un fallo nuestro, no una opcion.

**Dos choques conocidos:**

- **OptiScaler junto al `.exe`** (en WProton, puesto como `dxgi.dll`): puede
  quedarse las llamadas de FSR del juego y dejar a HelixSR sin trabajo. Lo dice
  su propio README.
- **Su instalador y las bibliotecas de Steam**: desde la 1.7, al acabar de
  construir, busca juegos en `~/.steam` y `~/.local/share/Steam` y ofrece
  meterse en ellos. WProton lo ejecuta con un `$HOME` propio para que no
  encuentre ninguna.

**Y una leccion que vale para cualquier cosa que lea un `.exe`:** la tabla de
importaciones **normal no basta**. Muchisimos juegos piden `d3d12.dll` por la
tabla de **carga retardada** (delay-load) y, mirando solo la primera, parecen
de DirectX 11. Los descriptores antiguos de esa tabla guardan **direcciones**
(ImageBase + RVA) en vez de RVAs, y el bit que lo indica se ve mal en la
practica: en vez de fiarse del bit, WProton prueba las dos lecturas y se queda
la que cae dentro de una seccion de verdad.

**Lo que todavia NO esta hecho aqui:** el camino de **HelixSR Scaler /
OptiScaler**, que es el que da HelixSR en juegos con DLSS, XeSS o FSR 2 sin FSR
3.1. Hay base (`install_optiscaler`), pero son mas piezas: la DLL va duplicada
bajo los dos nombres de FSR en una subcarpeta, y hay que escribir
`Dx12Upscaler=fsr31`, `FfxDx12Path` y `FfxDx12SRPath` en `OptiScaler.ini` con
rutas de Windows (`Z:\...`).

---

## El cursor del juego sale como una X, y con el mando no sale — CORREGIDO (2.11)

**Síntoma**, tal como lo contó Dani (18/10/2026, registro
`wproton_20261018_131254.log`, sesión Wayland/KDE):

> «en este juego por defecto aparece la X y si mueves el ratón sale el cursor
> bien, pero con el mando no sale ese cursor»

Eran **dos** fallos distintos que se veían como uno.

**Causa 1 — el mando como ratón acortaba el escondido.** El vigilante del
puntero esconde el cursor cuando nadie lo mueve, y mira el mando: si llegan
eventos del mando, quien juega no está en el ratón, así que con **1 s** quieto
basta en vez de 3. Correcto… salvo cuando el stick **es** el ratón: entonces
esos eventos son la mano moviendo el puntero, y el cursor desaparecía justo
mientras se apunta. En el registro se veía literalmente:

```
[cursor] 1.0 s sin mover el raton (jugando con el mando): puntero escondido
```

**Causa 2 — `XUndefineCursor` no devuelve el cursor del juego.** En Wayland el
puntero lo dibuja el compositor, así que además de `XFixesHideCursor` se pone
un cursor **transparente** en la ventana bajo el puntero. Al destapar se
quitaba con `XUndefineCursor`, y eso **no** restaura el cursor que el juego
tenía: hace que la ventana vuelva a **heredar** el del padre, y subiendo la
jerarquía se llega a la ventana raíz, **cuyo cursor por omisión es la X**. De
ahí la X. Al mover el ratón el juego recibe movimiento, Wine le manda
`WM_SETCURSOR` y el juego repinta el suyo: por eso «con el ratón sale bien».

**Arreglo:**

1. Si el juego lleva el mando como ratón, sus eventos **ya no** acortan la
   espera. Se sabe por la variable `WP_RATON_MANDO` que pone el lanzador y por
   la marca `runtime/.raton_mando` que deja el mapeador — la marca hace falta
   porque el vigilante arranca **antes** que el mapeador, así que al leer el
   entorno todavía no hay nada que leer. Se consulta como máximo una vez por
   segundo.
2. Al destapar se le da al puntero **un empujón de un píxel y se devuelve** con
   `XWarpPointer`. El juego recibe movimiento y repinta su cursor; la X
   desaparece sin esperar a que nadie toque nada. Un píxel queda por debajo del
   umbral de 8 px con el que se decide «lo está moviendo alguien», así que el
   empujón no se cuenta como movimiento a sí mismo. Solo se hace si habíamos
   tapado nosotros. Se apaga con `WP_CURSOR_EMPUJON=0`.

En el informe del puntero al cerrar salen las dos cosas: si el mando hacía de
ratón y cuántos empujones se dieron.

**Lo que NO era:** el tema de cursores del sistema, ni el juego (pone su cursor
perfectamente; lo que fallaba era que nadie le pedía repintarlo), ni Wayland
por sí mismo.

---

## Herramientas de diagnóstico

| ajuste | para qué |
|---|---|
| `DIAG_DLL=1` | qué DLL carga el juego y si un override se aplicó de verdad |
| `DIAG_VIDEO=1` | `+file,+quartz,+winegstreamer`; al salir resume las cuatro causas de que no se vea un vídeo |
| `DIAG_CIERRE=1` | qué queda vivo al cerrar |

**Al leer un registro, mirar primero:**

```
grep -c 'Missing decoder'        falta un descodificador
grep -c 80040218                 VFW_E_CANNOT_RENDER
grep -c 'ProcessInput() failed'  el descodificador rechaza fotogramas
grep -c VideoFrameStep           el juego avanza fotograma a fotograma
grep -c winegstreamer            0 = ese runner usa winedmo/ffmpeg
grep 'module_open failed'        plugins de GStreamer que no cargan
```

Y si el juego se cae, **el volcado de excepción vale más que el registro**: su
tabla de módulos lista los `.so` de Linux que se cargaron, que es donde se ve
qué plugin falta. El registro normal solo muestra las DLL de Windows.
