# Infernal Chairs

Juego de **sillas musicales** en Roblox, con un giro: los jugadores no controlan su movimiento mientras suena la música — orbitan automáticamente alrededor de las sillas. Cuando para la música, recuperan el control y corren a sentarse. Quien no alcanza silla queda eliminado. Cada ronda 2+ tiene un **evento** que modifica las reglas (hielo, lodo, niebla, luces intermitentes).

> Estado actual: jugable end-to-end. Core completo (state machine, sit lock, orbit, spectator, eliminación, 4 eventos), lobby con muebles, arena parametrizado, UI completa. Próximos pasos: persistencia (DataStore) y más eventos. Ver [DEV_PLAN.md](DEV_PLAN.md) para roadmap completo y [ROBLOX_PLAYBOOK.md](ROBLOX_PLAYBOOK.md) para lecciones reutilizables.

## Stack

| Herramienta | Para qué |
|---|---|
| **[Rokit](https://github.com/rojo-rbx/rokit)** | Gestor de versiones de herramientas (como `package.json` pero para CLIs). Define qué versión de Rojo/StyLua/Selene usa el proyecto. |
| **[Rojo](https://rojo.space)** | Sincroniza carpeta local ↔ Roblox Studio en vivo. Permite usar VS Code como editor principal. |
| **[StyLua](https://github.com/JohnnyMorganz/StyLua)** | Formateador de código Luau (opinionado, sin discusión). |
| **[Selene](https://github.com/Kampfkarren/selene)** | Linter para Luau. |
| **Roblox Studio** | El editor / runtime del juego. Necesario para correr y testear. |
| **Luau** | Lenguaje de scripting de Roblox (variante de Lua con tipos opcionales). |

## Setup desde cero

### 1. Instalar Rokit (toolchain manager)

Descarga desde https://github.com/rojo-rbx/rokit/releases y agrega `~/.rokit/bin` al PATH.

En Windows, instalar el binario y luego:

```powershell
rokit self-install
```

Esto crea `~/.rokit/bin` y configura el PATH. Cierra y reabre la terminal.

Verifica:
```powershell
rokit --version
```

### 2. Clonar el repo e instalar herramientas

```powershell
git clone <repo-url> infernal-chairs
cd infernal-chairs
rokit install
```

`rokit install` lee `rokit.toml` y baja las versiones exactas de Rojo, StyLua y Selene en `~/.rokit/`. Verifica:

```powershell
rojo --version       # 7.6.1
stylua --version     # 2.5.2
selene --version     # 0.31.0
```

Si te aparece "tool not trusted", córrelo manualmente la primera vez:
```powershell
rokit trust rojo-rbx/rojo JohnnyMorganz/StyLua Kampfkarren/selene
rokit install
```

### 3. Instalar Roblox Studio

Descarga desde https://create.roblox.com/ — entra con tu cuenta de Roblox.

### 4. Instalar el plugin de Rojo en Studio

```powershell
rojo plugin install
```

Esto copia el plugin a la carpeta de plugins de Studio (`%LOCALAPPDATA%\Roblox\Plugins\` en Windows).

### 5. Abrir el archivo de Studio

`infernal-chairs.rbxl` **viene en el repo** (versionado en git). Lo abrís con doble-click o
desde Studio: **File → Open**.

> El `.rbxl` se versiona porque contiene los Marketplace assets (Templates + lobby decor)
> con propiedades binarias que Rojo no roundtripea bien. Ver [ROBLOX_PLAYBOOK.md](ROBLOX_PLAYBOOK.md)
> sección 4 y `.gitignore` para la razón completa. **Fuente de verdad**: `default.project.json`
> + código en `src/` + `infernal-chairs.rbxl` para los assets visuales.

### 6. Arrancar el sync

En terminal:
```powershell
rojo serve
```

En Studio, plugin de Rojo en el toolbar → **Connect** (deja `localhost:34872`). Acepta el
prompt de permisos.

Listo. Cambios en `src/**/*.luau` → se sincronizan en vivo (re-Play para verlos en runtime).
Cambios en `default.project.json` → reiniciar `rojo serve` + Disconnect/Connect.

## Cómo correr el juego (testing)

Como mínimo requiere `MIN_PLAYERS` jugadores (definido en `src/server/Config.luau`, por
default 3). Para probar vos solo:

1. En Studio, pestaña **Test**.
2. Modo **Start** → cambiá `Players` a 3+.
3. Click **Start**. Se abre una ventana de server + una por cada cliente simulado.
4. Alt+Tab entre ventanas para mover cada player.
5. Para detener: en cualquier ventana → **Stop**.

## Estructura del proyecto

```
infernal-chairs/
├── rokit.toml                  # versiones de herramientas (Rojo/StyLua/Selene)
├── default.project.json        # mapa: filesystem + .rbxl → jerarquía Roblox
├── infernal-chairs.rbxl        # VERSIONADO: Marketplace assets + lobby decor + spawns
├── README.md                   # este archivo
├── DEV_PLAN.md                 # roadmap por fases + estado actual + decisiones
├── ROBLOX_PLAYBOOK.md          # lecciones reutilizables para futuros proyectos
├── .gitignore                  # *.rbxm/*.rbxmx ignored; *.rbxl SÍ versionado
└── src/
    ├── server/
    │   ├── init.server.luau    # game loop (state machine + sit + orbit + spectator)
    │   ├── Config.luau         # constantes tunables (cadencia, geometría, eventos)
    │   ├── Events.luau         # eventos de ronda (ice/mud/fog/flickering)
    │   ├── World.luau          # arena shell parametrizado + signs (SurfaceGui) + anchor pass del lobby decor
    │   └── Decor.luau          # slot del arena (DiscoBall) con pivot compensation
    ├── client/
    │   ├── init.client.luau    # bridges RemoteEvents → audio, SFX, fog particles
    │   └── Hud.luau            # toda la UI (banner, countdown, eliminated overlay, welcome)
    └── shared/
        └── Hello.luau          # placeholder (sin uso por ahora)
```

**Notar**: no hay carpeta `assets/`. Todo lo que sería asset del Marketplace vive dentro del
`.rbxl` (ver [ROBLOX_PLAYBOOK.md](ROBLOX_PLAYBOOK.md) §4 para la decisión).

### Cómo se traduce a Roblox

| Origen | Jerarquía en Roblox |
|---|---|
| `src/server/` | `ServerScriptService.Server` |
| `src/client/` | `StarterPlayer.StarterPlayerScripts.Client` |
| `src/shared/` | `ReplicatedStorage.Shared` |
| `default.project.json` declara | `Workspace.Baseplate`, `Workspace.Lobby.{Shell,Lights,Signs,SpawnPads,Decor}`, `Workspace.Arena` + `Workspace.Chairs` (vacíos, los llena el código), `ReplicatedStorage.{Events,Templates}`, `SoundService.Music`, configs de `Lighting`/`HttpService` |
| `.rbxl` aporta (vía `$ignoreUnknownInstances` en JSON) | Templates clonables (`Chair`, `DiscoBall`), muebles del lobby (`Workspace.Lobby.Decor`), SpawnLocations, Floor/Ceiling y MatchStatusSign del lobby |
| Código genera al startup | `Workspace.Arena.Shell.*` (Track, Walls, Pillars, NeonRing, CenterLight), `Workspace.Arena.Decor.DiscoBall`, `Workspace.Chairs.Chair1..N`, SurfaceGuis de los signs |

## Arquitectura

### Comunicación server ↔ cliente

Server y cliente están aislados (no comparten memoria). Se hablan vía **RemoteEvents** en `ReplicatedStorage.Events`:

| Evento | Dirección | Payload | Para qué |
|---|---|---|---|
| `PlayMusic` | server → todos los clientes | (sin payload) | "arranca la música local" |
| `StopMusic` | server → todos los clientes | (sin payload) | "para la música local" |
| `StateChanged` | server → todos los clientes | `{phase, message, sub}` | Actualizar UI banner |
| `YouEliminated` | server → cliente específico | (sin payload) | Mostrar overlay "ELIMINATED" |

### Decisiones de diseño

- **Server NUNCA confía en el cliente**. `Seat.Occupant` se lee del lado server. No hay manera de que un cliente "se siente" sin que el server lo valide.
- **Server NO reproduce audio**. Sólo dispara RemoteEvents; cada cliente toca/para su instancia local del `Sound`. Esto da control de volumen por jugador.
- **`ScreenGui.ResetOnSpawn = false`**. La UI sobrevive cuando el personaje muere (sin esto se borraría al respawn).
- **Sillas clonadas en runtime desde `ReplicatedStorage.Templates.Chair`**. El game loop las posiciona + muestra cada ronda. Se ocultan inmediatamente al spawnear (`hideAllChairs()` post-clone) para que no "flasheen" en la posición default del template.
- **Templates de assets viven en el `.rbxl`**, no en `.rbxm`. Porque Rojo no roundtripea bien propiedades binarias del engine (PBR, MaterialVariant, CSG). Detalle completo en [ROBLOX_PLAYBOOK.md](ROBLOX_PLAYBOOK.md) §3 y §4.

### State machine del GameLoop

```
Waiting → Warmup → Intermission → Playing → Stopped → Judgement → Eliminate
   ↑                                                                 │
   │                                                                 ▼
   └────────── Reset ←── Winner ←── (1 player left) ──── Next round
```

Vive en [src/server/init.server.luau](src/server/init.server.luau). Cada fase loguea con `[GameLoop:Phase]` y broadcasta el estado a la UI vía `StateChanged`.

## Hacia dónde vamos

Detalle completo en [DEV_PLAN.md](DEV_PLAN.md). Resumen:

- **Fase 13 (siguiente)**: persistencia con DataStore — wins, streak, leaderstats sidebar para que ganar importe.
- **Fase 14**: más eventos (reverseControls, lavaPits, speedBoost, shrinkingChairs, etc.).
- **Fase 15+**: monetización (GamePasses, DevProducts, VIP servers), multi-place, accesibilidad.
