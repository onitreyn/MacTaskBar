# Windows-style Taskbar для macOS — Архитектура

## 1. Цель проекта

Нативное приложение для macOS, заменяющее/дополняющее Dock панелью в стиле Windows Taskbar:

- список открытых приложений и окон (не только иконки);
- переключение между окнами по клику;
- закреплённые приложения;
- отображение на каждом мониторе;
- работа без тачпада (мышь + клавиатура);
- горячие клавиши переключения окон.

Целевая аудитория — один пользователь (вы), не App Store. Это снимает ограничения App Sandbox и позволяет использовать полный Accessibility API.

## 2. Стек технологий

| Слой | Технология | Причина |
|---|---|---|
| Язык | Swift 5.9+ | нативная интеграция с AppKit |
| UI-фреймворк | AppKit (+ SwiftUI внутри NSHostingView для части View) | точный контроль над NSWindow.level, collectionBehavior, Spaces — SwiftUI App/Scene этого не даёт |
| Сборка | Swift Package Manager + оболочка .app (без Xcode проекта, чтобы всё жило в git и собиралось из CLI) | воспроизводимость, не завязано на Xcode GUI |
| Минимальная macOS | 13.0 Ventura | `SMAppService` для автозапуска, актуальные API Accessibility |
| Дистрибуция | локальная сборка + ad-hoc подпись, без App Store | нужен полный доступ к Accessibility/Screen Recording, sandbox мешает |

## 3. Системные разрешения

| Разрешение | Зачем | API |
|---|---|---|
| **Accessibility (Универсальный доступ)** | Обязательно. Список окон, активация, закрытие, перемещение | `AXUIElement`, `AXObserver` |
| **Screen Recording** | Опционально, для превью окон (миниатюры) | `CGWindowListCreateImage` / `ScreenCaptureKit` |
| Без App Sandbox | Accessibility API плохо работает в sandbox без частных исключений | `com.apple.security.app-sandbox = false` в entitlements |

Оба разрешения запрашиваются при первом запуске, приложение проверяет `AXIsProcessTrusted()` и показывает инструкцию, если доступа нет.

## 4. Ключевое системное ограничение (обязательно зафиксировать)

Настоящий **macOS Full Screen** (зелёная кнопка → «Полный экран») создаёт отдельное Space.
Ни Dock, ни uBar, ни наше приложение **не могут гарантированно показываться поверх** такого Space без приватных/недокументированных трюков, которые Apple может заблокировать в любом обновлении.

Архитектура должна:
- максимально стараться показываться (`NSWindow.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]`, `level = .statusBar`);
- явно документировать пользователю, что в true-Fullscreen гарантий нет;
- рекомендовать режим "Maximize/Zoom" вместо true Fullscreen (это уже проговорено с пользователем ранее).

## 5. Модули

