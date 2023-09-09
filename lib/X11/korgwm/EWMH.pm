#!/usr/bin/perl
# made by: KorG
# vim: cc=119 et sw=4 ts=4 :
package X11::korgwm::EWMH;
use strict;
use warnings;
use feature 'signatures';
use open ':std', ':encoding(UTF-8)';
use utf8;
use Carp;
use X11::XCB ':all';
use X11::XCB::Event::PropertyNotify;
use X11::XCB::Event::ClientMessage;

use X11::korgwm::Window;

use Data::Dumper;
$Data::Dumper::Sortkeys = 1;

our ($X, $cfg, $windows);
*X = *X11::korgwm::X;
*cfg = *X11::korgwm::cfg;
*windows = *X11::korgwm::windows;

# Unconditionally update a title
sub icccm_update_title($evt) {
    my $win = $windows->{$evt->window} or return;
    $win->update_title();
}

# React only on urgency
sub icccm_update_wm_hints($evt) {
    my $win = $windows->{$evt->window} or return;

    # Short path if nothing changed
    my $urgency_old = $win->{urgent} // -1;
    my $urgency_new = $win->urgency_get() // -1;
    return if $urgency_new == $urgency_old;

    # The state has changed
    $win->urgency_clear() if $urgency_old > 0;
    $win->urgency_raise() if $urgency_new > 0;

    $win->{urgent} = $urgency_new > 0;
}

# Fullscreen handlers
my $atom_fullscreen;
sub icccm_update_maximize($evt) {
    my $win = $windows->{$evt->window} or return;

    # Ignore irrelevant events
    my ($action, $first, $second, $source_indication) = unpack "LLLL", $evt->data;
    return unless $first == $atom_fullscreen or $second == $atom_fullscreen;

    # Ok, now we're sure we were requested to change the fullscreen hint
    if ($action == _NET_WM_STATE_ADD) {
        $win->toggle_maximize(1);
    } elsif ($action == _NET_WM_STATE_REMOVE) {
        $win->toggle_maximize(0);
    } elsif ($action == _NET_WM_STATE_TOGGLE) {
        $win->toggle_maximize();
    } else {
        croak "Unknown action specified in _NET_WM_STATE EWMH";
    }
}

our $icccm_atoms = {};
our $icccm_handlers = {
    "WM_HINTS" => \&icccm_update_wm_hints,
    "WM_NAME" => \&icccm_update_title,
    "_NET_WM_NAME" => \&icccm_update_title,
    "_NET_WM_STATE" => \&icccm_update_maximize,
};

sub init {
    # Populate current atom ids
    $icccm_atoms->{$X->atom(name => $_)->id()} = $_ for keys %{ $icccm_handlers };
    $atom_fullscreen = $X->atom(name => "_NET_WM_STATE_FULLSCREEN")->id();

    # Set up event handlers
    &X11::korgwm::add_event_cb(CLIENT_MESSAGE(), sub ($evt) {
        my $atomname = $icccm_atoms->{$evt->type} or return;
        my $handler = $icccm_handlers->{$atomname} or return;
        warn "... running handler for $atomname";
        $handler->($evt);
    });

    &X11::korgwm::add_event_cb(PROPERTY_NOTIFY(), sub ($evt) {
        my $atomname = $icccm_atoms->{$evt->{atom}} or return;
        my $handler = $icccm_handlers->{$atomname} or return;
        warn "... running handler for $atomname";
        $handler->($evt);
    });
}

push @X11::korgwm::extensions, \&init;

1;
