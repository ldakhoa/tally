# Tally Design Philosophy & Hand-Drawn Cozy Style Guide

> **Theme:** *Paws & Cream* — Warm, personal, storybook-cozy household finance for couples who love dogs, cats, and everyday joy.

---

## 1. Design Philosophy

Personal finance apps often feel cold, academic, or stressful—stark black ink, sharp geometric fonts, monochrome charts, and spreadsheet jargon. **Tally** intentionally flips that feeling:

1. **Cozy over clinical:** Warm cream paper, roasted cocoa ink, and soft peach/mint/honey pastels replace harsh pure black (`#000000`) and clinical grays.
2. **Personal & joyful:** Finance is shared life. The couple's own **watercolor chibi portraits** and their animated **Shiba Puppy & Cream Kitty** companions live right inside the app, reacting empathetically to savings, budgets, and daily treats.
3. **Clear at a glance:** Cuteness never sacrifices readability. Every theme enforces WCAG AA contrast (`> 4.5:1` verified by `ThemeTokensTests`), every icon has a clear silhouette, and every number uses `monospacedDigit()` for effortless scanning.
4. **Alive, never sluggish:** Delightful spring physics, micro-haptics, and celebratory paw/heart bursts run exclusively on GPU transforms (`scaleEffect`, `offset`, `opacity`, `rotationEffect`) with pre-warmed haptic generators so the app stays locked at 60/120fps.

---

## 2. Color System (*Paws & Cream*)

Defined in `Packages/Sources/ThemeTokens/AppTheme.swift`.

### Light Mode (`cozyPawsLight`)
| Token | Hex | Role |
|---|---|---|
| `ios.page` | `#FFF8F0` | Warm oat / milk-tea cream page canvas |
| `ios.card` | `#FFFFFF` | Soft milk-white floating card surface |
| `ios.editor` | `#FAF0E4` | Biscuit cream sheet & input surface |
| `text` | `#3D2C26` | Warm espresso brown body & headings (never harsh black) |
| `textSecondary` | `#7E675E` | Soft latte secondary labels |
| `ink` | `#5A3F37` | Roasted cocoa primary pills & user chat bubbles |
| `accent` | `#E67360` | Warm coral-peach primary highlights & CTAs |
| `positive` | `#3E8E63` | Soft matcha sage (income, healthy savings) |
| `caution` | `#D68A28` | Warm honey amber (approaching budget limit) |
| `negative` | `#D95B5B` | Soft berry coral (over budget, destructive actions) |
| `info` | `#5589B8` | Soft sky blueberry (informational badges) |

### Dark Mode (`cozyPawsDark`)
| Token | Hex | Role |
|---|---|---|
| `ios.page` | `#1E1816` | Cozy evening cocoa background |
| `ios.card` | `#2A211E` | Warm mocha elevated card |
| `text` | `#FAF0E6` | Warm oat cream text |
| `accent` | `#F59382` | Soft peach coral highlight |

### Hero Gradients & Shadows
- **Light Hero Gradient:** `#FFE9D8 → #FFF5E6` with subtle `PawPrintBackdrop` (`accent` at 5–7% opacity).
- **Dark Hero Gradient:** `#3A2A25 → #2F2224`.
- **Warm Shadows:** Always tint shadows with warm brown (`#6B4423` at `8.5%` + `4%`), never cold `#000000`.

---

## 3. Typography & Surfaces

Defined in `Packages/Sources/DesignSystem/Theme.swift` and `ThemeRuntime.swift`.

- **Font Family:** **SF Pro Rounded** (`.system(size: ..., weight: ..., design: .rounded)`) across all SwiftUI views and UIKit `UINavigationBar` titles.
- **Tracking:** Neutral (`0.0`) so Vietnamese, English, and Chinese characters & diacritics breathe cleanly.
- **Numbers:** Always `.monospacedDigit()` + `.contentTransition(.numericText())` for smooth animated counter rolls.
- **Plush Corner Radii:**
  - Cards: `26pt` (continuous)
  - Metric Tiles: `22pt`
  - Panels / Chat Bubbles: `18–20pt`
  - Fields & Controls: `14pt`
  - Pills / Floating Tab Bar: `Capsule()`

---

## 4. Hand-Drawn Cozy & Pastel Illustration Style

All custom illustrations—Tab Bar icons (`CozyTabBar.swift`), Metric stickers (`ChibiIconViews.swift`), Pet companions (`PetCompanionView.swift`), and the App Icon—follow one unified **Japanese watercolor / storybook stationery** aesthetic:

