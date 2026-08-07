# Changelog

Novedades de WProton. Formato de versiones: `0.5 → 0.51 → 0.52 …` para mejoras
y correcciones, con salto a `0.6`, `0.7`… cuando hay cambios grandes.

---

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
