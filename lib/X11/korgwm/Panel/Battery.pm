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
&X11::korgwm::Panel::add_element("battery", sub($el, %params) {
    AE::timer 0, 30, sub {
        my ($val, $txt, $fd, $battery_low);

        # Get current value
        open $fd, "<", "/sys/class/power_supply/BAT0/capacity" or return;
        $val = 0 + <$fd>;
        $battery_low = 1 if $val <= 16;
        close $fd;

        # Prepare percentage text
        $txt = sprintf $cfg->{battery_format}, $val;

        # Process status
        open $fd, "<", "/sys/class/power_supply/BAT0/status" or return;
        unless (<$fd> eq "Discharging\n") {
            $txt = "" if $val == 100 and $cfg->{battery_hide_charged};
            $txt .= $cfg->{battery_charging_character};
        }
        close $fd;

        $el->set_text($txt);
        $el->get_style_context()->remove_class($_) for @{ $el->get_style_context()->list_classes() // [] };
        $el->get_style_context()->add_class('battery-low') if $battery_low;
    };
});

1;
