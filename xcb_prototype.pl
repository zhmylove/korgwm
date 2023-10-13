#!/usr/bin/perl
# made by: KorG
# vim: cc=119 et sw=4 ts=4 :
package X11::korgwm;
use strict;
use warnings;
use feature 'signatures';

use lib 'lib', '../X11-XCB/lib', '../X11-XCB/blib/arch';

use X11::XCB 0.20 ':all';
use X11::XCB::Connection;
use Carp;
use AnyEvent;

# TODO remove
use Devel::SimpleTrace;
use Data::Dumper;
$Data::Dumper::Sortkeys = 1;
#$Data::Dumper::Indent = 0;

use X11::korgwm::Common;
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
use X11::korgwm::Expose;
use X11::korgwm::API;
use X11::korgwm::Mouse;
use X11::korgwm::Hotkeys;

# Should you want understand this, first read carefully:
# - libxcb source code
# - X11::XCB source code
# - https://www.x.org/releases/X11R7.7/doc/xproto/x11protocol.txt
# - https://specifications.freedesktop.org/wm-spec/wm-spec-latest.html
# ... though this code is written once to read never.

$SIG{CHLD} = "IGNORE";

$X = X11::XCB::Connection->new;
die "Errors connecting to X11" if $X->has_error();
warn Dumper $X->screens;
warn Dumper my $r = $X->root;
warn Dumper $X->get_window_attributes($r->id);
warn Dumper my $wm = $X->change_window_attributes_checked($r->id, CW_EVENT_MASK, EVENT_MASK_SUBSTRUCTURE_REDIRECT | EVENT_MASK_SUBSTRUCTURE_NOTIFY | EVENT_MASK_POINTER_MOTION);
#warn Dumper $X->change_window_attributes($r->id, CW_EVENT_MASK, EVENT_MASK_BUTTON_1_MOTION|EVENT_MASK_BUTTON_2_MOTION|EVENT_MASK_BUTTON_3_MOTION|EVENT_MASK_BUTTON_4_MOTION|EVENT_MASK_BUTTON_5_MOTION|EVENT_MASK_BUTTON_MOTION|EVENT_MASK_BUTTON_PRESS|EVENT_MASK_BUTTON_RELEASE|EVENT_MASK_COLOR_MAP_CHANGE|EVENT_MASK_ENTER_WINDOW|EVENT_MASK_EXPOSURE|EVENT_MASK_FOCUS_CHANGE|EVENT_MASK_KEYMAP_STATE|EVENT_MASK_KEY_PRESS|EVENT_MASK_KEY_RELEASE|EVENT_MASK_LEAVE_WINDOW|EVENT_MASK_NO_EVENT|EVENT_MASK_OWNER_GRAB_BUTTON|EVENT_MASK_POINTER_MOTION|EVENT_MASK_POINTER_MOTION_HINT|EVENT_MASK_PROPERTY_CHANGE|EVENT_MASK_RESIZE_REDIRECT|EVENT_MASK_STRUCTURE_NOTIFY|EVENT_MASK_SUBSTRUCTURE_NOTIFY|EVENT_MASK_SUBSTRUCTURE_REDIRECT|EVENT_MASK_VISIBILITY_CHANGE);
# warn Dumper $X->change_window_attributes($r->id, CW_CURSOR, ...);
warn Dumper my $wm_error = $X->request_check($wm->{sequence});
die "Looks like another WM is in use" if $wm_error;

# Set root color
if ($cfg->{set_root_color}) {
    warn Dumper $X->change_window_attributes($r->id, CW_BACK_PIXEL, $cfg->{color_bg});
    warn Dumper $X->clear_area(0, $r->id, 0, 0, $r->_rect->width, $r->_rect->height);
}

$X->flush();

# Initialize RANDR
qx($cfg->{randr_cmd});
$X->randr_select_input($r->id, RANDR_NOTIFY_MASK_SCREEN_CHANGE);

my ($RANDR_EVENT_BASE);
init_extension("RANDR", \$RANDR_EVENT_BASE);

sub win_get_property($conn, $win, $prop_name, $prop_type='UTF8_STRING', $ret_length=8) {
    my $aname = $X->atom(name => $prop_name)->id;
    my $atype = $X->atom(name => $prop_type)->id;
    my $cookie = $X->get_property(0, $win, $aname, $atype, 0, $ret_length);
    $X->get_property_reply($cookie->{sequence});
}

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

$focus = {
    screen => $screens{(sort keys %screens)[0]},
    window => undef,
};

sub handle_existing_windows {
    # Query for windows and process them
    my %transients;
    for my $wid (
        map { $_->[0] }
        grep { $_->[1]->{map_state} == MAP_STATE_VIEWABLE and not $_->[1]->{override_redirect} }
        map { [ $_ => $X->get_window_attributes_reply($X->get_window_attributes($_)->{sequence}) ] }
        @{ $X->get_query_tree_children($r->id) }
    ) {
        if (my $transient_for = X11::korgwm::Window::_transient_for($wid)) {
            $transients{$wid} = $transient_for;
            next;
        }
        my $win = ($windows->{$wid} = X11::korgwm::Window->new($wid));
    }

    # Process transients
    for my $wid (keys %transients) {
        my $win = ($windows->{$wid} = X11::korgwm::Window->new($wid));
        $win->{transient_for} = $windows->{$transients{$wid}};
        $windows->{$transients{$wid}}->{siblings}->{$wid} = undef;
    }

    # Set proper window information
    for my $win (values %{ $windows }) {
        $win->{floating} = 1;
        $X->change_window_attributes($win->{id}, CW_EVENT_MASK, EVENT_MASK_ENTER_WINDOW | EVENT_MASK_PROPERTY_CHANGE);

        my ($x, $y, $w, $h) = $win->query_geometry();
        $y = $cfg->{panel_height} if $y < $cfg->{panel_height};
        my $bw = $cfg->{border_width};
        @{ $win }{qw( x y w h )} = ($x, $y, $w, $h);

        $win->resize_and_move($x, $y, $w + 2 * $bw, $h + 2 * $bw);
        my $screen = screen_by_xy($x, $y) || $focus->{screen};
        $screen->win_add($win)
    }
    $_->refresh() for reverse @screens;
}
handle_existing_windows();

