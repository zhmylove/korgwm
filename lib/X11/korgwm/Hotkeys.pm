#!/usr/bin/perl
# made by: KorG
# vim: cc=119 et sw=4 ts=4 :
package X11::korgwm::Hotkeys;
use strict;
use warnings;
use feature 'signatures';

use Carp;
use X11::XCB ':all';
use X11::korgwm::Common;
require X11::korgwm::Config;
require X11::korgwm::Executor;

# <X11/keysymdef.h>
my $keys = {
            "CR"    => 0xFF0D,              # XK_Return
            "TAB"   => 0xFF09,              # XK_Tab
    (map {; "F$_"   => 0xFFBD + $_ } 1..9), # XK_Fx
};

# xcb modifiers
my $modifiers = {
    "alt"   => MOD_MASK_1,
    "ctrl"  => MOD_MASK_CONTROL,
    "mod"   => MOD_MASK_4,
    "shift" => MOD_MASK_SHIFT,
};

my $keymap;     # a mapping between keycodes (arr index) and char codes from X11
my $keycodes;   # reverse mapping for us
my $hotkeys;    # hash with actual functions to run

# Register a hotkey
sub hotkey($hotkey, $cmd) {
    my @keys = split /_/, $hotkey;
    my $key = pop @keys;
    $key = $keys->{$key} // ord($key);
    my $mask = 0;
    for (@keys) {
        my $mod = $modifiers->{$_} or croak "Modifier $_ not defined";
        $mask |= $mod;
    }
    $hotkeys->{$key}->{$mask} = X11::korgwm::Executor::parse($cmd);
}

sub init {
    # Init keymap
    $keymap = $X->get_keymap();

    # Prepare reverse mapping
    for (my $i = 0; $i < @{ $keymap }; $i++) {
        my $keycode = $keymap->[$i] or next;
        $keycodes->{$keycode->[0]} = $i;
    }

    # Parse hotkeys from config and fill %$hotkeys
    hotkey($_, $cfg->{hotkeys}->{$_}) for keys %{ $cfg->{hotkeys} };

    # Register event handler
    &X11::korgwm::add_event_cb(KEY_PRESS(), sub($evt) {
        my $key = $keymap->[$evt->detail]->[0];
        my $mask = $evt->state;

        # Sometimes we get modifiers itself from X11, so ignore them (constants took from <X11/keysymdef.h>)
        return carp "X11 sent us a modifier key $key mask $mask" if $key >= 0xffe1 and $key <= 0xffee;

        my $handler = $hotkeys->{$key}->{$mask};
        croak "Caught unexpected key: $key mask: $mask" unless $handler;
        $handler->();
    });

    # Grab keys
    my $root_id = $X->root->id;
    for my $key (keys %{ $hotkeys }) {
        for my $mask (keys %{ $hotkeys->{$key} }) {
            $X->grab_key(0, $root_id, $mask, $keycodes->{$key}, GRAB_MODE_ASYNC, GRAB_MODE_ASYNC);
        }
    }
    $X->flush();
}

push @X11::korgwm::extensions, \&init;

1;
