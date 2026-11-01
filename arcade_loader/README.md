# Configuración especial de juegos de Arcade Loader

Aquí van los `.yaml` de los juegos de Arcade Loader que necesitan algo distinto
de lo que trae Arcade Loader de fábrica. WProton los busca y los copia solo.

## Dónde va cada fichero

```
arcade_loader/<sistema>/<gameid>.yaml
```

Por ejemplo:

```
arcade_loader/rawthrills/nicktoons-nitro-racing.yaml
```

## De dónde salen esos dos nombres (y no de donde parece)

**El `<gameid>` es el nombre del marcador que el juego lleva dentro**, sin la
extensión. Lo dice la ayuda del propio `arcade-launcher`:

```
launch a game from its dump (directory or <gameid>.windowsloader file)
The game executable comes from the dump: <dump>/<gameid>.windowsloader holds its path
```

Así que un paquete con `nicktoons-nitro-racing.windowsloader` dentro tiene el
gameid `nicktoons-nitro-racing`.

**No es el nombre del fichero del juego.** El `gamedirs.yaml` de Arcade Loader
lo deja claro:

```
rawthrills/nicktoons-nitro-racing: .../Nicktoons Nitro.squashfs
```

El fichero se llama «Nicktoons Nitro» y el gameid es `nicktoons-nitro-racing`.
No se parecen lo bastante para adivinar uno desde el otro, y adivinarlo mal
sería copiarle a un juego la configuración de otro.

**El `<sistema>` lo saca WProton de los perfiles que Arcade Loader ya trae
instalados**, sin preguntar nada a la red:

```
Arcade_Loader/systemprofiles/rawthrills/nicktoons-nitro-racing.yaml
```

Hoy Arcade Loader trae 195 perfiles de fábrica repartidos en 13 sistemas:
`arcadepc`, `europar`, `globalvr`, `konami`, `namcoes3`, `nesica`, `nesica2`,
`rawthrills`, `ringedge`, `segashell`, `tsunami`, `typex` y `wahlap`.

> Si algún día hace falta una configuración para un juego que Arcade Loader **no**
> trae en `systemprofiles/`, WProton no podrá saber su sistema y lo dirá en el
> registro. Entonces habrá que añadir un índice aquí; está sin hacer porque
> todavía no hace falta.

## Qué poner dentro del `.yaml`

Lo mismo que el perfil de fábrica, pero solo lo que cambie. El propio fichero de
Arcade Loader lo explica en su primera línea:

```yaml
# Nicktoons Nitro Racing (Raw Thrills, 2009) - template, override values in
# userprofiles/rawthrills/nicktoons-nitro-racing.yaml.
```

O sea: `systemprofiles/` es la plantilla y `userprofiles/` es donde van los
cambios. Lo de aquí acaba en `userprofiles/`, que es el sitio que manda y el que
no se pierde al actualizar Arcade Loader.

## Cuándo lo copia WProton

Al lanzar un juego de Arcade Loader:

1. Saca el gameid del marcador y el sistema de `systemprofiles/`.
2. **La primera vez pisa lo que haya** en
   `Arcade_Loader/userprofiles/<sistema>/<gameid>.yaml`. Ahí suele haber ya un
   fichero —de serie, o escrito por Arcade Loader al configurar el juego— y el
   de aquí es el que manda. Lo que había queda al lado como `.anterior`, por si
   alguien lo había ajustado a su mando.
3. **Después no lo vuelve a copiar**, salvo que aquí haya una versión más nueva.
   Eso se sabe sin descargar nada: se guarda el ETag que mandó GitHub y se
   vuelve a preguntar con `If-None-Match`. Si no ha cambiado contesta `304` y no
   manda el fichero.
4. Y **como mucho pregunta una vez al día**. Esto pasa justo antes de lanzar el
   juego: preguntar en cada arranque serían segundos de pantalla quieta cada vez
   que la red fuera mal. La marca es la fecha del fichero del ETag, que vive en
   `profiles/.al_cfg/`.

Si subes una configuración y la quieres **ya**, sin esperar al día siguiente:
Ajustes de un juego → **«Buscar su configuración de Arcade Loader»**, que fuerza
la comprobación.

Lo que nunca hace: copiar una respuesta vacía. Un yaml vacío ahí no solo le daría
a Arcade Loader una sobrescritura vacía, haría creer que ya hay configuración
puesta.
