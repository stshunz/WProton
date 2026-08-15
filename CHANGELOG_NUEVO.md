# Novedades

## v1.20

- **Crear las teclas de un juego desde el propio WProton.** En *Ajustes del
  juego → Mapeador .keys → Crear o editar las teclas*, salen todos los botones
  del mando en una lista y a cada uno se le asigna la tecla que quieras, con
  el mando y sin tocar ningún fichero. Si el juego ya tenía teclas, se parte
  de ellas. **Select + Start para cerrar el juego se pone siempre**, sin
  tener que acordarse.
- **Los juegos añadidos a Steam llevan sus carátulas.** Se aprovechan las que
  ya tienes: la vertical para la biblioteca y la panorámica para la cabecera y
  el fondo. Si a un juego solo le falta una, se pone la que haya; antes
  aparecían todos como un cuadro gris con el nombre.
- **Corregido: Steam podía seguir dando el juego por abierto.** Al terminar,
  WProton esperaba a que los procesos de Wine se fueran solos, pero no los
  cerraba. Ahora se cierran los del prefijo de ese juego, tanto con runners
  Wine como con Proton —que guardan ese componente en otra carpeta— y queda
  anotado en el registro.
- **Los números entre paréntesis ya no salen de otro color** en las opciones de
  menú (las proporciones tipo «(2:3)» se tomaban por «etiqueta: valor»).
- **Las carátulas anchas ya no se meten debajo de la barra** del lado derecho.
- **Corregidos los avisos falsos de "sigue vivo" al cerrar.** WProton se
  encontraba a sí mismo: la orden que cierra un proceso lleva su nombre
  escrito, así que al comprobar si quedaba algo se veía esa orden y creía que
  el proceso seguía en marcha. Por eso aparecían avisos justo después de decir
  que se había detenido.
- **Todos los procesos auxiliares se cierran de verdad.** WProton lanza cuatro
  procesos por detrás (puente del mando, mapeador, vigilante y menús) y los
  cuatro tenían el mismo defecto: se guardaba el identificador de un proceso
  intermedio que muere al instante, así que la orden de cierre no alcanzaba al
  real. Ahora se cierran por nombre y se comprueba el resultado; si alguno se
  resiste, queda anotado en el registro.
- **Revisados todos los modos de arranque.** WProton se puede abrir de nueve
  formas distintas (desde su icono, desde Steam, con un juego concreto, para
  importar un fichero...) y no todas vuelven a un menú al terminar. Ahora cada
  una hace lo que corresponde: las que vuelven a un menú lo recuperan, y las
  que no, se cierran sin dejar nada en pantalla.
- **El fondo de WProton ya no se queda en pantalla al lanzar un juego desde
  Steam.** Al terminar la partida se abría el menú para enseñar "Volviendo al
  menú…", pero lanzado desde Steam no hay menú al que volver: esa ventana se
  quedaba en pantalla y Steam daba el juego por abierto. Ahora solo se abre
  cuando de verdad se vuelve a un menú.
- **El fondo de WProton ya no se queda en pantalla tras cerrar un juego.**
  Aparecía unos segundos después de salir: un proceso lanzado justo antes del
  cierre tarda un momento en existir de verdad, así que la comprobación no lo
  veía y luego ya no quedaba nadie para cerrarlo. Ahora, en cuanto WProton
  empieza a cerrarse no se arranca nada más, y se vigila unos segundos por si
  aparece algún rezagado.
- **Steam ya no cree que el juego sigue abierto** al cerrarlo. El fondo de los
  menús se cerraba "a la orden" sin comprobar que hubiera obedecido, y si se
  quedaba vivo, Steam daba el juego por abierto —porque lo considera en marcha
  mientras quede algún proceso de WProton—. Ahora se comprueba, y si algo
  sobrevive queda anotado en el registro con su nombre.
- **WProton ya no se cierra por un fallo recuperable.** Había una veintena de
  situaciones que cerraban el programa entero: que falte un runner, que se
  cancele el asistente, que falle una descarga o un empaquetado, que no se
  pueda abrir un juego. Todas avisan ahora y vuelven al menú, dejando los
  montajes limpios. Los avisos, además, dicen dónde arreglarlo: por ejemplo,
  si no hay ningún runner, indican el menú desde el que descargarlo.

