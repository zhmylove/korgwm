#!/usr/bin/perl
# made by: KorG
# vim: cc=119 et sw=4 ts=4 :
package X11::korgwm::Panel::Clock;
use strict;
use warnings;
use feature 'signatures';

use AnyEvent;
use POSIX qw( strftime );
use X11::korgwm::Common;
use X11::korgwm::Panel;

# Add panel element
&X11::korgwm::Panel::add_element("clock", sub($el, %params) {
    my $ebox = $params{ebox} or croak "Clock EventBox undefined";
    my $panel = $params{panel} or croak "Clock Panel undefined";

    # Handle separate calendar for each panel
    my $calendar;
    my $calendar_x_base = $panel->{x} + $panel->{width};
    my $calendar_y_base = $panel->{y} + $panel->{height};

    # Save the calendar to panel
    $panel->{calendar}->destroy(), delete $panel->{calendar} if $panel->{calendar};
    $panel->{calendar} = $calendar;

    # Create new GtkCalendar window
    $ebox->signal_connect('button-press-event', sub ($obj, $e) {
        return $calendar->destroy(), undef $calendar if $calendar;

        # Create and show the calendar
        $calendar = Gtk3::Window->new('popup');
        my $widget = Gtk3::Calendar->new();
        $widget->signal_connect("month-changed" => sub {
            my ($d, $m, $y) = (localtime)[3, 4, 5];
            $y += 1900;
            if ($widget->get_property('month') == $m and $widget->get_property('year') == $y) {
                $widget->select_day($d)
            } else {
                $widget->select_day(0);
            }
        });
        $calendar->add($widget);
        $calendar->show_all;

        # Move it to the right side of the relevant screen
        $calendar->move($calendar_x_base - ($calendar->get_size())[0], $calendar_y_base);
    });

    # Return watcher
    AE::timer 0, 1, sub { $el->set_text(strftime($cfg->{clock_format}, localtime) =~ s/  +/ /gr) };
});

1;
