#!/usr/bin/perl
# made by: KorG
# vim: cc=119 et sw=4 ts=4 :
package X11::korgwm::Config;
use strict;
use warnings;
use feature 'signatures';
use YAML::Tiny;
use X11::korgwm::Common;

BEGIN {
    # Default values
    $cfg->{debug} = 0;
    $cfg->{api_host} = "127.0.0.1";

    ## This may be way too complicated, but thus I'm sure it won't be exploited. Resolves EADDRINUSE
    $cfg->{api_port} = ($ENV{KORGWM_DEBUG_PORT} // "") =~ m/^(\d+)$/s ? $1 : 27015;

    $cfg->{api_timeout} = 5;
    $cfg->{battery_charging_character} = chr(0x2234);
    $cfg->{battery_format} = "%s";
    $cfg->{battery_hide_charged} = 1;
    $cfg->{border_width} = 1;
    $cfg->{clock_format} = " %a %e %B %H:%M";
    $cfg->{color_battery_low} = '0xFF0000';
    $cfg->{color_bg} = '0x262729';
    $cfg->{color_border_focus} = '0xA3BABF';
    $cfg->{color_border} = '0x232426';
    $cfg->{color_expose} = '0x232426';
    $cfg->{color_fg} = '0xA3BABF';
    $cfg->{color_urgent_bg} = '0xFFFF00';
    $cfg->{color_urgent_fg} = '0x464729';
    $cfg->{color_append_bg} = '0x262729';
    $cfg->{color_append_fg} = '0xF502C8';
    $cfg->{expose_spacing} = 15;
    $cfg->{expose_show_id} = 1;
    $cfg->{font} = "DejaVu Sans Mono 10";
    $cfg->{hide_empty_tags} = 1;
    $cfg->{tag_rotate} = 1;
    $cfg->{initial_pointer_position} = "center"; # values: undef, "center", "hidden"
    $cfg->{lang_format} = " %s ";
    $cfg->{lang_names} = { 0 => chr(0x00a3), 1 => chr(0x20bd) };
    $cfg->{mouse_follow} = 1;
    $cfg->{mouse_nowarp} = 0;
    $cfg->{move_follow} = 1;
    $cfg->{warp_ignore_korgwm} = 1;
    $cfg->{notification_server} = 1;
    $cfg->{panel_end} = [qw( battery clock lang )];
    $cfg->{panel_height} = 20;
    $cfg->{panel_hide} = undef;
    $cfg->{randr_cmd} = q(xrandr --output HDMI-A-0 --left-of eDP --auto --output DisplayPort-0 --right-of eDP --auto);
    ## For 4K screens we perhaps need to override:
    # --output HDMI-A-0 --left-of eDP --mode 1920x1080 --output DisplayPort-0 --right-of eDP --mode 1920x1080
    $cfg->{set_root_color} = 0;
    $cfg->{title_max_len} = 128;
    $cfg->{ws_names} = [qw( 1 2 3 4 5 6 7 8 9 )];

    # Default keyboard layout
    $cfg->{hotkeys} = {
        (map {; "mod_$_"                => "focus_move($_)"         } qw(h j k l)),
        (map {; "mod_$_"                => "tag_select($_)"         } 1..9),
        (map {; "mod_F$_"               => "screen_select($_)"      } 1..9),
        (map {; "mod_ctrl_$_"           => "tag_append($_)"         } 1..9),
        (map {; "mod_ctrl_$_"           => "layout_resize($_)"      } qw(h j k l)),
        (map {; "mod_shift_$_"          => "focus_swap($_)"         } qw(h j k l)),
        (map {; "mod_shift_$_"          => "win_move_tag($_)"       } 1..9),
        (map {; "mod_shift_F$_"         => "win_move_screen($_)"    } 1..9),
                "alt_F4"                => "win_close()",
                "mod_shift_c"           => "win_close()",
                "mod_TAB"               => "focus_prev()",
                "alt_TAB"               => "focus_cycle(forward)",
                "alt_shift_TAB"         => "focus_cycle(backward)",
                "mod_CR"                => "exec(xkb-switch -s us; urxvt)",
                "mod_shift_CR"          => "exec(xkb-switch -s us; urxvt -name urxvt-float -g 120x32)",
                "mod_a"                 => "win_toggle_always_on()",
                "mod_shift_ctrl_l"      => "exec(lock)",
                "mod_e"                 => "expose()",
                "mod_shift_s"           => "mark_window()",
                "mod_s"                 => "mark_switch_window()",
                "mod_f"                 => "win_toggle_floating()",
                "mod_p"                 => "win_toggle_pinned()",
                "mod_g"                 => "exec(google-chrome --simulate-outdated-no-au --new-window --incognito)",
                "mod_shift_g"           => "exec(google-chrome --simulate-outdated-no-au --new-window)",
                "mod_m"                 => "win_toggle_maximize()",
                "mod_r"                 => "exec(xkb-switch -s us; rofi -show drun)",
                "mod_w"                 => "exec(firefox --new-instance --private-window)",
                "mod_shift_w"           => "exec(firefox --new-instance)",
                "mod_-"                 => "toggle_calendar()",
                "mod_="                 => "exec(galculator)",
                "mod_ctrl_shift_q"      => "exit()",
                "Print"                 => "exec(flameshot gui)",
                "XF86AudioLowerVolume"  => "nop()",
                "XF86AudioMute"         => "nop()",
                "XF86AudioRaiseVolume"  => "nop()",
                "XF86MonBrightnessDown" => "nop()",
                "XF86MonBrightnessUp"   => "nop()",
                "XF86WakeUp"            => "nop()",
                "mod_alt_F1"            => "exec(pactl set-sink-mute 0 toggle)",
                "mod_alt_F2"            => "exec(pactl set-sink-volume 0 -10%)",
                "mod_alt_F3"            => "exec(pactl set-sink-volume 0 +10%)",
                "mod_alt_F5"            => "exec(light -U 20)",
                "mod_alt_F6"            => "exec(light -A 20)",
    };

    $cfg->{rules} = {
        "evolution"                     => { tag => 3, follow => 0 },
        "evolution-alarm-notify"        => { floating => 1, urgent => 1 },
        "org.gnome.Evolution"           => { screen => 1, tag => 3, follow => 0 },
        "rofi"                          => { pinned => 1 },
        "flameshot"                     => { pinned => 1, floating => 1 },
        "galculator"                    => { floating => 1 },
        "mattermost"                    => { placement => [undef, [1, 4], [2, 4], [3, 4]], follow => 1 },
        "urxvt-float"                   => { floating => 1 },
        "xeyes"                         => { floating => 1 },
    };

    $cfg->{noclass_whitelist} = ["Event Tester", "glxgears"];

    $cfg->{autostart} = ["exec(setxkbmap -layout us,ru -option grp:alt_shift_toggle,compose:ralt)"];

    # Read local configs
    for my $file (
        "/etc/korgwm/korgwm.conf", "/usr/local/etc/korgwm/korgwm.conf",
        "$ENV{HOME}/.korgwmrc", "$ENV{HOME}/.config/korgwm/korgwm.conf"
    ) {
        next unless -f $file;
        my $rcfg;
        eval { $rcfg = YAML::Tiny->read($file) and $rcfg = $rcfg->[0]; 1; } or do {
            print STDERR "Error parsing config file: $@ ";
            exit 2;
        };
        # TODO did not implement validation yet to allow users shoot the legs
        %{ $cfg } = (%{ $cfg }, %{ $rcfg });
    }

    # Prepare whitelist of windows which we want to see with unset WM_CLASS
    $cfg->{noclass_whitelist} = { map { ($_, 1) } @{ $cfg->{noclass_whitelist} } };

    # Normalize numeric values
    $_ = hexnum for @{ $cfg }{grep /^color_/, keys %{ $cfg }};

    # Setup the DEBUG
    ## Allow override via environment and create a closure
    $cfg->{debug} = $1 if ($ENV{KORGWM_DEBUG} // "") =~ /^(\d+)$/ and $1 > 0;
    my $dbglvl = $cfg->{debug};

    ## Append backtrace for higher levels
    $Carp::Verbose = 1 if $dbglvl >= 3;

    ## Export common functions
    *X11::korgwm::Common::DEBUG_API = ($dbglvl or defined $ENV{KORGWM_DEBUG_API}) ? sub() {1} : sub() {undef};

    ## Create per-level constant functions
    ## Create slow S_DEBUG function that can be used within return clause
    {
        no strict 'refs';
        *{"X11::korgwm::Common::DEBUG$_"} = $dbglvl >= $_ ? sub() {1} : sub() {undef} for 1..9;
        *{"X11::korgwm::Common::S_DEBUG"} = sub($lvl, $msg) { $dbglvl >= $lvl and carp $msg; $dbglvl >= $lvl };
    }
}

1;
