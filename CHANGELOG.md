# Changelog

Novedades de WProton. Formato de versiones: `0.5 → 0.51 → 0.52 …` para mejoras
y correcciones, con salto a `0.6`, `0.7`… cuando hay cambios grandes.

---

## v1.0

Primera versión estable. Sin funciones nuevas: repaso completo del código y
corrección de los fallos encontrados en la revisión final.

- **Corregido**: los ajustes `ENV=` y `LANG=` de los `autorun.cmd` estilo
  Batocera no se estaban aplicando, y los argumentos escritos en el propio
  `autorun.cmd` se perdían.
- **Corregido**: esos mismos ajustes podían heredarse del juego anterior
  dentro de la misma sesión.
- Revisión cruzada de todas las opciones de menú y sus acciones: ninguna
  queda sin respuesta.
- Ficheros de idioma sincronizados con los textos del programa.
- **Soporte de `.bat` y `.cmd`**: algunos juegos —sobre todo ports y títulos
  antiguos— arrancan con un script por lotes en vez de un ejecutable. Ahora
  aparecen al elegir el ejecutable, se pueden importar y jugar directamente,
  y se lanzan con el intérprete de comandos de Windows. La detección
  automática sigue prefiriendo el `.exe` cuando lo hay, para no confundir un
  `config.bat` con el lanzador del juego.
- **Corregido el "reinicio de la consola" en el modo Juego de SteamOS**: al
  salir de un juego, WProton intentaba cerrar posibles instancias de gamescope
  buscándolas por su nombre. En el modo Juego la propia sesión **es** un
  gamescope, así que esa limpieza cerraba la sesión entera y Steam volvía a
  arrancar. Ya no se toca ningún proceso de gamescope.
- **Corregido**: al descargar un perfil de la comunidad, WProton se cerraba de
  golpe. Era una declaración de variables que bash dejaba sin valor y, con las
  comprobaciones estrictas activadas, abortaba el programa sin decir nada.
- **Perfiles de la comunidad automáticos**: al añadir o lanzar un juego nuevo,
  si el repositorio tiene una configuración con ese nombre, WProton lo ofrece.
  La lista se guarda un día y solo se pregunta una vez por juego. El nombre se
  compara ignorando mayúsculas y separadores (`Mina the Hollower`,
  `Mina.the.Hollower`, `MINA-THE-HOLLOWER`) y admitiendo la coletilla de
  versión o grupo que traen las descargas (`...v1.0.2`, `...-GOG`, `...-P2P`).
- **squashfuse y fuse-overlayfs se preparan durante la instalación**, no la
  primera vez que intentas jugar, y **se descarga una copia propia aunque el
  sistema ya las tenga**: así WProton se puede mover a otro equipo o a un
  pendrive y sigue funcionando igual.
- Compilar squashfuse queda **solo** para cuando no hay ninguna disponible (en
  SteamOS no hay compilador): si el sistema ya trae una, se usa esa.
- El registro explica ahora por qué se descarta cada binario candidato:
  arquitectura equivocada, librería ausente o una descarga que no era un
  binario.
- Si no se pudieran conseguir, WProton ya no se cierra: arranca igualmente,
  avisa de qué falta y deja reintentarlo desde el menú (los juegos en carpeta
  siguen funcionando mientras tanto).
- **Puesta en marcha desatendida**: al ejecutar WProton por primera vez avisa
  desde el primer segundo de que está descargando lo necesario —antes incluso
  de bajar las herramientas de montaje— y va informando de cada paso, primero
  con lo que haya disponible (terminal o zenity) y después en su propia
  ventana. Ya no hay que pulsar "Aceptar" tras instalar Python o GE-Proton:
  es un proceso automático de principio a fin, y nunca se apilan dos ventanas.
- Corregido el texto de la pantalla de carga, que se montaba sobre el logotipo.
- **El tema "moderno" pasa a ser el predeterminado** (el clásico y el arcade
  siguen disponibles en *Biblioteca y preferencias → Tema de los menús*).
- **Los menús se abren a pantalla completa por defecto**. Si prefieres
  ventana, Select+A (o F11) y queda recordado.
- La pregunta del primer arranque es ahora una elección clara entre usar la
  carpeta `games/` o buscar otra, y al elegir "otra" se abre directamente el
  navegador de WProton.
- **Corregida la instalación desde cero**: un parámetro de `pip` se había
  quedado con una tilde por un cambio de textos, así que la instalación de
  pygame fallaba siempre y los menús se quedaban en modo GTK/zenity. Ahora
  además se reintenta con la rueda precompilada y se comprueba que pygame
  funcione de verdad antes de darlo por bueno.
- **Carátulas por fila** ahora se elige desde *Biblioteca y preferencias*, sin
  editar ficheros: automático o de 4 a 8. Al fijar un número, el tamaño de las
  carátulas se recalcula para que quepan en la pantalla.
- **Al abrir WProton por primera vez pregunta dónde tienes los juegos**, para
  no obligar a mover nada a `games/`. Si no se elige ninguna, sigue usando esa.
- **Copias de partidas mucho más rápidas**: se excluye lo que no son partidas
  (el Windows del prefijo, cachés de shaders, temporales y registros) y se
  comprime en modo rápido. En un juego con prefijo incluido, una copia que
  antes tardaba más de media hora ahora se resuelve en segundos. Si aun así
  la copia es enorme, avisa del tamaño antes de empezar y muestra progreso.
