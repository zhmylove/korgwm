#!/usr/bin/perl
# vim: sw=4 ts=4 et cc=119 :
use strict;
use warnings;
use feature 'signatures';
use lib 'lib', '../X11-Xlib-0.23-work/lib', '../X11-Xlib-0.23-work/blib/arch';
use open ':std', ':encoding(UTF-8)';
use utf8;
use X11::Xlib ':all';
use X11::Protocol;
use X11::korgwm::Panel;

use Data::Dumper; # TODO remove

# TODO Should get from config
my $panel_height = 20;

# Initialization phase: connect to x11, prepare screens, subscribe for events
my $X = X11::Protocol->new();
$X->init_extension("XINERAMA") or die "XINERAMA not available";

my $display = X11::Xlib->new();
die "Use XINERAMA or die!" unless $display->screen_count() == 1;
my $screen = $display->screen(0);

# There is only one root window
my $root = $screen->root_window;

# Become a WM
my $error_caught = undef;
X11::Xlib::on_error(sub { $error_caught = 1 });
$root->event_mask_include(SubstructureRedirectMask, SubstructureNotifyMask);
$display->flush_sync();
die "Looks like other WM is running" if $error_caught;

# Detect real monitors
my $screens;

sub add_screen($id, $x, $y, $width, $height) {
    my $s = {};
    @{$s}{qw(present width height x y)} = (1, $width, $height, $x, $y);
    $s->{tags} = {}; # TODO create tags
    my $sid = $id;
    $s->{panel} = korgwm::Panel->new($id, sub { warn "ws_cb for screen $sid [@_]" });
    $screens->{$id} = $s;
}

if ($X->XineramaIsActive()) {
    my $id = 0;
    add_screen $id++, @$_ for $X->XineramaQueryScreens();
    die "Unable to get monitors" unless $id;
} else {
    add_screen(0, 0, 0, $screen->width, $screen->height);
}

warn Dumper $screens; # TODO remove

# Functions for keyboard events
## We're not interested in CHLD
$SIG{CHLD} = "IGNORE";

## Run new process
sub run_cmd($args) {
    my $cmd = defined $args ? $args->{cmd} : undef;
    next unless defined $cmd;
    my $pid = fork;
    die "Cannot fork(2)" unless defined $pid;
    return if $pid;
    exec $cmd;
    die "Cannot execute $cmd";
    ...;
}

# TODO move to some config
# Prepare configuration for hotkeys
my @keys_config = (
    {
        key => 'p',
        mod => Mod4Mask,
        cb => \&run_cmd,
        args => { cmd => 'xterm -font "xft:DejaVu Sans Mono" -fs 14 -g 150x40' }
    },
    {
        key => 'q',
        mod => Mod4Mask,
        cb => sub { exit 0 },
        args => {}
    },
);

# Initialize WM keybindings
my $keys_cb;
for my $hotkey (@keys_config) {
    my $keycode = $display->keymap->find_keycode($hotkey->{key});
    XGrabKey($display, $keycode, $hotkey->{mod}, $root, 0, GrabModeAsync, GrabModeAsync);
    $keys_cb->{$keycode} = sub { $hotkey->{cb}->($hotkey->{args}) };
}
$display->flush_sync();

# Handlers for events
my $evt_cb = {
    "X11::Xlib::XConfigureRequestEvent" => sub ($evt) {
        my %changes;

        # TODO deal somehow with fullscreen
        # TODO handle somehow modal windows
        # TODO process existing windows to move them below the panel and set their size
        $changes{$_} = $evt->$_ for qw( x y width height border_width );
        $changes{y} = $panel_height if $panel_height > $changes{y} // $panel_height;
        $changes{sibling} = $evt->above;
        $changes{stack_mode} = $evt->detail;
        XConfigureWindow($display, $evt->window, $evt->value_mask | CWY, \%changes);
        $display->flush();
    },
    "X11::Xlib::XKeyEvent" => sub ($evt) {
        return unless $evt->type == KeyPress;
        return unless defined (my $cb = $keys_cb->{$evt->keycode});
        $cb->();
    },
    "X11::Xlib::XMapRequestEvent" => sub ($evt) {
        # TODO resize window here ..?

        my $win = X11::Xlib::Window->new(display => $display, xid => $evt->window);

        # Handle known startup ids
        my $startup_id = $win->get_property($display->mkatom("_NET_STARTUP_ID"));
        $startup_id = defined $startup_id ? $startup_id->{data} : "";
        warn Dumper ["Startup ID:", $startup_id];

        if (index($startup_id, "korgwm-panel-") == 0) {
            # TODO handle RandR somehow to distinguish real screens
            my $screen_id = substr $startup_id, 13;
            my $screen = $screens->{$screen_id};
            die "Cannot find screen for panel $screen_id" unless $screen;
            XConfigureWindow($display, $evt->window, CWX | CWY | CWWidth, { x => $screen->{x},
                    y => 0, width => $screen->{width} });
        } else {
            #XConfigureWindow($display, $evt->window, CWX | CWY, { x => 40, y => 10 });
        }

        $win->show();
        $display->flush();
    },
    "X11::Xlib::XConfigureEvent" => sub ($evt) {
        warn Dumper [map { $evt->$_ } qw( above border_width event height override_redirect width window x y )];
    },
};

for(;;) {
    # TODO (obsoleted, but what is timeout?) rewrite event loop to handle events from Xlib, Gtk and AE and set timeout = 0

    # Process Gtk events from each screen panel
    $screens->{$_}->{panel}->iter() for keys %{ $screens };

    # Process Xlib events
    if (defined(my $evt = $display->wait_event(timeout => 0.01))) {
        # TODO check if wait_event could be interrupted
        my $ref = ref $evt;
        my $cb = $evt_cb->{$ref};
        printf STDERR "Evt: %s (w:%s) handler: %s\n", $ref, $evt->window // "undef", $cb // "IGNORE";
        defined $cb && $cb->($evt);
    }

    # TODO Process AE events here
}
