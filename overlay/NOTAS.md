# La capa de Vulkan del menú: por qué está hecha así

Notas de diseño con las fuentes al lado. Lo que sigue no son opiniones: cada
decisión está contrastada con lo que hacen los proyectos que ya resolvieron
esto, y se dice cuál y dónde.

Proyectos leídos: **MangoHud**, **Mesa** (`src/vulkan/overlay-layer`),
**vkBasalt**, **obs-vkcapture**, **RenderDoc**, **gamescope** (su capa de WSI),
**DXVK**, **Wine** (`dlls/winevulkan`), **KWin**, **RetroArch** y
**EmulationStation** (el de Batocera).

---

## 1. Por qué una copia y no un pipeline

MangoHud, Mesa, vkBasalt y RenderDoc pintan con un **render pass** con
`loadOp = LOAD`. Lo necesitan: dibujan texto y gráficas semitransparentes que
cambian cada fotograma.

Nuestro panel no. Es **opaco, rectangular, sin escalar**, y solo cambia cuando
el usuario mueve el mando. Para eso basta `vkCmdCopyBufferToImage`:

- unas 250 líneas en vez de unas 2000;
- sin shaders que compilar dentro del juego;
- sin tocar nada del estado gráfico del juego, que es donde se rompen los
  overlays.

El precio es que no hay mezcla alfa ni escalado. No hacen falta: el panel tapa
lo que hay debajo, igual que el menú de RPCS3 que puso Dani como referencia.

**Nadie más escribe una interfaz en la imagen del swapchain con una
transferencia.** El único que la toca con una copia es **obs-vkcapture**, y la
copia al revés (saca el fotograma para grabarlo). Nuestra secuencia de barreras
es la de obs-vkcapture con `TRANSFER_WRITE` donde él pone `TRANSFER_READ`.

### Lo que sí hay que vigilar por hacerlo con una copia

- **El formato.** `vkCmdCopyBufferToImage` NO convierte nada: los bytes del
  buffer tienen que estar ya en el formato de la imagen. Se admiten los cuatro
  de 8 bits por canal (`B8G8R8A8` y `R8G8B8A8`, `UNORM` y `SRGB`, más
  `A8B8G8R8_PACK32`). Con cualquier otro —HDR de 10 bits, coma flotante de 16—
  **no se pinta** y se dice el formato en el registro; el menú sale por la
  ventana de siempre.
- **El espacio de color NO hace falta convertirlo.** pygame da bytes sRGB y la
  pantalla espera bytes sRGB, tanto si el formato es `_SRGB` como si es
  `_UNORM` con espacio `SRGB_NONLINEAR`. El problema de «sale demasiado claro»
  es de los que pintan con un render pass, donde la salida del shader es lineal
  y se codifica al escribir. Con una copia no pasa por ahí.

---

## 2. Lo que hace que esto funcione dentro de Proton

**DXVK ya pide `TRANSFER_DST`, sin preguntar, desde noviembre de 2018**
(`dxvk/src/dxvk/dxvk_presenter.cpp`, commit `979ccf23`):

```cpp
swapInfo.imageUsage = VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT
                    | VK_IMAGE_USAGE_TRANSFER_DST_BIT;
```

Tres consecuencias, y la tercera es la que decide el diseño:

1. En un juego con DXVK nuestro enganche a `vkCreateSwapchainKHR` **no hace
   nada**: el bit ya está. Solo hace falta para juegos de Vulkan nativo.
2. DXVK tampoco pregunta por `supportedUsageFlags`. Si una superficie no
   admitiera `TRANSFER_DST`, el propio `vkCreateSwapchainKHR` de DXVK fallaría
   y el juego no arrancaría.
3. Por tanto, **en todo equipo donde arranca un juego con DXVK, `TRANSFER_DST`
   está disponible.** La especificación solo garantiza
   `COLOR_ATTACHMENT_BIT`, así que para una capa de uso general esto sería
   frágil; para la nuestra, que vive dentro de Proton, no lo es.

Y DXVK deja sus imágenes en `VK_IMAGE_LAYOUT_PRESENT_SRC_KHR`, que es
exactamente de donde parte nuestra primera barrera.

**La capa tiene que ser una `.so` de Linux, no una DLL.** Wine no enumera
ninguna capa: `vkEnumerateInstanceLayerProperties` de `winevulkan` devuelve
`*count = 0` y punto. Pero `wine_vkCreateInstance` reenvía la llamada al
cargador **de Linux**, que es quien lee `VK_LAYER_PATH` y compañía. Así que la
capa se sitúa **por debajo de winevulkan y por encima del driver**, y ve el
swapchain de DXVK igual que lo vería en un juego nativo. Es como funcionan
MangoHud, vkBasalt y obs-vkcapture bajo Proton.