- El selector de carpetas usa el navegador de WProton, manejable con el mando,
  en vez del diálogo del escritorio.
- Más formas de conseguir `squashfuse` y `fuse-overlayfs` cuando faltan, por
  orden: una copia alojada en las releases de WProton, los binarios estáticos
  de siempre, el paquete oficial de Arch Linux (del que se extrae el binario)
  y, como último recurso, compilarlo desde el tarball oficial. Cada candidato
  se ejecuta antes de darlo por bueno, así que uno que no funcione en tu
  sistema simplemente se descarta.
- Documentación: [manual de uso](MANUAL.md) completo y README actualizado.

## v0.98

**Copia de tu configuración**
- Exporta ajustes, perfiles, `.keys` y carátulas a un zip con fecha, para pasar de un equipo a otro o guardarlos.
- Al importar puedes **añadir solo lo que falte** (conservando lo tuyo) o **sustituirlo todo** (con copia previa automática). Si la carpeta de juegos del otro equipo no existe aquí, se detecta y se corrige.

**Accesibilidad y textos**
- **Tamaño de letra configurable**: normal, grande o muy grande. Escala también las filas y la cabecera.
- Todos los textos llevan ya las tildes correctas y se han renombrado las opciones menos claras.
- Traducción al inglés completa: **el inglés viaja dentro del script** y se instala solo, así no puede quedarse desfasado.

**Correcciones**
- Los avisos y preguntas se responden con el mando: antes algunos solo aceptaban teclado o ratón.
- Arreglado que "Añadir un juego" no abriera, por un texto renombrado sin actualizar su acción.
- La carpeta de origen se recuerda **antes** de borrar el archivo importado.
- SteamOS: WProton ya no se cierra cuando el servidor gráfico tumba el menú al salir de un juego; lo detecta y reabre el menú. Se espera además a que la pantalla se estabilice.
- Fondo entre menús para no ver el escritorio al cambiar de pantalla.

## v0.97

- **Soporte de DwarFS**: los `.dwarfs` se usan igual que los `.wsquashfs` (perfiles, partidas, prefijos) y se puede elegir el formato al empaquetar. Las herramientas se descargan portables.
- El formato se detecta por la **cabecera del archivo**, no por la extensión.

## v0.96

- **Verificación de integridad** de los archivos de juego, con comprobación rápida antes de montar.
- **Aviso de espacio insuficiente** antes de importar o empaquetar, con estimaciones realistas.
- **Espacio en disco**: qué ocupa cada cosa, tamaño por juego, limpieza de cachés, prefijos y partidas huérfanas, y borrado de copias antiguas.
- **Menú principal agrupado** en submenús temáticos.

## v0.95

- **Copias de seguridad de partidas**: WProton observa qué escribe cada juego y **aprende la carpeta exacta**, en vez de copiar AppData entero. Copias en zip con fecha, restauración y sincronización con rsync o Syncthing.
- **Perfiles de la comunidad**: descarga de configuraciones ya probadas, con validación del contenido y respeto por los perfiles propios.

## v0.94

- **Teclado en pantalla** para escribir argumentos, DLL overrides, notas o la clave de SteamGridDB con el mando.

## v0.93

- **Estadísticas** de tiempo jugado y última partida.
- **Favoritos** (con cinta en la carátula) y **orden** por nombre, recientes o más jugados.
- **Notas por juego**, que viajan con el perfil.

## v0.92

- **Internacionalización**: idioma en `settings.conf` y traducciones en ficheros JSON, ampliables sin tocar el script.

## v0.9 – v0.91

- Modo Juego de SteamOS: corregido el arranque y ajustado el tamaño de las carátulas a cada pantalla.
- Los argumentos de lanzamiento se aplican en todas las vías (antes se perdían en juegos sueltos).

## v0.85 – v0.89

- **Configuración rápida** con **X** desde la lista de juegos.
- **Mando vía SDL automático** según el mando conectado.
- Probar → configurar → volver a probar sin salir del flujo, y empaquetar desde la propia configuración.
- Juegos sueltos (carpetas y `.exe`) como ciudadanos de primera, también por línea de comandos.
- Modo "solo jugar" (`DIRECT_PLAY`) y rutas relativas.

## v0.8 – v0.84

- **Sistema de temas**: clásico, moderno y arcade.
- Búsqueda con teclado y teclado virtual, barra de desplazamiento y marquesina para textos largos.
- Memoria de la última carpeta usada.

## v0.7 – v0.76

- **Instalación desatendida** de instaladores GOG (sin ventanas ni teclado), con extractores portables como respaldo.
- **Vista de rejilla con carátulas** y descarga desde SteamGridDB.
- **Añadir juegos a Steam**.
- Pantalla completa con **Select + A** y NTsync.

## v0.6 – v0.65

- Primeras funciones de carátulas, Steam e importación desde GOG.
- Herramientas portables (innoextract, innounp) sin depender del sistema.

## v0.5 — punto de partida

Primera versión numerada, ya con: formatos `.wsquashfs`/carpeta/`.exe`, menús con mando por lectura directa de `/dev/input`, descarga de runners con auto-descarga por perfil, perfil por juego con todos los toggles, herramientas (winecfg, winetricks, redistribuibles, dgVoodoo2, OptiScaler, mapeador `.keys`), importación con pruebas antes de empaquetar, soporte de Batocera y auto-actualización.
