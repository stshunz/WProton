/* ===========================================================================
 * WProton: capa de Vulkan para el menu de dentro del juego
 * ===========================================================================
 *
 * POR QUE EXISTE ESTO
 *
 * El menu de WProton se dibujaba en una VENTANA propia encima del juego, y esa
 * es la raiz de todo lo que fallo durante la noche del 20/10:
 *
 *   - en KDE, el compositor tiene que sacar al juego de su camino directo a
 *     pantalla para poder componer nuestra ventana, y el juego se queda
 *     congelado -sonando, pero congelado- hasta que algo fuerza un repintado;
 *   - en SteamOS, gamescope decide el solo que se ve: una ventana que
 *     desaparece y vuelve a aparecer podia no volver nunca;
 *   - y antes de eso, el juego perdia el foco y se minimizaba.
 *
 * Lo dijo Dani en una linea: "nuestro overlay se apodera de la imagen y no
 * deberia ser asi, sino se desincroniza el juego".
 *
 * Y tenia razon: NINGUN overlay de verdad hace eso. Steam y MangoHud
 * no crean ventanas: se meten DENTRO del bucle de dibujo del juego y pintan
 * sobre el fotograma antes de que se presente. Si no hay ventana, no hay nada
 * que el compositor tenga que reorganizar, y no hay nada que congelar.
 *
 * COMO SE ENGANCHA UNA CAPA (resumen de la guia de RenderDoc)
 *
 * El cargador de Vulkan encadena las capas. A cada una le pasa, en el pNext de
 * vkCreateInstance/vkCreateDevice, un VkLayerInstanceCreateInfo con un puntero
 * a la funcion "siguiente" de la cadena. Hay que:
 *
 *   1. exportar vkGetInstanceProcAddr y vkGetDeviceProcAddr;
 *   2. implementar vkCreateInstance y vkCreateDevice para quedarse con ese
 *      puntero y AVANZAR el eslabon (pLayerInfo = pLayerInfo->pNext) antes de
 *      llamar al siguiente;
 *   3. devolver nuestras funciones en GetProcAddr solo para lo que nos
 *      interesa, y reenviar todo lo demas.
 *
 * Y el manifiesto .json dice donde esta el .so y con que variable de entorno
 * se enciende, para no tener que instalar nada en el sistema: WProton es
 * portable y esto tambien.
 *
 * ---------------------------------------------------------------------------
 * ETAPA 1 (hecha): engancharse y contar fotogramas. Contestaba a la unica
 * pregunta que importaba antes de dibujar un pixel: ¿el cargador de Vulkan nos
 * mete DENTRO de un .exe de Windows que corre bajo Proton, con DXVK por medio?
 *
 * ETAPA 2 (esto): PINTAR. Se copia un rectangulo de pixeles encima del
 * fotograma justo antes de presentarlo. El rectangulo viene de un fichero de
 * memoria compartida que escribe el menu de WProton (ver abajo), y si no hay
 * fichero y se pide WPROTON_CAPA_PRUEBA=1 se pinta un patron de prueba, que es
 * como se comprueba el camino sin depender del resto.
 *
 * POR QUE UNA COPIA Y NO UN PIPELINE
 *
 * MangoHud y compania dibujan con ImGui: pipeline grafico, render pass,
 * shaders, descriptores. Lo necesitan porque pintan texto y graficas
 * semitransparentes que cambian cada fotograma. Nuestro menu no: es un panel
 * OPACO, rectangular, sin escalar, que solo cambia cuando el usuario mueve el
 * mando. Para eso basta vkCmdCopyBufferToImage, que es:
 *
 *   - unas 200 lineas en vez de unas 2000;
 *   - sin shaders que compilar dentro del juego;
 *   - y sin tocar nada del estado grafico del juego, que es donde se rompen
 *     los overlays (MangoHud lleva anos arreglando fallos de ese tipo).
 *
 * El precio es que no hay mezcla alfa ni escalado. No nos hacen falta: el
 * panel tapa lo que hay debajo, igual que el menu de RPCS3 que puso Dani como
 * referencia.
 *
 * LAS TRES COSAS QUE TIENEN QUE ESTAR BIEN
 *
 *   1. La imagen del swapchain tiene que admitir ser destino de una copia. Eso
 *      se pide en vkCreateSwapchainKHR anadiendo TRANSFER_DST a imageUsage, y
 *      SOLO si la superficie dice que puede (supportedUsageFlags). Si no
 *      puede, no se pinta en ese swapchain y se dice por que.
 *   2. Las dos barreras de layout: la imagen esta en PRESENT_SRC_KHR, hay que
 *      pasarla a TRANSFER_DST_OPTIMAL y devolverla a PRESENT_SRC_KHR. Con
 *      oldLayout = PRESENT_SRC (no UNDEFINED), que es lo que preserva el
 *      fotograma que el juego acaba de dibujar.
 *   3. La sincronizacion. El present del juego espera unos semaforos; nuestra
 *      copia tiene que ir DESPUES de eso y ANTES del present. Asi que nuestro
 *      envio espera esos mismos semaforos, senala uno nuestro, y se reescribe
 *      el present para que espere al nuestro.
 *
 * REGLA QUE MANDA SOBRE TODAS LAS DEMAS: si cualquier cosa falla, se deja de
 * pintar en ese dispositivo PARA SIEMPRE y el present sale intacto. Un menu
 * que no aparece es un fallo; un juego que no presenta es un desastre.
 * ======================================================================== */

#define VK_NO_PROTOTYPES
#include <vulkan/vulkan.h>
#include <vulkan/vk_layer.h>

#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>

/* Las cabeceras de Khronos no traen esto: es una convencion de las capas (la
 * guia de RenderDoc la usa). Marca las DOS funciones que el cargador busca por
 * su nombre dentro del .so; todo lo demas se queda dentro. */
#if defined(__GNUC__)
#define VK_LAYER_EXPORT __attribute__((visibility("default")))
#else
#define VK_LAYER_EXPORT
#endif

/* ---------------------------------------------------------------------------
 * EL REGISTRO
 *
 * Va a stderr y, si WPROTON_CAPA_LOG apunta a un fichero, tambien ahi. Lo
 * segundo importa: dentro de Proton, stderr acaba mezclado con miles de lineas
 * de Wine, y buscar la nuestra entre ellas es justo lo que queremos evitarle a
 * quien esta probando.
 * ------------------------------------------------------------------------ */
static FILE *g_log = NULL;
static int g_log_probado = 0;

static void capa_log(const char *fmt, ...)
{
    va_list ap;
    if (!g_log_probado) {
        const char *ruta = getenv("WPROTON_CAPA_LOG");
        g_log_probado = 1;
        if (ruta && *ruta)
            g_log = fopen(ruta, "a");
    }
    va_start(ap, fmt);
    vfprintf(stderr, fmt, ap);
    va_end(ap);
    fflush(stderr);
    if (g_log) {
        va_start(ap, fmt);
        vfprintf(g_log, fmt, ap);
        va_end(ap);
        fflush(g_log);
    }
}

/* Donde se ha metido la capa. Se apunta una vez, al crear la instancia.
 *
 * LAS SEIS VARIABLES QUE DECIDEN SI EL JUEGO SE CONGELA al poner algo encima:
 * si la sesion es Wayland o X11, que compositor la lleva, si hay gamescope por
 * medio -que absorbe la ventana del juego y entonces el compositor de fuera no
 * decide nada sobre ella- y si el escaneo directo de KWin esta desactivado.
 * Sin esto, cada registro ajeno obliga a preguntar. */
/* Segundos desde que se cargo la capa. Reloj monotono: no lo mueve el cambio
 * de hora del sistema, que es justo lo que no se quiere en una medida. */
static double capa_segundos(void)
{
    struct timespec ahora;
    static struct timespec cero;
    static int puesto = 0;
    if (clock_gettime(CLOCK_MONOTONIC, &ahora) != 0)
        return 0.0;
    if (!puesto) {
        puesto = 1;
        cero = ahora;
    }
    return (double)(ahora.tv_sec - cero.tv_sec) +
           (double)(ahora.tv_nsec - cero.tv_nsec) / 1e9;
}

static void capa_entorno_apuntar(void)
{
    static const char *cuales[] = {
        "XDG_SESSION_TYPE", "XDG_CURRENT_DESKTOP", "WAYLAND_DISPLAY",
        "DISPLAY", "GAMESCOPE_WAYLAND_DISPLAY", "KWIN_DRM_NO_DIRECT_SCANOUT",
    };
    unsigned i;
    for (i = 0; i < sizeof(cuales) / sizeof(cuales[0]); i++) {
        const char *v = getenv(cuales[i]);
        capa_log("[wproton-capa] entorno: %s=%s\n", cuales[i],
                 (v && *v) ? v : "(sin poner)");
    }
}

/* ===========================================================================
 * EL PANEL: COMO LLEGAN LOS PIXELES DESDE WPROTON
 * ===========================================================================
 *
 * El menu lo dibuja Python (pygame) FUERA del juego, como hasta ahora, porque
 * ahi ya esta todo escrito y funciona. Lo unico que cambia es a donde lo
 * manda: en vez de a una ventana, a un fichero de memoria compartida. La capa
 * lo mapea de solo lectura y lo copia encima del fotograma.
 *
 * El fichero son 64 bytes de cabecera y despues los pixeles, de corrido, 4
 * bytes por pixel. Nada de bloqueos: el que escribe pone los pixeles y DESPUES
 * sube "generacion"; el que lee se queda con la generacion que vio. Si pilla un
 * fotograma a medias, el peor caso es un parpadeo de una franja durante 16 ms,
 * y por evitar eso no merece la pena meter semaforos entre dos procesos.
 *
 * "visible" a 0 significa "no pintes": la capa entonces no toca el present en
 * absoluto, asi que un juego con el menu cerrado corre exactamente igual que
 * sin capa.
 * ------------------------------------------------------------------------ */
