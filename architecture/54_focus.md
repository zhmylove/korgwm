# Focus related things

## Data structures

Hash to handle main focus information.

    $focus = {
      screen => ScreenPtr,
      window => WindowPtr,
    }

Each screen holds a reference to focused window as well.

    $screen = {
      ...
      focus => WindowPtr,
      ...
    }

## Triggers

There could be several reasons of changing focus on the screen.

1. New window created
    1. On a focused screen in foreground: the window obtains focus, focus and screen structures updated as well
    2. On a focused screen in background (due to rule), the window does not obtain focus: no focus related changes
    3. On another screen in foreground: the window obtains focus, focus and screen structures are updated as well
    4. On another screen in background: no focus related changes

2. Some window closed
    1. The window is focused on the focused screen: focus and screen structures are updated, next window from active screen is being selected for focus
    2. The window is focused on another screen: only screen structure is updated as so `focus` field set to `undef`
    3. The window is not focused: no focus-related changes

3. User pressed a hotkey to warp between screens: if `screen->focus` is defined, that window obtains focus, otherwise focus is given to any window on the active tag

4. User switched to another tag...
    1. on active screen: screen and focus structures are updated, if new tag has some windows, they obtain focus (?) randomly or by pointer position, otherwise `screen->focus` is set to undef
    2. on secondary screen: not possible via GUI, to switch between tags, user should move focus; only screen structure is updated: `screen->focus` set to undef... OR just set new active tag as focused :)

5. User moved pointer onto another window: screen and focus structures changes to reflect new focused one


In other words:

| Event                                     | Screen structure                      | Focus structure                       |
| ----------------------------------------- | ------------------------------------- | ------------------------------------- |
| EnterNotify                               | focus = window                        | update screen and window              |
| Switch tag on non-primary screen          | focus = undef                         | -                                     |
| Switch tag on primary screen              | focus = window                        | update window                         |
| Warp pointer to another screen            | only if focus changed                 | update screen and window              |
| Unmap + Delete or Destroy                 | focus = undef on all relevant screens | try to select new window and save it  |
| Map on active tag                         | focus = window                        | update window                         |
| Map on secondary window in foreground     | focus = window                        | -                                     |
| Map on non-active tag                     | -                                     | -                                     |
