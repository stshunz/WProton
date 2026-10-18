# Manual de uso de WProton

Guía práctica para empezar y para resolver los problemas más habituales.
Si solo quieres jugar, con los tres primeros apartados tienes de sobra.

---
## 1. Primeros pasos

![El menú principal de WProton](img/menu-principal.png)

### Antes de empezar

**Hace falta conexión a internet para instalar.** WProton se descarga a sí
mismo: su propio Python, los menús, umu-launcher, un GE-Proton y Proton
Frankenstein. Son unos cuantos cientos de megas, así que conviene hacerlo con
wifi y sin prisa.

**Para jugar no hace falta.** Una vez instalado, los juegos que ya tengas
funcionan sin conexión. Sí la necesitan cosas concretas: descargar más
runners, buscar carátulas, consultar la base de umu y traer las fichas de los
juegos.

### Instalar

Copia `wproton.sh` a una carpeta (por ejemplo `~/WProton`), dale permisos y ejecútalo:

```bash
chmod +x wproton.sh
./wproton.sh --setup
```

O más sencillo: **doble clic en `wproton.sh`** desde el explorador de archivos. Las dos formas hacen exactamente lo mismo; con doble clic te ahorras abrir la terminal.

`--setup` descarga todo eso **dentro de su carpeta**. No instala nada en el
sistema ni pide contraseña, y para desinstalarlo basta con borrar la carpeta.

La primera vez tarda unos minutos, según tu conexión. Si se corta a medias,
vuelve a lanzar `--setup`: continúa desde donde estaba. Después, arranca con:

```bash
./wproton.sh
```

Al abrirlo por primera vez te preguntará **dónde tienes los juegos**, con dos opciones: usar la carpeta `games/` de WProton, o buscar otra (se abre el navegador y la eliges con el mando). Se puede cambiar después en *Biblioteca y preferencias → Carpeta de juegos*.

Los menús se abren **a pantalla completa**. Si prefieres verlos en ventana, pulsa **Select + A** (o **F11**) y quedará recordado.

### Añadir tu primer juego

![Paso 1 de 3: elegir Proton o Wine](img/asistente-runner.png)

![Paso 2 de 3: elegir el ejecutable del juego](img/asistente-ejecutable.png)

![Prefijo: compartido, propio del juego o el de TeknoParrot](img/asistente-prefijo.png)

![Paso 3 de 3: los ajustes básicos, con lo recomendado ya marcado](img/asistente-ajustes.png)

![Al terminar: el perfil creado, con su runner y su prefijo](img/asistente-final.png)


**Si ya tienes un juego empaquetado** (`.wsquashfs`, `.squashfs` o `.dwarfs`), no hay nada que preparar: **cópialo a tu carpeta de juegos —`games/` por defecto— y ya aparece en *Jugar***. También puedes abrirlo directamente desde el navegador de archivos o desde la línea de comandos:

```bash
./wproton.sh "Mi juego.wsquashfs"
```

Esos archivos son la forma en que WProton guarda los juegos: **un solo fichero comprimido** que se monta al vuelo, se juega en modo solo lectura y **guarda las partidas aparte**, sin modificarse nunca. Si te pasan uno hecho por otra persona, funciona igual.

**Si tienes otro formato**, WProton lo convierte por ti: menú principal → **Añadir un juego**, y se abre un navegador de archivos donde puedes elegir:

| Lo que tienes | Qué hace WProton |
|---|---|
| Un `.wsquashfs`, `.squashfs` o `.dwarfs` | Nada: se juega tal cual (basta con copiarlo a `games/`) |
| Un `.zip`, `.rar` o `.7z` | Lo descomprime y lo convierte en un archivo de juego |
| Un instalador de GOG (`setup_*.exe`) | Lo instala solo, sin ventanas, y lo empaqueta |
| Una **imagen de disco** (`.iso`, `.img`, `.mdf`, `.nrg`, `.udf`) | La abre, busca su `setup.exe` y te guía por la instalación (ver abajo) |
| Una carpeta con el juego ya instalado | Te deja probarlo y luego empaquetarlo |
| Un `.exe` suelto | Igual, tomando su carpeta como raíz |
| Un `.bat` o `.cmd` | Igual: algunos juegos arrancan con un script en vez de un ejecutable |

> Las carpetas que estén **dentro de tu carpeta de juegos** salen solas en la lista, sin tener que añadirlas: basta con que tengan un ejecutable, un `autorun.cmd`, un `drive_c` o que acaben en `.pc`.

> **Una carpeta puede ser una estantería y no un juego.** Si tienes una carpeta `Lucha` con *Street Fighter*, *Mortal Kombat* y *Guilty Gear* dentro, al darle se abre y te deja elegir cuál de los tres. Se reconoce porque **no tiene ningún fichero suyo** en el primer nivel, sólo carpetas (o `.wsquashfs`), y porque dentro hay **dos juegos o más**: un juego de verdad siempre tiene algo en su raíz, aunque el ejecutable esté tres niveles más abajo. La carátula y los textos sueltos no cuentan. Funciona igual al jugar que al abrir los ajustes con X.

> Empaquetar no es obligatorio: una carpeta o un `.exe` se pueden jugar tal cual, sin convertir nada. Empaquetar solo sirve para tenerlo todo en un fichero, que ocupa menos y es más cómodo de mover.

> **El nombre se limpia solo.** Una carpeta llamada `rune-the.last.guardian` o `Doom_Eternal_v1.2_[2020]-CPY` da un juego llamado `The Last Guardian` y `Doom Eternal`: se quita la etiqueta del grupo —esté delante o detrás—, la versión, el *build* y el año, y los puntos y guiones bajos pasan a espacios. Lo que escribiste tú no se toca: si el nombre ya lleva espacios o mayúsculas, se respeta tal cual, y `S.T.A.L.K.E.R.` no se desmonta. Ese nombre es el que se usa para el perfil, la carátula y el `.wsquashfs`, y puedes cambiarlo cuando te lo pregunte. En el registro queda apuntado (`nombre: 'rune-Halo' -> 'Halo'`).

Cuando el juego esté en una carpeta, aparece este menú:

- **Probar el juego (sin empaquetar)** — lánzalo para ver si funciona.
- **Configurar** — cambia el Proton, el prefijo u otras opciones y vuelve a probar.
- **Empaquetar a wsquashfs** — cuando funcione, comprímelo en un solo archivo.

Puedes probar y ajustar tantas veces como quieras antes de empaquetar. **La configuración que hagas durante las pruebas se conserva** en el juego final.

### Instalar un juego desde una ISO

Elige la imagen en **Añadir un juego** y WProton hace el camino completo.

1. **La monta, sin copiar nada y sin tocar el sistema.** Una ISO de DVD son 4-8 GB; montada se lee donde está, así que tarda cero y no ocupa espacio. La monta **WProton mismo**: trae su propio sistema de ficheros de solo lectura, que la deja **dentro de su carpeta** y no la registra como un disco — no aparece en Dolphin ni en ningún gestor de archivos, no crea dispositivos de loop y no hace falta instalar ni descargar nada. Lo único que usa del sistema es `fusermount`, que es quien tiene permiso para montar y que ya hace falta para los `.wsquashfs`. Entiende **ISO9660**, **Joliet** (los nombres largos de Windows) y **Rock Ridge**; lo que no entiende es UDF puro, que llevan algunos DVD modernos. Si tienes `fuseiso` instalado se prueba también, como segunda opinión. Y **solo si nada de eso funciona la extrae** al disco — primero con el lector de WProton, que tampoco necesita nada, y si no con 7-Zip, que sí lee UDF. Siempre de **solo lectura**: la imagen es tu original. Si hay que extraer, comprueba antes que hay sitio y te lo dice con los números.
2. **Busca el instalador preguntándoselo al disco**, en su `autorun.inf`, que es donde el disco dice qué ejecuta Windows al meterlo. Si no lo dice, busca `setup`, `install`, `instalar`, `autoplay` y `autorun`. **Si hay varios te pregunta cuál** — en muchos discos uno de ellos es el de DirectX.
3. **Crea un perfil solo para la instalación**, con prefijo propio, el disco en la unidad **D: declarada CD-ROM** (muchos instaladores la comprueban antes de empezar) y **el mando como ratón**: stick **derecho** mueve el puntero, **A** o **R2** hacen el clic izquierdo y **B** el derecho. El puntero va **más lento que en un juego** (450 px/s en vez de 900): aquí hay que acertar en un *Siguiente* de treinta píxeles, no mirar alrededor. Así se puede instalar en el modo Juego sin teclado ni ratón.
4. **Abre el instalador.** Acepta las rutas que te ofrezca (`C:\...`); si te pide el disco, está en `D:`.
5. **Te dice dónde ha quedado el juego**: mira *Program Files*, *Program Files (x86)*, *GOG Games* y la raíz de `C:` y te ofrece las carpetas, sin mezclar las de Windows. También puedes buscarla a mano.
6. **Le pone tu nombre y tu idioma al crack.** Lo que viene en la carpeta `Crack` de la imagen es un emulador de la API de Steam con su configuración al lado, y ahí está escrito el nombre del jugador —el del grupo que hizo el release— y el idioma. Sin tocarlo, el juego arranca saludando a *RUNE* y en inglés. WProton busca esa configuración **por el contenido y no por el nombre del fichero** (cada emulador llama al suyo de una forma: `steam_emu.ini`, `ALI213.ini`, `SteamConfig.ini`, `OnlineFix.ini`…) y cambia `UserName`/`PlayerName` por el usuario de tu equipo y `Language` por tu idioma. Goldberg es la excepción: no usa un `.ini` sino un fichero por ajuste en `steam_settings/`, y esos se buscan por nombre. **Guarda copia de cada original** (`*.wproton.bak`), respeta los finales de línea de Windows y **no toca** un `Language=3` —hay emuladores que guardan ahí un número de su propia tabla—. Si la imagen trae el crack y el juego instalado no lo tiene, te ofrece copiarlo encima; eso sí se pregunta, porque sobrescribe ficheros del juego. Se puede repetir después desde *Ajustes del juego → Casos especiales → Nombre e idioma del juego instalado*, mientras el juego siga siendo una carpeta.
7. **Y pregunta cómo empaquetar:**

| Opción | Para qué |
|---|---|
| **Con el prefijo Y el juego** | Archivo autosuficiente: lleva dentro lo que el instalador dejó en Windows (DirectX, VC++, el registro). Funciona en otro equipo sin instalar nada; ocupa más |
| **Solo el juego** | Solo su carpeta. Se saca del prefijo antes de comprimir |
| **Nada por ahora** | Se queda en su prefijo; lo empaquetas cuando quieras desde *Ajustes del juego → Empaquetar con su prefijo* |

Al terminar, si la imagen estaba **montada** se desmonta sola —insistiendo y, si hace falta, forzando: hay instaladores que dejan algún fichero abierto un rato después de terminar—. Si WProton no llegara a cerrarla (un corte, un cierre a lo bruto), **la cierra en el siguiente arranque**; si hubo que **extraerla**, se ofrece borrar lo extraído, que son varios GB. **La imagen original no se toca nunca**, y si la instalación se quedó a medias puedes decir que no y repetirla sin volver a abrirla.

> Un `.bin` de GOG (`setup-juego-1.bin`) **no** se trata como imagen: esos los recompone el propio instalador de GOG. Lo mismo con un `.cue`, que es el índice y no la imagen — usa el `.iso`.

### Prefijos que vienen de Batocera

Batocera **corre como root**, así que un prefijo hecho allí guarda los datos
del juego en `drive_c/users/root/`. En un PC normal, Proton usa `steamuser` y
Wine usa tu nombre: el juego mira ahí, no encuentra nada y arranca como recién
instalado (sin idioma, sin configuración).

WProton lo enlaza solo al preparar el prefijo. Si tu `steamuser` ya tiene
ficheros propios, no toca nada y avisa, para no mezclar partidas.

También puede pasar que la superposición **tape** carpetas: Wine borra y
rehace las de usuario, y a partir de ahí lo que trae el archivo deja de verse.
Las de usuario se destapan solas; para el resto hay *Gestión de archivos →
Reparar carpetas tapadas*.

### Jugar

Menú principal → **Jugar**. Ahí salen todos los juegos de tu carpeta de juegos, ya sean archivos empaquetados o carpetas. Elige uno con el mando y pulsa **A**.

> ¿Dónde está esa carpeta? La primera vez que abres WProton te pregunta dónde tienes los juegos. Si no eliges ninguna, usa `games/`, dentro de la propia carpeta de WProton. Puedes cambiarla cuando quieras en *Biblioteca y preferencias → Carpeta de juegos*.

La primera vez que lances un juego, un asistente te preguntará tres cosas: qué Proton usar, cuál es el ejecutable y unas opciones básicas. Si no sabes qué contestar, acepta lo que viene marcado: funciona en la mayoría de casos.

---

## 2. Manejo con el mando

| Botón | Qué hace |
|---|---|
| Cruceta o stick | Moverse |
| **Izquierda / derecha** | Saltar una pantalla entera (en la lista) |
| **A** | Elegir |
| **B** | Volver atrás un nivel |
| **Select** | Volver al menú principal desde donde estés (y ahí, salir) |
| **X** | Configurar el juego resaltado (en la lista de juegos) |
| **Y** | Buscar |
| **Select + A** | Pantalla completa / ventana |
| **Select + X** | Cambiar de vista: lista → vertical → panorámica → 4:3 |
| **X** sobre *Jugar al último* | Configurar ese juego sin abrir la lista |
| **Select** (5 s) | (con un juego abierto) Cerrarlo y volver al menú |
| **Select + Y** | (con un juego abierto) Recuperar el foco si se ha ido detrás |

Con bibliotecas grandes, **izquierda y derecha** saltan una pantalla completa en
vez de ir de uno en uno, y el puntero se queda en la misma fila para no perder
el hilo.

**Select** vuelve al menú principal esté donde esté, sin tener que ir dando
atrás con **B** menú por menú. Y estando ya en el principal, **cierra WProton**
(preguntando antes). Es una pulsación corta: mantenerlo sigue siendo lo que
cierra un juego.

**Buscar entre muchos juegos**: pulsa **Y** y aparece un teclado en pantalla; o, si tienes teclado, empieza a escribir directamente. Se filtran los juegos cuyo nombre *empiece* por lo que escribas.

Ese mismo teclado en pantalla se usa para escribir argumentos, notas o cualquier otro texto, así que no hace falta teclado físico para nada.

---

![La biblioteca de WProton: lista de juegos con la carátula, la ficha y la sinopsis del seleccionado](img/biblioteca-ficha.jpg)

## 3. Ajustes de un juego

Desde la lista de juegos, ponte encima de uno y pulsa **X** (o entra en *Ajustes de un juego*).

![Pantalla de ajustes de un juego: arriba lo del día a día, abajo los submenús](img/ajustes-juego.png)

Arriba está lo del día a día. Lo que casi nunca se toca vive en dos submenús: **Rendimiento y compatibilidad** (MangoHud, Fsync, DXVK, FSR, gamescope…) y **Herramientas del prefijo** (winecfg, winetricks, dgVoodoo2, OptiScaler).

Lo más útil:

**Ejecutable** — qué se lanza. **Lo que elijas aquí es lo que arranca**: si ese fichero no está, WProton avisa y no arranca ningún otro, porque jugar a algo distinto de lo que elegiste es peor que no jugar. Déjalo en «automático» si prefieres que decida él.

Si el juego arranca con un `.bat`, elígelo igual: WProton lo **lee** y hace lo que dice —abrir el ejecutable que menciona, con sus argumentos— en vez de ejecutarlo. Si el `.bat` instala algo (copia ficheros, toca el registro), eso se hace una sola vez y después se abre el juego directamente. Lo mismo con los lanzadores `.ahk` de AutoHotkey, habituales en los recopilatorios: se leen y se traducen a ajustes del perfil.

**Runner (Proton/Wine)** — con qué se ejecuta. Si un juego no arranca, esto es lo primero que conviene cambiar: prueba otro GE-Proton o una versión más antigua.

**Casos especiales** — lo que solo necesita algún juego raro. La fila resume lo que tengas puesto:

