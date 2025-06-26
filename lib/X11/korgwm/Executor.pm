#!/usr/bin/perl
# made by: KorG
# vim: cc=119 et sw=4 ts=4 :
package X11::korgwm::Executor;
use strict;
use warnings;
use feature 'signatures';

use POSIX qw( setsid );
use List::Util qw( any );
use X11::XCB ':all';
use X11::korgwm::Common;

# Implementation of all the commands (unless some module push here additional funcs)
our @parser = (
    # nop
    [qr/nop[wlq]?\((.*)\)/, sub ($arg) { return sub { 1 }}],

    # Exec command
    [qr/exec\((.+)\)/, sub ($arg) { return sub {
        my $pid = fork;
        die "Cannot fork(2)" unless defined $pid;
        return if $pid;
        close $_ for *STDOUT, *STDERR, *STDIN;

        # Intentionally ignoring open(2) errors
        open STDIN, "+<", "/dev/null";
        open STDOUT, ">&STDIN";
        open STDERR, ">&STDIN";

        # Should always succeed after fork(2)
        setsid();
        exec $arg;
        die "Cannot execute $arg";
    }}],

    # Switch to a marked window
    [qr/mark_switch_window\(\)/, sub ($arg) { return sub {
        &X11::korgwm::Hotkeys::grab_key(sub ($data) {
                # $mask is ignored for now, but it is still available
                my ($key, $mask) = @$data;
                return unless defined $key;

                my $win = $marked_windows{$key};
                return S_DEBUG(5, "Cannot find any window with mark " . chr($key)) unless defined $win;

                DEBUG5 and carp "Switching to a window $win with key " . chr($key);
                $win->select();
            });
    }}],

    # Mark a focused window with some character
    [qr/mark_window\(\)/, sub ($arg) { return sub {
        &X11::korgwm::Hotkeys::grab_key(sub ($data) {
                # $mask is ignored for now, but it is still available
                my ($key, $mask) = @$data;
                return unless defined $key and defined $focus->{window};

                DEBUG4 and carp "Marking window $focus->{window} with key " . chr($key);
                $marked_windows{$key} = $focus->{window};
            });
    }}],

    # Set active tag
    [qr/tag_select\((\d+)\)/, sub ($arg) { return sub {
        # Prevent pointer events
        prevent_focus_in();
        prevent_enter_notify();

        $focus->{screen}->tag_set_active($arg - 1);
        $focus->{screen}->refresh();
        $X->flush();
    }}],

    # Append windows from other tag
    [qr/tag_append\((\d+)\)/, sub ($arg) { return sub {
        return unless $arg > 0;
        my $screen = $focus->{screen};
        my $tag = $screen->current_tag();
        my $other = $screen->{tags}->[ $arg - 1 ];
        $tag->append($other);
        $screen->refresh();
        $X->flush();
    }}],

    # Window close or toggle floating / maximize / always_on
    [qr/win_(close|toggle_(?:floating|maximize|always_on|pinned))\(\)/, sub ($arg) { return sub {
        my $win = $focus->{window};
        return unless defined $win;

        # Call relevant function
        $arg eq "close"             ? $win->close()             :
        $arg eq "toggle_floating"   ? $win->toggle_floating()   :
        $arg eq "toggle_maximize"   ? $win->toggle_maximize(2)  :
        $arg eq "toggle_always_on"  ? $win->toggle_always_on()  :
        $arg eq "toggle_pinned"     ? $win->toggle_pinned()     :
        croak "Unknown win_toggle_$arg function called"         ;

        $focus->{screen}->refresh();
        $X->flush();
    }}],

    # Window move to a particular tag
    [qr/win_move_tag\((\d+)\)/, sub ($arg) { return sub {
        my $win = $focus->{window};
        return unless defined $win;

        return if $win->{always_on};

        my ($screen, @multiple) = $win->screens();
        croak "win_move_tag() not implemented for windows on multiple screens" if @multiple;

        my $new_tag = $screen->{tags}->[$arg - 1] or return;
        my $curr_tag = $screen->current_tag();
        return if $new_tag == $curr_tag;

        $win->hide(); # always from visible tag to invisible
        $new_tag->win_add($win);
        $curr_tag->win_remove($win, 1);

        # Follow the window if required
        if ($cfg->{move_follow}) {
            # Prevent unwanted events
            prevent_enter_notify();
            prevent_focus_in();

            $screen->{focus} = $win;
            $screen->tag_set_active($new_tag->{idx}, rotate => 0);
        }

        $screen->refresh();
        $X->flush();

        $win->warp_pointer() if $cfg->{move_follow};
    }}],

    # Set active screen
    [qr/screen_select\((\d+)\)/, sub ($arg) { return sub {
        my $dst = $arg; # to avoid source sub corruption
        while ($dst > 1) {
            return $screens[$dst - 1]->set_active() if defined $screens[$dst - 1];
            $dst--;
        }
        croak "No screens found" unless defined $screens[0];
        $screens[0]->set_active();
    }}],
    [qr/iddqd|idkfa/i, sub { print "I love KorG!\n" }],

    # Window move to particular screen
    [qr/win_move_screen\((\d+)\)/, sub ($arg) { return sub {
        my $win = $focus->{window};
        return unless defined $win;

        my $new_screen = $screens[$arg - 1] or return;
        my ($old_screen, @multiple) = $win->screens();
        croak "win_move_screen() not implemented for windows on multiple screens" if @multiple;
        return if $new_screen == $old_screen;
        return if $new_screen->current_tag->{max_window} and $win->{maximized};

        prevent_enter_notify();

        my $always_on = $win->{always_on};
        $old_screen->win_remove($win, 1);
        $new_screen->win_add($win, $always_on);

        # Follow focus
        $new_screen->{focus} = $win;
        $focus->{screen} = $new_screen;

        $win->floating_move_screen($old_screen, $new_screen);

        $old_screen->refresh();
        $new_screen->set_active($win);
        $X->flush();
    }}],

    # Focus previous window (screen independent)
    [qr/focus_prev\(\)/, sub ($arg) { return sub {
        my $win = focus_prev_get();
        return unless defined $win;

        $win->select();
    }}],

    # Cycle focus
    [qr/focus_cycle\((.+)\)/, sub ($arg) { return sub {
        my $tag = $focus->{screen}->current_tag();
        my $win = $tag->next_window($arg eq "backward");
        return unless defined $win;
        prevent_enter_notify();
        $win->focus();
    }}],

    # Focus move
    [qr/focus_move\(([hjkl])\)/, sub ($arg) { return sub {
        my $win = $focus->{window};
        return unless defined $win;

        my $new = $win->win_by_direction({ h => "left", j => "down", k => "up", l => "right" }->{$arg});
        return unless defined $new;
        $new->focus();
        $new->warp_pointer() if $cfg->{mouse_follow};
    }}],

    # Focus swap
    [qr/focus_swap\(([hjkl])\)/, sub ($arg) { return sub {
        my $win = $focus->{window};
        return unless defined $win;

        my $new = $win->win_by_direction({ h => "left", j => "down", k => "up", l => "right" }->{$arg});
        return unless defined $new;
        $win->swap($new);
    }}],

    # Resize the layout
    [qr/layout_resize\(([hjkl])\)/, sub ($arg) { return sub {
        my $win = $focus->{window};
        return unless defined $win and not $win->{floating};

        my ($delta_x, $delta_y) =
        $arg eq "h" ? (-0.1, 0) :
        $arg eq "j" ? (0, 0.1) :
        $arg eq "k" ? (0, -0.1) :
        $arg eq "l" ? (0.1, 0) : (0, 0);

        # Select proper tag; croak if this window belongs to multiple tags
        my @visible_tags = $win->tags_visible();
        croak "Resizing layout for windows on several visible tags is not implemented" if @visible_tags > 1;
        return unless @visible_tags; # ignore requests for invisibe windows
        my $tag = $visible_tags[0];

        # Call actual resize
        $tag->{layout}->resize(0 + @{ $tag->{windows_tiled} }, @{ $win }{qw( real_i real_j )}, $delta_x, $delta_y);
        $tag->show();
        $win->warp_pointer();
    }}],

    # Expose windows
    [qr/expose\(\)/, sub ($arg) { return sub {
        &X11::korgwm::Expose::expose();
    }}],

    # Open the calendar
    [qr/toggle_calendar\(\)/, sub ($arg) { return sub {
        my $screen = $focus->{screen} // return carp "Focus screen undefined";
        my $ebox = $screen->{panel}->{"_ebox:clock"} // return carp "_ebox:clock undefined";
        my $win = $ebox->get_window() // return carp "Can't find relevant Panel window";
        my $display = $win->get_display() // return carp "Can't find Panel display";
        my $device_manager = $display->get_device_manager() // return carp "Can't find device manager";
        my $device = $device_manager->get_client_pointer() // return carp "Can't find mouse pointer device";

        my $event = Gtk3::Gdk::Event->new('button-press');
        $event->button(Gtk3::Gdk::BUTTON_PRIMARY());
        $event->window($win);
        $event->send_event(Gtk3::true());
        $event->device($device);
        Gtk3::main_do_event($event);
    }}],

    # Make some window urgent by class
    [qr/urgent_by_class\((.+)\)/, sub ($arg) { return sub {
        &X11::korgwm::Window::urgent_by_class($arg);
    }}],

    # Resize the layout from API
    [qr/layout_resize\((\d+\s*,\s*\d+\s*,\s*\d+\s*,\s*\d+\s*,\s*-?0\.\d+\s*,\s*-?0\.\d+)\)/, sub ($arg) { return sub {
        my ($arg_screen, $arg_tag, $arg_i, $arg_j, $arg_delta_x, $arg_delta_y) = split /\s*,\s*/, $arg;
        my $screen = $screens[$arg_screen] // return;
        my $tag = $screen->{tags}->[$arg_tag] // return;
        $tag->{layout}->resize(0 + @{ $tag->{windows_tiled} }, $arg_i, $arg_j, $arg_delta_x, $arg_delta_y);
        $tag->show();
    }}],

    # Exit from WM
    [qr/exit\(\)/, sub ($arg) { return sub {
        $X11::korgwm::exit_trigger = "I can see, friends, we're in for a fabulous evening's apocalypse!";
    }}],
);

