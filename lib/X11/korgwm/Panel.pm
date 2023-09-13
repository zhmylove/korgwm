#!/usr/bin/perl
# made by: KorG
# vim: cc=119 et sw=4 ts=4 :
package X11::korgwm::Panel;
use strict;
use warnings;
use feature 'signatures';
use open ':std', ':encoding(UTF-8)';
use utf8;
use Carp;
use Gtk3 -init;
use AnyEvent;

# Import config
our $cfg;
*cfg = *X11::korgwm::cfg;

# Prepare internal variables
my ($ready, $font, $color_fg , $color_bg , $color_urgent_bg, $color_urgent_fg, @ws_names);
sub _init {
    $font = Pango::FontDescription::from_string($cfg->{font});
    $color_fg = sprintf "#%x", $cfg->{color_fg};
    $color_bg = sprintf "#%x", $cfg->{color_bg};
    $color_urgent_bg = sprintf "#%x", $cfg->{color_urgent_fg};
    $color_urgent_fg = sprintf "#%x", $cfg->{color_urgent_bg};
    @ws_names = @{ $cfg->{ws_names} };
    $ready = 1;
}

# Patch Gtk3 for simple label output (yeah, gtk is ugly)
sub Gtk3::Label::txt($label, $text, $color=$color_fg) {
    $label->set_markup(
        sprintf "<span color='$color'>%s</span>",
        Glib::Markup::escape_text($text)
    );
}

# Set title (central label) text
sub title($self, $title = "") {
    if (length($title) > $cfg->{title_max_len}) {
        $title = substr $title, 0, $cfg->{title_max_len};
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
            return if $ws->{id} == $new_active;
            $ws->{active} = undef;
            if ($ws->{urgent}) {
                $self->ws_set_color($ws->{id}, $color_urgent_bg, $color_urgent_fg);
            } else {
                $self->ws_set_color($ws->{id}, $color_bg, $color_fg);
            }
        }

        if ($ws->{id} == $new_active) {
            $ws->{active} = 1;
            $self->ws_set_color($new_active, $color_fg, $color_bg);
        }
    }
}

# Set workspace urgency
sub ws_set_urgent($self, $ws_id, $urgent = 1) {
    my $ws = $self->{ws}->[$ws_id - 1];
    $ws->{urgent} = $urgent ? 1 : undef;
    return if $urgent and $ws->{active};
    $self->ws_set_color($ws_id, $urgent ?  ($color_urgent_bg, $color_urgent_fg) :
        $ws->{active} ? ($color_fg, $color_bg) : ($color_bg, $color_fg));
}

# Create new workspace during initialization phase
sub ws_create($self, $title = "", $ws_cb = sub {1}) {
    $self->{ws_num} = 0 unless defined $self->{ws_num};
    my $my_id = ++$self->{ws_num}; # closure

    my $workspace = { id => $my_id };

    my $label = Gtk3::Label->new();
    $label->txt($title);
    $label->set_size_request($cfg->{panel_height}, $cfg->{panel_height});
    $label->set_yalign(0.9);

    my $ebox = Gtk3::EventBox->new();
    $ebox->signal_connect('button-press-event', sub ($obj, $e) {
        return unless $e->button == 1;
        $ws_cb->($e->button, $my_id);
    });
    $ebox->add($label);

    $workspace->{label} = $label;
    $workspace->{ebox} = $ebox;
    $workspace;
}

# Hash for sanity of Panel:: modules (see Panel::Lang for example)
my %elements = (zhmylove =>\& Sergei::Zhmylev);
sub add_element($name, $watcher = undef) {
    croak "Redefined Panel element $name" if defined $elements{$name};
    $elements{$name} = $watcher;
}

sub new($class, $panel_id, $panel_width, $panel_x, $ws_cb) {
    my ($panel, $window, @workspaces, $label) = {};
    _init() unless $ready;
    bless $panel, $class;
    # Prepare main window
    $window = Gtk3::Window->new('popup');
    $window->modify_font($font);
    $window->set_default_size($panel_width, $cfg->{panel_height});
    $window->move($panel_x, 0);
    $window->set_decorated(Gtk3::false);
    $window->set_startup_id("korgwm-panel-$panel_id");

    # Create title label
    $label = Gtk3::Label->new();
    $label->set_yalign(0.9);
    $panel->{title} = $label;

    # Create @workspaces
    @workspaces = map { $panel->ws_create($_, $ws_cb) } @ws_names;
    $panel->{ws} = \@workspaces;
    $panel->ws_set_active(1);

    # Render the panel
    my $hdbar = Gtk3::Box->new(horizontal => 0);
    $hdbar->override_background_color(normal => Gtk3::Gdk::RGBA::parse($color_bg));
    $hdbar->pack_start($_->{ebox}, 0, 0, 0) for @workspaces;
    $hdbar->set_center_widget($label);

    # Add modules to the right-most side of the panel
    for (reverse @{ $cfg->{panel_end} }) {
        croak "Unknown element [$_] in cfg->{panel_end}" unless exists $elements{$_};
        my $el = Gtk3::Label->new();
        $el->set_yalign(0.9);
        $hdbar->pack_end($el, 0, 0, 0);
        $panel->{$_} = $el;
        $panel->{"_w:$_"} = $elements{$_}->($el) if defined $elements{$_};
    }

    # Map window
    $window->add($hdbar);
    $window->show_all unless $cfg->{panel_hide};

    # Hide empty tags if needed
    if ($cfg->{hide_empty_tags}) {
        $panel->ws_set_visible($_, 0) for 1..@ws_names;
    }

    $panel->{window} = $window;
    return $panel;
}

sub destroy($self) {
    $self->{window}->destroy();
    %{ $self } = ();
}

sub iter {
    Gtk3::main_iteration_do(0) while Gtk3::events_pending();
}

1;
