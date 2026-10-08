# WProton 2.0 — novedades

**La 2.0 es la primera version pensada para todo el mundo**, no solo para quien
estaba probando. Recoge el trabajo de las versiones 1.7x, que circularon entre
testers: desde el raton en los menus hasta las caratulas 4:3, pasando por una
larga lista de juegos que antes no arrancaban y ahora si.

> **Muchas gracias a Michel, Fransis y MRDeu** por todas las horas de testeo que
> habeis metido a WProton. Sin vosotros este proyecto no habria sido posible.

Si vienes de una 1.7x, lo que sigue ya lo conoces. Si llegas ahora, lo unico
que hace falta saber esta en la **Guia de uso**; esto es el detalle.

---

## Arreglos salidos de las capturas del manual

Cinco cosas que no se ven leyendo el codigo y si en una captura:

- **"Caratula 4:3" se pintaba como "Caratula 4: 3".** Las filas de menu se
  colorean partiendo por "etiqueta: valor", y los dos puntos de una proporcion
  se tomaban por el separador. Ya habia una excepcion para los parentesis
  -"(2:3)"- pero no cubria un "4:3" suelto. Ahora la regla es la de verdad:
  unos dos puntos ENTRE NUMEROS son una proporcion o una hora, nunca un
  separador. Arreglado en los dos motores de menu (pygame y Qt).
- **La ayuda de "Descargar caratulas" seguia diciendo que todo venia de
  SteamGridDB** y que hacia falta una clave. Ahora cuenta lo que hay: las 4:3
  del repositorio y sin clave, las otras dos de SteamGridDB.
- **En NOVEDADES, un punto partido a mano en dos lineas salia como dos filas**,
  y la segunda ("el suyo.") quedaba suelta. Cada punto va ahora en una linea.
- **El mensaje de "Perfil creado" del asistente ocupaba tres filas para una
  sola frase**, cortada en un ":" y en una coma. Ahora es una linea entera.
- **Una novedad que llevaba dos puntos se pintaba como si fuera un ajuste**,
  con media frase en color de etiqueta. Reescrita sin ellos.

## Arreglado: "creas las teclas y luego dice que el juego no tiene ninguna"

Un tester lo describio asi: *"si le creas las keys desde WProton te las crea
bien en la carpeta, pero despues, si vas a editarlas, te dice que no tiene keys,
y el archivo esta"*. Y no era solo el mensaje: el mapeador tampoco las cargaba,
asi que el juego se quedaba sin teclas de verdad.

Pasaba al usar **Asignar fichero .keys**, que es como se reaprovechan las teclas
de otro juego (coger las de The Walking Dead y ponerlas en otro). La copia se
quedaba con la marca del juego de origen, asi que WProton la veia como "de otro
juego" y la ignoraba... con el fichero recien puesto en `profiles/` y el mensaje
de "Asignado" dado. Dos cambios:

- **Al asignar un fichero, la copia pasa a ser de este juego.** Asignarlo es
  justamente decir eso. El original no se toca, y el dialogo avisa de a quien
  pertenecia antes.
- **Un `.keys` que esta en `profiles/` con el nombre del juego es de ese juego**,
  diga lo que diga su marca: ahi solo llega lo que ponemos nosotros o lo que el
  usuario pone a proposito. La marca sigue mandando donde se gano el sueldo
  -los ficheros que aparecen junto al juego o por sus carpetas-, que es de donde
  vino el problema de los controles de Halo.

De paso, en ese mismo menu:

- **El submenu del mapeador ya no se cierra en cada opcion.** Antes, tras crear
  el `.keys`, habia que salir y volver a entrar para ver que existia; mientras
  tanto el titulo seguia diciendo "ninguno" y parecia que no se habia guardado.
