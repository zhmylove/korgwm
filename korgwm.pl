#!/usr/bin/perl
# vim: sw=4 ts=4 et cc=119 :
use strict;
use warnings;
use feature 'signatures';
use lib 'lib';
use open ':std', ':encoding(UTF-8)';
use utf8;
use X11::Xlib ':all';
use X11::Protocol;
use korgwm::Panel;

use Data::Dumper; # TODO remove

# TODO Should get from config
my $panel_height = 20;

# Initialization phase: connect to x11, prepare screens, subscribe for events
my $X = X11::Protocol->new();
$X->init_extension("XINERAMA") or die "XINERAMA not available";

my $display = X11::Xlib->new();

printf STDERR "Screen count: %s\n", $display->screen_count(); # TODO remove
die "Use XINERAMA or die!" unless $display->screen_count() == 1;

my $screen = $display->screen(0);

# There is only one root window
my $root = $screen->root_window;

$root->event_mask_include(SubstructureRedirectMask, SubstructureNotifyMask);
$display->flush();

# Detect real monitors
my $screens;

sub add_screen($id, $x, $y, $width, $height) {
    my $s = {};
    @{$s}{qw(present width height x y)} = (1, $width, $height, $x, $y);
    $s->{tags} = {}; # TODO create tags
    my $sid = $id;
    $s->{panel} = korgwm::Panel->new($id, sub { warn "ws_cb for screen $sid [@_]" });
    $screens->{$id} = $s;
}

if ($X->XineramaIsActive()) {
    my $id = 0;
    add_screen $id++, @$_ for $X->XineramaQueryScreens();
    die "Unable to get monitors" unless $id;
} else {
    add_screen(0, 0, 0, $screen->width, $screen->height);
}

warn Dumper $screens; # TODO remove

for(;;) {
    # TODO rewrite event loop to handle events from Xlib, Gtk and AE and set timeout = 0

    # Process events from each screen panel
    $screens->{$_}->{panel}->iter() for keys %{ $screens };

    my $evt = $display->wait_event(timeout => 0.01);
    next unless defined $evt; # TODO check if wait_event could be interrupted
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
            my $screen_id = substr $startup_id, 13;
            my $screen = $screens->{$screen_id};
            die "Cannot find screen for panel $screen_id" unless $screen;
            XConfigureWindow($display, $evt->window, CWX | CWY | CWWidth, { x => $screen->{x},
                    y => 0, width => $screen->{width} });
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
