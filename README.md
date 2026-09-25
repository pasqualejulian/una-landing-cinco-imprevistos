# Una landing, cinco imprevistos

Un juego web para aprender Git construyendo una landing con IA. Elegís textos, atendés pedidos de último momento y ves crecer tu timeline con las cartas originales de **Oh My Git!**.

Cinco capítulos, un solo repositorio:

1. **v1_final_ahora_sí** — guardá tu primer hero con `add` y `commit`.
2. **¿Y si probamos otro wording?** — creá una rama con `branch`, viajá con `checkout` y guardá otra propuesta.
3. **Viernes, 18:57** — volvé a `main` para un pedido urgente de color.
4. **El experimento gustó** — integrá los caminos con `merge`.
5. **Era para la otra landing** — usá `revert` para corregir el color conservando el wording y toda la historia.

Se juega con mouse y teclado, en un navegador de escritorio con WebGL. Conserva las cartas SVG, el canvas animado, nodos arrastrables, HEAD, música, efectos y terminal. El sonido comienza después del primer clic.

## Ejecutar localmente

Requiere Node.js 22:

```sh
npm ci
npm run build
npm run dev
```

Abrí http://127.0.0.1:4173. El juego funciona completamente en el navegador. No requiere backend, cuenta, claves ni una instalación de Git para jugar.

Cada visitante tiene un repositorio independiente, guardado en `localStorage`. Recargar retoma el capítulo y los cambios preparados. Borrar los datos del sitio elimina la partida. No hay sincronización entre dispositivos. Las partidas de la primera misión se migran conservando el progreso.

## Código y arquitectura

- `src/campaign-runtime.mjs`: capítulos, comandos, repositorio y persistencia con isomorphic-git y memfs.
- `src/git-runtime.mjs`: primitivas Git compartidas y compatibilidad con la primera misión.
- `src/browser.mjs`: comunicación entre JavaScript y el juego.
- `godot-project/`: escenas, scripts y recursos editables del juego, basados en Oh My Git!.
- `godot/`: adaptación web, controlador de campaña y visualización del repositorio.
- `shell.html`: pantalla de carga y entrada.
- `game-export/`: exportación Godot ya generada, necesaria para construir y desplegar sin instalar el motor.
- `build.py`: exporta las escenas en una copia de trabajo aislada.
- `dist/`: sitio generado por `npm run build`.

Para cambiar JavaScript alcanza con `npm run build`. Para cambiar las escenas o recursos, instalá **Godot 3.5.3** y sus templates HTML5, luego ejecutá:

```sh
GODOT_BIN=/ruta/al/ejecutable/Godot npm run export:godot
```

También podés indicar `GODOT_WEB_TEMPLATE=/ruta/webassembly_release.zip`. La exportación usa Godot 3 y GLES2, sin migración a Godot 4.

## Pruebas

```sh
npm test
# Con el servidor local abierto en otra terminal:
npx playwright install chromium
npm run test:browser
```

Las pruebas de runtime incluyen ramas reales, merge con dos padres, revert, persistencia, migración, concurrencia y recuperación ante fallas. Algunos tests requieren Git instalado para verificar los objetos exportados y comparar el resultado con Git nativo.

La aceptación de navegador juega los cinco capítulos mediante mouse y teclado en Chromium, comprueba el audio, el arrastre, la timeline y el progreso al recargar. Los diagnósticos se usan para observar estado y ubicar elementos, no para ejecutar las acciones del juego.

## Desplegar en Vercel

Importá este repositorio con la raíz predeterminada. `vercel.json` configura **Other**, `npm run build` y salida `dist`. No requiere variables de entorno ni servicios externos durante la partida. `game-export/` permite construir en Vercel sin instalar Godot.

## Alcance

Esta campaña tiene cinco casos guiados. La terminal acepta los comandos que corresponden al paso activo, más `status`, `log`, `diff`, `show` y `branch` para consultar. No es una shell general.

El merge de este caso combina HTML y CSS sin conflictos. El revert aplica el parche inverso del commit de color indicado y crea un nuevo commit, conservando los cambios posteriores. No implementa todos los modos posibles de `git revert`, conflictos manuales, remotos ni colaboración multiusuario. Safari, Firefox e interacción táctil no se verificaron.

Detalles del recorrido en [CHAPTERS.md](CHAPTERS.md).

## Créditos y licencia

Adaptación de [Oh My Git!](https://ohmygit.org/) de **blinry y bleeptrack**. Código original: [git-learning-game/oh-my-git](https://github.com/git-learning-game/oh-my-git), revisión de referencia `cfa2625dbd09b50e3108bb9119f2d3b3043fb1b3`. Conserva sus recursos y mecánicas. Esta es una adaptación independiente en español.

[Blue Oak Model License 1.0.0](LICENSE.md). Créditos originales en [UPSTREAM.md](UPSTREAM.md). Motor Godot bajo [su licencia MIT](game-export/GODOT-LICENSE.txt). Licencias y créditos de dependencias en [THIRD-PARTY-NOTICES.txt](game-export/THIRD-PARTY-NOTICES.txt).