- **Quitado un fallo latente**: el titulo del submenu leia una variable de otro
  menu. Mientras se llegara desde los ajustes del juego funcionaba de milagro;
  desde cualquier otro sitio, con `set -u`, habria matado el script. Es el mismo
  fallo que cerraba WProton en el modo Juego de la Deck.
- **Los `.keys` que una version intermedia dejo ilegibles ya no pierden su dueño al repararse.**
  Habia dos versiones de esa reparacion en el codigo y la que corria era la que
  tiraba la linea sin guardar el nombre del juego.

## Las caratulas 4:3 las trae WProton, no SteamGridDB

Las 4:3 ahora salen de la carpeta `covers_43/` del repositorio de WProton, ya
recortadas a 640x480. La primera vez que cargas un juego, WProton mira si hay
una con su nombre y la baja sin preguntar nada: una caratula no cambia en nada
como se juega, y un dialogo justo antes de arrancar el juego no lo quiere nadie.
Si ya tenias una 4:3 puesta, no se toca.

El nombre del fichero del repositorio y el de tu juego no tienen que coincidir
exactamente: se comparan sin mayusculas ni separadores, y se admite la coletilla
de version o de grupo de las descargas. Asi `covers_43/Rave Racer.jpg` vale para
un `Rave_Racer.wsquashfs`. La caratula se guarda con EL NOMBRE DE TU JUEGO, no
con el del repositorio.

- En los ajustes de cada juego, *Caratula y ficha*: **Caratula 4:3: descargarla
  del repositorio de WProton**. Consulta la lista recien traida, por si la han
  subido hoy.
- En *Biblioteca y preferencias*, **Descargar caratulas**: la opcion de las 4:3
  ya no va a SteamGridDB. Y si solo pides esas, **no se te pide ninguna API
  key**: antes se pedia siempre, aunque no se fuera a usar.
- Lo descargado se comprueba: si GitHub devuelve una pagina de error en vez de
  la imagen, se descarta en vez de dejarte una caratula rota.

Por que: casi ningun juego tiene la forma 4:3 en SteamGridDB, y lo que devolvia
era una captura recortada a lo bruto.

## WProton arranca ya configurado

De fabrica: menu **moderno**, vista de **lista** y caratulas **4:3**. Antes la
vista de lista venia con la caratula vertical, que depende de que el usuario se
saque una clave de SteamGridDB: recien instalado, casi nadie veia ninguna
caratula. Las 4:3 vienen del repositorio, asi que ahora se ven desde el primer
momento. Todo se cambia en *Biblioteca y preferencias* y queda guardado; a quien
ya tenga su `settings.conf` no se le toca nada.

## Mejoras en la carga y compresion de juegos Linux

- Los `.sh` y `.AppImage` se detectan y lanzan tambien dentro de un
  `.wsquashfs`, y un AppImage ya no necesita traer el permiso de ejecucion.
- Se espera a que el juego termine de verdad: un lanzador `.sh` acaba en medio
  segundo y antes se desmontaba el archivo con el juego arrancando.
- Mantener Select cierra los juegos de Linux, tambien los que arrancan algo
  fuera de su carpeta.
- Se respeta la carpeta personal que traiga el juego (`.home`, incluido el
  convenio de AppImage).
- Al empaquetar, se recogen solas las librerias que el juego necesita y que no
  pone cualquier equipo, y se avisa si piden una glibc mas moderna que la del
  equipo donde vas a jugar.
- Arrancar en el modo Juego de la Deck es mas rapido: los diagnosticos ya no se
  hacen esperar al juego.

## Mejoras en el movimiento del raton

Mover el puntero selecciona, el clic izquierdo entra, el derecho abre los
ajustes del juego, y la rueda sube y baja media pantalla por golpe. Cuando la
lista no cabe salen flechas arriba y abajo. El puntero es morado y se esconde
solo cuando no se usa.

## Las teclas del mando ya no se aplican a un juego que no es el suyo

