## v1.05.1

- **Corregido: WProton no volvía al menú al cerrar el juego.** La espera a que
  el juego terminara contaba también a *nuestras propias* herramientas
  (squashfuse, fuse-overlayfs, el mapeador), que llevan la ruta del montaje en
  su línea de órdenes y no mueren hasta que WProton desmonta... lo que ocurre
  después de esa espera. Resultado: se esperaba a sí mismo para siempre.
- **Corregido: el mando no llegaba al juego con ficheros `.keys`.** La ventana
  de WProton se quedaba viva unos segundos tras lanzar (era un intento de tapar
  el hueco de escritorio mientras el juego arranca). Al estar a pantalla
  completa por delante, **se quedaba con el foco del teclado**: el mapeador
  enviaba las teclas correctamente pero no llegaban al juego, y los juegos en
  ventana parecían esconderse detrás. Ahora la ventana se cierra antes de
  lanzar, sin retrasos. Se ve un parpadeo de escritorio, que es mucho menos
  grave que un mando que no responde.
- **El mapeador ya no elige mando: los escucha todos.** Antes había que
  acertar con uno —esperando una pulsación y, si no llegaba, adivinando—, y con
  mandos que exponen varios nodos de entrada (el de Xbox 360 aparece como
  *"pad"* y *"pad 0"*) se podía acabar escuchando el que no recibe eventos: el
  mando no respondía a nada. Escuchando todos no hay nada que acertar, no hay
  espera, y si tienes dos mandos de verdad, funcionan los dos.
  Además se agrupan los nodos del mismo aparato físico, el perfil de botones se
  toma del mando reconocible, y si uno se desconecta a mitad se descarta ese
  sin tumbar el mapeador.
- **Corregido: el juego se quedaba detrás de WProton.** Al terminar el proceso
  que WProton lanza, muchos juegos de Windows siguen corriendo en otro proceso.
  La espera anterior se rendía a los 5 segundos y reabría el menú **a pantalla
  completa encima del juego**, que parecía esconderse. Ahora se espera a que no
  quede ningún proceso del juego, comprobando el wineserver y lo que cuelga del
  montaje, con un tope alto por si algo se queda colgado.
- La pantalla de carga se cierra 4 segundos después de lanzar (antes 8): con
  juegos que arrancan en ventana, tanto tiempo la dejaba por delante.
- **Corregido: el mapeador de mando tardaba en responder.** Antes de empezar a
  traducir botones esperaba **hasta 30 segundos** a que el usuario pulsara algo
  para saber qué mando usar. En una partida corta, eso significaba que el mando
  no hacía nada durante casi toda la sesión. Ahora, si solo hay un mando
  conectado —lo normal— se usa **al instante**; con varios, se pregunta cuál
  con una espera de 5 segundos.
- El mapeador escribe ya su actividad en el registro según ocurre (antes se
  quedaba en el búfer de Python y el registro aparecía vacío), y WProton avisa
  si el proceso se cierra nada más arrancar.
- **Corregido: no detectaba las versiones nuevas.** Si la etiqueta de la
  release llevaba la V en mayúscula (`V1.02`), WProton solo quitaba la `v`
  minúscula: la comparación numérica trataba `V1.02` como cero y decía que
  estaba al día teniendo una versión más nueva delante. Además la descarga
  habría fallado, porque la URL se construía con `v` + número en vez de con la
  etiqueta real. Ahora se admiten `v1.02`, `V1.02` y `1.02`, y si la etiqueta
  no se entiende lo dice en vez de callarse.
- **Corregido**: la ficha del juego no descargaba nada. La búsqueda en Steam
  hacía `return` dentro de una tubería, y eso solo termina el subshell: la
  función seguía hasta su salida de error, así que daba fallo aunque hubiera
  encontrado el juego. La consulta se ha reescrito en Python, que además
  analiza el JSON de verdad en vez de con expresiones regulares.
- **Corregido**: la duración solo se consultaba si Steam conocía el juego. Un
  juego que no esté en Steam pero sí en HowLongToBeat se quedaba sin ninguna
  de las dos cosas; ahora son independientes.
- La auditoría detecta desde ahora los `return` dentro de tuberías.

## v1.05

**Botones dedicados en la lista de juegos.** El menú de configuración ya tenía
demasiadas opciones, así que las dos más usadas salen de ahí:

| Botón | |
|---|---|
| **L1** | Ficha del juego |
| **R1** | Marcar o quitar favorito |

Funcionan igual en la lista y en la rejilla de carátulas, y la ayuda de abajo
los indica. Con teclado son **F1** y **F2**.