#define PANEL_MAGIA   0x4e505057u        /* "WPPN" en little-endian */
#define PANEL_VERSION 1u
#define PANEL_CABEZA  64u                /* bytes de cabecera */

/* Como vienen los bytes de cada pixel en el fichero. */
#define ORDEN_BGRA 0
#define ORDEN_RGBA 1

struct cabecera_panel {
    uint32_t magia;
    uint32_t version;
    uint32_t ancho;
    uint32_t alto;
    int32_t  x;                 /* negativo = contado desde el borde opuesto */
    int32_t  y;
    uint32_t visible;
    uint32_t generacion;        /* sube cuando cambian LOS PIXELES */
    uint32_t orden;             /* ORDEN_BGRA / ORDEN_RGBA */
    /* SUBE EN CADA VUELTA DEL MENU, cambien los pixeles o no. Son dos cosas
     * distintas y conviene no confundirlas:
     *
     *   - "generacion" dice si hay que volver a leer los pixeles. Con el menu
     *     abierto y quieto son los mismos medio millon de pixeles sesenta veces
     *     por segundo, y copiarlos para nada es trabajo tirado.
     *   - "latido" dice si el que escribe SIGUE VIVO. Hace falta porque la capa
     *     pinta mientras "visible" sea 1, y si el proceso del menu se muriera
     *     sin poder poner el cero, el panel se quedaria pegado en la pantalla
     *     del juego para el resto de la partida. Con el latido, la capa deja de
     *     pintar sola a los pocos segundos. */
    uint32_t latido;
    uint32_t reservado[6];
};

/* La cabecera tiene que medir EXACTAMENTE lo que dice PANEL_CABEZA: quien
 * escribe el fichero es Python, al otro lado, y si los dos no miden lo mismo
 * los pixeles salen desplazados y el fallo no apunta a ningun sitio. Que lo
 * compruebe el compilador y no el usuario. */
typedef char comprueba_cabecera_panel
    [(sizeof(struct cabecera_panel) == PANEL_CABEZA) ? 1 : -1];

static int        g_panel_fd = -1;
static void      *g_panel_map = NULL;
static size_t     g_panel_bytes = 0;
static int        g_panel_sin_suerte = 0;    /* ya se intento y no hay */
static uint32_t   g_panel_latido = 0;        /* el ultimo latido que vimos */
static unsigned long g_panel_latido_cuando = 0;  /* y en que fotograma */
static unsigned long g_panel_reintento = 0;  /* fotograma del proximo intento */

static void panel_cerrar(void)
{
    if (g_panel_map) {
        munmap(g_panel_map, g_panel_bytes);
        g_panel_map = NULL;
        g_panel_bytes = 0;
    }
    if (g_panel_fd >= 0) {
        close(g_panel_fd);
        g_panel_fd = -1;
    }
}

/* Abre o reabre el fichero del panel. Devuelve 1 si quedo mapeado. */
static int panel_abrir(void)
{
    const char *ruta = getenv("WPROTON_CAPA_PANEL");
    off_t tam;

    if (!ruta || !*ruta)
        return 0;
    panel_cerrar();
    g_panel_fd = open(ruta, O_RDONLY);
    if (g_panel_fd < 0)
        return 0;
    /* EL TAMANO CON lseek Y NO CON fstat, Y NO ES CAPRICHO.
     *
     * Las dos valen igual, pero fstat obliga a la capa a pedir GLIBC_2.33 -en
     * glibc 2.33 cambio de nombre por dentro-, y eso significa que un .so
     * compilado aqui no carga en un sistema con glibc anterior. La capa es
     * portable: viaja compilada de una maquina a otra, y pedir una glibc del
     * 2021 por una llamada que se puede hacer de otra forma seria dejar fuera
     * equipos por nada. Con lseek, lo mas nuevo que pide son 2.17, de 2012. */
    tam = lseek(g_panel_fd, 0, SEEK_END);
    if (tam < (off_t)PANEL_CABEZA) {
        panel_cerrar();
        return 0;
    }
    g_panel_bytes = (size_t)tam;
    g_panel_map = mmap(NULL, g_panel_bytes, PROT_READ, MAP_SHARED, g_panel_fd, 0);
    if (g_panel_map == MAP_FAILED) {
        g_panel_map = NULL;
        panel_cerrar();
        return 0;
    }
    capa_log("[wproton-capa] panel conectado: %s (%zu bytes)\n", ruta, g_panel_bytes);
    return 1;
}

/* EL LATIDO. Un fichero de tres numeros al lado del panel, que la capa reescribe
 * una vez por segundo mientras esta pintando de verdad.
 *
 * Hace falta por una razon muy concreta: el menu de WProton tiene que decidir,
 * ANTES de abrirse, si se dibuja dentro del juego -por aqui- o en su ventana de
 * siempre. Y no puede suponerlo: si el juego no usa Vulkan, o es de 32 bits y
 * falta la capa de 32, aqui no entra nadie y el menu tiene que salir por la via
 * de siempre. Con el latido la decision es un stat(): si el fichero es de hace
 * menos de unos segundos, la capa esta viva y ademas dice de que tamano es la
 * pantalla del juego, que es lo que hace falta para colocar el panel.
 */
static unsigned long g_vivo_cuando = 0;

static double capa_segundos(void);

/* Cuantos fotogramas ha presentado el juego desde que entro la capa. Se declara
 * aqui, y no abajo con las tablas, porque el latido ya lo necesita. */
static unsigned long g_fotogramas = 0;

static void vivo_tocar(uint32_t ancho, uint32_t alto)
{
    const char *ruta = getenv("WPROTON_CAPA_PANEL");
    char nombre[4096];
    FILE *f;

    if (!ruta || !*ruta)
        return;
    if (snprintf(nombre, sizeof(nombre), "%s.vivo", ruta) >= (int)sizeof(nombre))
        return;
    f = fopen(nombre, "w");
    if (!f)
        return;
    /* Y DE PASO, LOS FOTOGRAMAS Y EL RELOJ.
     *
     * Con esos dos numeros, el menu puede ensenar los FPS del juego restando
     * dos latidos. Y son los FPS DE VERDAD: los fotogramas que el juego ha
     * presentado, contados desde dentro. Un programa de fuera no puede saber
     * eso -por eso MangoHud tambien se mete dentro-, asi que es un dato que
     * solo tenemos porque ya estamos ahi. Cuesta dos numeros mas en una linea
     * que ya se escribia. */
    fprintf(f, "%u %u %lu %.3f\n", ancho, alto, g_fotogramas, capa_segundos());
    fclose(f);
}

/* Lo que la capa necesita saber de un fotograma de panel. */
struct vista_panel {
    const unsigned char *pixeles;
    uint32_t ancho, alto;
    int32_t  x, y;
    uint32_t orden;
    uint32_t generacion;        /* sube cuando cambian los pixeles */
    uint32_t latido;            /* sube en cada vuelta del menu */
};

/* EL PATRON DE PRUEBA. Se pide con WPROTON_CAPA_PRUEBA=1 y sirve para
 * comprobar el camino de pintado sin depender de que el menu este escribiendo.
 *
 * Cada cosa que lleva contesta a una pregunta distinta:
 *
 *   - el BORDE BLANCO dice que el rectangulo esta donde se pidio y mide lo que
 *     se pidio;
 *   - la DIAGONAL AZUL dice que las filas no estan desplazadas -si el ancho de
 *     fila estuviera mal, saldria torcida o escalonada-;
 *   - la LINEA ROJA QUE SE MUEVE dice que se pinta CADA fotograma: si se ve
 *     quieta, solo se pinto uno;
 *   - y que la linea sea roja y la diagonal azul, y no al reves, dice que el
 *     orden de los bytes del color es el correcto.
 *
 * Y va en RGBA a proposito, igual que el panel de verdad: asi recorre
 * EXACTAMENTE el mismo camino de conversion. Un patron en BGRA probaria un
 * camino que luego no se usa, que es la peor clase de prueba. */
#define PRUEBA_ANCHO 400u
#define PRUEBA_ALTO  300u
static unsigned char g_prueba[PRUEBA_ANCHO * PRUEBA_ALTO * 4];

static void prueba_dibujar(unsigned long fotograma)
{
    uint32_t x, y;
    uint32_t franja = (uint32_t)(fotograma % PRUEBA_ALTO);
    for (y = 0; y < PRUEBA_ALTO; y++) {
        for (x = 0; x < PRUEBA_ANCHO; x++) {
            unsigned char *p = &g_prueba[(y * PRUEBA_ANCHO + x) * 4];
            int borde = (x < 4 || y < 4 || x >= PRUEBA_ANCHO - 4 ||
                         y >= PRUEBA_ALTO - 4);
            int diagonal = (x * PRUEBA_ALTO / PRUEBA_ANCHO == y);
            /* R, G, B, A — en ese orden, que es ORDEN_RGBA. */
            if (borde)              { p[0] = 255; p[1] = 255; p[2] = 255; }
            else if (y == franja)   { p[0] = 255; p[1] = 0;   p[2] = 0;   }
            else if (diagonal)      { p[0] = 0;   p[1] = 0;   p[2] = 255; }
            else                    { p[0] = 20;  p[1] = 30;  p[2] = 60;  }
            p[3] = 255;
        }
    }
}

