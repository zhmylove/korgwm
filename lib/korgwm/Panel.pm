#!/usr/bin/perl
# vim: cc=119 et sw=4 ts=4 :
package korgwm::Panel;
use strict;
use warnings;
use feature 'signatures';
use open ':std', ':encoding(UTF-8)';
use utf8;
use Gtk3 -init;
use AnyEvent;
use POSIX qw(strftime);

# Should get from config
my $font = "DejaVu Sans Mono 10";
my $color_fg = "#a3babf";
my $color_bg = "#262729";
my $color_urgent_bg = "#464729";
my $color_urgent_fg = "#ffff00";
my $clock_format = " %a, %e %B %H:%M ";
my $panel_id = 1;
my $label_max = 64;
my $panel_height = 20;
my @ws_names = qw( T W M C 5 6 7 8 9 );

# Internal variables
$font = Pango::FontDescription::from_string($font);

# Patch Gtk3 for simple label output (yeah, gtk is ugly)
sub Gtk3::Label::txt ($label, $text, $color = $color_fg) {
    $color = $color_fg unless defined $color;
    $label->set_markup(
        sprintf "<span color='$color'>%s</span>",
        Glib::Markup::escape_text($text)
    );
}

# Set title (central label) text
sub title($self, $title = "") {
    if (length($title) > $label_max) {
        $title = substr $title, 0, $label_max;
        $title .= "...";
    }
    $self->{title}->txt($title);
}

# Set workspace color
sub ws_set_color($self, $ws, $new_color_bg, $new_color_fg) {
    $ws = $self->{ws}->[$ws - 1];
    $ws->{ebox}->override_background_color(normal => Gtk3::Gdk::RGBA::parse($new_color_bg));

    my $text = $ws->{label}->get_text;
    $ws->{label}->txt($text, $new_color_fg);
}

# Set workspace visibility
sub ws_set_visible($self, $id, $new_visible = 1) {
    my $meth = $new_visible ? "show" : "hide";
    my $ws = $self->{ws}->[$id - 1];
    return if $ws->{active} and not $new_visible;
    $ws->{ebox}->$meth;
}

# Make certain workspace active
sub ws_set_active($self, $new_active) {
    for my $ws (@{ $self->{ws} }) {
        if ($ws->{active}) {
            if ($ws->{id} == $new_active) {
                $ws->{urgent} = undef;
                return;
            }
            $ws->{active} = undef;
            $self->ws_set_color($ws->{id}, $color_bg, $color_fg);
        }

        if ($ws->{id} == $new_active) {
            $ws->{active} = 1;
            $ws->{urgent} = undef;
            $self->ws_set_color($new_active, $color_fg, $color_bg);
        }
    }
}

# Set workspace urgency
sub ws_set_urgent($self, $ws_id, $urgent = 1) {
    my $ws = $self->{ws}->[$ws_id - 1];
    return if $ws->{active};
    $ws->{urgent} = $urgent ? 1 : undef;
    $self->ws_set_color($ws_id, $urgent ? ($color_urgent_bg, $color_urgent_fg) : ($color_bg, $color_fg));
}

# Create new workspace during initialization phase
sub ws_create($self, $title = "", $ws_cb = sub {1}) {
    $self->{ws_num} = 0 unless defined $self->{ws_num};
    my $my_id = ++$self->{ws_num}; # closure

    my $workspace = { id => $my_id };

    my $label = Gtk3::Label->new();
    $label->txt($title);
    $label->set_size_request($panel_height, $panel_height);
    $label->set_yalign(0.9);

    my $ebox = Gtk3::EventBox->new();
    # $ebox->override_background_color(normal => Gtk3::Gdk::RGBA::parse("#464729"));
    $ebox->signal_connect('button-press-event', sub ($obj, $e) {
        return unless $e->button == 1;
        $self->ws_set_active($my_id);
        $ws_cb->($e->button, $my_id);
    });
    $ebox->add($label);

    $workspace->{label} = $label;
    $workspace->{ebox} = $ebox;
    $workspace;
}

sub new($class, $panel_id, $ws_cb) {
    my ($panel, $window, @workspaces, $label, $clock) = {};
    bless $panel, $class;
    # Prepare window
    $window = Gtk3::Window->new('toplevel');
    $window->modify_font($font);
    $window->set_default_size(1300, 0);
    $window->set_decorated(Gtk3::false);
    $window->set_startup_id("korgwm-panel-$panel_id");
    ## movement is handled in WM

    # Prepare workspaces, label and clock areas
    $label = Gtk3::Label->new();
    $label->set_yalign(0.9);
    $panel->{title} = $label;
    $clock = Gtk3::Label->new();
    $clock->set_yalign(0.9);
    my $clock_w = AE::timer 0, 1, sub { $clock->txt(strftime $clock_format, localtime) };
    $panel->{clock} = $clock;
    $panel->{_clock_w} = $clock_w;

    # Fill in @workspaces
    @workspaces = map { $panel->ws_create($_, $ws_cb) } @ws_names;
    $panel->{ws} = \@workspaces;
    $panel->ws_set_active(1);

    # Render the panel
    my $hdbar = Gtk3::Box->new(horizontal => 0);
    $hdbar->pack_start($_->{ebox}, 0, 0, 0) for @workspaces;
    $hdbar->set_center_widget($label);
    $hdbar->pack_end($clock, 0, 0, 0);
    $hdbar->override_background_color(normal => Gtk3::Gdk::RGBA::parse($color_bg));
    $window->add($hdbar);
    $window->show_all;
    # $panel->ws_set_visible($_, 0) for 1..@ws_names; # TODO uncomment on release

    return $panel;
}

sub iter {
    Gtk3::main_iteration_do(0) while Gtk3::events_pending();
}

# Process stdin
# my $stdin = AE::io *STDIN, 0, sub {
#     my $in = <STDIN>;
#     exit(0) unless defined $in;
#     if ($in =~ /^a\s*(\d)$/) {
#         warn "add workspace: ($1)";
#         return ws_set_visible($1, 1);
#     }
#     if ($in =~ /^r\s*(\d)$/) {
#         warn "remove workspace:: ($1)";
#         return ws_set_visible($1, 0);
#     }
#     if ($in =~ /^s\s*(\d)$/) {
#         warn "switching to ws ($1)";
#         return ws_set_active($1);
#     }
#     if ($in =~ /^u\s*(\d)$/) {
#         warn "toggle urgent: ($1)";
#         return ws_set_urgent($1);
#     }
#     if ($in =~ /^l\s*(\S+.*)?$/) {
#         warn "setting label: ($1)";
#         return title($1);
#     }
#     if ($in =~ /^d$/) {
#         use Data::Dumper;
#         return warn Dumper \@workspaces;
#     }
# 
#     exit(0) if $in =~ /^q$/;
# };
#
# warn <<'@';
#  Usage:
#     a5      -- add workspace #5
#     r3      -- remove workspace #3
#     s8      -- switch to workspace #8
#     u9      -- toggle urgency of workspace #9
#     l TEXT  -- set label text
#     d       -- dump @workspaces
#
# @
#
# my $p = __PACKAGE__->new(1, sub { warn "p1: @_" });
# my $p2 = __PACKAGE__->new(2, sub { warn "p2: @_" });
#
# # Handle gtk events each 1 second
# for(;;) {
#     iter();
#     my $pause = AE::cv;
#     my $w = AE::timer 1, 0, sub { $pause->send };
#     $pause->recv;
# }

1;
