#!/usr/bin/perl
# made by: KorG
# vim: cc=119 et sw=4 ts=4 :
package X11::korgwm;
use strict;
use warnings;
use feature 'signatures';

# Third-party includes
use X11::XCB 0.21 ':all';
use X11::XCB::Connection;
use Carp;
use AnyEvent;
use List::Util qw( any min max );

# Those two should be included prior any DEBUG stuf
use X11::korgwm::Common;
use X11::korgwm::Config;

# Early initialize debug output, if needed. Should run after Common & Config
BEGIN {
    DEBUG and do {
        require Devel::SimpleTrace;
        Devel::SimpleTrace->import();
        require Data::Dumper;
        Data::Dumper->import();
        $Data::Dumper::Sortkeys = 1;
    };
}

# Load all other modules
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

## Define internal variables
$SIG{CHLD} = "IGNORE";
my %evt_masks = (x => CONFIG_WINDOW_X, y => CONFIG_WINDOW_Y, w => CONFIG_WINDOW_WIDTH, h => CONFIG_WINDOW_HEIGHT);
my ($ROOT, $atom_wmstate);
our $exit_trigger = 0;
our $VERSION = "2.0";

## Define functions
# Handles any screen change
sub handle_screens {
    my @xscreens = @{ $X->screens() };

    # Drop information about visible area
    undef $visible_min_x;
    undef $visible_min_y;
    undef $visible_max_x;
    undef $visible_max_y;

    # Count current screens
    my %curr_screens;
    for my $s (@xscreens) {
        my ($x, $y, $w, $h) = map { $s->rect->$_ } qw( x y width height );
        $curr_screens{"$x,$y,$w,$h"} = undef;

        # Collect new information about visible area
        $visible_min_x = defined $visible_min_x ? min($visible_min_x, $x)      : $x;
        $visible_min_y = defined $visible_min_y ? min($visible_min_y, $y)      : $y;
        $visible_max_x = defined $visible_max_x ? max($visible_max_x, $x + $w) : $x + $w;
        $visible_max_y = defined $visible_max_y ? max($visible_max_y, $y + $h) : $y + $h;
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

    DEBUG and warn "Moving stale windows to screen: $screen_for_abandoned_windows";

    # Call destroy on old screens and remove them
    for my $s (@del_screens) {
        $screens{$s}->destroy($screen_for_abandoned_windows);
        delete $screens{$s};
        $screen_for_abandoned_windows->refresh();
    }

    # Sort screens based on X axis and store them in @screens
    @screens = map { $screens{$_} } sort { (split /,/, $a)[0] <=> (split /,/, $b)[0] or $a <=> $b } keys %screens;
}

# Scan for existing windows and handle them
sub handle_existing_windows {
    # Query for windows and process them
    my %transients;
    for my $wid (
        map { $_->[0] }
        grep { $_->[1]->{map_state} == MAP_STATE_VIEWABLE and not $_->[1]->{override_redirect} }
        map { [ $_ => $X->get_window_attributes_reply($X->get_window_attributes($_)->{sequence}) ] }
        @{ $X->get_query_tree_children($ROOT->id) }
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
        $X->change_property(PROP_MODE_REPLACE, $win->{id}, $atom_wmstate, $atom_wmstate, 32, 1, pack L => 1);

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

# Destroy and Unmap events handler
sub hide_window($wid, $delete=undef) {
    my $win = $delete ? delete $windows->{$wid} : $windows->{$wid};
    return unless $win;
    $win->{_hidden} = 1;

    for my $tag (values %{ $win->{on_tags} // {} }) {
        $tag->win_remove($win);
        if ($win == ($tag->{screen}->{focus} // 0)) {
            $tag->{screen}->{focus} = undef;
            $tag->{screen}->{panel}->title();
        }
    }

    # Remove from all the tags where it is appended
    $_->win_remove($win) for values %{ $win->{also_tags} // {} };

    if (my $on_screen = $win->{always_on}) {
        # Drop focus and title
        if (($on_screen->{focus} // 0) == $win) {
            $on_screen->{focus} = undef;
            $on_screen->{panel}->title();
        }

        # Remove from always_on
        my $arr = $on_screen->{always_on};
        $win->{always_on} = undef;
        splice @{ $arr }, $_, 1 for reverse grep { $arr->[$_] == $win } 0..$#{ $arr };
    }

    if ($win == ($focus->{window} // 0)) {
        $focus->{focus} = undef;
        $focus->{screen}->focus();
    }

    if ($delete and $win->{transient_for}) {
        delete $win->{transient_for}->{siblings}->{$wid};
    }
}

# Main routine
sub FireInTheHole {
    # Establish X11 connection
    $X = X11::XCB::Connection->new;
    die "Errors connecting to X11" if $X->has_error();

    # Save root window
    $ROOT = $X->root;

    # Preload some atoms
    $atom_wmstate = $X->atom(name => "WM_STATE")->id;

    # Check for another WM
    my $wm = $X->change_window_attributes_checked($ROOT->id, CW_EVENT_MASK,
        EVENT_MASK_SUBSTRUCTURE_REDIRECT |
        EVENT_MASK_SUBSTRUCTURE_NOTIFY |
        EVENT_MASK_POINTER_MOTION
    );
    die "Looks like another WM is in use" if $X->request_check($wm->{sequence});

    # Set root color
    if ($cfg->{set_root_color}) {
        $X->change_window_attributes($ROOT->id, CW_BACK_PIXEL, $cfg->{color_bg});
        $X->clear_area(0, $ROOT->id, 0, 0, $ROOT->_rect->width, $ROOT->_rect->height);
    }

    # Initialize RANDR
    $X->flush();
    qx($cfg->{randr_cmd});
    $X->randr_select_input($ROOT->id, RANDR_NOTIFY_MASK_SCREEN_CHANGE);

    my ($RANDR_EVENT_BASE);
    init_extension("RANDR", \$RANDR_EVENT_BASE);

    # Process existing screens
    handle_screens();
    die "No screens found" unless keys %screens;

    # Initial fill of focus structure
    $focus = {
        screen => $screens[0],
        window => undef,
    };

    # Scan for existing windows and handle them
    handle_existing_windows();

    # Ignore not interesting events
    add_event_ignore(CREATE_NOTIFY());
    add_event_ignore(MAP_NOTIFY());
    add_event_ignore(CONFIGURE_NOTIFY());

    # Add several important event handlers
    add_event_cb(MAP_REQUEST(), sub($evt) {
        my ($wid, $follow, $win, $screen, $tag, $floating) = ($evt->{window}, 1);

        # Ignore windows with no class (hello Google Chrome)
        my $class = X11::korgwm::Window::_class($wid);
        unless (defined $class) {
            my $wmname = X11::korgwm::Window::_title($wid) // return;
            return unless $cfg->{noclass_whitelist}->{$wmname};
        }

        # Create a window if needed
        $win = $windows->{$wid};
        if (defined $win) {
            delete $win->{_hidden};
        } else {
            $win = $windows->{$wid} = X11::korgwm::Window->new($wid);

            $X->change_window_attributes($wid, CW_EVENT_MASK, EVENT_MASK_ENTER_WINDOW | EVENT_MASK_PROPERTY_CHANGE);

            # Unconditionally set NormalState for any windows, we do not want to correctly process this property
            $X->change_property(PROP_MODE_REPLACE, $wid, $atom_wmstate, $atom_wmstate, 32, 1, pack L => 1);

            # Fix geometry if needed
            @{ $win }{qw( x y w h )} = $win->query_geometry() unless defined $win->{x};
        }

        # Apply rules
        my $rule = $cfg->{rules}->{$class // ""};
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
            # toggle_floating() won't do for transient, so do some things manually
            $win->{floating} = 1;
            $rule->{follow} //= $cfg->{mouse_follow};
            $win->{transient_for} = $parent;
            $parent->{siblings}->{$wid} = undef;

            $tag = ($parent->tags_visible())[0] // ($parent->tags())[0];
            $screen = $tag->{screen};
            $follow = 0 unless $tag == $screen->current_tag();
        }

        # Set default screen & tag, and fix position
        $screen //= $focus->{screen};
        $tag //= $screen->current_tag();
        if ($win->{x} == 0) {
            $win->{x} = $screen->{x} + int(($screen->{w} - $win->{w}) / 2);
            $win->{y} = $screen->{y} + int(($screen->{h} - $win->{h}) / 2);
        } elsif ($win->{x} < $screen->{x}) {
            $win->{x} += $screen->{x};
        }

        # Just add win to a proper tag. win->show() will be called from tag->show() during screen->refresh()
        $tag->win_add($win);

        if ($win->{transient_for}) {
            if ($win->{w} and $win->{h}) {
                $win->resize_and_move(@{ $win }{qw( x y w h )});
            } else {
                $win->move(@{ $win }{qw( x y )});
            }
        }

        $win->toggle_floating(1) if $floating;
        $win->urgency_raise(1) if $rule->{urgent};

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
    });

    add_event_cb(DESTROY_NOTIFY(), sub($evt) {
        hide_window($evt->{window}, 1);
    });

    add_event_cb(UNMAP_NOTIFY(), sub($evt) {
        # Handle only client unmap requests as we do not call unmap anymore
        hide_window($evt->{window});
    });

    add_event_cb(CONFIGURE_REQUEST(), sub($evt) {
        # Configure window on the server
        my $win_id = $evt->{window};

        if (my $win = $windows->{$win_id}) {
            # This ugly code is an answer to bad apps like Google Chrome
            my %geom;
            my $bw = $cfg->{border_width};

            # Parse masked fields from $evt
            $evt->{value_mask} & $evt_masks{$_} and $geom{$_} = $evt->{$_} for qw( x y w h );

            # Try to extract missing fields
            $geom{$_} //= $win->{$_} // $win->{"real_$_"} for qw( x y w h );

            # Ignore events for not fully configured windows. We've done our best.
            return unless 4 == grep defined, values %geom;

            # Save desired x y w h
            $win->{$_} = $geom{$_} for keys %geom;

            # Fix y
            $geom{y} = $cfg->{panel_height} if $geom{y} < $cfg->{panel_height};

            # Handle floating windows properly
            if ($win->{floating}) {
                my ($old_screen, $new_screen);

                # Verify that it moved inside the same screen
                if (defined $win->{real_y} and any { $geom{$_} != ($win->{"real_$_"} // 0) } qw( x y )) {
                    # Sometimes windows were not move()d prior ConfigureRequest and do not have real_x / real_y
                    # In that case old_screen will be undef and we want just reparent window to a new one
                    $old_screen = screen_by_xy(@{ $win }{qw( real_x real_y )});
                    $new_screen = screen_by_xy(@geom{qw( x y )});

                    if (($old_screen // 0) != $new_screen) {
                        # Reparent screen
                        my $always_on = $win->{always_on};
                        $old_screen->win_remove($win) if $old_screen;
                        $new_screen->win_add($win, $always_on);
                    } else {
                        undef $old_screen;
                    }
                }

                # For floating we need fixup border
                $win->resize_and_move($geom{x}, $geom{y}, $geom{w} + 2 * $bw, $geom{h} + 2 * $bw);

                # Update the screens if needed
                $old_screen->refresh() if $old_screen;
            } else {
                # If window is tiled or maximized, tell it it's real size
                @geom{qw( x y w h )} = @{ $win }{qw( real_x real_y real_w real_h )};

                # Two reasons: 1. some windows prefer not to know about their border; 2. $Layout::hide_border
                $bw = 0 if 0 == ($win->{real_bw} // $cfg->{border_width});
                $geom{x} += $bw;
                $geom{y} += $bw;
                $geom{w} -= 2 * $bw;
                $geom{h} -= 2 * $bw;
            }

            # Send notification to the client and return
            $win->configure_notify($evt->{sequence}, @geom{qw( x y w h )}, 0, 0, $bw);
            $X->flush();
            return;
        }

        # Send xcb_configure_notify_event_t to the window's client
        X11::korgwm::Window::_configure_notify($win_id, @{ $evt }{qw( sequence x y w h )});
        $X->flush();
    });

    # This will handle RandR screen change event
    add_event_cb($RANDR_EVENT_BASE, sub($evt) {
        qx($cfg->{randr_cmd});
        handle_screens();
    });

    # X11 Error handler
    add_event_cb(XCB_NONE(), sub($evt) {
        warn sprintf "X11 Error: code=%s seq=%s res=%s %s/%s", @{ $evt }{qw( error_code sequence
            resource_id major_code minor_code )};
    });

    # Init our extensions
    $_->() for our @extensions;

    # Set the initial pointer position, if needed
    if (my $pos = $cfg->{initial_pointer_position}) {
        if ($pos eq "center") {
            my $screen = $screens[$#screens / 2];
            $ROOT->warp_pointer(map { $screen->{$_ eq "w" ? "x" : "y"} + int($screen->{$_} / 2) - 1 } qw( w h ));
            $screen->focus();
        } elsif ($pos eq "hidden") {
            $ROOT->warp_pointer($ROOT->_rect->width, $ROOT->_rect->height);
        } else {
            croak "Unknown initial_pointer_position: $pos";
        }
    }

    # Main event loop
    for(;;) {
        die "Segmentation fault (core dumped)\n" if $exit_trigger;

        while (my $evt = $X->poll_for_event()) {
            # MotionNotifies(6) are ignored anyways. No room for error
            DEBUG and $evt->{response_type} != 6 and warn Dumper $evt;

            # Highest bit indicates that the source is another client
            my $type = $evt->{response_type} & 0x7F;

            if (defined(my $evt_cb = $xcb_events{$type})) {
                $evt_cb->($evt);
            } elsif (exists $xcb_events_ignore{$type}) {
                DEBUG and warn "Manually ignored event type: $type";
            } else {
                warn "Warning: missing handler for event $type";
            }
        }

        my $pause = AE::cv;
        my $w = AE::timer 0.1, 0, sub { $pause->send };
        $pause->recv;
    }

    # Not reachable code
    die qq(Exception in thread "main" java.lang.ArrayIndexOutOfBoundsException: 0\n    at Main.main(Main.java:26)\n);
}

"Sergei Zhmylev loves FreeBSD";

__END__

=head1 NAME

korgwm - a tiling window manager written in Perl

=head1 DESCRIPTION

Manages X11 windows in a tiling manner and supports all the stuff KorG needs.
Built on top of XCB, AnyEvent, and Gtk3.
It is not reparenting for purpose, so borders are rendered by X11 itself.
There are no any command-line parameters, nor any environment variables.
The only way to start it is: just to execute C<korgwm> when no any other WM is running.
Please see bundled README.md if you are interested in details.

=head1 CONFIGURATION

There are several things which affects korgwm behaviour.
Firstly, it has pretty good config defaults.
Then it reads several files during startup and merges the configuration.
Note that it merges configs pretty silly.
So it is recommended to completely specify rules or hotkeys if you want to change their parts.
The files are being read in such an order: C</etc/korgwm/korgwm.conf>, C<$HOME/.korgwmrc>, C<$HOME/.config/korgwm/korgwm.conf>.

Please see bundled korgwm.conf.sample to get the full listing of available configuration parameters.

=head1 INSTALLATION

As it is written entirely in pure Perl, the installation is pretty straightforward:

    perl Makefile.PL
    make
    make test
    make install

Although it has number of dependencies which in turn rely on C libraries.
To make installation process smooth and nice you probably want to install them in advance.
For Debian GNU/Linux these should be sufficient:

    build-essential libcairo-dev libgirepository1.0-dev libglib2.0-dev xcb-proto

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2023 Sergei Zhmylev E<lt>zhmylove@cpan.orgE<gt>

MIT License.  Full text is in LICENSE.

=cut
