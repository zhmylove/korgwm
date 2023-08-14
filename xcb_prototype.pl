#!/usr/bin/perl
package X11::korgwm;
use strict;
use warnings;
use feature 'signatures';
use lib 'lib', '../X11-XCB/lib', '../X11-XCB/blib/arch';
use X11::XCB ':all';
use X11::XCB::Connection;
use X11::XCB::Window;
use X11::XCB::Event::ConfigureRequest;
use X11::XCB::Event::KeyPress;
use X11::XCB::Event::EnterLeaveNotify;
die "X11::XCB minimum version 0.20 required" if 0.20 > X11::XCB->VERSION();
use AnyEvent;
use Data::Dumper;
$Data::Dumper::Sortkeys = 1;

use X11::korgwm::Panel;

# TODO get from some config file
our $cfg;
$cfg->{panel_height} = 20;
$cfg->{RANDR_cmd} = q(xrandr --output HDMI-A-0 --left-of eDP --auto --output DisplayPort-0 --right-of eDP --auto);
$cfg->{color_focus} = 0xA3BABF;
$cfg->{color_normal} = 0x262729;
$cfg->{border_width} = 2;

$SIG{CHLD} = "IGNORE";
my $x = X11::XCB::Connection->new;
die "Errors connecting to X11" if $x->has_error();
warn Dumper $x->screens;
warn Dumper my $r = $x->root;
warn Dumper $x->get_window_attributes($r->id);
warn Dumper my $wm = $x->change_window_attributes_checked($r->id, CW_EVENT_MASK, EVENT_MASK_SUBSTRUCTURE_REDIRECT | EVENT_MASK_SUBSTRUCTURE_NOTIFY);
#warn Dumper $x->change_window_attributes($r->id, CW_EVENT_MASK, EVENT_MASK_BUTTON_1_MOTION|EVENT_MASK_BUTTON_2_MOTION|EVENT_MASK_BUTTON_3_MOTION|EVENT_MASK_BUTTON_4_MOTION|EVENT_MASK_BUTTON_5_MOTION|EVENT_MASK_BUTTON_MOTION|EVENT_MASK_BUTTON_PRESS|EVENT_MASK_BUTTON_RELEASE|EVENT_MASK_COLOR_MAP_CHANGE|EVENT_MASK_ENTER_WINDOW|EVENT_MASK_EXPOSURE|EVENT_MASK_FOCUS_CHANGE|EVENT_MASK_KEYMAP_STATE|EVENT_MASK_KEY_PRESS|EVENT_MASK_KEY_RELEASE|EVENT_MASK_LEAVE_WINDOW|EVENT_MASK_NO_EVENT|EVENT_MASK_OWNER_GRAB_BUTTON|EVENT_MASK_POINTER_MOTION|EVENT_MASK_POINTER_MOTION_HINT|EVENT_MASK_PROPERTY_CHANGE|EVENT_MASK_RESIZE_REDIRECT|EVENT_MASK_STRUCTURE_NOTIFY|EVENT_MASK_SUBSTRUCTURE_NOTIFY|EVENT_MASK_SUBSTRUCTURE_REDIRECT|EVENT_MASK_VISIBILITY_CHANGE);
# warn Dumper $x->change_window_attributes($r->id, CW_CURSOR, ...);
warn Dumper my $wm_error = $x->request_check($wm->{sequence});
die "Looks like another WM is in use" if $wm_error;

# Set root color
warn Dumper $x->change_window_attributes($r->id, CW_BACK_PIXEL, $cfg->{color_normal});
warn Dumper $x->clear_area(0, $r->id, 0, 0, $r->_rect->width, $r->_rect->height);

# TODO make proper keymap hash
my $keymap = $x->get_keymap();
warn Dumper 0 + @$keymap;

# $r->warp_pointer(50, 150);
$x->flush();

# Grab keys
## GRAB_ANY => keycode[0]
## MOD_MASK_ANY => state
warn Dumper $x->grab_key(0, $r->id, MOD_MASK_4, GRAB_ANY, GRAB_MODE_ASYNC, GRAB_MODE_ASYNC);

# Initialize RANDR
# $x->randr_query_version(1, 1);
qx($cfg->{RANDR_cmd});
$x->randr_select_input($r->id, RANDR_NOTIFY_MASK_SCREEN_CHANGE);
my $RANDR = $x->query_extension_reply($x->query_extension(5, "RANDR")->{sequence});
die "RANDR not available" unless $RANDR->{present};
my $RANDR_SCREEN_CHANGE_NOTIFY = $RANDR->{first_event};
die "Could not get RANDR first_event" unless $RANDR_SCREEN_CHANGE_NOTIFY;

our $windows = {};

