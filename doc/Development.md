status: work in progress. This line will be removed as soon as this paper become published

# korgwm -- the only tiling window manager in Perl

## Introduction

## Requirements

## Architectural decisions

### X11 vs Wayland

Starting the development at the middle of 2023 I had to carefully choose proper display system to base my WM on.
After a short review of all existing display systems my choice has narrowed down to mature but pretty old X11 (specifically X.Org) and buggy but pretty perspective Wayland.
The latter is not the independent system itself, but more like a protocol and some libraries around it for communication.

I've done my little comparison and I'm happy to present my vision on the differences from the developer side.
Moreover I already had several [useless] discussions with all those religious fanatics of either X11 or Wayland.
So now I have to state that my comparison results reflect only my personal opinion and do not pretend to be the truth in the first instance.

| **#** | **Domain** | **X11** | **Wayland** |
|:---:|:---:|:---:|:---:|
| 1 | Completeness and convenience of a documentation | There are several books and some papers on writing the WM based on X11. The documentation of Xlib is more-less complete. The documentation of XCB mostly marked as TODO, but libxcb source code has lots of useful comments. The X11Protocol is pretty well documented | The documentation looks pretty confusing and inconsistent. If you're not agree: just try to implement your own simple Compositor |
| 2 | Existing WM or pet-projects that could be used as a reference or help | Tons of tiling WMs including some I already familiar with: dwm, awesomewm, i3wm, wmfs, bspwm, ... | Not so much: wlroots, dwl, sway |
| 3 | The most popular according to "Tiling WM Mastery" Telegram group | 2x more votes for X11 | Only several people recommended Wayland |
| 4 | How much should be implemented | X server does a lot of work, so writing a WM for X11 is mostly about writing it's business logic | In order to write a WM for Wayland one have to implement the full Compositor functionality |
| 5 | Typical arguments in favor of subj | Do not know :( | Absense of screen tearing, HiDPI support, true isolation of applications, ... What else? |
| 6 | My personal experience | For the last 10 years I've never experienced any issues with X11 | I've tried to use Wayland on Debian 12 Bookworm with GNOME3 and some things worked improperly: WebRTC screen sharing shown a black screen instead of the picture, Atlassian Confluence page hierarchy not shown a cursor when I moved a page in it |
| 7 | Last, but not least: the library for the language I'll use | There are several modules: X11::Xlib (supports some functionality for WM), X11::XCB (only client-side functionality), X11::Protocol (hard-to-use pure protocol library) | A single lonely "WL" in which only client part is [partly] implemented |

As you can see, Wayland has several advantages over X11: specifically modern screens support.
But there are only FHD screens in my setups so I cannot see the real difference.
I am also the only user of my PC/Laptop/etc, so I need no isolation or so.

At the same time X11 is much more mature than Wayland.
Wayland initial release was somewhere around 2008.
In six years it'll have the same age as X11 had by the time Wayland development started and it is still complex and not well documented.
Taking into account that personally I come across 2+ UI issues in Wayland, I suppose the world deserves a better, clearer and more understandable display system than it.

**As a result**: my personal choise for writing the very first WM is definitely X11.

### Xlib vs XCB

One way to write an application talking to X11 server is use of X11Protocol.
This approach requires to implement binary coder-decoder for 200+ data structures (requests, events, ...), proper connection handling and a logic around the connection itself.

Xlib was created to simplify this task.
It takes the responsibility of all these things.
Moreover, it has built-in cache for several requests to offload burst X11 requests onto it.
Moreover, it provides a synchronous interface to asynchronous-by-design X11 protocol.
To cut it short: it is not only well documented but also way too complicated.

As a response, community created a "lightweight" library -- XCB (an acronym for "X11 C bindings").
This library provides an asynchronous interface and literally bindings to X11 protocol.
It covers all those nasty things around X11 interaction revealing pure X11 protocol via usable and simple functional interface.
The only problem of XCB is its (absent) documentation:

    $ find /usr/share/man/ -name 'xcb_*' -exec man {} + | grep -c TODO
    10666

But there are several "official" tutorials on their website and self-descriptive comments in libxcb source code.
If doubt -- just check "src/xproto.h".
And as far as XCB are actually just simple bindings to X11 protocol, it's documentation answers on a huge number of developers questions.

**As a result**: most modern applications are built on top of XCB.
And I decided to use XCB as well.

### Why Perl

## Development

### A word to PerlWM

### X11-XCB and Michael

### Packages for ArchLinux and FreeBSD

## Bad architectural decisions

### Window shown on multiple tags and Tags VS Workspaces

### Expose module

## Problems solved

### Memory leak -- Devel::MAT and X11-XCB

## Conclusion
