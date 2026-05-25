# Dev Plan — Infernal Chairs

Roadmap completo del juego, dividido en fases. Cada fase tiene un objetivo claro y subtareas trackeables.

## Visión

Un juego de sillas musicales en Roblox con un giro: **los jugadores no controlan su movimiento mientras suena la música**. Orbitan automáticamente alrededor de las sillas. Cuando para la música, recuperan el control y corren a sentarse. El que no alcanza silla queda eliminado. Una silla menos cada ronda hasta que queda 1 ganador. A partir de la ronda 2, cada ronda tiene un **evento** que cambia las reglas (hielo, lodo, luces intermitentes, niebla…).

El nombre "Infernal" viene de esa pérdida de control que vuelve la mecánica más estresante que las sillas musicales tradicionales.

## Quick start para una sesión nueva

Si estás retomando este proyecto desde contexto cero:

1. **Lee este file de arriba a abajo** — refleja el estado real del código y el roadmap.
2. **Mira las memorias** en `~/.claude/projects/-Users-diegosalas-Documents-projects-infernal-chairs/memory/` — capturan los aprendizajes técnicos que no son obvios mirando el código (Rojo quirks, server/client split, FrictionWeight, marketplace policy).
3. **El código vivo está en**:
   - `src/server/init.server.luau` — state machine, orbit, sit, spectator, eventos
   - `src/server/Config.luau` — todas las constantes tunables
   - `src/client/init.client.luau` — UI (banner, countdown, overlay) + música
   - `default.project.json` — declaración del mapa (Baseplate, Track, Room, Spawns)
   - `assets/chair.rbxm` — modelo de silla del Marketplace bundled
