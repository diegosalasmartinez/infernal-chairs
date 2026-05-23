# Dev Plan — Infernal Chairs

Roadmap completo del juego, dividido en fases. Cada fase tiene un objetivo claro y subtareas trackeables.

## Visión

Un juego de sillas musicales en Roblox con un giro: **los jugadores no controlan su movimiento mientras suena la música**. Orbitan automáticamente alrededor de las sillas. Cuando para la música, recuperan el control y corren a sentarse. El que no alcanza silla queda eliminado. Una silla menos cada ronda hasta que queda 1 ganador.

El nombre "Infernal" viene de esa pérdida de control que vuelve la mecánica más estresante que las sillas musicales tradicionales.

---

## Estado por fase

Leyenda: ✅ done · 🔄 in progress · ⏳ pending

### Fase 0 · Tooling — ✅ done

- ✅ `rokit init` y agregar Rojo, StyLua, Selene como dependencias del proyecto (versionadas en `rokit.toml`)
- ✅ Verificar que las 3 herramientas son ejecutables

### Fase 1 · Estructura y sync con Studio — ✅ done

- ✅ `rojo init` → genera `default.project.json` + jerarquía estándar en `src/`
- ✅ Instalar plugin de Rojo en Studio (`rojo plugin install`)
- ✅ Conectar Studio a `rojo serve` y validar sync bidireccional en vivo

### Fase 2 · MVP jugable — ✅ done

- ✅ Mapa: Baseplate, 4 sillas (Seats coloreados), SpawnLocation
- ✅ State machine en server (`Waiting → Intermission → Playing → Stopped → Eliminate → Winner → Reset`)
- ✅ Audio: `Sound` en `SoundService`, server dispara `PlayMusic`/`StopMusic` vía RemoteEvent, cliente toca/para localmente
- ✅ Detección con `Seat.Occupant` desde server (sin trust del cliente)
- ✅ Eliminación real: kill character (`Humanoid.Health = 0`), tracking de `activePlayers`
- ✅ Detección de ganador (cuando queda 1 activo)
- ✅ Sillas se ocultan según cantidad de jugadores activos (`visibleChairs = activos - 1`)
- ✅ Loop entre matches (post-match wait, reset, esperar nuevos jugadores)

### Fase 3 · Posicionamiento dinámico — ✅ done

- ✅ Sillas aleatorias cada ronda dentro de radio 0–10 alrededor del origen
- ✅ Rejection sampling para garantizar separación mínima (5 studs)
- ✅ Sillas nacen ocultas desde `default.project.json` (sin flash de "default position")
- ✅ Posicionar primero, mostrar después (orden importa)
- ✅ Anillo de 8 SpawnLocations en circunferencia de radio 25 (los jugadores spawn-ean alrededor del cluster de sillas)

### Fase 4 · UI mínima — ✅ done

- ✅ Banner superior con estado actual + subtexto (creado programáticamente, sin archivos UI nuevos)
- ✅ `ScreenGui.ResetOnSpawn = false` para que la UI sobreviva la muerte
- ✅ Color del texto cambia según fase (waiting=gris, playing=verde, stopped=amarillo, winner=oro)
- ✅ Overlay rojo translúcido "ELIMINATED" cuando te eliminan (auto-oculta a los 3s)
- ✅ Nuevos RemoteEvents: `StateChanged` (broadcast) y `YouEliminated` (per-player)

---

## Próximos pasos

### Fase 5 · Rotación forzada — ⏳ pending

**Objetivo**: implementar la mecánica central que da nombre al juego. Mientras suena música los jugadores no se controlan; orbitan automáticamente.

Plan tentativo:

- 🔄 Durante fase **Playing** (música on):
  - Server pone `Humanoid.WalkSpeed = 0` y `JumpPower = 0` a todos los activos
  - Server arranca un loop (`task.spawn` con `RunService.Heartbeat`) que cada frame mueve el `CFrame` de cada personaje en órbita circular alrededor del centro de las sillas
  - Radio de órbita constante (~15 studs), velocidad angular constante (~0.5 rad/s)
  - Sentido de rotación: fijo, o random por ronda
  - Los personajes miran hacia el centro (o hacia adelante en la órbita)
- 🔄 Al entrar a fase **Stopped**:
  - Server detiene el loop de rotación
  - Restaura `WalkSpeed = 16` y `JumpPower = 50`
  - Jugadores ahora corren libres hacia las sillas
- 🔄 Cuando alguien se sienta (escuchar cambio de `Seat.Occupant`):
  - Bloquear el "stand up": cuando `Humanoid.Sit` cambia a `false`, volverlo a poner `true`
  - Alternativa más robusta: `WeldConstraint` entre `HumanoidRootPart` y el `Seat`
- 🔄 Al iniciar la próxima ronda:
  - Liberar a los que estaban sentados (`humanoid.Sit = false` y/o quitar weld)
  - Teletransportar a cada activo a su posición de órbita inicial

