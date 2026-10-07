# ArinController

Rear-paddle action panels and controller profiles for **WoW: Forever**, built
into the native gamepad crossbar. Designed for the Xbox Elite Series 2, the
PlayStation DualSense Edge, and any controller whose extra buttons can be
mapped to keys on PC.

ArinController is a modified and renamed fork of
[Backhand](https://github.com/snrn-Pontus/Backhand) plus a profile system.
See **Credits & License** at the bottom.

Forever's crossbar gives you the d-pad and face buttons on four layers (no
trigger, LT, RT, LT + RT). ArinController adds a 2 x 2 group for the P1-P4
paddles to each layer: 16 more actions without taking your thumbs off the
sticks. The panels use Blizzard's own crossbar art, expand and highlight
exactly like the native bars, and sit next to the bar that uses the same
trigger combination.

Built for **World of Warcraft: Forever** only (Interface 16001). It relies on
Forever's native crossbar and gamepad API and does nothing on other clients.

## Quick start

1. Map each paddle to a key WoW does not use. Xbox Elite with the Xbox
   Accessories app: paddle to F9, F10, F11, F12. Steam Input or reWASD (Xbox
   Elite, DualSense Edge, others): paddle to F13, F14, F15, F16.
2. In game open **Settings > AddOns > ArinController** (or type `/arincontroller`),
   click **Assign P1-P4** and press each paddle in turn.
3. Drag spells, items or macros onto the paddle slots. Hold LT, RT or both to
   fill the other layers.

Panels can be moved in WoW's normal Edit Mode, or with **Unlock panels outside
Edit Mode** in the settings. `/arincontroller reset` puts them back into the
crossbar.

## Profiles

Profiles are saved **per character**. Each profile stores:

- the **native crossbar layout** — every d-pad and face-button slot across all
  four trigger layers and all three action-bar pages, **except the reserved
  base X/Y/A/B face buttons** (those are system buttons the game keeps; a
  profile never touches them);
- the **pet utility bar** and the **active stance/form bar** storage ranges;
- every bound action **by its true type**, including icons Forever allows on
  the crossbar beyond plain spells and items (pet utilities, stance icons,
  mounts/critters, flyout wheels) — nothing is dropped because its type is
  uncommon;
- the four **paddle inputs** (`P1`-`P4` keys);
- the 16 **paddle action slots** (4 layers x 4 paddles).

Switching profiles restores the whole layout, so a profile is a full controller
setup rather than just the paddles.

### Create
**Create new profile** makes a brand-new profile that is empty everywhere except
the reserved base X/Y/A/B buttons: every crossbar slot and paddle is unbound
until you assign it. Pick the controller type first:

- **Xbox Elite** — four back paddles.
- **Xbox Standard** — no back paddles. A Standard profile drops all paddle
  bindings and **hides the on-screen panels and the Settings paddle rows**
  while it is active, because the controller has nothing to assign them to.

New profiles are named `Xbox Elite N` / `Xbox Standard N`, reusing the lowest
free number (deleting `Xbox Elite 2` lets the next create become `Xbox Elite 2`
again).

### Copy
**Copy current profile into target** overwrites the chosen existing profile's
data with the active profile's, without changing its **name** or its
controller type. Copying into a Standard target keeps the paddles dropped; a
Standard target simply has no paddles to keep. The base X/Y/A/B buttons are
never copied.

### Delete
**Delete target profile** removes the chosen other profile. The active profile
and the last remaining profile cannot be deleted.

Slash equivalents: `/arincontroller profile list|new <elite|standard>|switch
<id or name>|delete <id or name>|copy <id or name>|slots|actioninfo [n]`.

## Settings

Open with **Settings -> AddOns -> ArinController**, or type `/arincontroller`.
Options include:

- **Profiles** — controller type, create/copy/delete, active profile.
- Unlock panels outside Edit Mode.
- Only show in gamepad mode (panels hide in mouse-and-keyboard mode, stay
  visible while unlocked or in Edit Mode).
- Paddle inputs (one row per paddle, click to assign by pressing), Assign
  P1-P4, Setup guide.
- HUD scale.
- Inactive panel opacity (1.00 = native, no fading).
- Focus highlight and strength.
- LT / RT modifier icons (off by default; the native crossbar shows the same
  prompts).
- Paddle prompts on the focused panel.
- Diagnostics.

## Paddle inputs

On Windows the Xbox Elite Series 2 does not report its paddles to games, and
the DualSense Edge's back buttons arrive as copies of the face buttons. WoW only
sees whatever the Xbox Accessories app, Steam Input or reWASD maps a paddle to,
so ArinController listens for a configurable input per paddle instead of
assuming the native `PADPADDLE1-4` keys.

ArinController never takes over a button the native gamepad UI uses. Accepted
inputs are only ones WoW does not use:

- physical keyboard keys with no WoW binding (F9-F12 on a compact keyboard;
  also F6-F8, Page Up/Down, Scroll Lock, Pause, or Numpad keys), for the Xbox
  Accessories app's keyboard key mapping;
- the Share button (unused by the native UI, if Xbox Accessories offers it for
  your controller);
- keyboard F13-F24, for Steam Input or reWASD sending keys that are not on the
  keyboard;
- the native paddle keys, for controllers that actually report paddles.

**Assign by pressing** opens a prompt and assigns each paddle to whatever the
controller sends when you press it. If that is A, B, X, Y, a stick click, or
any other native button, the prompt refuses it, explains that the controller
profile is mirroring the paddle, and keeps waiting. Keyboard keys that already
have a binding are refused too. **Setup guide** opens an in-game window with
step-by-step instructions for both routes and a live "last input detected"
line.

