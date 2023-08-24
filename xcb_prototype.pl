#!/usr/bin/perl
# made by: KorG
# vim: cc=119 et sw=4 ts=4 :
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
use X11::XCB::Event::MapRequest;
use X11::XCB::Event::UnmapNotify;
use X11::XCB::Event::DestroyNotify;
die "X11::XCB minimum version 0.20 required" if 0.20 > X11::XCB->VERSION();
use Carp;
use AnyEvent;

use Devel::SimpleTrace;
use Data::Dumper;
$Data::Dumper::Sortkeys = 1;

use X11::korgwm::Panel;
use X11::korgwm::Layout;
use X11::korgwm::Window;
use X11::korgwm::Screen;

# TODO get from some config file
our $cfg;
$cfg->{RANDR_cmd} = q(xrandr --output HDMI-A-0 --left-of eDP --auto --output DisplayPort-0 --right-of eDP --auto);
$cfg->{border_width} = 2;
$cfg->{clock_format} = " %a, %e %B %H:%M ";
$cfg->{color_bg} = 0x262729;
$cfg->{color_fg} = 0xA3BABF;
$cfg->{color_urgent_bg} = 0x464729;
$cfg->{color_urgent_fg} = 0xffff00;
$cfg->{font} = "DejaVu Sans Mono 10";
$cfg->{hide_empty_tags} = 0;
$cfg->{panel_height} = 20;
$cfg->{set_root_color} = 0;
$cfg->{title_max_len} = 64;
$cfg->{ws_names} = [qw( T W M C 5 6 7 8 9 )];

$SIG{CHLD} = "IGNORE";
my $panel;
our $X = X11::XCB::Connection->new;
die "Errors connecting to X11" if $X->has_error();
warn Dumper $X->screens;
warn Dumper my $r = $X->root;
warn Dumper $X->get_window_attributes($r->id);
warn Dumper my $wm = $X->change_window_attributes_checked($r->id, CW_EVENT_MASK, EVENT_MASK_SUBSTRUCTURE_REDIRECT | EVENT_MASK_SUBSTRUCTURE_NOTIFY);
#warn Dumper $X->change_window_attributes($r->id, CW_EVENT_MASK, EVENT_MASK_BUTTON_1_MOTION|EVENT_MASK_BUTTON_2_MOTION|EVENT_MASK_BUTTON_3_MOTION|EVENT_MASK_BUTTON_4_MOTION|EVENT_MASK_BUTTON_5_MOTION|EVENT_MASK_BUTTON_MOTION|EVENT_MASK_BUTTON_PRESS|EVENT_MASK_BUTTON_RELEASE|EVENT_MASK_COLOR_MAP_CHANGE|EVENT_MASK_ENTER_WINDOW|EVENT_MASK_EXPOSURE|EVENT_MASK_FOCUS_CHANGE|EVENT_MASK_KEYMAP_STATE|EVENT_MASK_KEY_PRESS|EVENT_MASK_KEY_RELEASE|EVENT_MASK_LEAVE_WINDOW|EVENT_MASK_NO_EVENT|EVENT_MASK_OWNER_GRAB_BUTTON|EVENT_MASK_POINTER_MOTION|EVENT_MASK_POINTER_MOTION_HINT|EVENT_MASK_PROPERTY_CHANGE|EVENT_MASK_RESIZE_REDIRECT|EVENT_MASK_STRUCTURE_NOTIFY|EVENT_MASK_SUBSTRUCTURE_NOTIFY|EVENT_MASK_SUBSTRUCTURE_REDIRECT|EVENT_MASK_VISIBILITY_CHANGE);
# warn Dumper $X->change_window_attributes($r->id, CW_CURSOR, ...);
warn Dumper my $wm_error = $X->request_check($wm->{sequence});
die "Looks like another WM is in use" if $wm_error;

# Set root color
if ($cfg->{set_root_color}) {
    warn Dumper $X->change_window_attributes($r->id, CW_BACK_PIXEL, $cfg->{color_bg});
    warn Dumper $X->clear_area(0, $r->id, 0, 0, $r->_rect->width, $r->_rect->height);
}

