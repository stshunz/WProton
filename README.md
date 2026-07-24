# WProton
Programa hecho con la ayuda de Claude, si estas en contra de usar IA como ayuda a la programación no sigas leyendo.

Lanzador portable de juegos de Windows para Linux, en un solo script.

WProton monta, configura y lanza juegos de Windows (formato .wsquashfs estilo Batocera, carpetas sueltas o .exe) usando Proton o Wine, con menús navegables al 100% con mando. Todo vive junto al script: runners, prefijos, Python, saves y caches. Cópialo a un pendrive y juega en otra máquina.

> Versión actual: 0.5 — Probado en CachyOS (KDE Plasma), SteamOS (Steam Deck) y Batocera.

Inspirado en lo mejor de cuatro mundos: los menús y tweaks de PortProton/PortWINE, la descarga automática de runners de Heroic, los perfiles por juego de TeknoParrot y el lanzamiento vía umu de Faugus Launcher.

---

## Características

### Formatos de juego
- `.wsquashfs` / `.squashfs` — montaje con squashfuse + fuse-overlayfs: el juego es de solo lectura y los saves persisten en wsquashfs/overlays/<juego>/upper/ sin tocar el archivo original.
- Carpetas sueltas y `.exe` — se juegan directamente, sin empaquetar ni preguntas.
- Importación: zip, 7z, rar (multiparte: .001, .partN, .rNN, .z01), .wtgz → extracción, purga de originales y empaquetado a wsquashfs (zstd).
- Prefix incluido (estilo Batocera): si el wsquashfs contiene drive_c/ + system.reg, puede usarse como WINEPREFIX (las escrituras van al overlay).
- Wine incluido: si el wsquashfs trae su propio Wine (*/bin/wine), puede usarse como runner. Juego 100% autocontenido.

### Menús con mando (pygame)
- Lectura evdev directa de /dev/input: funciona sin foco de ventana, con hotplug, filtro de acelerómetros/IMU (handhelds) y soporte de crucetas por hat y por botones (Anbernic y similares).
- Búsqueda: escribe con el teclado real (filtro por prefijo de palabra en vivo) o pulsa Y para el teclado virtual en pantalla.
- Navegador de ficheros persistente e instantáneo para importar, jugar o elegir carpetas.
- Pantalla completa automática en Batocera; fallback a GTK/zenity/CLI si no hay pygame.