/* Que hay que pintar en este fotograma, si hay algo. */
static int panel_mirar(unsigned long fotograma, struct vista_panel *v)
{
    const struct cabecera_panel *c;
    size_t hacen_falta;

    if (!g_panel_map && !g_panel_sin_suerte) {
        if (fotograma >= g_panel_reintento) {
            if (!panel_abrir()) {
                /* Sin WPROTON_CAPA_PANEL no hay nada que esperar: se deja de
                 * mirar. Con ruta pero sin fichero todavia, se reintenta cada
                 * dos segundos: el menu puede crearlo despues. */
                const char *ruta = getenv("WPROTON_CAPA_PANEL");
                if (!ruta || !*ruta)
                    g_panel_sin_suerte = 1;
                else
                    g_panel_reintento = fotograma + 120;
            }
        }
    }

    if (g_panel_map) {
        c = (const struct cabecera_panel *)g_panel_map;
        if (c->magia == PANEL_MAGIA && c->version == PANEL_VERSION &&
            c->visible && c->ancho && c->alto) {
            hacen_falta = PANEL_CABEZA + (size_t)c->ancho * c->alto * 4;
            if (hacen_falta > g_panel_bytes) {
                /* El panel crecio y el mapeo se quedo corto: se reabre. Este
                 * fotograma se pierde, el siguiente ya va. */
                panel_abrir();
                return 0;
            }
            v->pixeles = (const unsigned char *)g_panel_map + PANEL_CABEZA;
            v->ancho = c->ancho;
            v->alto = c->alto;
            v->x = c->x;
            v->y = c->y;
            v->orden = (c->orden == ORDEN_RGBA) ? ORDEN_RGBA : ORDEN_BGRA;
            v->generacion = c->generacion;
            v->latido = c->latido;
            /* EL VIGILANTE DEL LATIDO. Si el que escribe el panel se quedo
             * parado -o se murio sin poder apagar el "visible"-, se deja de
             * pintar. Trescientos fotogramas son unos cinco segundos a 60 FPS,
             * y el menu late unas treinta veces por segundo: para que esto
             * salte tiene que haberse callado de verdad. */
            if (g_panel_latido != c->latido) {
                g_panel_latido = c->latido;
                g_panel_latido_cuando = fotograma;
            } else if (fotograma - g_panel_latido_cuando > 300) {
                static int avisado = 0;
                if (!avisado) {
                    avisado = 1;
                    capa_log("[wproton-capa] el menu dejo de latir con el panel "
                             "encendido; se deja de pintar\n");
                }
                return 0;
            }
            return 1;
        }
        return 0;
    }

    /* Sin panel: el patron de prueba, solo si se pide. */
    {
        static int quiere = -1;
        if (quiere < 0) {
            const char *s = getenv("WPROTON_CAPA_PRUEBA");
            quiere = (s && *s && strcmp(s, "0")) ? 1 : 0;
            if (quiere)
                capa_log("[wproton-capa] WPROTON_CAPA_PRUEBA: se pintara un "
                         "patron de %ux%u (borde blanco, diagonal AZUL, linea "
                         "ROJA en movimiento)\n", PRUEBA_ANCHO, PRUEBA_ALTO);
        }
        if (!quiere)
            return 0;
        prueba_dibujar(fotograma);
        v->pixeles = g_prueba;
        v->ancho = PRUEBA_ANCHO;
        v->alto = PRUEBA_ALTO;
        v->x = 40;
        v->y = 40;
        v->orden = ORDEN_RGBA;                  /* igual que el panel de verdad */
        v->generacion = (uint32_t)fotograma;    /* se mueve a proposito */
        v->latido = (uint32_t)fotograma;
        return 1;
    }
}

/* ---------------------------------------------------------------------------
 * LAS TABLAS
 *
 * Minusculas y de tamano fijo: un juego tiene un dispositivo, o dos, y un
 * swapchain, o dos si rehace la ventana. Una tabla fija no puede fallar al
 * reservar memoria en mitad de un fotograma, que es exactamente el momento en
 * el que no se puede fallar.
 * ------------------------------------------------------------------------ */
#define MAX_DISPOSITIVOS 8
#define MAX_INSTANCIAS   4
#define MAX_SWAPCHAINS   8
#define MAX_IMAGENES    16          /* 3 es lo normal (triple buffer) */
#define MAX_COLAS       16
#define MAX_ESPERAS     32          /* semaforos que puede esperar un present */

/* Lo maximo que se espera una valla nuestra, en nanosegundos. Tres segundos:
 * un equipo compilando shaders a la vez puede tardar bastante mas de lo normal
 * en despachar una cola, y cortar a un segundo convertiria un tiron en "deja de
 * pintar para siempre". Si una copia de dos megas tarda mas de tres segundos,
 * ahi ya no hay menu que salvar. */
#define ESPERA_MAX 3000000000ull

/* UNA RANURA POR IMAGEN DEL SWAPCHAIN.
 *
 * Y no un solo juego de objetos por dispositivo, que es lo primero que uno
 * escribe. La razon es fina pero importante: una valla dice que nuestro ENVIO
 * termino, NO que el motor de presentacion haya esperado ya nuestro semaforo.
 * Reusar un semaforo binario cuya espera anterior puede estar pendiente es
 * justo el fallo que produce los avisos de "semaphore already in use" y, en un
 * driver menos amable, imagen rota.
 *
 * Con una ranura por indice de imagen eso no puede pasar: el juego no puede
 * volver a presentar esa imagen sin haberla pedido otra vez, y pedirla implica
 * que la presentacion anterior acabo. Es lo que hace MangoHud, por lo mismo. */
struct ranura {
    VkCommandBuffer cmd;
    VkSemaphore sem;
    VkFence valla;
    int enviado;                     /* 1 = hay un envio por el que esperar */
};

/* Lo que hace falta para copiar, por dispositivo. Se crea la primera vez que
 * hay algo que pintar y no antes: un juego que nunca abre el menu no paga
 * nada. */
struct pintura {
    int lista;                       /* 1 = creado y utilizable */
    int rota;                        /* 1 = fallo algo; no se vuelve a probar */
    VkCommandPool pool;
    struct ranura ranuras[MAX_IMAGENES];
    uint32_t n_ranuras;
    /* EL BUFFER SI ES UNO SOLO, y se puede: solo se reescribe cuando el panel
     * cambia de verdad -o sea, cuando el usuario mueve el mando-, y antes de
     * reescribirlo se espera a todas las ranuras en vuelo. Mientras el menu
     * esta quieto, los envios de varias imagenes leen los mismos bytes y no
     * hay nada que sincronizar. */
    VkBuffer buffer;
    VkDeviceMemory memoria;
    unsigned char *pixeles;          /* el buffer, mapeado */
    VkDeviceSize bytes;
    uint32_t familia;                /* la familia de colas con la que se creo */
    uint32_t gen_vista;              /* la generacion que ya esta en el buffer */
    uint32_t orden_vista;            /* y en que orden de bytes se copio */
    int lleno;                       /* 1 = el buffer ya tiene algo valido */
};

struct entrada_inst {
    void *clave;
    VkInstance inst;
    PFN_vkGetInstanceProcAddr gipa;
    PFN_vkGetPhysicalDeviceMemoryProperties mem_props;
    PFN_vkGetPhysicalDeviceSurfaceCapabilitiesKHR caps_sup;
};

struct entrada_dev {
    void *clave;                        /* la "dispatch key" del dispositivo */
    VkDevice dev;
    VkPhysicalDevice fisico;
    PFN_vkQueuePresentKHR present;      /* el siguiente de la cadena */
    PFN_vkGetDeviceProcAddr gdpa;
    /* Todo lo que se llama al pintar se pide UNA vez aqui y se guarda: pedirlo
     * por su nombre en cada fotograma seria tonto, y ademas hace el codigo de
     * pintar ilegible. */
    PFN_vkDeviceWaitIdle esperar_todo;
    PFN_vkGetDeviceQueue cola_de;
    PFN_vkGetDeviceQueue2 cola_de2;
    PFN_vkCreateCommandPool crear_pool;
    PFN_vkDestroyCommandPool destruir_pool;
    PFN_vkAllocateCommandBuffers reservar_cmd;
    PFN_vkBeginCommandBuffer empezar_cmd;
    PFN_vkEndCommandBuffer terminar_cmd;
    PFN_vkResetCommandBuffer reiniciar_cmd;
    PFN_vkCmdPipelineBarrier barrera;
    PFN_vkCmdCopyBufferToImage copiar;
    PFN_vkCreateBuffer crear_buffer;
    PFN_vkDestroyBuffer destruir_buffer;
    PFN_vkGetBufferMemoryRequirements requisitos;
    PFN_vkAllocateMemory reservar_mem;
    PFN_vkFreeMemory liberar_mem;
    PFN_vkBindBufferMemory atar_mem;
    PFN_vkMapMemory mapear;
    PFN_vkUnmapMemory desmapear;
    PFN_vkCreateSemaphore crear_sem;
    PFN_vkDestroySemaphore destruir_sem;
    PFN_vkCreateFence crear_valla;
    PFN_vkDestroyFence destruir_valla;
    PFN_vkWaitForFences esperar_valla;
    PFN_vkResetFences reiniciar_valla;
    PFN_vkQueueSubmit enviar;
    PFN_vkCreateSwapchainKHR crear_sc;
    PFN_vkDestroySwapchainKHR destruir_sc;
    PFN_vkGetSwapchainImagesKHR imagenes_sc;
    /* copiadas de la instancia, que es quien las despacha */
    PFN_vkGetPhysicalDeviceMemoryProperties mem_props;
    PFN_vkGetPhysicalDeviceSurfaceCapabilitiesKHR caps_sup;
    struct pintura pin;
};

struct swapchain_info {
    VkSwapchainKHR sc;
    void *clave_dev;                 /* a que dispositivo pertenece */
    uint32_t n_imagenes;
    VkImage imagenes[MAX_IMAGENES];
    VkExtent2D tam;
    uint32_t orden;                  /* ORDEN_BGRA / ORDEN_RGBA de su formato */
    int escribible;                  /* ¿se le pudo pedir TRANSFER_DST? */
};

/* Que cola pertenece a que familia. Hace falta porque el pool de ordenes se
 * crea para una familia concreta, y la cola de presentar la elige el juego. */
struct entrada_cola {
    VkQueue cola;
    void *clave_dev;
    uint32_t familia;
};

static struct entrada_inst g_insts[MAX_INSTANCIAS];
static struct entrada_dev  g_devs[MAX_DISPOSITIVOS];
static struct swapchain_info g_swaps[MAX_SWAPCHAINS];
static struct entrada_cola g_colas[MAX_COLAS];
static PFN_vkGetInstanceProcAddr g_gipa_siguiente = NULL;