## v1.19

- **Corregido: configurar un juego suelto cerraba WProton.** Si el último juego
  jugado era un `.exe` dentro de una carpeta, al abrir sus ajustes WProton
  intentaba montarlo como si fuera un archivo empaquetado, daba error y se
  cerraba. Ahora usa su carpeta directamente, y un fallo al abrir un juego
  avisa y vuelve al menú en vez de cerrar el programa.
- **Se comprueba lo que se descarga.** De cada runner o herramienta se calcula
  su huella y queda anotada. Si un fichero llega corrupto o a medias, se
  descarta en vez de instalarse. Y en *Runners y herramientas → Comprobar lo
  descargado* puedes revisar cuando quieras que todo sigue como se descargó.
- **Las barras de progreso son reales.** Al empaquetar un juego o extraer un
  comprimido, la barra avanza según lo que va haciendo la herramienta, no
  yendo y viniendo sin significar nada. En un empaquetado de varios minutos
  ahora se sabe si queda mucho o poco.

## v1.18

- **Al salir con B se pregunta antes de cerrar.** Volver de un submenú y una
  pulsación de más cerraba WProton sin avisar.
- **Corregido: la pantalla podía quedarse en negro al cerrar.** Si algún
  proceso de los menús sobrevivía, su ventana a pantalla completa seguía
  ocupando el monitor y parecía que el equipo se había colgado. Ahora se
  comprueba al cerrar y al arrancar.
- **Cerrar un juego con el mando ya no se anota como error.** El corte
  intencionado devuelve un código que WProton interpretaba como fallo del
  juego.
- **La carpeta de un disco externo se apunta donde están los juegos**, no en la
  raíz de la unidad. Guardar la raíz obligaba a recorrer el disco entero cada
  vez que se abría la biblioteca.
- **Abrir la biblioteca es mucho más rápido.** WProton abría el perfil de cada
  juego tres veces para leer sus datos, y encima lo hacía dos veces: al
  ordenar la lista y al construirla. Ahora se leen todos de una vez. En una
  Steam Deck con 37 juegos se tardaba una veintena de segundos; con 141, la
  parte de los datos pasa de más de cuatro segundos a menos de dos décimas.
- **Los datos de los juegos tienen su propia carpeta.** La ficha (año, estudio,
  géneros, notas) y la duración de HowLongToBeat estaban mezcladas con las
  carátulas; ahora viven en `datos/`. Los ficheros que ya tuvieras se trasladan
  solos la primera vez.
- **El mapeador `.keys` se prepara solo si hace falta.** Si al lanzar un juego
  con `.keys` falta el módulo que necesita, WProton lo instala en ese momento
  en vez de limitarse a avisar de que no funciona.

## v1.17

- **Carátulas verticales y horizontales, cada una en su carpeta.** Las
  verticales siguen en `covers/` y las anchas van en `covers_wide/`, con el
  **mismo nombre de fichero**: así puedes copiar una colección tal cual, sin
  renombrar nada. Al descargar de SteamGridDB se traen **ambas** de una vez, y
  si un juego solo tiene una, se usa esa en las dos vistas.
- **Corregido: elegir una carátula a mano no hacía nada.** La opción estaba en
  el menú pero la función nunca llegó a escribirse. Ahora funciona, y permite
  elegir si la imagen es la vertical o la horizontal.
- **Buscar la carátula de un juego a mano**, desde sus ajustes: escribes el
  nombre real, eliges entre los resultados de SteamGridDB y se descarga. Útil
  cuando el fichero se llama con la versión o el grupo y la búsqueda
  automática no encuentra nada.
- Corregido: al volver de la vista de carátulas anchas a la vertical, las
  casillas se quedaban con la forma ancha.
- **Al descargar carátulas se elige qué forma**: solo verticales, solo
  panorámicas, solo 4:3, o las tres. Bajarlas todas gasta el triple de tiempo
  y de peticiones, y casi nadie usa las tres vistas.
- **Las carátulas ya no se deforman.** Se ajustan a su casilla manteniendo la
  proporción: una carátula vertical en la vista ancha se ve entera y centrada,
  en vez de achatada.