Cada `.keys` lleva ahora escrito a que juego pertenece. Antes se deducia de
donde estaba el fichero, y un comodin de Batocera puesto en una carpeta de
arriba acababa aplicandose a un juego cualquiera: el mando mandaba pulsaciones
de teclado y los controles no respondian.

Ahora solo se usa el que es de ese juego, o el que este dentro de su carpeta.
Lo que haya en carpetas superiores se ignora.

## El paquete se guarda en la carpeta de juegos de la que salio

Con varias carpetas configuradas, el `.wsquashfs` se queda en la misma de la
que salio el juego, no siempre en la principal. Si el juego no esta en ninguna,
se pregunta, mostrando el espacio libre de cada una.

## Raton para moverse por los menus

Mover el puntero selecciona la fila de debajo, el clic izquierdo entra, el
derecho abre los ajustes del juego en la lista de juegos (y vuelve atras en el
resto), y la rueda sube y baja media pantalla por golpe. El puntero se esconde
solo cuando no se usa. Se apaga con `RATON_MENUS=0`.

## Mejoras en la carga de ficheros sh y AppImage

- Los `.sh` y `.AppImage` sueltos salen en la biblioteca, y dentro de un
  `.wsquashfs` se detectan y se lanzan.
- Un AppImage ya no necesita traer el permiso de ejecucion puesto.
- Se respeta la carpeta personal que traiga el juego: `<lanzador>.home`,
  cualquier `*.home` que haya al lado -que es como se llama cuando un `.sh`
  invoca a un AppImage con otro nombre- o una `.home` en la raiz.
- Se espera a que el juego termine de verdad: un lanzador `.sh` acaba en medio
  segundo y antes se desmontaba el archivo con el juego arrancando.
- Corregido un fallo que cerraba WProton al lanzar un juego de Linux en el modo
  Juego de SteamOS.

## Copia de backups de juegos entre dos equipos de la misma red

Un equipo comparte sus copias y otro se trae las que le falten, con la direccion
elegida por el usuario y sin pisar nunca una copia mas nueva. Los equipos se
pueden guardar con un nombre para no volver a escribir la IP ni el codigo. Y hay
un modo servidor permanente para el equipo que mas tiempo este encendido.

## Los ficheros .keys soportan teclado y raton a la vez

Un `.keys` puede pedir un clic con `"type": "key"` y `"target": "BTN_LEFT"`, sin
bloque `mouse`. Eso no creaba el raton virtual, asi que las teclas funcionaban y
los clics no. Ahora el raton se crea en cuanto alguna tecla, direccion o
combinacion apunta a un boton de raton.

## Corregido un fallo al restaurar copias de seguridad

El manifiesto de la copia guardaba rutas absolutas del equipo donde se hizo, asi
que al restaurar en otro se copiaban las partidas a un arbol vacio que el juego
no mira, y la restauracion decia que habia ido bien. Ahora la ruta se rehace
para el equipo actual, y sirve con las copias ya hechas.

## "Buscar actualizaciones" cuenta que trae la version

Cuando WProton ya esta al dia, ese hueco decia solo "WProton esta al dia". Ahora
enseña las novedades de la version: quien entra ahi es justo quien quiere
saberlo. El texto vive en `novedades_texto`, asi que en cada version se cambia
en un sitio.

## Un prefijo hecho en otro equipo ya vale aqui

Empaquetar un juego con su prefijo en un equipo y jugarlo en otro fallaba: el
prefijo guarda medio Windows como ENLACES al runner, con rutas absolutas del
equipo de origen, y al traerlo wineboot chocaba con ellos y el juego no
arrancaba (`error=80`, que es ERROR_FILE_EXISTS: un enlace colgado sigue
"existiendo" para quien intenta crear el fichero encima).

Ahora el archivo **nace portatil**: al empaquetar se le quitan al prefijo las
rutas del equipo donde se hizo, y `dosdevices` se rehace en relativo. La misma
limpieza se aplica al usarlo, para los archivos ya hechos con versiones
anteriores.

