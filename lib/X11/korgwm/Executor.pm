#!/usr/bin/perl
# made by: KorG
# vim: cc=119 et sw=4 ts=4 :
package X11::korgwm::Executor;
use strict;
use warnings;
use feature 'signatures';
use open ':std', ':encoding(UTF-8)';
use utf8;
use Carp;
use X11::XCB ':all';

use Data::Dumper;
$Data::Dumper::Sortkeys = 1;

our ($X, $cfg, $focus, %screens, @screens);
*X = *X11::korgwm::X;
*cfg = *X11::korgwm::cfg;
*focus = *X11::korgwm::focus;
*screens = *X11::korgwm::screens;

# Implementation of all the commands (unless some module push here additional funcs)
our @parser = (
    # Exec command
    [qr/exec\((.+)\)/, sub ($arg) { return sub {
        my $pid = fork;
        die "Cannot fork(2)" unless defined $pid;
        return if $pid;
        exec $arg;
        die "Cannont execute $arg";
    }}],

    # Set active tag
    [qr/tag_select\((\d+)\)/, sub ($arg) { return sub {
        $focus->{screen}->tag_set_active($arg - 1);
        $focus->{screen}->refresh();
        $X->flush();
    }}],

    # Window close or toggle floating / maximize / always_on
    [qr/win_(close|toggle_(?:floating|maximize|always_on))\(\)/, sub ($arg) { return sub {
        my $win = $focus->{window};
        return unless defined $win;

        # Call relevant function
        $arg eq "close"             ? $win->close()             :
        $arg eq "toggle_floating"   ? $win->toggle_floating()   :
        $arg eq "toggle_maximize"   ? $win->toggle_maximize()   :
        $arg eq "toggle_always_on"  ? $win->toggle_always_on()  :
        croak "Unknown win_toggle_$arg function called"         ;

        $focus->{screen}->refresh();
        $X->flush();
    }}],

    # Window move to particular tag
    [qr/win_move_tag\((\d+)\)/, sub ($arg) { return sub {
        my $win = $focus->{window};
        return unless defined $win;

        my $new_tag = $focus->{screen}->{tags}->[$arg - 1] or return;
        my $curr_tag = $focus->{screen}->current_tag();
        return if $new_tag == $curr_tag;

        $win->hide(); # always from visible tag to invisible
        $new_tag->win_add($win);
        $curr_tag->win_remove($win);

        $focus->{screen}->refresh();
        $X->flush();
    }}],

    # Set active screen
    [qr/screen_select\((\d+)\)/, sub ($arg) { return sub {
        while ($arg > 1) {
            return $screens[$arg - 1]->set_active() if defined $screens[$arg - 1];
            $arg--;
        }
        croak "No screens found" unless defined $screens[0];
        $screens[0]->set_active();
    }}],
    [qr/iddqd|idkfa/i, sub { print "I love KorG!\n" }],

    # Window move to particular screen
    [qr/win_move_screen\((\d+)\)/, sub ($arg) { return sub {
        my $win = $focus->{window};
        return unless defined $win;

        my $new_screen = $screens[$arg - 1] or return;
        my $old_screen = $focus->{screen};
        return if $new_screen == $old_screen;

        $old_screen->win_remove($win);
        $new_screen->win_add($win);

        # Follow focus
        $new_screen->{focus} = $win;
        $focus->{screen} = $new_screen;

        # TODO handle maximized

        if ($win->{floating}) {
            my ($new_x, $new_y) = @{ $win }{qw( real_x real_y )};
            $new_x -= $old_screen->{x};
            $new_y -= $old_screen->{y};
            $new_x += $new_screen->{x};
            $new_y += $new_screen->{y};
            $win->move($new_x, $new_y);
        }

        $old_screen->refresh();
        $new_screen->set_active($win);
        $X->flush();
    }}],

    # Cycle focus
    [qr/focus_cycle\((.+)\)/, sub ($arg) { return sub {
        my $tag = $focus->{screen}->current_tag();
        my $win = $tag->next_window($arg eq "backward");
        return unless defined $win;
        $win->focus();
    }}],

    # Exit from WM
    [qr/exit\(\)/, sub ($arg) { return sub {
        $X11::korgwm::exit_trigger = 1;
    }}],
);

# Parses $cmd and returns corresponding \&sub
sub parse($cmd) {
    for my $known (@parser) {
        return $known->[1]->($1) if $cmd =~ m{^$known->[0]$}s;
    }
    # TODO change to croak
    carp "Don't know how to parse $cmd";
    sub { warn "Unimplemented cmd for key pressed: $cmd" };
}

1;
