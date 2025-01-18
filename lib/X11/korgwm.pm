#!/usr/bin/perl
# made by: KorG
# vim: cc=119 et sw=4 ts=4 :
package X11::korgwm;
use strict;
use warnings;
use feature 'signatures';

our $VERSION = "4.0";

# Third-party includes
use X11::XCB 0.23 ':all';
use X11::XCB::Connection;
use AnyEvent;
use List::Util qw( any first min max none );

# Those two should be included prior any DEBUG stuf
use X11::korgwm::Common;
use X11::korgwm::Config;

# Early initialize debug output, if needed. Should run after Common & Config
BEGIN {
    DEBUG1 and do {
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
use X11::korgwm::Notifications;

# Should you want understand this, first read carefully:
# - libxcb source code
# - X11::XCB source code
# - https://www.x.org/releases/X11R7.7/doc/xproto/x11protocol.txt
# - https://specifications.freedesktop.org/wm-spec/wm-spec-latest.html
# ... though this code is written once to read never.

## Define internal variables
# Ignore CHLD
$SIG{CHLD} = "IGNORE";
# Aliases for event masks
my %evt_masks = (x => CONFIG_WINDOW_X, y => CONFIG_WINDOW_Y, w => CONFIG_WINDOW_WIDTH, h => CONFIG_WINDOW_HEIGHT);
# Default event mask for new windows
my $new_window_event_mask = EVENT_MASK_ENTER_WINDOW | EVENT_MASK_PROPERTY_CHANGE | EVENT_MASK_FOCUS_CHANGE;
# Caching variable for $X->root
my $ROOT;
# Caching variable for WM_STATE atom
my $atom_wmstate;
# Flag shows that we want to ignore errors with type "Window"
my $prevent_window_errors;
# Set to True whenever we want to exit
our $exit_trigger;
# Array for selecting preferred tag during screen change event
my @preferred_tags = ();

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

        # Update visible area information
        $visible_min_x = defined $visible_min_x ? min($visible_min_x, $x)      : $x;
        $visible_min_y = defined $visible_min_y ? min($visible_min_y, $y)      : $y;
        $visible_max_x = defined $visible_max_x ? max($visible_max_x, $x + $w) : $x + $w;
        $visible_max_y = defined $visible_max_y ? max($visible_max_y, $y + $h) : $y + $h;
    }

    # Categorize them
    my @del_screens = grep { not exists $curr_screens{$_} } keys %screens;
    my @new_screens = grep { not defined $screens{$_} } keys %curr_screens;
    my @not_changed_screens = grep { defined $screens{$_} } keys %curr_screens;

    # NOTE we do not want to throw any warnings here to make this function reentrant
    return if @del_screens == 0 and @new_screens == 0;

    # Create screens for new displays
    $screens{$_} = X11::korgwm::Screen->new(split ",", $_) for @new_screens;

    # Find a screen to move windows from the screen being deleted
    my $screen_for_abandoned_windows = (@new_screens, @not_changed_screens)[0];
    $screen_for_abandoned_windows = $screens{$screen_for_abandoned_windows};
    croak "Unable to get the screen for abandoned windows" unless defined $screen_for_abandoned_windows;

    DEBUG1 and carp "Moving stale windows to screen: $screen_for_abandoned_windows";

    # Unfortunately, in case we have to change screen configuration, we must save preferred position for all windows
    # Now iterate over the screens we're not going to delete (the latter will be processed inside destroy() below)
    for my $screen (grep { my $s = $_; ! first { $s == $_ } @del_screens } @screens) {
        my $old_screen_idx = $screen->{idx};

        for my $tag (@{ $screen->{tags} }) {
            my $old_tag_idx = $tag->{idx};
            $_->{pref_position}->[@screens] = [$old_screen_idx, $old_tag_idx] for $tag->windows();
        }
    }

    # Save preferred_tags
    $preferred_tags[@screens] = [ map { $_->{tag_curr} } @screens ];

    # Call destroy on old screens and remove them saving pref_position for all their windows
    for my $s (@del_screens) {
        $screens{$s}->destroy($screen_for_abandoned_windows);
        delete $screens{$s};
    }

    # Sort screens based on X axis and store them in @screens
    DEBUG1 and carp "Old screens: (@screens)";
    @screens = map { $screens{$_} } sort { (split /,/, $a)[0] <=> (split /,/, $b)[0] or $a <=> $b } keys %screens;
    DEBUG1 and carp "New screens: (@screens)";

    # Assign indexes to use them during possible next handle_screens events
    $screens[$_]->{idx} = $_ for 0..$#screens;

    # Move the windows to preferred displays, if possible
    for my $win (values %{ $windows }) {
        # Skip always_on window because they can live only after manual creation
        next if $win->{always_on};

        # Try to get preferred position for the window
        my $pref_position = $win->{pref_position}->[ @screens ];
        unless ($pref_position) {
            # Here is the last chance for windows having no preferred position. We're almost ready to skip them
            my $rules = $cfg->{rules}->{ $win->{cached_class} } or next;
            ref(my $placement = $rules->{ placement }) eq 'ARRAY' or next;

            my ($pref_screen, $pref_tag) = map { max($_ - 1, 0) } @{ $placement->[ @screens ] // next };
            next if $pref_screen >= @screens or $pref_tag >= @{ $cfg->{ws_names} };

            # I solemnly swear that I am up to no good
            $pref_position = [ $pref_screen, $pref_tag ];
        }

        my @win_screens = $win->screens();
        my @win_tags = $win->tags();

        my $old_screen = $win_screens[0];
        my $old_tag = $win_tags[0];

        # Die here if we catch strange windows
        croak "Unimplemented preferred $win position for multiple screens=(@win_screens)" if @win_screens != 1;
        croak "Unimplemented preferred $win position for multiple tags=(@win_tags)" if @win_tags != 1;

        # Below we consider the window belongs to a single screen and tag, so just check if they're preferred
        next if $old_screen->{idx} == $pref_position->[0];

        my $new_screen = $screens[$pref_position->[0]] or croak "Invalid screen in pref_position";
        my $new_tag = $new_screen->{tags}->[$pref_position->[1]] or croak "Invalid tag in pref_position";

        $new_tag->win_add($win);
        $old_tag->win_remove($win);
        $win->floating_move_screen($old_screen, $new_screen);
        $win->hide() unless $new_tag == $new_screen->current_tag();
    }

    # Select preferred tags, if possible
    if (my $preferred_tags = $preferred_tags[@screens]) {
        for my $screen (@screens) {
            my $pref_tag = $preferred_tags->[ $screen->{idx} ] // croak "Invalid tag in preferred_tags";
            $screen->tag_set_active($pref_tag, rotate => 0);
        }
    }

    # Refresh all the screens as we could've moved some windows around
    $_->refresh() for @screens;
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
        $windows->{$transients{$wid}}->{children}->{$wid} = undef;
    }

    # Set proper window information
    for my $win (values %{ $windows }) {
        $win->{floating} = 1;
        $X->composite_redirect_window($win->{id}, COMPOSITE_REDIRECT_AUTOMATIC);
        $X->change_window_attributes($win->{id}, CW_EVENT_MASK, $new_window_event_mask);
        $X->change_property(PROP_MODE_REPLACE, $win->{id}, $atom_wmstate, $atom_wmstate, 32, 1, pack L => 1);

        my ($x, $y, $w, $h) = $win->query_geometry();
        $y = $cfg->{panel_height} if $y < $cfg->{panel_height};
        my $bw = $cfg->{border_width};
        my $screen = screen_by_xy($x, $y) || $focus->{screen};

        # Fix window position if they're outside of the visible screen
        unless ($screen->contains_xy($x, $y)) {
            $x = $screen->{x} + int(($screen->{w} - $w) / 2);
            $y = $screen->{y} + int(($screen->{h} - $h) / 2);
        }

        @{ $win }{qw( x y w h )} = ($x, $y, $w, $h);

        my $class = $win->class();
        if (defined $class) {
            push @{ $cached_classes->{ lc $class } }, $win;
            $win->{cached_class} = lc $class;
        }

        $win->resize_and_move($x, $y, $w + 2 * $bw, $h + 2 * $bw);
        $screen->win_add($win)
    }
    $_->refresh() for reverse @screens;
}