Y no basta con quitar los enlaces: al hacerlo el prefijo se queda sin
`kernel32.dll` y wineboot ni arranca. Quien sabe reponer eso es Proton, que
rehace el prefijo cuando la version no le cuadra, asi que **al quitar enlaces se
borra la marca de version** y Proton lo reconstruye. Cuesta un arranque mas
lento la primera vez.

**Solo se toca `drive_c/windows` y `dosdevices`.** El resto del prefijo no se
mira: ahi hay enlaces que WProton pone a proposito -`AppData` apunta al archivo
montado para no duplicar cientos de megas- y tocarlos deja el juego arrancando
pero sin sus datos.

## Wine y UMU-Proton al dia con una pulsacion

Junto a *Actualizar GE-Proton a la última* hay ahora dos filas mas en *Runners y
herramientas*:

- **Actualizar Wine a la última** — el Kron4ek mas reciente, variante
  `staging-amd64-wow64`: staging trae mas arreglos que el vanilla, y wow64 no
  necesita librerias de 32 bits, que es justo lo que no se puede instalar en una
  SteamOS inmutable. Quien quiera otra variante las tiene todas en el menu de
  Wine Kron4ek.
- **Actualizar UMU-Proton a la última** — el de Open Wine Components.

**GE-Proton sigue siendo el runner por defecto.** Esto no cambia con que se
lanzan los juegos: solo permite tener los otros dos al dia sin buscarlos.

Las tres van juntas en **Actualizar a la última versión >>**, y cada fila dice
que version tienes ya instalada:

```
GE-Proton    (el runner por defecto)   [GE-Proton11-6]
Wine         (Kron4ek staging wow64)   [wine-11.13-staging-amd64-wow64]
UMU-Proton   (Open Wine Components)    [no instalado]
```

Por dentro es una sola funcion con tres clases (`ge`, `umu`, `wine`) en vez de
tres copias: lo unico que cambia es el repositorio, el patron del fichero y el
nombre. Tres copias habrian significado tres sitios donde arreglar el mismo
fallo de descarga.

## El menu del juego, ordenado

Se habia convertido en un cajon de sastre. Tres agrupaciones:

- **Mandos >>** — SDL/hidraw, puente Steam Input a XInput, mando Sony, mando
  virtual y escribir SDL en el registro del prefijo. Estaban desperdigadas
  entre las caratulas y el acceso directo.
- **Protonfixes / UMU >>** — el GAMEID y la busqueda en la base de umu, que son
  la misma tarea en dos pasos.
- **Carátula y ficha >>** — las dos caratulas, la ficha del juego, las notas y
  las estadisticas. Ninguna cambia COMO SE EJECUTA el juego, que es para lo que
  se entra ahi casi siempre, asi que estaban de por medio. *Favorito* y
  *Completado* se quedan fuera: son interruptores de una pulsacion.
- **Archivo y mantenimiento >>** — copias de partidas, comprobar el archivo,
  acceso directo, repetir el asistente, borrar saves del overlay y borrar la
  configuracion: cosas de una vez cada muchos meses que estaban entre las de uso
  diario. Las dos de **empaquetar** se quedan fuera: son el paso final de
  preparar un juego y esconderlas ahi seria enterrarlas.
- El **Mapeador .keys** se queda fuera a proposito: convertir el mando en
  pulsaciones de teclado es otra cosa que elegir como se lee el mando.

Y dos que estaban donde nadie las buscaria: el **mando virtual**, metido dentro
del Mapeador .keys (tenia sentido cuando solo se usaba con un fichero de teclas,
ya no), y **Volver a instalar lo que trae el juego (.bat)**, que no pinta nada
ahi; ahora esta en *Archivo y mantenimiento*, que es donde encaja por lo poco que
se usa.

