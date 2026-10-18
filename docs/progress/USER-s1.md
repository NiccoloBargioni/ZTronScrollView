# USER-s1 handoff · 2026-10-18 · Sonnet 5.5
Status: done
Changed: Gesture/PanCoordinator.swift (`PanEnvironment.effectiveAxes`, used for env.axes and bounce); PanSessionTests (+1, 135 total); Demo ImageScreen.swift, Assets.xcassets (generated 600x1800 grid PNG), DemoApp `image` screen, ImageUITests (4).
Decisions: D15 (Orchestration.md). Demo uses `state:` init for outside readouts; `-ZTronImageStateless` runs the exact user snippet with a reader inside the content. `-ZTronImageFits` narrows the image to 100 pt to test rubber-band at 1x.
Open: horizontal indicators/arbitration participant also use the effective axes (same env), not separately tested.
Next: user runs their app with `.zoomRange`; device check of feel.
Tests: ZTronScrollViewTests 135 pass (27.0); ImageUITests 4/4 on 27.0 and 17.5, preferred and forced; full demo UI 24/24 on 27.0 preferred.
Usage: n/a

## How to use for a zoomable image (verified in ImageScreen, stateless variant)
```swift
ZTronScrollView(.vertical, showsIndicators: false) {
    Image("app.global.about.us.snapshot")
        .resizable()
        .aspectRatio(contentMode: .fit)
        .frame(maxWidth: .infinity)
}
.zoomRange(min: .absolute(1), max: .absolute(4))
```
At 1x it scrolls/rubber-bands vertically; once zoomed it pans on both axes while content exceeds the viewport.
