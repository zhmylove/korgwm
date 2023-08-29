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

our ($X, $cfg, $focus, %screens);
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

    # Set active tag
    [qr/tag_select\((\d+)\)/, sub ($arg) { return sub {
        $focus->{screen}->tag_set_active($arg - 1);
        $focus->{screen}->refresh();
        $X->flush();
    }}],

    # Cycle focus
    [qr/focus_cycle\((.+)\)/, sub ($arg) { return sub {
        my $tag = $focus->{screen}->{tags}->[ $focus->{screen}->{tag_curr} ];
        my $win = $tag->next_window($arg eq "backward");
        return unless defined $win;
        $win->focus();
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