- **Las carátulas con espacios en el nombre ya se encuentran.** WProton
  identifica los juegos cambiando los espacios por guiones bajos, así que una
  colección copiada a mano —con los nombres tal cual— no casaba. Ahora se
  prueban las dos formas, así que da igual cómo estén nombrados los ficheros.
- **Tres formas de carátula, cada una con su carpeta**: `covers/` (vertical
  2:3), `covers_wide/` (panorámica) y `covers_43/` (4:3). Los ficheros se
  llaman igual en las tres, así que puedes copiar una colección tal cual.
- **En la biblioteca ya no se ve la extensión** de los juegos: solo el nombre.
  Si dos ficheros distintos comparten nombre, el segundo la conserva para
  poder distinguirlos.
- **Estilo de botones para los `.keys`.** Los ficheros hechos en Batocera
  nombran los botones al estilo Nintendo —su "A" es el de la derecha y su "B"
  el de abajo—, al revés que el estilo Xbox. Con el estilo equivocado, los
  botones salen cambiados en el juego. Se elige por juego, en *Ajustes →
  Mapeador .keys → Estilo de botones*.
- **Corregido: los gatillos L2 y R2 no funcionaban con los `.keys`.** En casi
  todos los mandos no mandan una pulsación, sino un eje según lo apretados que
  estén, y WProton solo esperaba la pulsación. Ahora se traducen, con el
  recorrido que declare cada mando.
- **Corregido: la cruceta no funcionaba con los ficheros `.keys`.** Se
  comparaba con el mismo umbral que los sticks analógicos, y como la cruceta
  solo manda −1, 0 o +1, no llegaba a activarse nunca. Ahora funciona, y
  también en los mandos cuya cruceta llega como botones sueltos (Anbernic y
  similares).
- **Corregido: importar una carpeta sin ejecutable cerraba WProton.** El aviso
  se mostraba y, al aceptarlo, el programa se cerraba entero en vez de volver
  al menú. Lo mismo si un juego de la lista ya no existe en el disco.
- **Corregido: los mapeadores huérfanos de otra copia de WProton.** Se
  buscaban por la ruta exacta del programa, así que uno lanzado desde otra
  carpeta —una versión de pruebas, la del disco externo— no se encontraba y
  seguía mandando teclas. Ahora se buscan por nombre y se avisa en el registro
  de cuántos se cierran al arrancar.
- **Corregido: el mapeador `.keys` no llegaba a pararse.** Se guardaba el
  identificador de un proceso intermedio que muere al instante, así que la
  orden de parada no alcanzaba al proceso real. Ahora se para de verdad y
  WProton lo comprueba, dejando aviso en el registro si algo sobreviviera.
- **Corregido: el mapeador `.keys` seguía activo después de jugar.** Solo se
  paraba al cerrar WProton, así que durante todo el rato que navegaras por los
  menús tras una partida seguía convirtiendo los botones del mando en teclas
  del sistema. Ahora se para en cuanto termina el juego.
- **Corregido: un mapeador `.keys` de una sesión anterior escribía dentro de
  los menús.** Ese componente convierte los botones del mando en teclas del
  sistema. Si sobrevivía a la partida —por un cierre brusco—, seguía haciéndolo
  dentro de WProton: con un `.keys` que asigne A a la letra «i» y B a la «j»,
  entrar en una carpeta escribía «i» en el buscador y volver escribía «j». La
  pantalla se filtraba sola y parecía que los ficheros habían desaparecido.
  Ahora se eliminan al arrancar, como ya se hacía con los puentes de mando.
- **Corregido: la búsqueda se quedaba pegada de una pantalla a otra.** Lo que
  hubieras escrito en un buscador seguía filtrando la pantalla siguiente, así
  que al añadir un juego aparecían cuatro ficheros de cien y parecía que
  faltaban. El teclado en pantalla salía además con el texto anterior, al que
  se le iban sumando letras.
- Al navegar por las carpetas, **B en la carpeta raíz cierra el navegador** en
  vez de no hacer nada.
- **Al añadir un juego ya no aparecen los `.wsquashfs` ni los `.dwarfs`.** Esos
  ya salen solos en la biblioteca, y verlos ahí hacía pensar que había que
  añadirlos otra vez. Quedan las carpetas, los `.zip`, `.rar`, `.7z` y los
  ejecutables, que es lo que sí hay que importar.