**Ficha del juego.** Con **L1** sobre el juego, o en *Ajustes de un juego*: año de
publicación, desarrollador, editor, géneros y **nota de Metacritic**, con los
datos de la tienda de Steam. No necesita clave ni cuenta. La ficha se guarda en
`covers/<juego>.info.json`, así que solo se consulta una vez.

Debajo va siempre **lo que sabe WProton de tu partida** —tamaño, veces jugado,
tiempo total, última vez y tus notas—, que se muestra igual sin red o si el
juego no está en Steam.

**Duración de partida (opcional).** Con la biblioteca
[howlongtobeatpy](https://pypi.org/project/howlongtobeatpy/) instalada, la
ficha añade cuánto se tarda en terminar el juego (historia y al 100%). Se
instala desde *Runners y herramientas → Datos de duración de partida*; ocupa
unos 100 KB. Si no se instala, el resto de la ficha funciona igual.

Solo se acepta el dato si el nombre encontrado se parece de verdad al del juego
(similitud 0,7 o más): antes que dar la duración de otro juego, no se muestra
ninguna.

Para dar con el juego correcto se usa el mismo resolutor de nombres que la base
de umu: de los candidatos que devuelve Steam se coge **el que casa por nombre**,
no el primero de la lista.

**Añadir a Steam, sin ficheros corruptos.** Steam reescribe sus accesos
directos al salir, así que modificarlos con Steam abierto podía perder el
cambio o dejar el fichero mal. Ahora WProton se ofrece a **cerrar Steam, añadir
el juego y volver a abrirlo**, con espera ordenada (`steam -shutdown`) y aviso
si no llega a cerrarse.

**Y en el modo Juego de SteamOS no se puede usar**, por un motivo de peso: en
esa sesión Steam *es* el escritorio, y cerrarlo cerraría la sesión del usuario.
La opción se muestra como *"Añadir este juego a Steam (solo en modo
Escritorio)"* y, si se pulsa, explica por qué y no toca nada.

## v1.04

