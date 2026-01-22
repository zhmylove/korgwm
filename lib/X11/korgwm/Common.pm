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

our @EXPORT = qw(
    carp croak S_DEBUG DEBUG_API $X $cfg $focus $windows %screens %xcb_events %xcb_events_ignore @screens %atoms
    add_event_cb add_event_ignore hexnum init_extension replace_event_cb screen_by_xy pointer %marked_windows
    $visible_min_x $visible_min_y $visible_max_x $visible_max_y $prevent_focus_in $prevent_enter_notify $cpu_saver
    focus_prev_push focus_prev_remove focus_prev_get prevent_focus_in prevent_enter_notify $cached_classes atom
    gtk_init pinned_list pinned_add pinned_remove pinned_check
    );

# NOTE all the debug functions are defined in Config.pm
push @EXPORT, "DEBUG$_" for 1..9;

our $X;
our %atoms;
our $cfg;
our $cpu_saver = 0.1; # number of seconds to sleep before events processing (100ms by default)
our $focus;
our $windows = {};
our $cached_classes = {};
our %screens;
our %xcb_events;
our %xcb_events_ignore;
our @screens;
our ($visible_min_x, $visible_min_y, $visible_max_x, $visible_max_y);
our %marked_windows;

# Sometimes we want to ignore FocusIn (see Mouse/ENTER_NOTIFY and Executor/tag_select)
our $prevent_focus_in;
our $prevent_enter_notify;

# focus_prev() is now implemented as a functional interface and allows switch between more than two windows
my @focus_prev;
my $focus_prev_size = 5;

# Some windows could be always on top of the stack; to avoid confusion with "always_on [tag]" I name them "pinned"
my %pinned_windows;

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
    croak "$name extension not available" unless $ext->{present};

    # We can skip this part unless we're interested getting event
    return unless defined $first_event;
    croak "Could not get $name first_event" unless $$first_event = $ext->{first_event};
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

# pinned_windows helpers
sub pinned_add($win) {
    $pinned_windows{ $win->{id} } = $win;
}

sub pinned_remove($win) {
    delete $pinned_windows{ $win->{id} };
}

sub pinned_list() {
    values %pinned_windows;
}

sub pinned_check($win) {
    exists $pinned_windows{ $win->{id} };
}

# Preventor functions to avoid code copy-pasting
sub prevent_focus_in($timeout = 0.11) {
    $prevent_focus_in = AE::timer $timeout, 0, sub { $prevent_focus_in = undef };
}

sub prevent_enter_notify($timeout = 0.11) {
    $prevent_enter_notify = AE::timer $timeout, 0, sub { $prevent_enter_notify = undef };
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

# Caching function to resolve and create atoms
sub atom($name) {
    return $atoms{$name} if defined $atoms{$name};
    $atoms{$name} = $X->intern_atom_reply($X->intern_atom(0, length($name), $name)->{sequence})->{atom};
}

# GTK initialization (called either from Panel or Expose)
sub gtk_init() {
    return if $X11::korgwm::gtk_init;
    Gtk3::disable_setlocale();
    Gtk3::init();

    my $color_bg = sprintf "#%06x", $cfg->{color_bg};
    my $color_fg = sprintf "#%06x", $cfg->{color_fg};
    my $color_append_bg = sprintf "#%06x", $cfg->{color_append_bg};
    my $color_append_fg = sprintf "#%06x", $cfg->{color_append_fg};
    my $color_battery_low = sprintf '#%06x', $cfg->{color_battery_low};
    my $color_border = sprintf "#%06x", $cfg->{color_border};
    my $color_expose = sprintf "#%06x", $cfg->{color_expose};
    my $color_urgent_bg = sprintf "#%06x", $cfg->{color_urgent_bg};
    my $color_urgent_fg = sprintf "#%06x", $cfg->{color_urgent_fg};
    my ($font_name, $font_size) = $cfg->{font} =~ /(.+)\s+(\d+)$/ or die "Font: $cfg->{font} has invalid format";

    my $css_provider = Gtk3::CssProvider->new();
    my $css = <<~ "CSS";
    * {
        background-color: $color_bg;
        border-radius: 0;
        color: $color_fg;
        font-family: $font_name;
        font-size: ${font_size}pt;
    }

    .expose, .expose > * {
        background-color: $color_expose;
    }

    .append {
        background-color: $color_append_bg;
        color: $color_append_fg;
    }

    .urgent {
        background-color: $color_urgent_bg;
        color: $color_urgent_fg;
    }

    .battery-low {
        color: $color_battery_low;
    }

    calendar {
        border-color: $color_border;
        border: $cfg->{border_width}px solid;
    }

    calendar > * {
        padding: 0 10px;
    }

    calendar.header {
        border-bottom: 0px;
    }

    calendar:indeterminate {
        color: alpha(currentColor, 0.3);
    }

    .active, calendar:selected {
        background-color: $color_fg;
        color: $color_bg;
    }
    CSS

    $css_provider->load_from_data($css);
    Gtk3::StyleContext::add_provider_for_screen(
        Gtk3::Gdk::Screen::get_default(),
        $css_provider,
        Gtk3::STYLE_PROVIDER_PRIORITY_APPLICATION()
    );
    $X11::korgwm::gtk_init = 1;
}

1;