Las dos de empaquetar van ahora **juntas** en el menu principal. Recuerda que
*EMPAQUETAR A WSQUASHFS* solo sale si el juego esta en carpeta: si ya es un
`.wsquashfs` no hay nada que convertir.

El menu principal pasa de **33 filas a 21**, y cinco de ellas son puertas a
submenus en vez de ajustes sueltos.

## Los mandos se identifican preguntandole a udev

Como hace RetroArch con su driver `udev`, que es el de referencia en Linux: el
sistema ya ha clasificado cada dispositivo y lo deja etiquetado con
`ID_INPUT_JOYSTICK` y con `ID_INPUT_JOYSTICK_INTEGRATION`, que ademas dice si el
mando es el de la propia consola o uno externo. En el registro:

```
mando 1: "Microsoft X-Box 360 pad 0"  [28de:11ff] (integrado)
mando 2: "8BitDo Ultimate 2C"         [2dc8:301c] (externo)
```

Antes se deducia de un "js" en Handlers y de /devices/virtual/ en el Sysfs.
Funcionaba, pero eran heuristicas nuestras. Si no hay `udevadm` se sigue con
ellas: es informacion mejor, no una dependencia nueva.

## Y que un juego use siempre el mas nuevo

Al elegir el runner de un juego hay dos opciones nuevas junto a la de siempre:
**(siempre el ultimo Wine instalado)** y **(siempre el ultimo UMU-Proton
instalado)**.

Elegir una version concreta ata el perfil a ella: en tres meses esta vieja y hay
que volver a entrar juego por juego. Con estas, al bajar una version nueva los
juegos la cogen solos.

Si eliges una familia que no tienes instalada se te dice EN ESE MOMENTO, no al
lanzar, y el juego tira del ultimo GE-Proton hasta que bajes uno.

Versión de correcciones. Tres fallos que **cerraban o colgaban WProton**, más
la paridad pendiente entre juegos en imagen y juegos en carpeta.

## Se cerraba solo al lanzar cualquier juego

`MANGOHUD` y `DXVK_ASYNC` se llaman igual como campo del perfil y como variable
de entorno. Al apagarlas, `export_game_env` hacía `unset MANGOHUD`, que no
quitaba una variable del entorno: **borraba el campo del perfil**. Catorce
líneas después `build_runner_cmd` lo leía sin proteger y, con `set -u`, eso mata
bash. Pasaba con MangoHud apagado —o sea, casi siempre— y por los dos caminos,
también con los `.wsquashfs`.

Ahora se usa `export -n`: fuera del entorno del juego, pero el valor se queda
para los menús y el lanzamiento siguiente.

## Se cerraba solo al abrir winecfg, winetricks o el escritorio virtual

Cuatro piezas del lanzamiento de un juego habían acabado dentro de
`run_in_prefix`, que es la función que abre las herramientas del prefijo y la
que usan los instaladores de dependencias. Leían un ejecutable que esa función
no tiene, y con `set -u` eso cierra WProton en seco. También afectaba a los
`.wsquashfs` con carpeta `dependencies/`.

De paso, esto explica por qué el **escritorio virtual** no se había podido
probar nunca: pasa por ahí.

## El prefijo de TeknoParrot se quedaba colgado con runners Wine

Los juegos en carpeta no cerraban el wineserver al terminar, así que dejaban
procesos vivos en un prefijo que además comparten. Al siguiente lanzamiento con
un runner Wine, `wineboot -u` sobre ese prefijo ocupado por un wineserver de
otra versión se colgaba, y como la marca sólo se escribía al final, se repetía
en cada intento.

Ahora `wineserver_cerrar_prefijo` es una sola función que llaman los dos
caminos, se cierra el prefijo antes de tocarlo, y los plazos se respetan de
verdad: si se agotan se avisa y **no** se da el prefijo por bueno. Ajustables
con `WP_WINESERVER_TIMEOUT` (20 s) y `WP_WINEBOOT_TIMEOUT` (180 s).