# Destroy and Unmap events handler
sub annihilate_window($wid) {
    my $win = delete $windows->{$wid};
    return unless $win;
    $win->{_hidden} = 1;

    # Ignore Window errors [code=3] closing multiple window at a time
    $prevent_window_errors = AE::timer 0.1, 0, sub { $prevent_window_errors = undef };

    if ($win->{transient_for}) {
        delete $win->{transient_for}->{children}->{$wid};
    }

    for my $tag ($win->tags()) {
        if ($win->{urgent}) {
            delete $tag->{urgent_windows}->{$win};
            $tag->{screen}->{panel}->ws_set_urgent($tag->{idx} + 1, 0) unless keys %{ $tag->{urgent_windows} };
        }

        $tag->win_remove($win);
        if ($win == $tag->{screen}->{focus}) {
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
        @{ $arr } = grep { $win != $_ } @{ $arr };
    }

    if ($win == $focus->{window}) {
        $focus->{window} = undef;
        $focus->{screen}->focus();
    }

    focus_prev_remove($win);

    # Clean-up cached classes index
    if (my $class = $win->{cached_class}) {
        @{ $cached_classes->{ $class } } = grep { $win != $_ } @{ $cached_classes->{ $class } };
    }

    # Delete $win reference from %marked_windows
    delete $marked_windows{$_} for grep { $win == $marked_windows{$_} } keys %marked_windows;
}

# Main routine
sub FireInTheHole {
    # Establish X11 connection
    $X = X11::XCB::Connection->new;
    die "Errors connecting to X11" if $X->has_error();

    # Save root window
    $ROOT = $X->root;

    # Preload some atoms, create non-existent ones
    $atom_wmstate = atom("WM_STATE");

    # Check for another WM
    my $wm = $X->change_window_attributes_checked($ROOT->id, CW_EVENT_MASK,
        EVENT_MASK_SUBSTRUCTURE_REDIRECT |
        EVENT_MASK_SUBSTRUCTURE_NOTIFY |
        EVENT_MASK_POINTER_MOTION
    );
    die "Looks like another WM is in use" if $X->request_check($wm->{sequence});

    DEBUG1 and carp "It's time to chew bubble gum with debug level=$cfg->{debug}";

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

    # Initialize XComposite
    init_extension("Composite", undef);

    # Process existing screens
    handle_screens();
    die "No screens found" unless keys %screens;

    # Update EWMH supported declaration
    &X11::korgwm::EWMH::declare_support();

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
    add_event_ignore(FOCUS_OUT());

    # Add several important event handlers
    add_event_cb(MAP_REQUEST(), sub($evt) {
        my ($wid, $follow, $win, $screen, $tag, $floating) = ($evt->{window}, 1);

        # Ignore windows with no class (hello Google Chrome)
        my $class = X11::korgwm::Window::_class($wid);
        unless (defined $class) {
            my $wmname = X11::korgwm::Window::_title($wid) // return;
            return S_DEBUG(1, "Ignored window $wmname with no class") unless $cfg->{noclass_whitelist}->{$wmname};
        }

        # Create a window if needed
        $win = $windows->{$wid};
        if (defined $win) {
            delete $win->{_hidden};
        } else {
            $win = $windows->{$wid} = X11::korgwm::Window->new($wid);

            # Ask X11 for composition redirect
            $X->composite_redirect_window($wid, COMPOSITE_REDIRECT_AUTOMATIC);

            $X->change_window_attributes($wid, CW_EVENT_MASK, $new_window_event_mask);

            # Unconditionally set NormalState for any windows, we do not want to correctly process this property
            $X->change_property(PROP_MODE_REPLACE, $wid, $atom_wmstate, $atom_wmstate, 32, 1, pack L => 1);

            # Fix geometry if needed
            unless (defined $win->{x}) {
                # Ask X11 about regular geometry
                @{ $win }{qw( x y w h )} = $win->query_geometry();

                # Respect also WM_SIZE_HINTS
                my $hints = $win->size_hints_get();

                if ($hints->{flags} & ICCCM_SIZE_HINT_P_MIN_SIZE) {
                    $win->{w} = $hints->{min_width} if $win->{w} < $hints->{min_width};
                    $win->{h} = $hints->{min_height} if $win->{h} < $hints->{min_height};
                }

                if ($hints->{flags} & ICCCM_SIZE_HINT_P_MAX_SIZE) {
                    $win->{w} = $hints->{max_width} if $win->{w} > $hints->{max_width};
                    $win->{h} = $hints->{max_height} if $win->{h} > $hints->{max_height};
                }
            }
        }

        # Apply rules.  At this point both $screen and $tag are not defined
        my $rule = $cfg->{rules}->{$class // ""};
        if ($rule) {
            defined $rule->{follow} and $follow = $rule->{follow};
            defined $rule->{floating} and $floating = $rule->{floating};

            # XXX awaiting bugs with idx 0
            defined $rule->{screen} and $screen = $screens[ $rule->{screen} - 1 ] // $screens[0];
            defined $rule->{tag} and $tag = $screen->{tags}->[ $rule->{tag} - 1 ];

            # Process preferred position rules with optional fallback to previous $screen & $tag
            my $preferred;
            if (ref $rule->{placement} eq 'ARRAY' && ref($preferred = $rule->{placement}->[ @screens ]) eq 'ARRAY') {
                $screen = $screens[ $preferred->[0] - 1 ] // $screen // $focus->{screen};
                $tag = $screen->{tags}->[ $preferred->[1] - 1 ] // $tag // $screen->current_tag();
            }
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
            $parent->{children}->{$wid} = undef;

            $tag = ($parent->tags_visible())[0] // ($parent->tags())[0];
            $screen = $tag->{screen};
            $follow = 0 unless $tag == $screen->current_tag();
        }

        # Set default screen & tag, and fix position
        $screen //= $focus->{screen};
        $tag //= $screen->current_tag();

        # First and simple check and correction
        if ($win->{x} == 0) {
            $win->{x} = $screen->{x} + int(($screen->{w} - $win->{w}) / 2);
            $win->{y} = $screen->{y} + int(($screen->{h} - $win->{h}) / 2);
        } elsif ($win->{x} < $screen->{x}) {
            $win->{x} += $screen->{x};
        }

        # Make index by initial value of WM_CLASS, save the value to Window as well for proper garbage collection
        if (defined $class) {
            push @{ $cached_classes->{ lc $class } }, $win;
            $win->{cached_class} = lc $class;
        }

        DEBUG3 and carp "Mapping $win [$class] (@{ $win }{qw( x y w h )}) screen($screen->{id}) tag($tag->{idx})";

        # Just add win to a proper tag. win->show() will be called from tag->show() during screen->refresh()
        $tag->win_add($win);

        if ($win->{transient_for}) {
            if ($win->{w} and $win->{h}) {
                $win->resize_and_move(@{ $win }{qw( x y w h )});
            } else {
                $win->move(@{ $win }{qw( x y )});
            }
        }

        # This lines will apply rules
        $win->toggle_floating(1) if $floating;
        $win->urgency_raise(1) if $rule->{urgent};

        # The reason of floating does not matter here so checking the object directly
        prevent_enter_notify() if $win->{floating};

        if ($tag->{max_window} and not $win->relative_for($tag->{max_window})) {
            # There is some maximized window on the tag and $win is not transient for it or its children
            # TODO consider if we want to respect $follow here
            DEBUG2 and carp "Window $win is starting _hidden() behind some maximized one";
            $win->show_hidden();
        } elsif ($follow) {
            $screen->tag_set_active($tag->{idx}, rotate => 0);
            $screen->refresh();
            $win->focus();
            $win->warp_pointer() if $rule->{follow};
        } else {
            if ($screen->current_tag() == $tag) {
                $screen->refresh();
            } else {
                $win->urgency_raise(1);
                $win->show_hidden();
            }
        }

        $X->flush();
    });

    add_event_cb(DESTROY_NOTIFY(), sub($evt) {
        annihilate_window($evt->{window});
    });

    add_event_cb(UNMAP_NOTIFY(), sub($evt) {
        # We do not call unmap(), so delete any window that is being unmapped by client
        annihilate_window($evt->{window});
    });

    add_event_cb(CONFIGURE_REQUEST(), sub($evt) {
        # Configure window on the server
        my $win_id = $evt->{window};

        my $win = $windows->{$win_id};
        unless ($win) {
            # Send xcb_configure_notify_event_t to the window's client
            X11::korgwm::Window::_configure_notify($win_id, @{ $evt }{qw( sequence x y w h )});
            $X->flush();
            return;
        }

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
            # Prevent ConfigureRequest moving the window out of already assigned screen (if real_* set)
            # Otherwise: set new_screen using required win geometry if possible, or use currently focused screen.
            my $new_screen = screen_by_xy(@{ $win }{qw( real_x real_y )}) //
                screen_by_xy(@geom{qw( x y )}) // $focus->{screen};

            # Fix window position if it asked to place it outside of selected screen
            unless ($new_screen->contains_xy(@geom{qw( x y )})) {
                $geom{x} = $new_screen->{x} + int(($new_screen->{w} - $geom{w}) / 2);
                $geom{y} = $new_screen->{y} + int(($new_screen->{h} - $geom{h}) / 2);

                # Certainly save new position
                @{ $win }{qw( x y )} = @geom{qw( x y )};
            }

            # For floating we need fixup border
            $win->resize_and_move($geom{x}, $geom{y}, $geom{w} + 2 * $bw, $geom{h} + 2 * $bw);
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
    });

    # Under certain conditions X11 grants focus to other window generating FocusIn, we'll respect this
    add_event_cb(FOCUS_IN(), sub($evt) {
        # Sometimes X11 sends FocusIn on rapid EnterNotifies: when pointer is not where it thinks it should be
        return if $prevent_focus_in;

        # Skip grab-initiated events
        return unless $evt->{mode} == 0;

        # Skip unknown and already focused windows
        my $win = $windows->{$evt->{event}} or return;
        return if $focus->{window} == $win;

        $win->select();
    });

    # This will handle RandR screen change event
    add_event_cb($RANDR_EVENT_BASE, sub($evt) {
        qx($cfg->{randr_cmd});
        handle_screens();
    });

    # X11 Error handler
    add_event_cb(XCB_NONE(), sub($evt) {
        # https://www.x.org/releases/X11R7.7/doc/xproto/x11protocol.html#Encoding::Errors

        # Ignore Window errors [code=3] closing multiple window at a time
        return if 3 == ($evt->{error_code} || 0) and $prevent_window_errors;

        # Log unexpected errors
        carp sprintf "X11 Error: code=%s seq=%s res=%s %s/%s", @{ $evt }{qw( error_code sequence
            resource_id major_code minor_code )};
    });

    # Init our extensions
    $_->() for our @extensions;

    # Execute autostart, if any
    my $autostart = ref $cfg->{autostart} eq "ARRAY" ? $cfg->{autostart} : [];
    for my $cmd (@{ $autostart }) {
        my $cb;
        eval { $cb = X11::korgwm::Executor::parse($cmd); 1; } or next;
        ref $cb eq "CODE" and $cb->();
    }

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

        my $limit = 1024;
        while ($limit--) {
            my $evt = $X->poll_for_event();
            last unless $evt;

            # MotionNotifies(6) are ignored anyways. No room for error
            DEBUG9 and $evt->{response_type} != 6 and warn Dumper $evt;

            # Highest bit indicates that the source is another client
            my $type = $evt->{response_type} & 0x7F;

            if (defined(my $evt_cb = $xcb_events{$type})) {
                $evt_cb->($evt);
            } elsif (exists $xcb_events_ignore{$type}) {
                DEBUG9 and carp "Manually ignored event type: $type";
            } else {
                carp "Warning: missing handler for event $type";
            }
        }

        my $pause = AE::cv;
        my $w = AE::timer $cpu_saver, 0, sub { $pause->send };
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
There are no any command-line parameters, (almost) nor any environment variables.
The only way to start it is: just to execute C<korgwm> when no any other WM is running.
Please see bundled README.md if you are interested in details.

=head1 CONFIGURATION

There are several things which affects korgwm behaviour.
Firstly, it has pretty good config defaults.
Then it reads several files during startup and merges the configuration.
Note that it merges configs pretty silly.
So it is recommended to completely specify rules or hotkeys if you want to change their parts.
The files are being read in such an order: C</etc/korgwm/korgwm.conf>, C</usr/local/etc/korgwm/korgwm.conf>,
C<$HOME/.korgwmrc>, C<$HOME/.config/korgwm/korgwm.conf>.

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

And these for Archlinux:

    base-devel cairo glib2 gobject-introspection gtk3 libgirepository xcb-proto

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2023--2024 Sergei Zhmylev E<lt>zhmylove@narod.ru<gt>

MIT License.  Full text is in LICENSE.

=cut
