status: work in progress. This line will be removed as soon as this paper become published

# korgwm -- the only tiling window manager in Perl

## Introduction

TODO

## Requirements

Any development should obviously base on formal requirements and this case is not an exclusion.
As I had already been pretty familiar with most tiling WM functionality I need by the time I started writing korgwm, I firstly defined a list of 32 requirements.
I'm not sure presenting them all here worth it, but here are some examples just to illustrate the idea:

- Req.17: there should be a little Panel on top of the screen displaying current input language, time, a title of active window and a list of non-empty tags;
- Req.18: GUI should support Xft in order to use beautiful fonts for Panel;
- Req.19: WM should support not only regular hotkeys, but also media buttons in order to control volume, brightness and so on;
- ...

The full list of [the initial requirements](../architecture/00_requirements.txt) is saved in an architecture directory.

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
| 5 | Typical arguments in favor of subj | Do not know :( | Absence of screen tearing, HiDPI support, true isolation of applications, ... What else? |
| 6 | My personal experience | For the last 10 years I've never experienced any issues with X11 | I've tried to use Wayland on Debian 12 Bookworm with GNOME3 and some things worked improperly: WebRTC screen sharing shown a black screen instead of the picture, Atlassian Confluence page hierarchy not shown a cursor when I moved a page in it |
| 7 | Last, but not least: the library for the language I'll use | There are several modules: X11::Xlib (supports some functionality for WM), X11::XCB (only client-side functionality), X11::Protocol (hard-to-use pure protocol library) | A single lonely "WL" in which only client part is [partly] implemented |

As you can see, Wayland has several advantages over X11: specifically modern screens support.
But there are only FHD screens in my setups so I cannot see the real difference.
*Later, I tried using korgwm on a 4k screen, and everything looked smooth*.
I am also the only user of my PC/Laptop/etc, so I need no isolation or so.
As for performance, I see no difference as well.

At the same time X11 is much more mature than Wayland.
Wayland initial release was somewhere around 2008.
In six years it'll have the same age as X11 had by the time Wayland development started and it is still complex and not well documented.
Taking into account that personally I come across 2+ UI issues in Wayland, I suppose the world deserves a better, clearer and more understandable display system than it.

#### A couple of words regarding Wayland frameworks

There are actually several frameworks that encapsulate a lot of Wayland-specific work.
Such as: wlc, libweston, and wlroots.
I'm not very familiar with them, but I am pretty sure they have their own limitations.
In the [Way-cooler book](https://way-cooler.org/book/wlroots_introduction.html), wlroots are defined as: "*Pluggable, composable, unopinionated modules for building a Wayland compositor; or about 50,000 lines of code you were going to write anyway.*"
I prefer not to write so many lines of code if possible ;-)
Mostly due to a desire to obtain full control over the processes happening under the hood, I decided not to confine myself to the strict limits of those frameworks.

**As a result**: my personal choice for writing the very first WM is definitely X11.

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

Most likely you can name at least 3 languages you'd choose for WM development.
And even if you name 16 of them I still bet Perl would not be among them.
Many people may consider way too insane starting new project using Perl in a world with all those modern GPPL: Golang, Rust, C/C++, Lua, Python, ...
Unfortunately, nowadays Perl become underestimated and pretty unpopular language.
In spite that it is still being actively developed and has a lot of pretty unique functionality.

Several factors determined the choice of a language for development, besides the fact that Perl actually is my native language.

1. Perl gives an extreme speed writing prototypes: you can use tons of existing CPAN modules and write only tens lines of code in order to create powerful applications.
2. It's pretty easy to replace some parts of prototypes written in Perl with performant code in C -- Perl out of the box supports a lot of techniques for that: XSUB, FFI, even asynchronous micro-service architecture and fast IPC.
3. Being syntactically rich language Perl gives a number of ways for expression the same ideas in different words and all those expressions would just work: it does not imprison you into poor frameworks invented by some other people.
4. There already were several Perl modules for X11 interaction. *Although none of them were actually suitable for WM development*.

Given so much advantages using Perl I just did not find any drawbacks of it and thus **the choice was obvious**.

## Development

### A word to PerlWM

Speaking about window managers in Perl, it's impossible not to mention [perlwm](https://perlwm.sourceforge.net/).
Being written around 2002---2004, I believe, it's the very first WM written entirely in Perl.

This WM uses `X11::Protocol` under the hood and more-less looks like `twm`, the standard stacking window manager for X11.
Having 3966 lines of Perl code, this WM covers a lot of functionality of stacking window managers.

Fun fact: on the author's website, it says:
"*So, rather than do _the right thing_ and contribute to an existing window manager, I decided to write my own - in perl.
All the mature window managers looked pretty tricky to make any major changes - especially changes in behaviour.*"
However, his twenty-year-old code is also too complex to modify or use as a base for new projects.
Especially since `X11::Xlib` and `X11::XCB` emerged in 2009 instead of a raw `X11::Protocol`.

Let this paragraph be a kind of tribute to PerlWM.

### X11-XCB and Michael

The very first author of the XCB module for Perl is Michael Stapelberg, the creator of the well-known `i3` window manager.
He wrote a rather raw version of the package, which allowed him to perform certain tasks needed for `i3` testing.
It lacked some functionality related to the client and had nothing at all regarding the server-side part.
Nevertheless, it was a working version that supported a portion of XCB functions.
It's great that Michael chose Perl, as it's a cool and simple language, and he published his module on CPAN so others could use it.

Naturally, the first thing I did was propose a rather large patch for `X11::XCB`, which introduced some functionality I needed.
Michael and I had a chat, and since he's not as passionate about Perl now as he was in 2009---2011, we agreed that the maintenance of this package would be transferred to me.
In return, before each release of `X11::XCB`, I would test it both with the latest stable tag of `i3` and its master branch.

That's how I became the maintainer of `X11::XCB` and subsequently made several significant improvements, which now allow it to be used for managing the X11 server.

### Packages for ArchLinux and FreeBSD

TODO

## Bad architectural decisions

### Window shown on multiple tags and Tags VS Workspaces

TODO

### Windows re-arrangement on screen change

TODO

### Expose module

Didn't you know: it's pretty difficult to get "a screenshot" of all the windows in X11.
I bet Wayland built all around its famous "security" does this job even worther.

First thing first.
As I've already based some functionality on Gtk3 -- namely written a panel using this library -- I decided to write a little window chooser.
It is not a mandatory requirement to built such a thing into a WM, more or less it was just my desire to write one with my personal hotkeys and UX.

At the very early stages I created two little PoC applications: one contained an area displaying some other window and another created a window and placed some tiles in a table grid.
The idea of the latter was to come out with some suitable scaling algorithm: tiles should be proportionally resized based on their count and screen resolution.

Done with that I quickly enough implemented Expose.pm combining those ideas.
This time it was much more mature application: full-screen window with no decoration aka 'popup', nice looking colours, support for lots of hotkeys, several optimizations...
I was so happy absolutely not noticing how badly increased memory consumption.
Below will definitely be a couple of words on memory leaks analysis, to cut is short: GdkPixbuf creates way much Perl objects resulting into several MBytes overhead per window.
Moreover, it revealed that even GDK developers not happy with it as the most recent commit bda80c4e41 says: "It's a bad function, and people should feel bad about using it".
GdkPixbufs do not manage to properly dump partially obscured windows, nor able they to handle off screen windows.
And thus I decided to rework so called "X11 foreign windows" GdkPixbufs with some other techniques.

The solution was found during one of my daily meetings: once setting up desktop sharing in a web browser I saw a window selection dialog with pretty thumbnails for each of my windows.
At that time I asked myself where and how did my web browser get all those images.
Not waiting too long I cloned webrtc repo and inspected all the code under `modules/desktop_capture` -- there are two approaches: both require X11 composition extension.
One approach based on asking X11 to share pixmap memory of a window, while the other falls back to XImage interface.

I've updated X11::XCB -- added support for XComposite extension and implemented `xcb_get_image_data()` function in order to get image data directly from Perl code.
After a couple of hours refactoring Expose.pm I got a solution which consumed less memory and even was able to free some, reducing memory usage of a Perl program!
At the time I'm writing this text this solution still uses pixbufs for scaling and rendering of those images but it works way better.

The images from X11 server are usually encoded into BGRA32 format, while Gtk3 pixbufs support importing of only RGB8 (8 bits per sample, including alpha channel).
Each screenshot takes around 20 Mbytes, so in order to effectively translate colour channels I decided to add `get_image_data_rgba()` XS function to `X11::XCB`.
This function does all the job much faster and allows using of Gtk3 GdkPixbufs with proper colors.
And only after all those code fixes, Expose module became not so bad from an architectural point of view.

## Problems solved

### Memory leaks -- Devel::MAT, window destruction and X11-XCB

This part is not that interesting, so I'll be brief.
During the development, I faced a couple of memory leaks.
These kinds of situations can be resolved using the `Devel::MAT` module, which is a great and powerful tool for memory analysis in Perl.

One leak was right inside the XS code of `X11::XCB`.
I noticed that invoking Expose leads to a continuous increase in RSS (Resident Set Size) memory without any reasonable cause.
After some research, I discovered that the XCB library's `xcb_get_image()` function returns an X11 image as a pointer to a memory buffer, allocating it behind the scenes.
This resulted in a memory leak because XCB.xs did not properly use `free()` to clean up this memory.

Another memory leak was due to my personal, typical, and pretty embarrassing error.
While improving some functionality related to windows, I added an index structure that referred to windows by their references.
Keeping in mind that those references must be undefined when the window is deleted, I, without much thought, wrote this code directly inside the `Window::DESTROY` handler.
And that's it!
In this case, `Devel::MAT` was even more helpful, as it allowed me to find cross-references and pinpoint the problematic part of the code.

## Conclusion

Writing a window manager is not a very difficult task.
It is more like an educational, creative, and fun amusement.
If you have ever thought about writing a WM in a way that feels true to you, do not hold yourself back.
I encourage you to grab your favourite language and create your own ideal window manager!