- **Unidades de Windows**: darle al juego una letra propia (`D:`, `E:`…), para los que buscan sus datos en una ruta corta.
- **El juego debe estar en `C:\`**: para los que miran `C:\<carpeta>\...` con la ruta escrita a fuego. La carpeta se enlaza dentro de `C:`, no se copia.
- **Ejecutable acompañante**: un programa que se abre antes del juego y se cierra con él.
- **Versión de Windows**: de 98 a 11. Algunos juegos viejos se niegan a arrancar en «Windows 10»; algunos modernos no arrancan en XP.
- **Escritorio virtual**: encierra el juego en una ventana con su propio escritorio, para los que cambian la resolución y dejan la pantalla rota.
- **OpenGL por Vulkan (Zink)**: para juegos OpenGL antiguos cuyos shaders el driver normal no consigue compilar.

Nada de esto añade ajustes nuevos al perfil: se guarda con los que ya había.

**Argumentos** — parámetros que necesita el juego, por ejemplo `-novr` o `-windowed`.

**Prefijo** — dónde se guarda la "instalación de Windows" del juego:
- *Compartido*: todos los juegos usan el mismo. Ocupa menos y va bien casi siempre.
- *Propio del juego*: uno exclusivo. Útil si un juego necesita librerías que estorban a otros.
- *Incluido en el archivo*: si el juego trae el suyo (estilo Batocera).

**Idioma del juego** — se elige de una lista y viene en **español** de fábrica.
Muchos juegos miran el idioma del sistema para decidir en cuál arrancan. Si
tu sistema no tiene ese idioma generado, WProton te avisa: Wine suele
apañarse igual, pero si el juego sigue saliendo en inglés esa es la razón más
probable.

**DLL overrides** — para los juegos que necesitan cargar una DLL propia en vez
de la de Wine: dgVoodoo2, ReShade, OptiScaler, cargadores de mods como BepInEx.
Ya no hace falta escribir la cadena a mano:

- *Elegir de una lista* — las cinco habituales (`dinput8`, `d3d9`, `dxgi`,
  `winhttp`, `winmm`) y las que ya tengas puestas, marcadas.
- *Buscar las DLL que hay en el juego* — mira junto al ejecutable. Si alguien
  dejó ahí un `dinput8.dll`, es porque quiere que se cargue.
- *Escribir a mano* y *Quitar todos*, que avisa de lo que se lleva por delante.

Lo que ya tuvieras puesto **nunca se pierde**: la lista muestra la unión de lo
tuyo y lo que se ofrece, con tus valores intactos.

> ¿Se está aplicando de verdad? Pon `DIAG_DLL=1` en `settings.conf`, juega un
> minuto y mira el registro: dirá si cada DLL se cargó la nativa o la de Wine.
> Déjalo apagado el resto del tiempo, que habla muchísimo.

**HDR** — en *Rendimiento y compatibilidad*. Pone las variables que hacen falta
y se lo pide a gamescope. La propia fila del menú te dice si va a poder verse:
si no hay gamescope ni sesión Wayland, no hay HDR por mucho que lo enciendas.
El monitor también tiene que serlo, y el juego traerlo.

**Mando vía SDL** — en automático. Se activa solo con mandos que lo necesitan (DualSense, DualShock, mandos de Nintendo) y se queda apagado con mandos XInput como los de la Steam Deck o la Legion Go.

**Buscar en la base de umu** — consulta la base de datos de
[umu](https://github.com/Open-Wine-Components/umu-database) y, si encuentra el
juego, pone el identificador que necesita protonfixes para aplicarle sus
arreglos. Al añadir un juego nuevo lo propone solo.

**Carátula** — hay tres formas: descargarlas todas de golpe desde *Carátulas y
perfiles*, **buscar la de ese juego por nombre** (si el fichero se llama de
forma rara y la búsqueda automática falla), o elegir una imagen de tu disco. Hay
dos, y cada una vive en su carpeta con el nombre del juego:

| Carpeta | Para qué |
|---|---|
| `covers/` | Vertical (2:3), para la lista y la rejilla clásica |
| `covers_wide/` | Panorámica, tipo cabecera de Steam |
| `covers_43/` | Cuadrada 4:3 (640x480) |
| `metadata/` | Ficha del juego y duración (no son imágenes) |

Cada vista usa su carpeta, y en la vista de lista puedes elegir cuál se
enseña en el panel (*Biblioteca y preferencias → Carátula en la vista de
lista*). Si un juego no tiene la de esa forma, se usa la vertical. Las
imágenes nunca se deforman: se centran en su casilla.

Si ya tienes una colección de carátulas, cópiala en la carpeta que
corresponda: los ficheros se llaman igual que el juego, con espacios o con
guiones bajos — las dos formas valen.

![Carátulas y perfiles de la comunidad](img/caratulas-comunidad.png)

### Las 4:3 las pone WProton

![Carátula y ficha de un juego: la 4:3 se baja del repositorio](img/caratula-y-ficha.png)

Las carátulas **4:3** no se buscan en ningún sitio: salen de la carpeta
`covers_43/` del repositorio de WProton, recortadas a 640x480 una por una. Por
eso son la forma que viene puesta de serie.

No hay que pedirlas: **la primera vez que cargas un juego**, WProton mira si el
repositorio tiene una con su nombre y la baja. Si ya tenías una 4:3 ahí puesta
—a mano o de antes— no se toca.

El nombre del fichero del repositorio y el de tu juego no tienen que coincidir
exactamente: se comparan sin mayúsculas ni separadores, y se admite la coletilla
de versión o de grupo que traen las descargas. Así `covers_43/Rave Racer.jpg`
vale para un `Rave_Racer.wsquashfs`, y `Mina.the.Hollower.v1.0.2` encuentra la de
*Mina the Hollower*. La carátula se guarda con **el nombre de tu juego**, no con
el del repositorio: si se guardara con el de allá, no la encontraría nadie.

También se puede pedir a mano, cuando el repositorio acaba de añadir la de tu
juego: *Ajustes del juego → Carátula y ficha → **Carátula 4:3: descargarla del
repositorio de WProton***. Esa opción consulta la lista recién traída, sin
esperar a que caduque la del día, y avisa si todavía no hay ninguna.

**Y se pueden traer todas de golpe.** En *Biblioteca y preferencias → Traer
todas las carátulas del repositorio* se baja la colección entera, no solo las de
los juegos que tienes ahora: así, cuando añadas uno nuevo, su carátula ya estará
puesta y no hay que descargar nada más. Antes de empezar dice cuántas son y
cuánto ocupan, y no hace falta ninguna clave.

Las que se bajan así se guardan con el nombre que tienen en el repositorio. Si
alguno de tus juegos se llama distinto —`Halo_Combat_Evolved` frente a
`Halo.Combat.Evolved.png`— WProton deja además una copia con **tu** nombre, para
que se vea en la biblioteca sin tener que renombrar nada a mano.

Si te falta la de algún juego, puedes proponerla: un `png` o `jpg` a 640x480 en
la carpeta `covers_43/` del repositorio, con el nombre del juego.

> Para las descargas de SteamGridDB —las **verticales** y las
> **panorámicas**— hace falta una clave gratuita
> (steamgriddb.com → Profile → Preferences → API). En vez de teclearla con el
> mando, puedes pegarla en un fichero de texto y dejarlo junto a `wproton.sh`:
> WProton la recoge, la guarda a buen recaudo y borra el fichero.
>
> Para las 4:3 **no hace falta clave ninguna**: si solo pides esas, WProton ya
> no te la pregunta.

**Descargar datos de los juegos** (en *Biblioteca y preferencias*) hace lo
mismo con la información: baja de una vez la **ficha de Steam** (año, género,
nota, descripción) y la **duración de HowLongToBeat** de todos los juegos que
no la tengan. Antes solo se conseguían de uno en uno, entrando en la ficha de
cada juego.

El panel de la derecha enseña la carátula, la ficha y la sinopsis:

![La ficha de un juego: carátula, año, desarrollo, género, nota, duración y sinopsis](img/biblioteca-lista.jpg)

### La nota, y los juegos que no están en Steam

La **nota** que trae Steam es la de Metacritic, y solo la incluye si el juego
la tiene en su ficha: los juegos viejos casi nunca. Y un juego que no esté en
Steam se queda sin ficha ninguna.

Para esos dos casos se puede poner una **clave de RAWG** (*Biblioteca y
preferencias → Clave de RAWG*). Es gratuita y **opcional**: sin ella todo
funciona igual, solo con los datos de Steam.

RAWG es siempre la fuente **secundaria**: se consulta después de Steam y solo
rellena lo que falte, porque la ficha de Steam trae la sinopsis en español y
datos más completos. Cada fuente guarda su propio fichero, así que se sabe
siempre de dónde vino cada dato.

> Metacritic no tiene API propia. Lo que se anuncia como tal son raspadores de
> su web (que se rompen cuando cambian la página) o servicios de pago. RAWG
> publica esa nota en su API, que es estable y legal. Los datos son suyos y
> hay que citarlos como fuente.

Se puede pedir solo una de las dos. No se vuelve a descargar lo que ya está,
así que se puede repetir cuando añadas juegos nuevos. Los que no aparezcan
suelen tener el nombre del archivo muy distinto al del juego: se arregla
renombrando el `.wsquashfs`.

**Importar un fichero `.reg`** (en *Herramientas del prefijo*) — mete claves en
el registro del prefijo. El uso más común es cambiar el idioma de un juego que
lo guarda ahí y no en un menú. Antes de aplicarlo te enseña qué lleva dentro, y
**guarda una copia del registro** en `wp_registro_<fecha>/` dentro del prefijo,
porque una vez importado no hay deshacer.

> **Runners y herramientas** tenía diecinueve filas y mezclaba lo que se usa a
> diario con lo que se instala una vez. Lo segundo está ahora en *Instalar y
> actualizar componentes >>*: umu-launcher, Python portable, evdev, los
> extractores de GOG, las herramientas FUSE y DwarFS, y los datos de
> HowLongToBeat.
>
> *Instalar librerías de Windows* se queda fuera: eso no instala un componente
> de WProton, mete `vcredist` y compañía en el prefijo de un juego, se hace por
> juego y se repite. También se llega desde *Ajustes del juego*, pero desde
> aquí puedes elegir el prefijo, que es lo que hace falta cuando es compartido.

**Elegir versión de GE-Proton** — en *Runners y herramientas → Descargar
runners → GE-Proton*.

GE-Proton lleva cientos de versiones publicadas, y pedirlas todas eran tres
consultas a GitHub cada vez que entrabas. Al entrar salen ahora **las series**:

```
Serie 11.x
Serie 10.x
Serie 9.x
Serie 8.x
Serie 7.x
Serie 6.x
```

y al elegir una **se cargan solo las suyas**, enteras. Para las series nuevas es
una consulta en vez de tres, y la lista que sale es corta.

La lista de series se construye sola con lo que haya publicado, así que el día
que salga la 12 aparece sin tocar nada.

Lo consultado se guarda unas horas, así que entrar por segunda vez es
instantáneo. Si GitHub no responde, se usa lo guardado y se avisa en el
registro: una lista de hace un rato deja elegir, una lista vacía te deja sin
poder bajar nada.

**Elegir versión de Wine de Kron4ek** — mismo sitio, entrada *Wine Kron4ek*.

Tres pasos, y cada lista es corta:

1. **La serie**: 11.x, 10.x, 9.x… igual que en GE-Proton.
2. **La variante**, dentro de esa serie. Las filas van solo con el nombre y la
   explicación arriba, en la cabecera: el menú usa una fuente proporcional, así
   que rellenar con espacios no alinea nada y se veía el escalón.

   | Variante | Qué es |
   |---|---|
   | `wow64` | Vanilla, **no necesita librerías de 32 bits**. La que quieres en SteamOS |
   | `staging-tkg-wow64` | Staging más los parches de wine-tkg |
   | `staging-wow64` | Staging |
   | `amd64`, `staging-amd64`, `staging-tkg-amd64` | Lo mismo, pero necesitan multilib |
   | `x86`, `staging-x86`, `staging-tkg-x86` | Solo para sistemas de 32 bits |
   | `Wine Proton` | El de Valve. Son publicaciones aparte, con su propia numeración |

3. **La versión** concreta, y el paquete se localiza solo.

Antes había que elegir entre las 12 últimas versiones y luego leerse los doce
nombres de fichero de la publicación (`wine-11.13-staging-tkg-amd64-wow64.tar.xz`)
para dar con el que querías. Y de la serie 9 o la 8 no había forma de bajar
nada. Si una versión antigua no trae la variante que has pedido, se te dice y
se te enseña lo que sí trae, en vez de instalarte otra.

**Tener los tres al día** — *Runners y herramientas → Actualizar a la última
versión >>*. Cada fila dice qué versión tienes ya instalada:

```
GE-Proton    (el runner por defecto)   [GE-Proton11-6]
Wine         (Kron4ek staging wow64)   [wine-11.13-staging-amd64-wow64]
UMU-Proton   (Open Wine Components)    [no instalado]
```

Solo se descarga si hay una más nueva que la que tienes.

Del Wine se coge `staging-amd64-wow64` a propósito: staging trae más arreglos
que el vanilla, y wow64 **no necesita librerías de 32 bits**, que es justo lo
que no se puede instalar en una SteamOS inmutable. Si quieres otra variante,
están todas en *Descargar runners → Wine Kron4ek*.

### Juegos de Linux sueltos (.sh y .AppImage)

Un `.sh` o un `.AppImage` dejado **en la raíz de la carpeta de juegos** aparece
en la biblioteca como cualquier otro juego, sin empaquetar ni nada.

Solo se miran en el **primer nivel**, a propósito: casi todos los juegos traen
sus propios `.sh` por dentro (`start.sh`, `setup.sh`, el lanzador de una carpeta
que ya sale como juego). Si se buscaran en profundidad, un solo juego llenaría
la lista de entradas que no son juegos. En la raíz, en cambio, lo que hay
puesto lo has puesto tú a propósito.

### Manejar los menús con el ratón

Además del mando y el teclado, los menús responden al ratón:

| Acción | Qué hace |
|---|---|
| Mover el puntero | Selecciona la fila que hay debajo |
| Clic izquierdo | Entra en esa fila (como A o Intro) |
| Clic derecho | En la lista de juegos, abre los **ajustes de ese juego**; en el resto, vuelve atrás |
| Rueda | Sube y baja **media pantalla** por golpe |
| Flechas de la barra lateral | Desplazan media pantalla; solo salen si la lista no cabe |

El puntero es **morado**, del color de la marca, con un borde oscuro para que se
lea también sobre una carátula clara. El puntero blanco del sistema se perdía en
estos fondos, y además cambia de un equipo a otro.

El clic derecho selecciona antes la fila que hay debajo: abrir los ajustes de un
juego que no es el que señalas sería peor que no hacer nada.

La rueda mueve media pantalla porque con tres filas por golpe una lista de
cincuenta juegos son diecisiete vueltas, y entonces no compensa frente a la
búsqueda.

Cuando la lista no cabe en pantalla aparecen **flechas arriba y abajo** en los
extremos de la barra lateral. Se apagan en gris cuando ya no hay más por ese
lado. Su zona de clic es más ancha que el dibujo —acertar un triángulo de diez
píxeles con el puntero es incómodo— pero nunca invade la lista, para que los
últimos píxeles de una fila no desplacen en vez de elegir el juego.

**En pantallas de mucha resolución la letra sube sola.** Los tamaños van en píxeles, y un píxel de un 4K mide la cuarta parte que uno de un 1080p: la misma letra se ve diminuta. WProton mide la ventana y sube la letra en la misma proporción —1080p igual, 1440p un tercio más, 4K el doble—, y el resto del diseño sube con ella. Solo sube, nunca baja, y multiplica el tamaño que hayas elegido, así que *grande* sigue siendo más grande que *normal*. Se mira la ventana y no el escritorio a propósito: con gamescope dibujando a 1280x800 para un televisor 4K, del agrandado ya se encarga él, y hacerlo dos veces daría letras gigantes. Se apaga en *Preferencias → Tamaño de la letra → **Subir sola en pantallas 4K***, o con `MENU_AUTO_ESCALA=0`.

**El puntero se esconde solo** tras unos segundos quieto y vuelve al primer
movimiento: en una Deck sin ratón un puntero plantado en medio sobra, y con
ratón verlo encima del menú mientras juegas con el mando también.

Pasar el puntero por el **panel lateral** —la ficha del juego, la carátula— no
cambia la selección; solo cuenta la zona de la lista.

Se apaga con `RATON_MENUS=0` en `settings.conf`.

> Por dentro, el ratón **no reescribe la navegación**: mueve la selección e
> inyecta la misma tecla que pulsarías tú. Así no puede desincronizarse del
> mando, y cualquier arreglo en la selección vale para los tres a la vez.

### Juegos de Linux dentro de un `.wsquashfs`

Un `.sh` o un `.AppImage` empaquetado dentro de un `.wsquashfs` se detecta y se
lanza como juego de Linux, sin Wine de por medio.

> **El AppImage no necesita venir con permiso de ejecución.** Antes se buscaba
> «cualquier ejecutable ELF», y un AppImage lo es… pero solo si tiene el bit de
> ejecución puesto, y recién descargado no suele tenerlo. Squashfs conserva los
> permisos tal cual estaban al empaquetar, así que dentro del archivo seguía sin
> tenerlo y el juego no aparecía. Ahora se busca por extensión y el permiso se
> arregla al lanzar, aprovechando la capa de escritura del montaje.
>
> Si aun así no se puede poner (un archivo de solo lectura de verdad), se dice
> claramente en vez de intentar `bash` sobre un binario, que es lo que hacía una
> de las ramas y solo escupía basura.

![Archivo y mantenimiento: lo que se toca de uvas a peras](img/archivo-mantenimiento.png)

### Un juego puede traer su propia carpeta personal (`.home`)

WProton busca una carpeta personal dentro del juego, **en este orden**:

| Se busca | Ejemplo |
|---|---|
| `<lanzador>.home` junto al ejecutable | `Xemu.AppImage.home` |
| `<lanzador sin extensión>.home` | `Xemu.home` |
| **Cualquier `*.home` que haya al lado** | el `.sh` se llama distinto que el AppImage |
| `.home` en la raíz del juego | `.home` |
| Si no hay ninguna, la de siempre | `prefixes/<juego>.home` |

La tercera regla es la que resuelve el caso real: el lanzador que se detecta
suele ser un `.sh` que por dentro llama a otra cosa con parámetros —
`Crazy Taxi 3 High Roller.sh` ejecutando `Xemu.AppImage -dvd_path …`— y la
carpeta personal lleva el nombre **del AppImage**, no el del `.sh`.

Si hay **varias** `*.home`, se prefiere la que tenga su fichero al lado
(`Xemu.AppImage.home` con `Xemu.AppImage` presente). Si aún así queda más de
una, no se adivina: se anota en el registro y se usa la carpeta de siempre.
Elegir a boleo dónde va a guardar el juego sus partidas es la clase de acierto
que sale caro.

Las dos primeras son el **convenio de AppImage**: un AppImage busca por su cuenta
una carpeta llamada igual que él con `.home` detrás, y la usa como carpeta
personal. Si el paquete la trae, dentro está el juego ya configurado.

> **Solo cuentan las que acaban en `.home`.** Al lado del lanzador hay muchas
> otras carpetas —`Super Mario Remastered_Data` de Unity, `lib`, `share`— y
> ninguna es una carpeta personal. Aceptar cualquier carpeta con el nombre del
> juego sería meter al juego a escribir dentro de sus propios datos. Sirve
para empaquetar un juego **ya configurado**: ajustes hechos, mandos mapeados,
resolución puesta, y arranca bien a la primera.

Manda sobre todo lo demás: si está ahí, es que quien empaquetó el juego la puso
a propósito, y crear otra al lado sería tirar ese trabajo. En el registro se
distingue cuál se está usando:

```
[+] Carpeta del juego: /…/tmp_mount/MiJuego/.home
    La trae el propio juego (.home): se usa esa, con lo que
    venga configurado, en vez de crear una vacia.
