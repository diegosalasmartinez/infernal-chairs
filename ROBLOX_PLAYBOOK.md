# Roblox Game Dev Playbook

Lecciones, convenciones y patrones aprendidos construyendo juegos en Roblox (Luau + Rojo).
Pensado como referencia reutilizable para arrancar el próximo proyecto sin re-tropezar con
lo mismo. Cada sección lleva el **por qué** además del **qué**, porque las reglas sin razón
se aplican mal en los casos borde.

---

## 1. Tooling y setup

- **Rokit** (`rokit.toml`) versiona las herramientas del proyecto: Rojo, StyLua, Selene. Todos
  en el repo, misma versión para todo el equipo.
- **Rojo** mantiene la fuente de verdad en archivos de texto (JSON + Luau) y sincroniza
  filesystem → Studio. Es **unidireccional por convención** (two-way es frágil; evitarlo).
  El código edita, Studio renderiza.
- **StyLua** formatea. Correr `stylua --check src/` antes de dar algo por terminado.
- **Selene** lintea, pero **necesita un `selene.toml` con `std = "roblox"`**. Sin eso, da
  falsos positivos: marca `+=` como error de sintaxis y `Color3`/`Vector3` como variables
  indefinidas (parsea como Lua puro, no Luau+Roblox). Si ves esos errores, falta el config,
  no es tu código.
- **`rojo build default.project.json -o out.rbxl`** valida el project.json + la sintaxis de
  todo el árbol. Úsalo como smoke test rápido tras tocar el JSON o agregar instancias.

### Por qué Rojo y no Studio puro
Studio no versiona bien (`.rbxl` es binario, ilegible en diffs). Rojo deja el código en texto
plano versionable.

---

## 2. Arquitectura y estructura de código

### El problema del script monolítico
Es fácil empezar con un `init.server.luau` gigante (imperativo: funciones que mutan estado
global compartido vía closures). Funciona pero escala mal — todo queda acoplado, cualquier
función puede tocar cualquier estado, y extraer pedazos cuesta porque "agarran" muchas
variables del scope. Cuando un archivo pasa de ~500 líneas, empezá a partir.

### La unidad de reutilización: ModuleScript
Un `ModuleScript` `return`-a una tabla/función y se importa con `require()`. Es el módulo/
librería de Roblox. Organización canónica:

| Servicio | Para qué | Carpeta Rojo típica |
|---|---|---|
| `ReplicatedStorage` | código compartido client+server (constantes, tipos, utils) | `src/shared` |
| `ServerScriptService` / `ServerStorage` | módulos server-only | `src/server` |
| `StarterPlayerScripts` | módulos client | `src/client` |

El `init.server`/`init.client` quedan como **orquestadores delgados**: `require` de módulos +
arrancar. La lógica vive en módulos por responsabilidad única (`ChairService`, `EventService`,
`OrbitService`, `MatchLoop`, `UIController`…).

### Patrones de diseño útiles en game dev
- **Service/Module pattern** — el más práctico para Roblox. Servicios con responsabilidad
  única, cada uno un módulo. Empezá por acá.
- **State machine** — el match loop (Waiting → Warmup → Intermission → Playing → Stopped →
  Judgement → Winner → Reset) es una state machine. Hacerla explícita la vuelve clara y
  testeable, en vez de un `while` con flags implícitos.
- **Event-driven / Observer** — signals / `BindableEvent` para desacoplar módulos, en vez de
  closures sobre estado global.
- **ECS (Entity-Component-System)** — el patrón "pesado" de game dev (framework **Matter** en
  Roblox). Potente pero overkill para juegos chicos/medianos.
- **Frameworks**: **Knit** (services client/server), **Flamework**, **Matter**. Estructuran
  todo pero agregan curva de aprendizaje + dependencia. **No los adoptes por defecto** — para
  un juego chico, extraer ModuleScripts a mano es proporcional y suficiente.

### Regla práctica de refactor
Extraé incrementalmente, empezando por lo más grande y autocontenido (suele ser el sistema de
eventos/efectos). El costo escondido: si los módulos comparten estado, tenés que diseñar una
**"API de contexto"** que se les pasa, en vez de globals sueltas. Eso es el trabajo real, no
mover-y-pegar.

