#!/usr/bin/perl
# made by: KorG
# vim: cc=119 et sw=4 ts=4 :
package X11::korgwm::Common;
use strict;
use warnings;
use feature 'signatures';
use Carp;
use Exporter 'import';
use List::Util qw( first );

# TODO sort exports list
our @EXPORT = qw( $X $cfg $focus $unmap_prevent $windows %screens @screens add_event_cb replace_event_cb %xcb_events
    init_extension screen_by_xy );

our $X;
our $cfg;
our $focus;
our $unmap_prevent;
our $windows = {};
our %screens;
our %xcb_events;
our @screens;

# Helpers for extensions
sub add_event_cb($id, $sub) {
    croak "Redefined event handler for $id" if defined $xcb_events{$id};
    $xcb_events{$id} = $sub;
}

sub replace_event_cb($id, $sub) {
    croak "Event handler for $id is not defined" unless defined $xcb_events{$id};
    $xcb_events{$id} = $sub;
}

sub init_extension($name, $first_event) {
    my $ext = $X->query_extension_reply($X->query_extension(length($name), $name)->{sequence});
    die "$name extension not available" unless $ext->{present};
    die "Could not get $name first_event" unless $$first_event = $ext->{first_event};
}

# Other helpers
sub screen_by_xy($x, $y) {
    first { $_->{x} < $x and $_->{x} + $_->{w} > $x and $_->{y} < $y and $_->{y} + $_->{h} > $y } @screens;
}

1;