**Base de datos de umu.** Al añadir un juego nuevo, WProton consulta la base de
[umu-database](https://github.com/Open-Wine-Components/umu-database) y, si lo
encuentra, propone su identificador. Ese identificador es lo que permite a
protonfixes aplicar los arreglos concretos del juego, así que puede ser la
diferencia entre que arranque o no. La base (~1.200 entradas, 90 KB) se
descarga una vez y se guarda una semana; también se puede consultar a mano
desde *Ajustes de un juego → Buscar en la base de umu*.

La búsqueda usa tres pistas, en este orden: el **nombre del ejecutable** (la
más fiable, porque no depende de cómo se llame la carpeta), el nombre del
juego, y el acrónimo común (`aow` → Age of Wonders). El índice se precalcula,
así que una consulta tarda milisegundos.

**Elegir el ejecutable entre todos.** Al configurar un juego en carpeta ahora
se muestran **todos** los `.exe`, `.bat` y `.cmd` de la carpeta y subcarpetas,
no solo los que pasaban el filtro. Ordenados por probabilidad —el sugerido
arriba, después los de la raíz, luego los de subcarpetas y al final los
sospechosos (instaladores, desinstaladores, redistribuibles)— y con su tamaño
al lado, que distingue de un vistazo el juego del instalador de DirectX.

**Carátula desde el sistema.** *Ajustes de un juego → Carátula: elegir una
imagen del sistema*, sin depender de SteamGridDB. La imagen se copia a
`covers/`, así que puedes mover o borrar el original sin romper nada. Si la
imagen no es vertical, avisa de que en la rejilla se verá recortada.

**Por dentro**: un resolutor de nombres común a todas las búsquedas (umu,
perfiles de la comunidad y, más adelante, la ficha del juego). Compara
ignorando mayúsculas y separadores, admite la coletilla de versión o grupo
(`v1.0.2`, `-GOG`, `-P2P`, `REPACK`) y, cuando no hay una coincidencia clara,
**pregunta en vez de adivinar**: mostrar los datos de otro juego sería peor que
no mostrar ninguno.

## v1.03

Versión de mantenimiento: sin cambios visibles, pero con una red de seguridad
que antes no existía.

**Auditoría automática** (`auditar.py`), que se ejecuta en cada construcción y
la detiene si encuentra algo. Cada comprobación nació de un fallo real que nos
costó una sesión entera de depuración:

| Comprobación | El fallo que la motivó |
|---|---|
| Opciones de menú sin acción | "Añadir un juego" dejó de funcionar al renombrar el texto sin tocar su `case` |
| Declaraciones `local` que se usan a sí mismas | Descargar un perfil de la comunidad cerraba WProton de golpe, sin mensaje |
| Tildes dentro de código | `--disable-pip-versión-check` rompía la instalación de pygame en todos los equipos nuevos |
| Asignaciones dentro de subshells | Cuatro fallos distintos: ventanas duplicadas, servidor que no se paraba, WProton que no se cerraba |
| Procesos de fondo sin soltar el terminal | La ventana de Konsole no se cerraba al salir |
| Traducciones desincronizadas | Cadenas nuevas sin traducir o plantilla desfasada |
| Sintaxis de bash y Python, y `shellcheck` | |

Las comprobaciones usan las mismas reglas que bash (los patrones de `case` son
comodines), así que no dan falsos positivos, y las excepciones legítimas están
documentadas en el propio script.

Uso: `./auditar.py`, o `./build.sh --sin-auditar` para saltarla en pruebas.

## v1.02

**Menús persistentes.** Hasta ahora cada menú abría su propia ventana y la
cerraba al elegir. Eso provocaba el parpadeo al pasar de un menú a otro y,
en el modo Juego de SteamOS, dejaba al compositor sin ninguna ventana nuestra
a la que volver al salir de un juego.

Ahora **todos los menús se dibujan en un mismo proceso, que no se cierra entre
uno y otro**:

- Al cambiar de menú no hay ventana nueva: el contenido cambia y ya está.
- Entre menú y menú se ve una pantalla de reposo con la marca WProton, así que
  nunca aparece el escritorio de por medio.
- Mientras juegas, la ventana **se cierra** (mantener una conexión gráfica
  abierta durante la partida es lo que acababa en `XIO: fatal IO error` cuando
  gamescope reconfigura su XWayland) y se vuelve a abrir al terminar, una vez
  la pantalla se ha estabilizado.
- Si el proceso no arranca o se cierra por lo que sea, WProton lo detecta y
  vuelve al comportamiento antiguo —una ventana por menú— sin que se note.

**Pantalla de carga al abrir un juego**: los segundos que tarda en montarse y
prepararse ya no son una pantalla muda. Se ve qué está haciendo —*Montando el
juego...*, *Preparando el entorno de Windows...*, *Iniciando <juego>...*— y lo
mismo en las esperas largas, como descomprimir un archivo al importarlo.

Se puede desactivar con `MENU_SERVER=0` en `settings.conf`.

Corregido también: al salir, WProton dejaba procesos enganchados al terminal
desde el que se había lanzado, así que la ventana de la consola no se cerraba.
Ahora todos los procesos de fondo se lanzan desenganchados y cualquier cierre
pendiente se cancela al salir.

Corregido durante las pruebas: el fondo antiguo seguía levantándose junto al
proceso de menús, así que había **dos ventanas peleándose por el foco** y una
de ellas se recreaba en cada movimiento (de ahí el parpadeo y tener que
recuperar el foco a mano). Con el proceso de menús activo, ese fondo ya no se
usa: hace lo mismo y mejor.

**Por dentro**: el helper de menús se ha reorganizado en `set_request()`,
`load_request_data()`, `compute_layout()` y `run_session()`, de forma que una
sesión se puede ejecutar muchas veces sobre la misma ventana. El protocolo
entre bash y el proceso de menús es de ficheros, sin dependencias nuevas.

## v1.01

Reestructuración interna. **Para el usuario no cambia nada**: se sigue
descargando un único `wproton.sh` que funciona exactamente igual.

- El código Python (2.418 líneas: menús, mapeador, accesos de Steam y menús de
  respaldo) **deja de vivir dentro del bash como texto** y pasa a ficheros
  reales en `src/`. Ahora se puede editar con resaltado de sintaxis, linter y
  depurador, y los cambios se ven en los diffs de Git.
- Nuevo `build.sh`, que genera el `wproton.sh` de siempre a partir de
  `wproton.base.sh` y `src/`. Comprueba la sintaxis de todo el Python, de los
  JSON y del script resultante: si algo falla, no genera nada.
- **Las marcas de versión de los helpers se calculan del contenido**. Antes se
  escribían a mano y más de una vez se olvidó: el usuario se quedaba con un
  helper viejo sin enterarse.
- El `en.json` embebido se genera desde `src/lang/en.json`: una sola fuente.

Verificado: el `wproton.sh` generado es **idéntico** al publicado en la 1.0.
