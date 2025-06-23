#!/usr/bin/perl
# made by: KorG
# vim: cc=119 et sw=4 ts=4 :
package X11::korgwm::Panel;
use strict;
use warnings;
use feature 'signatures';

use Gtk3;
use Glib::Object::Introspection;
use AnyEvent;
use X11::korgwm::Common;

# Initialize GTK
gtk_init();

# Prepare internal variables
my ($ready, @ws_names);
sub _init {
    Glib::Object::Introspection->setup(basename => "GdkX11", version  => "3.0", package  => "Gtk3::Gdk");
    @ws_names = @{ $cfg->{ws_names} };
    $ready = 1;
}

# Set title (central label) text
sub title($self, $title = "") {
    if (length($title) > $cfg->{title_max_len}) {
        $title = substr $title, 0, $cfg->{title_max_len};
        $title .= "...";
    }
    $self->{title}->set_text($title);
}

# Add/remove CSS class for a workspace
sub _ws_class_action($self, $action, $id, $class) {
    my $ws = $self->{ws}->[$id - 1];
    $ws->{label}->get_style_context->$action($class);
}
sub ws_class_add($self, $id, $class) { $self->_ws_class_action('add_class', $id, $class) }
sub ws_class_remove($self, $id, $class) { $self->_ws_class_action('remove_class', $id, $class) }

# Set workspace visibility
sub ws_set_visible($self, $id, $new_visible = 1) {
    my $meth = $new_visible ? "show" : "hide";
    my $ws = $self->{ws}->[$id - 1];

    # Prevent hiding of the last visible workspace
    return if not $new_visible and $self->visbile_ws() <= 1;

    $ws->{ebox}->$meth;
}

# Make certain workspace active
sub ws_set_active($self, $new_active) {
    for my $ws (@{ $self->{ws} }) {
        if ($ws->{active}) {
            return if $ws->{id} == $new_active;
            $ws->{active} = undef;
            $self->ws_class_remove($ws->{id}, 'active');
        }

        if ($ws->{id} == $new_active) {
            $ws->{active} = 1;
            $self->ws_class_add($ws->{id}, 'active');
        }
    }
}

# Set workspace urgency
sub ws_set_urgent($self, $ws_id, $urgent = 1) {
    my $ws = $self->{ws}->[$ws_id - 1];
    $ws->{urgent} = $urgent ? 1 : undef;

    return if $urgent and $ws->{active};

    $self->_ws_class_action($urgent ? "add_class" : "remove_class", $ws->{id}, 'urgent');
}

# Clean all appends
sub ws_drop_appends($self) {
    $self->ws_class_remove($_->{id}, 'append') for @{ $self->{ws } };
}

# Mark some ws as appended to current active. Ws should not be active or urgent
sub ws_add_append($self, $ws_id) {
    $self->ws_class_add($ws_id + 1, 'append');
}

# Create new workspace during initialization phase
sub ws_create($self, $title = "", $ws_cb = sub {1}) {
    $self->{ws_num} = 0 unless defined $self->{ws_num};
    my $my_id = ++$self->{ws_num}; # closure

    my $workspace = { id => $my_id };

    my $label = Gtk3::Label->new();
    $label->set_text($title);
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
        $panel->ws_set_visible($_, 0) for 2..@ws_names;
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

sub visbile_ws($self) {
    grep { $_->{ebox}->get_visible() } @{ $self->{ws} };
}

# X11 id of the panel
sub xid($self) {
    Gtk3::Gdk::X11Window::get_xid($self->{window}->get_window());
}

1;