---

## 3. Rojo: quirks que cuestan horas

1. **`$path` a un `.rbxm`/`.rbxmx` + `$className` juntos → conflicto.** Error:
   `ClassName ... specified in both the project file and from the filesystem`. Fix: omití
   `$className` (que la clase la defina el archivo) **o** asegurá que el top-level del `.rbxm`
   sea un Folder.
2. **`.rbxm` con múltiples instancias top-level**: Rojo toma UNA sola y descarta el resto
   silenciosamente. Si necesitás varias, envolvelas en un Model/Folder antes de guardar.
3. **`rojo serve` NO recarga `default.project.json`.** Observa los archivos referenciados por
   `$path`, pero si editás el project.json (agregás nodos, renombrás), tenés que **matar y
   reiniciar `rojo serve`**. El plugin reconectando no alcanza — Studio toma un snapshot viejo.
4. **Inspeccionar qué hay dentro de un `.rbxm`**: `grep -aoE "INST.{30}" archivo.rbxm` lista
   cada instancia/clase del archivo. Útil para diagnosticar "este archivo tiene cosas que no
   quería incluir".
5. **UDim2 en `project.json` es un dolor.** Los errores son vagos (`Failed to deserialize
   JSON`) o engañosos (`Expected UDim2, got an array of four numbers` aunque la doc diga que
   esa forma vale). **Workaround confiable**: declará el container (Part, Frame) en JSON con
   props primitivas, y construí el árbol de GUI (SurfaceGui, TextLabels, UDim2) en una función
   Luau. No pierdas horas peleando con el schema.

---

## 4. Las tres formas de construir contenido del mundo

Esta es la decisión más importante a la hora de armar un mapa o agregar algo nuevo.
Cada approach tiene un workflow distinto con Rojo y un nicho específico. Mezclarlos sin
criterio es donde más se pierde tiempo. La regla:

### Approach 1 — JSON estático (`default.project.json`)
- **Cuándo**: geometría fija, simple, sin lógica, con propiedades primitivas
  (Position, Size, Color, Material, BasePart). Ej.: las paredes del lobby, el baseplate,
  un techo, un piso.