```

Funciona aunque el `.wsquashfs` sea de solo lectura: el juego se monta con una
capa de escritura encima, así que lo que escriba en su `.home` se conserva en
`overlays/<juego>/upper`.

Vale tanto para juegos de Linux (`.sh`, `.AppImage`) como para los de Windows.

### Borrar la caché de shaders de un juego

*Ajustes del juego → Rendimiento y compatibilidad → **Borrar la caché de shaders
de este juego***.

La caché de DXVK se va llenando mientras juegas y hace que los tirones del
principio desaparezcan. Pero si se corrompe —un cierre brusco, un cambio de
runner, un driver nuevo— el juego puede petar al arrancar, quedarse en negro o
dar tirones que no se van. Borrarla obliga a regenerarla desde cero.

Borra solo la de **ese** juego (`<ejecutable>.dxvk-cache` y su equivalente de
VKD3D), porque WProton junta todas las cachés en `cache/dxvk` y `cache/vkd3d` en
vez de dejarlas sueltas por los prefijos. Después ofrece borrar también la del
**driver (Mesa)**, que no se puede separar por juego: o entera o nada, y afecta
a todos.

> **Es una acción, no un interruptor, y es a propósito.** En Batocera
> (`dxvk_reset_cache`) es un ajuste que se queda puesto. Un ajuste permanente
> borraría la caché **en cada arranque**, con lo que el juego no llegaría a
> tener caché nunca y tendrías tirones para siempre sin saber por qué. Se hace
> una vez, que es cuando sirve.

![El menú del mapeador .keys de un juego](img/mapeador-keys.png)

### Mapear teclas al stick derecho

El editor de `.keys` ofrece las ocho direcciones de los dos sticks:

```
Stick izquierdo arriba / abajo / izquierda / derecha
Stick derecho   arriba / abajo / izquierda / derecha
```

> **Ojo con el ratón virtual.** Por defecto se mueve con el **stick derecho**.
> Si además le asignas una tecla a una dirección de ese stick, hará las dos
> cosas a la vez: mover el puntero y mandar la pulsación. El síntoma —el cursor
> se va solo mientras el juego recibe teclas— no se parece en nada a su causa,
> así que el editor avisa al asignarla y te deja cambiar de idea. Puedes pasar
> el ratón al stick izquierdo en ese mismo menú, o quitarlo si el juego no lo
> necesita.

### El tema cristal

Está en los **dos motores**. Con pygame trae los paneles translúcidos, los dos
focos de color del fondo y la viñeta; con Qt trae además el brillo giratorio de
la selección y el texto dibujado con halo.

Esos dos últimos se quedan fuera de pygame a propósito: pygame dibuja por
software, y un degradado cónico girando bajo la fila seleccionada hay que
recalcularlo en cada fotograma. En la Deck eso se come el presupuesto del menú
entero. Preferimos que cristal se vea bien y vaya fino a que se vea igual que en
Qt y raspe.

El fondo con los focos y la viñeta se dibuja **una sola vez** y se guarda: no
cambia, así que cada fotograma es una copia de imagen.

### Fondos de temporada

El fondo que se ve entre menús cambia solo en unas fechas:

| Tema | Cuándo | Fondo y partículas | La palabra WPROTON |
|---|---|---|---|
| Halloween | 25–31 de octubre | Morado oscuro, brasas naranjas subiendo | W morada, PROTON naranja calabaza |
| Navidad | 20–26 de diciembre | Azul noche, nieve cayendo | W roja (Papá Noel), PROTON blanco nieve |
| Fin de año | 30 dic – 2 ene | Chispas doradas subiendo | W dorada, PROTON blanco |
| Reyes | 5–6 de enero | Destellos dorados cayendo | W dorada, PROTON violeta |

La marca del centro se tiñe también: con el fondo cambiado y las letras en su
morado y cian de siempre, la pantalla queda a medias. Se respeta la forma —la W
distinta del resto— y solo cambian los colores.

El resto del año, el fondo de siempre: una decoración puesta todo el año
dejaría de ser una gracia. Se apaga con `TEMAS_TEMPORADA=0` en `settings.conf`.

> **Si tienes tu propio fondo, manda el tuyo.** Solo se le añaden las partículas
> encima; tu imagen no se pisa por una fiesta.
>
> No se descarga ni se empaqueta ninguna imagen: es todo dibujado. Meter fotos
> de calabazas y de nieve en el script serían megas para cuatro días al año.

El calendario está en una sola función (`tema_temporada`), así que cambiar
fechas o añadir una fiesta se hace en un sitio.

**Para verlos sin esperar a la fecha:** con `DEV_MODE=1` en `settings.conf`,
*Modo desarrollo → Probar un fondo de temporada*. Se rearrancan los menús y el
siguiente ya sale con el fondo elegido; «como toque por fecha» vuelve a lo
normal. El forzado dura hasta que cierres WProton.


![Mandos: SDL, Steam Input, mando Sony y mando virtual](img/mandos.png)

![Rendimiento y compatibilidad: MangoHud, MAKO, ReShade, Fsync, DXVK, FSR, gamescope…](img/rendimiento.png)

![Herramientas del prefijo: winecfg, winetricks, dgVoodoo2, OptiScaler, ReShade](img/herramientas-prefijo.png)

![Casos especiales: lo que necesitan muy pocos juegos](img/casos-especiales.png)

![Protonfixes / UMU: el identificador que usa protonfixes](img/protonfixes-umu.png)

### Cómo está organizado el menú del juego

Tres agrupaciones, porque la pantalla se había convertido en un
cajón de sastre:

| Submenú | Qué hay dentro |
|---|---|
| **Mandos >>** | SDL/hidraw, puente Steam Input → XInput, mando Sony, **mando virtual**, escribir SDL en el registro del prefijo |
| **Protonfixes / UMU >>** | El `GAMEID` y la búsqueda en la base de umu |
| **Carátula y ficha >>** | Las carátulas (elegir una imagen, la 4:3 del repositorio, buscar en SteamGridDB), la ficha del juego, las notas y las estadísticas |
| **Archivo y mantenimiento >>** | Reinstalar el `.bat` del juego, copias de partidas, comprobar el archivo, acceso directo, repetir el asistente, borrar saves del overlay y borrar la configuración |
| *Mapeador .keys* | Se queda **fuera**: convertir el mando en pulsaciones de teclado es otra cosa distinta de elegir cómo se lee el mando |

*Favorito* y *Completado* se quedan fuera de ese submenú a propósito: son
interruptores de una pulsación que se usan a menudo y ahí costarían tres.

Y las dos de empaquetar —*EMPAQUETAR A WSQUASHFS* y *Empaquetar con su prefijo*—
se quedan en el menú principal y **juntas**: son el paso final de preparar un
juego, se usan bastante, y esconderlas detrás de «mantenimiento» sería
enterrarlas.

> *EMPAQUETAR A WSQUASHFS* solo aparece si el juego está **en carpeta**. Si ya
> es un `.wsquashfs`, no hay nada que convertir y la fila no sale.

Dos cosas cambiaron de sitio por estar donde nadie las buscaría:

- El **mando virtual** vivía dentro del *Mapeador .keys*. Tenía sentido cuando
  solo se usaba junto a un fichero de teclas, pero ya no lo necesita.
- *Volver a instalar lo que trae el juego (.bat)* también estaba ahí, y no tiene
  ninguna relación con las teclas: vuelve a ejecutar el `.bat` de instalación
  del juego. Está en *Archivo y mantenimiento*, que es donde encaja por lo poco
  que se usa.

### Que un juego use siempre el más nuevo

Al elegir el runner de un juego, antes de la lista de versiones concretas hay
tres opciones:

| Opción | Qué hace |
|---|---|
| *(automático: último GE-Proton instalado)* | Lo de siempre, y el valor por defecto |
| *(siempre el último Wine instalado)* | El Kron4ek más nuevo que tengas |
| *(siempre el último UMU-Proton instalado)* | El UMU más nuevo que tengas |

Elegir una **versión concreta** ata el perfil a ella: en tres meses estará vieja
y hay que volver a entrar juego por juego. Con estas tres, al bajar una versión
nueva los juegos la cogen solos.

Si eliges una familia que no tienes instalada, WProton te lo dice en ese momento
—no al lanzar— y el juego se lanzará con el último GE-Proton hasta que bajes
uno. Quedarse sin jugar por eso sería peor.

### Pasar partidas entre dos equipos de la misma red

Sin instalar nada. En *Ajustes del juego → Archivo y mantenimiento → Partidas
guardadas → Sincronizar*:

1. En el equipo que **tiene** las partidas: *Compartir mis copias con otro
   equipo*. Sale su IP, el puerto y un **código de seis cifras**.
2. En el otro: *Traer copias de otro equipo*, y escribe esos tres datos.

Se trae lo que aquí no está y lo que allí es **más nuevo**. Lo que aquí es más
nuevo **no se toca**, y se dice cuáles son.

> **Por qué no es sincronización automática, y no va a serlo.** Un
> sincronizador genérico resuelve los choques guardando los dos ficheros con
> nombres distintos. Para un documento vale; para una partida no sirve de nada,
> porque el juego lee uno solo y tú no sabes cuál es el bueno. El caso malo
> llega solo: juegas en un equipo sin red, luego en el otro, y al reencontrarse
> uno pisa al otro en silencio. Con una dirección explícita eso no puede pasar.

Los tres campos que se escriben —IP, puerto y código— salen con un **teclado
numérico** de doce teclas en vez de la rejilla completa de cuarenta: con el
mando, cada cifra está a un paso.

El puerto es 8788 por defecto y se cambia en *Puerto para la red local*. Tiene
que ser **el mismo en los dos equipos**.

**Para no escribir nada la próxima vez.** La primera vez que traigas copias de
un equipo y funcione, se te ofrece guardarlo con un nombre («Deck»,
«Sobremesa»). A partir de ahí, *Traer copias* sale con la lista y no pide ni IP
ni código.

Para que eso funcione, el equipo que comparte debe usar un **código fijo**:
*Código al compartir* → fijo. De serie sale uno nuevo cada vez, que es más
seguro pero obliga a teclearlo siempre. Lo que se quita es escribirlo, no la
puerta: sigue haciendo falta un código.

> El equipo se ofrece guardar **después** de que la descarga haya funcionado, no
> antes. Guardar una IP o un código equivocados solo serviría para volver a
> fallar mañana sin saber por qué.

### Un servidor de partidas siempre disponible

En vez de que las dos máquinas coincidan encendidas, una guarda las copias de
todas. *Partidas guardadas → Sincronizar → **Servidor de partidas***.

**En el equipo que más tiempo esté encendido:** *Instalar el servidor AQUÍ*. Se
queda en marcha con la máquina, sin necesidad de abrir WProton, y te da su IP y
un **token**.

**En los demás:** *Usar un servidor*, con esa IP y ese token. Luego *Subir mis
copias al servidor* deja allí lo que tengas, y *Traer copias* se las lleva.

| Detalle | Cómo está resuelto |
|---|---|
| Permisos | Servicio **de usuario**, sin root. Se quita borrando un fichero |
| Con la sesión cerrada | Se activa *lingering*, o el servicio moriría al salir justo cuando más falta hace |
| Subir algo más viejo | **Se rechaza**: el servidor conserva la copia nueva y te lo dice |
| Una partida que se corrompió | Guarda las **5 últimas versiones** de cada juego en `backups/versiones/` |
| Quién puede escribir | Token largo generado solo, no un código de seis cifras: un servidor que acepta subidas necesita más puerta que uno que solo presta |

> El servidor de *Compartir mis copias* (el de un rato) **no acepta subidas**, y
> está comprobado que las rechaza. Son dos cosas distintas a propósito.

**Funciona en cualquier equipo con Python 3**, que es algo que WProton ya
necesita: no hay dependencias nuevas, todo es biblioteca estándar. *Instalar el
servidor aquí* necesita además systemd (CachyOS, SteamOS y las distribuciones
normales lo tienen; Batocera no, y ahí te avisa y queda el modo manual).

**Y es opcional del todo:** no arranca nada por su cuenta y los ajustes están
vacíos de serie.

> **Lo que más guerra da es el cortafuegos.** El servicio arranca, responde en
> el propio equipo, y desde el otro no hay manera. WProton lo comprueba solo al
> instalar —probando por su **IP de red**, no por `127.0.0.1`, que respondería
> aunque el puerto estuviera cerrado a todo el mundo— y te dice la orden exacta
> para `firewalld` o `ufw`.

Detalles que conviene saber:Detalles que conviene saber:

- **Se comparte solo mientras esa ventana esté abierta.** No queda ningún
  servicio en segundo plano.
- Hace falta el **código**, que cambia cada vez. Sin él no se lista ni se
  descarga nada.
- Se sirve **solo la carpeta de copias**, y solo ficheros `.zip` de dentro: los
  nombres se limpian, así que no se puede pedir nada de fuera.
- Cada copia que llega se **comprueba con su huella SHA-256** antes de darla por
  buena. Una copia de partidas a medias es peor que no tenerla, porque parece
  buena hasta que la restauras.

**Proton oficial de Steam** — en *Runners y herramientas → Descargar runners*.

Valve **no publica Proton para descargar por su cuenta**: solo se consigue a
través de Steam. Así que WProton no lo descarga: busca los que Steam ya tiene
instalados —incluidos los de la tarjeta o de otro disco— y los enlaza.

No ocupa nada, porque es un enlace a la copia de Steam, y se actualiza cuando
Steam lo actualice. Si algún día desinstalas ese Proton desde Steam, el enlace
se queda apuntando a la nada: basta con volver y elegir otro.

> Si no aparece ninguno, instálalo desde Steam: *Biblioteca → Herramientas →
> Proton*.

**Instalar librerías** — los redistribuibles de Windows. Está en la pantalla
de ajustes del juego y también en *Herramientas del prefijo*: desde ahí va
directo al prefijo de ese juego, sin tener que volver a elegirlo. (En el menú
principal sigue estando, para cuando quieras tocar otro prefijo.)

La fila dice a qué prefijo va a instalar, y si es el **compartido** pide
confirmación: lo que metas ahí lo verán todos los juegos en ese modo.

Primero se elige la categoría, para no tener que buscar entre cuarenta entradas:

- *Visual C++ y .NET* — lo que piden casi todos
- *DirectX y shaders*
- *Códecs de vídeo y sonido*
- *Otros* — fuentes, PhysX, XNA, Unreal
- *Verlo todo en una sola lista*

La de **códecs** es la que suele faltar cuando un juego arranca pero **las
cinemáticas salen en negro o sin sonido**.

| Si el juego... | Prueba con |
|---|---|
| No reproduce ningún vídeo | `quartz`, o el pack `directshow` |
| Es de los 2000 y pide Media Player | `wmp11` (o `wmp10`/`wmp9` si es más viejo) |
| Tiene intros de los 90 | `icodecs`, `cinepak` |
| Vídeo sin sonido | `l3codecx` |
| Cinemáticas `.wmv` | `wmv9vcm` |
| Nada de lo anterior funciona | `lavfilters`, o el pack `allcodecs` |

> De los tres Windows Media Player, **marca solo uno**: se pisan entre ellos.
> Si marcas varios, WProton se queda con el más nuevo.

Se puede elegir en qué prefijo van: el compartido, el de un juego concreto, o cualquiera de los que
tengas. Se instalan de uno en uno y la barra avanza de verdad; si alguno falla,
sigue con el resto y al final dice cuál falló.

**Empaquetar con su prefijo** — crea un archivo **autosuficiente**: lleva dentro
el juego y su prefijo, así que se copia a otro equipo y funciona sin instalar
nada. Necesita que el juego use un prefijo propio (no el compartido) y que lo
hayas probado antes. El original no se toca.

**Notas** — un recordatorio tuyo: *"necesita -novr"*, *"con GE 9-27 va mejor"*.

**Borrar la configuración de este juego** — quita sus ajustes y empieza de
cero. El juego y las partidas no se tocan, y queda una copia `.bak` por si
acaso. También están todos juntos en *Perfiles guardados*.

**Borrar este juego DEL DISCO** (*Herramientas del prefijo*) — borra el juego de la carpeta donde esté, y con él lo que WProton guarda de él: ajustes, prefijo propio, carátulas y ficha. Antes de borrar nada **pregunta una sola vez, diciendo el nombre del juego y lo que ocupa**, y avisa de que no se puede deshacer.

**Tus partidas se copian a `backups/` antes de borrar**, igual que en *Borrar TODOS los datos*. Si esa copia falla, no se borra nada: ni el juego ni los datos.

Tres cosas que no hace nunca, por si acaso:

- **No borra nada que esté fuera de tus carpetas de juegos.** Si el juego no está dentro de una carpeta que hayas configurado, lo dice y no lo toca.
- **No borra la carpeta de juegos entera**, solo lo que hay dentro.
- **Si el juego es un acceso directo** (un enlace a otro disco), quita el enlace y deja el juego donde está de verdad. Te lo dice antes.

Tampoco borra mientras estés jugando: hay que salir del juego primero.

**Acceso directo en el escritorio** — crea un icono que lanza ese juego
directamente, con su carátula. Útil para los que juegas a menudo.

**Favorito** — lo pone al principio de la lista, con una cinta en la carátula.

**Partidas guardadas** — copias de seguridad (ver apartado 5).

---

## 4. Si un juego no arranca

Prueba en este orden:

1. **Otro runner.** Muchos fallos se arreglan con un GE-Proton distinto. Los juegos antiguos suelen ir mejor con versiones antiguas (por ejemplo GE-Proton 9-27).
2. **Instalar librerías.** *Runners y herramientas → Instalar librerías de Windows*. Marca `vcrun2022`; si el juego es de Unreal, también el pack de prerrequisitos; PhysX si lo pide.
3. **Argumentos.** Algunos juegos necesitan `-novr` u otros parámetros para no arrancar en un modo que no tienes.
4. **Prefijo propio.** Si sospechas que otro juego le ha ensuciado el prefijo compartido. Con una excepción: si el juego trae **su propio prefijo** (los de Batocera), no lo cambies — trae el registro y las DLL que necesita.
5. **Mirar el registro.** *Ver el registro de la última sesión*: las últimas líneas suelen decir qué falta (una DLL, una librería…).

### WProton te dice qué hacer

Cuando un juego falla, WProton lee el final del registro y, si reconoce el
fallo, **dice qué hacer y dónde**, en vez de enseñarte un código. Cada caso que
reconoce es uno que ya le pasó a alguien:

| Lo que ves | Lo que es |
|---|---|
| `rc=53` y nada más | El juego es de .NET y Mono está apagado |
| «No encuentro los efectos» (ReShade) | Falta `d3dcompiler_47` |
| Un error genérico al arrancar | Falta un `d3dx9_XX` concreto, o un Visual C++ de una versión concreta |
| `rc=1` a los pocos segundos | El prefijo es de 32 bits y el runner no lo admite |
| El juego se sale solo al rato | Se acabó la memoria de 32 bits, o los shaders no compilan |
| Se cierra limpio en segundos | El lanzador arrancó y el juego reventó |

También avisa cuando el registro **repite la misma línea miles de veces**,
aunque la partida haya durado minutos: eso siempre significa que algo va mal.

Y si **no** reconoce el fallo, no se inventa nada.

Si un juego se cierra en menos de diez segundos, WProton te enseña automáticamente el final del registro.

### El mando va en los menús pero no en el juego

Es lo más frecuente en el modo Juego de SteamOS, y no es un fallo del juego.

Steam esconde el mando físico a lo que lanza —con
`SDL_GAMECONTROLLER_IGNORE_DEVICES`, una lista de casi 800 fabricante/modelo— y
ofrece a cambio su mando virtual, un «Microsoft X-Box 360 pad». El problema es
que **ese mando virtual está también dentro de la lista**, así que el juego
recibe la orden de ignorar el único mando que tiene. Los menús de WProton sí lo
ven porque leen `/dev/input` en crudo, y eso hace que parezca cosa del juego.

WProton lo detecta y lo dice en el registro:

```
mando 1: "Microsoft X-Box 360 pad 0"  [045e:028e] <-- STEAM LE DICE AL JUEGO QUE LO IGNORE
[!] TODOS LOS MANDOS QUE HAY ESTAN EN LA LISTA DE IGNORADOS DE STEAM.
```

**La solución** es *Ajustes del juego → Rendimiento y compatibilidad → Arreglo
mando SteamOS (Steam Input)*: quita esas cuatro variables para ese juego, y así
ve el mando virtual con normalidad.

Va por juego y no de serie porque no siempre conviene: si `/dev/hidraw` no se
puede leer, el mando virtual de Steam es el único que funciona, y es justo esa
lista la que hace que el juego lo use.

### Si con eso tampoco va: hacen falta las dos cosas

Hay un segundo motivo, independiente del primero, y por eso quitar la lista de
ignorados a veces no basta. El mando virtual de Steam Input es un dispositivo
**uinput**: aparece en `/dev/input` pero **no tiene nodo `/dev/hidraw`**. Y
GE-Proton 11-4 y siguientes leen los mandos precisamente por hidraw, así que ahí
no encuentran nada. No es que lo ignoren: es que no lo ven.

WProton también lo detecta:

```
[!] EL UNICO MANDO QUE HAY ES VIRTUAL (uinput), sin nodo /dev/hidraw.
    Este runner lee los mandos por hidraw, asi que no lo encontrara.