```
TaskbarApp/
├── Package.swift
├── Sources/
│   └── TaskbarApp/
│       ├── App/
│       │   ├── AppDelegate.swift          — точка входа, NSApplicationDelegate
│       │   ├── AppLifecycle.swift         — запрос прав, автозапуск (SMAppService)
│       │   └── main.swift                 — bootstrap NSApplication
│       │
│       ├── Core/
│       │   ├── WindowManager/
│       │   │   ├── WindowInfo.swift        — модель окна (pid, title, bounds, appIcon, isMinimized)
│       │   │   ├── RunningAppInfo.swift    — модель приложения (bundleId, name, icon, pid)
│       │   │   ├── WindowObserverService.swift  — AXObserver: created/destroyed/title/minimized
│       │   │   ├── AppLifecycleObserver.swift    — NSWorkspace: didLaunch/didTerminate/didActivate
│       │   │   └── WindowActionService.swift     — активировать/закрыть/минимизировать окно через AX
│       │   │
│       │   ├── SpacesTracker.swift         — отслеживание текущего Space/Display (NSWorkspace + CGSPrivate где доступно)
│       │   ├── ScreenTracker.swift         — NSScreen.screens, didChangeScreenParametersNotification
│       │   └── PermissionsService.swift    — проверка/запрос Accessibility & Screen Recording
│       │
│       ├── State/
│       │   ├── TaskbarStore.swift          — единый источник правды (ObservableObject), группировка окон по приложениям
│       │   └── PinnedAppsStore.swift        — закреплённые приложения, хранение в UserDefaults/JSON
│       │
│       ├── UI/
│       │   ├── TaskbarPanel.swift          — NSPanel-подкласс: level, collectionBehavior, positioning
│       │   ├── TaskbarPanelController.swift — по одному контроллеру на экран (NSScreen)
│       │   ├── TaskbarRootView.swift       — SwiftUI View, встраивается через NSHostingView
│       │   ├── AppTileView.swift           — плитка приложения/окна (иконка, título, badge)
│       │   ├── WindowPreviewPopover.swift  — превью окна при наведении (NSPopover)
│       │   └── ClockWidgetView.swift       — часы/дата в правом углу
│       │
│       ├── Hotkeys/
│       │   ├── HotkeyManager.swift         — регистрация глобальных горячих клавиш (Carbon RegisterEventHotKey)
│       │   └── WindowSwitcherOverlay.swift — Alt+Tab-подобный оверлей переключения окон
│       │
│       ├── Settings/
│       │   ├── SettingsWindowController.swift
│       │   ├── SettingsView.swift          — SwiftUI: позиция панели, авто-скрытие, группировка, тема
│       │   └── AppSettings.swift           — модель настроек (UserDefaults-backed, @AppStorage)
│       │
│       └── Utilities/
│           ├── LaunchAtLogin.swift          — SMAppService.mainApp
│           └── Logger.swift
│
└── Resources/
    └── Info.plist  (NSAccessibilityUsageDescription, LSUIElement=false пока разрабатываем с Dock-иконкой)
```

## 6. Поток данных (data flow)

```
NSWorkspace notifications ──┐
AXObserver callbacks ───────┼──► WindowManager (Core) ──► TaskbarStore (State)
CGWindowList polling (fallback) ┘                              │
                                                                 ▼
                                         TaskbarPanelController (по одному на NSScreen)
                                                                 │
                                                                 ▼
                                              TaskbarRootView (SwiftUI, реактивно на @Published)
                                                                 │
                                              клик/hover ───────►│
                                                                 ▼
                                          WindowActionService (активировать/закрыть/свернуть через AX)
```

`TaskbarStore` — единственный источник истины. Все View подписаны на него через `@Published`/`ObservableObject`, что даёт SwiftUI-реактивность без ручного обновления UI.

## 7. Многомониторность

- `TaskbarPanelController` создаётся на каждый `NSScreen` из `NSScreen.screens`.
- Подписка на `NSApplication.didChangeScreenParametersNotification` — пересоздание/переразмещение панелей при подключении/отключении монитора (ваш случай: MacBook на подставке + внешний монитор).
- Настройка: "показывать на всех экранах" / "только на главном" / "зеркалировать" (как в uBar).
- Панель на каждом экране показывает **только окна, находящиеся на этом экране/Space**, либо все — переключается в настройках.

## 8. Горячие клавиши и работа без тачпада

Раз мышь + клавиатура без тачпада — критичны:

- **Global hotkey** (Carbon `RegisterEventHotKey`, работает даже без фокуса приложения) для:
  - показать/скрыть панель;
  - открыть свитчер окон (аналог Alt+Tab, но по отдельным окнам, не по приложениям);
  - вызвать Mission Control/Exposé программно (`CGSHwSetWorkspaceHint` — недокументированный, либо просто триггерить системный hot corner через `CGEventSource`).
- Обычный `Cmd+Tab` в macOS переключает **приложения**, не окна — наш свитчер должен переключать **окна**, это и есть Windows-подобное поведение.
- Клик правой кнопкой мыши по плитке → контекстное меню (закрыть/закрепить/показать все окна) — полностью на мыши, без жестов тачпада.

## 9. Хранение настроек

- `UserDefaults` + `@AppStorage` для простых значений (позиция панели, авто-скрытие, тема).
- JSON-файл в `~/Library/Application Support/TaskbarApp/pinned.json` для закреплённых приложений (порядок важен, простой массив bundleId).

## 10. Автозапуск

