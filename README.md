# Universal Live Viewport

Universal Live Viewport is a docked editor panel extension for Godot 4.x that enables real-time 2D and 3D rendering of any active scene directly inside the editor. It provides developers with precise telemetry, alignment rulers, and optimized camera previews without runtime overhead.

## Features

- **Automated Mode Detection:** Automatically identifies whether the active scene is 2D or 3D and configures camera parameters and drawing overlays accordingly.
- **Dynamic Camera Selector:** Scans active scenes recursively to find game cameras (`Camera2D` or `Camera3D`). Developers can toggle between the editor's damping debug camera and any scene camera to preview gameplay perspectives in real-time.
- **Pixel-Accurate Rulers:** Includes CAD-style pixel rulers on the top and left borders that scale and offset dynamically based on active camera positioning and zoom.
- **Auto-Scaling Technical Grid:** Overlays a Cartesian coordinate grid with primary X (red) and Y (green) axes at origin `(0,0)`, automatically adjusting spacing steps depending on zoom density.
- **Physically-Damped Controls:** Provides orbital rotations, pans, and zooms via smooth lerp damping for visual fluidity.
- **Idle Energy Efficiency:** Pauses processing and disables rendering updates when the dock is hidden or docked behind other tabs (zero GPU/CPU background overhead).

## Installation

1. Copy the `addons/live_viewport` folder into your project's `addons` directory.
2. Navigate to **Project -> Project Settings -> Plugins** and enable **Universal Live Viewport**.
3. The visualizer panel will appear docked in your editor tabs.

## Configuration & Usage

### 3D Navigation
- **Orbit rotation:** Hold **Right Mouse Button (RMB)** and drag.
- **Pan viewport:** Hold **Middle Mouse Button (MMB)** or **Shift + Right Mouse Button (RMB)** and drag.
- **Zoom viewport:** Scroll the **Mouse Wheel** to zoom.

### 2D Navigation
- **Pan viewport:** Hold **Right Mouse Button (RMB)** or **Middle Mouse Button (MMB)** and drag.
- **Zoom viewport:** Scroll the **Mouse Wheel** or use the **(+)** and **(-)** buttons on the toolbar.

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for more information.

Developed by **NJALISTON** (<sparkmartines@gmail.com>).
Repository: [https://github.com/NJALISTON/VIEWPORT](https://github.com/NJALISTON/VIEWPORT)