```

### Cuando Steam se queda el mando: el mando virtual de WProton

Es la vía que **no necesita reiniciar Steam**, y la recomendada.

Steam Input se queda el mando físico y ofrece el suyo, que es uinput y que hay
juegos que no ven. WProton **captura el de Steam y le ofrece al juego un Xbox
360 corriente**, creado por él. El juego ve un mando normal y no hay que tocar
nada de Steam.

**Se elige a mano, en el juego que lo necesite**: *Ajustes del juego → Mapeador
.keys → Mando virtual → «Mando Xbox (probar esto primero)»*.

Y no es automático a propósito. En el modo Juego de la Deck, Steam Input esconde
el mando físico **en todos los juegos**, así que un automático basado en «el
único mando es el virtual de Steam» se activaría en la biblioteca entera para
arreglar uno. Y capturar el mando no es gratis: queda cogido en exclusiva, se
pierden la vibración, el giroscopio y el remapeado de Steam Input, y hay un
salto más de latencia. Eso se paga donde hace falta, no en todas partes.

En el registro se ve qué hizo, siempre:

```
[+] Mando virtual activado (xbox)
Mando virtual: apagado para este juego (MANDO_VIRTUAL=0)
```

> En versiones anteriores esta opción **no funcionaba en la mayoría de juegos**: la
> llamada que crea el mando virtual estaba dentro del bloque que busca el
> fichero `.keys`, así que solo se creaba en los juegos que tuvieran uno.
> Elegías «Mando Xbox», se guardaba en el perfil, y no pasaba nada — sin ningún
> aviso. El comentario del propio código decía que iba aparte del mapeador:
> estaba bien escrito y mal colocado.

Select 5 segundos sigue funcionando: el guardia de salida reescanea los
dispositivos cada 3 segundos y coge el nuestro.

### Si aun así no va

Queda desactivar Steam Input para el atajo de WProton **desde Steam**: en el
menú de Steam, sobre WProton, *Mando → plantilla «Desactivar Steam Input»*. Son
dos pulsaciones y hay que reiniciar Steam para que lo lea.

> WProton llegó a hacer esto solo, editando el `localconfig.vdf` de Steam,
> reiniciándolo y volviendo al juego. Funcionaba, pero eran tres piezas
> frágiles para algo que se hace en dos pulsaciones, y una fila más en los
> ajustes del juego pegada a otra parecida. Se quitó en favor del mando
> virtual.

### El caso del modo Juego: Steam se queda tu mando

En el modo Juego, Steam se queda el mando físico y solo ofrece el suyo, que es
virtual. Aquí **preferir SDL es lo peor que se puede hacer**:
`PROTON_PREFER_SDL` apaga Steam Input en winebus, y si el único mando que hay es
el de Steam Input, apagarlo quita el único mando que existe.

Lo que sirve es el puente que GE-Proton 11-4 añadió para esto:
`PROTON_STEAMINPUT_XINPUT_FALLBACK`, un dispositivo Steam Input que reenvía las
asignaciones de XInput. En *Ajustes del juego → Rendimiento y compatibilidad →
**Puente Steam Input → XInput***.

En **automático** se enciende solo cuando el único mando que hay es el virtual
**de Valve** (`0x28de`) — no con cualquier mando virtual, porque el nuestro
también lo es y para ése la respuesta es otra.

Las dos opciones son incompatibles y WProton no las pone juntas: si estás
prefiriendo SDL, el puente no se pone y se dice en el registro.

**El otro ajuste, para cuando el mando físico sí llega:** *Ajustes del juego →
Rendimiento y compatibilidad → **Desactivar Steam Input para este juego***.

Pone `PROTON_PREFER_SDL`, y GE-Proton **apaga Steam Input y hidraw** cuando esa
variable está presente, dentro de ese Proton y solo ahí. Por eso vale para tres
juegos y no para el resto, y funciona desde el modo Juego sin cerrar Steam.

> No confundir con el «Steam Input por juego» de Steam: Steam guarda eso **por
> aplicación**, y para Steam la aplicación es WProton entero. Editarlo exige
> además tener Steam cerrado, así que desde el modo Juego no se puede. Por eso
> no se hace por ahí.

**WProton lo resuelve solo.** Si el único mando que hay es virtual y
el runner lee por hidraw, pone `PROTON_USE_SDL` sin preguntar y lo dice:

```
[+] Mando por SDL, automatico: el unico mando que hay es virtual
    (el de Steam Input) y no tiene nodo /dev/hidraw, que es por
    donde lo buscaria GE-Proton11-6-x86_64. Con SDL si lo ve.
