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

    # Toggle floating
    [qr/\Qwin_toggle_floating()/, sub ($arg) { return sub {
        my $win = $focus->{window};
        return unless defined $win;
        $win->toggle_floating();
        $focus->{screen}->refresh();
        $X->flush();
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
