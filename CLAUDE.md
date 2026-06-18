# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

Personal project workspace (remote: `git@github.com:dahao0110/dahhhh.git`, branch: `main`). No package managers — each project is self-contained. Dark-theme UI is the convention across all HTML files (CSS custom properties on `:root`, radial gradient background decorations).

## Projects

### stock-screener.html — A-Share Dynamic Stock Screener

Single-file HTML that fetches real-time data from East Money public API and filters by four criteria from `select stock`:
1. Market cap < N billion (configurable slider, default 1000亿)
2. Revenue growth > N% for 3 consecutive years
3. Industry in 15th Five-Year Plan hot sectors (12 categories, multi-select tags)
4. At least 1 daily limit-up in past N trading days

**API endpoints used:**
- Stock list: `push2.eastmoney.com/api/qt/clist/get` (3,000+ stocks, market cap/PE/industry)
- K-line data: `push2his.eastmoney.com/api/qt/stock/kline/get` (daily bars for limit-up detection)

**Architecture:** `fetchStockList()` → `applyFilters()` (cap + industry) → `checkLimitUps()` (async batch, 8 concurrent) → `finalFilter()` → `renderTable()`. Revenue growth data requires a separate financial API and is currently marked "待查" in the UI.

### PomodoroApp — Native macOS Pomodoro Timer

SwiftUI `.app` with ring animation, mode switching (work/short/long break), sound/notification alerts, state persisted to `~/Library/Application Support/pomodoro_state.json`.

**Build:**
```bash
bash PomodoroApp/build.sh
```

**Architecture** (`PomodoroApp/Sources/main.swift`, ~580 lines):
- `@main PomodoroApp` — WindowGroup with fixed size, hidden title bar, keyboard shortcuts (Space=toggle, R=reset, S=skip, 1/2/3=modes)
- `AppDelegate` — notification permissions, window centering, dock re-open
- `TimerViewModel` (@MainActor) — core timer, auto mode-switch (4 work → long break), AIFF sound via AVAudioPlayer, state save/load (daily tomato counter resets at midnight)
- `TimerMode` enum — work/shortBreak/longBreak with durations from `Settings`
- Views: `ContentView`, `ModePicker`, `TimerView` (AngularGradient ring), `PlayButton`, `CircleButton`, `TomatoDots`, `SettingsRow`, `CongratOverlay`

**Compiler requirements:** `-parse-as-library` (for `@main`), `-target arm64-apple-macosx15.0`, frameworks: SwiftUI, AppKit, AVFoundation, UserNotifications. Float80 unavailable in Swift 6 — build script uses hardcoded 80-bit float bytes for 44100 Hz AIFF header.

### task-dashboard.html — Task Completion Dashboard

Single-file dark-theme web app (Chinese UI). Task cards with gradient progress bars, add/edit/delete via modal, stats bar (total/done/avg progress), localStorage persistence. Keyboard shortcuts: Ctrl+K (new task), Escape (close modal).

### pomodoro-timer.html — Web Pomodoro Timer

Browser-based Pomodoro timer. Superseded by the native PomodoroApp for macOS.

### create_ppt.py — Photo Layout PPT Generator

Python script using `python-pptx` to generate a PowerPoint template with 8 photo placeholders across 3 slides:
- Slide 1: Asymmetric (1 large + 2×2 small grid, 5 photos)
- Slide 2: Banner + side-by-side (1 wide + 2 below, 3 photos)
- Slide 3: Masonry/brick layout (3 columns, all 8 photos)

Generates `照片排列模板.pptx` on Desktop. Each placeholder is a rounded rectangle with shadow, border, and "照片 N" label. Warm white background with blue-gray accent titles.

### Data Files

- `random_numbers.xlsx` — 20 rows of random floats (openpyxl)
- `1234` — Instruction file (options strategy Word doc task, already executed)
- `select stock` — Stock screener requirements (4 rules, already implemented in stock-screener.html)

## Common Patterns

- HTML projects: dark theme CSS with `:root` custom properties, system font stack prioritizing PingFang SC / Microsoft YaHei, localStorage for persistence, no frameworks
- Python scripts are one-off utilities (`python-pptx`, `openpyxl`, `python-docx`, `matplotlib`); install what's needed with `pip3 install`
- When generating matplotlib charts with Chinese text: use Heiti SC font, avoid emoji, avoid `family='monospace'` in text boxes
- Output files typically go to Desktop (`~/Desktop/`)

## Git Identity

- Username: dahao0110
- Email: dahao0110@gmail.com
- SSH: `~/.ssh/id_ed25519` (ED25519)