```

Si quieres lo contrario, *Que Wine lea el mando por SDL* → **Nunca**.

> **Cuidado con dos ajustes que se llamaban casi igual.** Había *Mando vía SDL*
> en Rendimiento y compatibilidad y *Mandos por SDL en este prefijo* en Casos
> especiales, y hacen cosas distintas. Ahora cada uno dice lo que hace:
> **Que Wine lea el mando por SDL, no por hidraw** (el del mando) y
> **Escribir SDL en el registro del prefijo (avanzado)** (el del prefijo).

Si aun así va peor, apágalos y prueba *Arreglar permisos del mando (hidraw)*, o
desactiva Steam Input para el atajo de WProton desde Steam: así el mando físico
llega sin intermediarios.

### Cerrar el juego desde el menú de Steam

Funciona: en el menú de Steam, *Salir del juego* sobre la fila de **WProton**
cierra el juego y te devuelve a los menús de WProton, sin cerrar WProton.

Antes no hacía nada, y el motivo no era Steam. En el modo Juego, Steam
manda un `TERM` a WProton **al cerrarse su ventana** para dejar paso al juego, y
atender ése desmontaba el `.wsquashfs` con el juego dentro. Por eso WProton
ignoraba esas señales a secas — y con ellas, la que manda Steam cuando pulsas
*Salir del juego*, que es exactamente la misma.

Ahora se distinguen por cuándo llegan: en los primeros segundos es la de Steam
al cerrarse la ventana y se ignora; pasado ese rato es tuya y se cierra el
juego. El margen es `WP_CIERRE_GRACIA` en `settings.conf`, 20 segundos por
defecto. Súbelo si un juego tarda mucho en aparecer y se te cierra solo; bájalo
si tardas en poder cerrarlo.

Con el mando, **Select** 5 segundos hace lo mismo y sigue disponible.

### El juego no sale con su nombre en el menú de Steam

Si en el menú de Steam sale solo «WProton» y no la fila del juego, es la
**superposición de Steam**. Steam se entera de que hay un juego corriendo
porque le mete su `gameoverlayrenderer.so` al proceso; si eso no llega, para
Steam solo existe el atajo, y desde su menú no hay nada que cerrar.

WProton la deja puesta. Los `wrong ELF class ... ignored` que verás en el
registro **son normales**: Steam pone las rutas de 32 y de 64 bits a la vez y
`ld.so` descarta la que no corresponde.

Se decide **por juego**, en *Ajustes del juego → Casos especiales → Cómo ve
Steam este juego*, con cuatro opciones:

| Opción | Qué hace |
|---|---|
| **Automático** | Lo que diga el ajuste general. Es lo normal |
| **Puesta** | Steam ve el juego, con superposición |
| **Sin superposición** | Le quita la superposición, pero **Steam sigue viéndolo** |
| **Ocultar el juego a Steam** | Steam solo verá WProton |

La diferencia entre las dos últimas importa, y costó averiguarla: quitar la
superposición **no oculta nada**. En la 1.60 se quitaba y el juego seguía
saliendo en el menú de Steam. Lo que ata la ventana del juego a una aplicación
de Steam son las variables de identidad —`SteamAppId`, `SteamGameId` y
compañía—, y de ellas `SteamGameId` en particular: umu-launcher saca de ahí el
AppID y se lo pone a la ventana, que es lo que lee el compositor.

**Ocultar** quita esas variables. Lo que pierdes:

- No hay superposición: nada de Shift+Tab, capturas de Steam ni contador de FPS.
- Steam Input no engancha en el juego.

Lo que ganas: para Steam solo existe WProton, así que *Salir del juego* actúa
sobre WProton —que cierra el juego y hace el fin de partida completo: desmontar,
recolocar los menús, guardar las estadísticas— y Steam no puede dar la partida
por terminada antes de tiempo. **Select** 5 segundos sigue funcionando igual.

Va por juego y no con un interruptor general porque hay lanzadores que se
cierran al leer lo que otros programas les escriben en la salida —BudgieLoader,
el de los juegos de Raw Thrills, se cierra con los avisos de GameMode y
MangoHud—, y no es descartable que alguno haga lo mismo con esto. Un
interruptor general obligaría a elegir entre ese juego y todos los demás.

`STEAM_COMPAT_CLIENT_INSTALL_PATH` no se toca en ningún modo: Proton la necesita
para arrancar y no es una variable de identidad.

El general, si alguna vez hace falta, es `STEAM_OVERLAY_GENERAL` en
`settings.conf`: sólo cambia lo que significa «automático».

### Si la pantalla se queda en «Preparando el prefijo…»

Pasa al usar un runner **Wine** sobre un prefijo que hizo Proton: hay que volver
a registrar sus servicios, y eso tarda unos segundos la primera vez con cada
runner. La pantalla dice hasta cuánto puede tardar.

Si se pasa de ese plazo, WProton **corta y te lo dice**, en vez de quedarse ahí.
Casi siempre es un proceso de Wine de otra versión que sigue vivo en ese prefijo:
cierra WProton del todo y vuelve a entrar. Si se repite con un juego concreto,
dale un prefijo propio.

Los plazos se pueden cambiar en `settings.conf`, aunque no suele hacer falta:

| Ajuste | Para qué | Por defecto |
|---|---|---|
| `WP_WINEBOOT_TIMEOUT` | Volver a registrar el prefijo | 180 s |
| `WP_WINESERVER_TIMEOUT` | Cerrar los procesos de un prefijo | 20 s |

**Perfiles de la comunidad**: en *Carátulas y perfiles de la comunidad* puedes descargar configuraciones ya probadas para juegos problemáticos. Vienen con notas explicando por qué necesitan esos ajustes.

Si el juego además necesita un **mapeo de mando**, el perfil trae también su `.keys` y se descarga con él; el diálogo lo avisa antes. Se guarda con el nombre de *tu* juego y queda marcado como suyo, así que funciona aunque en el repositorio se llame distinto. Si ya tenías uno, se te pregunta antes y el tuyo se conserva como `.bak`.

También puedes pedirla tú en cualquier momento, sin esperar a que salte ningún aviso: *Ajustes del juego → **Traer la configuración de la comunidad***. La fila dice en qué situación estás —que no la tienes, que ya la tienes, o que hay una nueva—, y funciona siempre, incluso si tienes la misma versión: sirve para **volver atrás** cuando has estado toqueteando ajustes y lo has dejado peor. Antes de hacer nada avisa de que sustituye tu configuración, que se guarda como `.conf.bak`.

Si el perfil que tienes **se mejora más tarde en el repositorio**, WProton te lo dice: al lanzar ese juego avisa de que la comunidad ha mejorado su configuración y te ofrece la nueva. Si dices que no, no vuelve a preguntar por *esa* versión, pero sí cuando salga la siguiente. Y si habías ajustado tu copia a mano te lo advierte antes: la tuya se guarda como `.conf.bak`.

Para revisarlos todos de golpe, sin esperar a abrir cada juego: *Biblioteca y preferencias → Perfiles del repositorio → **Buscar perfiles actualizados***. Dice qué juegos tienen versión nueva, marca los que has modificado tú, y los actualiza todos con una sola confirmación.

Esto no cuesta ninguna consulta extra a GitHub: la lista de perfiles que WProton ya pide al arrancar trae dentro la versión de cada fichero. Un perfil que te hayas hecho tú a mano no se compara con nada y no se toca nunca.

Al arrancar, WProton **pone al día las listas de perfiles y de carátulas** del repositorio, en segundo plano y sin que el arranque espere (con un suelo de diez minutos entre refrescos, para no agotar las 60 peticiones por hora que da la API de GitHub sin credenciales). Además, **un juego que se acabe de subir se encuentra igual**: si no está en la lista guardada, WProton la pide otra vez antes de darlo por perdido (una sola vez por sesión). Y si aun así no aparece, *Biblioteca y preferencias → Comprobar el repositorio* dice por qué.

### Si hace falta mirar más adentro

En `settings.conf` hay tres interruptores de diagnóstico. Se activan con `=1`, se
juega una vez y el resultado queda en el registro:

| Ajuste | Qué apunta |
|---|---|
| `DIAG_DLL=1` | Qué DLL carga el juego, y si un override se aplicó de verdad |
| `DIAG_VIDEO=1` | Todo lo del vídeo (incluido Media Foundation); al salir resume las cinco causas de que no se vea |
| `DIAG_CIERRE=1` | Qué queda vivo al cerrar |

Acuérdate de volver a ponerlos a `0`: el registro crece bastante.

---

## 5. Partidas guardadas

![Partidas guardadas de un juego: copiar, restaurar y ver dónde guarda](img/partidas-guardadas.png)

WProton **aprende dónde guarda cada juego**. Al jugar, observa qué ficheros escribe y localiza la carpeta exacta (por ejemplo `AppData/Roaming/Yacht Club Games/Mina the Hollower`), ignorando cachés y temporales.

En *Ajustes de un juego → Partidas guardadas*:

- **Crear copia de seguridad ahora** — genera un zip con fecha en `backups/`.
- **Restaurar una copia** — vuelve a una copia anterior (te pide confirmación).
- **Ver dónde guarda las partidas** — comprueba qué se está copiando.
- **Sincronizar** — con *rsync* a otro equipo o disco, o preparando la carpeta para *Syncthing*.

> Si acabas de añadir un juego, juega una partida antes de hacer la copia: hasta entonces WProton aún no sabe dónde guarda.

---

## 6. Personalizar el aspecto

Si vienes de Batocera o ES-DE y ya tienes tus carátulas escaneadas, WProton las
usa tal cual: busca la carpeta `images` (o `media`) junto a los juegos. No hay
que copiar nada. Si además pones una carátula propia en `covers/`, esa manda.


En *Biblioteca y preferencias*:

- **Vista de juegos**: lista o **rejilla de carátulas**. En la lista, el panel de la derecha muestra la carátula del juego resaltado y sus datos.

> **Cómo arranca WProton recén descargado**: menú **moderno**, vista de
> **lista** y carátulas **4:3**. Es la combinación que funciona sin que el
> usuario tenga que hacer nada: las 4:3 vienen del repositorio y las otras
> formas dependen de que uno se saque una clave de SteamGridDB. Todo se
> cambia aquí mismo y queda guardado.

![Vista de rejilla: los juegos como carátulas grandes](img/biblioteca-rejilla.jpg)

La vista de **carátulas panorámicas** enseña menos juegos a la vez, pero se
reconocen mejor. La cinta de la esquina marca los favoritos, y debajo de
cada uno sale el tiempo jugado y cuándo fue la última vez:

![Vista de carátulas panorámicas, cuatro por fila](img/biblioteca-anchas.jpg)

- **Carátulas por fila**: automático (se adapta a tu pantalla) o de 4 a 8. Menos carátulas por fila significa carátulas más grandes; más, ver más juegos de un vistazo.
- **Traer todas las carátulas del repositorio**: baja de una vez TODAS las 4:3 de `covers_43/`, no solo las de tus juegos. Dice cuántas son y cuánto ocupan antes de empezar, y no pide clave ninguna.
- **Perfiles del repositorio**: dos opciones que hacen cosas distintas.
    - **Traer los de tus juegos (los instala)**: cruza tu biblioteca con `profiles/` e instala de una vez todas las configuraciones que te correspondan, con sus `.keys` cuando los haya. Quedan en `profiles/` con el nombre de *tus* juegos, listas para jugar. Pregunta **una sola vez**, antes de empezar, qué hacer con los juegos que ya tienen perfil: dejarlos como están (lo que viene marcado) o sustituirlos guardando el tuyo como `.conf.bak`.
    - **Traer TODOS a comunidad/**: el repositorio entero, tengas sus juegos o no, en una carpeta aparte y con el nombre que tienen allá. No van a `profiles/` a propósito: ahí cada fichero tiene que llamarse como *tu* juego para que WProton lo encuentre, y el menú de perfiles pasaría a tener cientos de entradas que no son tuyas. En `comunidad/` los puedes abrir como ficheros de texto para mirar o comparar, y además **esta carpeta es la primera parada**: si el perfil de un juego ya está aquí, WProton lo instala del disco al instante sin preguntarle nada a GitHub, y funciona igual sin conexión. Solo si el juego no está en la copia se sale a la red. Las carátulas siguen saliendo del repositorio siempre. Solo descarga lo que falte.
- **Comprobar el repositorio**: dice cuántos perfiles, ficheros de teclas y carátulas hay en el repositorio **ahora mismo**, y, cruzándolo con tu biblioteca, **cuáles de tus juegos se quedan sin perfil o sin carátula**. Es lo primero que hay que mirar cuando algo "no se descarga": separa los cinco motivos posibles (sin conexión, repositorio mal escrito, GitHub limitando peticiones, el fichero no está subido, o el nombre no coincide) sin tener que abrir una terminal. El detalle completo, con la lista entera de los que faltan, queda en el registro.
- **Descargar carátulas**: las **4:3** salen de la carpeta `covers_43/` del repositorio de WProton y no piden nada; las **verticales** y las **panorámicas** necesitan una clave gratuita de [SteamGridDB](https://www.steamgriddb.com) (Perfil → Preferences → API), que se pide una sola vez y solo si las has pedido.
- **Tema**: *moderno* (paneles y acento neón, el que viene puesto), *clásico* (sobrio) o *arcade* (synthwave con efecto CRT).
- **Tamaño de la letra**: normal, grande o muy grande. En consolas portátiles se agradece "grande".
- **Ordenar juegos por**: nombre, últimos jugados o más jugados. Los favoritos van siempre primero.
- **Extensión en la lista**: apagada de fábrica. Encendida, la lista muestra `Halo.wsquashfs` en vez de `Halo` — útil cuando tienes la biblioteca a medio convertir y quieres distinguir de un vistazo lo que está en `.wsquashfs` y lo que está en `.dwarfs`. Solo afecta a la **lista**: en la rejilla no se ve nunca. El panel de la derecha tiene además una fila **Formato** que lo dice siempre, encendido o no.
- **Usuario instalación ISO**: el nombre que se le pone a la configuración que trae el juego al instalarlo desde una imagen (`UserName`/`PlayerName`). De fábrica **Deck** — ese nombre sale en la pantalla del juego, así que lo suyo es el nombre de la máquina y no tu cuenta de Linux. Si lo dejas vacío, se usa el usuario del sistema.
- **Idioma**: castellano o inglés.
- **Copia de tu configuración**: exporta perfiles, ajustes y carátulas a un zip para llevarlos a otro equipo.

---

## 7. Modo "solo jugar"

Para quien solo quiere jugar y no tocar nada. Edita `settings.conf` y pon:

```
DIRECT_PLAY=1
```

Al abrir WProton irás directo a la lista de juegos; al salir de ella, el programa se cierra. Para volver al menú completo: `./wproton.sh --menu`, o vuelve a poner `DIRECT_PLAY=0`.

Combinado con la vista de rejilla y las carátulas, queda como un lanzador de consola.

---

## 8. Gestión de archivos

![Gestión de archivos: tamaños, montajes colgados, caché de shaders y huérfanos](img/gestion-archivos.png)

*Gestión de archivos* en el menú principal:

- **Mostrar el tamaño de WProton** — desglose por partes y espacio libre.
- **Tamaño por juego** — cada juego con sus partidas y su prefijo.
- **Limpiar caché de shaders** — se puede borrar sin miedo: se regenera sola.
- **Buscar prefijos y partidas huérfanas** — restos de juegos que ya borraste.
- **Borrar copias de partidas antiguas** — conserva las tres más recientes de cada juego.
- **Reparar carpetas tapadas** — cuando algo borra y rehace una carpeta, el juego
  deja de ver lo que trae su propio archivo (idiomas, configuración).
- **Copiar o mover ficheros** — ver abajo.

Antes de importar o empaquetar, WProton comprueba que haya sitio y avisa si no lo hay.

### Copiar o mover ficheros

Para llevar algo de un sitio a otro sin salir de WProton: una partida guardada,
un `.keys`, una carátula, un fichero que le falte a un juego.

Eliges **qué** copiar y **dónde** ponerlo, y ya. Vale tanto para ficheros sueltos
como para carpetas enteras.

**No borra nada.** Si te equivocas, el original sigue donde estaba. Y hay tres
avisos por si acaso: no deja copiar algo sobre sí mismo, ni una carpeta dentro de
sí misma —se copiaría sin fin hasta llenar el disco—, y pregunta antes de
reemplazar algo que ya exista.

> Si borras un prefijo desde aquí, WProton guarda antes una copia de lo que haya
> en `users/` (partidas y configuración). En el compartido son las de **todos** los
> juegos que lo usen.

---

## 9. Juegos de Linux

Un `.wsquashfs` no tiene por qué llevar un juego de Windows. Si dentro hay un
juego de **Linux**, WProton lo detecta y lo lanza tal cual: sin Wine, sin
Proton y sin prefijo.

No hay que hacer nada especial. Añades el juego como cualquier otro —eligiendo
su `.sh` o su ejecutable— y WProton se encarga del resto:

- **Lo detecta solo.** Si hay algún `.exe` por medio, lo trata como juego de
  Windows: eso manda siempre.
- **No pregunta qué ejecutar.** Estos juegos tienen un lanzador y punto.
- **No escribe `autorun.cmd`**, que es una convención de Wine y aquí no pinta
  nada.

### Dónde guardan sus cosas

Un juego de Linux escribe sus ajustes y partidas en tu carpeta personal
(`~/.config`, `~/.local`). WProton los desvía a una carpeta propia, como hace
el prefijo con los juegos de Windows:

- **`WProton.home`** — una sola para todos, si el juego usa el prefijo
  compartido (lo normal).
- **`<juego>.home`** — solo suya, si le pones *prefijo propio del juego*.

Así tu carpeta personal no se llena, y para llevarte un juego a otro sitio te
llevas su carpeta.

> Las opciones de Wine —runner, prefijo, librerías, GAMEID— no aparecen en la
> configuración de estos juegos: ahí no hacen nada.

**Si un juego no arranca** y el registro habla de `GLIBC` o de una biblioteca
que falta, es que se compiló para otra distribución. Eso no lo arregla WProton;
suele resolverse con una versión del juego más reciente.

---

## 10. Juegos de TeknoParrot

Los juegos de recreativa que usan **TeknoParrot** funcionan sin preparar nada.

Estos juegos suelen venir de Batocera con un `.bat` que comprueba en qué ruta
está la ISO y copia uno de dos perfiles ya rellenos. Esas rutas no existen aquí
—el juego se monta en una carpeta temporal distinta cada vez—, así que WProton
lo resuelve por su cuenta al lanzarlo:

- Da a la carpeta del juego **su propia unidad** (`D:`), para que las rutas del
  perfil sean cortas, que es lo que TeknoParrot reconoce.
- Rellena la ruta del juego en el perfil de `UserProfiles`, aunque venga vacía.
- Se salta el `.bat` y llama a TeknoParrot directamente con ese perfil.

**El fichero original no se pierde.** Antes de tocar nada se guarda una copia
(`<perfil>.xml.wproton_original`) y al salir del juego se devuelve a su sitio,
así que **el juego sigue funcionando en Batocera** sin hacer nada. Si WProton se
cierra de golpe, se restaura al arrancar la próxima vez.

> TeknoParrot es un **lanzador**: su ventana se queda abierta mientras el juego
> corre. Para volver a WProton, ciérrala o mantén **Select**.

Si el perfil pide un fichero que no está en el juego, WProton lo dice con el
nombre en vez de fallar en silencio.

### Lo que WProton hace solo

Tres cosas que hacían falta y no eran evidentes:

**GameMode y MangoHud se apagan.** El cargador de los juegos de Raw Thrills
(BudgieLoader) **se cierra al leer los avisos** que esos dos programas escriben
en la salida: los toma por errores fatales. Se apagan solo cuando el lanzador es
TeknoParrot, y sin tocar tus ajustes.

**Los prefijos de 32 bits funcionan.** Los `.wsquashfs` que vienen de Batocera
traen prefijos de 32 bits. Antes fallaban con `rc=1` a los pocos segundos porque
WProton exportaba `WINEARCH=win32` a todo, que es lo que hace que los Wine
modernos se nieguen a arrancar (`WINEARCH is set to 'win32' but this is not
supported in wow64`).

Ahora se decide según el caso: **no se exporta nunca de oficio** —la arquitectura
está en el registro del prefijo y Wine la lee de ahí—, pero **sí** cuando se usa
un runner **Wine** sobre un prefijo que de verdad es de 32 bits, porque ese wine
arrancaría en modo de 64 y lo rechazaría. Es lo que hacen Bottles, Lutris y
Batocera, y es lo que hace funcionar *Aliens Armageddon*.

**Lo que el paquete trae en `drive_c` se ve desde `C:\`.** El perfil XML de un
juego suele decir `C:\game\game.exe`. Si usas un prefijo distinto del incluido,
ese `C:` es otro sitio y el juego no encontraría nada: WProton enlaza las
carpetas del paquete dentro del `C:` que se esté usando.

![Instalar librerías: primero se elige en qué prefijo](img/instalar-librerias-prefijo.png)

### Un prefijo para todos los juegos de TeknoParrot

En **Biblioteca y preferencias → Prefijo de TeknoParrot** se **descarga uno ya
hecho**, con sus librerías puestas —Visual C++, compiladores de shaders, XACT,
varios .NET y DXVK— y probado. Tarda lo que tarde la descarga; después cualquier
juego lo elige en **Ajustes del juego → Prefijo → TeknoParrot** y lo reutiliza.

> Antes se creaba aquí mismo con winetricks. Se quitó: eran quince verbos, varios
> de ellos bajando ficheros de terceros, y cuando alguno fallaba el prefijo
> quedaba a medias sin que nadie supiera cuál. Bajarlo hecho da siempre el mismo
> resultado.

La otra opción del mismo menú, **Completarlo con instaladores de
`dependencies/`**, no es lo mismo ni la sustituye: usa los instaladores de verdad
que traiga el juego en esa carpeta. El DXSETUP de un juego cubre cosas —sonido y
mando, en 32 y en 64 bits— a las que los verbos sueltos de winetricks no llegan,
y eso ha resuelto algún juego que con winetricks no había forma.

Si algo falta, la fila del menú lo dice por su nombre, para reintentar solo eso.

### Si cambias de runner en ese prefijo

Lo comparten todos los juegos de TeknoParrot, así que es el único que pasa de un
runner a otro. Cambiar de **Proton a Wine** (o al revés) sobre el mismo prefijo
requiere cerrarlo y volver a registrar sus servicios, y WProton lo hace solo:

- Cierra lo que quede vivo dentro (`wineserver`, `services.exe`, `winedevice`).
- Vuelve a registrar los servicios con el runner nuevo. Son unos segundos, y
  **solo la primera vez con cada runner**.

Si eso se pasa del plazo, **te lo dice** y no da el prefijo por preparado, así
que el siguiente intento vuelve a probarlo. Cuando pasa, casi siempre es un
proceso de Wine de otra versión que sigue vivo ahí dentro: cierra WProton del
todo y vuelve a entrar. Si se repite con un juego concreto, dale un prefijo
propio.

### Qué se sabe de cada juego

**Biblioteca y preferencias → Base de datos de arcades.** Reúne lo documentado
sobre TeknoParrot, JConfig, RConfig, iDMac, DemulShooter, Taito Type X, Sega
Ring y bastantes títulos concretos. Se busca por nombre —del juego, del
ejecutable o de la plataforma— o se mira el listado entero, y **cada ficha dice
de qué fuente sale**.

Con un juego delante, la ficha está en **Ajustes del juego → Instalar librerías
→ Qué se sabe de este juego**, con la opción de instalar lo que necesite.

Un par de cosas que están ahí y ahorran tiempo:

- **JConfig**: si no hay un mando conectado al arrancar, el juego se cierra con
  el error **1280**. Conecta el mando antes de lanzar.
- **Sega Rally 3, la serie WMMT y Mario Kart GP DX** necesitan **GStreamer y sus
  plugins instalados en el sistema** para los vídeos.

---

## 11. Formatos de archivo

Al importar un juego, WProton puede dejarlo de tres maneras (*Biblioteca y preferencias → Formato al empaquetar*):

- **wsquashfs** — el de siempre, compatible con Batocera y PortProton.
- **dwarfs** — comprime más. Se nota sobre todo en juegos con muchos archivos parecidos; en juegos cuyos datos ya vienen comprimidos, la diferencia es pequeña.
- **carpeta** — **sin empaquetar**: el juego queda como una carpeta normal dentro de tu carpeta de juegos.

Los dos primeros se montan igual de rápido y se usan exactamente igual. Puedes tener juegos de los tres tipos mezclados.

**Todo lo demás funciona igual con los tres**, y esto se pregunta a menudo con los `.keys`: el mapeo del mando, los perfiles, las carátulas, el overlay de las partidas y los prefijos no miran el formato del paquete. Un `Mi_Juego.keys` junto a un `Mi_Juego.dwarfs` se encuentra exactamente igual que junto a un `.wsquashfs`, y lo mismo con `Mi_Juego.dwarfs.keys` o con el de `profiles/`.

### Cuándo elegir "carpeta", y qué se pierde

Es más sencillo y se entiende de un vistazo: lo que hay en el disco es el juego, sin nada en medio. A cambio se pierden las cuatro cosas para las que existe el empaquetado, y conviene saberlas antes de activarlo (WProton te las recuerda al elegirlo):

- **Un fichero por juego.** Un juego son decenas de miles de archivos sueltos, y en una microSD eso se lee bastante más lento que un `.wsquashfs`.
- **La compresión.** El juego ocupa lo que ocupa.
- **El overlay que separa tus partidas del juego.** Con el juego en carpeta, las partidas se guardan entre sus archivos, como en Windows.
- **Llevártelo a otro equipo copiando un archivo.**

Los juegos que ya tengas empaquetados se siguen usando igual: el ajuste solo afecta a los que importes a partir de ese momento. Y las dos opciones cuyo trabajo *es* empaquetar —*Convertir carpeta a wsquashfs* y *empaquetar un juego con su prefijo*— siguen haciendo un archivo aunque tengas puesto "carpeta": si has pedido un paquete, es que quieres un paquete.

### Juegos con decenas de miles de archivos

Hay un caso en el que **"carpeta" es la buena**, y conviene conocerlo porque desde fuera parece una avería: un juego con *muchísimos* archivos —decenas de miles— puede quedarse cargando para siempre si lo empaquetas, mientras que en carpeta arranca normal.

Pasó con un juego de 48 GB y 32.164 archivos. No estaba roto: en el registro no había ni un error y la ventana del juego llegaba a abrirse. Simplemente tardaba una barbaridad. El motivo es que se juntan dos cosas que por separado no se notan:

- Un juego empaquetado se lee a través de **dos capas** (la imagen y la superposición que guarda tus partidas), y cada una de ellas atiende desde un programa, no desde el núcleo del sistema.
- Wine resuelve las rutas **sin distinguir mayúsculas de minúsculas**, y para eso **lee la carpeta entera** cada vez que el juego abre un archivo.

Con unos cientos de archivos eso es gratis. Con treinta mil en la misma carpeta, se multiplica.

Por eso, **al empaquetar, si el juego pasa de 20.000 archivos WProton te avisa y te ofrece dejarlo en carpeta**, diciéndote cuántos son. Puedes decirle que no y empaquetar igualmente —el aviso no impide nada—, pero merece la pena pensárselo antes: rehacer el empaquetado de un juego grande en el otro formato son otras tantas horas.

Dicho esto, **un paquete monta más rápido de lo que montaba**: WProton usa ahora `squashfuse_ll` cuando está disponible —el driver rápido del mismo proyecto— y le dice al sistema que lo que lee de una imagen no caduca, porque una imagen montada no puede cambiar. Eso quita muchísimas idas y venidas en juegos con muchos archivos.

**Si no lo tienes, WProton se lo descarga solo**, en segundo plano al arrancar, sin que nadie espere: un binario a `runtime/tools`, como `squashfuse` o 7-Zip. Se intenta una vez; si no hay red o no se encuentra, se reintenta a la semana y mientras tanto se monta como siempre. Para forzarlo en el momento está *Runners y herramientas → Descargar herramientas FUSE*, que además te dice qué driver vas a usar. En el registro aparece en cada arranque:

```
Montaje de imagenes: driver = .../squashfuse_ll [low-level, cache permanente]
```

Si quieres cambiar ese número, o quitar el aviso, está en `settings.conf`:

```
PACK_AVISO_FICHEROS=20000   # 0 = no avisar nunca
```

Y si ya tienes el juego empaquetado y te pasa esto, la salida es *Archivos y discos → Convertir wsquashfs a carpeta*. Si ese juego tiene partidas guardadas en su superposición, **te pregunta si incluirlas** en la carpeta —lo normal es decir que sí: así la carpeta queda como lo veías al jugar—. Las originales no se tocan, siguen en `wsquashfs/overlays/<juego>/upper/`.

### Los comprimidos de los que salió el juego

Al importar un `.zip`, `.7z` o `.rar`, cuando el juego ya está instalado WProton **te pregunta** si borrar los comprimidos originales, diciéndote cuántos son y cuánto ocupan. Antes los borraba sin preguntar, y hay dos buenas razones para conservarlos que no puede adivinar: que sean tu única copia del juego, o que quieras importarlo en otro equipo.

Solo toca ficheros con extensión de comprimido, incluidos los multiparte (`.001`, `.partN.rar`, `.rNN`, `.z01`). Un `Mi.Juego-partidas.txt` o un `Mi.Juego.jpg` al lado no se tocan.

### 7-Zip

Para abrir `.7z` y `.rar` hace falta 7-Zip, y **WProton se lo descarga solo**: un único binario en `runtime/tools`, sin sudo y sin instalar nada en el sistema, igual que hace con `squashfuse` o con su propio Python. Si ya tienes un `7z` en el sistema, usa el tuyo y no descarga nada.

Esto importa sobre todo en la Steam Deck: su sistema es de solo lectura, así que la vía de "instala el paquete p7zip" no era una opción ahí. Si prefieres poner el binario a mano, vale cualquier 7z: déjalo en `runtime/tools` con el nombre `7zz`.

---

## 12. Preguntas frecuentes

**¿Puedo mover WProton a otro sitio o a un pendrive?**
Sí. Si en `settings.conf` usas una ruta relativa —`GAMES_PATH="games"`— puedes mover la carpeta entera y todo seguirá funcionando.

**Se ve el puntero del ratón encima del juego.**

WProton lo **esconde por inactividad**, como hace `unclutter`: si pasan unos segundos sin que muevas el ratón —que es lo que ocurre jugando con el mando— el puntero desaparece, y en cuanto lo mueves vuelve al instante. Se ajusta en *Preferencias → **Puntero mientras juegas***: encendido o apagado, 1, 3 (lo normal), 5 o 10 segundos de espera, y el **margen de movimiento**. En `settings.conf` son `OCULTAR_CURSOR`, `CURSOR_SEGUNDOS` y `CURSOR_UMBRAL`.

**El margen de movimiento es la parte que no se ve venir.** En un equipo de juego el puntero casi nunca está en el píxel exacto: Steam Input puede estar emulando un ratón, un trackpad haciendo de ratón manda movimiento con solo apoyar el dedo y un stick con deriva lo empuja un píxel cada tanto. Pidiendo el píxel exacto, el puntero **no se escondía nunca** y parecía que la función no funcionaba. Con un margen de 8 px un temblor ya no cuenta como "estoy usando el ratón", y mover el ratón de verdad lo sigue devolviendo al instante. Si aún así se te queda a la vista, sube el margen; si tarda en reaparecer, bájalo.

Y como WProton ya está leyendo el mando para poder cerrar el juego, lo aprovecha: **si están llegando eventos del mando, con un segundo quieto basta**, porque entonces es seguro que no estás en el ratón.

Si el puntero sigue a la vista, el registro lo dice cada minuto con los números: cuánto hace que se movió de verdad, cuántas veces ha temblado y cuántas se ha movido. Eso distingue "no se intenta esconder" de "se esconde y algo lo vuelve a pintar", que son dos averías distintas.

Está hecho así porque hay **dos cosas que cumplir a la vez**: el puntero tiene que irse de verdad, y el cursor tiene que estar cuando el juego lo pide. Esconderlo a secas (`XFixesHideCursor` y punto) cumplía la primera a medias y rompía la segunda: se llevaba por delante el cursor **del juego** y en los menús de configuración de algunos juegos no había con qué pinchar. Con la inactividad no hay que elegir: tocas el ratón y el cursor está ahí.

**Si el puntero se esconde mientras lees un menú del juego**, sube los segundos. Y si el juego **captura** el ratón —lo normal en primera persona— para WProton eso es "no se mueve", así que se queda escondido, que es justo lo que quieres ahí.

Se esconde en **todas las pantallas** de la sesión, no solo en la de WProton: con gamescope por medio el juego pinta en otro XWayland, y tocando solo la nuestra el puntero seguía viéndose encima del juego.

**Y por dos caminos a la vez**, porque uno solo no llega a todas partes:

1. `XFixesHideCursor`, el de X de toda la vida. Funciona en una sesión X11.
2. Ponerle a la ventana del juego un **cursor transparente**. Es el camino que usa cualquier programa para enseñar su propio cursor, así que cruza XWayland sin problema.

El segundo hace falta porque en una **sesión Wayland** —lo normal en CachyOS con KDE— el puntero no lo dibuja X: lo dibuja el compositor, y el juego corre dentro de XWayland. Ahí el primer camino puede quedarse en nada; es la misma razón por la que `unclutter` tampoco funciona en Wayland. El registro dice al arrancar qué clase de sesión hay, para que no haya que adivinarlo.

El cursor transparente se vuelve a poner en cada vuelta mientras está escondido, porque el juego pone el suyo cuando le apetece —Wine lo hace con cada `WM_SETCURSOR`— y si no se repite el puntero reaparece solo. Al mover el ratón se le devuelve su cursor al juego, y al cerrar el juego el puntero vuelve siempre.

**¿Cómo sé si hay un GE-Proton nuevo?**

WProton lo avisa solo. En *Runners y herramientas*, la fila de actualizar pasa a decir `*** RUNNER NUEVO: GE-Proton11-8 *** >>`, y dentro cada familia (GE-Proton, Wine, UMU-Proton) lleva su aviso junto a la versión instalada. La consulta a GitHub se hace en segundo plano al arrancar, así que abrir el menú no espera a la red.

Solo avisa de las familias que tienes instaladas: si no usas Wine, no te dice que hay un Wine nuevo. Y lo que compara no es el número de versión sino el nombre de la carpeta que se instalaría —la misma comprobación que hace la descarga—, así que lo que se avisa y lo que se baja son siempre lo mismo.

**¿Qué mando va a usar el juego, si veo dos?**

En *Ajustes del juego → Mandos → **Detectar el mando que usas y proponer ajustes***. Escucha unos segundos, le mueves el stick al mando que quieras usar, y te dice cuál es y qué ajustes le tocan a ese juego.

Hace falta porque en una Deck, o con Steam abierto, se ven dos mandos: el físico y el `Microsoft X-Box 360 pad 0`, que es el virtual de Steam Input. Y por el nombre no se distinguen —el virtual se hace pasar por un Xbox 360—, así que WProton mira el sysfs, la lista de mandos que Steam pide ignorar, y sobre todo **cuál manda eventos**. Si no mueves nada, te lo dice y no cambia nada: no elige uno al azar.

**Un juego trae su prefijo dentro del archivo y no arranca.**

Proton no sabía que ese prefijo ya existía —le falta un fichero interno (`pfx/creation_sync_guard`) que sólo pone él al crear uno— así que intentaba crearlo encima y se caía con un `FileExistsError` al primer fichero repetido. El juego moría en tres segundos, en cada intento. WProton pone ese fichero y marca el prefijo con la versión de formato que Proton compara de verdad, leída del propio runner.

**Ese arreglo trajo otro, y por eso en la 2.04 cambió el método.** Poner ese fichero hace que Proton se salte la creación del prefijo… y había otra parte de WProton contando con que la hiciera: al sacar el prefijo del archivo se borraban las DLL que trae el runner, con la idea de que Proton las repusiera. No las reponía nadie, y el prefijo se quedaba sin `kernel32.dll` (`wine: could not load kernel32.dll`). Ahora `windows/` se copia entera: ocupa más y arranca.

Y el fichero **sólo se pone si el prefijo se sostiene solo** —tiene registro y tiene `kernel32.dll`—. Dicho de un prefijo vacío sería mentira, y Proton se la creía: se saltaba la creación y se estrellaba en la primera copia (`FileNotFoundError: .../pfx/drive_c/vrclient/bin`). Si encuentra uno puesto por una versión anterior en un prefijo a medias, **lo quita**, así que los prefijos que se rompieron con la 2.03 se arreglan solos al volver a entrar.

Si tienes un juego así y sigue fallando, el registro lo dice: busca `creation_sync_guard` y `CURRENT_PREFIX_VERSION`.

**¿Dónde están mis partidas?**
En `wsquashfs/overlays/<juego>/upper/` y, según el juego, dentro de su prefijo. Esa carpeta **no se borra nunca** al reempaquetar un juego.

**Los trackpads de la Steam Deck**

Esto hay que contarlo bien, porque se arregló dos veces a ciegas antes de ir a mirar el código del driver (`drivers/hid/hid-steam.c` del kernel), y las dos veces se atacó un mecanismo equivocado.

El mando tiene **dos modos**, y los cambias tú **manteniendo pulsado OPCIONES** (el botón de las tres rayas) **medio segundo**. El mando vibra al cambiar. Es el mismo gesto que usa Steam:

- **Modo escritorio** (lo normal). El *firmware del mando* emula ratón y teclado: el pad **derecho** mueve el puntero y el **izquierdo** hace de rueda. A cambio, el sistema no publica los trackpads: el dispositivo existe pero no manda ni un evento.
- **Modo gamepad**. Se apaga esa emulación —y esto es lo que la gente cuenta como *"se han muerto los trackpads"*— y el sistema empieza a publicar los dos pads como ejes del mando.

**Así que si los trackpads no te mueven el puntero, lo más probable es que el mando esté en modo gamepad, y se arregla manteniendo OPCIONES medio segundo.** No hace falta WProton, ni `sudo`, ni reiniciar.

Y lo que **no** es verdad, aunque antes lo dijera este manual: que WProton los apagara al abrir el mando. En el kernel, el apagado automático al abrir el dispositivo de entrada está excluido para la Deck desde la versión 6.8. Lo que sí puede apagarlos es un programa que abra el mando por `hidraw` y se lo pida al firmware — Steam lo hace, y los juegos hechos con SDL también.

### Tus trackpads, no los de Steam

Lo anterior obliga a mantener pulsado OPCIONES, que es el gesto de Steam. WProton tiene los suyos, y los enciende y apaga cuando tú quieras: en *Runners y herramientas → **Trackpads de la Deck*** eliges qué pad mueve el puntero y a qué velocidad, y ya funciona sin ningún gesto previo.

Para eso WProton **le apaga al mando su emulación de ratón** mientras usa el pad, y **se la devuelve** al apagar la opción o al cerrar. No son registros inventados: son exactamente los dos comandos que manda el driver del kernel en `steam_set_lizard_mode()`, con los mismos valores y el mismo envoltorio (informe de característica de 65 bytes por `HIDIOCSFEATURE`, que es lo que el mando entiende; un `write()` normal manda un informe de salida y lo ignora).

```
apagar:   0x81                        (borrar las asignaciones de teclado/ratón)
          0x87 06 09 00 00 47 00 00   (modo lagarto = 0, watchdog = 0)
