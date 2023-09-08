#!/usr/bin/perl
# made by: KorG
# vim: cc=119 et sw=4 ts=4 :
package X11::korgwm::Config;
use strict;
use warnings;
use feature 'signatures';
use open ':std', ':encoding(UTF-8)';
use utf8;
use Carp;

our $cfg;
*cfg = *X11::korgwm::cfg;

# TODO get from some config file

# Default values
$cfg->{battery_format} = "%s";
$cfg->{border_width} = 1;
$cfg->{clock_format} = " %a, %e %B %H:%M";
$cfg->{color_battery_low} = 0xFF0000;
$cfg->{color_bg} = 0x262729;
$cfg->{color_border_focus} = 0xA3BABF;
$cfg->{color_border} = 0x232426;
$cfg->{color_fg} = 0xA3BABF;
$cfg->{color_urgent_bg} = 0x464729;
$cfg->{color_urgent_fg} = 0xFFFF00;
$cfg->{font} = "DejaVu Sans Mono 10";
$cfg->{hide_empty_tags} = 0;
$cfg->{initial_pointer_position} = "center"; # values: undef, "center", "hidden"
$cfg->{lang_format} = " %s ";
$cfg->{lang_names} = { 0 => chr(0x00a3), 1 => chr(0x20bd) };
$cfg->{panel_end} = [qw( battery clock lang )];
$cfg->{panel_height} = 20;
$cfg->{panel_hide} = undef;
$cfg->{randr_cmd} = q(xrandr --output HDMI-A-0 --left-of eDP --auto --output DisplayPort-0 --right-of eDP --auto);
$cfg->{set_root_color} = 0;
$cfg->{title_max_len} = 64;
$cfg->{ws_names} = [qw( T W M C 5 6 7 8 9 )];

# TODO brightness, galculator, wifi, volume, media buttons
$cfg->{hotkeys} = {
    (map {; "mod_$_"            => "focus_move($_)"         } qw(h j k l)), # TODO
    (map {; "mod_$_"            => "tag_select($_)"         } 1..9),
    (map {; "mod_F$_"           => "screen_select($_)"      } 1..9),
    (map {; "mod_ctrl_$_"       => "tag_append($_)"         } 1..9), # TODO
    (map {; "mod_shift_$_"      => "focus_swap($_)"         } qw(h j k l)), # TODO
    (map {; "mod_shift_$_"      => "win_move_tag($_)"       } 1..9),
    (map {; "mod_shift_F$_"     => "win_move_screen($_)"    } 1..9),
            "alt_F4"            => "win_close()",
            "mod_shift_c"       => "win_close()",
            "alt_TAB"           => "focus_cycle(forward)",
            "alt_shift_TAB"     => "focus_cycle(backward)",
            "mod_CR"            => "exec(urxvt)",
            "mod_shift_CR"      => "exec(urxvt -name urxvt-float)",
            "mod_a"             => "win_toggle_always_on()",
            "mod_ctrl_l"        => "exec(lock)",
            "mod_e"             => "expose()", # TODO
            "mod_f"             => "win_toggle_floating()",
            "mod_g"             => "exec(google-chrome --new-window --incognito)",
            "mod_shift_g"       => "exec(google-chrome --new-window)",
            "mod_m"             => "win_toggle_maximize()", # TODO
            "mod_r"             => "exec(dmenu_run -i -nb #262729 -nf #A3BABF -sb #464729 -sf #FFFF00)",
            "mod_w"             => "exec(firefox --new-instance --private-window)",
            "mod_shift_w"       => "exec(firefox --new-instance)",
            "mod_ctrl_shift_q"  => "exit()",
};

1;
