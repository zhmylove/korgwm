#!/usr/bin/perl
# made by: KorG
# vim: cc=119 et sw=4 ts=4 :
package X11::korgwm::Panel::Battery;
use strict;
use warnings;
use feature 'signatures';

use AnyEvent;
use X11::korgwm::Common;
use X11::korgwm::Panel;

# Add panel element
&X11::korgwm::Panel::add_element("battery", sub($el) {
    AE::timer 0, 30, sub {
        my ($txt, $fd, $color);

        # Get current value
        open $fd, "<", "/sys/class/power_supply/BAT0/capacity" or return;
        $txt = 0 + <$fd>;
        $color = sprintf '#%x', $cfg->{color_battery_low} if $txt < 16;
        close $fd;

        # Process status
        open $fd, "<", "/sys/class/power_supply/BAT0/status" or return;
        unless (<$fd> eq "Discharging\n") {
            $txt = "" if $txt == 100;
            $txt .= chr(0x2234);
        }
        close $fd;

        $el->txt(sprintf($cfg->{battery_format}, $txt), $color ? $color : ());
    };
});

1;