sub hide_window($wid, $delete=undef) {
    my $win = $delete ? delete $windows->{$wid} : $windows->{$wid};
    return unless $win;

    for my $tag (values %{ $win->{on_tags} // {} }) {
        $tag->win_remove($win);
        if ($win == ($tag->{screen}->{focus} // 0)) {
            $tag->{screen}->{focus} = undef;
            $tag->{screen}->{panel}->title();
        }
    }

    if ($win->{always_on} and $win->{always_on}->{focus} == $win) {
        $win->{always_on}->{focus} = undef;
        $win->{always_on}->{panel}->title();
    }

    if ($win == ($focus->{window} // 0)) {
        $focus->{focus} = undef;
        $focus->{screen}->focus();
    }

    if ($delete and $win->{transient_for}) {
        delete $win->{transient_for}->{siblings}->{$wid};
    }
}

%xcb_events = (
    MAP_REQUEST, sub($evt) {
        my ($wid, $follow, $win, $screen, $tag, $floating) = ($evt->{window}, 1);

        # Create a window if needed
        $win = $windows->{$wid};
        unless (defined $win) {
            $win = $windows->{$wid} = X11::korgwm::Window->new($wid);

            $X->change_window_attributes($wid, CW_EVENT_MASK, EVENT_MASK_ENTER_WINDOW | EVENT_MASK_PROPERTY_CHANGE);

            # Fix geometry if needed
            @{ $win }{qw( x y w h )} = $win->query_geometry() unless defined $win->{x};
        }

        # Apply rules
        my $rule = $cfg->{rules}->{$win->class()};
        if ($rule) {
            # XXX awaiting bugs with idx 0
            defined $rule->{screen} and $screen = $screens[$rule->{screen} - 1] // $screens[0];
            defined $rule->{tag} and $tag = $screen->{tags}->[$rule->{tag} - 1];
            defined $rule->{follow} and $follow = $rule->{follow};
            defined $rule->{floating} and $floating = $rule->{floating};
        }

        # Process transients
        my $transient_for = $win->transient_for() // -1;
        $transient_for = undef unless defined $windows->{$transient_for};
        if ($transient_for) {
            my $parent = $windows->{$transient_for};
            $win->{floating} = 1;
            $win->{transient_for} = $parent;
            $parent->{siblings}->{$wid} = undef;

            $tag = ($parent->tags_visible())[0] // ($parent->tags())[0];
            $screen = $tag->{screen};
            $follow = 0; # TODO consider if I really want this
        }

        # Set default screen & tag, and fix position
        $screen //= $focus->{screen};
        $tag //= $screen->current_tag();
        $win->{x} += $screen->{x} if $win->{x} < $screen->{x};

        # Place it in proper place
        $win->show() if $screen->current_tag() == $tag;
        $tag->win_add($win);
        $win->toggle_floating(1) if $floating;
        if ($follow) {
            $screen->tag_set_active($tag->{idx}, 0);
            $screen->refresh();
            $win->focus();
            $win->warp_pointer() if $rule->{follow};
        } else {
            if ($screen->current_tag() == $tag) {
                $screen->refresh();
            } else {
                $win->urgency_raise(1);
            }
        }
        $X->flush();
    },
    DESTROY_NOTIFY, sub($evt) {
        hide_window($evt->{window}, 1);
    },
    UNMAP_NOTIFY, sub($evt) {
        # This condition is to distinguish between unmap due to $tag->hide() and unmap request from client
        hide_window($evt->{window}) unless delete $unmap_prevent->{$evt->{window}};
    },
    CONFIGURE_REQUEST, sub($evt) {
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
                # TODO check if it moved to another screen
                $win->resize_and_move($x, $y, $w + 2 * $bw, $h + 2 * $bw);
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
        qx($cfg->{randr_cmd});
        handle_screens();
    },
);

# Prepare manual exit switch
our $exit_trigger = 0;

# Init our extensions
$_->() for our @extensions;

# Set the initial pointer position, if needed
if (my $pos = $cfg->{initial_pointer_position}) {
    if ($pos eq "center") {
        my $screen = $screens[0];
        $r->warp_pointer(map { int($screen->{$_} / 2) - 1 } qw( w h ));
    } elsif ($pos eq "hidden") {
        $r->warp_pointer($r->_rect->width, $r->_rect->height);
    } else {
        croak "Unknown initial_pointer_position: $pos";
    }
}

# Main event loop
for(;;) {
    die "Segmentation fault (core dumped)\n" if $exit_trigger;

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

    my $pause = AE::cv;
    my $w = AE::timer 0.1, 0, sub { $pause->send };
    $pause->recv;
}
