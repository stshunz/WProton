# Compatibilidad — recetas verificadas y casos conocidos

Notas de juegos que han costado tiempo, con lo que **se comprobó de verdad** y
lo que no. El objetivo es no volver a recorrer el mismo camino dentro de seis
meses.

Cada entrada dice si la receta está **verificada** (funcionó y hay registro) o
es una **hipótesis** (razonable pero sin confirmar). La diferencia importa: en
este documento han acabado varias hipótesis que resultaron falsas, y están
anotadas a propósito para que nadie las repita.

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
