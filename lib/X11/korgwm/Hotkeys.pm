#!/usr/bin/perl
# made by: KorG
# vim: cc=119 et sw=4 ts=4 :
package X11::korgwm::Hotkeys;
use strict;
use warnings;
use feature 'signatures';

use X11::XCB ':all';
use X11::korgwm::Common;
require X11::korgwm::Config;
require X11::korgwm::Executor;

# <X11/keysymdef.h>
my $keys = {
            "CR"    => 0xFF0D,              # XK_Return
            "TAB"   => 0xFF09,              # XK_Tab
            "Print" => 0xFF61,              # XK_Print
    (map {; "F$_"   => 0xFFBD + $_ } 1..9), # XK_Fx
    "XF86MonBrightnessUp"   => 0x1008FF02,
    "XF86MonBrightnessDown" => 0x1008FF03,
    "XF86AudioLowerVolume"  => 0x1008FF11,
    "XF86AudioMute"         => 0x1008FF12,
    "XF86AudioRaiseVolume"  => 0x1008FF13,
    "XF86AudioPlay"         => 0x1008FF14,
    "XF86AudioStop"         => 0x1008FF15,
    "XF86AudioPrev"         => 0x1008FF16,
    "XF86AudioNext"         => 0x1008FF17,
    "XF86WakeUp"            => 0x1008FF2B,
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

# Flag and result container for grab_key()
my $grab_active;
my $grab_result;

# Switch to a mode to grab a single key
sub grab_key($callback = undef) {
    $grab_result = $callback;
    $grab_active = 1;
    $X->grab_keyboard(0, $X->root->id, TIME_CURRENT_TIME, GRAB_MODE_ASYNC, GRAB_MODE_ASYNC);
    $X->flush();
}

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
    for (my $i = $#{ $keymap }; $i > 0; $i--) {
        my $keycode = $keymap->[$i] or next;
        $keycodes->{$keycode->[0]} = $i;
    }

    # Parse hotkeys from config and fill %$hotkeys
    hotkey($_, $cfg->{hotkeys}->{$_}) for keys %{ $cfg->{hotkeys} };

    # Register event handler
    add_event_cb(KEY_PRESS(), sub($evt) {
        my $key = $keymap->[$evt->{detail}]->[0];
        my $mask = $evt->{state};

        # If some routine asks us to grab the key, save it to an object and return
        if ($grab_active) {
            $grab_active = undef;

            my $grab_data = [ $key, $mask ];

            if (ref(my $callback = $grab_result) eq 'CODE') {
                $callback->($grab_data);
            }

            $grab_result = $grab_data;

            $X->ungrab_keyboard(TIME_CURRENT_TIME);
            $X->flush();
            return;
        }

        # Sometimes we get modifiers itself from X11, so ignore them (constants took from <X11/keysymdef.h>)
        return carp "X11 sent us a modifier key $key mask $mask" if $key >= 0xffe1 and $key <= 0xffee;

        my $handler = $hotkeys->{$key}->{$mask};
        unless ($handler) {
            return carp "X11 sent us XK_Escape, but didn't even think to call us Godfather" if $key == 0xff1b;
            return carp "Caught unexpected key: $key code: $evt->{detail} mask: $mask";
        }
        $handler->();
    });

    # We are not interested in KeyRelease events, so ignore it
    add_event_ignore(KEY_RELEASE());

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
