# ParallelX

Minimal iOS 15 / Dopamine RootHide / arm64e floating-app experiment. This is
a new project: it does not package or link Myrtle or MoxuanSplit.

Alpha 1 scope: select applications in Settings, pull a narrow panel from the
right edge, tap one application to open a single floating window, and close it
with the title-bar button. There are no shortcuts, radial selector, resize,
multiple windows, or background-card changes.

Swift owns the panel, preferences picker, window presentation, and animations.
Objective-C is limited to SpringBoard injection, installed-app enumeration,
and iOS 15's private Scene/layer-host boundary. The panel design is informed
by the user's BottomControlX branch, but this project does not copy its UI code.

This is a **device-test alpha**, not a stable replacement. Do not install it
alongside Myrtle, MyrtleSwitcherFix, or MoxuanSplit. First verify warm app
opening, visible interactive content, closing, and absence of SpringBoard
crashes. Cold launches, keyboard, rotation, backgrounding, and long-term
resource use are not validated.

Build on macOS with Xcode, roothide/theos, and the iPhoneOS 16.5 SDK:

```sh
make clean package THEOS_PACKAGE_SCHEME=roothide
```