- **Cuatro vistas**, que se recorren con Select + X: lista, rejilla vertical,
  rejilla panorámica y rejilla 4:3.
- **En la vista de lista puedes elegir qué carátula se ve** en el panel:
  vertical, panorámica o 4:3. Las panorámicas y las 4:3 se ven ahora bastante
  más grandes, porque ocupan el ancho del panel.
- Quitada la entrada *"juego suelto"* también de la rejilla: ya salían las
  carpetas por su cuenta.
- Corregido: la vista de carátulas horizontales no llegaba a aplicarse, y la
  descarga de SteamGridDB nunca pedía las anchas para los juegos que ya tenían
  la vertical.
- **Tercera forma de ver la biblioteca: carátulas horizontales.** Además de la
  lista y la rejilla de carátulas verticales, ahora hay una rejilla con
  portadas anchas —las que trae Steam de serie—, que se ven bastante más
  grandes. Se pasa de una a otra con **Select + X** o desde *Biblioteca y
  preferencias*.
- En la vista de lista, la carátula del panel lateral se ve más grande.
- **Las carpetas de juegos ya no se pueden perder solas.** A un tester le
  desapareció de los ajustes la carpeta de su disco externo sin haberla
  quitado. Ahora, si algo intenta guardar los ajustes sin ellas, se conservan
  y queda anotado en el registro. Para quitarlas sigue estando la opción del
  menú.
- **Los discos configurados se montan solos.** Si tienes una carpeta de juegos
  en un disco externo y al arrancar no está montado, WProton lo monta sin
  preguntar. Comprueba que la carpeta aparezca de verdad; si el disco no era
  el que hacía falta, lo deja como estaba. Funciona también con discos sin
  etiqueta, y **si el sistema lo monta en una ruta distinta a la de la vez
  anterior, corrige la ruta guardada** en vez de dar la carpeta por perdida.
- **Configurar el último juego sin abrir la lista**: ponte encima de *Jugar al
  último* en el menú principal y pulsa **X**.
- **Las copias de seguridad ya no incluyen la caché de shaders.** Se colaba la
  carpeta `dxvk` del prefijo, que puede ocupar bastante y se regenera sola: no
  es una partida guardada. Se descarta también en los perfiles que ya la
  hubieran aprendido, sin tener que borrarlos ni volver a jugar.
- **WProton ya no se queda colgado al salir.** Si al cerrar creía que aún
  había un juego en marcha, esperaba **hasta diez minutos en silencio** a que
  soltara sus procesos: desde fuera parecía que se había bloqueado y no
  quedaba más remedio que matarlo. Ahora espera veinte segundos como mucho y
  se cierra igualmente.
- **Configurar un juego es inmediato.** La primera vez que abrías la
  configuración de un juego, WProton consultaba por red la base de umu para
  proponerte su identificador, y eso se hacía **en silencio**: pulsar X sobre
  un juego nuevo podía tardar una eternidad y parecía que se había colgado.
  Esa consulta ya no se hace sola — sigue disponible cuando la quieras, en
  *Buscar en la base de umu* dentro de los ajustes del juego. La búsqueda de
  perfiles de la comunidad sí se mantiene, ahora avisando en pantalla y con
  mucha menos espera antes de rendirse.
- **Abrir la lista de juegos es más rápido** con bibliotecas grandes: se
  acotaron las búsquedas dentro de las carpetas y se dejaron de repetir
  comprobaciones que se hacían una vez por juego.

- **Dos runners nuevos para descargar**: **Soda** y **Caffe**, los de Bottles.
  Soda está basado en el Wine de Valve y Caffe es una compilación estable;
  ambos son alternativas a Wine-GE para juegos que no van bien con Proton.
- **Mando via SDL vuelve a funcionar** con GE-Proton 11-4 y posteriores. Se
  usaba un nombre de opción antiguo, así que la opción no tenía efecto; y con
  esas versiones se ignoraba aunque la activaras a mano. Si un juego iba bien
  con una versión anterior de GE-Proton, ponerla en ON suele recuperar ese
  comportamiento.
- Corregido: al salir de WProton podía quedarse la pantalla en negro.

## v1.15

- **Cambiar entre lista y rejilla con el mando**, con Select + X.
- **La clave de SteamGridDB, sin teclearla**: deja un fichero de texto con la
  clave junto a `wproton.sh` y WProton la recoge y la guarda a buen recaudo.