encender: 0x85  y  0x8E               (restaurar las de fábrica)
```

El watchdog se apaga porque es lo que hace el driver: sin eso, el firmware vuelve a encender su emulación al rato por su cuenta.

**Se devuelve siempre.** Al apagar la opción, al cerrar WProton y también si a WProton lo matan con una señal. Y hay red de seguridad doble: al cerrarse el descriptor, el propio driver del kernel vuelve a registrar el mando y restaura la emulación. Si aun así te quedan muertos —un corte de luz, un `kill -9`—, hay *Devolver los pads al mando ahora* en ese mismo menú, y mantener OPCIONES dos veces también lo arregla.

**Lo que cuesta, para que lo sepas:** mientras WProton lee el mando por `hidraw`, el driver retira el gamepad del sistema. Con Steam en marcha eso da igual, porque Steam ya lo tenía cogido y publica su propio mando virtual. Sin Steam, el mando desaparece para los juegos mientras el trackpad esté activo; queda dicho en el registro.

Si prefieres que WProton **no le escriba nada** al mando, en ese menú está *Quién manda en los pads*. Con esa opción en "el mando", WProton sólo lee —por el dispositivo de entrada del sistema, donde el pad izquierdo son los ejes `ABS_HAT0X/Y` y el derecho los `ABS_HAT1X/Y`, publicados desde el kernel 6.3— y entonces sí hace falta poner el mando en modo gamepad a mano.

**Y hay un diagnóstico que lo dice todo.** *Runners y herramientas → Trackpads de la Deck → Probar los trackpads* mira el parámetro del módulo, si existe el dispositivo con los pads, si otro programa tiene el `hidraw` cogido, y escucha unos segundos para saber en qué modo está el mando. Te dice en pantalla cuál de los casos es y qué hacer, y el detalle queda en el registro.

**Y se puede decidir por juego.** En *Ajustes del juego → Mandos → **Trackpad como ratón en este juego*** eliges si ese juego concreto usa un pad como puntero, cuál, o ninguno. Viene en *"lo que diga el ajuste general"*, así que no cambia nada hasta que lo tocas. Se aplica al lanzar y, al salir, vuelve a lo que diga el ajuste general — también si el juego falla al arrancar.

**¿Puedo lanzar los juegos desde Steam?**
Sí: *Ajustes de un juego → Añadir este juego a Steam*. Aparecerá en tu biblioteca como juego no-Steam, con su carátula. Hazlo con Steam cerrado.

Al añadirlo, WProton **descarga las carátulas de SteamGridDB** y pone las cuatro imágenes que usa la ficha de Steam: la vertical de la estantería, la apaisada de la cabecera, el fondo grande y el logotipo. Las dos primeras se guardan también en `covers/` y `covers_wide/`, así que sirven igual en la biblioteca de WProton. Si no tienes API key de SteamGridDB no se te pregunta nada en ese momento: el juego se añade con las carátulas que haya y el aviso del final te dice dónde se pone la clave.

**¿Y desde EmulationStation o DeckStation?**
Apunta el lanzador a `wproton.sh %ROM%`.

**El mando funciona en los menús pero no dentro del juego.**
Mira el ajuste *Mando vía SDL* del juego. En automático debería acertar, pero puedes forzarlo a ON (mandos de PlayStation) u OFF (mandos XInput).

**¿Se llenará la carpeta `logs/` de ficheros?**
No: WProton borra los registros que tengan más de dos días.

**Mi mando de PlayStation no responde (DualSense o DualShock 4).**
Desde GE-Proton 11-4 los mandos de Sony se leen por `/dev/hidraw`, y en muchos
sistemas esos dispositivos no son legibles por el usuario.

La forma cómoda: *Runners y herramientas → Arreglar permisos del mando*.
WProton deja el fichero preparado y te dice los comandos exactos para tu
sistema, que solo tienes que copiar en una terminal.

> Los comandos de abajo funcionan en cualquier terminal. Si en algún sitio ves
> instrucciones con `sudo tee ... <<'EOF'`, eso es sintaxis de **bash** y da un
> error de sintaxis en **fish**, que es el shell por defecto de CachyOS.

A mano, en una distribución normal:

```bash
sudo cp runtime/70-wproton-mandos.rules /etc/udev/rules.d/
sudo udevadm control --reload-rules && sudo udevadm trigger
```

**En SteamOS hay dos pasos más**, y son la causa habitual de que "el comando no
funcione": el sistema de ficheros es de solo lectura y hay que desbloquearlo,
y el usuario `deck` no trae contraseña de fábrica, así que `sudo` no puede
funcionar hasta que se crea una:

```bash
passwd                          # solo la primera vez, crea tu contraseña
sudo steamos-readonly disable
sudo cp runtime/70-wproton-mandos.rules /etc/udev/rules.d/
sudo udevadm control --reload-rules && sudo udevadm trigger
sudo steamos-readonly enable
```

Después, desconecta y vuelve a conectar el mando.

**El mando se ve pero el juego no responde a ningún botón.**
Puede ser el modo escritorio de Steam: ahí los botones mandan teclas, no
botones, así que un juego que espere un mando no recibe nada. Mantén pulsado
Start unos segundos para cambiarlo, o usa *Ajustes del juego → Mapeador .keys
→ Mando virtual → Traducir el modo escritorio de Steam*.

**El juego no hace caso a la cruceta, o mi mando le llega raro.**
En *Ajustes del juego → Mapeador .keys → Mando virtual*. WProton crea un mando
"de mentira" y le copia el tuyo. Empieza por **Mando Xbox**, que arregla los
mandos que llegan de forma rara sin cambiar nada más. Si el juego lee la
cruceta pero no la usa, prueba **+ cruceta al stick**. Y para juegos antiguos
que se aceleran solos, **Mando clásico**.

**Este juego apunta con el stick derecho y me iría mejor con el izquierdo.**
En *Ajustes del juego → Mapeador .keys → **Intercambiar los sticks***. El juego verá el stick izquierdo donde estaba el derecho y al revés, y el **clic de cada stick se va con el suyo** (si apuntas con el izquierdo, pulsarlo hace lo que antes hacía pulsar el derecho).

Esto no lo hace el mapeador de teclas —ése convierte el mando en pulsaciones—, sino el **mando virtual**, presentándole al juego otro mando con los sticks cambiados. Así que si lo tenías apagado se enciende solo, en modo copia, al lanzar ese juego: eso **captura el mando físico**, con lo que pierdes la vibración y el remapeado de Steam Input mientras juegas. Se combina con todo lo demás del mando virtual (Xbox, DualShock, clásico, cruceta al stick).

Si es lo **único** que activas, se guarda igual: el editor escribe el `.keys` con sólo esa opción (y la salida de emergencia Select+Start, que va siempre). Y si WProton no consigue capturar el mando físico —normalmente porque ya lo tiene cogido el mapeador, cuando el `.keys` mapea el movimiento— el intercambio **no funciona**, porque el juego sigue viendo el mando real con los sticks en su sitio; eso queda dicho en el registro con el motivo.

Se guarda **en el `.keys` del juego**, no en su perfil, por dos razones: es cosa de ese juego, y así viaja con él —un `.keys` de la comunidad puede traerlo ya puesto—. En el fichero es una sección propia de WProton que Batocera ignora:

```json
{ "sticks": { "swap": 1 } }
```

**Quiero que un juego responda a teclas concretas del teclado.**
En *Ajustes del juego → Mapeador .keys*.

Si el juego ya trae uno de Batocera, WProton lo encuentra solo, esté donde
esté: junto al `.wsquashfs` con el nombre del juego, o dentro de la carpeta
`.pc` llamado `padto.keys`. Lo que edites tú manda sobre los dos. Si el juego ya tiene un `.keys`, lo
primero que ofrece es **ver las teclas que tiene asignadas**, sin abrir el
fichero:

```
Ver las teclas asignadas  (4)

    Hotkey + Start             ->  Alt + F4
    A                          ->  Espacio
    L1                         ->  E
    Stick izq. arriba          ->  Flecha arriba
