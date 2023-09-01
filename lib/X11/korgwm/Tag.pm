#!/usr/bin/perl
# made by: KorG
# vim: cc=119 et sw=4 ts=4 :
package X11::korgwm::Tag;
use strict;
use warnings;
use feature 'signatures';
use open ':std', ':encoding(UTF-8)';
use utf8;
use List::Util qw( first );
use Carp;
use X11::XCB ':all';
use X11::korgwm::Layout;

use Data::Dumper;
$Data::Dumper::Sortkeys = 1;

our ($X, $cfg);
*X = *X11::korgwm::X;
*cfg = *X11::korgwm::cfg;

sub new($class, $screen) {
    bless {
        screen => $screen,
        layout => undef,
        max_window => undef,
        windows_float => [],
        windows_tiled => [],
    }, $class;
}

sub destroy($self, $new_screen) {
    # Move windows to some other place
    my $new_tag = $new_screen->{tags}->[0];
    for my $win (grep defined, $self->{max_window}, @{ $self->{windows_float} }, @{ $self->{windows_tiled} }) {
        $new_tag->win_add($win);
        $self->win_remove($win);
    }
    %{ $self } = ();
}

sub hide($self) {
    # Remove layout if we're hiding empty tag
    $self->{layout} = undef unless
        defined $self->{max_window} or
        @{ $self->{windows_float} } or
        @{ $self->{windows_tiled} };

    # Hide all windows
    $_->hide for grep defined, $self->{max_window}, @{ $self->{windows_float} }, @{ $self->{windows_tiled} };
    $X->flush();
}

sub show($self) {
    # Redefine layout if needed
    $self->{layout} //= X11::korgwm::Layout->new();

    # Map all windows from the tag
    my ($w, $h, $x, $y) = @{ $self->{screen} }{qw( w h x y )};
    if (defined $self->{max_window}) {
        # if we have maximized window, just place it over the screen
        ...;
    } else {
        $_->show for grep defined,
            @{ $self->{screen}->{always_on} },
            @{ $self->{windows_float} },
            @{ $self->{windows_tiled} };
        $h -= $cfg->{panel_height};
        $y += $cfg->{panel_height};
        $self->{layout}->arrange_windows($self->{windows_tiled}, $w, $h, $x, $y);
        # Raise floating all the time
        $X->configure_window($_->{id}, CONFIG_WINDOW_STACK_MODE, STACK_MODE_ABOVE) for @{ $self->{windows_float} };
        $X->flush();
    }

    # Handle focus change
    my $focus = $X11::korgwm::focus;
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

    unshift @{ $win->{floating} ? $self->{windows_float} : $self->{windows_tiled} }, $win;
}

sub win_remove($self, $win) {
    delete $win->{on_tags}->{$self};

    $self->{max_window} = undef if $win == ($self->{max_window} // 0);

    my $arr;
    $arr = $self->{windows_float};
    splice @{ $arr }, $_, 1 for reverse grep { $arr->[$_] == $win } 0..$#{ $arr };

    $arr = $self->{windows_tiled};
    splice @{ $arr }, $_, 1 for reverse grep { $arr->[$_] == $win } 0..$#{ $arr };

    # If this tag is visible, call screen refresh
    $self->{screen}->refresh() if $self == $self->{screen}->current_tag();
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

    # Ok, so firstly we want to look up focused window
    my $win_curr = $self->{screen}->{focus};
    return unless defined $win_curr;

    # Check floating first
    my $arr = $self->{windows_float};
    my ($idx) = grep { $arr->[$_] == $win_curr } 0..$#{ $arr };
    if (defined $idx) {
        # Try to guess next window
        if ($backward) {
            if ($idx == 0) {
                # Previous window will be either last tiled, or last float
                return first { defined } $self->{windows_tiled}->[-1], $self->{windows_float}->[-1];
            } else {
                # Previous window is previous float
                return $self->{windows_float}->[$idx - 1];
            }
        } else {
            if ($idx == $#{ $arr }) {
                # Next window will be either first tiled, or first float
                return first { defined } $self->{windows_tiled}->[0], $self->{windows_float}->[0];
            } else {
                # Next window is next float
                return $self->{windows_float}->[$idx + 1];
            }
        }
    }

    # Then check tiled
    $arr = $self->{windows_tiled};
    ($idx) = grep { $arr->[$_] == $win_curr } 0..$#{ $arr };

    # Looks like there is no focused window among current tag, so just drop next_window request
    return unless defined $idx;

    # Again: guess next window
    if ($backward) {
        if ($idx == 0) {
            # Previous window will be either last float, or last tiled
            return first { defined } $self->{windows_float}->[-1], $self->{windows_tiled}->[-1];
        } else {
            # Previous window is previous tiled
            return $self->{windows_tiled}->[$idx - 1];
        }
    } else {
        if ($idx == $#{ $arr }) {
            # Next window will be either first float, or first tiled
            return first { defined } $self->{windows_float}->[0], $self->{windows_tiled}->[0];
        } else {
            # Next window is next float
            return $self->{windows_tiled}->[$idx + 1];
        }
    }
}

1;