### Linework & Proportions
- **Outline color:** Warm dark-brown cocoa ink (`#4E382F` in light mode; `#FFF2E6` when active in dark mode). Never pure `#000000`.
- **Stroke weight:** `1.5pt – 1.8pt` with `.lineCap = .round` and `.lineJoin = .round` for soft felt-tip / ink-pen warmth.
- **Shapes:** Plump, rounded silhouettes (`Ellipse`, `Capsule`, `RoundedRectangle(..., style: .continuous)`, gentle `QuadCurve` roofs & ears). Avoid sharp 90° corners.

### Color & Shading
- **Unselected state (Tab Bar):** Clean warm-brown outline only (`Color.textSecondary.opacity(0.75)`), keeping the bar airy and uncluttered.
- **Selected state (Tab Bar) & Stickers:** Fill with soft watercolor-inspired pastel washes:
  - Peach / Coral: `#F28B76`, `#FFD2D8`, `#FFE9DB`
  - Butter / Gold Coin: `#FFD966`, `#F5B959`
  - Matcha / Mint: `#8AD6AE`, `#9DE0B8`
  - Warm Cream: `#FFF9F0`, `#FFF5E6`
  - Rosy Blush: `#F59B9B` at `55–70%` opacity
- **Contrast Rule:** Never place a dark emoji (`🐾`) on a dark pill (`Color.ink`) or a pale yellow icon (`💡`) on a pale yellow background. Use adaptive SF Symbols (`pawprint.fill`) on dark pills and complementary pastel tints (e.g., periwinkle `#6482B8` behind `💡`).

### Icon Semantics (Icon-Only Floating Tab Bar)
| Tab | Hand-Drawn Motif | Meaning at a Glance |
|---|---|---|
| **Overview** | Cozy Cottage with peach roof & heart door | Home / household summary |
| **Transactions** | Cream Journal Notebook + golden coin | Daily spending & income log |
| **Statistics** | Three chubby pastel bars + sparkle | Trends & analytics |
| **Budgets & Goals** | Chubby pink Piggy Bank + dropping gold coin | Limits & savings jars |
| **Settings** | 6-petal daisy blossom with honey center | Preferences & sharing |

### Hybrid Hand-Drawn Icon System (Watercolor PNG Stickers + SwiftUI Vectors)
Defined in `Packages/Sources/DesignSystem/ChibiIconViews.swift`, `CozyCategoryIcons.swift`, `CozySettingsIcons.swift`, and `CozyUIIcons.swift`:

Tally uses a **Hybrid Icon Architecture** optimized for both storybook warmth and 60/120fps scrolling performance:
1. **Cached Watercolor PNG Stickers (`Packages/Sources/DesignSystem/Resources/`, `256×256` @3x):**
   - Used for all hero sticker badges (`32–44pt`) where Japanese watercolor brushwork shines:
     - **All 11 Categories (`cat_*.png`):** `cat_food`, `cat_housing`, `cat_transport`, `cat_shopping`, `cat_bills`, `cat_health`, `cat_entertainment`, `cat_other`, `cat_salary`, `cat_freelance`, `cat_income`.
     - **All 6 Savings Goals (`goal_*.png`):** `goal_target`, `goal_shield`, `goal_plane`, `goal_laptop`, `goal_house`, `goal_heart`.
     - **All 6 Main Settings Rows (`settings_*.png`):** `settings_general`, `settings_ai`, `settings_shortcuts`, `settings_email`, `settings_icloud`, `settings_backup`.
     - **Overview Metric Cards, KPI Tiles & Couple Portraits:** `icon_income`, `icon_spending`, `icon_budget`, `kpi_leaf`, `kpi_flame`, `chibi_husband`, `chibi_wife`.
   - Loaded once through an in-memory cache (`CozyWatercolorAsset`) so scrolling lists draw a single cached GPU texture quad per row with zero disk I/O. Every sticker automatically falls back to its matching SwiftUI vector if an asset is absent.
2. **Procedural SwiftUI Vector Icons (`CozyUIIcon`, `CozyCategoryIcon(..., style: .tinted)`, `CozyGoalIcon(..., style: .tinted)`, `CozyTabIconView`):**
   - Used for all **12–28pt UI/action glyphs** (plump felt-tip `+` FAB, AI sparkles, lightning bolt, desk calendar, journal list, trash, note, keypad, mic/stop/send, chevrons, arrows), **dark selected filter pills**, and the **Floating Tab Bar**. Instant tinting, dark-mode adaptation, and razor-sharp rendering at small sizes.