/* La clave de despacho: el primer puntero de cualquier objeto de Vulkan es su
 * tabla de despacho, y el cargador garantiza que es la misma para un
 * dispositivo y para sus colas -y para una instancia y sus dispositivos
 * fisicos-. Asi, desde una VkQueue se llega al VkDevice que la creo sin tener
 * que apuntarlo aparte. Es lo que hacen todas las capas, MangoHud incluida. */
static void *clave_de(void *objeto)
{
    return *(void **)objeto;
}

static struct entrada_dev *dev_buscar(void *clave)
{
    int i;
    for (i = 0; i < MAX_DISPOSITIVOS; i++)
        if (g_devs[i].clave == clave)
            return &g_devs[i];
    return NULL;
}

static struct entrada_dev *dev_hueco(void)
{
    int i;
    for (i = 0; i < MAX_DISPOSITIVOS; i++)
        if (g_devs[i].clave == NULL)
            return &g_devs[i];
    return NULL;
}

static struct entrada_inst *inst_buscar(void *clave)
{
    int i;
    for (i = 0; i < MAX_INSTANCIAS; i++)
        if (g_insts[i].clave == clave)
            return &g_insts[i];
    return NULL;
}

static struct swapchain_info *swap_buscar(VkSwapchainKHR sc)
{
    int i;
    for (i = 0; i < MAX_SWAPCHAINS; i++)
        if (g_swaps[i].sc == sc)
            return &g_swaps[i];
    return NULL;
}

static void swap_olvidar(VkSwapchainKHR sc)
{
    struct swapchain_info *s = swap_buscar(sc);
    if (s)
        memset(s, 0, sizeof(*s));
}

static uint32_t cola_familia(VkQueue cola)
{
    int i;
    for (i = 0; i < MAX_COLAS; i++)
        if (g_colas[i].cola == cola)
            return g_colas[i].familia;
    return UINT32_MAX;
}

static void cola_apuntar(VkQueue cola, void *clave_dev, uint32_t familia)
{
    int i;
    for (i = 0; i < MAX_COLAS; i++)
        if (g_colas[i].cola == cola)
            return;
    for (i = 0; i < MAX_COLAS; i++)
        if (g_colas[i].cola == VK_NULL_HANDLE) {
            g_colas[i].cola = cola;
            g_colas[i].clave_dev = clave_dev;
            g_colas[i].familia = familia;
            return;
        }
}

/* El orden de bytes de un formato de swapchain. Importa porque
 * vkCmdCopyBufferToImage NO convierte nada: los bytes del buffer tienen que
 * estar ya en el formato de la imagen. Si el formato no es uno de estos
 * cuatro, no se pinta ahi (y se dice cual era). */
static int orden_de_formato(VkFormat f, uint32_t *orden)
{
    switch (f) {
    case VK_FORMAT_B8G8R8A8_UNORM:
    case VK_FORMAT_B8G8R8A8_SRGB:
        *orden = ORDEN_BGRA; return 1;
    case VK_FORMAT_R8G8B8A8_UNORM:
    case VK_FORMAT_R8G8B8A8_SRGB:
    /* A8B8G8R8 empaquetado en un uint32: en little-endian los bytes salen
     * R,G,B,A, igual que R8G8B8A8. */
    case VK_FORMAT_A8B8G8R8_UNORM_PACK32:
    case VK_FORMAT_A8B8G8R8_SRGB_PACK32:
        *orden = ORDEN_RGBA; return 1;
    default:
        return 0;
    }
}

/* ===========================================================================
 * PINTAR
 * ======================================================================== */

/* Espera a que acabe todo lo que tengamos en vuelo. Hace falta antes de
 * reescribir el buffer y antes de destruir cualquier cosa. */
static void pintura_esperar_todo(struct entrada_dev *d)
{
    struct pintura *p = &d->pin;
    uint32_t i;
    for (i = 0; i < p->n_ranuras; i++) {
        struct ranura *r = &p->ranuras[i];
        if (!r->enviado || !r->valla || !d->esperar_valla)
            continue;
        d->esperar_valla(d->dev, 1, &r->valla, VK_TRUE, ESPERA_MAX);
        if (d->reiniciar_valla)
            d->reiniciar_valla(d->dev, 1, &r->valla);
        r->enviado = 0;
    }
}

static void pintura_soltar(struct entrada_dev *d)
{
    struct pintura *p = &d->pin;
    uint32_t i;
    for (i = 0; i < MAX_IMAGENES; i++) {
        struct ranura *r = &p->ranuras[i];
        if (r->valla && d->destruir_valla) d->destruir_valla(d->dev, r->valla, NULL);
        if (r->sem   && d->destruir_sem)   d->destruir_sem(d->dev, r->sem, NULL);
        memset(r, 0, sizeof(*r));
    }
    p->n_ranuras = 0;
    if (p->pixeles && d->desmapear) { d->desmapear(d->dev, p->memoria); p->pixeles = NULL; }
    if (p->buffer  && d->destruir_buffer) { d->destruir_buffer(d->dev, p->buffer, NULL); p->buffer = VK_NULL_HANDLE; }
    if (p->memoria && d->liberar_mem)     { d->liberar_mem(d->dev, p->memoria, NULL);    p->memoria = VK_NULL_HANDLE; }
    /* El deposito se destruye al final: destruirlo libera de golpe todos los
     * bloques de ordenes que salieron de el, asi que no hay que soltarlos uno
     * a uno -y hacerlo despues seria usar memoria ya liberada-. */
    if (p->pool && d->destruir_pool) { d->destruir_pool(d->dev, p->pool, NULL); p->pool = VK_NULL_HANDLE; }
    p->lista = 0;
    p->bytes = 0;
    p->lleno = 0;
}

static void pintura_romper(struct entrada_dev *d, const char *por_que)
{
    capa_log("[wproton-capa] no se puede pintar en este dispositivo (%s); "
             "el juego sigue igual, sin menu dentro\n", por_que);
    d->pin.rota = 1;
}

/* Un tipo de memoria que se pueda escribir desde la CPU y que no haga falta
 * vaciar a mano (coherente). Es lo que quiere un buffer de subida. */
static int memoria_para_subir(struct entrada_dev *d, uint32_t permitidos,
                              uint32_t *tipo)
{
    VkPhysicalDeviceMemoryProperties props;
    uint32_t i;
    const VkMemoryPropertyFlags quiero = VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT |
                                         VK_MEMORY_PROPERTY_HOST_COHERENT_BIT;
    if (!d->mem_props)
        return 0;
    memset(&props, 0, sizeof(props));
    d->mem_props(d->fisico, &props);
    for (i = 0; i < props.memoryTypeCount; i++) {
        if (!(permitidos & (1u << i)))
            continue;
        if ((props.memoryTypes[i].propertyFlags & quiero) == quiero) {
            *tipo = i;
            return 1;
        }
    }
    return 0;
}

/* Crea (o recrea, si el panel crecio) todo lo que hace falta para copiar.
 * Devuelve 1 si quedo listo. */
static int pintura_asegurar(struct entrada_dev *d, uint32_t familia,
                            VkDeviceSize bytes, uint32_t n_imagenes)
{
    struct pintura *p = &d->pin;
    VkCommandPoolCreateInfo ipool;
    VkCommandBufferAllocateInfo icmd;
    VkSemaphoreCreateInfo isem;
    VkFenceCreateInfo ivalla;
    VkBufferCreateInfo ibuf;
    VkMemoryRequirements req;
    VkMemoryAllocateInfo imem;
    uint32_t tipo = 0, i;
    void *mapeado = NULL;

    if (p->rota)
        return 0;
    if (n_imagenes > MAX_IMAGENES)
        n_imagenes = MAX_IMAGENES;
    if (p->lista && p->familia == familia && p->bytes >= bytes &&
        p->n_ranuras >= n_imagenes)
        return 1;
    /* Algo cambio (primera vez, otra cola, o el panel crecio): se rehace. Si
     * habia envios en vuelo, hay que esperarlos antes de destruir nada. */
    if (p->lista) {
        pintura_esperar_todo(d);
        if (d->esperar_todo)
            d->esperar_todo(d->dev);
        pintura_soltar(d);
    }

    if (!d->crear_pool || !d->reservar_cmd || !d->crear_sem || !d->crear_valla ||
        !d->crear_buffer || !d->requisitos || !d->reservar_mem || !d->atar_mem ||
        !d->mapear || !d->enviar || !d->barrera || !d->copiar) {
        pintura_romper(d, "el driver no dio alguna de las funciones de copia");
        return 0;
    }

    memset(&ipool, 0, sizeof(ipool));
    ipool.sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO;
    ipool.flags = VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT;
    ipool.queueFamilyIndex = familia;
    if (d->crear_pool(d->dev, &ipool, NULL, &p->pool) != VK_SUCCESS) {
        pintura_romper(d, "no se pudo crear el deposito de ordenes");
        return 0;
    }

    memset(&isem, 0, sizeof(isem));
    isem.sType = VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO;
    memset(&ivalla, 0, sizeof(ivalla));
    ivalla.sType = VK_STRUCTURE_TYPE_FENCE_CREATE_INFO;
    memset(&icmd, 0, sizeof(icmd));
    icmd.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO;
    icmd.commandPool = p->pool;
    icmd.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY;
    icmd.commandBufferCount = 1;
    for (i = 0; i < n_imagenes; i++) {
        struct ranura *r = &p->ranuras[i];
        if (d->reservar_cmd(d->dev, &icmd, &r->cmd) != VK_SUCCESS) {
            pintura_soltar(d);
            pintura_romper(d, "no se pudo reservar el bloque de ordenes");
            return 0;
        }
        if (d->crear_sem(d->dev, &isem, NULL, &r->sem) != VK_SUCCESS) {
            pintura_soltar(d);
            pintura_romper(d, "no se pudo crear el semaforo");
            return 0;
        }
        if (d->crear_valla(d->dev, &ivalla, NULL, &r->valla) != VK_SUCCESS) {
            pintura_soltar(d);
            pintura_romper(d, "no se pudo crear la valla");
            return 0;
        }
        p->n_ranuras = i + 1;
    }

    memset(&ibuf, 0, sizeof(ibuf));
    ibuf.sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO;
    ibuf.size = bytes;
    ibuf.usage = VK_BUFFER_USAGE_TRANSFER_SRC_BIT;
    ibuf.sharingMode = VK_SHARING_MODE_EXCLUSIVE;
    if (d->crear_buffer(d->dev, &ibuf, NULL, &p->buffer) != VK_SUCCESS) {
        pintura_soltar(d);
        pintura_romper(d, "no se pudo crear el buffer de subida");
        return 0;
    }

    memset(&req, 0, sizeof(req));
    d->requisitos(d->dev, p->buffer, &req);
    if (!memoria_para_subir(d, req.memoryTypeBits, &tipo)) {
        pintura_soltar(d);
        pintura_romper(d, "no hay memoria visible desde la CPU para el buffer");
        return 0;
    }
    memset(&imem, 0, sizeof(imem));
    imem.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
    imem.allocationSize = req.size;
    imem.memoryTypeIndex = tipo;
    if (d->reservar_mem(d->dev, &imem, NULL, &p->memoria) != VK_SUCCESS) {
        pintura_soltar(d);
        pintura_romper(d, "no se pudo reservar la memoria del buffer");
        return 0;
    }
    if (d->atar_mem(d->dev, p->buffer, p->memoria, 0) != VK_SUCCESS) {
        pintura_soltar(d);
        pintura_romper(d, "no se pudo atar la memoria al buffer");
        return 0;
    }
    if (d->mapear(d->dev, p->memoria, 0, VK_WHOLE_SIZE, 0, &mapeado) != VK_SUCCESS) {
        pintura_soltar(d);
        pintura_romper(d, "no se pudo mapear la memoria del buffer");
        return 0;
    }

    p->pixeles = (unsigned char *)mapeado;
    p->bytes = bytes;
    p->familia = familia;
    p->lista = 1;
    capa_log("[wproton-capa] listo para pintar: familia de colas %u, "
             "buffer de %llu bytes, %u ranura(s)\n", familia,
             (unsigned long long)bytes, p->n_ranuras);
    return 1;
}