`SMAppService.mainApp.register()` (macOS 13+) — современный API вместо старых LaunchAgent plist. Настройка "запускать при входе" в Settings.

## 11. Фазы реализации (roadmap)

| Фаза | Содержание | Критерий готовности |
|---|---|---|
| **MVP (Фаза 1)** | WindowManager + одна панель на главном экране + список окон + клик-переключение + запрос Accessibility | Показывает реальные открытые окна, клик активирует нужное |
| **Фаза 2** | Многомониторность, закреплённые приложения, группировка окон по приложению | Работает на вашей связке MacBook + внешний монитор |
| **Фаза 3** | Глобальные горячие клавиши, свитчер окон (Alt+Tab-аналог), автозапуск | Полностью управляется мышью+клавиатурой без Dock |
| **Фаза 4** | Превью окон (hover), темы, авто-скрытие, настройки | Похоже на uBar по UX |
| **Фаза 5 (опционально)** | Мини-режим "поверх Fullscreen" через canJoinAllSpaces/fullScreenAuxiliary, тестирование на разных приложениях | Задокументированы приложения, где это не работает |

## 12. Риски

1. **Fullscreen-ограничение** — описано в п.4, неустранимо полностью средствами публичных API.
2. **Обновления macOS** — Accessibility API стабилен, но поведение Spaces/collectionBehavior иногда меняется между версиями (Sequoia/Tahoe).
3. **Подпись и Gatekeeper** — без Developer ID приложение будет блокироваться Gatekeeper при каждом запуске; для личного использования используется собственный self-signed сертификат (`scripts/create_dev_cert.sh`) вместо ad-hoc — см. п.13.6, почему именно так, и разрешение через "Открыть в любом случае".
4. **Производительность** — опрос `CGWindowListCopyWindowInfo` не должен идти поллингом чаще, чем раз в 300–500 мс как fallback; основной источник — событийный `AXObserver`.

## 13.5 Инцидент 05.08 и защита при управлении системным Dock

**Что произошло:** во время тестирования z-order панели агент напрямую менял
глобальную системную настройку (`defaults write com.apple.dock autohide-delay`)
через bash-инструмент, а не через код приложения. Когда сессия агента
прервалась (дневной лимит), откат не произошёл, и пользователю пришлось
вручную восстанавливать Dock через терминал.

**Вывод:** любое изменение системных настроек, которое не является тривиально
обратимым в рамках одного вызова, не должно зависеть от того, что "агент не
забудет откатить" или "приложение штатно завершится". Нужна независимая
гарантия отката.

**Принятое решение — три независимых уровня защиты (см. `DockController` +
`scripts/dock_watchdog.sh`):**

1. **Marker-файл** на диске (`~/Library/Application Support/TaskbarApp/dock_hidden_by_us`),
   создаётся ДО изменения настроек Dock — переживает краш процесса.
2. **`applicationWillTerminate`** в AppDelegate — восстанавливает Dock при
   любом штатном завершении (Cmd+Q, System Events quit).
3. **Независимый launchd LaunchAgent** (`com.local.taskbarapp.dockwatchdog`,
   `scripts/dock_watchdog.sh`) — проверяет каждые 15 секунд и при каждом
   логине: если marker-файл существует, а процесс TaskbarApp не запущен,
   Dock восстанавливается автоматически. Это единственный уровень, который
   сработает, даже если TaskbarApp убит `kill -9` и никогда больше не
   запустится.

Скрытие Dock — явный тумблер в UI приложения (пункт меню), а не автоматическое
поведение при старте. Установка/удаление сторожа — через
`scripts/install_watchdog.sh` / `scripts/uninstall_watchdog.sh`.

## 13.6 Инцидент 08.08: плитки приложений не отображались на панели

**Симптом:** после реализации многомониторности обе панели физически
создавались на верных экранах (подтверждено через `CGWindowListCopyWindowInfo`,
layer и bounds корректны), но иконки/названия приложений визуально не
показывались. При этом иногда (нестабильно) плитки на короткое время были
видны, что указывало на race condition, а не на детерминированную ошибку.