```

Si el `.keys` **sustituye al mando** —es decir, si asigna teclas al movimiento:
sticks, cruceta o gatillos— WProton captura el mando para que el juego solo vea
el teclado, que es lo que hace Batocera. Sin eso, un juego con soporte de mando
usa el mando e ignora las teclas.

Se decide solo mirando el fichero, así que normalmente no hay que tocar nada. Si
un juego concreto lo lleva mal, está en *Mapeador .keys → El juego NO ve el mando*, con tres opciones y una explicación de cada una.

> El ratón también funciona: si el `.keys` asigna un stick al ratón, WProton
> crea un ratón virtual, y los clics van por ahí, no por el teclado.

**Los tres botones del ratón.** En *Crear o editar las teclas → Ratón* se elige
qué botón del mando hace cada clic: el **izquierdo**, el **derecho** y el
**central**. El derecho hace falta en los juegos que lo usan para apuntar o para
recargar; los dos últimos se pueden dejar sin asignar, que es como vienen.

Funcionan igual si el botón elegido es un gatillo: en casi todos los mandos L2 y
R2 no mandan una pulsación sino un eje, y WProton lo traduce.

Y un clic se le puede colgar a cualquier botón **sin tocar el stick**: al asignar
una tecla, en *Botones del ratón*. Sirve aunque el puntero no se mueva —WProton
crea el ratón virtual igualmente—, así que vale para un juego que solo necesita
un clic derecho de vez en cuando.

**El teclado en pantalla** resuelve los juegos que te obligan a escribir un
nombre y no soportan mando: una combinación abre un teclado que se maneja con
la cruceta y A, y va escribiendo en el juego.

Se añade desde el editor, *Añadir: teclado en pantalla*, eligiendo la
combinación (Hotkey + X, L1 + R1…). Las que se ofrecen no chocan con la salida
de emergencia.

**Si el juego se minimiza al abrir el teclado**, usa *Añadir: escribir un
texto*. Guardas el texto (tu nombre) en los ajustes y una combinación lo
teclea dentro del juego, **sin abrir ninguna ventana**: así el juego no pierde
el foco. Opcionalmente pulsa Enter al terminar.

> La ñ y las vocales con tilde no se pueden escribir así: se mandan códigos de
> tecla y un teclado no tiene tecla para «ñ». Se avisa al guardar.

Si algún juego se pierde letras, sube `WP_TECLEO_MS` en `settings.conf` (60 por
defecto): es cuánto se mantiene pulsada cada tecla.

También se puede **usar el mando como ratón**: un stick mueve el puntero y un
botón hace clic. Va bien en juegos de estrategia, aventuras gráficas e
instaladores, que con el mando no se pueden ni empezar.

Para cambiarlas, *Crear o editar las teclas*. Salen
todos los botones del mando; eliges uno y le asignas su tecla. Se guarda solo
y se activa al lanzar el juego. La combinación **Select + Start** cierra el
juego siempre, aunque no la configures.

**Con un `.keys` los botones salen cambiados (disparo en B en vez de en A).**
Ese fichero se escribió con la convención de Batocera, que nombra los botones
al estilo Nintendo. En *Ajustes del juego → Mapeador .keys → Estilo de
botones*, cámbialo a **Nintendo / Batocera**.

**Mi mando iba bien con una versión anterior de GE-Proton.**
Prueba a poner *Mando via SDL* en **ON** en los ajustes de ese juego: hace que
el juego reciba el mando por SDL en vez de por la vía nueva, que es como
funcionaba antes.

**Mi mando de PlayStation ha dejado de funcionar tras actualizar GE-Proton.**
GE-Proton 11-4 rehízo el soporte de los mandos de Sony. Entra en los ajustes
del juego y prueba *Mando Sony (DualSense/DS4)*: normalmente lo arregla la
opción **como mando de Xbox**, y en juegos con soporte de DS4, **como
DualShock 4**.

Ojo: *Mando via SDL* y *Mando Sony* son incompatibles. Al elegir un modo Sony,
la primera se ignora automáticamente.

**Mis juegos están en otro disco y no aparecen.**
Entra en *Biblioteca y preferencias → Montar un disco*: te lista los que hay
sin montar y, al elegir uno, lo monta y te ofrece añadirlo como carpeta de
juegos. No hace falta contraseña.

Si el disco ya estaba configurado como carpeta de juegos, WProton lo detecta
al arrancar y te ofrece montarlo él solo.

**El juego se ha ido detrás de otra ventana y no puedo volver.**
Con el teclado, Alt+Tab. Si quieres hacerlo con el mando, crea el `.keys` de
ejemplo desde *Runners y herramientas* y cópialo junto al juego: trae
Select+Y para el Alt+Tab. No viene puesto de serie porque el mapeador crea un
teclado virtual durante la partida y algunos juegos se confunden al ver un
dispositivo nuevo.

Las combinaciones globales están en `runtime/wproton_global.keys` y se pueden
cambiar a mano. Si un juego tiene su propio `.keys`, ese tiene preferencia.

**En SteamOS me dice que evdev no compiló.**
SteamOS no trae las cabeceras del kernel, así que ese módulo no se puede
compilar ahí. WProton lo detecta y descarga la versión ya compilada, que
funciona igual. Si por lo que sea no lo consigue, prueba *Runners y
herramientas → Instalar evdev*, o copia una carpeta `evmapy/` con el módulo a
la raíz de WProton.

Cerrar el juego con el mando **no depende de eso**: WProton lee el mando
directamente y funciona igual.

**Se ve el puntero del ratón encima del juego.**
WProton lo esconde tras unos segundos sin mover el ratón y lo devuelve en
cuanto lo mueves. Se ajusta en *Preferencias → **Puntero mientras juegas***, o
con `OCULTAR_CURSOR`, `CURSOR_SEGUNDOS` y `CURSOR_UMBRAL` en `settings.conf`. Está contado con
detalle en las preguntas frecuentes.

**¿Cómo salgo de un juego que no tiene opción de salir?**
Mantén pulsado **Select** cinco segundos y WProton lo cierra. En la Steam
Deck también sirve el botón de Steam. Si prefieres otra cosa, puedes
desactivarlo con `PAD_EXIT=0` en `settings.conf`.

Si prefieres otra combinación, en `settings.conf`:

| `PAD_EXIT_COMBO` | Qué hay que mantener |
|---|---|
| `select` | Select (el de serie) |
| `l3r3` | Los dos sticks a la vez |
| `start` | Select + Start (en SteamOS choca con el cambio de modo del mando) |

Y `PAD_EXIT_SEGUNDOS` cambia cuánto hay que mantenerlo.

**Al moverme por los menús aparecen letras solas en el buscador.**
Es un mapeador `.keys` de una partida anterior que se quedó vivo y sigue
convirtiendo los botones del mando en teclas. Cierra WProton y vuelve a
abrirlo: al arrancar se limpian esos procesos. Mientras tanto, **B** borra lo
que se haya escrito.

**WProton se ha quedado en "Volviendo al menú..." y no reacciona.**
Algunos juegos dejan procesos colgados al cerrarse y WProton espera a que
terminen. A los 20 segundos te pregunta si quieres forzar el cierre; responde
que sí y volverás al menú.

Si aun así no reacciona, desde otra terminal:

```bash
./wproton.sh --kill
```

Eso detiene Wine y desmonta todo. Es seguro: las partidas guardadas no se
tocan.

**¿Cómo actualizo?**
*Buscar actualizaciones* en el menú principal, o `./wproton.sh --update`. Descarga la versión nueva, la valida y guarda la anterior como `.bak`.

---

## 13. Salir de un juego con el mando

Mantén **Select cinco segundos** durante la partida y el juego se cierra. Son
cinco y no dos a propósito: es una salida de emergencia y no debe dispararse
sin querer.

Sirve sobre todo en el escritorio, donde un juego sin opción de salir te deja
atrapado si no tienes el teclado a mano. En el modo Juego de la Deck también
funciona, aunque ahí está además el botón de Steam.

Se puede cambiar el tiempo y la combinación en `settings.conf`
(`PAD_EXIT_SEGUNDOS`, `PAD_EXIT_COMBO`: `select`, `l3r3` o `start`).

---

## 14. Actualizar WProton

![Lo que trae la versión instalada](img/novedades.png)

![Runners y herramientas](img/runners-herramientas.png)

Cuando hay versión nueva, **la fila del menú principal cambia de texto**:

```
Buscar actualizaciones [v1.55]      ->      *** ACTUALIZAR A v1.56 ***
```

No hay que entrar a comprobarlo. La consulta se hace en segundo plano al
arrancar, así que el menú nunca espera a la red; si aún no ha llegado la
respuesta, no avisa y ya lo hará en el siguiente arranque.

---

**Un juego se cierra al cargar un vídeo (intro, presentación…).**

Casi siempre es que falta el descodificador. WProton le presta al juego los plugins de GStreamer de un Proton que los traiga completos —`libgstlibav` es el que sabe de WMV, H.264 y compañía— y le presta **las dos arquitecturas del mismo paquete**, 32 bits primero.

**Y hay una cosa que conviene saber, porque explica casi todos estos casos: Proton no trae descodificador de H.264.** Valve no distribuye descodificadores de formatos con patentes; en Proton, FFmpeg va compilado con todo desactivado y el H.264 lo aporta **el propio Steam**. Fuera de Steam no hay quien lo ponga, así que tiene que venir **del sistema** (el paquete `gst-libav`) o **de un pack de códecs** tuyo. Por eso **el Proton que elijas no cambia nada**: ninguno lo trae. Y que el runner tenga el fichero `libgstlibav.so` tampoco significa que sepa descodificar: puede estar ahí y venir vacío.

WProton lo comprueba de verdad y lo dice en el registro:

| Línea del registro | Qué significa |
|---|---|
| `Video H.264: disponible, lo aporta …` | Hay descodificador. Si el vídeo falla, no es por falta de códec |
| `Video H.264: NO HAY DESCODIFICADOR…` | **Es esto.** Un vídeo H.264 no se va a poder cargar |
| `H.264: NO en … (libavcodec… compilada sin H.264)` | Ese paquete tiene el fichero pero viene sin el códec dentro |
| `conversor de Proton apartado` | Normal y bueno: ver abajo |

Entre varios paquetes, WProton **prefiere el que sí sabe de H.264**, y si ninguno sabe elige el mismo de siempre. Busca también en el **Steam Linux Runtime**, que en una Steam Deck está instalado siempre y es un contenedor completo: muchas veces el descodificador que falta ya está en el disco.

**El conversor de Proton.** Dentro de Steam, los formatos con patentes no se descodifican: el cliente baja una versión **ya convertida** del vídeo y un conversor (`protonvideoconverter`) la sirve, con prioridad por delante de los descodificadores de verdad. Fuera de Steam ese conversor no puede funcionar —no hay vídeo convertido— pero sigue yendo primero y **tapa al bueno**. WProton lo aparta solo cuando lo encuentra. Si quieres decidir tú, pon `GST_PLUGIN_FEATURE_RANK` en los argumentos de lanzamiento y WProton respeta lo tuyo.

Si esto te pasa **en una Steam Deck pero no en un PC de escritorio**, el motivo es ese: en una distro de escritorio el sistema suele tener `gst-libav`, y en SteamOS el GStreamer del sistema es mucho más corto.

En el registro, la línea `GST_PLUGIN_PATH=` dice exactamente qué carpetas se van a usar, y justo después si **el runner aporta las suyas** o solo hay las del sistema. Si ves muchas líneas de `wrong ELF class: ELFCLASS32`, son plugins de 32 que el juego de 64 no puede usar: es ruido, no la avería, siempre que la carpeta de 64 también esté en la lista.

**Si el juego es de Unity y se cierra solo, no hace falta activar nada.** WProton busca el `Player.log` que el juego escribe dentro del prefijo, pega sus últimas líneas en el registro y, si ahí dentro pone que no pudo descodificar el vídeo, lo traduce al salir: la línea del juego, el formato (`H264`, `WMV`…) y si en ese arranque había descodificador o no. Con `DIAG_VIDEO=1` en `settings.conf` queda además todo el camino apuntado y al salir se resumen las cinco causas de que un vídeo no se vea, incluida la de **Media Foundation**, que es por donde van los vídeos de Unity y Unreal.

**Un juego de Linux (nativo) no llega a arrancar.**

El registro lo cuenta solo. Para un juego nativo, WProton apunta ahora **lo que escribió el juego** (su salida y sus errores, en un bloque aparte), **el código de salida del lanzador y cuánto vivió**, y su **`Player.log`** si es de Unity —que en Linux va a `$XDG_CONFIG_HOME/unity3d/<empresa>/<juego>/`, dentro de la carpeta portátil que le da WProton—.

Lo primero que hay que mirar, por este orden:

| Línea del registro | Qué significa |
|---|---|
| `el lanzador salio con codigo 0 tras 0s` + `procesos usando la carpeta al empezar: 0` | El lanzador no arrancó nada. Sigue leyendo su salida |
| `el juego no escribio NADA por su salida ni por sus errores` | Se murió sin hablar: mira el `Player.log` y las variables de Steam |
| `AL JUEGO LE FALTA UNA LIBRERIA DEL SISTEMA: …` | Copia ese `.so` a una carpeta `lib/` dentro del juego y vuelve a empaquetarlo |
| `el juego declara SteamAppId=…` | El juego espera que **Steam esté en marcha** |
| `heredado de Steam -> SteamAppId=…` | El identificador que le llega de fuera |
| `…NO es de este juego; se le pone el suyo` | WProton lo ha corregido: ver abajo |

**El identificador de Steam que no era suyo.** Esta era la causa de un cuelgue que costó lo suyo encontrar, y conviene entenderla. Si añades WProton a Steam, en el modo Juego lo arranca Steam, y sus variables —`SteamAppId`, `SteamOverlayGameId`, `LD_PRELOAD` con su capa de superposición— **las hereda el juego que lances**. Un juego nativo comprado en Steam lee justo `SteamAppId` para inicializar Steamworks: si le llega el identificador del **atajo de WProton** en lugar del suyo, responde `Invalid APPID`, Steamworks no arranca y el juego se cae con un SIGSEGV. El mismo juego lanzado desde Steam ve su identificador de verdad y funciona.

WProton lo corrige solo: compara lo que hereda con lo que el juego declara —en su lanzador o en su `steam_appid.txt`— y le pone el suyo; si no se sabe cuál es, le quita el ajeno y el juego se apaña con su `steam_appid.txt`, que es de donde debería haberlo sacado. **No hay nada que configurar.** Lo que no se toca es la superposición (`SteamOverlayGameId` y `LD_PRELOAD`), que son otras variables y siguen funcionando. Para quitarlo todo está *Casos especiales → Superposición de Steam → oculto*.

**La carpeta personal de un juego de Linux.** Un juego nativo no usa prefijo de Wine, pero sus ajustes y sus partidas tienen que ir a alguna parte, y van a una carpeta de WProton, no a la tuya. En **Ajustes del juego → Carpeta personal del juego** eliges `compartida` (`WProton.home`, para todos) o `propia` (`<juego>.home`, aislada). Si el juego trae su propia carpeta `.home` al lado del lanzador, manda esa y este ajuste no se usa.

**Un juego con un lanzador que hay que pulsar con el ratón.** En el modo Juego no hay ratón ni teclado, así que un lanzador con un botón *Play* no se puede usar. La solución está en **Ajustes del juego → Casos especiales → El mando como ratón (lanzadores)**: el stick **derecho** mueve el puntero, **A** o **R2** hacen el clic izquierdo y **B** el derecho (los dos, para no tener que acordarse de cuál).

> Ojo, que se parecen y no son lo mismo: el **mando virtual** crea un *mando*, para juegos que no ven el de la Deck. Esto crea un *puntero*. Si lo que no puedes es pulsar un botón en pantalla, lo que necesitas es esto.

Si el juego ya tenía teclas configuradas, se le añade solo el ratón y las teclas se conservan. Para afinarlo —cambiar de stick, la velocidad o los botones de clic— está *Teclas del mando → Ratón con el mando*.

> **En el modo Juego el puntero no sale de donde crees, y conviene saberlo.** Con **Steam Input activo** —que es lo normal para un atajo lanzado desde el modo Juego— los trackpads **no son un ratón**: los coge Steam y los reparte según la disposición del mando del atajo, que de fábrica es *Gamepad* y no trae puntero. En el escritorio sí lo son, por el modo lagarto, y por eso el mismo lanzador se deja pulsar allí y aquí no. Las dos salidas: usar el **stick como ratón** (*Casos especiales → El mando como ratón*), o cambiar la disposición del mando en Steam por una que ponga el ratón en el trackpad derecho. WProton lo apunta en el registro al lanzar, para no tener que compararlo a mano.

> **Si el puntero se va solo a una esquina**, es que ese mando no descansa en cero. WProton le pregunta al mando su zona muerta y aprende el reposo del primer valor que manda el stick, así que no debería pasar; si pasa, el registro lo dice con todas las letras: `[keys] Raton ABS_RX: reposo 9257, recorrido 32767, zona muerta 3932` y, cada dos segundos, cuánto se ha movido el puntero y con qué valores del stick.

**Y lo primero que hay que probar si en Steam arranca y aquí no:**

**Ajustes del juego → Casos especiales → Runtime de Steam (juegos de Linux)**

Un juego nativo moderno puede pedir librerías más nuevas que las del sistema, y en SteamOS no se puede instalar nada en la imagen base. Steam lo resuelve lanzando el juego **dentro de un contenedor** —el *Steam Linux Runtime*—, con su propio juego de librerías. Eso es lo que hace que el mismo juego vaya en Steam y no lanzado directamente. Las opciones son `no` (como siempre), `automático` (el más nuevo instalado) o una versión: **4.0** (la más nueva, Debian 13), 3.0 (*sniper*), 2.0 (*soldier*), 1.0 (*scout*).

Si la fila dice **`NO está instalado`**, se instala desde Steam: en la Biblioteca, busca *Steam Linux Runtime* y dale a instalar. El juego se lanzaría igual, pero sin contenedor, y el registro lo avisa. Si tu juego está **fuera de tu carpeta personal** —en la tarjeta SD, por ejemplo— WProton lo monta dentro del contenedor solo; sin eso, ahí dentro el juego no existiría.

WProton también lo sugiere por su cuenta: si un juego de Linux dura menos de doce segundos, no se estaba usando contenedor y hay uno instalado, lo dice al salir.

Esa última fila de la tabla es la que conviene entender. Si añades WProton a Steam, en el modo Juego lo arranca Steam, y sus variables (`SteamAppId`, `SteamOverlayGameId`, `LD_PRELOAD` con su capa de superposición) **las hereda el juego que lances**. Un juego nativo comprado en Steam mira justo esas: si le llega el identificador del atajo de WProton en lugar del suyo, su `steam_api` se inicializa contra el juego equivocado. WProton no cambia ninguna —solo las escribe, al lado de lo que el lanzador declara, para que se puedan comparar—.

**El teclado en pantalla tiene dos distribuciones.** Para **buscar** un juego salen solo letras y números: son menos teclas y cada una está a un paso del mando. Para **escribir texto** —argumentos de lanzamiento, DLL overrides, notas— sale un teclado completo con minúsculas, símbolos (`= % : / \ " | + * @ # $ &`) y una tecla de **mayúsculas** que se queda encendida mientras lo está. Así se puede pegar una línea de ProtonDB tal cual, con su `%command%` incluido. Escribiendo texto, la **Y** acepta lo escrito; buscando, cierra el teclado.