sub win_get_property($conn, $win, $prop_name, $prop_type='UTF8_STRING', $ret_length=8) {
    my $aname = $x->atom(name => $prop_name)->id;
    my $atype = $x->atom(name => $prop_type)->id;
    my $cookie = $x->get_property(0, $win, $aname, $atype, 0, $ret_length);
    $x->get_property_reply($cookie->{sequence});
}

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

        warn Dumper [$x->get_window_attributes_reply($x->get_window_attributes($evt->{window})->{sequence})];
        warn Dumper [win_get_property($x, $evt->{window}, '_NET_STARTUP_ID')->{value}];

        # TODO consider die ".... TRYING TO MAP AN UNKNOWN WINDOW" . Dumper $evt unless defined $windows->{$evt->{window}};
        $x->change_window_attributes($evt->{window}, CW_EVENT_MASK,
            EVENT_MASK_ENTER_WINDOW | EVENT_MASK_LEAVE_WINDOW
        );
        $x->map_window($evt->{window});
        $x->flush();
    },
    CONFIGURE_REQUEST, sub($evt) {
        # Order of the fields from xproto.h:
        #   XCB_CONFIG_WINDOW_X = 1,
        #   XCB_CONFIG_WINDOW_Y = 2,
        #   XCB_CONFIG_WINDOW_WIDTH = 4,
        #   XCB_CONFIG_WINDOW_HEIGHT = 8,
        #   XCB_CONFIG_WINDOW_BORDER_WIDTH = 16,
        #   XCB_CONFIG_WINDOW_SIBLING = 32,
        #   XCB_CONFIG_WINDOW_STACK_MODE = 64
        #
        # On any configure request we disrespect most parameters.
        # TODO handle floating windows
        # TODO should we handle 'sibling' field?

        # Configure window on the server
        my $mask = CONFIG_WINDOW_X | CONFIG_WINDOW_Y | CONFIG_WINDOW_WIDTH | CONFIG_WINDOW_HEIGHT | CONFIG_WINDOW_BORDER_WIDTH;
        my $win_id = $evt->{window};
        # TODO remove
        CORE::state $i = 0;
        my ($win_x, $win_y, $win_w, $win_h, $win_bw) = (30 + 10 * $i, 30 + 10 * $i, 400, 300, $cfg->{border_width});
        $i++;
        $x->configure_window($win_id, $mask, $win_x, $win_y, $win_w, $win_h, $win_bw);

        # Save the window to windows
        unless (defined $windows->{$win_id}) {
            my $win = {};
            @{ $win }{qw( is_maximized on_tags x y w h )} = (undef, {}, $win_x, $win_y, $win_w, $win_h);
			$win->{win} = X11::XCB::Window->new(_conn => $x, parent => $evt->{parent}, id => $win_id, 
                rect => X11::XCB::Rect->new(x => $win_x, y => $win_y, width => $win_w, height => $win_h),
                class => X11::XCB::WINDOW_CLASS_INPUT_OUTPUT(),
            );
            $windows->{$win_id} = $win;
            warn "Obtained control over the window $win_id";
        }

        # Send xcb_configure_notify_event_t to the window's client
        my $packed = pack('CCSLLLssSSSC', CONFIGURE_NOTIFY, 0, $evt->{sequence},
            $win_id, $win_id, 0, $win_x, $win_y, $win_w, $win_h, $win_bw,
            0       # override_redirect
        );
        $x->send_event(0, $win_id, EVENT_MASK_STRUCTURE_NOTIFY, $packed);

        $x->flush();
    },
    $RANDR_SCREEN_CHANGE_NOTIFY => sub($evt) {
        warn "RANDR screen change notify";
        qx($cfg->{RANDR_cmd});
        warn Dumper $x->xinerama_query_screens_reply($x->xinerama_query_screens()->{sequence});
        $x->flush();
        warn Dumper $x->screens();
    },
    ENTER_NOTIFY, sub($evt) { focus($evt->event, 1); },
);

sub focus($win, $focused=1) {
    # TODO unfocus currently focused window on the screen
    warn sprintf "%socusing %s\n", $focused ? "F" : "Unf", $win;
    $x->change_window_attributes($win, CW_BORDER_PIXEL, $focused ? $cfg->{color_focus} : $cfg->{color_normal});
    if ($focused) {
        $x->configure_window($win, CONFIG_WINDOW_STACK_MODE, STACK_MODE_ABOVE);
        $x->set_input_focus(INPUT_FOCUS_POINTER_ROOT, $win, TIME_CURRENT_TIME);
    }
    $x->flush();
}

X11::korgwm::Panel->new(1, sub { die "ws_cb" . Dumper \@_ } );

# Main event loop
for(;;) {
    while (my $evt = $x->poll_for_event()) {
        warn Dumper $evt;
        if (defined(my $evt_cb = $xcb_events{$evt->{response_type}})) {
            $evt_cb->($evt);
        } else {
            warn "... MISSING handler for event " . $evt->{response_type};
        }
    }

    # TODO should handle Gtk / AE events here

    my $pause = AE::cv;
    my $w = AE::timer 0.01, 0, sub { $pause->send };
    $pause->recv;
}
