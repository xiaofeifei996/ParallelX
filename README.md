# ParallelX

Minimal iOS 15 / Dopamine RootHide / arm64e floating-app experiment. This is
a new project: it does not package or link Myrtle or MoxuanSplit.

Alpha scope: select applications in Settings, pull a narrow panel from the
right edge, tap one application to open a single floating window, resize it
from either bottom corner, drag it from the bottom-center grip, open it full-screen
from the title bar, or close it. Window corner radius is adjustable in Settings.
There are no shortcuts, radial selector, multiple windows, or background-card changes.

Swift owns the panel, preferences picker, window presentation, and animations.
Objective-C is limited to SpringBoard injection, installed-app enumeration,
and iOS 15's private Scene/layer-host boundary. The panel design is informed
by the user's BottomControlX branch, but this project does not copy its UI code.

This is a **device-test alpha**, not a stable replacement. Do not install it
alongside Myrtle, MyrtleSwitcherFix, or MoxuanSplit. First verify warm app
opening, visible interactive content, closing, and absence of SpringBoard
crashes. Cold launches, keyboard, rotation, backgrounding, and long-term
resource use are not validated. Application scenes are uniformly scaled within
the floating window; ParallelX does not inject into application processes.

Build on macOS with Xcode, roothide/theos, and the iPhoneOS 16.5 SDK:

```sh
make clean package THEOS_PACKAGE_SCHEME=roothide
```