### Runners
- Descarga desde el menú: GE-Proton (últimas + cierre de cada serie: 9-27, 8-32, 7-55...), Proton-CachyOS, DWProton (fixes anime/gacha), Wine-LG y Proton-LG (Castro-Fidel/PortWINE), Wine-GE, Kron4ek.
- Auto-descarga: si el perfil de un juego pide un runner que no está instalado, se descarga solo antes de lanzar.
- Los Proton corren vía umu-launcher (protonfixes incluidos); los Wine puros, en directo.
- En Batocera: detecta los Wine del sistema (/usr/wine/* y /userdata/system/wine/custom/*) como runners sys:.

### Perfil por juego (profiles/<juego>.conf)
Runner, ejecutable, argumentos, prefijo (compartido / propio / incluido), GAMEID de protonfixes, y toggles: MangoHud, GameMode, Fsync/Esync, DXVK Async+GPL, WineD3D, FSR, LAA, Wayland, gamescope, DLL overrides, idioma, variables extra y Mando vía SDL (hace que DualSense/DS4/Switch aparezcan como mando Xbox en juegos solo-XInput, como hace PortProton).

### Herramientas integradas
- winecfg y winetricks sobre el prefijo del juego.
- Redistribuibles (menú principal, eligiendo prefijo destino): vcredist 2005-2022, PhysX, pack de prerrequisitos Unreal Engine, DirectX 9, d3dcompiler, XACT, Media Foundation, .NET 4.8.
- dgVoodoo2 (DX1-9/Glide para juegos antiguos) con su panel de control.
- OptiScaler (FSR/DLSS/XeSS upscaling).
- Mapeador `.keys` (mando → teclado por juego, formato Batocera/evmapy): se engancha automáticamente al lanzar si existe <juego>.keys junto al archivo o profiles/<juego>.keys.

### Batocera
- Lanzamiento delegado en `batocera-wine windows play` (toggle por juego, activado por defecto): prefijos, DXVK, mando y redistribuibles los gestiona el propio sistema.
- autorun.cmd completo: DIR=, CMD= (con comillas y argumentos), ENV=, LANG=; SAVEDIR= se ignora porque el overlay ya persiste los saves.
- Errores y log visibles en pantalla aunque no haya zenity.

- ### Importación con pruebas (modding)
Al importar una carpeta o .exe: Probar el juego sin empaquetar las veces que quieras (metiendo mods entre prueba y prueba) y empaquetar solo cuando funcione. La configuración hecha durante las pruebas se hereda al wsquashfs final. Tras empaquetar con éxito, pregunta si borrar la carpeta original.

### Auto-actualización
"Buscar actualizaciones" en el menú (o --update): consulta este repositorio, descarga la versión nueva, la valida (bash -n + formato) y se auto-reemplaza dejando copia .bak.

---

## Instalación

# 1. Descarga el script (o clona el repo) y dale permisos
chmod +x wproton.sh

# 2. Primera puesta en marcha: Python portable + pygame + umu + GE-Proton
./wproton.sh --setup

# 3. A jugar
./wproton.sh

### Requisitos

| Componente | Notas |
|---|---|
| bash, curl, tar | Presentes en cualquier distro |
| fusermount3 (paquete fuse3) | Del sistema |
| squashfuse, fuse-overlayfs | Pueden ir junto al script (portables) o en el sistema |
| mksquashfs (squashfs-tools) | Solo para importar/empaquetar |
| 7z (p7zip) | Solo para importar .7z/.rar |
| zenity | Opcional (diálogos en escritorio) |
| Python + pygame | Se auto-instalan portables con --setup |
| evdev (Python) | Para el mapeador .keys: --setup lo compila (CachyOS); en SteamOS/Deck copia tu carpeta evmapy/ a la raíz de WProton |

---

## Uso por línea de comandos

./wproton.sh                        # Menús
./wproton.sh juego.wsquashfs        # Montar y jugar
./wproton.sh juego.exe              # Jugar el exe directamente
./wproton.sh /ruta/carpeta          # Jugar la carpeta (busca el exe o su .sh)
./wproton.sh juego.zip              # Importar: extraer → empaquetar → jugar
./wproton.sh --import <exe|carpeta> # Forzar el flujo probar/empaquetar
./wproton.sh --exe juego.wsquashfs  # Elegir ejecutable manualmente
./wproton.sh --setup                # (Re)instalar Python portable, pygame, umu
./wproton.sh --update               # Buscar actualizaciones
./wproton.sh --version

Integración con frontends (ES-DE, DeckStation, etc.): apunta el lanzador a wproton.sh %ROM%.

## Controles del mando en los menús

| Botón | Acción |
|---|---|
| Dpad / stick izquierdo | Moverse |
| A / Start | Elegir / entrar |
| B | Volver / subir carpeta / limpiar búsqueda |
| X | Marcar casilla (listas de opciones) / borrar letra (búsqueda) |
| Y | Abrir el teclado virtual de búsqueda |

Con teclado: flechas, Enter, Esc, y escribe directamente para filtrar cualquier lista.

## Estructura de carpetas

wproton.sh                  ← todo el programa
settings.conf               ← carpeta de juegos, último jugado
profiles/                   ← un .conf (y opcionalmente un .keys) por juego
runtime/
  ├── python/ + libs_pyX.Y/ ← Python portable y dependencias
  ├── proton/               ← runners descargados
  ├── umu/                  ← umu-launcher
  └── mapeador.py, menu_pygame.py, ...
prefixes/
  ├── default/              ← prefijo compartido (por defecto)
  └── <juego>/              ← prefijos propios
wsquashfs/
  ├── tmp_mount/            ← montajes (se vacía al salir)
  └── overlays/<juego>/upper/  ← TUS SAVES (no borrar)
cache/                      ← shaders dxvk/vkd3d/mesa
logs/
games/                      ← tus .wsquashfs (configurable)

## Solución de problemas

- "Ver último log" en el menú principal muestra la sesión actual; los ficheros completos están en logs/.
- Un lanzamiento falla en <10 s → se muestran las últimas líneas del log automáticamente.
- El mando no funciona *dentro* de un juego (menús sí): comprueba el toggle "Mando vía SDL" en el perfil — imprescindible para DualSense/DS4 en juegos XInput fuera de Steam.
- El mapeador `.keys` no engancha: el log dice el motivo exacto (fichero no encontrado con las rutas probadas, o falta evdev).
- Batocera: runners custom en /userdata/system/wine/custom/<Runner>/ — recuerda el chmod a+x -R * tras copiarlos.
- tmp_mount con restos tras un corte de luz: se limpian solos en el siguiente arranque.