Диагностика заняла много времени именно из-за нестабильности: одинаковый
бинарник давал разный результат в зависимости от способа запуска (прямой
запуск из Terminal vs `open`), что маскировало реальную причину до тех пор,
пока обе причины не были найдены и устранены по отдельности.

Найдены **две независимые причины**, обе устранены:

### Причина A — z-order: `level` затирается `isFloatingPanel`

В `TaskbarPanel.configure()` порядок был:
```swift
level = NSWindow.Level(rawValue: dockLevel + 1)  // (1) ставим уровень выше Dock
...
isFloatingPanel = true                            // (2) сеттер сбрасывает level на .floating (rawValue 3)!
```
Сеттер `isFloatingPanel` в AppKit сам присваивает `level = .floating` (3) —
это ниже системного Dock (level 20). Из-за этого наша панель физически
оказывалась НИЖЕ Dock по z-order, и Dock (если не скрыт) визуально
перекрывал плитки снизу экрана. Подтверждено эмпирически через
`CGWindowListCopyWindowInfo`: layer=3 у панели против layer=20 у Dock.

**Фикс:** переставить порядок — `level` устанавливается ПОСЛЕ
`isFloatingPanel = true`. После фикса: layer=21 у панели, 20 у Dock.

### Причина B — сброс разрешения Accessibility при пересборке (ad-hoc подпись)

Даже после фикса z-order плитки не появлялись при запуске через `open`
(обычный способ запуска), хотя при запуске бинарника напрямую из Terminal
всё работало. Диагностика через временный файловый лог показала:
`axGranted=false` при запуске через `open`, `axGranted=true` при прямом
запуске из Terminal — при одном и том же бинарнике.

**Механизм:** ad-hoc подпись (`codesign --sign -`, `TeamIdentifier=not set`)
не даёт стабильного CDHash — Swift debug-сборки встраивают build UUID,
меняющийся при каждой компиляции даже без изменений кода. macOS TCC
привязывает разрешение Accessibility к конкретному бинарному хешу, поэтому
каждая пересборка выглядит для системы как новое приложение — TCC-запись
формально существует и toggle в System Settings включён, но
`AXIsProcessTrusted()` возвращает `false` для нового бинарника.

При прямом запуске из Terminal разрешение "маскировалось" через механизм
responsible process — macOS относит право доступа к процессу, ответственному
за запуск (Terminal), у которого Accessibility уже был выдан вручную ранее.
Именно поэтому баг не воспроизводился при разработке через терминал и
проявлялся только при реальном использовании через `open`/Finder.

**Фикс:** создан собственный self-signed сертификат `TaskbarApp Local Dev`
(`scripts/create_dev_cert.sh`, запускается один раз на машине разработчика).
`build_app.sh` подписывает этим стабильным identity вместо ad-hoc. TCC
привязывает разрешение к Subject сертификата, а не к хешу файла — разрешение
теперь переживает пересборки. После смены схемы подписи разрешение
Accessibility нужно выдать заново один раз (`tccutil reset Accessibility
com.local.taskbarapp`, затем обычный запрос через UI).

**Общий вывод:** при диагностике UI-багов в AppKit-приложениях с системными
разрешениями и window levels нельзя ограничиваться визуальной проверкой или
логами внутри процесса — необходимо перепроверять поведение при разных
способах запуска (прямой бинарник vs `open`/LaunchServices), так как TCC и
responsible-process механизмы могут маскировать баги в одном из путей запуска.

## 13.7 Инцидент 13.08: контекстное меню плитки и активация окна из меню

В контекстное меню плитки (правый клик) добавлены действия: «Вывести на
передний план», «Развернуть под Taskbar», «Переместить на экран N» (пункты
экранов показываются только если `NSScreen.screens.count > 1`). Логика выбора
окна та же, что у обычного клика — первое не свёрнутое окно приложения.

### Проблема — «вывести на передний план» не активирует окно из меню

Из обычного левого клика по плитке активация (`WindowActionService.activate`
→ `NSRunningApplication.activate(.activateIgnoringOtherApps)`) работает надёжно.
Но из пункта контекстного меню тот же вызов НЕ работал: приложение становилось
frontmost не всегда, а чаще окно вообще не поднималось или поднималось и тут же
«пряталось» за прежним окном.