4. **Para jugar**: `rojo serve` desde la raíz, plugin Rojo en Studio → Connect, abrir el `.rbxl`, F5.
5. **Próximo paso recomendado**: ver sección [Próximos pasos](#próximos-pasos--orden-recomendado) más abajo. Hoy lo más alto en prioridad es **Fase 10 (Polish)** porque el core jugable está completo.

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

- ✅ `Workspace.Room`: Ceiling (Y=30) + 4 paredes (X/Z = ±70), `SmoothPlastic` color púrpura oscuro
- ✅ `Lighting`: `ShadowMap` technology (mejor que Voxel, carga instantánea)
- ✅ `Atmosphere` con haze sutil
- ✅ `CenterLight`: PointLight en (0, 25, 0) con Range 80, ilumina toda la pista
- ✅ Asset de silla cargado desde `assets/chair.rbxm` vía Rojo `$path` (sin HTTP runtime, todo bundled)
- ✅ Track más grande (radio 54), spawns alineados al borde de la órbita
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

### Fase 10 · Polish (siguiente recomendado) — ⏳ pending

Pequeños toques que multiplican la sensación de "juego serio". Cada uno son 15-30 min de trabajo + buscar/subir el asset de audio.

- ⏳ **SFX del stop** — sonido corto de "alarma/sirena" justo cuando para la música. Cliente lo dispara desde el `StopMusic.OnClientEvent`. Asset: Marketplace audio o sube tu propio mp3 corto.
- ⏳ **SFX de eliminación** — "bzzt" o "game over chime" cuando recibís `YouEliminated`. Sonido per-client en `YouEliminated.OnClientEvent`.
- ⏳ **Partículas del ganador** — `ParticleEmitter` adjunto al `HumanoidRootPart` del ganador durante la fase `Winner`. Confeti / chispas doradas.
- ⏳ **Animación del banner del evento** — cuando aparece "★ EVENT NAME", que el banner haga un punch/zoom + cambio de color brusco para que sea evidente que cambió el juego.
- ⏳ **Música rotativa** — array de `SoundId`s, cada match elige uno random. Sin esto el track se repite y cansa.
- ⏳ **Lobby loop pulido** — countdown grande "next match in Xs" entre matches en lugar del texto chiquito actual.

### Fase 11 · Tutorial / Onboarding — ⏳ pending

La primera partida es muy confusa sin contexto. Necesitamos que un jugador nuevo entienda las reglas en los primeros 30 segundos.

- ⏳ **Overlay one-time** la primera vez que un player joinea: "Press E to sit near a chair when music stops" + "You can't control yourself during music" + "Last to sit gets eliminated". Almacenar el flag en DataStore para no mostrar de nuevo.
- ⏳ **Tooltip persistente** durante la fase `Stopped`: ícono grande "E" arriba a la izquierda, recordatorio visible.
- ⏳ **Sign in lobby** (físico, modelo 3D) con resumen de reglas para players que están esperando.

### Fase 12 · Lobby liviano — ⏳ pending

Mientras se espera que entren players (fase `Waiting`), darles algo que hacer / mirar.

- ⏳ **Spawn area separada del arena**: una sala chica al lado de la sala principal con música ambiente más relajada. Los players spawn-ean ahí en `Waiting` y se teletransportan al arena cuando empieza el match.
- ⏳ **Decoración del lobby**: signs, espejos, sillas decorativas (no las del juego), props.
- ⏳ **Counter visible** "Players: 3/2" más grande, no solo el banner.
- ⏳ Música distinta en lobby vs match (más chill).

### Fase 13 · Persistencia (DataStore) — ⏳ pending

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

1. **Player respawn mid-round**: si un jugador muere/respawnea mientras está activo (no eliminado), el nuevo character no recibe `SetNetworkOwner(nil)` ni la WalkSpeed correcta para el evento activo. En la práctica esto solo pasa si algo externo (caída, glitch) los mata — los activos están freezeados durante orbit y locked durante sit. Fix: re-aplicar el estado del player en `onCharacterAdded` si es activo.

2. **Bloque `EVENTS` (~200 líneas) en `init.server.luau`**: cuando lleguemos a 6+ eventos vale la pena moverlo a `src/server/Events.luau`. Por ahora se queda en el archivo principal porque los eventos toman closure sobre mucho estado (activePlayers, lockedToChair, eventState, walkSpeedOverride, jumpDisabled, getCharacterParts…) y extraerlo requiere diseñar una API de contexto. ~~Constantes mezcladas~~ ✅ resuelto con `Config.luau`.

---

## Decisiones tomadas que vale la pena recordar

### Por qué Rojo y no Studio puro

Studio no versiona bien (`.rbxl` es binario). Rojo mantiene la fuente de verdad en archivos de texto (JSON + Luau).

### Sync de una sola vía (filesystem → Studio)

Por default Rojo es unidireccional. Two-way sync es frágil, lo evitamos. Convención: el código edita, Studio renderiza.

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

### Sillas declaradas en JSON, hijos cargados desde `.rbxm`

Carpeta `Chairs` vacía en JSON. El template viene de `assets/chair.rbxm` cargado por Rojo en `ReplicatedStorage.Templates.Chair`. Server clonea 4 veces al startup. **No usamos `InsertService:LoadAsset`** porque era HTTP cada server start — el .rbxm bundled es instantáneo y no depende de permisos del asset.

### Lighting Technology = `ShadowMap`

`Voxel` (default original) tarda en cargar la grilla. `ShadowMap` es real-time y aparece al instante. `Future` sería mejor calidad (PBR) pero más pesado — quizás más adelante.

---

## Configuración tunable

Todas las constantes viven en **`src/server/Config.luau`**. El archivo `init.server.luau` hace `local Config = require(script.Config)` y se crea aliases locales (`local MIN_PLAYERS = Config.MIN_PLAYERS`, etc.) para que el resto del código quede legible. Si querés cambiar el balance del juego, editás solo `Config.luau`.

Las secciones del módulo:

- **Match cadence**: `MIN_PLAYERS`, `INTERMISSION_SECS`, `MUSIC_MIN_SECS/MAX_SECS`, `SIT_GRACE_SECS`, `POST_MATCH_SECS`, `VERDICT_PAUSE_SECS`
- **Chair placement**: `CHAIR_COUNT`, `CHAIR_RADIUS_MIN/MAX`, `CHAIR_MIN_SEPARATION`, `CHAIR_PLACEMENT_ATTEMPTS`
- **Orbit**: `ORBIT_RADIUS`, `ORBIT_ANGULAR_SPEED`, `ORBIT_HEIGHT`
- **Movement defaults**: `DEFAULT_WALK_SPEED`, `DEFAULT_JUMP_POWER`, `DEFAULT_JUMP_HEIGHT`
- **Sit**: `SIT_PROMPT_DISTANCE`
- **Spectator**: `SPECTATOR_RING_OFFSET_MIN/MAX`, `SPECTATOR_HEIGHT`
- **Visual**: `DEFAULT_TRACK_COLOR`
- **Events**: `ICE_TRACK_COLOR`, `ICE_WALK_SPEED`, `SLOW_FLOOR_WALK_SPEED`, `MUD_PATCH_*`

## Idle entre matches

Cuando termina un match, el server hace cleanup completo (`runEventHook("onRoundEnd")`, `releaseSits`, `thawAllSpectators`, `hideAllChairs`), espera `POST_MATCH_SECS`, y vuelve al loop. Si no hay suficientes jugadores, queda en fase Waiting hasta que llegan. Si todos se desconectan a mitad de partida, `Players.PlayerRemoving → cleanupPlayer` limpia `activePlayers` y el `while countActive() > 1` sale solo.