/* Copia los pixeles del panel al buffer de subida, cambiando el orden de los
 * bytes si el formato del swapchain no es el que trae el panel. */
static void rellenar_buffer(struct pintura *p, const struct vista_panel *v,
                            uint32_t orden_destino)
{
    size_t n = (size_t)v->ancho * v->alto;
    if (v->orden == orden_destino) {
        memcpy(p->pixeles, v->pixeles, n * 4);
        return;
    }
    /* El unico cambio posible entre los formatos que admitimos es intercambiar
     * el primer y el tercer byte (R y B). */
    {
        const unsigned char *s = v->pixeles;
        unsigned char *t = p->pixeles;
        size_t i;
        for (i = 0; i < n; i++, s += 4, t += 4) {
            t[0] = s[2];
            t[1] = s[1];
            t[2] = s[0];
            t[3] = s[3];
        }
    }
}

/* Mete en el bloque de ordenes las dos barreras y la copia para UNA imagen. */
static void mandar_copia(struct entrada_dev *d, VkCommandBuffer cmd,
                         VkImage imagen, const struct vista_panel *v,
                         int32_t x, int32_t y, uint32_t ancho, uint32_t alto)
{
    VkImageMemoryBarrier b;
    VkBufferImageCopy region;

    memset(&b, 0, sizeof(b));
    b.sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER;
    b.srcAccessMask = VK_ACCESS_MEMORY_READ_BIT;
    b.dstAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT;
    /* PRESENT_SRC y no UNDEFINED: es lo que CONSERVA el fotograma que el juego
     * acaba de dibujar. Con UNDEFINED el driver puede tirarlo entero y lo que
     * se veria es el panel sobre basura. */
    b.oldLayout = VK_IMAGE_LAYOUT_PRESENT_SRC_KHR;
    b.newLayout = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
    b.srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
    b.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
    b.image = imagen;
    b.subresourceRange.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
    b.subresourceRange.levelCount = 1;
    b.subresourceRange.layerCount = 1;
    d->barrera(cmd, VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT,
               VK_PIPELINE_STAGE_TRANSFER_BIT, 0, 0, NULL, 0, NULL, 1, &b);

    memset(&region, 0, sizeof(region));
    region.bufferOffset = 0;
    /* El buffer tiene las filas del panel COMPLETO; si el panel se sale de la
     * pantalla se copia menos ancho, pero las filas siguen midiendo lo mismo.
     * Para eso esta bufferRowLength. */
    region.bufferRowLength = v->ancho;
    region.bufferImageHeight = v->alto;
    region.imageSubresource.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
    region.imageSubresource.layerCount = 1;
    region.imageOffset.x = x;
    region.imageOffset.y = y;
    region.imageExtent.width = ancho;
    region.imageExtent.height = alto;
    region.imageExtent.depth = 1;
    d->copiar(cmd, d->pin.buffer, imagen,
              VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &region);

    b.srcAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT;
    b.dstAccessMask = VK_ACCESS_MEMORY_READ_BIT;
    b.oldLayout = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
    b.newLayout = VK_IMAGE_LAYOUT_PRESENT_SRC_KHR;
    d->barrera(cmd, VK_PIPELINE_STAGE_TRANSFER_BIT,
               VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT |
               VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT,
               0, 0, NULL, 0, NULL, 1, &b);
}

/* Pinta el panel sobre los swapchains de este present.
 *
 * EL MODELO ES EL DE vkBasalt, que es el que funciona cuando hay mas de un
 * swapchain en un present: un envio por swapchain, pero SOLO EL PRIMERO espera
 * los semaforos del juego -un semaforo binario se espera una vez y nada mas-, y
 * el present acaba esperando a todos los nuestros. Lo que NO se hace es partir
 * el present en varios: eso obliga a recortar todas las estructuras colgadas
 * del pNext (regiones, identificadores, vallas de presentacion...) y una capa
 * que no conozca una de ellas la estropea en silencio. Mesa tiene ese fallo
 * ahora mismo; gamescope necesita trescientas lineas para hacerlo bien.
 *
 * Devuelve cuantos semaforos nuestros tiene que esperar el present, 0 si no se
 * pinto nada. */
