# Infernal Chairs

Juego de **sillas musicales** en Roblox, con un giro: los jugadores no controlan su movimiento mientras suena la música — orbitan automáticamente alrededor de las sillas. Cuando para la música, recuperan el control y corren a sentarse. Quien no alcanza silla queda eliminado.

> Estado actual: MVP jugable con eliminación, sillas aleatorias, y UI mínima. La mecánica de rotación forzada todavía no está implementada (siguiente paso). Ver [DEV_PLAN.md](DEV_PLAN.md) para roadmap completo.

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

### 5. Crear el archivo de Studio

Abre Studio, **File → New** (te abre un Baseplate vacío). Guárdalo como `infernal-chairs.rbxl` dentro de la carpeta del proyecto.

> Este archivo `.rbxl` está en `.gitignore` — cada dev tiene el suyo. La fuente de verdad es `default.project.json` + el código en `src/`.

### 6. Arrancar el sync

En terminal:
```powershell
rojo serve
```

En Studio, abre la pestaña **Rojo** del toolbar → **Connect** (deja `localhost:34872`). Acepta el prompt de permisos.

Listo. Ahora cualquier cambio en `src/**/*.luau` o `default.project.json` se refleja en Studio en vivo.

## Cómo correr el juego (testing)

Como mínimo requiere 2 jugadores (`MIN_PLAYERS = 2` en `src/server/Config.luau`). Para probar tú solo:

1. En Studio, ve a pestaña **Test**
2. Modo **Start** → cambia `Players` a `2` (o más)
3. Click **Start**

Studio abre una ventana "server" + una ventana cliente por cada jugador simulado. Puedes Alt+Tab y mover cada uno.

Para detener: cualquier ventana → **Stop**.

## Estructura del proyecto

```
infernal-chairs/
├── rokit.toml                  # versiones de herramientas
├── default.project.json        # mapa: carpeta → jerarquía Roblox (declara mundo + objetos)
├── README.md                   # este archivo
├── DEV_PLAN.md                 # roadmap detallado por fases
├── .gitignore
├── assets/
│   └── chair.rbxm              # modelo de silla del Marketplace (bundled, sin HTTP runtime)
└── src/
    ├── server/
    │   ├── init.server.luau    # GameLoop server (state machine completo + eventos)
    │   └── Config.luau         # todas las constantes tunables (cadencia, geometría, eventos)
    ├── client/
    │   └── init.client.luau    # UI + audio playback (LocalScript per-cliente)
    └── shared/
        └── Hello.luau          # placeholder (sin uso por ahora)
```

### Cómo se traduce a Roblox

| Carpeta / archivo | Jerarquía en Roblox |
|---|---|
| `src/server/` | `ServerScriptService.Server` |
| `src/client/` | `StarterPlayer.StarterPlayerScripts.Client` |
| `src/shared/` | `ReplicatedStorage.Shared` |
| `default.project.json` define | `Workspace.Baseplate`, `Workspace.Chairs`, `Workspace.SpawnPads`, `ReplicatedStorage.Events`, `SoundService.Music` |

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

- **Server NUNCA confía en el cliente**: `Seat.Occupant` se lee del lado server. No hay manera de que un cliente "se siente" sin que el server lo valide.
- **Server NO reproduce audio**: solo dispara RemoteEvents; cada cliente toca/para su instancia local del `Sound`. Esto da control de volumen por jugador.
- **`ScreenGui.ResetOnSpawn = false`**: la UI sobrevive cuando el personaje muere (sin esto se borraría al respawn).
- **Sillas declaradas en `default.project.json`** (no creadas en runtime): nacen ocultas (`Transparency=1, CanCollide=false, Disabled=true`) y el server las posiciona + muestra cada ronda. Esto evita el "flash" de verlas en posición default antes de moverlas.
- **8 SpawnLocations en círculo de radio 25** (perímetro), sillas en cluster central (radio 0-10). Da la forma circular del juego.

### State machine del GameLoop

```
Waiting → Intermission → Playing → Stopped → Eliminate
   ↑                                              │
   │                                              ▼
   └──── Reset ←── Winner ←── (1 player left)  Next round
```

Vive en [src/server/init.server.luau](src/server/init.server.luau). Cada fase loguea con `[GameLoop:Phase]` y broadcasta el estado a la UI vía `StateChanged`.

## Hacia dónde vamos

Resumen muy corto. Detalle completo en [DEV_PLAN.md](DEV_PLAN.md).

- **Próximo paso**: rotación forzada — los jugadores orbitan automáticamente alrededor de las sillas mientras suena la música, recuperan control al parar, y quedan bloqueados al sentarse (no se pueden parar).
- **Después**: polish (SFX de stop, celebración del ganador, lobby loop entre matches).
- **Eventual**: visuales (sillas que parezcan sillas, modelo de mapa elaborado), persistencia de stats, matchmaking.