**Механизм:** при открытии контекстного меню AppKit на короткое время делает
наш TaskbarApp frontmost (чтобы «хостить» меню и принимать клавиатуру). После
закрытия меню macOS возвращает фокус предыдущему приложению. В этом
post-menu контексте обычный `NSRunningApplication.activate` молча не срабатывает.

### Что перепробовано и что НЕ сработало

1. **Прямой вызов из action меню** — не активирует.
2. **`DispatchQueue.main.async` (следующий тик)** — не помогло.
3. **Фиксированная задержка 0.15с** — срабатывало лишь иногда (гонка с возвратом фокуса).
4. **`NSApp.deactivate()` перед активацией** — УХУДШИЛО: активация перестала
   работать полностью. Причина: к моменту вызова наше приложение уже НЕ frontmost
   (фокус уже вернулся к прежнему приложению), а `deactivate()` в этом состоянии
   только дополнительно сбивал системную логику фокуса.

### Рабочее решение

1. Активация на следующем тике run loop (после закрытия меню).
2. «Жёсткая» активация в `performActivation`:
   - `NSRunningApplication.activate([.activateIgnoringOtherApps, .activateAllWindows])`;
   - **belt-and-suspenders**: прямое выставление `kAXFrontmostAttribute = true`
     на appElement через Accessibility API (`AXUIElementCreateApplication(pid)`).
     AX-атрибут срабатывает даже там, где `NSRunningApplication.activate` молчит.
3. Страховка: через 0.25с проверка `NSWorkspace.shared.frontmostApplication`;
   если цель не стала frontmost — повтор активации (идемпотентен).

Ключевая находка — `NSApp.deactivate()` вреден в этом сценарии, а не полезен;
прямой `kAXFrontmostAttribute` оказался самым надёжным примитивом.

### Диагностические уроки (важно для будущей отладки)

1. **`NSLog` не попадал в `log stream`** — при отладке межпроцессной активации
   и фокуса переключились на файловый лог (`FileHandle` в `/tmp/taskbar_focus.log`)
   + подписку на `NSWorkspace.didActivateApplicationNotification`. Это дало точную
   последовательность событий фокуса и выявило, что цель вообще не становится
   frontmost (а не «становится и откатывается»).

2. **`open build/TaskbarApp.app` НЕ перезапускает уже запущенный инстанс** —
   если приложение уже работает, `open` просто активирует существующий процесс,
   а не запускает новый бинарник. Из-за этого несколько итераций фиксов тестировались
   на СТАРОЙ сборке (процесс не перезапускался между `pkill`/`open`), и результат
   вводил в заблуждение. Надёжный способ перезапуска: сначала `pkill -9 -x TaskbarApp`,
   убедиться через `pgrep`, что процесс мёртв, затем `open`.

3. **`codesign` периодически зависает на запросе keychain** — ключ `TaskbarApp
   Local Dev` импортирован с подтверждением при каждом использовании. При появлении
   системного диалога нужно одобрить его с отметкой «Всегда разрешать». Сам
   `set-key-partition-list` требует пароль keychain, поэтому программно это не
   устраняется без участия пользователя.

## 14. Следующий шаг

Реализовано и проверено: MVP-панель на всех экранах, список окон, клик-активация,
снап под Taskbar, вывод на передний план, перенос окна на другой экран, бейдж
количества окон + список окон в контекстном меню, сжатие плиток при переполнении.

Дальше — по итогам исследования uBar (см. **`UBAR_RESEARCH.md`**, полный инвентарь
фич и приоритеты заимствования):
1. Per-monitor окна (каждый экран — только свои окна).
2. «Клик по активному приложению скрывает его» + модификаторы клика
   (Option-скрыть / Shift-quit / Cmd-показать в Finder / middle-click закрыть).
3. Переход ядра перечисления окон с AX-заголовков на `CGWindowList` (надёжные
   заголовки, стабильный window id, фундамент для превью/activity).
4. Clock Area (+ hover-календарь) — дешёвая косметика.
5. Превью окон по hover и Activity Mode (CPU/RAM) — Фаза 4.
6. App Flashes/Status/Badges — только после исследования private API (рискованно).
