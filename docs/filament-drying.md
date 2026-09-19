# Filament drying timers

Filament items no longer need a manually entered drying time. Starting drying, restarting a timer, bulk status changes, and the item editor all use the same rules:

1. Use a positive saved duration if one exists.
2. Otherwise estimate from the material and filament weight per spool. Missing, zero, or invalid weight uses 1 kg. Item quantity and spool tare do not multiply the duration.
3. Unknown materials receive a generic six-hour baseline. Every estimate can be overridden.

The duration field can stay blank. Generic material suggestions no longer become saved overrides. Existing saved durations remain unchanged. Each running cycle keeps its starting duration even if weight or material is edited later.

## Defaults

At 1 kg: PLA/HTPLA, PETG, PCTG, ABS and TPU use six hours; ASA four hours; PC five hours; Nylon/PA/PPA twelve hours; PVA/BVOH eight hours. Blends such as PA6-CF use their base material.

These are timer starting estimates, not moisture measurements or heater settings. Existing app templates supply most baselines. Manufacturer guidance varies by grade, dryer, and temperature; see [Prusa drying guidance](https://help.prusa3d.com/article/drying-filament_332086) and [Bambu filament guide](https://cdn1.bambulab.com/filament/filament-guide/250123/filament-guide-en.pdf). Use the spool manufacturer's procedure when available.

Weight adjustment is an Inventorinator heuristic, not a manufacturer-validated formula: multiply the baseline by `max(0.75, sqrt(weight grams / 1000))`, rounded up to 15 minutes. It avoids treating half a spool as needing half the drying time. A missing weight behaves exactly like 1 kg.

## Owner policy

Remote Settings → **Require manual drying times** is off by default. Only the workspace Owner can change it; other devices read the setting. When enabled, a positive saved duration is required before starting/restarting drying. Other edits and already-running cycles are unaffected. The cached policy is used offline; server schema 32 enforces it when changes sync. Policy changes do not alter timers already running.
