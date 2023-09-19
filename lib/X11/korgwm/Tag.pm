#!/usr/bin/perl
# made by: KorG
# vim: cc=119 et sw=4 ts=4 :
package X11::korgwm::Tag;
use strict;
use warnings;
use feature 'signatures';

use List::Util qw( first );
use Scalar::Util qw( weaken );
use Carp;
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
    }, $class;
}

sub windows($self) {
    grep defined, $self->{max_window}, @{ $self->{windows_float} }, @{ $self->{windows_tiled} };
}

sub destroy($self, $new_screen) {
    # Move windows to some other place
    my $new_tag = $new_screen->{tags}->[0];
    for my $win ($self->windows()) {
        $new_tag->win_add($win);
        $self->win_remove($win);
    }
    %{ $self } = ();
}

sub hide($self) {
    # Remove layout and hide on panel if we're hiding an empty tag
    unless ($self->first_window()) {
        $self->{layout} = undef;
        $self->{screen}->{panel}->ws_set_visible($self->{idx} + 1, 0) if $cfg->{hide_empty_tags};
    }

    # Hide all windows and drop focus
    $_->hide() for $self->windows();
    $X->flush();
}

sub show($self) {
    # Redefine layout if needed
    $self->{layout} //= X11::korgwm::Layout->new();

    # Map all windows from the tag
    my ($w, $h, $x, $y) = @{ $self->{screen} }{qw( w h x y )};
    if (defined $self->{max_window}) {
        # if we have maximized window, just place it over the screen
        # I believe there is no need to process focus here, right?
        $self->{max_window}->resize_and_move(@{ $self->{screen} }{qw( x y w h )}, 0);
        $self->{max_window}->show();
    } else {
        $self->{screen}->{panel}->ws_set_visible($self->{idx} + 1, 1) if $cfg->{hide_empty_tags};
        for my $win (grep defined,
            @{ $self->{screen}->{always_on} },
            @{ $self->{windows_float} },
            @{ $self->{windows_tiled} }) {
            $win->show();
            $win->reset_border() if $win != ($self->{screen}->{focus} // 0);
        }
        $h -= $cfg->{panel_height};
        $y += $cfg->{panel_height};
        $self->{layout}->arrange_windows($self->{windows_tiled}, $w, $h, $x, $y);
        # Raise floating all the time
        $X->configure_window($_->{id}, CONFIG_WINDOW_STACK_MODE, STACK_MODE_ABOVE) for @{ $self->{windows_float} };
        $X->flush();
    }

    # Handle focus change
    $focus->{screen} = $self->{screen};
    my $focus_win = $self->{screen}->{focus};
    if (defined $focus_win and exists $focus_win->{on_tags}->{$self} ) {
        # If this window is focused on this tag, just give it a focus
        $focus_win->focus();
    } else {
        # Try to select next window and give it a focus
        my $win = $self->first_window();
        # XXX maybe drop focus otherwise?
        $win->focus() if $win;
    }

    $X->flush();
}

sub win_add($self, $win) {
    $win->{on_tags}->{$self} = $self;
    $self->{urgent_windows}->{$win} = undef if $win->urgency_get();
    $self->{screen}->{panel}->ws_set_visible($self->{idx} + 1);

    $self->{max_window} = $win if $win->{maximized};
    unshift @{ $win->{floating} ? $self->{windows_float} : $self->{windows_tiled} }, $win;
}

sub win_remove($self, $win, $norefresh = undef) {
    delete $win->{on_tags}->{$self};
    delete $self->{urgent_windows}->{$win};

    $self->{max_window} = undef if $win == ($self->{max_window} // 0);

    my $arr;
    $arr = $self->{windows_float};
    splice @{ $arr }, $_, 1 for reverse grep { $arr->[$_] == $win } 0..$#{ $arr };

    $arr = $self->{windows_tiled};
    splice @{ $arr }, $_, 1 for reverse grep { $arr->[$_] == $win } 0..$#{ $arr };

    # If this tag is visible, call screen refresh
    $self->{screen}->refresh() if not $norefresh and $self == $self->{screen}->current_tag();
}

sub win_float($self, $win, $floating=undef) {
    # Move $win to appropriate array
    my $arr;
    if ($floating) {
        $arr = $self->{windows_tiled};
        splice @{ $arr }, $_, 1 for reverse grep { $arr->[$_] == $win } 0..$#{ $arr };
        unshift @{ $self->{windows_float} }, $win;
    } else {
        $arr = $self->{windows_float};
        splice @{ $arr }, $_, 1 for reverse grep { $arr->[$_] == $win } 0..$#{ $arr };
        unshift @{ $self->{windows_tiled} }, $win;
    }
}

# Select some window, if any
sub first_window($self) {
    return $self->{max_window}      ? $self->{max_window}           :
        $self->{windows_float}->[0] ? $self->{windows_float}->[0]   :
        $self->{windows_tiled}->[0];
}

# Select next window
sub next_window($self, $backward = undef) {
    # There is no point in next window when user sees only the maximized one
    return $self->{max_window} if defined $self->{max_window};

    # Look up the focused one
    my $win_curr = $self->{screen}->{focus} or return;

    # Prepare list for search
    my ($idx, $found) = $backward ? -1 : 0;
    my @win_float = @{ $self->{windows_float} };
    my @win_tiled = @{ $self->{windows_tiled} };

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
}

1;