Two routes:

1. **Xbox Accessories keyboard mapping**: map each paddle to a real key WoW
   leaves unbound (F9-F12 on a compact keyboard; also F6-F8, Page Up/Down,
   Scroll Lock, Pause, or Numpad keys), then use Assign by pressing. Share also
   works for one paddle if the app offers it.
2. **Steam Input or reWASD**: install Steam's Xbox Extended Feature Support
   driver (or use reWASD), map the paddles to F13-F16, leave them unassigned in
   Xbox Accessories, and select Keyboard F13-F16 in the addon. All four paddles
   work and the native layout stays intact. If a paddle press flips the UI to
   mouse-and-keyboard mode, pin the interface style to gamepad in the game's
   controls settings.

**PlayStation DualSense Edge**: Sony has no PC app for the Edge, and without a
profile the back buttons and Fn buttons just repeat face buttons (Steam shows
them as Circle and Cross, so the addon refuses them). Steam Input and reWASD do
see the back buttons as their own inputs: add WoW as a non-Steam game, enable
PlayStation controller support in Steam's controller settings, bind the two
back buttons (and, if you like, the two Fn buttons) to F13-F16, and use route 2
above. A PS5 is not needed for this.

The client's own default config for the Elite Series 2 (vendor 1118, product
767) maps raw buttons 16-19 to PADPADDLE1-4, but the controller never sends
them on Windows. `/arincontroller test` shows raw presses; `/arincontroller
learn` is only useful for controllers whose paddles arrive on other raw
indices.

## Usage

Drag a spell, item, macro, or supported action-bar action onto any paddle slot.
Press P1-P4 to activate the corresponding action in the currently active
controller layer.

Paddle actions, native crossbar layout and profiles are saved per character.
Paddle keys, panel positions and the appearance settings are shared by every
character on the account.

## Slash commands

- `/arincontroller` (or `/arincontroller options`) — open native settings.
- `/arincontroller unlock` — move panels outside WoW Edit Mode.
- `/arincontroller lock` — lock panels outside WoW Edit Mode.
- `/arincontroller reset` — reset all four panel positions to the nested
  crossbar layout.
- `/arincontroller reset <base|lt|rt|both>` — reset one panel.
- `/arincontroller clear <base|lt|rt|both> <1-4>` — clear one paddle action.
- `/arincontroller guide` — open the setup guide window.
- `/arincontroller assign [1-4]` — assign one paddle (or all four in order) by
  pressing it.
- `/arincontroller keys [P1 P2 P3 P4 | reset]` — show or set the paddle inputs,
  e.g. `/arincontroller keys F13 F14 F15 F16`.
- `/arincontroller profile list|new <elite|standard>|switch <id or name>|delete
  <id or name>|copy <id or name>` — manage controller profiles.
- `/arincontroller profile slots` — list the crossbar/stance/pet storage ranges
  and the action type in every tracked slot (used to validate the ranges).
- `/arincontroller profile actioninfo [n]` — print the raw GetActionInfo (type /
  id / subType) of the tracked slots; useful for reporting bindings that are
  unusual or not copying.
- `/arincontroller diag` — print gamepad integration diagnostics.
- `/arincontroller diag copy` — open the same diagnostics as plain text you can
  select and copy.
- `/arincontroller test` — for 30 seconds, print the raw controller button
  index of anything you press and what the client maps it to.
- `/arincontroller learn [force|cancel|clear]` — press P1-P4 in order to map
  them to PADPADDLE1-4 in the client's gamepad config.
- `/arincontroller glowtest` — toggle the proc glow on every filled slot.
- `/arincontroller help` — print command help.

## Diagnostics

`/arincontroller diag` reports the addon version and client build, native
storage status and slots, storage scope, LT / RT bindings, modifier-emulation
CVars, LT / RT mapped button indices and values, visual detection method,
secure panel, native style CVars, native art availability, secure panel-driver
mode, and Edit Mode integration state. **View Diagnostics** in the Settings
Diagnostics section (or `/arincontroller diag copy`) opens it as selectable
plain text you can Ctrl+C into a bug report.

## Credits & License

- **Backhand** — the addon ArinController is forked and renamed from, by
  SillyNameRandomNumber (`https://github.com/snrn-Pontus/Backhand`). MIT.
- **PulseHaptics** — the taint-free dropdown/popup approach in Settings.lua is
  adapted from it, by codingdoctorbot. MIT.
- ArinController modifications copyright (c) 2026 Arinrare, also MIT.

See `LICENSE` for the full license and attribution text. ArinController is an
unofficial fan project and is not affiliated with or endorsed by Blizzard
Entertainment.

## Releasing

Releases are automated with the BigWigs packager via GitHub Actions
(`.github/workflows/release.yml`). Pushing a tag builds the addon, uploads it
to CurseForge, and creates a GitHub Release.

```bash
git add -A
git commit -m "Describe your change"
git tag -a v0.0.2 -m "v0.0.2"
git push origin main --follow-tags
```

- The tag name (e.g. `v0.0.2`) becomes the addon version, via
  `## Version: @project-version@` in the TOC.
- Tags **must start with `v`** to trigger the workflow.
- Use `alpha`/`beta` in the tag (e.g. `v0.0.2-beta1`) for a pre-release build.
- Requires the `CF_API_KEY` repository secret (Settings -> Secrets and variables
  -> Actions).
- If a tag push doesn't start the workflow, re-push that tag:
  `git push origin :refs/tags/<tag> && git push origin <tag>`.