# Presets

Ready-made panels for three synths. Open one with File → Open, or double-click
it once PatchWork is installed.

| File | Device | Elements |
|---|---|---|
| `Microkorg.pwork` | Korg microKORG (2002) | 56 |
| `minilogue.pwork` | Korg minilogue | 42 |
| `opsix.pwork` | Korg opsix | 22 |

A `.pwork` file is a **layout**, not a patch: it holds the controls, their
positions and their MIDI addresses — not the sound currently in the synth.
Opening one gives you an editor for that device; the values it starts with are
defaults, not a dump of your instrument.

All three open in **Active Mode**, ready to play rather than to rearrange —
press ⌘R to switch to the editor. `Microkorg.pwork` is also locked (⌘L) so its
arrangement cannot be nudged by accident.

Before playing one, set the ports under the MIDI menu: Output is where the
panel sends.

Check any address that matters against your own manual before relying on it.
Firmware revisions differ, and a wrong address writes to the wrong parameter.
