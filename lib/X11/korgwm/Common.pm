#!/usr/bin/perl
# made by: KorG
# vim: cc=119 et sw=4 ts=4 :
package X11::korgwm::Common;
use strict;
use warnings;
no warnings 'experimental::signatures';
use feature 'signatures';
use Carp;
use Exporter 'import';
use List::Util qw( any first );
use Scalar::Util qw( looks_like_number );

our @EXPORT = qw( DEBUG $X $cfg $focus $windows %screens %xcb_events %xcb_events_ignore @screens
    add_event_cb add_event_ignore hexnum init_extension replace_event_cb screen_by_xy pointer
    $visible_min_x $visible_min_y $visible_max_x $visible_max_y $prevent_focus_in $cpu_saver
    focus_prev_push focus_prev_remove focus_prev_get
    );

# Set after parsing config
sub DEBUG;

our $X;
our $cfg;
our $cpu_saver = 0.1; # number of seconds to sleep before events processing (100ms by default)
our $focus;
our $windows = {};
our %screens;
our %xcb_events;
our %xcb_events_ignore;
our @screens;
our ($visible_min_x, $visible_min_y, $visible_max_x, $visible_max_y);

# Sometimes we want to ignore FocusIn (see Mouse/ENTER_NOTIFY and Executor/tag_select)
our $prevent_focus_in;

# focus_prev() is now implemented as a functional interface and allows switch between more than two windows
my @focus_prev;
my $focus_prev_size = 5;

# Helpers for extensions
sub add_event_cb($id, $sub) {
    croak "Redefined event handler for $id" if defined $xcb_events{$id};
    $xcb_events{$id} = $sub;
}

sub add_event_ignore($id) {
    croak "Redefined event ignore for $id" if defined $xcb_events_ignore{$id};
    $xcb_events_ignore{$id} = undef;
}

sub replace_event_cb($id, $sub) {
    croak "Event handler for $id is not defined" unless defined $xcb_events{$id};
    $xcb_events{$id} = $sub;
}

sub init_extension($name, $first_event) {
    my $ext = $X->query_extension_reply($X->query_extension(length($name), $name)->{sequence});
    die "$name extension not available" unless $ext->{present};

    # We can skip this part unless we're interested getting event
    return unless defined $first_event;
    die "Could not get $name first_event" unless $$first_event = $ext->{first_event};
}

# focus_prev helpers
sub focus_prev_push($win) {
    return unless defined $win;
    focus_prev_remove($win);
    push @focus_prev, $win;
    shift @focus_prev if @focus_prev > $focus_prev_size;
}

sub focus_prev_remove($win) {
    return unless defined $win;
    @focus_prev = grep { $_ != $win } @focus_prev;
}

sub focus_prev_get() {
    (grep { $_ != $focus->{window} } @focus_prev)[-1];
}

# Other helpers
sub screen_by_xy($x, $y) {
    return unless defined $x and defined $y;
    first { $_->contains_xy($x, $y) } @screens;
}

sub hexnum($str = $_) {
    looks_like_number $str ? $str : hex($str);
}

sub pointer($wid = $X->root->id) {
	$X->query_pointer_reply($X->query_pointer($wid)->{sequence}) // {};
}

1;