- **Workflow**:
  1. Editás `default.project.json` (texto).
  2. Si `rojo serve` está corriendo, hay que **reiniciarlo** (matar y volver a iniciar) —
     Rojo NO recarga el project.json en caliente (ver Rojo quirk #3).
  3. En Studio, **Disconnect → Connect** el plugin. La nueva geometría aparece en el árbol.
- **Pros**: versionable como texto, diff legible, simple para tipos primitivos.
- **Cons**: no computa nada (no podés escribir `width = radius * 2`). UDim2 y tipos
  complejos sufren (ver quirk #5). No se edita visualmente — escribís números.

### Approach 2 — Código en runtime (módulos Luau)
- **Cuándo**: geometría parametrizada (deriva de constantes que querés reescalar de un
  solo número), lógica de runtime, UI con UDim2, props que necesitan setup complejo
  (signals, scripts, conexiones de eventos). Ej.: el shell del arena que se reescala
  desde `ARENA_RADIUS`, los SurfaceGuis de los signs, los placeholders dinámicos de Decor.
- **Workflow**:
  1. Editás un módulo Luau (ej. `World.luau`).
  2. Rojo sincroniza el archivo a Studio automáticamente (no requiere reiniciar serve
     para edits de `.luau`, solo para edits del `project.json`).
  3. **PERO**: si ya le diste Play, los Scripts del server **no se re-ejecutan**. Para
     ver los cambios tenés que **parar Play (Shift+F5) y volver a darle Play (F5)**.
- **Pros**: reescalable (un solo `ARENA_RADIUS = 100` redefine todo), versionable,
  programable, soporta cualquier tipo (UDim2 ✓).
- **Cons**: NO se ve en Studio sin darle Play (lo construye el server en runtime), ciclo
  de iteración más lento (cambiar código → re-Play → ver).

### Approach 3 — `.rbxm` editado visualmente en Studio (Save to File)
- **Cuándo**: decoración estática que querés posicionar/rotar **con el mouse**, no a ojo
  con coordenadas. Ej.: los muebles del lobby (sofás, plantas, jukebox), props de
  Marketplace, dressing visual. Cualquier cosa fija donde "ojímetro" + manipulador 3D
  es mejor que adivinar números.
- **Workflow**:
  1. En Studio (**modo Edit**, no Play) creás o editás el contenido. Si lo agrupás todo
     en un Folder/Model contenedor, mejor.
  2. Click derecho sobre el Folder/Model → **Save to File...** → guardás como
     `assets/<nombre>.rbxm`.
  3. Declarás en `default.project.json` con `$path`:
     ```json
     "Decor": { "$path": "assets/lobby-decor.rbxm" }
     ```
  4. Reiniciás `rojo serve` (porque tocaste el project.json).
  5. En Studio, **borrá el Folder manual** que creaste (si existía) — Rojo lo recrea
     desde el `.rbxm` y si lo dejás manual quedan duplicados. Después **Disconnect →
     Connect** y el Folder reaparece servido desde el `.rbxm`.
- **Pros**: edición visual con manipuladores 3D, ves cambios al instante en Edit,
  versionable como `.rbxm` binario (cabe en git), no requiere re-Play para ver cambios
  offline.
- **Cons**:
  - **Los cambios en Play no se guardan**: si movés algo durante Play, al detenerlo se
    pierde. Siempre editás en Edit mode, después Save to File.
  - Hay que **acordarse de "Save to File"** cada vez que edites; los cambios no se
    persisten automáticamente al filesystem (Rojo es unidireccional).
  - El `.rbxm` es binario — los diffs no muestran qué cambió. Versionás "snapshots".

### ¿Cuál elijo? — decisión rápida

| Pregunta | Si SÍ |
|---|---|
| ¿Necesita lógica en runtime o responde a eventos? | **Approach 2** (código) |
| ¿Deriva de un parámetro que querés reescalar? (`width = radius * 2`) | **Approach 2** (código) |
| ¿Tiene UDim2 o tipos complejos para Rojo? | **Approach 2** (código) |
| ¿Es decoración estática que querés mover con el mouse? | **Approach 3** (`.rbxm`) |
| Si nada de lo anterior aplica — geometría fija primitiva | **Approach 1** (JSON) |

### Mezclar los tres en un solo nivel
Lo común es **combinar los tres**. Ejemplo del proyecto Infernal Chairs:
- **Arena shell** (paredes, techo, track, pillars, neon ring) → código (`World.buildArena`),
  porque deriva de `ARENA_RADIUS`.
- **Lobby shell** (paredes, piso, techo, luces ambientales) → JSON, porque es fijo.
- **Lobby decor** (sofás, plantas, jukebox) → `.rbxm` editado en Studio, porque querés
  arrastrar los muebles con el mouse.
- **Signs** (RulesSign, MatchStatusSign): el Part en JSON + el SurfaceGui construido en
  código (workaround de UDim2 en JSON).
- **Disco ball**: viene de un `.rbxm` del Marketplace + posicionado por código en un
  slot derivado de `ARENA_RADIUS`.

### El loop diario con Rojo (resumen)
Cuando hagas cambios, **el reflejo en Studio depende de qué tocaste**:
| Edité | Necesito | Rojo recarga? | Studio recarga? | Play se actualiza solo? |
|---|---|---|---|---|
| `.luau` (módulo, init) | nada extra | sí, en caliente | sí, vía plugin | **NO** — re-Play (Shift+F5 → F5) |
| `.rbxm` referenciado por `$path` | nada extra | sí | sí, vía plugin reconnect | **NO** — re-Play |
| `default.project.json` | **reiniciar `rojo serve`** | no recarga solo | reconnect plugin | **NO** — re-Play |
| Algo en Studio (manual) | **Save to File** del Folder/Model | n/a | ya está en Studio | n/a (estás en Edit) |

Internalizar esta tabla ahorra horas de "¿por qué no veo mis cambios?".

---

## 5. Server / Client: quién hace qué

### En el cliente (LocalScript / per-player)
- Cualquier cosa que responda a input local y deba sentirse **inmediata** (inercia de hielo,
  jump-pads, controllers custom, efectos de cámara). Hacerlo server-side mete un round-trip de
  red por frame y se siente laggy.
- **UI** (banners, countdowns, overlays) — siempre cliente.
- Música / SFX con volumen per-player.
- **Efectos cosméticos puros** (niebla de partículas, post-procesado) — no necesitan autoridad,
  no satures la red replicándolos.

### En el server
- Cualquier cosa **autoritativa** (límites de WalkSpeed, detección anti-cheat, "estás sobre
  barro", quién gana). Aunque sea per-frame, suele ser barato y a prueba de tampering.
- **Single source of truth** (jugadores activos, quién está sentado, evento de la ronda, scores).
- `SetNetworkOwner(nil)` para forzar movimiento (el server toma ownership para que el cliente
  no pelee sus escrituras de CFrame).
- Broadcasts a todos los clientes.

### El puente
Cuando el cliente reacciona a un cambio de estado, el server lo manda en el **payload de un
RemoteEvent existente** (ej. `StateChanged.payload.event`). **No agregues un RemoteEvent por
cada efecto** — extendé el payload.

### Regla de oro
Antes de agregar un efecto/sistema: **¿necesita autoridad?** No (visual / feel de movimiento)
→ cliente. Sí (toca reglas de supervivencia) → server.

### El incidente que originó la regla (ice-lag)
La inercia de hielo se implementó primero como `RunService.Heartbeat` server-side escribiendo
`AssemblyLinearVelocity`. Con personajes client-owned, cada escritura viajaba: input cliente →
server procesa → server replica de vuelta → cliente renderiza. ~50-200ms de lag por frame,
matando el feel. Moverlo al cliente lo hizo instantáneo.

---

## 6. Lighting y efectos visuales (muchos gotchas)

- **`Lighting` es SIEMPRE global por place.** `Ambient`, `Atmosphere`, fog legacy
  (`FogStart`/`FogEnd`/`FogColor`), y los `PostEffect` (ColorCorrection, DepthOfField, Blur…)
  afectan TODO el mundo. **No se puede limitar un efecto de Lighting a una zona.**
- **`Atmosphere` es quality-dependent**: en graphics quality baja se atenúa o no renderiza.
  Si lo usás para algo gameplay-relevante, algunos jugadores no lo verán.
- **Fog legacy (`FogEnd`) NO renderiza con `Lighting.Technology = "ShadowMap"`** (ni con las
  tecnologías modernas). Es API vieja, ignorada. Además, mientras hay un `Atmosphere` presente,
  el fog legacy queda anulado.
- **Para niebla/efecto LOCALIZADO a una zona Y consistente en todos los clientes: partículas
  físicas.** Un `ParticleEmitter` con `rbxasset://textures/particles/smoke_main.dds`, `Shape =
  Box` + `ShapeStyle = Volume` (llena el volumen, no solo las caras), `Speed ≈ 0` (la niebla
  flota quieta), y `:Emit(n)` para llenar al instante. Las partículas son objetos del mundo →
  solo existen donde las ponés, y son render básico → no quality-gated.
- **Cold start del ShadowMap**: salas cerradas que dependen solo de PointLights tienen un flash
  de oscuridad al cargar (el ShadowMap tarda 1-2 frames en inicializar). **Fix: subir
  `Lighting.Ambient`** (luz base global, presente desde el frame 0). Más notorio en Studio Play
  que en el cliente real.
- **`Ambient` es global**: si lo subís para iluminar una sala, afecta TODAS. Compensá bajando
  los PointLights específicos de las otras salas para mantener su mood.
- **Materiales**: `SmoothPlastic` se ve plastilina. `Brick`/`Concrete`/`Slate` dan textura sin
  asset externo. `Neon` es auto-iluminado (acentos, strips, pillars).
- **Skybox**: un `Sky` con `StarCount`/`CelestialBodiesShown` da cielo nocturno sin asset.

### `rbxasset://` vs `rbxassetid://`
- `rbxasset://textures/...` → assets que vienen con el engine (texturas de partículas, sonidos
  default). Disponibles offline, sin subir nada.
- `rbxassetid://NUMERO` → assets del Marketplace / subidos por vos.

---

## 7. Física

- **FrictionWeight**: el motor mezcla la fricción entre dos superficies como un **promedio
  ponderado por `FrictionWeight`**. El constructor `PhysicalProperties.new(density, friction,
  elasticity)` de **3 args resetea el weight a 1**, lo que pisa el weight intrínseco de
  materiales como `Ice` (que es 3). Para superficies resbaladizas custom usá el de **5 args**
  con `FrictionWeight` explícito alto (ej. `PhysicalProperties.new(0.919, 0, 0.15, 1000, 1)` →
  fricción efectiva ≈ 0.0003, casi sin fricción).
- **`SetNetworkOwner(nil)`**: el server toma ownership del root part para escribir su CFrame
  sin que el cliente lo sobreescriba (movimiento forzado, ej. orbitar).
- **Bloquear el salto de verdad**: Roblox moderno usa `JumpHeight` (default 7.2), NO
  `JumpPower`. Setear solo `JumpPower=0` no impide saltar. Para freezar: `JumpPower=0` +
  `JumpHeight=0` + `humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)` +
  `AutoJumpEnabled = false`.
- **Seats**: para sentar a la fuerza, `Seat.Disabled = true` permanente (evita auto-sit al
  tocar) + `seat:Sit(humanoid)` para forzar + un `WeldConstraint` de respaldo. **No confíes en
  `Seat.Occupant`** como fuente de verdad — el motor lo limpia cuando el jugador intenta saltar.
  Mantené tu propia tabla `lockedToChair`.

---

## 8. Geometría parametrizada

- Derivá TODA la geometría de una **única fuente de verdad** + factores. Ej.: `ARENA_RADIUS` y
  `ORBIT_RADIUS = ARENA_RADIUS * 0.69`, paredes en `±ARENA_RADIUS`, etc. Reescalar el mundo = un
  solo número.
- El módulo de Config (un `ModuleScript` Lua) **puede computar** valores derivados — aprovechalo.
- Como JSON no computa, esa geometría va en código (una función `buildArena()` que crea
  paredes/techo/piso/etc. a partir de las constantes). Usá un helper `makePart(name, parent,
  props)` para no repetir `Instance.new` + setear cada propiedad.

---

## 9. Performance

- **Partículas — el costo es overdraw, no simulación.** Overdraw ≈ `partículas_vivas × tamaño²`
  (sprites transparentes pintándose uno sobre otro). Partículas vivas = `Rate × Lifetime_promedio`.
  Para densidad visual con buen FPS: **menos partículas pero más grandes y opacas** > muchas
  chicas. Bajar el count es la palanca más efectiva.
- `LightInfluence = 0` (unlit) es más barato que samplear la luz de escena por partícula.
- **Efectos client-side no replican**: no saturan la red, y un cliente con FPS bajo no afecta a
  los demás.
- `StreamingEnabled = false` está bien para mapas chicos; activarlo recién con mundos grandes.

---

## 10. UI

- **`TextScaled` vs `TextSize` fijo**: `TextScaled` escala el texto al tamaño del frame — se ve
  inconsistente si los frames varían (una regla de 1 línea se ve gigante, una de 2 chica). Para
  control fino y consistencia, **`TextSize` fijo**. Trade-off: TextScaled se adapta a
  resoluciones distintas automáticamente.
- **`UIListLayout`** para spacing automático entre elementos (no hardcodees posiciones Y). Si
  agregás/sacás items, se reacomodan solos. `Padding` controla el gap.
- **Jerarquía visual**: overlays del HUD que conviven (banner, timer, tooltip) deberían
  compartir altura, estilo, transparencia y esquinas. Definí constantes compartidas
  (`HUD_TOP`, `HUD_HEIGHT`, `HUD_BG`…) y que solo difieran en el anchor horizontal. Si no, se
  siente desordenado.
- **`UIScale`** para animaciones de punch/zoom (tween del `Scale` con `TweenService`).
- **`ScreenGui.ResetOnSpawn = false`** para UI que debe persistir entre respawns.

---

## 11. Patrones de juego (reutilizables)

- **State machine para el match loop**, con broadcast de la fase actual a los clientes.
- **Warmup countdown**: no arranques el match apenas se alcanza `MIN_PLAYERS`. Meté una fase de
  espera (ej. 10s) para que los que joinean justo no caigan directo a jugar. Si la headcount
  baja del mínimo durante el warmup, cancelá y volvé a esperar.
- **Capacidad**: el cap de jugadores lo da `Players.MaxPlayers` (setting del place, no código).
  Las cosas que escalan con N jugadores (ej. cantidad de sillas) computalas dinámicamente.
- **Spectator mode**: a los eliminados, respawn a un anillo afuera del área, congelados
  (`WalkSpeed=0` + jump disabled), mirando al centro. Re-liberarlos al terminar el match.
- **Eventos/modificadores extensibles con hooks**: una tabla `EVENTS` donde cada uno define
  `onStart` / `onEnd` (o las fases que correspondan). Un `runEventHook(name)` los dispara. Fácil
  de agregar variantes.
- **Lobby separado del área de juego**: sala aparte donde los jugadores esperan y vuelven entre
  matches. El "teleport" al área puede ser implícito (el sistema que los posiciona al empezar
  ya los mueve). Para volver al lobby: `humanoid.Health = 0` fuerza respawn vía SpawnLocations.

---

## 12. Assets del Marketplace

- **Chequeá el Marketplace antes de codear desde cero.** Muchas cosas (modelos, sonidos,
  texturas) ya existen gratis en el Toolbox.
- **Bundleá como `.rbxm` en `assets/`** y cargalo vía Rojo `$path`. **No uses
  `InsertService:LoadAsset` en runtime** — es HTTP en cada server start y depende de permisos
  del asset. El `.rbxm` bundleado es instantáneo y self-contained.
- Inspeccioná el asset antes de integrarlo (ver Rojo quirk #4).

---

## 13. Audio

- **SoundIds configurables, vacío = silencio sin crash**: guardá los IDs en Config; si están
  vacíos, el código chequea y no toca nada (en vez de romper). Así podés codear la
  infraestructura antes de tener los assets.
- **Música rotativa**: array de SoundIds, pick random por match, para que no canse.
- Música distinta por contexto (lobby chill vs match intenso), elegida server-side y enviada al
  cliente.

---

## 14. Convenciones de proyecto que funcionaron

- **`Config.luau` como fuente única de constantes tunables.** El `init` hace
  `local Config = require(script.Config)` y crea aliases locales (`local MIN_PLAYERS =
  Config.MIN_PLAYERS`) para que el resto del código quede legible. Balancear el juego = editar
  solo Config.
- **Debug flags reversibles**: ej. `FORCE_EVENT = "fog"` (fuerza un evento todas las rondas para
  testear) o `HUD_DEBUG_ALWAYS_VISIBLE = true` (muestra todos los overlays con data mock sin
  correr un match). Comentá claro cómo revertir (`= nil` / `= false`).
- **Cleanup completo entre matches**: al terminar, correr todos los teardown (eventos, welds,
  spectators, ocultar props), esperar, y volver al loop. No dejar estado colgado entre rondas.
- **Comentarios que explican el PORQUÉ no obvio** (constraints ocultos, workarounds de bugs
  específicos), no el QUÉ (que el código ya dice).

---

## Checklist para arrancar un proyecto nuevo

- [ ] `rokit init` + agregar Rojo, StyLua, Selene a `rokit.toml`
- [ ] Crear `selene.toml` con `std = "roblox"` (evita los falsos positivos)
- [ ] `default.project.json` con el árbol base + carpetas `src/server`, `src/client`, `src/shared`
- [ ] `Config.luau` desde el día 1 (no hardcodear constantes sueltas)
- [ ] Decidir geometría: fija → JSON, parametrizada → código
- [ ] Pensar el split server/client desde el diseño (¿qué necesita autoridad?)
- [ ] Empezar con módulos por responsabilidad antes de que el `init` pase de ~500 líneas
