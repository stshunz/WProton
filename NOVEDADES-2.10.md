# WProton 2.10 — novedades

> **Muchas gracias a Michel, Fransis y MRDeu** por todas las horas de testeo que
> habeis metido a WProton. Sin vosotros este proyecto no habria sido posible.

Aviso de version nueva de GE-Proton, letra legible en pantallas 4K, un cambio
de fondo en como se preparan los prefijos que vienen dentro del archivo y el
final de un caso que costo seis teorias: por que un juego se cerraba al cargar
su video de presentacion en una Steam Deck y en un escritorio no.

Casi todo lo de esta version sale de lo que contaron los testers probando la
2.03, con sus registros y sus capturas delante.

## El puntero mientras juegas: se esconde solo, y vuelve cuando lo mueves

Esto estaba mal por los dos lados, y lo conto Dani con una frase que lo dice
todo: *"realmente no desaparece el cursor, sigue en pantalla; lo que desaparece
es el cursor ingame y no se puede usar en algunos menus de configuracion"*.

Son **dos quejas**, y conviene subrayarlo porque lo que vino despues se
entiende solo mirandolas juntas: el puntero tiene que desaparecer DE VERDAD, y
el cursor tiene que ESTAR cuando el juego lo necesita. Un arreglo que cumpla
una y rompa la otra no es un arreglo.

### Lo que habia, y los dos intentos que no valieron

Lo que habia era un `XFixesHideCursor`: oculta el puntero **de toda la
pantalla** mientras la conexion con las X siga abierta. Fallaba por los dos
lados a la vez. Al ocultar el cursor de la pantalla entera se llevaba por
delante EL DEL JUEGO, asi que en los menus de configuracion de algunos juegos
no habia puntero con el que pinchar; y encima **tampoco escondia el que
molestaba**, porque solo tocaba la pantalla de WProton y con gamescope por
medio el juego pinta en otra.

El segundo intento fue mover el puntero **un pixel y devolverlo**, siguiendo un
comentario antiguo del codigo que decia *"se queda en medio de la pantalla
hasta que lo mueves"*. Tampoco. En un juego de Unity como Nine Sols el puntero
no se esconde porque se mueva; moverlo, si acaso, es lo que lo hace aparecer.
Ese comentario era una suposicion de hace tiempo, no una observacion, y
fiarse de el costo una version.

### Lo que si funciona

**Esconderlo por inactividad**, que es lo que hace `unclutter` y lo que hace
todo el mundo: si pasan unos segundos sin mover el raton -que es exactamente lo
que pasa jugando con el mando- el puntero se esconde; y en cuanto mueves el
raton, aunque sea un pixel, vuelve al instante.

Y esto cumple **las dos** quejas de una vez, que es la señal de que por fin es
el camino bueno:

- el puntero desaparece de verdad, no se aparta ni se disimula;
- y el cursor esta ahi en cuanto hace falta: tocas el raton y puedes usar el
  menu de configuracion del juego sin haber perdido nada.

Si el juego **captura** el raton -lo normal en primera persona- para nosotros
es "no se mueve" y se queda escondido, que es justo lo que se quiere ahi.

### Y en todas las pantallas, que era la otra mitad del fallo

El vigilante hereda el `DISPLAY` de WProton, pero **el juego no siempre pinta
ahi**: con gamescope por medio, gamescope levanta su propio XWayland -otra
pantalla- y es el juego el que se va alli. Escondiendo el puntero solo en la
nuestra, el de la pantalla del juego seguia a la vista. Eso es, palabra por
palabra, lo que se veia en la captura de Nine Sols.

Asi que ahora se buscan todas las pantallas de la sesion -la de `DISPLAY` y las
que tengan socket en `/tmp/.X11-unix`- y se esconde en todas a la vez, porque
no se sabe de antemano cual se esta mirando. Basta con que el raton se mueva en
cualquiera de ellas para que el puntero vuelva en todas.

De paso, el registro ahora dice **si XFixes esta de verdad** en cada pantalla.
Importa porque sin esa extension las llamadas no dan error: simplemente no
hacen nada, y el puntero se queda en pantalla sin que nada lo explique.

### Y la razon por la que aun asi se seguia viendo

Con todo lo anterior puesto, el puntero **seguia saliendo**. Y la causa no era
como se escondia, sino **cuando**: la comprobacion pedia que el puntero
estuviera en el **pixel exacto** para contarlo como quieto.

En un equipo de juego eso casi nunca pasa. Steam Input puede estar emulando un
raton, un trackpad haciendo de raton manda movimiento con solo apoyar el dedo,
y un stick con deriva empuja un pixel cada tanto. Con cualquiera de esas tres
cosas -y en una Deck suele haber alguna- el puntero nunca llegaba a estar
quieto y **no se escondia jamas**. La idea estaba bien; la condicion, no.

Ahora hay un **margen** (`CURSOR_UMBRAL`, 8 px por omision): un temblor de uno
o dos pixeles no cuenta como "estoy usando el raton", pero moverlo de verdad
si, y el puntero vuelve al instante. Un movimiento lento, pixel a pixel,
tambien acaba contando: la posicion de referencia no se actualiza con el
temblor, asi que la mano de una persona siempre acaba sumando lo suficiente.

Y se aprovecha algo que `unclutter` no tiene y nosotros si: **el mando**. El
vigilante ya lo esta leyendo para poder cerrar el juego, asi que si llegan
eventos del mando sabemos que nadie esta tocando el raton, y con **un
segundo** quieto basta.

### Y la razon de verdad en un sobremesa: Wayland

Con el margen puesto, en un **sobremesa con CachyOS y el raton parado** -o
sea, sin nada que lo moviera- el puntero **seguia saliendo**. Asi que el
margen no era la causa ahi, y la causa era otra bastante mas de fondo.

En una sesion **Wayland** -lo que trae CachyOS con KDE por omision- el puntero
**no lo dibuja X**: lo dibuja el compositor, y el juego corre dentro de
XWayland. `XFixesHideCursor` es una peticion al servidor X, y ahi puede
quedarse en nada. Es exactamente la razon por la que `unclutter` tampoco
funciona en Wayland y por la que cada compositor tiene lo suyo (sway lo hace
con `hide_cursor`, GNOME con una extension).

Eso explica ademas por que las pruebas se contradecian: en las Deck de los
testers, en X11, el ocultado SI llegaba a funcionar -tanto que se llevaba por
delante el cursor del juego-; en el sobremesa, en Wayland, no hacia nada.
Mismo codigo, dos resultados, y la diferencia no estaba en WProton.

**Asi que ahora se esconde por dos caminos a la vez:**

1. `XFixesHideCursor`, el de siempre, que vale en una sesion X11.
2. Ponerle a la ventana que hay bajo el puntero un **cursor transparente**.
   Ese es el camino por el que cualquier programa enseña su propio cursor, y
   por tanto **cruza XWayland y llega al compositor**: si el cursor no tiene
   ni un pixel pintado, no se ve nada.

El segundo se vuelve a poner en cada vuelta mientras esta escondido, porque el
juego pone el suyo cuando le apetece -Wine, con cada `WM_SETCURSOR`- y si no
se repite el puntero reaparece solo. Al mover el raton se le devuelve su
cursor al juego, y al cerrar no queda ninguna ventana tocada.

Y un detalle que no se ve pero importa: Xlib, de serie, ante un error del
protocolo **imprime y sale**. Como aqui se tocan ventanas del juego, que
pueden desaparecer entre que se miran y se tocan, se le pone un manejador de
errores que los cuenta y se los traga. Sin eso, un juego cerrando una ventana
en el momento justo se habria llevado por delante el vigilante, y con el, el
cierre del juego con el mando. El puntero no vale eso.

### Y si aun asi pasara algo, que lo diga el registro

Los dos intentos anteriores fallaron **en silencio**: el puntero seguia ahi y
el registro no decia nada, asi que habia que adivinar. Eso tambien se arregla.
Si el puntero sigue a la vista, cada minuto se escribe una linea con los
numeros: que clase de sesion hay (X11 o Wayland), cuanto hace que se movio de
verdad, cuantas veces ha temblado sin pasar el umbral, cuantas se ha movido,
donde esta en cada pantalla, si estan llegando eventos del mando y cuantos
errores de X se han tragado. Con eso se distingue *"no se intenta esconder"* de
*"se esconde y algo lo vuelve a pintar"*, que son dos averias distintas y
piden arreglos distintos.

### Como se ajusta

En *Preferencias → **Puntero mientras juegas*** se enciende, se apaga, se
elige cuanto esperar -1, 3 (lo normal), 5 o 10 segundos- y el **margen de
movimiento** -0 (el pixel exacto), 4, 8 (lo normal) o 20 px-. Si se te esconde
mientras lees un menu del juego, sube los segundos; si se te queda a la vista,
sube el margen. En `settings.conf` son `OCULTAR_CURSOR`, `CURSOR_SEGUNDOS` y
`CURSOR_UMBRAL`. Al cerrar el juego el puntero vuelve siempre, pase lo que
pase.

## Los prefijos que vienen dentro del archivo, otra vez

El arreglo de Grandia HD funciono, pero **se llevo por delante otra cosa**, y
conviene contarlo entero porque es un caso de libro de dos arreglos que se
anulan entre si.

Aquel arreglo pone en el prefijo un `pfx/creation_sync_guard`: es lo que le
dice a Proton *"este prefijo ya esta creado, no lo hagas encima"*, y sin eso
Proton reventaba en `copy_pfx()` con un `FileExistsError`.

Lo que no se vio es que **habia otra parte del codigo contando con que
`copy_pfx()` se ejecutara**. Al sacar el prefijo del archivo se borraban todas
las DLL y los EXE que trae el runner -cientos de megas- con esta idea: *"total,
los vuelve a poner Proton"*. Y era verdad... hasta que el centinela hizo que
Proton no ejecutara `copy_pfx()` nunca.

Los ficheros no volvian. En el registro de un tester se ve entero y en orden:

```
(305 DLL quitadas: las pone el runner)
[+] Actualizando el prefix incluido (wineboot)...
wine: could not load kernel32.dll, status c0000135
El prefijo parece roto: Wine no consigue arrancar ni Windows.
```

El borrado existia para evitar los choques de `copy_pfx()` al enlazar encima de
un fichero que ya estaba. **Si `copy_pfx()` no se ejecuta, no hay con que
chocar**, asi que ya no evitaba nada y lo unico que hacia era dejar el prefijo
sin `kernel32.dll`. Se ha quitado: ahora `windows/` se copia entera. Ocupa mas,
y a cambio el prefijo que sale de ahi **arranca**.

### Y un prefijo vacio tampoco puede llevar centinela

El segundo registro enseña la otra cara, con la opcion *"prefijo propio del
juego"*, que crea uno nuevo y vacio:

```
FileNotFoundError: [Errno 2] No such file or directory:
  '.../prefixes/Skate_3_Recompiled/pfx/drive_c/vrclient/bin'
```

El centinela es una **afirmacion**: "este prefijo ya esta creado". Dicha de uno
vacio es mentira, y Proton se la cree: se salta `copy_pfx()` y se estrella en
la primera copia, porque la carpeta de destino no la ha creado nadie.

Asi que ahora se comprueba antes de ponerlo, y se comprueban las dos cosas que
de verdad hacen falta: que haya **registro** -o sea, que eso sea un prefijo- y
que este **`kernel32.dll`**, que es el fichero exacto con el que fallaba Wine.
Con esas dos, Proton puede saltarse la creacion sin que falte nada; sin ellas,
el prefijo **tiene** que crearlo el.

Y si encuentra un centinela puesto por una version anterior en un prefijo que
esta a medias, **lo quita**. Si no, ese prefijo se quedaria roto para siempre:
Proton no lo crearia nunca y no habria forma de que se recuperase solo.

## Cerrar con el mando un juego de Linux en carpeta

Un tester lo conto con todo el detalle que hacia falta:

> *"los juegos de linux en modo carpeta no deja salir pulsando select, y al
> salir del propio juego se queda un tiempo pensando y si despues le dejas
> pulsado el select como que lo termina de cerrar. El mismo juego comprimido en
> wsquashfs lo cierra perfecto."*

Las dos mitades son **el mismo fallo**, y la pista buena es la ultima frase:
comprimido si funciona.

Para cerrar un juego de Linux, el vigilante necesita que se le apunte la
carpeta desde la que corre -por el identificador no basta: un lanzador arranca
el juego y termina, asi que el juego de verdad ya no es hijo nuestro-. Y esa
carpeta solo se apuntaba si el lanzador acababa en `.sh` o `.AppImage`, o si
estaba puesta `WP_NATIVO`... que **solo existe en el camino de imagen**.

Asi que un juego de Linux en carpeta con un binario pelado -`Juego.x86_64`,
`juego.bin`, o sin extension ninguna- no casaba con nada y se trataba como
juego de Windows. De ahi lo uno y lo otro:

- **Select no hacia nada**, porque el vigilante no sabia que cerrar.
- **Y al terminar "se quedaba pensando"**, porque se recorria el cierre de Wine
  entero, con sus esperas, para un juego que no tiene Wine ni prefijo.

Ahora no se adivina por el nombre: si la extension no lo dice, **se mira el
fichero**. Un ELF empieza por `7f 45 4c 46` y un guion por `#!`, y eso no
miente se llame como se llame. Y si no se sabe, se trata como juego de Windows,
que es lo conservador.

### Y el aviso que no era

En los dos registros salia esto, sin que pasara nada malo:

```
AVISO: el vigilante de salida SE CERRO; el cierre con el mando no funcionara
```

Dos causas, las dos del propio aviso:

- Preguntaba por el identificador que devuelve `lanzar_suelto`, que es el del
  `setsid`, y ese puede haber desaparecido en cuanto arranco al python. Es el
  mismo fallo que ya estaba contado en `guardia_salida_stop`, cometido otra vez
  veinte lineas mas arriba. Ahora se pregunta por el **nombre** del proceso.
- Y saltaba aunque la partida **ya hubiera terminado**. El vigilante se cierra
  a proposito al acabar el juego; con un juego que duraba 3 segundos -porque el
  prefijo estaba roto-, a los 20 s el aviso salia siempre, anunciando una
  averia que no existia.

## La letra en pantallas 4K

Un tester con una pantalla 4K dijo que las letras se ven diminutas. **No es la
fuente: es aritmetica.** Los tamaños estan en pixeles, y un pixel de un 4K mide
la cuarta parte que uno de un 1080p a la misma distancia. Un titulo de 34 px
que se lee comodo en 1080p es una hormiga en 3840x2160.

