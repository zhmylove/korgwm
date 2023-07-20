#!/usr/bin/perl
# vim: sw=4 ts=4 et cc=119 :
use strict;
use warnings;
use feature 'signatures';
use open ':std', ':encoding(UTF-8)';
use utf8;
use X11::Xlib ':all';
use X11::Protocol;

use Data::Dumper; # TODO remove

# TODO Should get from config
my $panel_height = 20;

my $X = X11::Protocol->new();
$X->init_extension("XINERAMA") or die "XINERAMA not available";
# $X->XineramaIsActive(), $X->XineramaQueryScreens()

my $display = X11::Xlib->new();

printf STDERR "Screen count: %s\n", $display->screen_count(); # TODO remove
die "Use XINERAMA or die!" unless $display->screen_count() == 1;

my $screen = $display->screen(0);

printf STDERR "$_ => %s\n", $screen->$_ for qw( width height width_mm height_mm depth root_window_xid root_window ); # TODO remove

my $root = $screen->root_window;

$root->event_mask_include(SubstructureRedirectMask, SubstructureNotifyMask);

for(;;) {
    # TODO rewrite event loop to handle events from Xlib, Gtk and AE and set timeout = 0
    my $evt = $display->wait_event(timeout => 0.01);
    next unless defined $evt; # TODO check if wait_event could be interrupted
    warn $evt->type;
    my $ref = ref $evt;

    printf STDERR "Evt: %s (w:%s)\n", $ref, $evt->window // "undef";

    if ($ref eq "X11::Xlib::XMapRequestEvent") {
        # TODO resize window here ..?

        my $win = X11::Xlib::Window->new(display => $display, xid => $evt->window);

        # Handle known startup ids
        my $startup_id = $win->get_property($display->mkatom("_NET_STARTUP_ID"));
        $startup_id = defined $startup_id ? $startup_id->{data} : "";
        warn Dumper ["Startup ID:", $startup_id];

        if (index($startup_id, "korgwm-panel-") == 0) {
            # TODO handle RandR somehow to distinguish real screens
            XConfigureWindow($display, $evt->window, CWX | CWY | CWWidth, { x => 0, y => 0, width => $screen->width });
        } else {
            #XConfigureWindow($display, $evt->window, CWX | CWY, { x => 40, y => 10 });
        }

        $win->show();
        $display->flush();
        next;
    }

    if ($ref eq "X11::Xlib::XConfigureRequestEvent") {
        my %changes;

        # TODO deal somehow with fullscreen
        # TODO handle somehow modal windows
        # TODO process existing windows to move them below the panel and set their size
        $changes{$_} = $evt->$_ for qw( x y width height border_width );
        $changes{y} = $panel_height if $panel_height > $changes{y} // $panel_height;
        $changes{sibling} = $evt->above;
        $changes{stack_mode} = $evt->detail;
        XConfigureWindow($display, $evt->window, $evt->value_mask | CWY, \%changes);
        $display->flush();
        next;
    }

    if ($ref eq "X11::Xlib::XDestroyWindowEvent") {
        #die "$0 is exiting now on any window close";
    }

    print STDERR "... ignored\n";
}