# Define some debug internals
DEBUG_API and push @parser,
    [qr/dump_windows\(\)/, sub ($arg) { return sub ($hdl) {
        {
            require Data::Dumper;
            local $Data::Dumper::Sortkeys = 1;
            local $Data::Dumper::Maxdepth = 3;
            $hdl->push_write(Data::Dumper::Dumper($windows));
        }
    }}],
    [qr/dump_screen\((\d+)\)/, sub ($arg) { return sub ($hdl) {
        {
            my $screen = $screens[$arg];
            return $hdl->push_write("No such screen: $arg\n") unless $screen;
            require Data::Dumper;
            local $Data::Dumper::Sortkeys = 1;
            $hdl->push_write(Data::Dumper::Dumper($screen));
        }
    }}],
    [qr/dump_screens\(\)/, sub ($arg) { return sub ($hdl) {
        {
            require Data::Dumper;
            local $Data::Dumper::Sortkeys = 1;
            local $Data::Dumper::Maxdepth = 3;
            $hdl->push_write(Data::Dumper::Dumper(\@screens));
        }
    }}],
    [qr/dump_tag\((\d+\s*,\s*\d+)\)/, sub ($arg) { return sub ($hdl) {
        {
            my ($arg_screen, $arg_tag) = split /\s*,\s*/, $arg;
            my $screen = $screens[$arg_screen];
            return $hdl->push_write("No such screen: $arg_screen\n") unless $screen;
            my $tag = $screen->{tags}->[$arg_tag];
            return $hdl->push_write("No such tag: $arg_tag\n") unless $tag;
            require Storable;
            require Data::Dumper;
            local $Data::Dumper::Sortkeys = 1;
            my $ttag = Storable::dclone($tag);
            $ttag->{screen} = "<truncated screen> " . $tag->{screen}->{id};
            $hdl->push_write(Data::Dumper::Dumper($ttag));
        }
    }}],
;

# Parses $cmd and returns corresponding \&sub
sub parse($cmd) {
    for my $known (@parser) {
        return $known->[1]->($1) if $cmd =~ m{^$known->[0]$}s;
    }
    croak "Don't know how to parse $cmd";
}

1;