---

## 5. Pet Companions & Couple Chibi Avatars

- **Couple Avatars (`ChibiAvatarView`, `CoupleAvatarsBadge`):** Circular crops of the couple's hand-painted watercolor chibi portraits with warm cream borders (`#FFFDF9`), soft brown shadow, and a gentle pulsing heart (`♥`) when paired together.
- **Animated Pets (`ShibaPuppyView`, `CreamKittyView`, `CozyPetDuoView`):**
  - Subtle idle life: breathing scale (`1.9s` / `2.2s`), periodic eye blinks (`3.3s` / `4.0s`), ear wiggle / tail sway.
  - Tap interaction: bouncy jump + floating hearts/paws/sparkles + `CozyHaptics.soft()`.
  - Financial mood states: `.happy` (positive savings), `.cozy` (neutral), `.sleepy` (empty state), `.alert` (over budget).

---

## 6. Animation & Haptic Performance Guidelines

Defined in `Packages/Sources/DesignSystem/CozyAnimations.swift`.

1. **GPU-Only Properties:** Animate `scaleEffect`, `offset`, `opacity`, `rotationEffect`, and `matchedGeometryEffect`. Avoid animating `frame` widths/heights inside scrolling lists.
2. **Fire-Once Entrances:** `.cozyEntrance(index:)` guards with `guard !appeared else { return }` so cards glide in gently once and never re-trigger during scrolling.
3. **Preserve Tab State:** Keep the native `TabView` with `.toolbar(.hidden, for: .tabBar)` and attach `CozyFloatingTabBar` via `.safeAreaInset(edge: .bottom)` so switching tabs is instantaneous with zero view reconstruction.
4. **Pre-Warmed Haptics (`CozyHaptics`):** Reuse pre-prepared `UISelectionFeedbackGenerator`, `UIImpactFeedbackGenerator`, and `UINotificationFeedbackGenerator` instances on `@MainActor` so haptic feedback fires with zero latency:
   - Tab switch / chip select → `CozyHaptics.selection()`
   - Card tap / period shift / copy → `CozyHaptics.light()`
   - Petting companions → `CozyHaptics.soft()`
   - Primary `+` add / voice toggle → `CozyHaptics.medium()`
   - Transaction logged / AI action confirmed → `CozyHaptics.success()` + `CozyCelebrationOverlay`

---

## 7. Motivation & Reward Loops (Budgets · Goals · Commitments)

The three plan screens are built to make progress feel good, so opening them pulls toward earning and keeping more. Components live in `Packages/Sources/DesignSystem/CozyMotivation.swift`; every figure they show is computed in `Packages/Sources/BudgetKit/MotivationMetrics.swift` (unit-tested), never in the view.

| Screen | Hero (`cozyHeroSurface`) | Reward loop |
|---|---|---|
| **Budgets** (mint / honey / peach by pace) | Money left, `CozyProgressRing` of budget remaining, pace pill, pets reacting | Spend-per-day allowance, under-budget month streak (`CozyStreakFlame`), "Kept this month" level ladder with the exact amount to earn or cut for the next level |
| **Goals** (mint) | Total saved, overall ring, trophies, the goal closest to done | 25 / 50 / 75 / 100% stars on `CozyMilestoneBar`, coin burst and milestone banner on every contribution, live preview in the contribution sheet |
| **Commitments** (honey) | Paid so far, debt-free ring, debt-free month | One `CozyPaymentDots` segment per payment, "back every month once done", trophies on finished plans |

Rules:
1. **Celebrate real events only.** `CozyCoinBurstOverlay` + `CozySounds.play(.coin)` fire when money actually moves (a contribution, a milestone), never on simply opening a screen.
2. **Numbers arrive, they don't just appear.** Hero figures use `CozyCountUpText`; rings and bars sweep in from zero once.
3. **Always show the next step.** Each card names the nearest reachable target and its exact amount ("S$1,500 to the 75% star").
4. **Kind when behind.** Over-budget states use berry coral and a gentle pet note, never alarms or shaming copy.
5. **Reduce Motion** settles every ring, bar, count-up and burst instantly.
6. **Salary privacy.** The "Kept this month" level is derived from income, so it is masked whenever the month's income is (`isSalaryMasked`).
