# Dev Plan — Infernal Chairs

Roadmap completo del juego, dividido en fases. Cada fase tiene un objetivo claro y subtareas trackeables.

## Visión

Un juego de sillas musicales en Roblox con un giro: **los jugadores no controlan su movimiento mientras suena la música**. Orbitan automáticamente alrededor de las sillas. Cuando para la música, recuperan el control y corren a sentarse. El que no alcanza silla queda eliminado. Una silla menos cada ronda hasta que queda 1 ganador. A partir de la ronda 2, cada ronda tiene un **evento** que cambia las reglas (hielo, lodo, luces intermitentes, niebla…).

El nombre "Infernal" viene de esa pérdida de control que vuelve la mecánica más estresante que las sillas musicales tradicionales.

## Quick start para una sesión nueva

Si estás retomando este proyecto desde contexto cero:

1. **Lee este file de arriba a abajo** + leé **`ROBLOX_PLAYBOOK.md`** (lecciones reutilizables; secciones 3-4 son críticas para entender la arquitectura).
2. **Estructura del proyecto** (post-refactor):
   - **Server** (`src/server/`):
     - `init.server.luau` — game loop (state machine), sit, orbit, spectator, eliminación.
     - `Config.luau` — todas las constantes tunables (fuente única).
     - `Events.luau` — definiciones de eventos (ice/mud/fog/flickering), factory con contexto.
     - `World.luau` — escena runtime: arena shell parametrizado desde `ARENA_RADIUS`, signs (SurfaceGui), partículas, anchored pass del lobby decor.
     - `Decor.luau` — slot del arena (sólo DiscoBall ahora) con pivot compensation.
   - **Client** (`src/client/`):
     - `init.client.luau` — bridges RemoteEvents → audio, SFX, fog particles.
     - `Hud.luau` — toda la UI (banner, countdown, eliminated overlay, welcome modal).
   - **JSON** (`default.project.json`): geometría primitiva fija del Lobby (Walls, NeonStrips, Lights, RulesSign), Baseplate. Templates y Decor declarados como Folders vacíos con `$ignoreUnknownInstances: true` para que vivan en el `.rbxl`.
   - **`.rbxl` versionado** (`infernal-chairs.rbxl`): templates del Marketplace + lobby decor + Floor/Ceiling del lobby + MatchStatusSign + SpawnLocations. Todo lo que tiene `MaterialVariant`/`SurfaceAppearance`/`AeroMeshData`/binarios complejos vive acá porque Rojo no roundtripea bien esas propiedades por `.rbxm` (ver Playbook §3 quirks 6-7).
3. **Para jugar**: `rojo serve` desde la raíz, plugin Rojo en Studio → Connect, abrir `infernal-chairs.rbxl`, F5.
4. **Loop diario con Rojo**:
   - Edité `.luau` → re-Play (Shift+F5 → F5). Rojo sincroniza solo.
   - Edité `default.project.json` → **reiniciar `rojo serve`** + Disconnect/Connect plugin + re-Play.
   - Edité algo visual en Studio (lobby decor, templates) → **Ctrl+S** al `.rbxl` + `git commit`. No requiere reiniciar Rojo.
   - **NUNCA** uses Save to File a `.rbxm` para Marketplace assets — pierde texturas. Vive en el `.rbxl`.
   - Ver Playbook §4 ("loop diario") para la tabla completa.
