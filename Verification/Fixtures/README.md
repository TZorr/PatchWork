# Fixtures

Two real MIDI files, checked in so the harness does not depend on anything
outside the repository. They are what `MIDIFile.parse` is checked against: an
independent parser read the same bytes, and its answers - 58 events ending at
4.485s, and 592 ending at 35.555584s - are asserted in `main.swift` part 14.

Real files rather than only the synthetic one built in the harness: a format is
easy to implement against your own idea of it and hard to implement against
what a sequencer actually writes.

This folder sits outside `PatchWork/PatchWork/`, so the app target's
file-system-synchronized group does not pick it up - nothing here ships in the
app.
