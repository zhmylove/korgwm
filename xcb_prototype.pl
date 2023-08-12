#!/usr/bin/perl
use strict;
use warnings;
use v5.36;
use lib 'lib', '../X11-XCB/lib', '../X11-XCB/blib/arch';
use X11::XCB ':all';
use X11::XCB::Connection;
use X11::XCB::Setup;
use X11::XCB::Event::KeyPress;
use Data::Dumper;

my $RANDR_cmd = q(xrandr --output HDMI-A-0 --left-of eDP --auto --output DisplayPort-0 --right-of eDP --auto);
die "X11::XCB minimum version 0.20 required" if 0.20 > X11::XCB->VERSION();

my $x = X11::XCB::Connection->new;
warn Dumper $x->screens;
warn Dumper my $r = $x->root;
warn Dumper $x->get_window_attributes($r->id);
warn Dumper my $wm = $x->change_window_attributes_checked($r->id, CW_EVENT_MASK, EVENT_MASK_SUBSTRUCTURE_REDIRECT);
#warn Dumper $x->change_window_attributes($r->id, CW_EVENT_MASK, EVENT_MASK_BUTTON_1_MOTION|EVENT_MASK_BUTTON_2_MOTION|EVENT_MASK_BUTTON_3_MOTION|EVENT_MASK_BUTTON_4_MOTION|EVENT_MASK_BUTTON_5_MOTION|EVENT_MASK_BUTTON_MOTION|EVENT_MASK_BUTTON_PRESS|EVENT_MASK_BUTTON_RELEASE|EVENT_MASK_COLOR_MAP_CHANGE|EVENT_MASK_ENTER_WINDOW|EVENT_MASK_EXPOSURE|EVENT_MASK_FOCUS_CHANGE|EVENT_MASK_KEYMAP_STATE|EVENT_MASK_KEY_PRESS|EVENT_MASK_KEY_RELEASE|EVENT_MASK_LEAVE_WINDOW|EVENT_MASK_NO_EVENT|EVENT_MASK_OWNER_GRAB_BUTTON|EVENT_MASK_POINTER_MOTION|EVENT_MASK_POINTER_MOTION_HINT|EVENT_MASK_PROPERTY_CHANGE|EVENT_MASK_RESIZE_REDIRECT|EVENT_MASK_STRUCTURE_NOTIFY|EVENT_MASK_SUBSTRUCTURE_NOTIFY|EVENT_MASK_SUBSTRUCTURE_REDIRECT|EVENT_MASK_VISIBILITY_CHANGE);
# warn Dumper $x->change_window_attributes($r->id, CW_CURSOR, ...);
warn Dumper my $wm_error = $x->request_check($wm->{sequence});
die "Looks like another WM is in use" if $wm_error;

# Set root color
warn Dumper $x->change_window_attributes($r->id, CW_BACK_PIXEL, 0xff262729);
warn Dumper $x->clear_area(0, $r->id, 0, 0, $r->_rect->width, $r->_rect->height);

warn Dumper my $setup = $x->get_setup();
# warn Dumper my $kbdmap = $x->get_keyboard_mapping($setup->min_keycode, $setup->max_keycode - $setup->min_keycode + 1);
# warn Dumper $x->get_keyboard_mapping_reply($kbdmap->{sequence});
my $keymap = $x->get_keymap();
warn Dumper 0 + @$keymap;

$r->warp_pointer(50, 150);
$x->flush();

# Grab keys
## GRAB_ANY => keycode[0]
## MOD_MASK_ANY => state
warn Dumper $x->grab_key(0, $r->id, MOD_MASK_4, GRAB_ANY, GRAB_MODE_ASYNC, GRAB_MODE_ASYNC);

# Initialize RANDR
$x->randr_query_version(1, 1);
$x->randr_select_input($r->id, RANDR_NOTIFY_MASK_SCREEN_CHANGE);
my $RANDR = $x->query_extension_reply($x->query_extension(5, "RANDR")->{sequence});
die "RANDR not available" unless $RANDR->{present};
my $RANDR_SCREEN_CHANGE_NOTIFY = $RANDR->{first_event};
die "Could not get RANDR first_event" unless $RANDR_SCREEN_CHANGE_NOTIFY;

my %xcb_events = (
    KEY_PRESS, sub($evt) {
        # state: ... 1 4 8 64
        # warn Dumper [MOD_MASK_SHIFT, MOD_MASK_CONTROL, MOD_MASK_1, MOD_MASK_4];
        # %keys_by_state = (
        #   64 => {}, # keys with Super
        #   12 => {}, # keys with Ctrl + Alt
        # )
        # warn Dumper [$keymap->[$evt->detail]];
        warn sprintf("Key pressed, key: (%c) state:(%x)", $keymap->[$evt->detail]->[0], $evt->state);
    },
    MAP_REQUEST, sub($evt) {
        warn "Mapping...";
        $x->map_window($evt->{window});
        $x->flush();
    },
    CONFIGURE_REQUEST, sub($evt) {
        warn "Configuring...";
        # TODO process $evt->{value_mask}
        ##
        #       'x' => 0,
        #       'sequence' => 5,
        #       'value_mask' => 12,
        #       'h' => 316,
        #       'y' => 0,
        #       'w' => 484,
        #       'border_width' => 1,
        #       'window' => 14680076,
        #       'response_type' => 23,
        #       'sibling' => 0,
        #       'parent' => 1730
        #   }, 'X11::XCB::Event::ConfigureRequest' );
        #
        my $mask = CONFIG_WINDOW_X | CONFIG_WINDOW_Y | CONFIG_WINDOW_WIDTH | CONFIG_WINDOW_HEIGHT;
        my @values = map { $evt->{$_} } qw( x y w h );
        warn "val: @values";
        $x->configure_window($evt->{window}, $mask, @values);
        $x->flush();
    },
    $RANDR_SCREEN_CHANGE_NOTIFY => sub($evt) {
        warn "RANDR screen change notify";
        qx($RANDR_cmd);
        warn Dumper $x->xinerama_query_screens_reply($x->xinerama_query_screens()->{sequence});
        $x->flush();
        warn Dumper $x->screens();
    },
);

# Main event loop
for(;;) {
    my $evt = $x->wait_for_event();
    warn Dumper $evt;
    if (defined $evt && defined(my $evt_cb = $xcb_events{$evt->{response_type}})) {
        $evt_cb->($evt);
    }

    # TODO should handle Gtk / AE events here
}