Asi que ahora se mide la pantalla y la letra sube en la misma proporcion: un
1080p se queda igual, un 1440p sube un tercio y un 4K la dobla. Y sube el
diseño con ella, porque los margenes ya iban en `FS(...)` y la altura de fila
sale de `FSCALE`: se ven menos filas, pero legibles.

Tres decisiones que no se ven y que son las que lo hacen correcto:

- **Solo sube, nunca baja.** En pantallas pequeñas manda lo que diga la
  persona; si esto pudiera achicar, una Deck o un portatil acabarian con letras
  mas pequeñas que las de ahora.
- **Multiplica el ajuste de la persona, no lo sustituye**, para que *"grande"*
  siga siendo mas grande que *"normal"* tambien en un 4K.
- **Se mira la VENTANA, no el escritorio.** Es lo mas facil de estropear: con
  gamescope dibujando a 1280x800 para escupirlo a un televisor 4K, aqui se ven
  1280x800 y no se toca nada, que es lo correcto -de agrandarlo ya se encarga
  gamescope, y hacerlo dos veces daria letras gigantes-. A pantalla completa en
  un 4K de verdad, la ventana ya es de 3840x2160 y si sube.

Se apaga en *Preferencias → Tamaño de la letra → **Subir sola en pantallas
4K***, o con `MENU_AUTO_ESCALA=0`. Y el registro escribe la resolucion, el
ajuste de la persona, el factor aplicado y el resultado, para no tener que
adivinar si alguien vuelve a decir que lo ve pequeño.

## Avisa cuando hay un GE-Proton nuevo

Lo pidieron asi de claro: que avise igual que avisa cuando hay una version
nueva de WProton. Pues igual, y por el mismo camino.

En *Runners y herramientas*, la fila de actualizar pasa a decir
**`*** RUNNER NUEVO: GE-Proton11-8 *** >>`**, y dentro, cada familia lleva su
aviso al lado de la version instalada. La consulta a GitHub va **en segundo
plano al arrancar**, como la de WProton: el menu solo lee un fichero, asi que
abrirlo no espera a la red ni a que la red falle, que es peor.

**No se compara la version: se compara el nombre de la carpeta.** Puede sonar
tosco y es justo lo contrario. `setup_runner_ultimo` ya saca el nombre de la
carpeta del propio fichero publicado -quitandole la extension- y luego mira si
esa carpeta existe; el aviso hace EXACTAMENTE esa comparacion, con el mismo
repositorio y el mismo patron. Asi lo que se avisa y lo que se descarga no
pueden desviarse: si el aviso dice que hay una nueva, al pulsar se baja esa.

Comparar numeros habria sido inventar un segundo criterio, y uno con trampa:
por orden alfabetico `GE-Proton11-7` va DETRAS de `GE-Proton9-27`.

Dos detalles que se notan al usarlo:

- **Si no tienes esa familia instalada, no se avisa de ella** -ni se gasta la
  consulta-. Ahi no hay "version nueva": hay "no instalado", que es lo que ya
  dice la fila. Avisar de una actualizacion de algo que no tienes confunde.
- **Lo que viene de GitHub se valida antes de pintarlo.** Ese texto acaba en un
  menu y dentro de una ruta, asi que una respuesta rara -una pagina de error,
  un nombre con barras- se descarta en vez de acabar ahi.

## --config aceptaba ficheros, pero no carpetas

Lo encontro, lo localizo y lo validou un tester con un *Age of Empires Gold.pc*
de verdad, y el informe que mando no dejaba nada que adivinar.

Al pedir los ajustes de un juego desde la linea de ordenes:

```
./wproton.sh --config "/ruta/Age of Empires Gold autorun to exe.pc"
ERROR: No existe el fichero: /ruta/Age of Empires Gold autorun to exe.pc
```

Y la ruta existia. Lo que pasaba es que era una **carpeta**, y la comprobacion
usaba `-f`, que solo da verdadero para ficheros normales.

Lo llamativo es que **el resto de WProton ya sabia tratarla**: lanzar ese mismo
juego sin `--config` funcionaba, y `game_config_menu` esta escrita para recibir
las dos cosas -lo dice su propia documentacion, *"wsquashfs o carpeta"*, y
tiene una fila de empaquetar que solo aparece con carpetas-. O sea que la
carpeta se rechazaba **antes de llegar a la funcion que sabe tratarla**.

El arreglo es cambiar `-f` por `-e`, y el mensaje pasa a hablar de *ruta* en
vez de *fichero*, porque ahora valen las dos. Nada mas: ni parser nuevo, ni
tocar `game_config_menu`, ni cambiar el sistema de perfiles.

Se ha revisado que esa comprobacion no estuviera en mas sitios -no lo estaba- y
queda una prueba que ejecuta el bloque real del programa generado con una
carpeta, un `.wsquashfs`, un `.exe`, un enlace roto y una ruta que no existe.
Si alguien vuelve a apretar la comprobacion a `-f`, salta ahi.

## El teclado en pantalla no tenia el "="

Un tester se quedo plantado intentando escribir esto en *Argumentos de
lanzamiento*:

```
SDL_VIDEODRIVER=x11
```

El teclado que salia tenia A-Z, 0-9, espacio, punto, guion y guion bajo. **Y
ya.** Sin `=` no hay forma de escribir una variable, y sin `%` tampoco
`%command%`, que es literalmente lo que se pega de ProtonDB. El campo era
inservible con el mando.

La causa: **el motor Qt usaba el teclado de BUSCAR para escribir texto.** Para
filtrar nombres de juegos, A-Z y numeros estan bien y se manejan rapido con el
mando; para escribir argumentos, no llegan ni de lejos. El motor pygame ya
tenia un teclado aparte para este campo, con su qwerty y sus simbolos, asi que
el mismo cuadro de texto se podia rellenar o no **segun el motor que le tocara
al equipo** -y WProton lo elige solo con `MENU_UI=auto`-.

Ahora el motor Qt tiene los dos teclados y usa el que toca segun el modo, con
**exactamente la misma distribucion** que el de pygame: numeros con `-` y `=`,
qwerty en minusculas, los simbolos de puntuacion, y una fila con
`_ : " | + * @ # $ % &`. Hay una tecla de **mayusculas** que se queda encendida
mientras lo esta, para saber que vas a escribir sin tener que probar.

El de buscar se queda **exactamente como estaba**: ahi menos teclas es mejor.

De paso, el pie del teclado mentia a medias: al escribir texto la **Y** no
cierra, **acepta** lo escrito y termina. Ahora lo dice segun el modo.

## El juego que se cerraba al cargar el video de presentacion

Un tester lo conto con el dato que lo resolvia todo:

> *"se cierra al cargar el video de presentacion, da igual el Proton que ponga.
> Lo curioso es que desde CachyOS si que lo carga bien; es en SteamOS, modo
> juego y escritorio."*

En su registro, justo antes de morir, habia **doscientas** lineas de esto:

```
GStreamer-WARNING: Failed to load plugin
  '.../files/lib/i386-linux-gnu/gstreamer-1.0/libgstXXX.so': wrong ELF class: ELFCLASS32
```

Un juego de 64 bits intentando cargar, uno por uno, los plugins de 32. Y en
`GST_PLUGIN_PATH` aparecia **solo** la carpeta `i386` del runner: la de 64, que
el runner tambien traia, no estaba.

La causa: el prestamo de codecs solo aceptaba carpetas **de 32 bits**. Nacio
para los videos WMV de juegos de 32 -donde la multilib de Arch se queda corta-
y el filtro se quedo escrito a fuego. En un juego de 64 el efecto era el peor
posible: se le ponia delante la carpeta que no podia usar, y la que si le
servia no se añadia nunca.

**Y eso explica lo de los dos sistemas**, que es lo que parecia magia: en
CachyOS el GStreamer del sistema esta completo, asi que el descodificador
aparecia de todas formas; en SteamOS no, y al llegar al video no habia con que
descodificarlo. *"Da igual el Proton que ponga"* encaja perfectamente: el
Proton nunca fue el problema.

Ahora se prestan **las dos arquitecturas del mismo paquete**, 32 primero -que
es lo que hace Batocera y lo que necesita un juego de 32-. Y del **mismo**
paquete a proposito: la regla de no mezclar plugins de uno con el nucleo de
otro sigue intacta, porque fue lo que hundio un intento anterior con Wine-GE;
lo que se arregla es que un paquete se usaba a medias. Un runner que solo trae
las de 64 tambien vale ahora: antes se descartaba entero.

El registro dice de que paquete sale cada carpeta **y de cuantos bits**, que es
lo primero que hace falta si un video vuelve a fallar.

### Y comparando los dos registros aparecio la causa de verdad

Lo de arriba era un fallo real, pero NO era el que cerraba este juego. Con los
dos registros al lado -el de SteamOS y el de CachyOS, mismo juego- la linea que
lo decia todo era esta, en el de SteamOS:

```
GST_PLUGIN_PATH=/usr/lib/gstreamer-1.0:/usr/lib64/gstreamer-1.0
```

Las carpetas **del propio runner** no estaban. Ni una.

La lista de sitios donde buscarlas miraba `lib/` y `lib64/` del runner... y ya.
Y **todos los Proton** -GE, CachyOS, el de Valve- usan el diseño del Steam
Linux Runtime:

```
<runner>/files/lib/i386-linux-gnu/gstreamer-1.0
<runner>/files/lib/x86_64-linux-gnu/gstreamer-1.0
```

Asi que los plugins del propio runner **no entraban nunca**. Con un Proton 11,
que ademas no recibe prestamo porque usa winedmo/FFmpeg, la lista se quedaba
literalmente en lo del sistema. En un escritorio eso basta; en SteamOS el
GStreamer del sistema es minimo, y al llegar al video no habia con que
descodificarlo.

**Y encaja con las dos cosas que el tester repetia y que no cuadraban:**

- *"da igual el Proton que pongas"* — ninguno aportaba los suyos, porque todos
  usan ese diseño;
- *"en CachyOS si va"* — alli el sistema los tiene, y ademas estaba usando un
  runner **Wine**, que si usa `lib/` y `lib64/` y por tanto si entraba en la
  lista.

El comentario de cabecera de esa funcion **ya nombraba** el diseño multiarch
desde hacia tiempo. La lista no lo incluia. Eran dos lineas.

Ahora el registro dice ademas, en una linea, **si el runner ha aportado sus
propios plugins o no**, que es la pregunta que hubo que contestar leyendo dos
registros enteros.

### Y aun asi el juego seguia cerrandose. La causa, a la sexta

Hay que contarlo como paso, porque la leccion vale mas que el arreglo.

Los dos fallos de arriba eran reales y estan corregidos, pero **ninguno de los
dos era el que cerraba este juego**. Detras fueron cayendo cuatro teorias mas:
las carpetas tapadas de la superposicion, la familia del runner, el HDR y el
motor grafico. El tester las fue tumbando una a una, con razon y con paciencia:

> *"el HDR tampoco es, es un problema que al cargar la intro se cuelga"*
>
> *"da igual que ponga wined3d o fuerce OpenGL o vulkan"*
>
> *"te estas yendo por las ramas, no estas buscando el verdadero problema"*

Tenia razon en las tres. Y el motivo de ir por las ramas era concreto: **el
dato no estaba en nuestro registro**. Un juego de Unity que se cierra solo no
dice nada por la salida estandar —imprime su configuracion de memoria y se
acaba—, asi que lo unico que quedaba era conjeturar.

Pero si estaba en **el suyo**. Unity escribe un `Player.log` con el motivo
exacto, dentro del prefijo. WProton no lo habia mirado nunca. Se le añadio que
lo volcara, y a la primera aparecio esto:

```
WindowsVideoMedia error 0xc00d5212 while reading archive:/CAB-f910...
Context: Setting media type for first video stream
Error details: Codec was not found.
   Video Track [3840 x 1920], type: H264
```

**No faltaban "plugins de GStreamer": faltaba el descodificador de H.264.** Y
aqui esta lo que no se veia por ninguna parte:

> **Proton no trae descodificador de H.264.** Valve no distribuye
> descodificadores de formatos con patentes: su FFmpeg va compilado con todo
> desactivado, y el H.264 lo aporta **el propio Steam**. Fuera de Steam, no hay
> quien lo ponga.

Con eso, las dos frases que llevaban semanas sin encajar encajan a la primera:

- *"da igual el Proton que ponga"* — **ninguno lo trae**. No era cosa de uno.
- *"en CachyOS si va"* — alli lo pone **el sistema**, que tiene `gst-libav` con
  FFmpeg completo. En SteamOS no.

Y explica tambien por que las comprobaciones anteriores daban por bueno al
runner: se miraba **que existiera el fichero** `libgstlibav.so`. Y existe. Lo
que no tiene es el codec dentro.

**Lo que hace ahora WProton**

- **Pregunta de verdad.** No si el fichero esta, sino si la `libavcodec` que lo
  respalda trae el descodificador. Sin ejecutar nada, leyendo el binario.
- **Prefiere al que si sabe.** Entre varios paquetes elige uno que pueda con
  H.264; si ninguno puede, elige exactamente el mismo que antes, asi que nada
  de lo que hoy funciona se queda sin su paquete.
- **Busca en el Steam Linux Runtime**, que en una Deck esta instalado siempre y
  es un contenedor completo: muchas veces el descodificador que falta **ya esta
  en el disco**, sin descargar nada. Tambien mira la tarjeta SD y el Steam de
  Flatpak.
- **Aparta el conversor de Proton.** Dentro de Steam los formatos con patentes
  no se descodifican: se **transcodifican**, y un conversor sirve el video que
  el cliente ha bajado ya convertido —con prioridad por delante de los
  descodificadores de verdad—. Fuera de Steam ese conversor no puede funcionar,
  pero sigue yendo primero y **tapa al bueno**. Eso es, exactamente, el segundo
  registro del tester: alli algo si acepto el video y se rompio despues
  pidiendo un atributo que no estaba. Si el usuario pone `GST_PLUGIN_FEATURE_RANK`
  a mano, manda el usuario.
- **Rehace el indice de plugins cuando cambia el runner.** Ese indice es una
  cache y sobrevivia al cambio: una vez indexado en malas condiciones, probar
  otro Proton no cambiaba nada. Otro motivo, este de los de verdad, para *"da
  igual el Proton que ponga"*.
- **Lo dice en el registro, siempre.** Una linea: `Video H.264: disponible…` o
  `Video H.264: NO HAY DESCODIFICADOR…`. Y si el juego se cierra en un video,
  al salir se traduce lo que ha dicho **el propio juego**: su linea, el formato
  (`H264`, `WMV`…) y si en ese arranque habia descodificador o no. Sin activar
  ningun diagnostico: cuando pasa, eso **es** la respuesta.
