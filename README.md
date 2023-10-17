# Joke

No, it is not a joke.

# Why?

**Back in 2010** I used the most impressive WM I think &mdash; WMFS (version 1).
Then WMFS author ([@xorg62](https://github.com/xorg62)) decided to completely drop WMFS and started working on WMFS2.
It lacks a lot of functionality: EWMH, Xft, always\_on\_top, ...
And I **solely** supported my personal fork of WMFS: [github.com/zhmylove/wmfs](https://github.com/zhmylove/wmfs).

Over time, new technologies emerged and new WM features were required to feel entirely at home, so I dropped WMFS too.
Since that days, I always had **the idea of writing my own WM**.
The perfect time is now.

# What is?

**korgwm** is my personal WM.
I do NOT want to make it highly customizable as I do know my wishes pretty well.
I decided to write it in [Perl](https://www.perl.org/), as Perl is the best language ever.
This WM is not a proof of concept, nor a society-oriented pet-project.
It is just my instrument that I'm going to use on a daily basis.
In it's heart it uses XCB for X11 interaction, AnyEvent for API and event loop and Gtk3 for panel rendering.
It is not reparenting for purpose, so borders are rendered by X11 itself.

# Screenshots

![Tiled windows](resources/screenshots/tiling.png)

![Floating windows](resources/screenshots/tiling.png)

![Expose all windows](resources/screenshots/expose.png)

# Contribution

**Yes**, I do appreciate contribution.
But it should not break the default behaviour of *korgwm*, as I'm going to tune it for myself.
Though this is discussible in your PRs.
Welcome!