static uint32_t pintar_fotograma(struct entrada_dev *d, VkQueue cola,
                                 const VkPresentInfoKHR *info,
                                 VkSemaphore *sems, uint32_t tope_sems)
{
    struct vista_panel v;
    struct pintura *p = &d->pin;
    VkCommandBufferBeginInfo ini;
    VkSubmitInfo envio;
    VkPipelineStageFlags etapas[MAX_ESPERAS];
    uint32_t familia, i, n_sems = 0, n_imagenes = 0;
    uint32_t orden_destino = ORDEN_BGRA;
    int primero = 1;
    VkDeviceSize hacen_falta;

    if (p->rota)
        return 0;
    if (!panel_mirar(g_fotogramas, &v))
        return 0;
    /* Mas semaforos de los que caben en el array fijo: se deja de pintar ESTE
     * fotograma y nada mas. No se rompe la capa por algo que el fotograma
     * siguiente puede no traer, y no se reserva memoria en el camino del
     * present, que es donde no se puede reservar memoria. */
    if (info->waitSemaphoreCount > MAX_ESPERAS) {
        static int avisado = 0;
        if (!avisado) {
            avisado = 1;
            capa_log("[wproton-capa] AVISO: el juego espera %u semaforos al "
                     "presentar y solo se manejan %u; no se pinta\n",
                     info->waitSemaphoreCount, (unsigned)MAX_ESPERAS);
        }
        return 0;
    }

    familia = cola_familia(cola);
    if (familia == UINT32_MAX) {
        /* No vimos como pidio esta cola, asi que no se sabe para que familia
         * crear el deposito de ordenes. Se dice UNA vez y no se pinta, pero NO
         * se rompe la capa: el juego puede presentar mas adelante en otra cola
         * que si hayamos visto, y romperla aqui dejaria eso sin menu por un
         * primer fotograma raro. */
        static int avisado = 0;
        if (!avisado) {
            avisado = 1;
            capa_log("[wproton-capa] AVISO: se presenta en una cola que no "
                     "vimos pedir; en ella no se pinta\n");
        }
        return 0;
    }

    /* Cuantas ranuras hacen falta: la imagen de mas indice que vayamos a tocar.
     * Y de paso se decide el orden de bytes del relleno. */
    for (i = 0; i < info->swapchainCount; i++) {
        struct swapchain_info *s = swap_buscar(info->pSwapchains[i]);
        if (!s || !s->escribible || s->clave_dev != d->clave)
            continue;
        if (primero) {
            orden_destino = s->orden;
            primero = 0;
        }
        if (s->n_imagenes > n_imagenes)
            n_imagenes = s->n_imagenes;
    }
    if (primero)
        return 0;               /* ningun swapchain nuestro en este present */

    hacen_falta = (VkDeviceSize)v.ancho * v.alto * 4;
    if (!pintura_asegurar(d, familia, hacen_falta, n_imagenes))
        return 0;

    /* EL BUFFER SOLO SE RELLENA CUANDO EL PANEL HA CAMBIADO DE VERDAD.
     *
     * Mientras el menu esta abierto y quieto son los mismos pixeles sesenta
     * veces por segundo, y cambiar el orden de los bytes de medio millon de
     * pixeles para nada es justo el trabajo que no se hace. Y cuando SI hay que
     * reescribirlo, primero se espera a todo lo que este en vuelo: hay un solo
     * buffer y varios envios pueden estar leyendolo. */
    if (!p->lleno || p->gen_vista != v.generacion ||
        p->orden_vista != orden_destino) {
        pintura_esperar_todo(d);
        rellenar_buffer(p, &v, orden_destino);
        p->gen_vista = v.generacion;
        p->orden_vista = orden_destino;
        p->lleno = 1;
    }

    for (i = 0; i < info->waitSemaphoreCount; i++)
        etapas[i] = VK_PIPELINE_STAGE_TRANSFER_BIT;

    for (i = 0; i < info->swapchainCount && n_sems < tope_sems; i++) {
        struct swapchain_info *s = swap_buscar(info->pSwapchains[i]);
        struct ranura *r;
        uint32_t idx, ancho, alto;
        int32_t x, y;

        if (!s || !s->escribible || s->clave_dev != d->clave)
            continue;
        if (s->orden != orden_destino)
            continue;           /* dos formatos distintos en un present: raro */
        idx = info->pImageIndices[i];
        if (idx >= s->n_imagenes || !s->imagenes[idx] || idx >= p->n_ranuras)
            continue;

        /* Donde va. Negativo = desde el borde opuesto, que es como se pide un
         * panel pegado a la derecha o abajo sin saber la resolucion. */
        x = (v.x < 0) ? (int32_t)s->tam.width  + v.x - (int32_t)v.ancho : v.x;
        y = (v.y < 0) ? (int32_t)s->tam.height + v.y - (int32_t)v.alto  : v.y;
        if (x < 0) x = 0;
        if (y < 0) y = 0;
        if ((uint32_t)x >= s->tam.width || (uint32_t)y >= s->tam.height)
            continue;
        ancho = v.ancho;
        alto = v.alto;
        if ((uint32_t)x + ancho > s->tam.width)  ancho = s->tam.width  - (uint32_t)x;
        if ((uint32_t)y + alto  > s->tam.height) alto  = s->tam.height - (uint32_t)y;
        if (!ancho || !alto)
            continue;

        /* La ranura de ESTA imagen. Si tiene algo en vuelo hay que esperarlo
         * antes de reescribir su bloque de ordenes. En la practica no espera
         * nunca: el juego no puede volver a presentar esta imagen sin haberla
         * pedido otra vez. */
        r = &p->ranuras[idx];
        if (r->enviado) {
            if (d->esperar_valla(d->dev, 1, &r->valla, VK_TRUE, ESPERA_MAX)
                    != VK_SUCCESS) {
                pintura_romper(d, "la valla del envio anterior no llego a tiempo");
                return n_sems;
            }
            d->reiniciar_valla(d->dev, 1, &r->valla);
            r->enviado = 0;
        }

        if (d->reiniciar_cmd)
            d->reiniciar_cmd(r->cmd, 0);
        memset(&ini, 0, sizeof(ini));
        ini.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;
        ini.flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;
        if (d->empezar_cmd(r->cmd, &ini) != VK_SUCCESS) {
            pintura_romper(d, "no se pudo empezar el bloque de ordenes");
            return n_sems;
        }
        mandar_copia(d, r->cmd, s->imagenes[idx], &v, x, y, ancho, alto);
        if (d->terminar_cmd(r->cmd) != VK_SUCCESS) {
            pintura_romper(d, "no se pudo cerrar el bloque de ordenes");
            return n_sems;
        }

        memset(&envio, 0, sizeof(envio));
        envio.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO;
        /* SOLO EL PRIMERO espera los semaforos del juego: un semaforo binario
         * se espera UNA vez. Los demas envios van detras en la misma cola, y el
         * orden dentro de una cola ya los ordena. */
        if (n_sems == 0) {
            envio.waitSemaphoreCount = info->waitSemaphoreCount;
            envio.pWaitSemaphores = info->pWaitSemaphores;
            envio.pWaitDstStageMask = info->waitSemaphoreCount ? etapas : NULL;
        }
        envio.commandBufferCount = 1;
        envio.pCommandBuffers = &r->cmd;
        envio.signalSemaphoreCount = 1;
        envio.pSignalSemaphores = &r->sem;
        if (d->enviar(cola, 1, &envio, r->valla) != VK_SUCCESS) {
            pintura_romper(d, "el envio de la copia fue rechazado");
            return n_sems;
        }
        r->enviado = 1;
        sems[n_sems++] = r->sem;
    }
    return n_sems;
}

/* ---------------------------------------------------------------------------
 * PRESENTAR: el momento en el que el juego dice "este fotograma ya esta".
 *
 * Es el unico sitio donde se pinta, y la regla es siempre la misma: si algo no
 * sale, el present se hace TAL CUAL venia. Una capa que se cuela entre los
 * fotogramas de un juego tiene que poder quitarse de en medio sin dejar rastro.
 * ------------------------------------------------------------------------ */
static VKAPI_ATTR VkResult VKAPI_CALL
capa_QueuePresentKHR(VkQueue cola, const VkPresentInfoKHR *info)
{
    struct entrada_dev *d = dev_buscar(clave_de(cola));
    VkSemaphore sems[MAX_SWAPCHAINS];
    VkPresentInfoKHR mio;
    uint32_t n_sems;

    if (!d || !d->present) {
        /* No deberia pasar nunca: si pasa, es un fallo nuestro y hay que
         * saberlo, no tragarselo. Pero tampoco se puede dejar al juego sin
         * presentar, asi que se dice una vez y se sigue. */
        static int avisado = 0;
        if (!avisado) {
            avisado = 1;
            capa_log("[wproton-capa] AVISO: presentar sin dispositivo "
                     "conocido; la capa se aparta\n");
        }
        return VK_ERROR_INITIALIZATION_FAILED;
    }

    g_fotogramas++;
    /* Cada 600 fotogramas: a 60 FPS son diez segundos. Lo justo para saber que
     * seguimos vivos sin llenar el registro.
     *
     * Y CON EL RELOJ AL LADO, que es lo que separa los dos fallos que desde
     * fuera se parecen: si estas lineas siguen saliendo mientras la pantalla
     * esta congelada, el juego sigue presentando y el problema es del
     * compositor; si se paran, el que se ha quedado quieto es el juego. Sin la
     * hora, las dos cosas se ven igual en el registro. */
    if (g_fotogramas == 1 || (g_fotogramas % 600) == 0)
        capa_log("[wproton-capa] fotograma %lu presentado (%.1f s)\n",
                 g_fotogramas, capa_segundos());

    /* El latido, una vez por segundo. Solo si de verdad se puede pintar: decir
     * "estoy viva" cuando no se puede pintar dejaria al menu sin ventana Y sin
     * panel dentro, que es la peor de las tres opciones. */
    if (g_fotogramas >= g_vivo_cuando && info && info->swapchainCount) {
        struct swapchain_info *s = swap_buscar(info->pSwapchains[0]);
        if (s && s->escribible) {
            vivo_tocar(s->tam.width, s->tam.height);
            g_vivo_cuando = g_fotogramas + 60;
        }
    }

    if (info && info->swapchainCount) {
        n_sems = pintar_fotograma(d, cola, info, sems, MAX_SWAPCHAINS);
        if (n_sems) {
            /* Nuestros envios ya esperaron los semaforos del juego, asi que el
             * present pasa a esperar a los NUESTROS y solo a los nuestros.
             *
             * Y SE COPIA LA ESTRUCTURA EN PLANO, con su pNext tal cual: como
             * swapchainCount no cambia, todo lo que cuelga del pNext sigue
             * siendo valido. Es lo que hacen MangoHud y obs-vkcapture. Lo que
             * rompe las cosas es partir el present, y eso no se hace. */
            mio = *info;
            mio.waitSemaphoreCount = n_sems;
            mio.pWaitSemaphores = sems;
            return d->present(cola, &mio);
        }
    }

    return d->present(cola, info);
}

/* ---------------------------------------------------------------------------
 * EL SWAPCHAIN: hay que pedirle que admita ser destino de una copia, y hay que
 * apuntarse sus imagenes para saber a cual se pinta en cada present.
 * ------------------------------------------------------------------------ */