---

## 3. Las tres cosas que tienen que estar bien

### Un nombre de capa por arquitectura

MangoHud: `VK_LAYER_MANGOHUD_overlay_x86_64` / `..._x86`.
gamescope: `VK_LAYER_FROG_gamescope_wsi_x86_64` / `..._x86`.

No es cosmético. Si las dos se llamaran igual, el cargador encontraría el
primer manifiesto con ese nombre e intentaría abrir el `.so` de la arquitectura
equivocada: falla, y falla en silencio. WProton enciende **los dos nombres** y
cada cargador usa el suyo.

### `file_format_version` en `1.0.0`

El contenedor de Steam (pressure-vessel) rechazaba manifiestos que declaraban
`1.2.0` porque no conocía ese número, y dejaba la capa fuera sin decir por qué
([steam-runtime #457](https://github.com/ValveSoftware/steam-runtime/issues/457)).
MangoHud y gamescope siguen poniendo `1.0.0`.

### Las dos puertas y la moderna

Los cargadores antiguos buscan `vkGetInstanceProcAddr` /
`vkGetDeviceProcAddr` **por su nombre dentro del `.so`** —de ahí el mapa
`functions` del manifiesto, que las renombra para no chocar con las de
verdad—. Los de ahora llaman a `vkNegotiateLoaderLayerInterfaceVersion` y se
quedan con los punteros que les devuelve. **Se mantienen las dos vías**: sin la
moderna la capa entra en un equipo viejo y no en uno nuevo, y eso desde fuera
parece «a veces funciona».

Y `-fvisibility=hidden`: una `.so` exporta todos sus símbolos por omisión, y
una capa que exporta de más pisa los del juego o los del cargador.

---

## 4. La sincronización, que es la otra mitad de los fallos

Nuestra copia tiene que ir **después** de que el juego acabe de dibujar y
**antes** del present. Así que el envío espera los mismos semáforos que iba a
esperar el present, señala uno nuestro, y se reescribe el present para que
espere al nuestro.

### Una ranura por imagen del swapchain

Lo primero que uno escribe es un juego de objetos —bloque de órdenes, valla,
semáforo— por dispositivo. Está mal, y de una forma fina: **una valla dice que
el ENVÍO terminó, no que el motor de presentación haya esperado ya nuestro
semáforo.** Reusar un semáforo binario con una espera pendiente es lo que
produce los avisos de «semaphore already in use» y, en un driver menos amable,
imagen rota.

Con una ranura por índice de imagen eso no puede pasar: el juego no puede
volver a presentar esa imagen sin haberla pedido otra vez, y pedirla implica que
la presentación anterior acabó. **MangoHud lo hace así, por lo mismo**
(`get_overlay_draw`, indexado por `image_idx`, con `WaitForFences` al
reciclar). vkBasalt usa semáforo por imagen pero **sin valla ninguna**: le
funciona, y no conviene copiarlo.

El buffer de subida sí es uno solo, y se puede: solo se reescribe cuando el
panel cambia de verdad, y antes de reescribirlo se esperan todas las ranuras en
vuelo.

### Varios swapchains en un present

Cuatro proyectos, cuatro respuestas:

- **Mesa** parte el present en N llamadas. Tiene **dos fallos** ahí: copia
  `VkPresentInfoKHR` en plano y deja el `pNext` con `swapchainCount = N` dentro
  mientras la estructura de fuera dice 1; y pasa los semáforos del juego a cada
  iteración, o sea que espera N veces un semáforo binario señalado una.
- **MangoHud** se niega a partirlo: pinta solo en `pSwapchains[0]` y reenvía el
  present entero con los semáforos cambiados.
- **vkBasalt**: un envío por swapchain, y **solo el primero consume los
  semáforos del juego**; todos los semáforos nuestros van al present.
- **gamescope** es el único que parte un present bien, y le cuesta una clase de
  trescientas líneas (`PresentInfoSlice`) que recorta cada array del `pNext` —
  con una bandera `complete` que se pone a falso ante cualquier `sType`
  desconocido, y entonces **se niega a partir**.

**Aquí se usa el modelo de vkBasalt**, y el present no se parte nunca. Como
`swapchainCount` no cambia, copiar la estructura en plano con su `pNext` tal
cual es correcto, y es lo que hacen MangoHud y obs-vkcapture.

### Detalles pequeños que vienen de leerlos

- `pWaitDstStageMask` = `VK_PIPELINE_STAGE_TRANSFER_BIT` (MangoHud pone
  `FRAGMENT_SHADER_BIT` porque dibuja; nosotros copiamos).
- Array fijo de 32 esperas, el tope de obs-vkcapture. Por encima **no se pinta
  ese fotograma** y nada más: ni se rompe la capa ni se reserva memoria en el
  camino del present.
- **Todo el estado va colgado de los identificadores**, nunca de un global. Ese
  es literalmente el fallo del overlay de Steam
  ([steam-for-linux #9120](https://github.com/ValveSoftware/steam-for-linux/issues/9120)):
  guardaba el `VkDevice` en un global y liberaba objetos por el dispositivo
  equivocado cuando DXVK creaba un segundo para vídeo. `VK_ERROR_DEVICE_LOST`.
- Se envía **en la cola que nos han dado**, no en otra. Enviar a `graphic_queue`
  desde dentro del enganche de present es un problema de sincronización
  conocido y sin arreglar en Mesa
  ([mesa #3155](https://gitlab.freedesktop.org/mesa/mesa/-/issues/3155)).

---

## 5. El orden de las capas

Nuestra capa es **explícita y encendida a mano**, así que el cargador la pone
**más cerca del driver** que MangoHud y que la capa de WSI de gamescope, que son
implícitas. Consecuencia práctica: nuestro `vkQueuePresentKHR` ve un
`VkPresentInfoKHR` que MangoHud **ya ha reescrito**, y nuestro panel se pinta
**encima** del suyo. Para un panel lateral da igual.

Para ver la cadena de verdad en un equipo: `VK_LOADER_DEBUG=layer`.

---

## 6. El fallo de KDE que empezó todo esto

El síntoma: juego a pantalla completa bajo Proton, se abre algo encima, la
imagen se congela, el sonido sigue, y vuelve al mover el ratón de verdad.

**No se ha encontrado un informe de fallo que describa exactamente eso.** Lo que
sí se puede decir, leído de KWin:

- Las *frame callbacks* se emiten **solo para lo que el compositor ha pintado**
  en esa vista (`Item::framePainted` → `collectItems`, filtrado por
  `shouldHideItem`). **No se encontró supresión por oclusión**: un juego a
  pantalla completa que se sigue pintando debajo de un overlay debería seguir
  recibiendo callbacks. Eso apunta a que el síntoma **no** es simple inanición
  de callbacks.
- **KWin no respeta `_NET_WM_BYPASS_COMPOSITOR`**: cero apariciones en todo el
  árbol. En Wayland el equivalente es el escaneo directo, y lo decide el
  compositor (`layers.size() == 1 && layers[0].directScanout`), no lo pide el
  cliente. Una ventana encima rompe necesariamente la condición de una sola
  capa y fuerza la transición de escaneo directo a composición — que es
  justo donde vive esta clase de fallo.
- La prueba que separa las dos hipótesis: arrancar la sesión con
  `KWIN_DRM_NO_DIRECT_SCANOUT=1`. Si el congelado desaparece, es la transición
  de escaneo; si sigue, es el ritmo de las callbacks o de XWayland. La capa
  apunta esa variable y las otras cinco del entorno en `runtime/capa.log`, y
  pone la hora en cada aviso de fotograma: así un registro distingue «el juego
  dejó de presentar» de «sigue presentando y no se ve nada».
- Que correr el juego dentro de gamescope lo arregla **se recomienda mucho y no
  está documentado por nadie**. Es arquitectónicamente razonable: gamescope
  absorbe la superficie del juego y KWin nunca decide nada sobre ella.

Como referencia de que la inanición de callbacks sí existe cuando una ventana
**está oculta**: [SDL #4335](https://github.com/libsdl-org/SDL/issues/4335),
«Wayland compositors will inhibit frame callbacks for window that are not
visible»; se arregló con un tiempo de espera de 100 ms.

---

## 7. La otra vía, que es más simple y ya está hecha

`mangoapp` no es una capa: es una ventana X11 normal que pone **una** propiedad
y deja que gamescope la componga encima del juego.

```c
Atom overlay_atom = XInternAtom(x11_display, "GAMESCOPE_EXTERNAL_OVERLAY", False);
set_x_cardinal_property(x11_display, x11_window, overlay_atom, 1);
```

gamescope la lee (`steamcompmgr.cpp`, `externalOverlayAtom`) y la pinta como un
plano propio. **WProton ya hace esto** en `src/menu_pygame.py`, y ya tiene un
ajuste por juego para lanzar dentro de gamescope. Para un panel opaco que solo
cambia con el mando, esa vía es mucho más robusta que enganchar el present — a
cambio de necesitar gamescope.

Las dos conviven: la capa funciona sin gamescope, y el panel por gamescope
funciona sin la capa.

---

## 8. Y cómo NO lo hacen los demás

- **Batocera / EmulationStation**: no hay overlay. `FileData::launchGame`
  **apaga su propio renderizador y el audio**, lanza el emulador como proceso
  hijo bloqueante y se reinicializa al volver. El menú que ve un usuario de
  Batocera dentro del juego es el del emulador, no el del frontend.
- **RetroArch**: un solo proceso. El core dibuja en el framebuffer de
  RetroArch y RetroArch compone el menú en el mismo fotograma. Sin inyección y
  sin ventana aparte. No sirve para un `.exe` ajeno.
- **Steam**: sí es una capa de Vulkan
  (`VK_LAYER_VALVE_steam_overlay_{32,64}`), de código cerrado.
- **VR / OpenXR**: no son capas de Vulkan, son capas de composición que se le
  entregan al compositor del runtime.

---

## 9. Cómo se prueba esto sin GPU

Era el supuesto que más tiempo nos costó: que lo de dentro del juego «solo lo
contesta el hardware». **Es falso.** No hay tarjeta gráfica, pero sí hay
cargador de Vulkan de verdad, y el cargador es quien encadena las capas: el que
lee el manifiesto, abre el `.so`, pregunta por las puertas y llama a nuestro
`vkCreateInstance` pasándonos el eslabón siguiente. Toda esa parte —que es
donde viven los fallos clásicos de una capa— no necesita GPU.

Lo único que faltaba era **algo al final de la cadena**, y eso se escribe: un
driver de Vulkan de mentira que no dibuja nada y se limita a apuntar lo que le
piden. Con él puesto, la capa se ejecuta de verdad y el diario del driver dice
exactamente lo que pidió:

```
driver: vkCreateInstance
driver: vkCreateDevice
driver: vkGetDeviceQueue familia=0
driver: vkGetPhysicalDeviceSurfaceCapabilitiesKHR
driver: vkCreateSwapchainKHR 1920x1080 uso=18 copia=1
driver: vkCreateCommandPool familia=0
driver: vkCreateBuffer 480000 bytes uso=1
driver: barrera 1000001002 -> 7 (etapas 8192 -> 4096)
driver: copia imagen=1 layout=7 en 40,40 de 400x300 fila=400
driver: barrera 7 -> 1000001002 (etapas 4096 -> 8193)
driver: vkQueueSubmit espera=1 senala=1 ordenes=1
driver: vkQueuePresentKHR esperas=1
```

Ahí está todo el diseño comprobado en una pantalla: `uso=18` es
`COLOR_ATTACHMENT|TRANSFER_DST` (el bit lo añadimos nosotros, `copia=1`),
`1000001002` es `PRESENT_SRC_KHR` y `7` es `TRANSFER_DST_OPTIMAL`, la copia cae
donde dice el panel, el envío espera el semáforo del juego y señala el nuestro,
y el present acaba esperando **uno** semáforo, que es el nuestro.

**Dos detalles para montarlo**, que costaron un rato cada uno:

1. El cargador exige el juego **completo** de funciones de dispositivo físico
   antes de aceptar un driver (`vkGetPhysicalDeviceFeatures`,
   `...FormatProperties`, `...ImageFormatProperties`,
   `...SparseImageFormatProperties`, `vkEnumerateDeviceLayerProperties`,
   `vkEnumerateInstanceVersion`), aunque no vaya a usar casi ninguna. Si falta
   una, descarta el driver con «Failed to find required entrypoints» y luego
   «Found no drivers!», que parece otra cosa.
2. Para probar el swapchain hace falta una **superficie de verdad**. El cargador
   implementa él las superficies «sin pantalla» (`VK_EXT_headless_surface`),
   pero sólo las ofrece si algún driver dice saber de superficies: basta con que
   el driver de mentira anuncie `VK_KHR_surface` y
   `VK_EXT_headless_surface`. Con un identificador inventado, el cargador lo
   desenvuelve al crear el swapchain y se cae ahí, antes de llegar a la capa.

Y encontró un fallo que leyendo el código no se veía: **cuando el driver no
tiene `vkCreateSwapchainKHR`, el cargador escribe un error en su registro y
devuelve `VK_SUCCESS` sin dar ningún swapchain.** Apuntar ese hueco habría
pisado la tabla de swapchains, porque la tabla usa el identificador vacío para
marcar las filas libres.