- El diagnostico de video (`DIAG_VIDEO=1`) mira ademas **Media Foundation**,
  que es por donde van los videos de Unity y Unreal. Las cuatro
  comprobaciones que habia solo cubrian DirectShow, asi que este fallo no se
  veia ni activandolo.

La leccion, dicha sin adornos: **antes de teorizar, buscar donde el programa ya
ha escrito el motivo**. Seis teorias podrian haber sido ninguna.

## Un juego de Linux que "no llega a arrancar" ahora dice por que

Y la leccion de arriba se cobro su factura al dia siguiente. Dani consiguio una
version **nativa** de Linux del mismo juego:

> *"en el escritorio y en el modo juego funciona, le puse el Steam runtime 4.0,
> pero en WProton no llega a arrancar"*

De la partida entera, su registro traia esto y nada mas:

```
19:18:51  [+] Carpeta del juego: /home/deck/wptoton/prefixes/WProton.home
19:18:52  juego nativo: el lanzador termino; se espera a los procesos dentro de...
19:18:58  juego nativo: procesos usando la carpeta al empezar: 0
19:19:02  juego nativo: ya no queda ningun proceso usando ...
```

El lanzador vivio **un segundo** y no hay ni una palabra de lo que dijo. Otra
vez el mismo agujero, en otro sitio. Mirando el codigo salieron **cuatro**, y
los cuatro se comprobaron ejecutando la funcion de verdad con un lanzador de
pega que se queja:

1. **La salida del juego se tiraba.** El lanzador se ejecutaba con
   `setsid $exe &`, sin redirigir nada: lo que escribiera se iba por donde
   fuera la salida de WProton, que en el modo Juego **no va a ninguna parte**.
2. **El codigo de salida no se apuntaba.** Se recogia en una variable, se
   devolvia... y no se escribia. En el registro no habia ni el codigo ni el
   tiempo: solo *"el lanzador termino"*, que no distingue entre uno que hizo su
   trabajo y uno que se murio en el sitio.
3. **Y por lo primero, un diagnostico entero estaba muerto.** El que caza
   `error while loading shared libraries` y dice *que* libreria falta lo busca
   **dentro del registro**... donde ese mensaje no llegaba jamas. Escrito,
   probado y sin poder funcionar nunca. En la prueba de ayer salto a la primera
   vez que la salida llego a su sitio.
4. **El camino nativo no pasaba por ningun diagnostico de salida**: ni por el
   del registro del propio juego ni por el del video. Los dos se llamaban solo
   en los caminos de Windows.

Lo que trae ahora el registro de un juego de Linux:

- **lo que escribio el juego**, en su propio bloque, con las ultimas 80 lineas
  (y diciendo cuantas eran en total, para que un juego hablador no tape el
  resto);
- **el codigo de salida del lanzador y cuanto vivio**;
- **su `Player.log`**, si es de Unity. Para los juegos de Windows ya se buscaba
  en el prefijo; un juego de Linux no tiene prefijo, escribe en
  `$XDG_CONFIG_HOME/unity3d/<empresa>/<juego>/`, que es la carpeta portatil que
  le da WProton. Ahora se busca ahi;
- **si el lanzador espera que Steam este en marcha**: se lee el propio `.sh` y
  se apunta su `SteamAppId` y si carga `steamclient.so`. Hay juegos nativos de
  Steam que, sin encontrar a Steam, se cierran en un segundo y sin decir nada
  —que es exactamente la pinta que tenia este—;
- **y las variables de Steam que heredamos.** WProton se añade a Steam como
  juego ajeno, asi que en el modo Juego lo arranca Steam —en ese registro se
  veian `steam`, `steam-runtime-l` y `reaper` en nuestro propio grupo de
  procesos— y sus variables (`SteamAppId`, `SteamOverlayGameId`, `LD_PRELOAD`…)
  las hereda el juego. Si a un juego nativo de Steam le llega el identificador
  del **atajo de WProton** en vez del suyo, su `steam_api` se inicializa contra
  el juego equivocado.

De esas variables **no se cambia ninguna**: solo se escriben, al lado de lo que
el lanzador declara, para poder comparar las dos cosas de un vistazo. Tocar el
entorno heredado sin saber todavia que esta pasando seria meter opciones a
ciegas, y eso ya se ha visto en que acaba.

Nada de esto adivina el fallo del juego de Dani: lo que hace es que el proximo
registro lo traiga escrito.

## Lanzar un juego de Linux DENTRO del runtime de Steam

Y la otra mitad de la frase de Dani era una pieza que faltaba de verdad:

> *"le puse el Steam runtime 4.0"*

Un juego nativo moderno puede pedir librerias mas nuevas que las del sistema, y
en SteamOS eso pasa a menudo: la imagen base es corta y **no se puede instalar
nada en ella**. Steam lo resuelve lanzando el juego **dentro de un contenedor**
—el *Steam Linux Runtime*—, que trae su propio juego de librerias completo. Eso
es lo que hace que el mismo juego arranque en Steam y no lanzado a pelo.

Ahora WProton puede hacer lo mismo:

**Ajustes del juego → Casos especiales → Runtime de Steam (juegos de Linux)**

con `no` (como siempre), `automatico` (el mas nuevo que haya instalado) o una
version concreta: **4.0** (la mas nueva, Debian 13), 3.0 (*sniper*), 2.0
(*soldier*) o 1.0 (*scout*), que son los nombres de Valve.

Por dentro no hay nada inventado: se usa el punto de entrada que declara el
propio runtime y que es el que usa Steam,

```
<runtime>/_v2-entry-point --verb=waitforexitandrun -- <lanzador>
```

y se le dan las dos cosas que necesita: `STEAM_COMPAT_CLIENT_INSTALL_PATH`
—donde esta Steam— y, **si el juego esta fuera de tu carpeta personal**,
`STEAM_COMPAT_MOUNTS` con su carpeta. Esto ultimo no es un detalle: el
contenedor monta tu `$HOME`, pero no lo de fuera, asi que **un juego en la
tarjeta SD no existiria ahi dentro**. Es el mismo mecanismo que WProton ya usa
para MAKO y ReShade cuando caen fuera de `$HOME`.

Las carpetas de los runtimes no se buscan por nombres fijos: la 4.0 salio **sin
nombre en clave publicado**, asi que se acepta cualquier `SteamLinuxRuntime*`
que traiga su punto de entrada y la version se averigua despues —por el nombre,
por su `VERSIONS.txt` o por la carpeta del contenedor—. Se mira tambien la
tarjeta SD y el Steam de Flatpak.

Tres decisiones que conviene saber:

- **`no` es el valor de fabrica.** Un juego que hoy arranca lanzado directo se
  sigue lanzando exactamente igual. Esto no cambia nada hasta que alguien lo
  toca.
- **Si se pide un runtime que no esta instalado, el juego se lanza igual**, sin
  contenedor, y el registro y la pantalla lo dicen. Dejar a alguien sin poder
  jugar por un ajuste que no se pudo cumplir seria peor.
- **Y si se pide una version concreta que no esta, no se cuela otra por
  detras.** Que el registro diga "no esta" es mas util que un juego corriendo
  en un contenedor que no es el que se queria.

**Ademas, WProton lo sugiere solo.** Si un juego de Linux dura menos de doce
segundos, no se estaba usando contenedor y hay uno instalado, lo dice al salir:
*"Hay Steam Linux Runtime 4.0 instalado y NO se esta usando"*. Es la pregunta
que se hace cualquiera al ver un juego nativo que no arranca, y WProton tiene
los tres datos para contestarla.

**Y una incoherencia vieja, arreglada de paso.** El ajuste *Casos especiales →
Superposicion de Steam* en `oculto` le quita al juego las variables de
identidad de Steam... pero solo se aplicaba a los juegos de **Windows**. Para
un juego nativo **de Steam** es justo donde mas puede importar, por lo que se
cuenta arriba. Ahora tambien se aplica ahi, y el `env -u` va **detras** del
`--` del contenedor: se le quita al juego, no al punto de entrada, que usa sus
propias `STEAM_COMPAT_*`.

## Y por fin: el identificador de Steam que no era suyo

El registro del propio juego cerro el caso, y lo dijo **por las dos puntas**.
El mismo juego, el mismo dia, los dos `Player.log` al lado:

```
lanzado desde Steam:      Using environment steamid 892970      -> arranca
lanzado desde WProton:    Using environment steamid 3975565157
                          Using steam APPID:3975565157
                          Invalid APPID
                          InvalidOperationException: Steamworks is not initialized.
                          Got a SIGSEGV while executing native code
```

Ese **3975565157 es el atajo de WProton en Steam**, no el juego.

WProton se añade a Steam como juego ajeno, asi que en el modo Juego lo arranca
Steam y le deja puestas sus variables. Un juego **nativo de Steam** lee esa
misma `SteamAppId` para inicializar Steamworks, asi que recibia el
identificador del atajo de WProton en lugar del suyo: *Invalid APPID*,
Steamworks sin inicializar y, un instante despues, SIGSEGV. El juego trae su
`892970` en su `steam_appid.txt`, pero mira **antes** el entorno, y ganaba el
heredado.

Ahora, antes de lanzar un juego de Linux, WProton compara lo que hereda con lo
que el juego declara, y si no es suyo lo corrige:

```
juego nativo: el juego declara SteamAppId=892970; espera que Steam este en marcha
juego nativo: heredado de Steam -> SteamAppId=3975565157
juego nativo: el identificador heredado de Steam (3975565157) NO es de este
              juego; se le pone el suyo (892970)
```

Y si no se sabe cual es el suyo, al menos **no se le miente**: se quita el
ajeno y el juego se apaña con su `steam_appid.txt`, que es de donde deberia
haberlo sacado desde el principio.

**Esto se arregla solo, sin ningun ajuste**, y es a proposito: pasarle a un
juego la identidad de OTRA aplicacion no es una opcion que alguien pueda
preferir, es una fuga.

**Lo que NO se toca: la superposicion.** Son dos cosas que se parecen y no son
la misma:

| Variable | Quien la lee | Que se hace |
|---|---|---|
| `SteamAppId`, `SteamGameId` | el **juego**, para su Steamworks | se corrige a la suya |
| `SteamOverlayGameId`, `LD_PRELOAD` | la **superposicion** de Steam | no se tocan |

Asi el juego recibe su identidad y la superposicion sigue funcionando. Quien
quiera quitarlo todo tiene el ajuste de siempre, *Superposicion de Steam →
oculto*.

## Dos cosas del menu que un juego de Linux no tenia

Las dos salieron de probar lo de arriba, y las dos eran de la misma familia:
el menu daba por hecho que un juego de Linux no necesita nada.

**"Con un .sh no aparece la opcion Casos especiales."** Cierto: el menu de
ajustes vaciaba esa fila entera en los juegos nativos. Tenia todo el sentido
cuando dentro solo habia cosas de Wine —unidades, Mono, version de Windows—,
pero ahi dentro viven ahora el **Runtime de Steam**, que es *solo* para juegos
de Linux, y la **superposicion de Steam**. Era justo el menu que un juego
nativo necesita, y era el unico que no se le enseñaba. Ahora sale, y el
submenu **se filtra por su cuenta**: a un juego de Linux no se le ofrecen las
filas de Wine, y a uno de Windows no se le ofrece el runtime. Las dos de Mesa
—Zink y la memoria de video— y la superposicion salen en los dos, porque son
del driver y del cliente de Steam, no de Wine.

**"Tampoco puedo crear un prefijo propio para los juegos, solo con AppImage."**
El mecanismo ya estaba: un juego de Linux no tiene prefijo de Wine pero si su
mundo aparte, la **carpeta personal** donde van sus ajustes y sus partidas, y
`home_portable` ya sabia dar una propia por juego con el mismo ajuste que el
prefijo. Lo que faltaba era **por donde tocarlo**: la fila del prefijo tambien
se vaciaba en los juegos nativos. Con un AppImage se podia porque existe el
convenio `<lanzador>.home` y la carpeta se puede crear a mano; desde el menu,
no habia forma.

Ahora hay una fila propia:

**Ajustes del juego → Carpeta personal del juego: compartida / propia**

Compartida sigue siendo lo de siempre (`WProton.home` para todos, porque un
juego de Linux suele guardar cuatro ficheros y mil carpetas casi vacias no
aportan nada) y propia da `<juego>.home`, aislada. Si el juego trae su propia
`.home` al lado del lanzador, manda esa y este ajuste no se usa.

## Instalar un juego desde una ISO, con el mando

Se pidio asi: una opcion en *Añadir un juego* que monte una ISO y cargue su
`setup.exe`; que en ese modo el **stick derecho sea el raton** con su clic; que
la instalacion tenga un **perfil exclusivo**; y que al acabar pregunte si se
quiere el wsquashfs **con el prefijo y el juego** o **solo el juego**.

Ahora, en **Añadir un juego**, el navegador enseña tambien las imagenes de
disco. Al elegir una, WProton hace todo el camino:

**1. Abre la imagen. MONTANDOLA, sin copiar nada.** Lo dijo Dani: *"podriamos
usar mejor fuseiso y nos ahorramos muchos gigas por el camino y ganamos
tiempo"*. Y de sobra: una ISO de DVD son 4-8 GB que se copiaban al disco para
borrarlos media hora despues. Montada, la imagen se lee donde esta: **tarda
cero y no ocupa nada**.

Se prueba por este orden, y cada paso tiene su motivo:

| | Como | Por que ahi |
|---|---|---|
| 1 | **fuseiso**, si ya esta | No pide nada a nadie: instantaneo y sin red |
| 2 | **udisks** | Monta **el kernel**, asi que entiende tambien **UDF** —los DVD modernos—, donde fuseiso se queda corto. No hace falta ser root y en SteamOS y CachyOS esta casi siempre |
| 3 | **fuseiso**, bajandolo | Por si no hay udisks. Mismo camino que `squashfuse_ll`: nuestro repositorio, binario estatico, paquete de la distribucion |
| 4 | **extraer con 7zz** | Siempre funciona, y es lo unico que cuesta espacio y tiempo |

fuseiso va antes que udisks **solo si ya esta**: montar con lo que hay no pide
nada. Si hay que bajarlo, se prueba antes udisks, que no necesita descargar.

Dos detalles que no se ven y que importan:

- **La imagen se monta de SOLO LECTURA** (`loop-setup -r`). Una imagen es el
  original del juego y un instalador no tiene por que poder tocarla.