static VKAPI_ATTR VkResult VKAPI_CALL
capa_CreateSwapchainKHR(VkDevice dev, const VkSwapchainCreateInfoKHR *info,
                        const VkAllocationCallbacks *alloc,
                        VkSwapchainKHR *salida)
{
    struct entrada_dev *d = dev_buscar(clave_de(dev));
    VkSwapchainCreateInfoKHR mio;
    struct swapchain_info *s;
    VkSurfaceCapabilitiesKHR caps;
    uint32_t n = 0, orden = ORDEN_BGRA;
    int pedido = 0, formato_ok;
    VkResult r;

    if (!d || !d->crear_sc)
        return VK_ERROR_INITIALIZATION_FAILED;

    mio = *info;
    formato_ok = orden_de_formato(info->imageFormat, &orden);

    /* TRANSFER_DST solo si la superficie dice que puede. Pedirlo a lo bruto
     * hace que vkCreateSwapchainKHR falle y el juego se quede sin imagen: el
     * menu no vale ese precio. */
    if (formato_ok && d->caps_sup &&
        !(info->imageUsage & VK_IMAGE_USAGE_TRANSFER_DST_BIT)) {
        memset(&caps, 0, sizeof(caps));
        if (d->caps_sup(d->fisico, info->surface, &caps) == VK_SUCCESS &&
            (caps.supportedUsageFlags & VK_IMAGE_USAGE_TRANSFER_DST_BIT)) {
            mio.imageUsage |= VK_IMAGE_USAGE_TRANSFER_DST_BIT;
            pedido = 1;
        }
    } else if (formato_ok && (info->imageUsage & VK_IMAGE_USAGE_TRANSFER_DST_BIT)) {
        pedido = 1;     /* el juego ya lo pedia (DXVK suele pedirlo) */
    }

    r = d->crear_sc(dev, &mio, alloc, salida);
    if (r != VK_SUCCESS && pedido) {
        /* Dijo que podia y no pudo. Se reintenta sin tocar nada: antes se
         * queda el juego sin menu que sin pantalla. */
        capa_log("[wproton-capa] AVISO: el swapchain no acepto TRANSFER_DST; "
                 "se reintenta sin el\n");
        pedido = 0;
        r = d->crear_sc(dev, info, alloc, salida);
    }
    if (r != VK_SUCCESS)
        return r;

    /* UN "SI" SIN SWAPCHAIN. Parece imposible y no lo es: el cargador de Vulkan,
     * cuando el driver no tiene vkCreateSwapchainKHR, escribe un error en su
     * registro y devuelve VK_SUCCESS sin tocar la salida. Apuntar ese hueco
     * seria peor que no apuntar nada: la tabla usa el identificador vacio para
     * saber que una fila esta libre, asi que una fila "ocupada" con el
     * identificador vacio se pisaria con la siguiente de verdad. */
    if (*salida == VK_NULL_HANDLE) {
        capa_log("[wproton-capa] AVISO: crear el swapchain dijo que si pero no "
                 "dio ninguno; no se pintara dentro\n");
        return r;
    }

    if (info->oldSwapchain)
        swap_olvidar(info->oldSwapchain);

    s = swap_buscar(VK_NULL_HANDLE);
    if (!s) {
        capa_log("[wproton-capa] AVISO: demasiados swapchains; en este no se "
                 "pintara\n");
        return r;
    }
    memset(s, 0, sizeof(*s));
    s->sc = *salida;
    s->clave_dev = d->clave;
    s->tam = info->imageExtent;
    s->orden = orden;
    s->escribible = 0;

    if (pedido && d->imagenes_sc &&
        d->imagenes_sc(dev, *salida, &n, NULL) == VK_SUCCESS && n &&
        n <= MAX_IMAGENES &&
        d->imagenes_sc(dev, *salida, &n, s->imagenes) == VK_SUCCESS) {
        s->n_imagenes = n;
        s->escribible = 1;
    }

    if (s->escribible) {
        capa_log("[wproton-capa] swapchain %ux%u, %u imagenes: el menu se "
                 "puede pintar dentro\n", s->tam.width, s->tam.height, n);
        /* Se late YA, sin esperar el primer segundo de partida: si el menu se
         * invoca en los primeros fotogramas, tiene que encontrar el latido. */
        vivo_tocar(s->tam.width, s->tam.height);
        g_vivo_cuando = g_fotogramas + 60;
    } else if (!formato_ok) {
        capa_log("[wproton-capa] swapchain con formato %d, que esta capa no "
                 "sabe escribir; no se pintara dentro\n", (int)info->imageFormat);
    } else {
        capa_log("[wproton-capa] el swapchain no admite copias; no se pintara "
                 "dentro\n");
    }
    return r;
}

static VKAPI_ATTR void VKAPI_CALL
capa_DestroySwapchainKHR(VkDevice dev, VkSwapchainKHR sc,
                         const VkAllocationCallbacks *alloc)
{
    struct entrada_dev *d = dev_buscar(clave_de(dev));
    /* Primero se espera lo nuestro: un envio en vuelo tiene ordenes que
     * mencionan las imagenes de ESTE swapchain, y van a desaparecer. */
    if (d)
        pintura_esperar_todo(d);
    if (sc)
        swap_olvidar(sc);
    if (d && d->destruir_sc)
        d->destruir_sc(dev, sc, alloc);
}

/* ---------------------------------------------------------------------------
 * LAS COLAS: se apunta de que familia es cada una, porque el deposito de
 * ordenes se crea para una familia y la cola de presentar la elige el juego.
 * ------------------------------------------------------------------------ */
static VKAPI_ATTR void VKAPI_CALL
capa_GetDeviceQueue(VkDevice dev, uint32_t familia, uint32_t indice,
                    VkQueue *salida)
{
    struct entrada_dev *d = dev_buscar(clave_de(dev));
    if (!d || !d->cola_de) {
        if (salida) *salida = VK_NULL_HANDLE;
        return;
    }
    d->cola_de(dev, familia, indice, salida);
    if (salida && *salida)
        cola_apuntar(*salida, d->clave, familia);
}

static VKAPI_ATTR void VKAPI_CALL
capa_GetDeviceQueue2(VkDevice dev, const VkDeviceQueueInfo2 *info,
                     VkQueue *salida)
{
    struct entrada_dev *d = dev_buscar(clave_de(dev));
    if (!d || !d->cola_de2) {
        if (salida) *salida = VK_NULL_HANDLE;
        return;
    }
    d->cola_de2(dev, info, salida);
    if (salida && *salida && info)
        cola_apuntar(*salida, d->clave, info->queueFamilyIndex);
}

/* ---------------------------------------------------------------------------
 * CREAR EL DISPOSITIVO: aqui se recoge el eslabon siguiente de la cadena y se
 * piden, de una vez, todas las funciones con las que se pinta.
 * ------------------------------------------------------------------------ */
static VkLayerDeviceCreateInfo *enlace_device(const VkDeviceCreateInfo *info)
{
    VkLayerDeviceCreateInfo *l = (VkLayerDeviceCreateInfo *)info->pNext;
    while (l && !(l->sType == VK_STRUCTURE_TYPE_LOADER_DEVICE_CREATE_INFO &&
                  l->function == VK_LAYER_LINK_INFO))
        l = (VkLayerDeviceCreateInfo *)l->pNext;
    return l;
}

#define PIDE(campo, tipo, nombre) \
    d->campo = (tipo)gdpa(*salida, nombre)

static VKAPI_ATTR VkResult VKAPI_CALL
capa_CreateDevice(VkPhysicalDevice fisico, const VkDeviceCreateInfo *info,
                  const VkAllocationCallbacks *alloc, VkDevice *salida)
{
    VkLayerDeviceCreateInfo *enlace = enlace_device(info);
    PFN_vkGetInstanceProcAddr gipa;
    PFN_vkGetDeviceProcAddr gdpa;
    PFN_vkCreateDevice crear;
    struct entrada_inst *in;
    struct entrada_dev *d;
    VkResult r;

    if (!enlace || !enlace->u.pLayerInfo) {
        capa_log("[wproton-capa] AVISO: sin enlace de capa al crear el "
                 "dispositivo; la capa se aparta\n");
        return VK_ERROR_INITIALIZATION_FAILED;
    }
    gipa = enlace->u.pLayerInfo->pfnNextGetInstanceProcAddr;
    gdpa = enlace->u.pLayerInfo->pfnNextGetDeviceProcAddr;

    /* AVANZAR EL ESLABON ANTES DE LLAMAR, y esto no es opcional: si no se
     * avanza, la capa siguiente recibe NUESTRO enlace y la cadena se muerde la
     * cola. Es el fallo clasico al escribir una capa. */
    enlace->u.pLayerInfo = enlace->u.pLayerInfo->pNext;

    crear = (PFN_vkCreateDevice)gipa(NULL, "vkCreateDevice");
    if (!crear)
        return VK_ERROR_INITIALIZATION_FAILED;

    r = crear(fisico, info, alloc, salida);
    if (r != VK_SUCCESS)
        return r;

    d = dev_hueco();
    if (!d) {
        capa_log("[wproton-capa] AVISO: mas de %d dispositivos; en este no se "
                 "pintara\n", MAX_DISPOSITIVOS);
        return r;
    }
    memset(d, 0, sizeof(*d));
    d->clave = clave_de(*salida);
    d->dev = *salida;
    d->fisico = fisico;
    d->gdpa = gdpa;

    PIDE(present,        PFN_vkQueuePresentKHR,        "vkQueuePresentKHR");
    PIDE(esperar_todo,   PFN_vkDeviceWaitIdle,         "vkDeviceWaitIdle");
    PIDE(cola_de,        PFN_vkGetDeviceQueue,         "vkGetDeviceQueue");
    PIDE(cola_de2,       PFN_vkGetDeviceQueue2,        "vkGetDeviceQueue2");
    PIDE(crear_pool,     PFN_vkCreateCommandPool,      "vkCreateCommandPool");
    PIDE(destruir_pool,  PFN_vkDestroyCommandPool,     "vkDestroyCommandPool");
    PIDE(reservar_cmd,   PFN_vkAllocateCommandBuffers, "vkAllocateCommandBuffers");
    PIDE(empezar_cmd,    PFN_vkBeginCommandBuffer,     "vkBeginCommandBuffer");
    PIDE(terminar_cmd,   PFN_vkEndCommandBuffer,       "vkEndCommandBuffer");
    PIDE(reiniciar_cmd,  PFN_vkResetCommandBuffer,     "vkResetCommandBuffer");
    PIDE(barrera,        PFN_vkCmdPipelineBarrier,     "vkCmdPipelineBarrier");
    PIDE(copiar,         PFN_vkCmdCopyBufferToImage,   "vkCmdCopyBufferToImage");
    PIDE(crear_buffer,   PFN_vkCreateBuffer,           "vkCreateBuffer");
    PIDE(destruir_buffer,PFN_vkDestroyBuffer,          "vkDestroyBuffer");
    PIDE(requisitos,     PFN_vkGetBufferMemoryRequirements,
                                                       "vkGetBufferMemoryRequirements");
    PIDE(reservar_mem,   PFN_vkAllocateMemory,         "vkAllocateMemory");
    PIDE(liberar_mem,    PFN_vkFreeMemory,             "vkFreeMemory");
    PIDE(atar_mem,       PFN_vkBindBufferMemory,       "vkBindBufferMemory");
    PIDE(mapear,         PFN_vkMapMemory,              "vkMapMemory");
    PIDE(desmapear,      PFN_vkUnmapMemory,            "vkUnmapMemory");
    PIDE(crear_sem,      PFN_vkCreateSemaphore,        "vkCreateSemaphore");
    PIDE(destruir_sem,   PFN_vkDestroySemaphore,       "vkDestroySemaphore");
    PIDE(crear_valla,    PFN_vkCreateFence,            "vkCreateFence");
    PIDE(destruir_valla, PFN_vkDestroyFence,           "vkDestroyFence");
    PIDE(esperar_valla,  PFN_vkWaitForFences,          "vkWaitForFences");
    PIDE(reiniciar_valla,PFN_vkResetFences,            "vkResetFences");
    PIDE(enviar,         PFN_vkQueueSubmit,            "vkQueueSubmit");
    PIDE(crear_sc,       PFN_vkCreateSwapchainKHR,     "vkCreateSwapchainKHR");
    PIDE(destruir_sc,    PFN_vkDestroySwapchainKHR,    "vkDestroySwapchainKHR");
    PIDE(imagenes_sc,    PFN_vkGetSwapchainImagesKHR,  "vkGetSwapchainImagesKHR");

    /* Las dos del dispositivo FISICO las despacha la instancia, no el
     * dispositivo: se cogen de la entrada de la instancia, que comparte clave
     * de despacho con sus dispositivos fisicos. */
    in = inst_buscar(clave_de(fisico));
    if (in) {
        d->mem_props = in->mem_props;
        d->caps_sup = in->caps_sup;
    }
    if (!d->mem_props || !d->caps_sup)
        capa_log("[wproton-capa] AVISO: faltan funciones de la instancia; "
                 "no se podra pintar\n");

    capa_log("[wproton-capa] dispositivo listo\n");
    return r;
}