## En el modo Juego, Steam vuelve a ver el juego

WProton quitaba entera la variable `LD_PRELOAD` del juego para no llenar el
registro de `wrong ELF class`. Ese ruido es normal —Steam pone las rutas de 32 y
de 64 bits a la vez y `ld.so` descarta la que no toca—, pero quitarla dejaba a
Steam sin su `gameoverlayrenderer.so`: en el menú de Steam salía solo «WProton»
y no la fila del juego, así que **no se podía cerrar desde ahí**, y Steam Input
se quedaba a medias.

Y hay un cuarto modo, **Ocultar el juego a Steam**: además de la superposición
le quita la identidad de Steam (`SteamAppId`, `SteamGameId`…), que es lo que de
verdad ata la ventana del juego a una aplicación de Steam. Con eso, en el menú
de Steam solo sale WProton, y *Salir del juego* actúa sobre WProton, que cierra
el juego y hace el fin de partida completo. A cambio, no hay superposición ni
Steam Input.

Ahora se deja puesta, y se decide **por juego** en *Ajustes del juego → Casos
especiales → Superposición de Steam*: automático, puesta o quitada. Va por juego
porque hay lanzadores que se cierran al leer lo que otros programas les escriben
en la salida, y un interruptor general obligaría a elegir entre ese juego y
todos los demás.

Campo nuevo del perfil, `STEAM_OVERLAY` (57 campos en total). Los perfiles de
1.66 se leen igual: lo que no traen sale en «automático».

## Cerrar el juego desde el menú de Steam

En el modo Juego, *Salir del juego* no hacía nada, y el motivo no era Steam.
WProton ignora las señales de cierre durante la partida porque Steam manda un
`TERM` **al cerrarse la ventana de WProton** para dejar paso al juego, y
atender ése desmontaba el `.wsquashfs` con el juego dentro. Pero la señal que
manda Steam cuando pulsas *Salir del juego* es la misma, así que también se
ignoraba: el botón funcionaba, el que no hacía nada era WProton.

Ahora se distinguen por cuándo llegan, con `WP_CIERRE_GRACIA` (20 s) de margen.
Se cierra **el juego**, no WProton, así que sigue el camino normal de fin de
partida: desmontar, recolocar los menús y guardar las estadísticas.

De paso, por el camino de carpeta el juego corría en primer plano y sin guardar
su PID, así que ahí **nada** podía cerrarlo: ni esto ni el guardia de SELECT.
Ya corre igual que en el camino de la imagen.

## El menú de GE-Proton, por familias

Pedir la lista entera de GE-Proton eran tres consultas a GitHub y cientos de
versiones en pantalla, cada vez que se entraba. Al entrar salen ahora las
series —11.x, 10.x, 9.x, 8.x, 7.x, 6.x— y al elegir una **se cargan solo las
suyas**: una consulta en vez de tres para las series nuevas, y dos para la 9 y
la 8.

Además se guarda lo consultado unas horas, así que la segunda visita no toca la
red. Si GitHub no responde se usa lo guardado, en vez de dejar la lista vacía.

La lista de familias sale de lo que haya publicado, no de una lista escrita a
mano: cuando salga la serie 12 aparecerá sola.

## El de Kron4ek, lo mismo y por variantes

*Wine Kron4ek* va ahora en tres pasos: **serie** (11.x, 10.x…), **variante**
(`wow64`, `staging-tkg-wow64`, `staging-wow64`, los `amd64` con multilib, los
`x86`, y `Wine Proton` aparte) y **versión**. El paquete se localiza solo.

Antes solo se ofrecían las 12 últimas versiones —de la serie 9 o la 8 no había
forma de bajar nada— y había que leerse los doce nombres de fichero de la
publicación para dar con el que querías. Si una versión antigua no trae la
variante pedida, se avisa y se enseña lo que sí trae.