Riesgos a investigar:
- Movimiento de `CFrame` desde server puede chocar con la física del Humanoid (si el personaje está "andando" físicamente, mover su CFrame puede causar jitter)
- Posible alternativa: usar una `Part` rotante invisible como "plataforma" y parentar cada personaje a ella (más complejo pero físicamente limpio)

### Fase 6 · Polish — ⏳ pending

- ⏳ SFX en el momento del stop (sonido corto de "alarma" cuando para la música)
- ⏳ Ganador: confeti / explosión de partículas / fanfarria
- ⏳ Lobby loop pulido: mensaje de bienvenida, contador de "siguiente match en Xs"
- ⏳ Sonido de eliminación (un "bzzt" cuando te marcan OUT)
- ⏳ Mejora visual de las sillas (respaldo, patas, o modelo del Toolbox)
- ⏳ Mejora visual del mapa (skybox, lighting, decoración del Baseplate)

### Fase 7 · Cosas futuras (no comprometidas) — ⏳ pending

- ⏳ Stats persistentes: matches ganados, vegas jugadas, mejor racha (usar `DataStoreService`)
- ⏳ Cosmetics: skins de personaje desbloqueables
- ⏳ Matchmaking: lobby + matches separados (usar `TeleportService` y `MessagingService`)
- ⏳ Más mapas / temas (Halloween, lava, espacio, etc.)
- ⏳ Modos: equipos, eliminación rápida, doble silla
- ⏳ Mejor música: rotación de tracks aleatoria, beat-sync con animaciones
- ⏳ Mobile-friendly UI (TextScaled ya ayuda, pero hay que probar)

---

## Decisiones tomadas que vale la pena recordar

### Por qué Rojo y no Studio puro

Studio es un editor IDE-like, pero versionar `.rbxl` (binario) es un infierno: no hay diffs útiles en git, merges imposibles, y el archivo crece sin control. Rojo mantiene la **fuente de verdad** en archivos de texto (JSON + Luau) que sí versionan bien.

### Sync de una sola vía (VS Code → Studio)

Por default Rojo es unidireccional. Existe "Two-Way Sync" experimental pero es frágil y la comunidad lo evita. Convención: VS Code edita, Studio renderiza/testea. Si queremos diseñar visualmente algo complejo en Studio, usamos `rojo build` o "Sync from Studio" puntual.

### Sillas como `Seat` y no `Part`

`Seat` es una subclase de `Part` que ya viene con detección automática: cuando un Humanoid lo toca, el motor lo sienta y expone `Seat.Occupant` (el Humanoid). Sin código de detección manual, sin trust del cliente.

### Sillas declaradas en JSON, no creadas en runtime

Pros de runtime: máxima flexibilidad. Pros de JSON: declarativo, sin race conditions de carga, fácil de leer. Para 4 sillas fijas (que solo cambian posición / visibilidad), JSON gana. Cuando queramos N sillas variables al inicio, migramos a runtime.

### Por qué nacen ocultas desde el JSON

Si arrancaran visibles en posición default, los jugadores las verían en posiciones predecibles antes de que el server las randomice. Naciendo invisibles, el server las posiciona y luego las muestra — sin flash.

### Por qué 8 SpawnLocations en círculo

Roblox respawn-ea en un `SpawnLocation` random cuando hay varios. Con 8 spawn pads en perímetro y sillas al centro, la geometría del juego refuerza el flujo: spawn afuera → correr al centro → sentarte.

### Eliminación = matar el personaje + sacar del set `activePlayers`

`Humanoid.Health = 0` causa muerte visual + respawn automático. El jugador sigue conectado, pero como ya no está en `activePlayers`, no cuenta para checks. Reaparece como espectador.

---

## Configuración tunable

Todo en `src/server/init.server.luau` arriba del todo:

```lua
local MIN_PLAYERS = 2              -- mínimo para arrancar un match
local INTERMISSION_SECS = 5        -- pausa entre rondas
local MUSIC_MIN_SECS = 5           -- música duración min
local MUSIC_MAX_SECS = 12          -- música duración max
local SIT_GRACE_SECS = 3           -- ventana para sentarse tras stop
local POST_MATCH_SECS = 6          -- pausa entre matches

local CHAIR_RADIUS_MIN = 0         -- distancia min de silla al origen
local CHAIR_RADIUS_MAX = 10        -- distancia max
local CHAIR_MIN_SEPARATION = 5     -- distancia min entre sillas
local CHAIR_PLACEMENT_ATTEMPTS = 100  -- intentos de rejection sampling
```

Ajustar estos cambia la cadencia del juego sin tocar lógica.

## Idle entre matches

Cuando termina un match, el server hace `hideAllChairs()`, espera `POST_MATCH_SECS`, y vuelve al loop. Si no hay suficientes jugadores, queda en fase Waiting hasta que llegan. Si todos se desconectan a mitad de partida, `Players.PlayerRemoving` limpia `activePlayers` y el `while countActive() > 1` sale solo.