# TODO make proper keymap hash
my $keymap = $X->get_keymap();
warn Dumper 0 + @$keymap;

# $r->warp_pointer(50, 150);
$X->flush();

# Grab keys
## GRAB_ANY => keycode[0]
## MOD_MASK_ANY => state
warn Dumper $X->grab_key(0, $r->id, MOD_MASK_4, GRAB_ANY, GRAB_MODE_ASYNC, GRAB_MODE_ASYNC);

# Initialize RANDR
qx($cfg->{RANDR_cmd});
$X->randr_select_input($r->id, RANDR_NOTIFY_MASK_SCREEN_CHANGE);
my $RANDR = $X->query_extension_reply($X->query_extension(5, "RANDR")->{sequence});
die "RANDR not available" unless $RANDR->{present};
my $RANDR_SCREEN_CHANGE_NOTIFY = $RANDR->{first_event};
die "Could not get RANDR first_event" unless $RANDR_SCREEN_CHANGE_NOTIFY;

our $windows = {};
my $focused;

sub win_get_property($conn, $win, $prop_name, $prop_type='UTF8_STRING', $ret_length=8) {
    my $aname = $X->atom(name => $prop_name)->id;
    my $atype = $X->atom(name => $prop_type)->id;
    my $cookie = $X->get_property(0, $win, $aname, $atype, 0, $ret_length);
    $X->get_property_reply($cookie->{sequence});
}

our %screens;
sub handle_screens {
    my @screens = @{ $X->screens() };

    # Count current screens
    my %curr_screens;
    for my $s (@screens) {
        my ($x, $y, $w, $h) = map { $s->rect->$_ } qw( x y width height );
        $curr_screens{"$x,$y,$w,$h"} = undef;
    }

    # Categorize them
    my @del_screens = grep { not exists $curr_screens{$_} } keys %screens;
    my @new_screens = grep { not defined $screens{$_} } keys %curr_screens;
    my @not_changed_screens = grep { defined $screens{$_} } keys %curr_screens;

    return if @del_screens == 0 and @new_screens == 0;

    # Create screens for new displays
    $screens{$_} = X11::korgwm::Screen->new(split ",", $_) for @new_screens;

    # Find a screen to move windows from the screen being deleted
    my $screen_for_abandoned_windows = (@new_screens, @not_changed_screens)[0];
    $screen_for_abandoned_windows = $screens{$screen_for_abandoned_windows};
    croak "Unable to get the screen for abandoned windows" unless defined $screen_for_abandoned_windows;

    # TODO remove
    warn "Moving stale windows to screen: $screen_for_abandoned_windows";

    # Call destroy on old screens and remove them
    for my $s (@del_screens) {
        $screens{$s}->destroy($screen_for_abandoned_windows);
        delete $screens{$s};
        $screen_for_abandoned_windows->refresh();
    }
}
handle_screens();
die "No screens found" unless keys %screens;

our $focus = {
    screen => $screens{(sort keys %screens)[0]},
    window => undef,
};