5. **Si la cagás en Studio** (borraste algo accidental, los muebles se ven raros): cerrá Studio **sin guardar** y reabrí el `.rbxl`. El de disco no se sobreescribió hasta el próximo Ctrl+S.
6. **Próximo paso**: Fase 13 (DataStore) o Fase 14 (más eventos). Ver [Próximos pasos](#próximos-pasos--orden-recomendado).

---

## Estado por fase

Leyenda: ✅ done · 🔄 in progress · ⏳ pending

### Fase 0 · Tooling — ✅ done

- ✅ `rokit init` + Rojo / StyLua / Selene versionados en `rokit.toml`
- ✅ Las 3 herramientas ejecutables

### Fase 1 · Estructura y sync con Studio — ✅ done

- ✅ `default.project.json` + jerarquía estándar en `src/`
- ✅ Plugin de Rojo instalado en Studio
- ✅ Sync vivo Studio ↔ filesystem validado

### Fase 2 · MVP jugable — ✅ done

- ✅ Mapa: Baseplate, Sillas, SpawnLocations, Track (carrusel)
- ✅ State machine completa
- ✅ Audio: server dispara `PlayMusic`/`StopMusic` vía RemoteEvent, cliente toca/para localmente
- ✅ Sit detection server-authoritative (sin trust del cliente)
- ✅ Eliminación: kill character + tracking de `activePlayers`
- ✅ Detección de ganador
- ✅ Sillas se ocultan según count de activos (`visibleChairs = activos - 1`)
- ✅ Loop entre matches

### Fase 3 · Posicionamiento dinámico — ✅ done

- ✅ Sillas a posiciones aleatorias cada ronda (rejection sampling para separación mínima)
- ✅ Sillas nacen ocultas (sin flash)
- ✅ Anillo de 8 SpawnLocations en circunferencia

### Fase 4 · UI mínima — ✅ done

- ✅ Banner con estado actual + subtexto, ResetOnSpawn=false
- ✅ Color del texto cambia según fase
- ✅ Overlay "ELIMINATED" cuando te eliminan
- ✅ Countdown rojo arriba a la derecha durante fase Stopped
- ✅ RemoteEvents: `StateChanged` (broadcast), `YouEliminated` (per-player)

### Fase 5 · Rotación forzada — ✅ done

**Approach final**: CFrame directo desde server + `SetNetworkOwner(nil)`. Velocidad angular 0.45 rad/s, radio 48 (justo dentro del borde del track). Los jugadores orbitan mirando hacia adelante (tangente al círculo). Al parar la música se les devuelve ownership y vuelven a controlar.

- ✅ `freezeAndAssign` por activo: SetNetworkOwner(nil), WalkSpeed=0, JumpPower/JumpHeight=0
- ✅ `applyOrbit` corriendo en `RunService.Heartbeat`, una CFrame por activo por frame
- ✅ `thaw` libera ownership y restaura velocidad cuando para la música
- ✅ Posiciones iniciales distribuidas uniformemente alrededor del círculo

### Fase 5b · Sit lock + verdict — ✅ done

Cuando la música para, los jugadores corren y presionan **E** cerca de una silla para sentarse. Una vez sentados no pueden moverse ni saltar — el motor intenta varias cosas (jump, levantarse), pero todas están bloqueadas por capas redundantes.

- ✅ ProximityPrompt en cada silla (KeyCode E, MaxActivationDistance 8, HoldDuration 0)
- ✅ Silla siempre `Disabled=true` para evitar auto-sit por tocar; el prompt es el único trigger
- ✅ Server llama `chair:Sit(humanoid)` (acepta seats Disabled) + `WeldConstraint` físico de respaldo
- ✅ Lockdown: `JumpPower=0`, `JumpHeight=0`, `AutoJumpEnabled=false`, state `Jumping` disabled, listener en `Sit` que re-sienta si flippea
- ✅ `lockedToChair` es la source-of-truth para "quién está sentado" (no confiamos en `Seat.Occupant`, lo limpia el engine cuando intentan saltar)
- ✅ Si todas las sillas se llenan antes del grace timeout, la ronda termina al toque (poll 150ms)
- ✅ **Fase Judgement**: 2s de pausa dramática después del grace, todos los no-sentados quedan congelados en su sitio (velocity=0), después se eliminan los no-sentados

### Fase 6 · Mundo cerrado + lighting — ✅ done

Sala con paredes y techo, ambiente nocturno-discoteca. Profundidad visual con `Atmosphere` sutil.

- ✅ `Workspace.Arena.Shell`: Ceiling + 4 paredes parametrizados desde `ARENA_RADIUS`, `SmoothPlastic` color púrpura oscuro
- ✅ `Lighting`: `ShadowMap` technology (mejor que Voxel, carga instantánea)
- ✅ `Atmosphere` con haze sutil
- ✅ `CenterLight`: PointLight, ilumina toda la pista (referenciado por el evento `flickering`)
- ✅ Asset de silla cargado desde `ReplicatedStorage.Templates.Chair` (en el `.rbxl`, NO en `.rbxm` — ver Fase 12.6 para la razón)
- ✅ Track más grande, spawns alineados al borde de la órbita
- ✅ `StreamingEnabled = false` (mapa chico, sin necesidad de streaming)
- ✅ `HttpService.HttpEnabled = true` declarado en JSON para que el plugin Rojo conecte
- ✅ Material/Track friction defaults guardados como constantes (para que eventos puedan modificarlos y restaurar)

### Fase 7 · Spectator mode — ✅ done

Los eliminados respawnean en un anillo afuera del juego, congelados, solo para ver.

- ✅ `CharacterAdded` hook detecta respawn de eliminado y los teletransporta al spectator ring
- ✅ Radio relativo: `ORBIT_RADIUS + 12..18` (= 60-66 con orbit 48)
- ✅ WalkSpeed=0, JumpHeight=0, Jumping state disabled — no se pueden mover
- ✅ Miran hacia el centro de la sala (`CFrame.lookAt`)
- ✅ Se "thawean" al terminar el match (próximo match arranca con todos liberados)

### Fase 8 · Round events — ✅ done

Sistema extensible con hooks (`onPlayingStart`, `onStoppedStart`, `onRoundEnd`). Cada ronda 2+ elige un evento random. El nombre del evento se anuncia en el banner durante Intermission y Stopped.

- ✅ Server: tabla `EVENTS` + `runEventHook(name)` + `pickRandomEvent()`
- ✅ Client: lee `payload.event` de `StateChanged` y aplica efectos locales (solo hielo por ahora)
- ✅ **`flickering`**: server apaga el CenterLight + drop `Lighting.Ambient/Brightness` a 0 (oscuridad real, no solo light off). Ciclo 2.5-3.5s OFF, 0.8-1.2s ON
- ✅ **`ice`**: Track cambia a `Material.Ice` + color pastel blue del asset `4902389321` + `CustomPhysicalProperties(0.919, 0, 0.15, 1000, 1)` (Friction=0 con FrictionWeight=1000 → fricción efectiva ≈ 0.0003 contra el personaje, prácticamente sin fricción). También `WalkSpeed = 28` (`ICE_WALK_SPEED`) para velocidad, y `jumpDisabled = true` (no se puede saltar para escapar del slide). Aprendizajes: la fórmula de mezcla de fricción de Roblox pondera por `FrictionWeight`, así que un weight alto hace que el valor 0 domine totalmente. Memoria: `roblox_friction_weight.md`.
- ✅ **`mud`**: 28 patches de barro de distintos tamaños (radio 4-10) cobertura ~75% del playing area. Heartbeat server-side detecta entrada/salida de patch → WalkSpeed 6 o default
- ✅ **`fog`**: sube `Lighting.Atmosphere.Density` a 0.85 + `Haze` a 5 + cambia `Color` a tinte amarillento gris. Apenas se ven las sillas a distancia → planificación visual difícil. Snapshot/restore de los valores originales en cleanup.

---

## Próximos pasos — orden recomendado

El sistema de eventos ya está sólido y extensible. **Antes de meter más eventos, hay otros frentes que dan más retorno por hora invertida.** Orden sugerido:

### Fase 10 · Polish — ✅ done

Infraestructura de polish lista. La animación, partículas, música rotativa y SFX-on-event ya disparan. Los SoundIds de SFX están vacíos en `Config.luau` (server) y como locales en `init.client.luau` (cliente) — pegá ahí los IDs del marketplace cuando los tengas y el código los toca automáticamente sin más cambios.

- ✅ **SFX del stop** — `playSfx(stopSfx)` en `StopMusic.OnClientEvent`. SoundId vacío = no-op; pegá tu ID en `STOP_SFX_ID` (cliente) para activarlo.
- ✅ **SFX de eliminación** — `playSfx(eliminateSfx)` en `YouEliminated.OnClientEvent`. Mismo patrón: setear `ELIMINATE_SFX_ID`.
- ✅ **Partículas del ganador** — `spawnWinnerParticles` adjunta un `ParticleEmitter` al `HumanoidRootPart` del ganador durante la fase Winner. Confeti dorado/naranja/rosa, auto-destruido vía `Debris:AddItem` después de `POST_MATCH_SECS + 1`. Sin asset externo (textura default).
- ✅ **Animación del banner del evento** — `UIScale` en el banner + `TweenService` punch (1 → 1.25 → 1) con flash de color a oro. Server manda `eventChanged = true` solo cuando el evento activo cambia; cliente dispara `punchBanner(phaseColor)`.
- ✅ **Música rotativa** — `Config.MUSIC_TRACKS` es un array de SoundIds. Server pickea random y lo envía con `PlayMusic:FireAllClients(trackId)`. Cliente cambia `Music.SoundId` solo si difiere del actual (no reset si se repite la misma).
- ✅ **Lobby loop pulido** — `lobbyFrame` centrado, grande, solo visible en fase Reset. Cuenta los segundos hasta el próximo match con texto dorado gigante.

### Fase 11 · Tutorial / Onboarding — ✅ done

Tres capas de onboarding superpuestas: bienvenida explícita al join, recordatorio durante la fase Stopped, y referencia ambiental siempre disponible en el mapa.

- ✅ **Welcome overlay** al joinear: panel full-screen oscuro con las 3 reglas + botón "GOT IT". Se muestra una vez por sesión (el LocalScript corre una sola vez al entrar). La persistencia entre sesiones queda para Fase 13 (DataStore).
- ✅ **Tooltip "E" en Stopped**: `sitTipFrame` arriba a la izquierda con un cuadradito dorado grande con la letra "E" + texto "PRESS TO SIT". Solo visible cuando `payload.phase == "Stopped"`.
- ✅ **Sign 3D en lobby**: Part `Workspace.Room.RulesSign` (22×14×0.4) pegado a la pared norte (z=68.8) con `SurfaceGui` + 2 `TextLabel`s (Title dorado + reglas en blanco). El Part está declarado en `default.project.json`; el GUI tree lo construye `setupRulesSign()` en `init.server.luau` al startup (más simple que pelear con UDim2 en JSON — ver memoria `rojo_path_quirks.md` para detalle).

### Fase 12.5 · Lobby v2 (matchmaking + status board) — ✅ done

Añadidos para resolver el problema "ni bien joineás te mete al match" y dejar el lobby preparado para futuras features sociales/monetización.

- ✅ **Warmup countdown**: `Config.LOBBY_WARMUP_SECS = 15`. Una vez alcanzado `MIN_PLAYERS`, el server entra a fase `Warmup` y espera 15s antes de arrancar el match. Si la headcount baja del mínimo durante el warmup, `runLobbyWarmup()` aborta y el loop vuelve a `Waiting`. Banner muestra "MATCH STARTING · X players ready · starting in Ns" en naranja (`PHASE_COLORS.Warmup`).
- ✅ **MIN_PLAYERS subido**: 2 → 3. Un 1vs1 era trivial; con 3 ya hay tensión real.
- ✅ **MatchStatusSign 3D**: Part en `Workspace.Lobby` pegado a la pared sur (frente al `RulesSign` del norte). Server lo actualiza en vivo vía `updateMatchStatus(text)`: "WAITING FOR PLAYERS · 2/3" / "STARTING IN 12s" / "MATCH IN PROGRESS". Sin RemoteEvent extra — el server modifica el TextLabel server-side y Roblox replica automáticamente.
- ✅ **Fix respawn mid-round** (deuda técnica resuelta): si un activo muere durante el match, `onCharacterAdded` ahora detecta que sigue siendo activo y re-aplica el estado de la fase actual. Si estamos en Playing → `freezeAndAssign` con su angle previo (sigue orbitando sin interrupciones); si estamos en Stopped/Judgement → `thaw()` aplicando el `walkSpeedOverride` y `jumpDisabled` del evento activo.

**Lo que NO se hizo** (postpuesto explícitamente):
- `MAX_PLAYERS_PER_MATCH` — por ahora el cap del Roblox server (`Players.MaxPlayers`, default ~50) maneja eso. Las sillas escalan dinámicamente con N players.
- Multi-place / matchmaking — pertenece a Fase 16, requiere `TeleportService` + DataStore.
- Stands de Robux / Season Pass — pertenece a Fase 15.
- Extraer `EVENTS` a `Events.luau` — sigue siendo solo 4 eventos; postpuesto hasta 6+.

### Fase 12.6 · Decoración con assets del Marketplace — ✅ done (con refactor doloroso)

Esta fase tuvo dos iteraciones. La primera (approach `assets/*.rbxm` + `$path`) terminó
rompiéndose por bugs de Rojo con propiedades binarias del engine. La segunda (approach
`.rbxl` versionado) es la actual. Vale la pena documentar ambas para no repetir el camino.

#### Iteración 1 (deprecada) — `.rbxm` + `$path` ❌

El primer intento: bajar cada asset del Marketplace, guardarlo como `assets/<nombre>.rbxm`,
declararlo en `default.project.json` con `$path`. Para los muebles del lobby, agregarlos
todos en un `Folder` Decor en Studio y hacer Save to File a `assets/lobby-decor.rbxm`.

**Por qué se cayó**: Rojo NO roundtripea bien propiedades binarias del engine (ver Playbook
§3 quirk 6). Específicamente:
- `MaterialVariantSerialized` (texturas PBR de los couches): el asset `8851439806` se
  preservaba en `couch.rbxm` original pero se corrompía a `2035360759` (otro asset random)
  cuando guardabas el lobby-decor entero como Folder agregado. Visualmente: la textura
  linda del Marketplace se reemplazaba por "bloques feos" default.
- `UnionOperation` (CSG): la geometría procedural se perdía al ciclo. Bars del Marketplace
  con Unions aparecían incompletos al recargar.
- `AeroMeshData` y otros blobs binarios: similar.

Diagnóstico definitivo: hacer `Insert from File` directo del `.rbxm` en Studio (sin Rojo)
mostraba el asset OK. Vía Rojo, no. Concluimos: no es bug de Studio Save, es bug de Rojo
deserializing. Y no hay versión más nueva de Rojo que lo arregle — los issues en el repo
de Rojo están marcados "external" (problema upstream de `rbx-dom`).

#### Iteración 2 (actual) — `.rbxl` versionado ✅

Cambio arquitectónico: **todos los assets del Marketplace viven en el `.rbxl` versionado en
git**, no en `.rbxm`. Rojo declara los Folders padre con `$ignoreUnknownInstances: true`
así no toca el contenido, y Ctrl+S en Studio persiste todo al `.rbxl`.

- ✅ **`*.rbxl` removido del `.gitignore`**, ahora se versiona. El `.rbxl` es binario (diffs
  ilegibles), pero clone-and-play funciona y los assets sobreviven intactos.
- ✅ **`assets/` carpeta borrada entera** — ya no se usa nada de filesystem para Marketplace.
- ✅ **`ReplicatedStorage.Templates`** ahora vive en el `.rbxl` (declarado con
  `$ignoreUnknownInstances`). Contiene `Chair`, `DiscoBall`. Ya no están DjBooth y Speaker
  porque se sacaron del arena (decisión de diseño). Para clonar en runtime, el código hace
  `ReplicatedStorage.Templates.X:Clone()` y todas las propiedades llegan intactas.
- ✅ **`Workspace.Lobby.Decor`** vive en el `.rbxl` (declarado con `$ignoreUnknownInstances`).
  Editás visualmente en Studio, Ctrl+S, git commit. Texturas perfectas.
- ✅ **Slot del arena** (`Decor.luau`): único slot `DiscoBall`, posicionado por código desde
  `ARENA_RADIUS / ARENA_WALL_HEIGHT`. Si el template falta, placeholder magenta.

#### Lecciones del refactor (graves)

- ✅ **Save to File de un Folder agregado pierde refs binarias.** Si insistís en `.rbxm`, al
  menos guardá Models individuales (uno por archivo). Pero realmente: para Marketplace
  assets, usá `.rbxl` y olvidá `.rbxm`.

- ✅ **`$ignoreUnknownInstances` NO transfiere ownership al `.rbxl`** (Playbook §3 quirk 7).
  Las Parts inyectadas por Rojo desde el JSON quedan "managed by Rojo" — si las sacás del
  JSON esperando que persistan en el `.rbxl`, se borran de Studio aunque hayas hecho
  Ctrl+S. Solo las Parts que vos modificás o creás explícitamente se persisten. Esto nos
  hizo perder buena parte del lobby shell en una iteración intermedia — recovery: cerrar
  Studio sin guardar y reabrir.

- ✅ **Pivot compensation con `GetBoundingBox`** (`Decor.luau:placeTemplate`): el
  `WorldPivot` de templates del Marketplace está donde sea (depende del creator + cómo lo
  duplicaste/moviste en Studio). En lugar de confiar en eso, el código calcula
  `offset = pivot.Position - bboxCenter.Position` y hace `PivotTo(targetCf + offset)` para
  que el centro geométrico aterrice en el slot. Funciona para cualquier template, no hay
  que pedirle al usuario "Reset Pivot" manualmente.

- ✅ **Esconder templates al startup**: el código clona Chairs al startup pero las posiciona
  recién cuando empieza el match. Si no las ocultabas, aparecían visibles en el CFrame del
  template (que coincidía con el lobby porque ahí las dropeé al importar). Fix:
  `hideAllChairs()` justo después de `cloneChairsFromTemplate()` en el bootstrap.

- ✅ **Bug clave aprendido (lobby decor se desmorona en Play)**: el lobby decor se monta del
  `.rbxl` directamente; si alguna sub-part tiene `Anchored = false`, los Welds legacy de
  los modelos del Marketplace no aguantan y el modelo se "desarma como lego" al Play.
  Fix: `World.setupLobbyDecor()` recorre el Folder y anchora cada BasePart.

- ✅ **Bug aprendido (PlayOnRemove)**: si un Sound tiene `PlayOnRemove = true`, hacer
  `:Destroy()` lo **dispara** en vez de silenciarlo. Setear `PlayOnRemove = false` ANTES de
  destruirlo, o dejarlo vivo con `Volume = 0`.

- ✅ **Convert to MeshPart** para Unions: si tenés que conservar un asset con `UnionOperation`
  y vas a guardarlo a `.rbxm`, en Studio reciente: **Model → Solid Modeling → Convert to
  MeshPart**. Uploadea el mesh a tu cuenta y reemplaza el Union con un MeshPart estable.
  Pero en general: dejá el Union en el `.rbxl` (Approach 4) y evitá el ciclo.

- ✅ **Lección sobre Rojo + Studio**: el server-side code (`Decor.build`, etc.) **no se
  re-ejecuta** cuando Rojo sincroniza un cambio en el filesystem — solo al re-Play.
  Reconectar el plugin actualiza el árbol estático, los Scripts ya corriendo no se
  reinician.

### Fase 12 · Lobby liviano — ✅ done

Sala separada del arena (al sur, a `z = -200`) donde los players spawnean y vuelven entre matches. Reusa todo lo que ya existía (SpawnLocations, freezeAndAssign para el "teleport" al arena vía orbit, `applySpectatorState` para los eliminados, `PlayMusic` RemoteEvent).

- ✅ **Spawn area separada**: `Workspace.Lobby` (Folder) con `Floor/Ceiling/Walls/AmbientLight` formando una sala 80×22×80 centrada en `(0, _, -200)`. Los 8 SpawnLocations se movieron a un anillo de radio 18 dentro del lobby (Roblox respawnea ahí automáticamente).
- ✅ **Teleport implícito al arena**: no hace falta código nuevo — al empezar `Playing`, `freezeAllActives()` ya pone a cada activo en una posición orbital, lo que efectivamente los teletransporta del lobby al arena.
- ✅ **Respawn al lobby al fin del match**: después de `task.wait(POST_MATCH_SECS)`, el server mata a todos los `Humanoid`s sobrevivientes → Roblox los respawnea vía `SpawnLocations` (que ahora viven en el lobby). `matchInProgress = false` en ese momento, así que `applySpectatorState` no los manda al ring del arena.
- ✅ **Decoración** (evolución completa en Fase 12.6): inicialmente sillas clonadas por código → después `lobby-decor.rbxm` Save-to-File → finalmente **`.rbxl` versionado** con muebles dentro de `Workspace.Lobby.Decor` (con `$ignoreUnknownInstances` para que Rojo no los pise). Cada paso fue por dolor real: el primero era frustrante de editar, el segundo perdía texturas PBR. El `RulesSign` y `MatchStatusSign` siguen pegados a las paredes norte/sur.
- ✅ **Música del lobby**: `Config.LOBBY_MUSIC_TRACKS` (array separado del match music, vacío por default — pegá un SoundId del marketplace para activarlo). `playLobbyMusic()` se dispara al entrar a Waiting y a Reset; el cliente solo cambia `Music.SoundId` si difiere del actual (no reset si ya está tocando el mismo).
- ✅ **Counter de players**: SKIP. La PlayerList nativa de Roblox (arriba a la derecha) ya muestra todos los players con sus nombres; el banner ya muestra "WAITING FOR PLAYERS X/MIN_PLAYERS" durante Waiting. No vale la pena un counter custom encima — sería redundante.

### Fase 13 · Persistencia (DataStore) (siguiente recomendado) — ⏳ pending

Hacer que ganar/perder importe. Sin esto el juego es un loop infinito sin progresión.

- ⏳ **DataStore service**: clave `player.UserId` → tabla con `matchesPlayed`, `matchesWon`, `currentStreak`, `bestStreak`, `firstSeen`.
- ⏳ **Leaderstats** sidebar (lo que Roblox muestra automáticamente arriba a la derecha): `Wins`, `Streak`.
- ⏳ **Top 10 post-match**: panel que aparece después del Winner con los 10 mejores del servidor por wins.
- ⏳ **Achievement-like flags** ("First Win", "5-Streak", "Survived 10 matches"): badges visuales chiquitos.
- ⏳ Cuidado: `pcall` envolviendo todas las DataStore calls (pueden throw si Roblox está caído), throttling, retry con backoff.

### Fase 14 · Más eventos — ⏳ pending

Cuando lo anterior esté, expandir el sistema de eventos. Cada nuevo evento son ~30 líneas en `init.server.luau`.

Ideas (en orden de complejidad ascendente):

- ⏳ **`reverseControls`**: invertir movement del cliente. Server emite el evento, cliente intercepta `Humanoid.MoveDirection` y lo invierte. Difícil porque pelea con el PlayerModule de Roblox.
- ⏳ **`lavaPits`**: zonas peligrosas en el track que matan instantáneamente (server polling como mud, pero hace `humanoid.Health = 0`). Visualmente parts rojo brillante.
- ⏳ **`speedBoost`**: WalkSpeed alta (~24) sin inercia. Casi opuesto de mud — corren rapidísimo pero sin sliding.
- ⏳ **`shrinkingChairs`**: durante el grace, cada N segundos una silla se vuelve `Disabled=true` aleatoriamente. Acelera la decisión.
- ⏳ **`teleportSit`**: cuando alguien se sienta, lo teletransporta a un punto random del mapa, tiene que correr de vuelta. Caótico.
- ⏳ **`darknessAndSpotlight`**: combina flickering con una luz que sigue al jugador. Solo ves lo que está cerca de vos.
- ⏳ **Combinables**: dos eventos a la vez en rondas tardías ("ice + fog" — patinar a ciegas).

### Fase 15 · Monetización y servers privados — ⏳ pending

Solo arrancar esto cuando haya jugadores reales midiendo retención.

- ⏳ **Private/VIP servers**: cero código — `Home → Game Settings → Permissions → toggle "Private Server"`. Roblox lo expone, podés cobrar Robux por crear uno.
- ⏳ **GamePass** "VIP" (50-100 Robux): nombre dorado en leaderstats, partículas custom al sentarse, prioridad de spawn, etc. `MarketplaceService:UserOwnsGamePassAsync()`.
- ⏳ **DevProducts** (consumibles): "Skip eliminación 1 vez por match" (200 Robux), "Doble ganancia de stats por match" (50 Robux).
- ⏳ **Skin shop**: cosmetics no-pay-to-win. Sombreros, colores de personaje, chair custom durante el sit, etc.
- ⏳ Setup analytics: `AnalyticsService` para trackear cuántos players completan un match, cuántos se van pre-match, qué evento les hace cerrar.

### Fase 16 · Infraestructura cuando crezca — ⏳ pending

Solo necesario si llegamos a 50+ servidores concurrentes o queremos UX más pulida.

- ⏳ **Multi-place**: separar Lobby place (sociabilizar, comprar cosmetics) del Match place (el juego). `TeleportService` entre ellos. Ventaja: lobby tiene capacity de 50 mientras matches mantienen 8.
- ⏳ **Cross-server leaderboards**: `MessagingService` + DataStore global para top 100 worldwide.
- ⏳ **Matchmaking**: queue para emparejar players de skill similar (requiere tracking de skill, ELO o similar).
- ⏳ **Mobile-friendly UI**: botón táctil grande "E to sit" en lugar de teclado. Detectar input device con `UserInputService.TouchEnabled`.
- ⏳ **Más mapas/temas**: variantes del arena con paleta distinta (Halloween rojo-naranja, Neón cyberpunk, lava infernal, jardín tóxico). Selección random por match.

### Fase 17 · Accesibilidad y QoL — ⏳ pending

- ⏳ **Settings menu**: volumen, opciones daltónicas, sensibilidad de cámara
- ⏳ **Texto siempre legible**: TextScaled ya está, pero verificar contraste en cada fase
- ⏳ **Replay de muerte**: bird's eye view del momento de eliminación
- ⏳ **Spectator camera**: el modo espectador podría tener cámara libre o cycle entre players activos en lugar de quedarse parado mirando el centro

---

## Deuda técnica conocida (no urgente)

Stuff que vimos en la auditoría pero no amerita arreglar hoy. Anotar acá para no olvidar:

1. ~~**Player respawn mid-round**~~ ✅ resuelto en Fase 12.5: `onCharacterAdded` ahora re-aplica el estado del player si sigue siendo activo. Si estamos en Playing, vuelve a la órbita con su angle previo; si estamos en Stopped/Judgement, recibe el `walkSpeedOverride` + `jumpDisabled` correcto.

2. ~~**Bloque `EVENTS` (~200 líneas) en `init.server.luau`**~~ ✅ resuelto: extraído a `src/server/Events.luau` como una factory `create(ctx)`. La "API de contexto" pasa tablas estables por referencia (`activePlayers`, `lockedToChair` — init las muta con `table.clear`, nunca reasigna) y los escalares que `thaw()` lee (`walkSpeedOverride`, `jumpDisabled`) vía setters, manteniendo init como source of truth.

### Arquitectura modular (refactor hecho)

El código está partido en módulos por responsabilidad (el `init` orquesta, la lógica vive en módulos):

- **`src/server/init.server.luau`** (~890 líneas): game loop (state machine), sit lock, orbit, spectator, eliminación.
- **`src/server/Config.luau`**: constantes tunables (fuente única). `init` crea aliases locales.
- **`src/server/Events.luau`**: definiciones de eventos. Factory `create(ctx)` → `{ definitions, keys }`. `runEventHook`/`pickRandomEvent` quedan en init (referencian `activeEvent`).
- **`src/server/World.luau`**: construcción de escena estática. Fachada `World.build()` (arena shell desde `ARENA_RADIUS` + lobby decor + signs) y `World.updateMatchStatus(text)`.
- **`src/client/init.client.luau`** (~125 líneas): bridges RemoteEvents → audio, SFX, fog (efectos no-UI).
- **`src/client/Hud.luau`**: toda la UI + su lógica. Fachada `Hud.applyState(payload)` y `Hud.flashEliminated()`.

Pendiente si crece: un `ChairService` (sillas + lógica de sit están acopladas en init) y un `GameState` (centralizar `activePlayers`/`lockedToChair`/etc. detrás de una API en vez de upvalues sueltos). No urgente.

---

## Decisiones tomadas que vale la pena recordar

### Por qué Rojo + `.rbxl` versionado (no Studio puro, tampoco Rojo puro)

Rojo mantiene código y configuración primitiva como texto plano versionable (JSON + Luau).
Pero **Rojo no roundtripea bien Marketplace assets con propiedades binarias** (PBR,
MaterialVariant, CSG, AeroMeshData) — esos viven en el `.rbxl` versionado. Hybrid approach.
Ver Playbook §3 (quirks 6 y 7) + §4 para la decisión completa de qué vive dónde.

### Sync de una sola vía (filesystem → Studio)

Por default Rojo es unidireccional. Two-way sync es frágil, lo evitamos. Convención:
- **Código y geometría primitiva** → editás en filesystem (Rojo sync a Studio).
- **Marketplace assets + decor visual** → editás en Studio (Ctrl+S al `.rbxl`).

### Sillas: Model + Seat + ProximityPrompt + WeldConstraint

- `Model` permite mover toda la silla con `PivotTo` (seat + respaldo + patas + mesh juntos).
- `Seat.Disabled = true` para siempre — evita auto-sit al tocar.
- ProximityPrompt con KeyCode E es el único trigger.
- `chair:Sit(humanoid)` fuerza el sit (ignora Disabled), engine crea la animación.
- WeldConstraint encima del SeatWeld del engine como respaldo físico.
- `lockedToChair` es la source-of-truth — `Seat.Occupant` no es confiable (el engine lo limpia al intentar saltar).

### Server/client split

Server: state machine, autoridad de quién está activo/sentado/eliminado, orbit (con `SetNetworkOwner(nil)`), spawn/colocación de cosas, broadcast de StateChanged, eliminate, freeze del veredicto, polling autoritativo (mud). Client: UI, música, **física del hielo** (sin lag de red), tracking de evento activo. Detalles en `~/.claude/projects/.../memory/server_client_split.md`.

### `JumpHeight = 0` además de `JumpPower = 0`

Roblox moderno usa `JumpHeight` (default 7.2), no `JumpPower`. Setear solo `JumpPower=0` no impide saltar. Para freezar el salto hay que setear los dos + `humanoid:SetStateEnabled(Jumping, false)` + `AutoJumpEnabled = false` + listener en `Sit` que re-sienta si flippea.

### Sillas declaradas en JSON, hijos clonados desde `ReplicatedStorage.Templates`

Carpeta `Workspace.Chairs` vacía en JSON. El template `Chair` vive en
`ReplicatedStorage.Templates` (en el `.rbxl` versionado, NO en filesystem `.rbxm`). Server
clonea N veces al startup (`cloneChairsFromTemplate`), las oculta inmediatamente con
`hideAllChairs()`, y el game loop las posiciona en el arena cuando empieza el match.

**No usamos `InsertService:LoadAsset`** porque era HTTP en cada server start y depende de
permission del asset. **Tampoco usamos `assets/chair.rbxm`** porque Rojo no roundtripea
correctamente las propiedades binarias de los Marketplace assets (Playbook §3 quirk 6).
Vivir en el `.rbxl` da fidelidad visual completa y clone-and-play sin HTTP.

### Lighting Technology = `ShadowMap`

`Voxel` (default original) tarda en cargar la grilla. `ShadowMap` es real-time y aparece al instante. `Future` sería mejor calidad (PBR) pero más pesado — quizás más adelante.

---

## Configuración tunable

Todas las constantes viven en **`src/server/Config.luau`**. El archivo `init.server.luau` hace `local Config = require(script.Config)` y se crea aliases locales (`local MIN_PLAYERS = Config.MIN_PLAYERS`, etc.) para que el resto del código quede legible. Si querés cambiar el balance del juego, editás solo `Config.luau`.

Las secciones del módulo:

- **Match cadence**: `MIN_PLAYERS`, `LOBBY_WARMUP_SECS`, `INTERMISSION_SECS`, `MUSIC_MIN_SECS/MAX_SECS`, `SIT_GRACE_SECS`, `POST_MATCH_SECS`, `VERDICT_PAUSE_SECS`
- **Arena geometry (fuente única de verdad)**: `ARENA_RADIUS` + factores. **Cambiar `ARENA_RADIUS` reescala TODO el arena de un saque** — paredes, techo, track, órbita, dispersión de sillas, pillars, neon strips, y hasta el spread/count del mud. El resto de la geometría se computa de ahí (`ARENA_TRACK_RADIUS`, `ARENA_PILLAR_RADIUS`, `ARENA_NEON_RADIUS`, `ORBIT_RADIUS`, `CHAIR_RADIUS_MAX`...). El shell del arena se **construye en código** (`buildArena()` en `init.server.luau`) porque `default.project.json` no puede computar relaciones — ver decisión abajo.
- **Chair placement**: `CHAIR_COUNT`, `CHAIR_RADIUS_MIN`, `CHAIR_MIN_SEPARATION`, `CHAIR_PLACEMENT_ATTEMPTS` (`CHAIR_RADIUS_MAX` es derivado del `ARENA_RADIUS`)
- **Orbit**: `ORBIT_ANGULAR_SPEED`, `ORBIT_HEIGHT` (`ORBIT_RADIUS` es derivado)
- **Movement defaults**: `DEFAULT_WALK_SPEED`, `DEFAULT_JUMP_POWER`, `DEFAULT_JUMP_HEIGHT`
- **Sit**: `SIT_PROMPT_DISTANCE`
- **Spectator**: `SPECTATOR_RING_OFFSET_MIN/MAX`, `SPECTATOR_HEIGHT`
- **Visual**: `DEFAULT_TRACK_COLOR`
- **Audio**: `MUSIC_TRACKS`, `LOBBY_MUSIC_TRACKS`, `STOP_SFX_ID`, `ELIMINATE_SFX_ID` (+ volúmenes)
- **Events**: `FORCE_EVENT` (debug), `ICE_TRACK_COLOR`, `ICE_WALK_SPEED`, `SLOW_FLOOR_WALK_SPEED`, `MUD_PATCH_*` (count/ring derivados del `ORBIT_RADIUS`)

### Por qué el arena se construye en código y el lobby está mixto

El arena **se reescala desde un solo número** (`ARENA_RADIUS`), y JSON es estático (no
computa). Así que `World.buildArena()` arma Track + paredes + techo + pillars + neon +
center light derivados de las constantes, todo bajo `Workspace.Arena.Shell`. El **arena
decor** (DiscoBall) lo arma `Decor.build()` posicionando templates en `Workspace.Arena.Decor`.

El **lobby** es mixto:
- **Shell primitivo** (Walls, NeonStrips, Lights, RulesSign): en JSON, porque es fijo y
  diffeable como texto.
- **Decor + signs interactivos + SpawnPads + Floor/Ceiling editados**: en el `.rbxl`,
  dentro de `Workspace.Lobby.Decor` y otros sub-folders. Editás visualmente con Ctrl+S.
- Los `SurfaceGui` de los signs se arman en código (workaround del quirk de UDim2 en JSON).

## Idle entre matches

Cuando termina un match, el server hace cleanup completo (`runEventHook("onRoundEnd")`, `releaseSits`, `thawAllSpectators`, `hideAllChairs`), espera `POST_MATCH_SECS`, y vuelve al loop. Si no hay suficientes jugadores, queda en fase Waiting hasta que llegan. Si todos se desconectan a mitad de partida, `Players.PlayerRemoving → cleanupPlayer` limpia `activePlayers` y el `while countActive() > 1` sale solo.

---

## Estado actual y próximos pasos concretos (snapshot al cambiar de PC)

### ✅ Lo que está terminado y funcionando
- Core completo: state machine (Waiting → Warmup → Intermission → Playing → Stopped → Judgement → Winner → Reset), sit lock, orbit forzado, spectator ring, eliminación.
- 4 eventos de ronda: `flickering`, `ice`, `mud`, `fog`. Sistema extensible (factory con contexto en `Events.luau`).
- UI completa: banner, countdown, eliminated overlay, welcome modal — todo en `Hud.luau`.
- Lobby con sala separada (sub-folders Shell, Lights, Signs, SpawnPads, Decor), RulesSign + MatchStatusSign con SurfaceGui dinámico, partículas ambientales.
- Arena parametrizada bajo `Workspace.Arena.Shell` (todo deriva de `ARENA_RADIUS = 100`); decor del arena en `Workspace.Arena.Decor` (sólo DiscoBall).
- Anillo de neón + barrera invisible en el borde del playfield (activos no pueden salir).
- Refactor modular: `init.server` 1416 → 888 líneas; `init.client` 452 → 124 líneas. Módulos: `World`, `Events`, `Decor`, `Hud`, `Config`.
- **Migración a `.rbxl` versionado**: todos los Marketplace assets viven ahí (Templates + lobby decor). Carpeta `assets/` borrada. Rojo declara los Folders padre con `$ignoreUnknownInstances: true`. Pivot compensation en `Decor.placeTemplate`, anchor pass en `World.setupLobbyDecor`, `hideAllChairs()` al startup, cleanup defensivo de paths viejos.

### 🔄 In progress / loop continuo (no urgente)
- **Seguir decorando el lobby**: en Studio, drag-and-drop muebles del Toolbox a `Workspace.Lobby.Decor`. Ctrl+S, git commit. Listo.
- **Llenar SoundIds vacíos**: en `Config.luau`, `STOP_SFX_ID`, `ELIMINATE_SFX_ID`, `LOBBY_MUSIC_TRACKS = {}`. Cuando subas/elijas assets de audio del Marketplace, pegás los IDs.

### ⏳ Pendiente (siguiente decisión cuando retomes)
1. **Fase 13 · DataStore / persistencia** — wins, streak, leaderstats sidebar. Ganar empieza a importar.
2. **Fase 14 · Más eventos** — `reverseControls`, `lavaPits`, `speedBoost`, `shrinkingChairs`, etc. Cada uno ~30 líneas en `Events.luau`.
3. **Pulir lo existente** — animaciones del winner, anuncio del evento al empezar, ajustes finos visuales.

Las fases 15 (monetización), 16 (multi-place), 17 (accesibilidad) son más a futuro — sólo cuando haya retención real.

### Cómo retomar en una PC nueva (checklist)
1. `git clone` del repo + `cd` adentro. Como el `.rbxl` está versionado, viene todo incluido — no hay que conseguir assets aparte.
2. `rokit install` (instala Rojo, StyLua, Selene desde `rokit.toml`).
3. `rojo serve` desde la raíz (dejá la terminal abierta).
4. En Studio, instalar/abrir el plugin de Rojo, abrir `infernal-chairs.rbxl` (doble-click).
5. En el plugin Rojo de Studio → **Connect** a `localhost:34872`.
6. Verificar el árbol: `Workspace.Lobby.Decor` con tus muebles, `Workspace.Arena.Shell` con paredes, `ReplicatedStorage.Templates` con Chair y DiscoBall.
7. **F5** (Play) para probar.
8. Para hacer cambios: mirá la tabla "Loop diario con Rojo" en el Quick start arriba.
