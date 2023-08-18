#!/usr/bin/perl
# vim: cc=119 et sw=4 ts=4 :
package X11::korgwm::Tag;
use strict;
use warnings;
use feature 'signatures';
use open ':std', ':encoding(UTF-8)';
use utf8;
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

sub destroy($self) {
    # TODO move window to some other place
    ...;
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
        $_->show for grep defined, @{ $self->{windows_float} }, @{ $self->{windows_tiled} };
        $h -= $cfg->{panel_height};
        $y += $cfg->{panel_height};
        $self->{layout}->arrange_windows($self->{windows_tiled}, $w, $h, $x, $y);
    }

    # Handle focus change
    my $focus = $X11::korgwm::focus;
    $focus->{screen} = $self->{screen};
    my $focus_win = $self->{screen}->{focus};
    if (defined $focus_win) {
        $focus_win->reset_border();
        $focus->{focus} = $focus_win;
        $focus_win->focus();
    }

    $X->flush();
}

sub win_add($self, $win) {
    $win->{on_tags}->{$self} = $self;

    # TODO handle floating windows
    unshift @{ $self->{windows_tiled} }, $win;
}

sub win_remove($self, $win) {
    $self->{max_window} = undef if $win == ($self->{max_window} // 0);

    my $arr;
    $arr = $self->{windows_float};
    splice @{ $arr }, $_, 1 for reverse grep { $arr->[$_] == $win } 0..$#{ $arr };

    $arr = $self->{windows_tiled};
    splice @{ $arr }, $_, 1 for reverse grep { $arr->[$_] == $win } 0..$#{ $arr };

    # If this tag is visible, call screen refresh
    $self->{screen}->refresh() if $self == $self->{screen}->{tags}->[$self->{screen}->{tag_curr}];
}

sub next_window($self) {
    my $win = $self->{max_window};
    return $win if defined $win;
    $win = $self->{windows_float}->[0];
    return $win if defined $win;
    $win = $self->{windows_tiled}->[0];
    return $win;
}

1;
