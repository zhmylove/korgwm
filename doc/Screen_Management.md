# Screen Management in korgwm

`korgwm` dynamically handles changes in the X11 output configuration, such as when monitors are connected or disconnected via HDMI or DisplayPort. This document explains the internal workflow of this process.

### X11 Basics: Outputs vs. Monitors

To understand how `korgwm` manages displays, it is essential to distinguish between three related but different concepts in X11:

*   **Outputs:** Physical connectors (HDMI, DisplayPort, eDP) and the monitors attached to them. The `xrandr` tool manages outputs — it can turn them on or off (`--auto`, `--off`), set their resolution, and position them relative to each other (`--left-of`, `--right-of`). This is the **hardware/connector level**. An output typically corresponds to one physical monitor.

*   **Monitors:** A more flexible concept introduced in newer versions of RandR. Using `xrandr --setmonitor`, you can define a monitor as a **region of the screen** that may span multiple outputs, or conversely, split a single output into multiple independent monitors. For example, you could create two separate monitors on a single ultra-wide display, each with its own workspace and panel. This is the **logical region level**.

*   **Screens (CRTCs):** In the traditional X11 sense, a "screen" represents a drawing area with a contiguous coordinate space. With RandR, this concept becomes less relevant for day-to-day configuration. **`korgwm` internally uses the term "screens" differently — as objects representing each logical monitor.**

When you connect a new physical display, the X server generates a RandR event. `korgwm` reacts to this event by re-evaluating the **monitors** available to it, creating a separate `X11::korgwm::Screen` object for each. It then relies on a user-defined `xrandr` command to properly configure both the physical outputs and any custom monitor definitions.

### Core Principle: Reacting to RandR Events

`korgwm` does not poll for changes. Instead, it listens for `XCB_RANDR_SCREEN_CHANGE_NOTIFY` events from the X server. When the physical display configuration changes, the X server generates this event, which is the primary trigger for the window manager to reconfigure its virtual desktops (screens).

### Step-by-Step Workflow

1.  **Event Trigger:** A monitor is connected or disconnected. The X server detects this and sends a RandR event to all listening clients, including `korgwm`.

2.  **Initialization of Reconfiguration:** `korgwm`'s main event loop receives this event and calls the core function `handle_screens()` (located in `lib/X11/korgwm.pm`).

3.  **Querying New State:** `handle_screens()` queries the X server for the current list of monitors and their geometries (width, height, x, y offsets) using `$X->screens()`. This represents the new logical monitor configuration — regardless of whether each monitor corresponds to a physical output or a custom-defined region.

4.  **Detecting Changes:** The function compares the newly acquired monitor list (`%curr_screens`) with the previously stored list (`%screens`) to identify:
    *   `@new_screens`: Monitors that have just been added.
    *   `@del_screens`: Monitors that have been removed.
    *   If there are no changes, the function exits early to avoid unnecessary work.

5.  **Handling Removed Monitors:**
    *   For every monitor being removed, its `destroy()` method is called.
    *   All windows that were on that monitor are migrated to a "survivor" monitor (the first remaining monitor in the list).
    *   The window manager saves the preferred position (monitor and tag index) for every window relative to the *new* monitor count. This allows windows to return to their logical workspace if the monitor is recreated later.

6.  **Handling New Monitors:**
    *   For every new monitor detected, a new `X11::korgwm::Screen` object is instantiated. This object creates its own set of tags (workspaces) and a new panel.

7.  **Re-indexing and Window Placement:**
    *   The `@screens` array is sorted, typically by their X-axis position, to maintain a consistent left-to-right order. Each screen object is assigned a new index.
    *   `korgwm` then iterates through all managed windows. It attempts to place them on their preferred monitor and tag. This preference is either saved from step 5 or defined by the user's placement rules in the configuration file.

8.  **Restoring Focus and Refreshing:**
    *   The system attempts to restore the last active tag on each monitor.
    *   All screens are refreshed, which redraws the windows in their new layout and updates the panels to reflect the current tag state.

9.  **Post-Reconfiguration Hook (`randr_cmd`):**
    *   After `korgwm` has updated its internal state, moved windows, and recreated panels, it executes the command specified in the user's configuration as `randr_cmd`.
    *   By default, this command is configured as:
        ```perl
        $cfg->{randr_cmd} = "korgwm_xrandr || xrandr --auto";
        ```
    *   This means `korgwm` first attempts to execute `korgwm_xrandr` — a user-provided script that should be placed in `$PATH`. If this script is not found or fails to execute, it falls back to the simple `xrandr --auto` command.
    *   The `korgwm_xrandr` script gives users full control over the final display configuration. A working example can be found in the repository at `resources/korgwm_xrandr`:
        ```bash
        #!/bin/sh
        xrandr --output HDMI-A-0 --left-of eDP --auto \
               --output DisplayPort-0 --right-of eDP --auto \
               --output eDP --primary
        exit 0
        ```
    *   This script interacts with `xrandr` at the output and monitor level. While `korgwm` now understands the new monitor setup, the underlying X server outputs might still be misconfigured (e.g., disabled, wrong position). Additionally, any custom monitor definitions using `--setmonitor` need to be reapplied.
    *   A well-written `korgwm_xrandr` will enable all connected outputs with `--auto`, arrange them using positional flags (`--left-of`, `--right-of`), set a primary output, and optionally define custom monitor regions with `--setmonitor`. This finalizes both the physical and logical display layout.

### Summary

`korgwm` handles screen changes through a robust, event-driven process:
1.  Detects a change via a RandR event.
2.  Reconstructs its internal `Screen` objects to match the new monitor geometry.
3.  Relocates windows intelligently based on saved preferences or rules.
4.  Executes a user-provided `randr_cmd` (with fallback to `xrandr --auto`) to properly configure X11 outputs and custom monitor regions, ensuring a seamless multi-monitor experience.