static VKAPI_ATTR void VKAPI_CALL
capa_DestroyDevice(VkDevice dev, const VkAllocationCallbacks *alloc)
{
    struct entrada_dev *d = dev_buscar(clave_de(dev));
    PFN_vkDestroyDevice destruir = NULL;
    int i;

    if (d) {
        destruir = (PFN_vkDestroyDevice)d->gdpa(dev, "vkDestroyDevice");
        /* Nada de destruir objetos con un envio en vuelo. */
        pintura_esperar_todo(d);
        if (d->esperar_todo)
            d->esperar_todo(dev);
        pintura_soltar(d);
        for (i = 0; i < MAX_SWAPCHAINS; i++)
            if (g_swaps[i].clave_dev == d->clave)
                memset(&g_swaps[i], 0, sizeof(g_swaps[i]));
        for (i = 0; i < MAX_COLAS; i++)
            if (g_colas[i].clave_dev == d->clave)
                memset(&g_colas[i], 0, sizeof(g_colas[i]));
        memset(d, 0, sizeof(*d));
    }
    if (destruir)
        destruir(dev, alloc);
}

/* ---------------------------------------------------------------------------
 * CREAR LA INSTANCIA: lo mismo, un eslabon mas arriba.
 * ------------------------------------------------------------------------ */
static VkLayerInstanceCreateInfo *enlace_instancia(const VkInstanceCreateInfo *info)
{
    VkLayerInstanceCreateInfo *l = (VkLayerInstanceCreateInfo *)info->pNext;
    while (l && !(l->sType == VK_STRUCTURE_TYPE_LOADER_INSTANCE_CREATE_INFO &&
                  l->function == VK_LAYER_LINK_INFO))
        l = (VkLayerInstanceCreateInfo *)l->pNext;
    return l;
}

static VKAPI_ATTR VkResult VKAPI_CALL
capa_CreateInstance(const VkInstanceCreateInfo *info,
                    const VkAllocationCallbacks *alloc, VkInstance *salida)
{
    VkLayerInstanceCreateInfo *enlace = enlace_instancia(info);
    PFN_vkGetInstanceProcAddr gipa;
    PFN_vkCreateInstance crear;
    VkResult r;
    int i;

    if (!enlace || !enlace->u.pLayerInfo)
        return VK_ERROR_INITIALIZATION_FAILED;
    gipa = enlace->u.pLayerInfo->pfnNextGetInstanceProcAddr;
    enlace->u.pLayerInfo = enlace->u.pLayerInfo->pNext;   /* avanzar */

    crear = (PFN_vkCreateInstance)gipa(NULL, "vkCreateInstance");
    if (!crear)
        return VK_ERROR_INITIALIZATION_FAILED;

    g_gipa_siguiente = gipa;
    r = crear(info, alloc, salida);
    if (r != VK_SUCCESS)
        return r;

    /* DONDE NOS HEMOS METIDO, apuntado una vez.
     *
     * Esto no es curiosidad. El fallo que estamos persiguiendo -la imagen del
     * juego congelada al abrir el menu, con el sonido siguiendo- depende de si
     * la sesion es Wayland o X11, de que compositor hay y de si gamescope esta
     * por medio. Con estas seis lineas en el registro, el siguiente que mire un
     * registro de un equipo ajeno no tiene que preguntar nada. */
    capa_entorno_apuntar();

    for (i = 0; i < MAX_INSTANCIAS; i++) {
        if (g_insts[i].clave)
            continue;
        g_insts[i].clave = clave_de(*salida);
        g_insts[i].inst = *salida;
        g_insts[i].gipa = gipa;
        g_insts[i].mem_props = (PFN_vkGetPhysicalDeviceMemoryProperties)
            gipa(*salida, "vkGetPhysicalDeviceMemoryProperties");
        g_insts[i].caps_sup = (PFN_vkGetPhysicalDeviceSurfaceCapabilitiesKHR)
            gipa(*salida, "vkGetPhysicalDeviceSurfaceCapabilitiesKHR");
        break;
    }

    capa_log("[wproton-capa] dentro del juego; el menu se pintara sobre el "
             "fotograma\n");
    return r;
}

/* ---------------------------------------------------------------------------
 * LAS DOS PUERTAS QUE EL CARGADOR BUSCA POR SU NOMBRE.
 * ------------------------------------------------------------------------ */
#define SI_ES(nombre, fn) \
    if (!strcmp(pName, nombre)) return (PFN_vkVoidFunction)(fn)

VK_LAYER_EXPORT VKAPI_ATTR PFN_vkVoidFunction VKAPI_CALL
wproton_GetInstanceProcAddr(VkInstance inst, const char *pName);

VK_LAYER_EXPORT VKAPI_ATTR PFN_vkVoidFunction VKAPI_CALL
wproton_GetDeviceProcAddr(VkDevice dev, const char *pName)
{
    struct entrada_dev *d = dev ? dev_buscar(clave_de(dev)) : NULL;

    SI_ES("vkGetDeviceProcAddr", wproton_GetDeviceProcAddr);
    SI_ES("vkDestroyDevice", capa_DestroyDevice);

    /* LAS DEMAS, SOLO SI EL DE DEBAJO LAS TIENE DE VERDAD.
     *
     * Y esto no es una precaucion de adorno. vkGetDeviceProcAddr es tambien la
     * forma en que un programa PREGUNTA si una funcion existe: si devolvemos un
     * puntero para vkGetDeviceQueue2 en un dispositivo de Vulkan 1.0, o para
     * vkCreateSwapchainKHR en uno que no activo la extension, el juego creera
     * que puede usarlas. Devolviendo nuestro enganche solo cuando el eslabon
     * siguiente tiene la funcion, un NULL sigue significando NULL. */
    if (d) {
        if (d->present && !strcmp(pName, "vkQueuePresentKHR"))
            return (PFN_vkVoidFunction)capa_QueuePresentKHR;
        if (d->crear_sc && !strcmp(pName, "vkCreateSwapchainKHR"))
            return (PFN_vkVoidFunction)capa_CreateSwapchainKHR;
        if (d->destruir_sc && !strcmp(pName, "vkDestroySwapchainKHR"))
            return (PFN_vkVoidFunction)capa_DestroySwapchainKHR;
        if (d->cola_de && !strcmp(pName, "vkGetDeviceQueue"))
            return (PFN_vkVoidFunction)capa_GetDeviceQueue;
        if (d->cola_de2 && !strcmp(pName, "vkGetDeviceQueue2"))
            return (PFN_vkVoidFunction)capa_GetDeviceQueue2;
    }

    if (!d || !d->gdpa)
        return NULL;
    return d->gdpa(dev, pName);
}

/* LA PUERTA MODERNA. Los cargadores de 2016 buscaban las dos funciones por su
 * nombre dentro del .so -que es lo que dice el "functions" del manifiesto-; los
 * de ahora preguntan por aqui y se quedan con los punteros que les damos. Se
 * mantienen las dos vias porque hay equipos de las dos epocas, y porque es lo
 * que hacen MangoHud y gamescope. */
VK_LAYER_EXPORT VKAPI_ATTR VkResult VKAPI_CALL
vkNegotiateLoaderLayerInterfaceVersion(VkNegotiateLayerInterface *pVersionStruct)
{
    if (!pVersionStruct ||
        pVersionStruct->sType != LAYER_NEGOTIATE_INTERFACE_STRUCT)
        return VK_ERROR_INITIALIZATION_FAILED;
    if (pVersionStruct->loaderLayerInterfaceVersion > 2)
        pVersionStruct->loaderLayerInterfaceVersion = 2;
    pVersionStruct->pfnGetInstanceProcAddr = wproton_GetInstanceProcAddr;
    pVersionStruct->pfnGetDeviceProcAddr = wproton_GetDeviceProcAddr;
    pVersionStruct->pfnGetPhysicalDeviceProcAddr = NULL;
    return VK_SUCCESS;
}

VK_LAYER_EXPORT VKAPI_ATTR PFN_vkVoidFunction VKAPI_CALL
wproton_GetInstanceProcAddr(VkInstance inst, const char *pName)
{
    SI_ES("vkGetInstanceProcAddr", wproton_GetInstanceProcAddr);
    SI_ES("vkCreateInstance", capa_CreateInstance);
    SI_ES("vkCreateDevice", capa_CreateDevice);
    SI_ES("vkGetDeviceProcAddr", wproton_GetDeviceProcAddr);
    SI_ES("vkDestroyDevice", capa_DestroyDevice);
    SI_ES("vkQueuePresentKHR", capa_QueuePresentKHR);
    SI_ES("vkCreateSwapchainKHR", capa_CreateSwapchainKHR);
    SI_ES("vkDestroySwapchainKHR", capa_DestroySwapchainKHR);
    SI_ES("vkGetDeviceQueue", capa_GetDeviceQueue);
    SI_ES("vkGetDeviceQueue2", capa_GetDeviceQueue2);

    if (!g_gipa_siguiente)
        return NULL;
    return g_gipa_siguiente(inst, pName);
}
