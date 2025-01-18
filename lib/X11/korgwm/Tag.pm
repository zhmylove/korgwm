#!/usr/bin/perl
# made by: KorG
# vim: cc=119 et sw=4 ts=4 :
package X11::korgwm::Tag;
use strict;
use warnings;
use feature 'signatures';

use List::Util qw( first );
use Scalar::Util qw( weaken );
use X11::XCB ':all';
use X11::korgwm::Common;
use X11::korgwm::Layout;

sub new($class, $screen) {
    weaken($screen);
    bless {
        idx => undef,
        screen => $screen,
        layout => undef,
        max_window => undef,
        windows_float => [],
        windows_tiled => [],
        windows_appended => [],
    }, $class;
}

sub windows($self) {
    grep defined, $self->{max_window}, @{ $self->{windows_float} }, @{ $self->{windows_tiled} };
}

sub destroy($self, $new_screen) {
    # Move windows to a $new_screen
    my $old_screen = $self->{screen};
    my $old_screen_idx = $old_screen->{idx};
    my $old_tag_idx = $self->{idx};
    my $new_tag = $new_screen->{tags}->[$old_tag_idx] || $new_screen->{tags}->[0];

    for my $win ($self->windows()) {
        $new_tag->win_add($win);
        $self->win_remove($win);

        $win->floating_move_screen($old_screen, $new_screen);
        $win->hide() unless $new_tag == $new_screen->current_tag();

        # Save preferred screen to be able to restore window position
        $win->{pref_position}->[@screens] = [$old_screen_idx, $old_tag_idx];
    }

    %{ $self } = ();
}

sub hide($self) {
    # Remove layout and hide on panel if we're hiding an empty tag
    unless ($self->first_window(1)) {
        $self->{layout} = undef;
        $self->{screen}->{panel}->ws_set_visible($self->{idx} + 1, 0) if $cfg->{hide_empty_tags};
    }

    # Hide all windows and drop focus
    $_->hide() for $self->windows();
    $X->flush();
}