- **Si fuseiso monta la imagen VACIA —una UDF pura— se nota ahi mismo** y se
  pasa a la via siguiente, en vez de descubrirlo tres pasos despues buscando un
  `setup.exe` en la nada.

**Y si no hay manera de montar, se extrae**, como antes: con el 7-Zip que ya
trae, **comprobando el sitio antes de empezar** —si no cabe lo dice con los
numeros— y, ya que va a costar varios GB, **mirando primero dentro de la imagen
sin extraerla** (`7zz l`) para no gastar cuatro gigas y descubrir despues que
ese disco no trae instalador.

**Sobre pycdlib**, que tambien se propuso: lee ISO en Python puro, pero **no es
un sistema de ficheros**. Wine no puede leer el disco a traves de el, asi que
habria que extraer igual y no se ahorraria ni un byte; y su propio repositorio
tiene imagenes UDF que no abre. Para mirar dentro sin extraer ya vale 7zz. Queda
escrito en el codigo para no volver a plantearlo dentro de tres meses.

**2. Busca su instalador, preguntandoselo al disco.** Un CD de juego trae un
`autorun.inf` con la orden que Windows ejecuta al meterlo:

```
[autorun]
open=setup.exe
shellexecute=Autorun\Autorun.exe
```

Eso es **mejor que adivinar por nombres**: hay discos donde `setup.exe` es el de
DirectX y el del juego se llama de otra forma. Se entienden las barras
invertidas, los finales de linea de Windows, los argumentos que lleve detras
(`open=setup.exe /autorun`) y las mayusculas —en un CD viejo el fichero esta
como `SETUP.EXE` y el autorun dice `Setup.exe`; en Windows da igual y aqui
no—. Si el disco no lo dice, se buscan `setup`, `install`, `instalar`,
`autoplay` y `autorun`, la raiz primero. Y **si hay varios, se pregunta**:
elegir a boleo entre el instalador del juego y el de DirectX es justo el
acierto que sale caro.

**3. Prepara un perfil exclusivo para la instalacion** (`instalador_<juego>`),
con tres cosas que hacen falta y solo ahi:

- **prefijo propio**, porque un instalador escribe en el registro de Windows y
  deja dependencias, y eso no tiene que caer en el prefijo compartido. Es
  ademas lo que hace posible el paso 5: empaquetar "con el prefijo" necesita un
  prefijo que sea solo suyo.
- **el disco en la unidad D:, declarada CD-ROM**, porque muchos instaladores
  comprueban que el disco este puesto antes de empezar y bastantes leen los
  datos de la unidad en vez de copiarlos.
- **el mando como raton**: stick **derecho** mueve el puntero, **A** es el clic
  izquierdo y **B** el derecho. Un instalador se maneja pulsando "Siguiente",
  y en una Deck en modo Juego no hay raton ni teclado. Si ya habia un `.keys`
  de una instalacion anterior **no se pisa**.

**4. Abre el instalador** y te dice por adelantado que vas a ver: el nombre del
instalador, que el disco esta en D: y como se mueve el puntero.

**5. Al acabar, te dice donde ha quedado el juego.** Antes esto era "navega por
`drive_c` y encuentralo", que obliga a saber si el instalador eligio *Program
Files*, *Program Files (x86)*, *GOG Games* o la raiz. Ahora WProton mira esos
sitios y **ofrece los candidatos**, sin colar `windows`, `users` ni
`ProgramData`, que no son el juego. Buscarla a mano sigue estando, por si el
juego fue a otra parte.

**6. Y la pregunta del final**, tal cual se pidio:

| | Que hace |
|---|---|
| **Con el prefijo Y el juego** | Archivo autosuficiente: dentro va el `drive_c` con lo que el instalador dejo en Windows (DirectX, VC++, el registro). Funciona en otro equipo sin instalar nada, a cambio de tamaño |
| **Solo el juego** | Solo la carpeta del juego. Antes de comprimir **se saca del prefijo** y se deja en la carpeta de juegos: comprimirlo dentro de `drive_c` dejaria el original colgando de un prefijo que luego se borra |
| **Nada por ahora** | Se queda instalado en su prefijo y se puede empaquetar cuando sea, desde *Ajustes del juego → Empaquetar con su prefijo* |

**Al cerrar, cada forma de abrir se cierra como le toca**, y confundirlas seria
grave:

- **montada** → se **desmonta** (y con udisks se suelta ademas el dispositivo
  de loop, o se queda ocupado hasta reiniciar). El punto de montaje se retira
  con `rmdir`, que **falla si queda algo dentro**: es justo la garantia que
  hace falta, porque si el desmontaje no fue bien no se borra nada. **En ese
  camino no hay ni una orden de borrado recursivo**: un `rm -rf` sobre un punto
  de montaje borraria el contenido de la imagen, o lo que hubiera debajo si el
  montaje ya no estaba.
- **extraida** → se ofrece **borrarla**, porque son varios GB, y solo alcanza a
  carpetas con nuestra marca en el nombre.

La imagen original **no se toca nunca**, y si la instalacion se quedo a medias,
decir "no" deja repetirla sin volver a abrirla.

Dos detalles de los que no se ven:

- **Una ISO ya no se trata como un comprimido.** Antes caia en el camino de los
  zip: se abria y se empaquetaba lo extraido *como si fuera el juego*, con lo
  que el `.wsquashfs` acababa llevando dentro el **instalador** en vez del
  juego. Una ISO de instalacion hay que instalarla.
- **El `.bin` no cuenta como imagen, a proposito.** Los instaladores de GOG
  vienen troceados en `setup-juego-1.bin` y los recompone el propio instalador;
  tomarlos por imagenes mandaria un juego de GOG por el camino equivocado.
  Tampoco el `.cue`, que es el indice y no la imagen.

Y una de las lecciones de siempre: la lista de extensiones que el navegador
enseña estaba **duplicada en los dos motores de menus**, y WProton elige el
motor solo. Si solo se toca una, la misma ISO se puede importar o no segun el
equipo. Estan las dos, y ahora hay una prueba que las compara.

## Un juego de Linux ya sale como "el ultimo jugado"

Dani, probando lo de arriba: *"he detectado un problema al ejecutar el juego en
sh, y es que no aparece como ultimo juego despues de ejecutarlo"*.

Era verdad, y es **otra vez el mismo descuido de este programa**: hay cuatro
caminos que lanzan un juego y el recado estaba en dos.

```
launch_game            imagenes .wsquashfs   -> lo apuntaba (su propia copia)
launch_loose_exe       un .exe suelto        -> lo apuntaba (otra copia)
lanzar_script_si_existe un .sh de la lista   -> NADIE
lanzar_nativo_suelto   un .sh elegido a mano -> NADIE
```

Y hay un detalle que explica por que sobrevivio tanto: en esos dos caminos
nativos ya se habia arreglado una vez lo de las estadisticas, y el comentario
que quedo escrito decia que sin eso el juego *"no salia como ultimo juego
lanzado"*. **Son dos cosas distintas que se parecen mucho:**

| | Donde se escribe | Para que |
|---|---|---|
| `PLAY_COUNT`, `LAST_PLAYED` | en el **perfil** del juego | las partidas y la "ultima vez" de su ficha |
| `LAST_GAME` | en los **ajustes** | el **"Jugar al ultimo"** del menu principal |

`stats_record` escribe las primeras. Nadie escribia la segunda. El comentario
daba por hecho que aquel arreglo cubria las dos, asi que el fallo se quedo
escondido detras de una nota que decia lo contrario.

Ahora hay **un solo sitio** que lo hace —`ultimo_juego_recordar`— y lo llaman
los cuatro caminos. Guarda la **carpeta** y no el lanzador, porque "Jugar al
ultimo" se lo pasa a `play_folder`, que es quien sabe encontrar el `.sh` otra
vez; con la ruta del `.sh` tambien arrancaria, pero el menu enseñaria
*"Mi Juego.sh"* en vez de *"Mi Juego"*. Y si es un `.exe` metido muy adentro
—`.../Binaries/Win64/juego.exe`— sube hasta la carpeta que de verdad
identifica al juego, que es algo que ya hacia uno de los dos caminos y ahora
hacen todos.

**La auditoria pidio su parte, y con razon.** Tenia un contrato que exigia que
los dos caminos grandes llamaran a `save_settings` al lanzar... que es
justamente lo que hacian **cada uno con su copia del codigo**. Ese contrato se
ha cambiado por uno mas estricto: ahora exige `ultimo_juego_recordar`, asi que
lo vigilado no es "guarda los ajustes" sino "apunta el ultimo juego", que es lo
que importaba. Y de paso la auditoria cazo un fallo que acababa de meter al
simplificar: al quitar el bloque viejo de `launch_game` se fue con el la
definicion de `abs_squash`, que se usa once veces mas abajo —con `set -u`, eso
mata el programa al lanzar cualquier juego—. Lo canto antes de que saliera de
aqui.

## Un lanzador que hay que pulsar con el raton, en el modo Juego

Dani: *"este juego tiene un lanzador que hay que pulsar play con el raton, en
el escritorio funciona sin problema pero en modo juego no nos deja. He probado
a crear un raton virtual pero sigue igual"*.

Lo del raton virtual es una confusion facil de tener, y conviene aclararla
porque son dos cosas distintas:

| Lo que se pone | Lo que crea | Para que sirve |
|---|---|---|
| **Mando virtual** | un **mando** | juegos que no ven el mando de la Deck |
| **Raton con el mando** (bloque `mouse` de un `.keys`) | un **puntero** | justo esto: pulsar botones con el stick |

El puntero lo crea el mapeador a partir del bloque `mouse` de un `.keys`, y lo
movia **por uinput**, o sea un raton de verdad para el sistema. Aqui se dijo que
por eso funcionaba igual en el modo Juego que en el escritorio. **No era
verdad**, y lo cuenta la seccion siguiente: en el modo Juego ese puntero no
llega al juego. Se quedo escrito a proposito para que se vea de donde venia el
siguiente arreglo.

**Se podia hacer ya**, pero habia que entrar al editor de teclas y saber que ahi
dentro hay un *"Raton con el mando"*. Ahora hay un atajo donde se busca:

**Ajustes del juego → Casos especiales → El mando como raton (lanzadores)**

Stick **derecho** mueve el puntero, **A** o **R2** hacen el clic izquierdo y
**B** el derecho. Sale en todos los juegos, no solo en los de Linux: un lanzador de
Windows tiene exactamente el mismo problema.

**Y no se lleva por delante lo que ya hubiera.** Si el juego ya tenia teclas
configuradas se le añade SOLO el bloque del raton, descomponiendo el `.keys` y
volviendolo a componer, que es lo que hace el editor. Las dos formas cortas que
parecen valer no valen, y las dos se probaron antes de dar con esta:

- `raton-poner` sobre el `.keys` final escribe en el **nivel superior** del
  fichero —esa funcion esta hecha para el TEMPORAL del editor—, asi que deja
  campos que no lee nadie y el raton sigue sin aparecer;
- componer pasandole solo el raton mete el raton bien... y **deja las acciones
  en las de fabrica**: las teclas del usuario se pierden.

Y si el juego ya tenia raton configurado —aunque sea con el stick izquierdo—
**manda el suyo**: ahi decidio el usuario.

**De paso, una linea del registro que mentia.** La que apunta lo que Steam deja
puesto decia *"heredado de Steam -> LD_PRELOAD=..."* mirando solo si la variable
existia. Pero WProton la **desexporta** al arrancar: sigue en el shell y el
juego NO la recibe. En el registro del 17/10 salia como heredada cuando no lo
era, que es justo el dato que luego se usa para diagnosticar. Ahora se mira si
esta exportada de verdad y se dice cual de las dos cosas es.

## El puntero en el modo Juego: la comparacion que lo explica

El atajo del mando como raton no arreglo el caso. Dani: *"esto sigue
fallando"*, con una foto en la que el puntero sale como una **X** pegada al
boton *Play*.

### El primer intento, y por que se volvio atras

De la X salio una teoria: en el modo Juego hay **dos servidores X** -gamescope
monta un XWayland para Steam y otro para el juego- y el puntero en forma de X
es el cursor por defecto de una ventana raiz, el que se ve cuando el puntero no
ha entrado en ninguna ventana. De ahi a mover el puntero **dentro** del
servidor X del juego con XTEST, que es lo que hace `xdotool`.

Funcionaba en la prueba y **en la Deck fue peor**: *"con este cambio fue peor,
creo que estás buscando algo más complicado de lo que es"*. Y tenia razon. La
premisa estaba mal: el puntero que se VE en el modo Juego no es el del XWayland
del juego, asi que moviendo ese se mueve uno que no se ve, mientras el que si
se veia —el del raton uinput— deja de moverse.

**Se volvio atras.** El raton del mando vuelve a ir por uinput, como desde la
2.01. El codigo de XTEST se queda para poder probarlo (`WP_RATON_XTEST=si`),
pero no decide nada por su cuenta.

### Lo que si dicen los registros

Dos registros del **mismo juego, el mismo dia, con siete minutos de
diferencia**:

| | Escritorio (18:50) — va | Modo Juego (18:57) — no va |
|---|---|---|
| Sesion | Wayland (KDE) | x11 (gamescope) |
| Pantallas X | 1 (`:0`) | 2 (`:0` y `:1`) |
| Steam Input | **no activo** | **ACTIVO** |
| Puntero | `:0=(349, 290)`, moviendose | `(1279, 799)`, siempre |
| Clics en el registro | — | **ninguno** |

`1279x799` es **la esquina de abajo a la derecha** de una pantalla de 1280x800.
El puntero no es que fuera mal: se iba al borde y se quedaba. Eso no es cosa de
dos servidores X: es la firma exacta de **un stick que no descansa en cero**.

Y la segunda linea de la tabla es igual de clara: en todo el registro **no hay
ni un clic**. El puntero se movia (a la esquina) y el boton no salia nunca.

### Los tres arreglos que salen de ahi