## 15. Llamar a WProton desde la línea de órdenes

Está pensado para frontends —DeckStation lo usa así— y para automatizar cosas.
Todas las rutas admiten **espacios sin comillas internas**: WProton junta los
argumentos que le llegan.

| Orden | Qué hace |
|---|---|
| `./wproton.sh` | Abre el menú normal |
| `./wproton.sh <juego>` | Lanza ese juego: `.wsquashfs`, carpeta, `.exe`, `.sh`, `.AppImage`, `.zip`/`.7z`/`.rar` |
| `./wproton.sh --config <juego>` | Abre *Ajustes del juego* para ese juego |
| `./wproton.sh --exe <juego.wsquashfs>` | Lanza eligiendo el ejecutable a mano |
| `./wproton.sh --saves <juego>` | Abre el gestor de **partidas guardadas** de ese juego, sin lanzarlo |
| `./wproton.sh --keys <juego>` | Abre el **editor de teclas del mando** de ese juego, sin lanzarlo |
| `./wproton.sh --import <exe\|carpeta\|zip>` | Fuerza el flujo de importar/empaquetar |
| `./wproton.sh --play` | Modo "solo jugar" |
| `./wproton.sh --menu` | Menú completo (salida de emergencia del modo solo-jugar) |
| `./wproton.sh --update` | Busca e instala una versión nueva de WProton |
| `./wproton.sh --kill` | Cierra todo lo de WProton |
| `./wproton.sh --version` | Dice la versión |

**Un juego puede ser un fichero o una carpeta**, y eso vale en todas partes:
`--config` acepta igual un `.wsquashfs` que un directorio `.pc` de los de
Batocera. Si una ruta no existe, el error lo dice y no se abre nada.

**Desde un frontend (ES-DE, DeckStation).** `--saves` está pensado para ser un
lanzador más en ES-DE, junto a los dos que ya se usan para jugar:

```xml
<command label="WProton (Launch Direct)">./Apps/WProton/wproton.sh %ROM%</command>
<command label="WProton (Launch WithMenu)">./Apps/WProton/wproton.sh --config %ROM%</command>
<command label="WProton (Saved Games)">./Apps/WProton/wproton.sh --saves %ROM%</command>
<command label="WProton (Keys Games)">./Apps/WProton/wproton.sh --keys %ROM%</command>
```

El juego no se nombra en ningún sitio: `%ROM%` es el marcador de ES-DE, así que
la misma línea vale para todos los juegos y la carpeta se puede mover sin
tocar nada. No es un menú nuevo, es el mismo *Partidas guardadas de [juego]*
que ya está en *Ajustes del juego*.

## 16. Dónde está cada cosa

| Carpeta | Contiene |
|---|---|
| `games/` | Tus juegos empaquetados |
| `profiles/` | La configuración de cada juego |
| `comunidad/` | Copia de los perfiles del repositorio, si la has pedido |
| `wsquashfs/overlays/` | **Tus partidas** |
| `prefixes/` | Los prefijos de Wine |
| `backups/` | Copias de partidas y de tu configuración |
| `covers/` | Carátulas |
| `metadata/` | Fichas de Steam y duraciones (se llamaba `datos`) |
| `runtime/` | Python, runners y herramientas |
| `logs/` | Registros (se limpian solos) |
| `lang/` | Idiomas |

Los ajustes generales están en `settings.conf`, que es un fichero de texto normal y corriente, comentado, por si prefieres editarlo a mano.

---

## Gracias

Esta es la primera versión de WProton lista para el público general, y no habría
llegado aquí sola.

**Muchas gracias a Michel, Fransis y MRDeu** por todas las horas de testeo que
habéis metido a WProton: por probarlo una y otra vez, por los registros a las
tantas y por encontrar los fallos que en el equipo de uno nunca aparecen. Sin
vosotros este proyecto no habría sido posible.

---

## Licencia

WProton es software libre bajo la **GPL-3.0 o posterior**. Puedes usarlo,
estudiarlo, modificarlo y compartirlo; si distribuyes una versión modificada,
tiene que ir con la misma licencia y con su código fuente.

El texto completo está en el fichero `LICENSE` del proyecto.