sub hide_window($wid, $delete=undef) {
    my $win = $delete ? delete $windows->{$wid} : $windows->{$wid};
    return unless $win;
    for my $tag (values %{ $win->{on_tags} // {} }) {
        $tag->win_remove($win);
        $tag->{screen}->{focus} = undef if $win == ($tag->{screen}->{focus} // 0);
    }
    if ($win == ($focus->{window} // 0)) {
        $focus->{focus} = undef;
        $focus->{screen}->focus();
    }
    if ($delete and $win->{transient_for}) {
        delete $win->{transient_for}->{siblings}->{$wid};
    }
}

our $unmap_prevent;
my $enter_notify_w;

our %xcb_events = (
    KEY_PRESS, sub($evt) {
        # state: ... 1 4 8 64
        # warn Dumper [MOD_MASK_SHIFT, MOD_MASK_CONTROL, MOD_MASK_1, MOD_MASK_4];
        # %keys_by_state = (
        #   64 => {}, # keys with Super
        #   12 => {}, # keys with Ctrl + Alt
        # )
        # warn Dumper [$keymap->[$evt->detail]];
        my $key = $keymap->[$evt->detail]->[0];
        warn sprintf("Key pressed, key: char(%c),hex(%x),dec(%d) state:(%x)", $key, $key, $key, $evt->state);

        if (chr($key) eq 'f') {
            my $win = $focus->{window};
            return unless defined $win;
            $win->toggle_floating();
            $focus->{screen}->refresh();
            $X->flush();
        }
    },
    MAP_REQUEST, sub($evt) {
        warn "Mapping...";
        my $wid = $evt->window;

        $X->change_window_attributes($wid, CW_EVENT_MASK,
            EVENT_MASK_ENTER_WINDOW | EVENT_MASK_LEAVE_WINDOW | EVENT_MASK_PROPERTY_CHANGE
        );
        $windows->{$wid} = X11::korgwm::Window->new($wid) unless defined $windows->{$wid};

        my $transient_for = $windows->{$wid}->transient_for() // -1;
        $transient_for = undef unless defined $windows->{$transient_for};
        if ($transient_for) {
            $windows->{$wid}->{floating} = 1;
            $windows->{$wid}->{transient_for} = $windows->{$transient_for};
            $windows->{$transient_for}->{siblings}->{$wid} = undef;
        }

        $windows->{$wid}->show();
        $focus->{screen}->add_window($windows->{$wid});
        $windows->{$wid}->focus();
        $focus->{screen}->refresh();
        $X->flush();
    },
    DESTROY_NOTIFY, sub($evt) {
        hide_window($evt->window, 1);
    },
    UNMAP_NOTIFY, sub($evt) {
        # The problem here is to distinguish between unmap due to $tag->hide() and unmap request from client
        hide_window($evt->window) unless delete $unmap_prevent->{$evt->window};
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
        # TODO should we handle 'sibling' field?

        # Configure window on the server
        my $win_id = $evt->{window};

        if (my $win = $windows->{$win_id}) {
            # Save desired x y w h
            my ($x, $y, $w, $h) = @{ $win }{qw( x y w h )} = @{ $evt }{qw( x y w h )};
            $y = $cfg->{panel_height} if $y < $cfg->{panel_height};

            # Handle floating windows properly
            if ($win->{floating}) {
                # For floating we need fixup border
                my $bw = $cfg->{border_width};
                $win->resize_and_move($x, $y, $w + 2 * $bw, $h + 2 * $bw);
                $win->configure_notify($evt->{sequence}, $x, $y, $w, $h);
                $X->flush();
            }

            # Ignore configure requests from other known windows
            return;
        }

        # Send xcb_configure_notify_event_t to the window's client
        X11::korgwm::Window::_configure_notify($win_id, @{ $evt }{qw( sequence x y w h )});

        $X->flush();
    },
    $RANDR_SCREEN_CHANGE_NOTIFY => sub($evt) {
        warn "RANDR screen change notify";
        qx($cfg->{RANDR_cmd});
        warn "Xinerama query screens:";
        # TODO check if it's really needed
        warn Dumper $X->xinerama_query_screens_reply($X->xinerama_query_screens()->{sequence});
        $X->flush();
        warn "New screens:";
        warn Dumper $X->screens();
        handle_screens();
    },
    ENTER_NOTIFY, sub($evt) {
        # To bypass consequent EnterNotifies and use only the last one for focus
        # This likely fixes the bug I observed 6 years ago in WMFS1
        my $win = $windows->{$evt->event} // X11::korgwm::Window->new($evt->event);
        if ($win->{floating}) {
            $enter_notify_w = AE::timer 0.1, 0, sub { $win->focus(); };
        } else {
            $win->focus();
        }
    },
);

my $die_trigger = 0;

# Main event loop
for(;;) {
    die "Die triggered" if $die_trigger;

    while (my $evt = $X->poll_for_event()) {
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