## Runners y herramientas, ordenado

Esa pantalla tenía diecinueve filas y mezclaba lo que se usa a diario —runners,
convertir un juego, probar el mando— con lo que se instala una vez y no se
vuelve a tocar. Lo segundo está ahora en **Instalar y actualizar componentes
>>**: umu-launcher, Python portable, evdev, extractores de GOG, herramientas
FUSE y DwarFS, y datos de HowLongToBeat.

*Instalar librerías de Windows* se queda en el menú principal: eso no instala un
componente de WProton, mete `vcredist` y compañía en el prefijo de un juego, y
eso se hace por juego y se repite.

Y fuera *Crear un .keys de ejemplo*: dejaba un fichero en `runtime/` que había
que copiar a mano junto al juego con el nombre exacto. *Ajustes del juego →
Mapeador .keys → Crear o editar las teclas de este juego* hace lo mismo y lo
deja donde va.

## Limpieza

Cuatro funciones que no llamaba nadie, y **una que sí servía**:

- *Ajustes del juego → Mandos por SDL en este prefijo* prometía dos veces que se
  podía deshacer, y no era cierto: solo se llamaba al «poner», así que elegirlo
  otra vez lo volvía a aplicar. El deshacer estaba escrito y sin conectar. Ahora
  es un interruptor de verdad y la fila dice en qué estado está, leyendo el
  registro del prefijo y no una marca nuestra.
- Fuera `gh_digest`, `perfil_poner` y `descendientes_nuestros`, con una nota en
  su sitio de qué había y por qué se fue.
- Y con la última se quedó huérfano el puente entero a **`procesos.py`**: 223
  líneas de Python que se empaquetaban en cada descarga sin que nada las
  invocara. Fuera el módulo, su puente y sus entradas en `build.sh`. **7 KB
  menos** en la descarga y un módulo menos que mantener.

Lo que ese módulo prometía —cerrar solo lo que desciende de nosotros, porque
matar el grupo entero costó un reinicio de la Deck— lo hace `matar_con_hijos` en
bash, con `pgrep -P` y de las hojas a la raíz.

## Detalles

- Dos ajustes nuevos en `settings.conf`: `WP_WINEBOOT_TIMEOUT` (180 s) y
  `WP_WINESERVER_TIMEOUT` (20 s).
- El menú del prefijo de TeknoParrot decía «crearlo ahora» cuando lo que hace
  es descargarlo ya hecho. Corregido, y el manual también.

## Paridad imagen / carpeta

Lo que hacía `launch_game` y no `launch_loose_exe`, ya en los dos:

- perfiles de la comunidad para un juego nuevo
- dependencias que trae el propio paquete
- librerías del prefijo, y **en el orden correcto** (hacían falta `RUN_CMD` y
  `RUNNER_KIND`, que las pone `build_runner_cmd`)
- descargar el runner que pide el perfil si no está instalado, en vez de caer
  al automático sin decir nada
- cerrar los menús antes de lanzar, que es lo que le robaba el foco al juego
- recuperar el ejecutable del perfil si el paquete se rehizo
- blindaje de señales durante la partida, y levantarlo en **todas** las salidas
  (`partida_fin`) — esto último también faltaba en `launch_game`

## Que no vuelva

La auditoría del proyecto tiene tres comprobaciones nuevas, todas probadas en
negativo (se reintroduce el fallo y saltan, mientras `bash -n` sigue en verde):

- variables que una función usa y no define, distinguiendo lo que muere en una
  subshell de lo que mata el script
- paridad imagen / carpeta: contrato de llamada directa, alcanzables y blindaje
- ningún campo del perfil se puede borrar con `unset`

Y `banco_pruebas.sh`: ejecuta la secuencia de lanzamiento sin juego, con un
`trap EXIT` que dice la última orden. Encontró lo de `MANGOHUD` en un intento.
