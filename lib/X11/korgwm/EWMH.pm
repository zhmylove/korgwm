#!/usr/bin/perl
# made by: KorG
# vim: cc=119 et sw=4 ts=4 :
package X11::korgwm::EWMH;
use strict;
use warnings;
use feature 'signatures';

use X11::XCB ':all';
use X11::XCB::Event::ClientMessage;
use X11::XCB::Event::PropertyNotify;

use X11::korgwm::Common;
use X11::korgwm::Window;

# Unconditionally update a title
sub icccm_update_title($evt) {
    my $win = $windows->{$evt->{window}} or return;
    $win->update_title();
}

# React only on urgency
sub icccm_update_wm_hints($evt) {
    my $win = $windows->{$evt->{window}} or return;

    # Short path if nothing changed
    my $urgency_old = $win->{urgent} // -1;
    my $urgency_new = $win->urgency_get() // -1;
    return if $urgency_new == $urgency_old;

    # The state has changed
    $win->urgency_clear() if $urgency_old > 0;
    $win->urgency_raise() if $urgency_new > 0;

    $win->{urgent} = $urgency_new > 0;
}

# _WM_STATE Attention handler
sub net_wm_attention($action, $win) {
    if ($action == _NET_WM_STATE_ADD) {
        $win->urgency_raise();
    } elsif ($action == _NET_WM_STATE_REMOVE) {
        $win->urgency_clear();
    } elsif ($action == _NET_WM_STATE_TOGGLE) {
        $win->{urgent} ? $win->urgency_clear() : $win->urgency_raise();
    } else {
        croak "(attention) Unknown action specified in _NET_WM_STATE EWMH: $action";
    }
}

# _WM_STATE Fullscreen handler
sub net_wm_fullscreen($action, $win) {
    if ($action == _NET_WM_STATE_ADD) {
        $win->toggle_maximize(1, allow_invisible => 1);
    } elsif ($action == _NET_WM_STATE_REMOVE) {
        $win->toggle_maximize(0, allow_invisible => 1);
    } elsif ($action == _NET_WM_STATE_TOGGLE) {
        $win->toggle_maximize(2, allow_invisible => 1);
    } else {
        croak "(fullscreen) Unknown action specified in _NET_WM_STATE EWMH: $action";
    }
}

# _NET_WM_STATE handlers
my $atom_fullscreen;
my $atom_netwm_attention;
my %wm_state_handlers;
sub icccm_update_wm_state($evt) {
    my $win = $windows->{$evt->{window}} or return;

    # Extract event from the data
    my ($action, $first, $second, $source_indication) = unpack "LLLL", $evt->{data} // return;
    $second //= $first //= 0;

    # Execute handler for each known atom
    $_->($action, $win) for grep defined, map { $wm_state_handlers{$_} } $first, $second;
}

our $icccm_atoms = {};
our $icccm_handlers = {
    "WM_HINTS" => \&icccm_update_wm_hints,
    "WM_NAME" => \&icccm_update_title,
    "_NET_WM_NAME" => \&icccm_update_title,
    "_NET_WM_STATE" => \&icccm_update_wm_state,
    "_NET_SUPPORTED" => undef,
    "_NET_SUPPORTING_WM_CHECK" => undef,
    "_NET_WM_STATE_DEMANDS_ATTENTION" => undef,
    "_NET_WM_STATE_FULLSCREEN" => undef,
};

sub fill_icccm_atoms {
    $icccm_atoms->{atom($_)} = $_ for keys %{ $icccm_handlers };
}

# Set EWMH support declaration
sub declare_support {
    fill_icccm_atoms unless keys %{ $icccm_atoms };
    my @atoms = keys %{ $icccm_atoms };

    # Create a child window
    my $wid = $X->generate_id();
    $X->create_window(0, $wid, $X->root->id, 0, 0, 1, 1, 0, WINDOW_CLASS_INPUT_OUTPUT, 0, CW_OVERRIDE_REDIRECT, 1);

    # Define EWMH atoms we support
    $X->change_property(PROP_MODE_REPLACE, $X->root->id, atom("_NET_SUPPORTED"),
        atom("ATOM"), 32, 0+@atoms, pack "L" x @atoms => @atoms);

    # Watchdog for siblings
    for my $id ($wid, $X->root->id) {
        $X->change_property(PROP_MODE_REPLACE, $id, atom("_NET_SUPPORTING_WM_CHECK"),
            atom("WINDOW"), 32, 1, pack L => $wid);
    }
}

sub init {
    # Populate current atom ids
    fill_icccm_atoms unless keys %{ $icccm_atoms };

    $atom_fullscreen = atom("_NET_WM_STATE_FULLSCREEN");
    $wm_state_handlers{ $atom_fullscreen } = \&net_wm_fullscreen;

    $atom_netwm_attention = atom("_NET_WM_STATE_DEMANDS_ATTENTION");
    $wm_state_handlers{ $atom_netwm_attention } = \&net_wm_attention;

    # Set up event handlers
    add_event_cb(CLIENT_MESSAGE(), sub ($evt) {
        my $atomname = $icccm_atoms->{$evt->type} or return;
        my $handler = $icccm_handlers->{$atomname} or return;
        $handler->($evt);
    });

    add_event_cb(PROPERTY_NOTIFY(), sub ($evt) {
        my $atomname = $icccm_atoms->{$evt->{atom}} or return;
        my $handler = $icccm_handlers->{$atomname} or return;
        $handler->($evt);
    });
}

push @X11::korgwm::extensions, \&init;

1;