# Makes the $self tag visible
# Options:
# - noselect => do not call select() to avoid warp_pointer()
sub show($self, %opts) {
    # Redefine layout if needed
    $self->{layout} //= X11::korgwm::Layout->new();
    DEBUG8 and carp "tag->show($self, @{[%opts]})";

    # Map all windows from the tag
    my ($w, $h, $x, $y) = @{ $self->{screen} }{qw( w h x y )};
    if (defined $self->{max_window}) {
        # If we have maximized window, just place it over the screen
        # I believe there is no need to process focus here, right?
        $self->{max_window}->resize_and_move(@{ $self->{screen} }{qw( x y w h )}, 0);
        $self->{max_window}->show();
        $_->show() for $self->{max_window}->transients();
    } else {
        $self->{screen}->{panel}->ws_set_visible($self->{idx} + 1, 1) if $cfg->{hide_empty_tags};

        # Firstly move
        $h -= $cfg->{panel_height};
        $y += $cfg->{panel_height};
        $self->{layout}->arrange_windows($self->{windows_tiled}, $w, $h, $x, $y);

        # Only then -- show
        for my $win (reverse grep defined,
            @{ $self->{screen}->{always_on} },
            @{ $self->{windows_float} },
            @{ $self->{windows_tiled} }) {
            $win->show();
            $win->reset_border() if $win != ($self->{screen}->{focus} // 0);
        }

        # XXX There should be no need to restack windows here.
        # The only case: if the window stack order was changed on another tag. Fix if any bugs found

        $X->flush();
    }

    # Handle focus change
    $focus->{screen} = $self->{screen};
    my $focus_win = $self->{screen}->{focus};
    if (defined $focus_win and exists $focus_win->{on_tags}->{$self}) {
        # If this window is focused on this tag, just give it a focus
        $focus_win->focus();
    } else {
        # Try to focus previously focused window (or any window)
        if (my $win = $self->{focus} || $self->first_window()) {
            if ($win->{floating} or $win->{maximized} or $opts{noselect}) {
                $win->focus(); # floating, maximized, always_on
            } else {
                $win->select(); # tiled
            }
        }
    }

    $X->flush();
}

sub win_add($self, $win) {
    $win->{on_tags}->{$self} = $self;

    $self->{urgent_windows}->{$win} = undef if $win->urgency_get();
    $self->{screen}->{panel}->ws_set_visible($self->{idx} + 1);

    $self->{max_window} = $win if $win->{maximized};

    my $arr = $win->{floating} ? $self->{windows_float} : $self->{windows_tiled};
    # For windows calling map multiple times
    unshift @{ $arr }, $win unless first { $_ == $win } @{ $arr };
}

# XXX this function is also used for appended windows
sub win_remove($self, $win, $norefresh = undef) {
    delete $win->{on_tags}->{$self};
    delete $self->{urgent_windows}->{$win};

    $self->{max_window} = undef if $win == ($self->{max_window} // 0);

    for my $arr (map { $self->{$_} } qw( windows_float windows_tiled )) {
        @{ $arr } = grep { $win != $_ } @{ $arr };
    }

    # Remove title when removing focused window
    $self->{screen}->{panel}->title() if $win == $focus->{window};

    # Update panel if tag becomes empty
    $self->{screen}->{panel}->ws_set_visible($self->{idx} + 1, 0)
        if $cfg->{hide_empty_tags} and not $self->first_window();

    # Clean preferred focus for this tag if needed
    $self->{focus} = undef if $win == $self->{focus};

    # If this tag is visible, call screen refresh
    $self->{screen}->refresh() if not $norefresh and $self == $self->{screen}->current_tag();
}

sub win_float($self, $win, $floating=undef) {
    # Move $win to appropriate array
    my ($arr_from, $arr_to) = map { $self->{$_} } "windows_float", "windows_tiled";
    ($arr_from, $arr_to) = ($arr_to, $arr_from) if $floating;

    @{ $arr_from } = grep { $win != $_ } @{ $arr_from };
    unshift @{ $arr_to }, $win;
}

# Select some window, if any
sub first_window($self, $only_tag = undef) {
    return $self->{max_window} || $self->{windows_float}->[0] || $self->{windows_tiled}->[0] ||
        ($only_tag ? () : $self->{screen}->{always_on}->[0]);
}

# Select next window
sub next_window($self, $backward = undef) {
    # There is no point in next window when user sees only the maximized one
    return $self->{max_window} if defined $self->{max_window};

    # Look up the focused one
    my $win_curr = $self->{screen}->{focus} or return;

    # Prepare list for search
    my ($idx, $found) = $backward ? -1 : 0;
    my @win_float = (@{ $self->{windows_float} }, @{ $self->{screen}->{always_on} });
    my @win_tiled = @{ $self->{windows_tiled} };

    # If win_curr belongs to other tag, we need any window from the current one
    $found = 1 unless $win_curr->{on_tags}->{$self} or $win_curr->{always_on};

    # Reverse them if searching backward
    if ($backward) {
        @win_float = reverse @win_float;
        @win_tiled = reverse @win_tiled;
    }

    # Do actual search
    for my $win (grep defined, @win_float, @win_tiled, $win_float[$idx], $win_tiled[$idx]) {
        return $win if $found;
        $found = 1 if $win == $win_curr;
    }

    # To avoid ''
    undef;
}

# Append windows from $other tag to $self
sub append($self, $other) {
    # Obvious check
    return if $self == $other;

    # Prevent adding tags with maximized windows
    return if $other->{max_window};

    # Skip empty
    return unless $other->first_window(1);

    for my $win (map { @{ $other->{$_} } } qw( windows_float windows_tiled )) {
        # Add $win to $self manually, bypassing on_tags modification
        my $arr = $win->{floating} ? $self->{windows_float} : $self->{windows_tiled};
        unless (first { $_ == $win } @{ $arr }) {
            unshift @{ $arr }, $win;

            # The window was really added, save it for later use
            unshift @{ $self->{windows_appended} }, $win;

            # Save $self to window
            $win->{also_tags}->{$self} = $self;
        }
    }

    $self->{screen}->{panel}->ws_add_append($other->{idx});
}

# Remove all the windows from appends
sub drop_appends($self) {
    return unless @{ $self->{windows_appended} };

    for my $win (@{ $self->{windows_appended} }) {
        $self->win_remove($win, 1);
        delete $win->{also_tags}->{$self};
        $win->hide();
    }

    $self->{screen}->{panel}->ws_drop_appends();

    $self->{windows_appended} = [];
}

1;