- Corregido: cambiar el tema, el idioma o el tamaño de letra no se notaba
  hasta reiniciar WProton.
- Menos opciones que entender: *Mando Sony* pasa a tres estados
  (AUTO / ON / OFF) y el registro deja de llenarse de información de
  diagnóstico salvo que la pidas.

## v1.14

- **WProton se añade a Steam con su propia imagen** y aparece en la biblioteca
  como un juego más. Desde el modo Juego se abre sin salir al escritorio.
- **Accesos directos en el escritorio**, tanto de WProton como de cada juego,
  con su carátula de icono.
- **Cerrar un juego con el mando**: mantén Select unos segundos. Útil en el
  escritorio, donde no hay botón de Steam.
- **El puntero del ratón deja de estorbar** mientras juegas.
- **Runner propio de WProton (GE-Custom)**, que se instala de serie.
- **Montar discos desde WProton**: si tus juegos están en un disco externo, se
  detecta, se monta y se añade a la biblioteca de una vez.
- **Más librerías de Windows** para instalar: `d3dcompiler_43`, `d3dx11_43`,
  `xna40`, `corefonts` y varias más, además de un pack que instala de golpe
  todo lo de DirectX.
- **Borrar la configuración de un juego** y empezar de cero, desde sus ajustes
  o desde la lista de perfiles guardados.
- **Dos asistentes para los problemas de mando**: uno prueba el mando y dice
  qué botones llegan; otro prepara los permisos que hacen falta en algunas
  distribuciones.
- Con GE-Proton 11-4 o más nuevo, WProton **no toca la configuración de los
  mandos**: esa versión los maneja mejor por su cuenta.

**Correcciones destacadas**

- Los juegos no arrancaban en el modo Juego de SteamOS.
- Los perfiles de la comunidad se descargaban pero no llegaban a aplicarse.
- Entrar en los ajustes de un juego recién añadido devolvía al menú principal.
- En algunos mandos, cada pulsación contaba dos veces.
- El menú se cerraba solo al volver a abrirse Steam.
- Con la biblioteca vacía, *Jugar* y *Ajustes de un juego* no decían nada.

## v1.11

- **Varias carpetas de juegos**, para quien los tenga repartidos entre discos.
- **Las carpetas cuentan como juegos**: un juego descomprimido aparece en la
  lista sin tener que empaquetarlo.
- **Las actualizaciones miran también la fecha**, así que una corrección
  publicada con el mismo número de versión ya no pasa desapercibida.

## v1.10

Limpieza interna. Nada cambia al usarlo, pero se eliminó código repetido que
era fuente de errores difíciles de encontrar.

## v1.09

- El menú de ajustes de un juego pasa de 42 opciones a 24, agrupando en dos
  submenús lo que casi nunca se toca.
- Corregido: pulsar B para salir de la lista de juegos daba un error y cerraba
  WProton.

## v1.07

- **Empaquetar un juego con su prefijo**: crea un archivo autosuficiente que se
  copia a otro equipo y funciona sin instalar nada.

## v1.06

- **La lista de juegos enseña la carátula** y los datos del juego resaltado:
  año, estudio, géneros, nota de la crítica y cuánto llevas jugado.
- **Marcar favoritos al instante** con R1, sin salir de la lista.

## v1.05

- **Ficha del juego** (L1): año, desarrollador, editor, géneros y notas de la
  crítica, con la duración aproximada si instalas los datos de HowLongToBeat.
- **Botones dedicados** en la lista: L1 para la ficha, R1 para favoritos.
- Añadir a Steam más fiable: WProton lo cierra y lo reabre él mismo.

## v1.04

- **Base de datos de umu**: identifica el juego y aplica los arreglos que
  necesita, sin tener que buscarlos a mano.
- **Elegir el ejecutable** de una lista ordenada, con el tamaño de cada uno
  para distinguir el juego del instalador.
- **Carátula manual**: elige cualquier imagen de tu disco.

## v1.02 – v1.03

- **Los menús ya no parpadean** entre pantalla y pantalla.
- Comprobaciones automáticas al construir el programa, para que ciertos fallos
  no puedan repetirse.

## v1.01

Reorganización interna del código. Sin cambios visibles.