**1. La zona muerta se le pregunta al mando.** Era un 12% fijo sobre un centro
supuesto. Cualquier mando que descanse por encima de ese 12% empuja el puntero
a una esquina y no hay forma de apuntar a nada. Ahora se lee del propio mando
—su `flat` por tres, como ya se hacia con las direcciones desde hace tiempo— y
**el reposo de verdad se aprende del primer valor que manda el eje**: al
arrancar el juego nadie esta tocando el stick, asi que ese es su cero aunque el
mando diga otra cosa. Las direcciones ya se calculaban asi (*"Umbral de ABS_RX:
11468, el perfil decia 16000"*); el raton se habia quedado atras.

De paso se escala **desde el borde de la zona muerta** y no desde el centro: si
no, al salir de la zona el puntero pegaria un salto del tamaño de la zona.

**2. El umbral del gatillo, tambien del mando.** Era `> 64` a pelo, que da el
25% en un gatillo de 0-255 y practicamente cero en uno de 0-32767. Ahi el clic
izquierdo se quedaria **pulsado solo**, y con el boton enganchado no se puede
pulsar nada.

**3. El clic izquierdo, en dos botones.** Era solo `r2`. Delante de un boton
*Play*, lo que hace cualquiera es pulsar la **A**. Ahora van los dos a la vez
(`"click_left": "a,r2"`), y el `.keys` admite una lista separada por comas en
los tres botones.

### Y el registro, para que la proxima vez conteste solo

- El reposo, el recorrido y la zona muerta de cada eje, en cuanto llega el
  primer evento: `[keys] Raton ABS_RX: reposo 9257, recorrido 32767, zona
  muerta 3932 (el mando declara flat=...)`.
- Cuanto se mueve el puntero y con que valores crudos del stick, una linea cada
  dos segundos: `[keys] Raton: +212,+180 px en 2.0 s (stick en 9257,11439;
  reposo 0,0)`. Un mando que no reposa en cero se ve a la primera.
- **Cada clic**, el analogico y el digital. Esa era la linea que faltaba.
- Y de donde sale el puntero en cada sitio, al lanzar: con Steam Input activo
  los trackpads no son un raton (los reparte Steam segun la disposicion del
  atajo, que de fabrica es *Gamepad*); en el escritorio si lo son, por el modo
  lagarto.


## El panel dice en que formato esta el juego

El panel de la derecha, el de **SELECCIÓN**, tiene una fila nueva: **Formato**.
Dice `.wsquashfs`, `.squashfs`, `.dwarfs`, `.pc` o `Carpeta`.

Sale **de la ruta real**, nunca del nombre que se ve en la lista. Es la parte
que importa: el nombre de la lista puede llevar o no la extension, puede
llevar pegado de que carpeta de juegos viene, y en dos juegos repetidos uno
conserva su nombre completo. Sacar el formato de ahi lo ataria a como se
dibuja la lista.

Una carpeta `.pc` es las dos cosas —carpeta y extension conocida— y manda la
extension, que dice mas. Y un fichero **sin** extension no es una carpeta: se
comprueba de verdad si la ruta es un directorio, en vez de dar por hecho que
lo que no tiene extension lo es.

El manifiesto de la biblioteca pasa de nueve campos a diez, en **las dos
vias** —la rapida en Python y la lenta en bash— y en **los dos motores** de
menus, pygame y Qt. Tenian que cambiar las dos a la vez: WProton compara una
contra otra cuando se le pide, y si una pone el campo y la otra no, saldria un
aviso de "no coinciden" en cada arranque.

## Y, si quieres, la extension tambien en la lista

Lo pidio Dani: *"sobre lo de mostrar la extensión también estaría bien una
opción en Biblioteca y preferencias para poder mostrar la extensión en el modo
lista, por defecto estaría desactivado"*.

**Biblioteca y preferencias → Extensión en la lista: no / sí.** Apagada de
fabrica, que es lo razonable: al jugar interesa el nombre del juego. Encendida
se ve `Halo.wsquashfs` en vez de `Halo`, que es lo que hace falta cuando tienes
la biblioteca a medio convertir y quieres distinguirlos de un vistazo.

**Solo la lista.** En la rejilla no se enseña nunca, y ahi hay un motivo
tecnico que obligo a forzarlo: el recorte de la rejilla es un *"corta todo lo
que venga detras de .wsquashfs"*, heredado del bash de la 1.20. Con la
extension puesta se habria llevado por delante el `   (carpeta)` que se añade
cuando tienes varias carpetas de juegos, y el juego apareceria sin saber de
cual viene.

El campo **Formato** del panel no depende de esto: sale igual con la opcion
encendida que apagada.

## Una carpeta puede ser una estanteria, no un juego

Dani: *"en la opción jugar, cuando muestra un juego en carpeta, puede existir
la posibilidad de que sea una carpeta con juegos dentro, por ejemplo Lucha y
dentro estén Street Fighter, Mortal Kombat y Guilty Gear"*.

Hasta ahora esa carpeta salia en la lista **como un juego mas** —la
comprobacion de "esto es un juego" es generosa a proposito, para que nada se
quede fuera— y al darle no arrancaba nada. Ahora se abre y enseña lo que tiene
dentro.

**Como se distingue una estanteria de un juego**, que es la parte delicada:
una estanteria **no tiene ni un fichero suyo** en el primer nivel, solo
carpetas. Un juego siempre tiene algo ahi —un `.exe`, un leeme, un `.dll`, un
`.ini`—, aunque el ejecutable de verdad este tres niveles mas abajo. Esa es la
linea, y es la unica que separa bien los dos casos sin pedirle nada al
usuario.

Se perdonan la caratula y los textos sueltos (no arrancan nada, y es muy normal
dejarlos al lado), y tambien los `.wsquashfs`: una carpeta con cuatro paquetes
dentro es justamente una estanteria.

Y se exigen **dos juegos o mas**. Con uno solo lo mas probable es que sea un
juego que lo guarda todo en una subcarpeta, y convertirlo en estanteria seria
meter un paso de mas por el camino. Tampoco lo es nunca una carpeta `.pc`, una
con `drive_c` ni una con `autorun.cmd`: esas ya se saben juego por otra via.

Funciona igual al **jugar** y al abrir los **ajustes** (la X sobre el juego):
en los dos sitios se pregunta primero cual de los de dentro.

## Un tercer lanzador para DeckStation: `--saves`

En ES-DE cada sistema puede tener varios lanzadores, y los dos que ya habia
llaman a WProton para **jugar**. Ahora hay un tercero que abre el gestor de
partidas guardadas del juego marcado, **sin arrancarlo**:

```xml
<command label="WProton (Saved Games)">./Apps/WProton/wproton.sh --saves %ROM%</command>
```

No hay menu nuevo: es el mismo **Partidas guardadas de [juego]** de siempre, el
de *Ajustes del juego*. Lo unico que se añade es la puerta de la calle.

El juego no se nombra en ningun sitio —`%ROM%` es lo que pone ES-DE—, asi que
la entrada vale para todos y DeckStation se puede mover de carpeta sin tocar
nada. La ruta se junta con `cli_ruta`, el mismo arreglo que ya tienen `--exe` y
`--config`, por si el frontend llama sin entrecomillar y el nombre lleva
espacios. Y se acepta con `-e` y no con `-f`: un juego tambien puede ser una
carpeta.

## Y un cuarto: `--keys`, el editor de teclas

Igual que `--saves`, pero abriendo el editor de teclas del mando:

```xml
<command label="WProton (Keys Games)">./Apps/WProton/wproton.sh --keys %ROM%</command>
```

Tampoco hay menu nuevo: es el mismo *Mapeador .keys* de *Ajustes del juego*.
Aqui si se arranca el servidor de menus a mano, porque el editor pinta lo suyo
y conviene tener la ventana puesta desde el principio.

## El nombre y el idioma que deja puestos el crack

Dani, sobre la instalacion desde imagen: *"que examines la carpeta crack y
mires en qué fichero guarda la información del username y lenguaje y los
cambies, por ejemplo Rune por Deck y english por spanish"*.

Lo que hay dentro de esa carpeta es un emulador de la API de Steam, y lleva su
configuracion al lado. Ahi esta escrito el nombre del jugador —de fabrica, el
del grupo que hizo el release— y el idioma que se le pide al juego. Al
arrancar, el juego saluda con *"Hola, RUNE"* y se pone en ingles.

**Por el nombre del fichero no se puede ir.** Cada emulador llama al suyo de
una forma —`steam_emu.ini`, `ALI213.ini`, `SteamConfig.ini`, `OnlineFix.ini`,
`SmartSteamEmu.ini`…— y la lista siempre se queda corta. Lo que no cambia es
que **dentro** hay una clave de nombre y otra de idioma, asi que se busca por
el contenido:

| Emulador | Fichero | Nombre | Idioma |
|---|---|---|---|
| CODEX y compañía | `steam_emu.ini` | `UserName=` | `Language=` |
| ALI213 | `ALI213.ini`, `SteamConfig.ini` | `PlayerName=` | `Language=` |
| Goldberg | `steam_settings/*.txt` | `force_account_name.txt` | `force_language.txt` |

Goldberg es la excepcion al "por contenido": no usa un `.ini`, usa **un fichero
por ajuste**, asi que esos se buscan por nombre porque es lo unico que tienen.
Y se exige que cuelguen de `steam_settings` o que empiecen por `force_`, porque
un `language.txt` suelto puede ser perfectamente del juego.

**Lo que no se toca:**

- Un `.ini` del juego que no lleve ninguna de esas claves.
- Un `Language=3`: hay emuladores que guardan ahi un numero de su propia tabla,
  y ponerles `spanish` los dejaria sin idioma. Se avisa en el registro y se
  deja como esta.
- La clave, tal como este escrita: `PlayerName = Nah` sale como
  `PlayerName = Deck`, con sus espacios.
- Los **finales de linea**. Estos ficheros vienen de Windows y casi todos traen
  CRLF. Editando con el `\r` dentro, el `.*` del `sed` se lo lleva y esa linea
  se queda en LF mientras el resto sigue en CRLF: un fichero a medias que falla
  **solo en la linea que hemos tocado**, que es el peor fallo posible de
  encontrar. Se quita, se edita y se vuelve a poner.

De cada original se guarda copia (`*.wproton.bak`), y a la segunda pasada **no
se pisa**: la copia buena sigue siendo la primera.

El idioma sale del de WProton —quien pone los menus en castellano quiere el
juego en castellano— y si no, del sistema, traducido a los nombres que usa
Steam (`spanish`, `brazilian`, `koreana`, `tchinese`…). El nombre, del usuario
del equipo: en una Deck es `deck`, con la inicial en mayuscula, que es justo el
ejemplo que puso Dani.

**Va antes de empaquetar, no despues.** Dentro de un `.wsquashfs` la carpeta es
de solo lectura y el nombre se quedaria para siempre como lo dejo el grupo.

**Y si el crack no esta aplicado**, WProton lo ve —compara lo que hay en la
carpeta de la imagen con lo que hay en el juego instalado— y ofrece copiarlo
encima. Eso **si se pregunta**: sobrescribe ficheros del juego, y eso no se
hace sin avisar.

Se puede repetir cuando se quiera, mientras el juego siga siendo una carpeta:
**Ajustes del juego → Casos especiales → Nombre e idioma del juego instalado**.

**El nombre, de fabrica, es `Deck`.** La primera instalacion de verdad puso
`UserName=Dani` —el usuario del sistema— y Dani lo vio enseguida: queria
*Deck*. Y tiene razon, porque ese nombre sale **en la pantalla del juego**, no
en el sistema: ahi uno quiere el nombre de la maquina con la que juega, no su
cuenta de Linux. Se cambia en **Biblioteca y preferencias → Usuario instalación ISO**, y si
se deja vacio se vuelve a lo de antes.

**El puntero del instalador va mas lento.** Tambien de la primera instalacion
de verdad: *"podrías bajar un poco la sensibilidad del stick derecho en el
instalador"*. En un juego el puntero sirve para mirar alrededor y cuanto mas
suelto mejor; en un instalador hay que acertar en un *Siguiente* de treinta
pixeles, y a 900 px/s se pasa de largo una y otra vez. El instalador va a 450;
el atajo de *Casos especiales*, que es para jugar, se queda a 900.

## La imagen se quedaba montada, y era una subshell

Dani: *"veo que se queda la imagen montada en el sistema, desmontala al acabar
la instalación"*.

El cierre estaba escrito y se llamaba donde debia. Lo que fallaba era mas
tonto: `iso_montar_udisks` dejaba el dispositivo de loop en una variable,
pero se la llama **dentro de `$( )`** —o sea, en una subshell—, asi que la
variable se ponia alli y **se perdia al volver**. Al cerrar estaba vacia, no
se llamaba a `udisksctl` y la imagen se quedaba montada en `/run/media`, a la
vista en todo el sistema.

Ahora el loop vuelve por la salida estandar junto al punto de montaje, que es
lo unico que cruza una subshell. Y de paso, el cierre dejo de ser confiado:

- Si el loop no se sabe por lo que sea, **se le pregunta a `/proc/mounts`**:
  ahi esta el dispositivo que hay montado en esa carpeta.
- **Con udisks se desmonta con udisks, y primero.** `umount_dir` esta hecho
  para FUSE; sobre un montaje del kernel gastaba cinco reintentos con su
  espera para nada antes de llegar a quien si podia.
- **Insiste tres veces** y, si sigue ahi, **fuerza**: hay instaladores que
  dejan algun fichero abierto un rato despues de terminar.
- El dispositivo de loop **se suelta siempre**, aunque el desmontaje se haya
  torcido: si no, se queda ocupado hasta reiniciar.

**Y si WProton no llega a cerrarla** —un corte, un cierre a lo bruto, un fallo
a mitad— queda una nota con el loop y el punto de montaje. **Al arrancar, lo
primero que hace es cerrar lo que quedara abierto**, y lo dice en el registro.

---

# Lo que ya venia en la 2.03

## Saber cual de los mandos se esta usando, y proponer los ajustes

WProton ya apuntaba en el registro los mandos que ve el sistema, pero eso es
una LISTA, no una respuesta. En una Deck -o en un escritorio con Steam abierto-
lo normal es ver dos: el fisico y el `Microsoft X-Box 360 pad 0`, que es el
virtual que ofrece Steam Input. Y los dos ajustes de mando del juego dependen
de cual va a usar el juego, no de cuantos hay.

**Por el nombre no se distinguen**: el virtual de Steam se hace pasar por un
Xbox 360, asi que nombre y fabricante:modelo son identicos a los de uno de
verdad. Lo que si distingue:

- el sysfs, porque los virtuales cuelgan de `/devices/virtual/`;
- la lista `SDL_GAMECONTROLLER_IGNORE_DEVICES`, donde Steam mete el fisico
  cuando lo esconde;
- y sobre todo **cual manda eventos cuando mueves el stick**, que no se deduce:
  se mide.

Asi que en *Ajustes del juego → Mandos* hay un **Detectar el mando que usas y
proponer ajustes**: escucha unos segundos, te pide que muevas el stick del
mando que quieras usar, y con eso dice cual es y que le toca a ese juego:

- si el activo es el virtual de Steam, propone el **puente Steam Input →
  XInput** (su "automatico" solo se enciende cuando el virtual es el UNICO
  mando, asi que este es justo el caso en que hay que pedirlo a mano);
- si es un DualSense o un DualShock de verdad, propone el **arreglo de mandos
  Sony**;
- y si no hay nada que cambiar, lo dice y no toca el perfil.

**Si nadie mueve nada, NO se inventa un ganador.** Decir "el activo es el
primero de la lista" seria exactamente el error que esto viene a corregir: se
dice que no se ha podido saber y se deja todo como estaba. Lo mismo con un
mando quieto: un pad parado manda sincronizaciones y ejes en reposo, y si eso
contara ganaria siempre el primero, asi que solo cuentan las pulsaciones y los
ejes empujados de verdad.

De paso, un fallo que cazo la prueba: la lista de Steam se parseaba con
`lstrip('0x')`, que no quita el prefijo `0x` sino **todos los ceros y equis del
principio**, de modo que `045e:028e` se quedaba en `45e:028e` y no casaba con
nada; y el formato real de Steam lleva barras (`0x045e/0x028e`), que tampoco se
partian. Ahora no se parsea un formato concreto: se sacan los grupos de cuatro
digitos hexadecimales y se emparejan, venga escrito como venga.

## Un juego con su prefijo dentro del archivo no arrancaba

Lo encontro Dani con Grandia HD Remaster: un juego que trae su propio prefijo
dentro del `.wsquashfs` -estilo Batocera, hecho con Wine a secas- moria **en
tres segundos, en cada intento**. En el registro, Proton reventaba asi:

```
File ".../proton", line 999, in pfx_copy
    os.symlink(contents, dst)
FileExistsError: [Errno 17] File exists:
  '.../files/lib/wine/i386-windows/wmplayer.exe' ->
  '.../pfx/drive_c/Program Files (x86)/Windows Media Player/wmplayer.exe'
```

Leyendo el codigo de Proton (`proton`, de ValveSoftware) salieron **dos
errores**, y uno de ellos llevaba aqui desde el principio.

### 1. Faltaba el centinela de creacion (esto era lo que tumbaba el juego)

```python
if not file_exists(self.creation_sync_guard, follow_symlinks=False):
        makedirs(self.prefix_dir + "/drive_c")
        ...
        self.copy_pfx()
```

con `self.creation_sync_guard = self.path("pfx/creation_sync_guard")`. Un
prefijo que viene en un archivo NO tiene ese fichero, asi que Proton creia que
tenia que **crear el prefijo desde cero encima del que ya estaba**, y `copy_pfx`
reventaba al primer fichero que ya existia.

Ahora WProton pone ese centinela, que es decirle la verdad: este prefijo ya
esta creado. Y es seguro saltarse SOLO esa parte, porque el resto de
`setup_prefix` usa `try_copy`, que borra el destino antes de copiar:

```python
if file_exists(dst, follow_symlinks=False):
        os.remove(dst)
```

Lo unico que no lo era es `copy_pfx`, que es justo lo que el centinela salta.

### 2. En `version` se escribia el nombre del runner, y Proton compara otra cosa

WProton escribia `GE-Proton11-6` en `<compatdata>/version`. Pero Proton no
compara eso con nada: compara con una constante propia.

```python
CURRENT_PREFIX_VERSION="11.0-100"
...
def upgrade_pfx(self, old_ver):
        if old_ver == CURRENT_PREFIX_VERSION:
                return
```

Es la version del **formato** del prefijo, no la del runner: cambia cuando
cambia el formato, no cuando cambias de Proton. Escribiendole el nombre del
runner pasaban dos cosas y las dos malas: no coincidia nunca -asi que Proton
entraba siempre al camino de actualizacion- y encima `"GE-Proton11-6".split('-')`
le da **tres** trozos donde espera dos.

El comentario que habia en el codigo explicaba por que se escribia solo el
nombre, citando un `Upgrading prefix from 6.21-GE-2 to 6.21-GE-1` de hace años.
Y tenia sentido ENTONCES: en aquellos Proton la constante se parecia a la
version del runner, asi que el truco funcionaba por casualidad. Lleva roto
desde que Proton cambio a `11.0-100`.

Ahora se lee `CURRENT_PREFIX_VERSION` **del propio runner** (de su script
`proton`), asi que vale para cualquier version sin volver a tocar esto. Si el
runner es tan viejo que no la lleva, se cae al comportamiento de antes.

### Y dos cosas de las que se aprende leyendo registros

- La comprobacion de "ya esta marcado" volvia **antes** de poner el centinela.
  O sea que un prefijo con la version correcta y sin centinela seguia sin
  arrancar, para siempre. Ahora el centinela se pone primero y la prueba cubre
  ese caso exacto.
- Se comparaba una cosa y se escribia otra, por dos caminos distintos: de ahi
  que el registro dijera *"ya marcado para GE-Proton11-6-x86_64"* justo
  despues de haber escrito `GE-Proton11-6`. Ahora se escribe el mismo valor
  con el que se compara.
- De paso: `tr -d '\r' < fichero 2>/dev/null` no tapa nada cuando el fichero
  no existe, porque ese error lo imprime el shell al redirigir, antes de que
  `tr` llegue a correr. Cada prefijo nuevo dejaba un `version: No such file or
  directory` en el registro, con pinta de fallo sin serlo.

# WProton 2.02 — novedades

> **Muchas gracias a Michel, Fransis y MRDeu** por todas las horas de testeo que
> habeis metido a WProton. Sin vosotros este proyecto no habria sido posible.

Esta version trae dos cosas que pidieron los testers y que faltaban desde el
principio: **borrar un juego del disco desde WProton**, y todo lo que tiene que
ver con **traer y mantener al dia los perfiles de la comunidad**.

## Intercambiar los sticks, por juego

Lo pidieron para un juego que apunta con el stick derecho y que se maneja mucho
mejor apuntando con el izquierdo. En *Ajustes del juego -> Mapeador .keys ->
Intercambiar los sticks*: el juego ve el izquierdo donde estaba el derecho y al
contrario, y **el clic de cada stick se va con el suyo** -si apuntas con el
izquierdo, pulsarlo hace lo que antes hacia pulsar el derecho; dejarlo en su
sitio seria dejar el cambio a medias-.

**No lo hace el mapeador de teclas, y no podria.** Aquel convierte el mando en
PULSACIONES, y aqui lo que hace falta es que el juego lea los sticks al reves.
Eso solo se consigue presentandole OTRO MANDO, que es el trabajo del mando
virtual. Asi que si lo tenias apagado -como esta de serie- se enciende solo en
modo copia al lanzar ese juego, y queda dicho en el registro: pedir una opcion y
que no pase nada es el peor de los resultados.

A cambio, el mando virtual **captura el mando fisico**, asi que mientras juegas
se pierden la vibracion y el remapeado de Steam Input. Se avisa al activarlo. Se
combina con todos los modos que ya habia: Xbox, DualShock, clasico y la cruceta
al stick.

**Se guarda en el `.keys`, no en el perfil.** Es cosa de ESE juego, y asi viaja
con el: un `.keys` de la comunidad puede traer ya puesto "este juego se maneja
mejor apuntando con el izquierdo". Es una seccion propia de WProton que Batocera
ignora, asi que el fichero sigue valiendo alli:

```json
{ "sticks": { "swap": 1 } }
```

Por dentro, el intercambio se traduce **una sola vez, al leer el evento**, y de
ahi para abajo el bucle trabaja ya con el eje que vera el juego. Hacerlo al
escribir habria obligado a acordarse del cambio en los cinco sitios donde se
escribe un eje, y el primero que se olvidara dejaria el cambio a medias sin que
nada lo dijera.

### El fallo que dejo esta opcion sin funcionar

La primera version no funcionaba, y el motivo no estaba en el intercambio sino
en el guardado: **el editor no escribia el `.keys`**. Su comprobacion de "¿has
asignado algo?" miraba las teclas, las combinaciones y el raton, y se añadio el
intercambio sin sumarlo ahi. Asi que quien activaba SOLO eso -que es justo el
caso normal: el juego se maneja bien, lo unico que molesta es que apunta con el
derecho- se encontraba un *"No has asignado nada"* y no se guardaba nada. Sin
fichero no hay nada que leer al lanzar, asi que la opcion no existia: ni
funcionaba ni daba un error que lo explicara.

Es **el mismo error que ya se habia cometido con el raton** y que estaba
contado en un comentario justo encima de esa linea. Ahora lo cubren las
pruebas, y de una forma que sirve para la proxima: ademas de probar cada bloque
guardado por separado, la prueba **lee la condicion del `wproton.sh` generado**
y comprueba que nombra los cuatro temporales. El dia que se añada un quinto
bloque que se pueda guardar solo y no se sume ahi, salta la prueba en vez de
salir el fallo.

Y al guardar, el aviso dice *"Guardado (con los sticks intercambiados)"* cuando
es lo unico que se ha puesto: antes decia "Teclas guardadas" siempre, y quien
venia de activar el intercambio no veia su opcion mencionada en ninguna parte.

### Y si el mando no se puede capturar, se dice

El mando virtual **captura** el mando fisico para que el juego no vea los dos.
Si no puede -lo mas comun: que ya lo tenga cogido el mapeador `.keys`, lo que
pasa cuando ese `.keys` mapea el movimiento-, antes era un aviso suave de "el
juego puede ver los dos". Con los sticks intercambiados eso **no es un aviso,
es un fallo**: el juego lee tambien el mando fisico, con los sticks en su sitio,
y ese manda. Ahora se dice con todas las letras en el registro y se apunta el
motivo probable.

## Los registros de las sesiones que van bien se borran solos

Lo pidio Dani, y la razon es clara en cuanto se mira la carpeta: en DeckStation
cada juego lanza su propio `wproton.sh`, asi que una tarde de pruebas deja
decenas de registros, y los de las sesiones que fueron bien no le sirven a
nadie. Ahora, **al cerrar, si la sesion no dio ningun aviso ni error, su
registro se borra**; los que tienen algo se quedan.

**La decision se toma en el momento, no leyendo el registro al final.** Un grep
a posteriori seria adivinar, y de dos maneras: hay lineas que llevan la palabra
"error" hablando de otra cosa -las que explican un error ya arreglado-, y hay
salida que se escribe DIRECTA al fichero sin pasar por nuestro `log`, como el
`Proton: Error: unable to use parent for game drive` que sale en todas las
partidas y es inofensivo. Asi que cada aviso o error deja una marca cuando se
produce, por dos caminos: el NIVEL de la linea (todo lo que no sea INFO lo pone
quien la escribe a proposito) y el PRINCIPIO del texto, que es como avisan
`say "AVISO: ..."` y `fallo`/`die`.

La marca va en un **fichero** al lado del registro, no en una variable, por la
razon de siempre en este programa: medio WProton se ejecuta dentro de subshells
-los menus son `sel="$(menu ...)"`- y una variable puesta ahi dentro no llega al
padre. Un error dentro de un menu tiene que contar igual.

**Hay cinco casos en los que se conserva aunque no haya errores**, porque son
justo los registros que alguien va a querer leer: un cierre que no fue normal,
cualquier `DIAG_*` encendido -su unico producto es el registro-, el modo
desarrollo, y la primera puesta en marcha. Y el registro dice por que se queda:

```
Registro: se conserva (hubo avisos o errores)
Registro: se conserva (DIAG_MANDO=1)
```

**Y siempre se guarda el de la ultima sesion limpia.** Esto no es prudencia
generica: hay fallos que NO escriben ni un error, y el caso que lo enseño es de
esta misma version -un juego que se quedaba cargando y no entraba, cuyo
registro no tenia una sola linea de error porque el juego hasta abria su
ventana-. Ese registro fue exactamente el que hizo falta. Se ajusta con
`LOGS_OK_GUARDAR` (0 borra tambien el ultimo) o desde *Biblioteca y preferencias
-> Registros*, que ademas enseña cuantos hay y permite borrar los limpios ahora
mismo.

Dos detalles de los que se aprende tarde si no se piensan antes:

- **El borrado es lo ULTIMO del cierre.** Cualquier linea escrita despues
  resucitaria el fichero -el descriptor sigue abierto- y en la carpeta
  quedarian registros de cero bytes, que no sirven para nada y encima parecen
  un fallo.
- **Solo se borran los registros MARCADOS como limpios.** Los de versiones
  anteriores, y los de una sesion que murio de golpe, no llevan marca: a esos
  no se les toca aqui, de ellos sigue encargandose la limpieza por antiguedad
  (2 dias, 40 como maximo). Y esa limpieza ahora se lleva tambien las marcas
  huerfanas, que si no se quedarian ahi para siempre haciendo creer que existe
  un registro que ya no esta.

## El raton fisico en los menus: menos sensible

Esto es para quien usa WProton **con un raton**, en un sobremesa o en el modo
escritorio de la Deck. Dos cosas iban demasiado sueltas de serie:

- **La seleccion seguia al puntero SIN NINGUN UMBRAL.** Un pixel de movimiento
  -o un golpe en la mesa, o el puntero que ya estaba encima de otra fila cuando
  la lista se redibujaba- y te cambiaba de fila, incluso si estabas navegando
  con el mando. Con el raton quieto al lado del teclado, eso es un sobresalto
  constante. Ahora hay que moverlo unos pixeles antes de que mande, y se
  cuentan **desde la ultima tecla o boton del mando**: un roce no hace nada,
  pero en cuanto usas el raton de verdad la seleccion le sigue como siempre, sin
  retraso.
- **Cada muesca de la rueda saltaba un tercio de pantalla.** Se eligio asi
  pensando en recorrer listas largas sin raton, y con la rueda de un raton de
  sobremesa es brutal: una muesca y te has ido media biblioteca.

Ahora son 12 px de umbral y 3 filas por muesca, y se ajusta en *Biblioteca y
preferencias -> Raton en los menus* o en `settings.conf` (`RATON_UMBRAL`,
`RATON_RUEDA`). Los dos aceptan **0** para volver al comportamiento de antes,
porque esto es cuestion de gusto y de que raton tengas.

## Borrar un juego del disco desde WProton

Se podian borrar los DATOS de un juego, pero el juego habia que ir a borrarlo al
explorador de archivos. Ahora esta en *Ajustes del juego → Herramientas del
prefijo → **Borrar este juego DEL DISCO***.

Pregunta **una sola vez**, con el nombre del juego y lo que ocupa, y avisa de
que no se puede deshacer. Con el juego se va tambien lo que WProton guarda de
el -ajustes, prefijo propio, caratulas y ficha-, porque borrar el juego y
dejarse un prefijo de 12 GB colgando no es lo que nadie quiere, y encadenar un
segundo "¿y los datos tambien?" es como la gente acaba dandole a "si" sin leer.

**Las partidas se copian a `backups/` antes de borrar**, y si esa copia falla no
se borra nada: ni el juego ni los datos. Lo irreversible es el juego, no la
partida.

Los seguros, que en un `rm -rf` son lo importante:

- **Nada que este fuera de tus carpetas de juegos.** Se comparan las rutas ya
  resueltas, asi que no se escapa por un `..` ni por un enlace.
- **La carpeta de juegos entera no se borra nunca**, solo algo de dentro.
- **Un acceso directo se quita, no se sigue.** Quien tiene los juegos en un
  disco externo y enlaces en la carpeta de juegos espera que se le quite el
  enlace, no que se le vacie el disco. Esto lo encontro una prueba: estaba
  mirando el enlace DESPUES del seguro, y como un enlace apunta fuera de la
  biblioteca a proposito, el seguro lo rechazaba y no habia forma de quitarlo.
- **No se borra un juego que se este jugando.**
- Y el identificador se valida antes de tocar nada: vacio o con `../` dentro se
  rechaza, porque de ahi salen los borrados en sitios que nadie pidio.

Por dentro, el inventario de lo que cuelga de un juego y el borrado se han
separado del dialogo, asi que "Borrar los datos" y "Borrar el juego" usan
exactamente el mismo criterio y el mismo codigo. Dos listas de lo que hay que
borrar se habrian separado en cuanto se añadiera algo nuevo a una.

## Traer de golpe los perfiles del repositorio

**Biblioteca y preferencias → Perfiles del repositorio**, con dos opciones que
hacen cosas distintas:

### Traer los de tus juegos (los instala)

Cruza tu biblioteca con `profiles/` e instala de una vez todas las
configuraciones que te corresponden, con sus `.keys` cuando los haya. Quedan en
`profiles/` con el nombre de **tus** juegos, listas para jugar.

Pregunta **una sola vez**, antes de empezar -no un dialogo por juego-, que hacer
con los juegos que ya tienen perfil:

- **Solo los que aun no tienen perfil** (lo que viene marcado). Lo que hayas
  ajustado a mano no se toca.
- **Tambien sustituir los que ya tienen.** El tuyo se guarda como `.conf.bak`.

Al final dice cuantos entraron, cuantos traian teclas y cuantos de tus juegos
no conoce el repositorio.

### Traer TODOS a comunidad/

El repositorio entero, los 250, tengas sus juegos o no. Van a una carpeta
nueva, **`comunidad/`**, con el nombre que tienen alla (`Silver Pines.conf`).

No pueden ir en `profiles/` porque ahi cada fichero tiene que llamarse como el
juego de AQUI (`Silver_Pines.conf`) para que WProton lo encuentre, y porque el
menu de perfiles pasaria a tener cientos de entradas que no son tuyas. En su
propia carpeta no estorban a nada, se pueden abrir como ficheros de texto para
mirar o comparar lo que ha puesto cada uno... **y sirven para trabajar sin
conexion**:

- La lista de perfiles, cuando GitHub no contesta, se hace con esta copia. Con
  eso, buscar el perfil de un juego, saber si trae teclas y el menu de perfiles
  funcionan igual sin red.
- Instalar un perfil ya no sale a Internet si el fichero esta aqui: se copia del
  disco, al instante.

**Y es la PRIMERA parada al buscar el perfil de un juego.** Si el fichero ya
esta en `comunidad/`, no hay nada que preguntarle a GitHub -ni la lista ni el
fichero-: se instala del disco, al instante, y funciona igual sin conexion.
Solo si el juego no esta en la copia se sale a la red. Las **caratulas** siguen
saliendo del repositorio siempre: esto es solo para los perfiles.

Solo se descarga lo que falte, asi que volver a pulsarlo despues de que alguien
suba perfiles nuevos trae unicamente esos. Lo que no sea un `.conf` de verdad o
un `.keys` legible se descarta en vez de guardarse, y el aviso del final dice
cuantos eran: son ficheros mal subidos al repositorio, y nombrarlos es lo que
hace que se arreglen.

## Si el perfil de la comunidad mejora, te enteras

Hasta ahora, el aviso de "la comunidad tiene una configuracion para este juego"
solo salia cuando NO tenias ninguna. Asi que quien se bajo el perfil el primer
dia no se enteraba nunca de las mejoras posteriores: la version vieja se queda
puesta y nada vuelve a avisar. Lo pidieron desde el canal.

Ahora, al lanzar un juego cuyo perfil vino de la comunidad, WProton mira si en
el repositorio hay una version mas nueva y te la ofrece.

### Como se sabe, sin gastar ni una peticion mas

La idea evidente -preguntar por la fecha del ultimo commit de cada fichero- es
**una peticion por juego**, y con 60 peticiones por hora que da la API de GitHub
sin credenciales eso se agota con treinta juegos.

No hace falta: el listado de `profiles/` que WProton ya pide al arrancar trae,
por cada fichero, el **sha de su contenido**. O sea que la informacion de si un
perfil ha cambiado YA ESTABA llegando, sin usarse. Al instalar un perfil se
apunta ese sha, y comparar es gratis.

Y es mejor que una fecha: la fecha dice "esto se subio despues", que no es lo
mismo que "esto es distinto". Un commit que toca otro fichero, o volver a subir
el mismo contenido, cambian la fecha y no el sha.

### Que no hace

- **No pregunta dos veces por la misma version.** Si dices que no, se apunta
  ESE sha como rechazado: no vuelve a salir para esa version -un dialogo antes
  de cada partida es la forma mas rapida de que alguien deje de leer los
  dialogos- pero si cuando salga la siguiente.
- **No pisa tu trabajo sin avisar.** Si habias ajustado tu copia a mano,
  WProton lo detecta -compara el fichero con el sha que se apunto al
  instalarlo- y te lo dice antes. El tuyo se guarda como `.conf.bak`.
- **No toca los perfiles que te hayas hecho tu.** Sin marca de la comunidad no
  hay nada con que comparar, y no se compara.

### Y todos de una vez

*Biblioteca y preferencias → Perfiles del repositorio → **Buscar perfiles
actualizados***, porque el aviso al lanzar un juego solo llega cuando lo lanzas,
y a los juegos que no se tocan en meses no llega nunca. Dice que juegos tienen
version nueva, marca los que has modificado tu, y los actualiza con una sola
confirmacion.

### Dos cosas que salieron probandolo

- **Al actualizar salian DOS dialogos seguidos** cuando el perfil traia teclas:
  "¿quieres la version nueva?" y "¿sustituyo tambien el .keys?", con el usuario
  habiendo dicho que si una linea antes. `community_keys_fetch` no respetaba el
  modo sin preguntas que si tenia `community_fetch`. El dialogo ha pasado de
  once lineas a cuatro.
- **Un conteo que daba "0" dos veces.** `$(grep -c ... || echo 0)`: grep ya
  imprime 0 cuando no encuentra nada, asi que el "|| echo 0" añadia un segundo
  cero y la variable valia "0\n0" -que no es igual a 0-. Se veia en la revision
  en tanda, que decia "actualizados 0 de 0" en vez de "estan al dia". Estaba en
  doce sitios y se ha corregido en todos.

## Traer la configuracion de la comunidad cuando te de la gana

*Ajustes del juego → **Traer la configuracion de la comunidad***. Es la tercera
forma de conseguir un perfil de la comunidad, y la unica que la pide el usuario:

| | Cuando salta | Cuando funciona |
|---|---|---|
| Al abrir un juego nuevo | sola | si NO tienes perfil |
| Aviso de version nueva | sola | si hay una MAS NUEVA |
| **Traer la configuracion** | **la pides tu** | **siempre** |

Ese "siempre" es el motivo de que exista. El caso que la pidio: alguien va a
jugar, ve que su configuracion no le va bien y quiere la de la comunidad YA, sin
esperar a que haya version nueva ni tener que borrar su perfil para que vuelva a
saltar el aviso del juego nuevo.

Y sirve para **volver atras**: si uno ha estado toqueteando ajustes y lo ha
dejado peor, esto le devuelve el que funcionaba. Por eso funciona tambien cuando
ya tienes esa misma version -te lo dice, pero no te lo impide-.

La fila del menu dice en que situacion estas, que son cuatro y cada una quiere
una palabra distinta: no la tienes, ya la tienes, hay una nueva, o el perfil es
tuyo. Una etiqueta fija obligaria a entrar para saber cual.

### El fallo que esto podia tener, y que no tiene

La pantalla de ajustes guarda el perfil al salir, con los valores que haya EN
MEMORIA. Asi que descargar el fichero y no recargarlo habria sido un fallo
perfecto: el perfil se baja bien, y al pulsar "<< Volver" se pisa con los
valores de antes. La descarga pareceria no hacer nada, y el registro diria que
fue bien.

Es el mismo fallo que ya aparecio al borrar los datos de un juego, asi que esta
vez se contemplo desde el principio: tras instalar se recarga el perfil, y la
rama del menu no vuelve a guardarlo. Hay una prueba que lo comprueba haciendo
exactamente lo que hace el menu al salir.

## Importar juegos: 7-Zip portable, sin empaquetar y sin borrar nada a ciegas

Tres cambios en el camino de importar un juego desde un comprimido. Salieron de
una idea que llego del canal, y los tres sirven igual en WProton tal cual.

### 7-Zip lo descarga WProton

Para abrir `.7z` y `.rar` hace falta 7-Zip. Lo que habia era un mensaje diciendo
*"sudo pacman -S p7zip"*, y eso falla justo en los dos sitios donde mas se usa
WProton:

- En una **Steam Deck el sistema es de solo lectura**. No es que sea incomodo:
  es que no se puede. Un usuario en modo Juego no tenia NINGUNA forma de
  importar un `.rar`, y el mensaje le mandaba a hacer algo imposible.
- Y va contra la regla de la casa: WProton no pide sudo ni instala nada en el
  sistema, se trae lo que necesita a `runtime/`.

Ahora se lo descarga solo: el binario estatico oficial de 7-Zip, un fichero en
`runtime/tools`, por el mismo camino que `squashfuse` o DwarFS (primero el
repositorio de WProton, luego el paquete de Arch, luego el tarball oficial). Si
ya tienes un `7z` en el sistema, usa el tuyo y no descarga nada.

### Formato "carpeta": sin empaquetar

Un tercer valor en *Biblioteca y preferencias → Formato al empaquetar*, junto a
wsquashfs y dwarfs: **carpeta**, que deja el juego sin empaquetar. Lo pidieron
desde el canal, y no ha hecho falta nada nuevo para que funcione: WProton sabe
lanzar un juego que es una carpeta desde siempre.

Al activarlo dice lo que se pierde, porque son cuatro cosas que no se ven hasta
mucho despues: un fichero por juego en vez de decenas de miles (y en una microSD
eso se nota), la compresion, el overlay que separa las partidas del juego, y
poder llevarte un juego a otro equipo copiando un archivo.

Las dos opciones cuyo trabajo **es** empaquetar -*Convertir carpeta a
wsquashfs* y *empaquetar un juego con su prefijo*- siguen haciendo un archivo
aunque este puesto "carpeta". Si alguien ha pedido un paquete es que quiere un
paquete; obedecer ahi al ajuste las habria dejado moviendo carpetas de sitio,
que es lo contrario de lo que dicen hacer.

Si ya hay una carpeta con ese nombre no se pisa: la nueva entra como
`Nombre (2)`. Y el overlay del juego anterior no se borra, al contrario que al
empaquetar: ahi estan las partidas de cuando lo tenias en `.wsquashfs`.

### Y ya no borra los comprimidos sin preguntar

Cuando el juego ya esta instalado, WProton **pregunta** si borrar los
comprimidos de los que salio, diciendo cuantos son y cuanto ocupan -tres
ficheros de 200 MB y veinte de 60 GB no se responden igual-. Hay dos razones
para conservarlos que no puede adivinar: que sean la unica copia que tienes del
juego, y que quieras importarlo en otro equipo. Un borrado de 40 GB que nadie
pidio no se deshace.

Sigue tocando solo ficheros con extension de comprimido, multiparte incluidos
(`.001`, `.partN.rar`, `.rNN`, `.z01`): un `Mi.Juego-partidas.txt` al lado no se
toca.

## El juego que carga para siempre: aviso al empaquetar, y conversion con partidas

Un tester empaqueto un juego de **48 GB y 32.164 ficheros**. En carpeta arrancaba
bien; empaquetado **se quedaba cargando y no llegaba a entrar**. En el registro no
habia ni un error: DwarFS montaba, GE-Proton arrancaba, la ventana del juego
llegaba a abrirse y ahi se quedaba. No estaba roto, tardaba una barbaridad.

Lo que se junta son dos cosas que por separado no se notan:

- Un paquete se lee a traves de **dos capas FUSE** -la imagen y la superposicion
  de las partidas-, las dos atendidas desde un proceso de usuario. Una carpeta la
  sirve el kernel con su cache de nombres.
- Wine resuelve las rutas **sin distinguir mayusculas**, y para eso **lee la
  carpeta entera** cada vez que el juego abre un fichero.

Con unos cientos de ficheros eso es gratis. Con treinta mil en el mismo sitio se
multiplica, y el resultado es un juego que no entra nunca.

**Ahora se avisa antes de empaquetar.** Si el juego pasa de 20.000 ficheros,
WProton dice cuantos son y ofrece dejarlo en carpeta. No impide nada -se puede
decir que no y empaquetar igual- pero se pregunta en el unico momento en que
sirve de algo: despues, rehacer el empaquetado de un juego grande son otras
tantas horas. El numero esta en `settings.conf` (`PACK_AVISO_FICHEROS`, 0 lo
apaga), y donde el formato viene forzado -*Convertir carpeta a wsquashfs*,
*empaquetar con su prefijo*- avisa pero no pregunta: ahi el usuario acaba de
pedir un archivo a proposito.

**Y convertir un paquete a carpeta ya no se deja las partidas fuera.** Esto
salio al ir a documentar la salida del problema de arriba: *Convertir wsquashfs a
carpeta* montaba la imagen en solo lectura, o sea **sin la superposicion**, y las
partidas se quedaban en `overlays/<juego>/upper` sin que nada lo dijera. Quien
convertia su juego a carpeta justo para que cargara rapido se encontraba el juego
entero y la partida a cero. Ahora, si ese juego tiene partidas, pregunta si
incluirlas -diciendo cuanto ocupan- y las pone encima de lo extraido, que es
exactamente lo que se veia al jugar. Las originales no se tocan.

Al mirar si hay partidas se descartan las marcas internas de overlayfs y **las
carpetas vacias que las sostienen**: `drive_c/users/steamuser/.wh..wh..opq` es
contabilidad de la superposicion, no una partida, y contarla habria hecho que
WProton ofreciera recuperar partidas inexistentes en casi cualquier juego.

### De paso: "carpeta" ya no se colaba en el gestor de archivos

Con `PACK_FORMAT=carpeta`, *Archivos y discos → Convertir carpeta a...* tomaba el
ajuste al pie de la letra: salia un fichero llamado `Mi Juego.carpeta` que por
dentro era un squashfs, y que luego no se reconocia por la extension. Ahora usa
la misma regla que el resto de caminos que piden un archivo: si el ajuste dice
"carpeta", se empaqueta en wsquashfs.

## El montaje de wsquashfs: el driver rapido y la cache que faltaba

Lo de arriba explica por que un juego con muchisimos ficheros carga tan mal
empaquetado, y ahi hay algo que se podia arreglar de raiz: **cuantas veces el
kernel tiene que volver a preguntar por lo mismo**.

El proyecto squashfuse trae DOS drivers, y vienen en el mismo paquete:

- **squashfuse** usa la interfaz ALTA de FUSE. Le dice al kernel que lo que
  contesta **caduca en un segundo**, y las busquedas que no encuentran nada
  **no se guardan en absoluto**.
- **squashfuse_ll** usa la interfaz BAJA y contesta `DBL_MAX`, o sea *"esto no
  caduca nunca"*, **tambien para las busquedas fallidas**.

Una imagen montada no puede cambiar, asi que la segunda respuesta es la
correcta y la primera es trabajo tirado. Y es justo el trabajo que mas se repite
aqui: Wine lee la carpeta entera cada vez que abre un fichero, y pregunta por un
monton de rutas que no existen. Con el driver bajo, todo eso lo contesta el
kernel de su cache sin salir a espacio de usuario.

Asi que **ahora se monta con `squashfuse_ll` si esta**. En el registro queda cual
se ha usado, en cada arranque.

**Y si no esta, WProton se lo descarga.** Esto hizo falta pensarlo dos veces: el
camino que busca las herramientas de montaje solo entra cuando FALTA squashfuse,
asi que en una instalacion que ya funciona -o sea, en todas las que vienen de
una version anterior- no se habria llegado a buscar nunca y la mejora se habria
quedado sin estrenar. Ahora se mira en cada arranque, con tres cuidados:

- **En segundo plano**, como el refresco de las listas del repositorio. Son una
  consulta y un mega de descarga; esperarlos aqui seria hacer que arrancar
  WProton tarde lo que tarde la red, o lo que tarde en FALLAR, que es peor. Y
  como el driver se elige en el momento de montar, si la descarga termina antes
  de que elijas juego **esta** partida ya va con el rapido.
- **Una vez a la semana como maximo**, con marca en `runtime/`. La marca se
  escribe ANTES de intentarlo: si la descarga se cuelga y alguien mata WProton,
  sin marca se reintentaria en cada arranque.
- **Con el PID apuntado**, para que el cierre lo remate como a los demas
  trabajos de fondo en vez de avisar de "trabajos en segundo plano".

Las fuentes, por orden: el repositorio de WProton, los binarios estaticos, y el
paquete de Arch. De ese ultimo se saca **solo** `squashfuse_ll`: pedir el
paquete entero pisaria un squashfuse que ya este funcionando, que puede venir de
otra fuente e ir perfectamente. Para eso se ha partido el manejo de los paquetes
de Arch en piezas (bajar, abrir, sacar un binario, instalarlo), que ademas
descomprime una sola vez aunque se saquen varios binarios del mismo paquete.

Si no aparece en ninguna fuente no es un fallo: se monta con squashfuse como
siempre. Y para forzarlo en el momento, *Runners y herramientas → Descargar
herramientas FUSE* borra la marca, lo intenta esperando -ahi hay alguien
delante- y dice que driver vas a usar.

**Y al squashfuse normal se le piden las opciones que le faltaban**:
`kernel_cache`, `attr_timeout`, `entry_timeout` y `negative_timeout`, una hora
las tres ultimas. De serie son un segundo, un segundo y **cero**, que esta bien
para un sistema de ficheros que puede cambiar y es tirar el trabajo en uno de
solo lectura. Hasta ahora se montaba **sin ninguna opcion**, ni siquiera `ro`.

Dos cuidados que merece la pena dejar escritos:

- **A `squashfuse_ll` no se le pasa nada de eso.** Su `-o timeout=N` **no es** la
  caducidad de los atributos: es *"desmontate solo tras N segundos sin uso"*.
  Pasarle ahi un numero grande pensando en la cache seria programar un
  desmontaje en mitad de la partida.
- Estas opciones **no salen en su `--help`** -ahi solo pone que admite las de la
  libreria FUSE-, asi que no vale el truco de leer la ayuda que se usa con
  dwarfs. Se intenta montar y, si el driver no las acepta, se reintenta con `ro`
  y, si tampoco, sin ninguna opcion, que es como se montaba hasta ahora. Lo que
  funcione se queda para el resto de la sesion, y el aviso sale una vez.

## El montaje DwarFS, afinado

De serie el driver de DwarFS monta con 512 MB de cache de bloques y 2 hilos de
descompresion: valores prudentes, pensados para no comerse la memoria. Un juego
de 30 GB en una microSD agradece bastante mas, y se nota justo en el rato de
carga. Ahora se monta con **1 GB de cache y tantos hilos como nucleos** (hasta
4), configurable en `settings.conf` (`DWARFS_CACHE`, `DWARFS_WORKERS`).

No se piden a ciegas, porque una opcion `-o` que dwarfs no conozca no da un error
suyo: se la pasa al kernel, y el kernel **rechaza el montaje entero**. Asi que
primero se mira su propia ayuda y solo se pide lo que aparece ahi; y si aun asi
el montaje afinado falla, se reintenta con las opciones de siempre y se apunta en
el registro. Mas vale cargar lento que no cargar.

## Al añadir un juego a Steam, las caratulas se descargan solas

"Añadir a Steam" copiaba unicamente las caratulas que WProton **ya** tuviera,
asi que un juego recien añadido salia casi siempre como un cuadro gris con el
nombre: lo normal es añadirlo a Steam antes de haber descargado ninguna
caratula, que es justo el caso en el que hacia falta.

Ahora, al añadirlo, se traen de SteamGridDB las cuatro imagenes que usa la
ficha de Steam:

| Imagen | Fichero que exige Steam | De donde sale |
|---|---|---|
| Vertical, la de la estanteria | `<appid>p.png` | SteamGridDB (y se guarda en `covers/`) |
| Apaisada, la de la cabecera | `<appid>.png` | SteamGridDB (y se guarda en `covers_wide/`) |
| El fondo grande de la ficha | `<appid>_hero.png` | SteamGridDB |
| El logotipo sobre el fondo | `<appid>_logo.png` | SteamGridDB |

Las dos primeras se guardan tambien en las carpetas de WProton, asi que sirven
igual en su propia biblioteca y no se descargan dos veces. El fondo y el
logotipo son solo de Steam.

Con **una sola busqueda** en la API se piden las cuatro. Y si no tienes API key
de SteamGridDB **no se te pregunta nada en medio**: el juego se añade igual con
las caratulas que haya, y el aviso del final explica por que no hay mas y donde
se pone la clave. Interrumpir con un dialogo bloqueante a quien esta esperando
con Steam cerrado no es forma de hacerlo.

## Las listas del repositorio se ponen al dia en cada arranque

Para no volver a tener el problema de Silver Pines por ninguna via: al arrancar,
WProton actualiza la lista de perfiles y la de caratulas del repositorio.

**En segundo plano, siempre.** Son dos consultas a GitHub; esperarlas aqui
significaria que arrancar WProton tarda lo que tarde la red, o lo que tarde en
FALLAR, que es peor: en una Deck sin conexion serian doce segundos de pantalla
muerta. Van a un subproceso que nadie espera -el arranque sigue tardando lo
mismo, medido- y las listas se escriben con un temporal y un `mv`, asi que quien
las lea mientras tanto lee la anterior entera, nunca una a medias. Si cierras
WProton en esos dos segundos, el cierre lo remata como a los demas procesos.

**Con un suelo de diez minutos, y esto conviene saberlo.** La API de GitHub sin
credenciales da **60 peticiones por hora y por IP**. Dos por arranque parecen
pocas hasta que se cuenta como se usa esto de verdad: en DeckStation cada juego
lanza su propio `wproton.sh`, asi que una tarde de pruebas son dos peticiones
por juego lanzado. Al pasar de 60, GitHub contesta 403 a **todo** durante el
resto de la hora, y entonces no funciona ni la lista, ni las caratulas, ni los
perfiles. El suelo deja el "cada vez que arranque" intacto en el uso normal y
quita el unico caso en el que se rompia.

El menu de perfiles de la comunidad tambien deja de consultar GitHub cada vez
que se abre: usa la lista que el arranque acaba de dejar al dia, y sin red usa
la copia local.

## Un juego recien subido al repositorio ya se encuentra

Las listas de `profiles/` y de `covers_43/` se guardaban un dia para no pedirlas
a GitHub en cada partida, y eso tenia un efecto que costo encontrar: **un juego
subido al repositorio hoy no aparecia hasta el dia siguiente**. Se veia con
Silver Pines: el perfil y la caratula estaban subidos, y WProton no los traia.

Ahora, cuando un juego no esta en la lista guardada, WProton **pide la lista otra
vez** antes de darlo por perdido. Una sola vez por sesion y por lista, asi que
tener veinte juegos sin perfil no son veinte consultas a GitHub.

De paso, dos cosas mas del mismo camino:

- **Un juego sin perfil ya no deja mudos a los demas.** El "ya se le pregunto"
  se guardaba en una variable en memoria que se leia antes de cargar el perfil
  del juego, asi que conservaba el valor del juego anterior: bastaba arrancar un
  juego que no estuviera en el repositorio para que, en el resto de la sesion,
  ningun otro volviera a preguntar. Incluido uno que si tenia perfil. Ahora el
  "ya preguntado" va por juego, en disco.
- **Si GitHub falla, no se pierde la lista de ayer.** Antes se borraba antes de
  pedir la nueva, asi que un corte de red dejaba a WProton sin ninguna lista.

## El registro cuenta por que no se descargo algo

Cuando algo "no se baja" hay cinco motivos posibles y desde fuera son
indistinguibles: sin red, repositorio mal escrito, GitHub limitando peticiones,
el fichero no esta subido, o el nombre no coincide. Este camino **no escribia
nada** en el registro, asi que el unico sintoma era el silencio.

Ahora queda apuntado todo: la edad de la lista guardada, cuantos perfiles y
cuantas teclas tiene el repositorio, la **clave normalizada** con la que se
busca el juego, el codigo HTTP cuando GitHub contesta mal, y el aviso de que la
carpeta llega al tope de 1000 ficheros de la API de GitHub (con los `.keys` al
lado de los `.conf`, ese tope llega a la mitad de juegos de lo que parece).

## Biblioteca y preferencias → Comprobar el repositorio

Una opcion nueva que contesta la pregunta de siempre sin abrir una terminal:
cuantos perfiles, teclas y caratulas hay en el repositorio ahora mismo, y
**cuales de tus juegos se quedan sin perfil o sin caratula**, con nombres. Esos
son los que hay que subir o renombrar.

El cruce de la biblioteca entera con el repositorio se hace de una pasada: con
300 juegos y 300 caratulas tarda **un segundo** en vez de los cinco minutos que
costaba comparando juego a juego.

---

---

# WProton 2.01 — novedades

## Los perfiles de la comunidad traen tambien las teclas del mando

En la carpeta `profiles/` del repositorio hay juegos que necesitan DOS cosas: el
perfil con su runner y sus ajustes, y un `.keys` con el mapeo del mando. Los dos
estaban subidos, pero WProton solo se bajaba el `.conf`: el juego quedaba
configurado a medias y el mando sin mapear. Lo vio un tester.

Ahora, si junto al perfil hay un fichero con el **mismo nombre** y extension
`.keys`, se descarga con el. Detalles:

- Se guarda con el nombre de **tu** juego, igual que el perfil. El del
  repositorio puede llamarse distinto, y entonces no lo encontraria nadie.
- Se **remarca** como de tu juego. El del repositorio viene marcado con el
  nombre de alla; sin remarcarlo, WProton lo veria como "de otro juego" y lo
  ignoraria.
- Si ya tenias un `.keys` para ese juego, se pregunta antes y el tuyo se guarda
  como `.bak`.
- Si lo descargado no es un JSON valido, se descarta en vez de dejarte un
  fichero roto en `profiles/`.
- Antes de descargar, el dialogo avisa de que ese perfil trae teclas.

---

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

## Los tres botones del raton en el mapeador

Al poner un stick como raton se podia elegir que boton hacia clic, pero solo el
IZQUIERDO. Lo conto un tester con un juego en el que recargar es el boton
derecho: podia mover el puntero y disparar, pero no recargar.

Ahora se eligen los tres —izquierdo, derecho y central— en *Crear o editar las
teclas -> Raton*. El derecho y el central se pueden dejar sin asignar, que es
como venian. Funcionan igual con un gatillo que con un boton normal: en casi
todos los mandos L2 y R2 mandan un eje en vez de una pulsacion, y eso ya estaba
resuelto para el izquierdo; ahora lo heredan los otros dos sin duplicar nada.

Ademas, al asignar una tecla a un boton hay una opcion nueva, **Botones del
raton**, que le cuelga un clic a ese boton aunque ningun stick mueva el puntero.
El mapeador sabia mandarlos desde hace tiempo, pero habia que escribir el .keys
a mano.

Y el resumen de teclas de un juego ya los enseña los tres: antes decia "clic del
raton" a secas y se callaba el derecho y el central.

## Todas las caratulas de golpe

En *Biblioteca y preferencias* hay una opcion nueva, **Traer todas las caratulas
del repositorio**: baja la coleccion entera de 4:3 de una vez, no solo las de los
juegos que tengas ahora. Asi, cuando anadas uno nuevo, su caratula ya esta
puesta. Dice cuantas son y cuanto ocupan antes de empezar —el tamano lo da la
propia API, no es una estimacion— y no pide clave ninguna. Lo pidio un tester.

Las que se bajan asi se guardan con el nombre del repositorio; si alguno de tus
juegos se llama distinto, WProton deja ademas una copia con el tuyo para que se
vea en la biblioteca.

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
