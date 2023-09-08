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

use X11::korgwm::Config;
use X11::korgwm::Panel::Battery;
use X11::korgwm::Panel::Clock;
use X11::korgwm::Panel::Lang;
use X11::korgwm::Panel;
use X11::korgwm::Layout;
use X11::korgwm::Window;
use X11::korgwm::Screen;
use X11::korgwm::EWMH;
use X11::korgwm::Xkb;
use X11::korgwm::Hotkeys;

# Should you want understand this, first read carefully:
# - libxcb source code
# - X11::XCB source code
# - https://www.x.org/releases/X11R7.7/doc/xproto/x11protocol.txt
# - https://specifications.freedesktop.org/wm-spec/wm-spec-latest.html

our $cfg;
$SIG{CHLD} = "IGNORE";

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

# $r->warp_pointer(50, 150);
$X->flush();

# Initialize RANDR
qx($cfg->{randr_cmd});
$X->randr_select_input($r->id, RANDR_NOTIFY_MASK_SCREEN_CHANGE);

sub init_extension($name, $first_event) {
    my $ext = $X->query_extension_reply($X->query_extension(length($name), $name)->{sequence});
    die "$name not available" unless $ext->{present};
    $$first_event = $ext->{first_event};
    die "Could not get $name first_event" unless $$first_event;
}

my ($RANDR_EVENT_BASE);
init_extension("RANDR", \$RANDR_EVENT_BASE);

our $windows = {};
my $focused;

sub win_get_property($conn, $win, $prop_name, $prop_type='UTF8_STRING', $ret_length=8) {
    my $aname = $X->atom(name => $prop_name)->id;
    my $atype = $X->atom(name => $prop_type)->id;
    my $cookie = $X->get_property(0, $win, $aname, $atype, 0, $ret_length);
    $X->get_property_reply($cookie->{sequence});
}

our %screens;
our @screens;
sub handle_screens {
    my @xscreens = @{ $X->screens() };

    # Count current screens
    my %curr_screens;
    for my $s (@xscreens) {
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

    # Sort screens based on X axis and store them in @screens
    @screens = map { $screens{$_} } sort { (split /,/, $a)[0] <=> (split /,/, $b)[0] or $a <=> $b } keys %screens;
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
        if ($win == ($tag->{screen}->{focus} // 0)) {
            $tag->{screen}->{focus} = undef;
            warn "Setting title to zero";
            $tag->{screen}->{panel}->title();
        }
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

our %xcb_events = (
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
            # TODO implement screen change and win->move here
        }

        $windows->{$wid}->show();
        $focus->{screen}->win_add($windows->{$wid});
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
            } else {
                # If window is tiled or maximized, tell it it's real size
                ($x, $y, $w, $h) = @{ $win }{qw( real_x real_y real_w real_h )};
            }

            # Send notification to the client and return
            $win->configure_notify($evt->{sequence}, $x, $y, $w, $h);
            $X->flush();
            return;
        }

        # Send xcb_configure_notify_event_t to the window's client
        X11::korgwm::Window::_configure_notify($win_id, @{ $evt }{qw( sequence x y w h )});

        $X->flush();
    },
    $RANDR_EVENT_BASE => sub($evt) {
        warn "RANDR screen change notify";
        qx($cfg->{randr_cmd});
        warn "Xinerama query screens:";
        # TODO check if it's really needed
        warn Dumper $X->xinerama_query_screens_reply($X->xinerama_query_screens()->{sequence});
        $X->flush();
        warn "New screens:";
        warn Dumper $X->screens();
        handle_screens();
    },
    ENTER_NOTIFY, sub($evt) {
        # TODO Do we really need to ignore EnterNotifies on unknown windows? I'll leave it here waiting for bugs.
        return unless exists $windows->{$evt->event};
        my $win = $windows->{$evt->event};
        $win->focus();
    },
);

# Helper for extensions
sub add_event_cb($id, $sub) {
    croak "Redefined event handler for $id" if defined $xcb_events{$id};
    $xcb_events{$id} = $sub;
}

# Prepare manual exit switch
our $exit_trigger = 0;

# Init our extensions
$_->() for our @extensions;

# Set the initial pointer position, if needed
if (my $pos = $cfg->{initial_pointer_position}) {
    if ($pos eq "center") {
        my $screen = $screens[0];
        $r->warp_pointer(map { int($screen->{$_} / 2) } qw( w h ));
    } elsif ($pos eq "hidden") {
        $r->warp_pointer($r->_rect->width, $r->_rect->height);
    } else {
        croak "Unknown initial_pointer_position: $pos";
    }
}

# Main event loop
for(;;) {
    die "Exit requested" if $exit_trigger;

    while (my $evt = $X->poll_for_event()) {
        warn Dumper $evt;

        # Highest bit indicates that the source is another client
        my $type = $evt->{response_type} & 0x7F;

        if (defined(my $evt_cb = $xcb_events{$type})) {
            $evt_cb->($evt);
        } else {
            warn "... MISSING handler for event " . $type;
        }
    }

    # TODO should handle Gtk / AE events here

    my $pause = AE::cv;
    my $w = AE::timer 0.1, 0, sub { $pause->send };
    $pause->recv;
}
