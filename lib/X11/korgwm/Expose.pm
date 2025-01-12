#!/usr/bin/perl
# made by: KorG
# vim: cc=119 et sw=4 ts=4 :
package X11::korgwm::Expose;
use strict;
use warnings;
use feature 'signatures';

use Carp;
use List::Util qw( any );
use POSIX qw( ceil );
use X11::XCB ':all';
use X11::korgwm::Common;
use Glib::Object::Introspection;
use Gtk3;

unless ($X11::korgwm::gtk_init) {
    Gtk3::disable_setlocale();
    Gtk3::init();
    $X11::korgwm::gtk_init = 1;
}

my $display;
my $win_expose;
my $font;
my ($color_fg, $color_bg, $color_expose);
my ($color_gdk_fg, $color_gdk_bg, $color_gdk_expose);

sub _create_thumbnail($scale, $win, $title, $id, $cb) {
    my $vbox = Gtk3::Box->new(vertical => 0);
    my $vbox_inner = Gtk3::Box->new(vertical => 0);
    my $pixbuf = $win->_get_pixbuf();

    # Normalize size
    my ($w, $h) = ($pixbuf->get_width(), $pixbuf->get_height());
    ($w, $h) = ($h, $w) if $h > $w;
    $h = int($scale * $h / $w);
    $w = $scale;

    # Prepare image
    my $thumbnail = $pixbuf->scale_simple($w, $h, 'bilinear');
    my $image = Gtk3::Image->new_from_pixbuf($thumbnail);
    $image->override_background_color(normal => $color_gdk_fg);

    # Put a frame around it
    my $frame = Gtk3::Frame->new();
    my $hbox = Gtk3::Box->new(horizontal => 0);
    $frame->add($image);
    $hbox->set_center_widget($frame);

    # Prepare label
    my $label = Gtk3::Label->new();
    $label->txt($title); # this imlicitly depends on the hack from X11::korgwm::Panel
    $label->set_margin_top(5);
    $label->set_ellipsize('middle');

    # Prepare id label
    my $label_id = Gtk3::Label->new();
    $label_id->txt($id); # this imlicitly depends on the hack from X11::korgwm::Panel
    $label_id->set_margin_bottom(5);

    # Place elements
    $vbox_inner->pack_start($label_id, 0, 0, 0) if $cfg->{expose_show_id};
    $vbox_inner->pack_start($hbox, 0, 0, 0);
    $vbox_inner->pack_start($label, 0, 0, 0);
    $vbox->set_center_widget($vbox_inner);

    # Add a callback
    my $ebox = Gtk3::EventBox->new();
    $ebox->add($vbox);
    $ebox->signal_connect('button-press-event', $cb);
    return $ebox;
}

# Returns estimated number of rows based on WxH and number of windows
sub _get_rownum($number, $width, $height) {
    my $rownum = 1;
    return $rownum if $number <= 1;
    for (;; $rownum++) {
        return $rownum if $rownum * $rownum * $width / $height > $number + 1;
    }
}

# Main routine
sub expose {
    # Drop any previous window
    return if $win_expose;

    # We should return earlier unless windows exist
    my $nwindows = keys %{ $windows };
    return unless $nwindows;

    # If there is only one window we just want to focus it.
    # Sorry for this ugly code. The logic is mostly copied from focus_prev() of Executor
    if ($nwindows == 1) {{
        my $win = (values %{ $windows })[0];
        return carp "Unable to find single existing window to focus" unless $win;

        last unless 1 == $win->tags();
        $win->select() and return;
    }}

    # Select current screen
    my $screen_curr = $focus->{screen};

    # Create a window for expose
    $win_expose = Gtk3::Window->new('popup');
    $win_expose->modify_font($font);
    $win_expose->set_default_size(@{ $screen_curr }{qw( w h )});
    $win_expose->move(@{ $screen_curr }{qw( x y )});
    $win_expose->override_background_color(normal => $color_gdk_expose);

    # Create a grid
    my $grid = Gtk3::Grid->new();
    $grid->set_column_spacing($cfg->{expose_spacing});
    $grid->set_row_spacing($cfg->{expose_spacing});
    $grid->set_margin_start($cfg->{expose_spacing});
    $grid->set_margin_end($cfg->{expose_spacing});
    $grid->set_margin_top($cfg->{expose_spacing});
    $grid->set_margin_bottom($cfg->{expose_spacing});
    $grid->set_row_homogeneous(1);
    $grid->set_column_homogeneous(1);

    # Prepare thumbnails
    my ($x, $y) = (0, 0);

    # Estimate sizes
    # XXX it is incorrect as one window could belong to several tags, dont know how to represent it so left it for now
    my $rownum = _get_rownum($nwindows, @{ $screen_curr }{qw( w h )});
    my $scale = 0.9 * ($screen_curr->{h} - $rownum * 2 * $cfg->{expose_spacing}) / $rownum;

    # This math formulae describes proper number of characters in window ID: 9 => 1, 10 => 2, 89 => 2, 90 => 3
    my $lgnwindows = ceil(log($nwindows)/log(10));
    my $id_len = $nwindows <= 9 ? 1 :
        $nwindows <= (10 ** $lgnwindows - 10 ** ($lgnwindows - 1)) ?
        $lgnwindows : $lgnwindows + 1;

    my %callbacks;
    my $shortcut_str = "";
    my $shortcut = Gtk3::Label->new();

    # Draw the windows
    my $total_windows = 0;
    my $last_cb;
    for my $screen (values %screens) {
        for my $tag (@{ $screen->{tags} }) {
            for my $win ($tag->windows()) {
                # Event-independent callback
                my $cb = sub {
                    prevent_focus_in();
                    prevent_enter_notify();
                    $win_expose->destroy();
                    $win_expose = undef;
                    $win->select();
                };

                # Count them for quick path
                $total_windows++;
                $last_cb = $cb;

                # Form an id for quick access if $cfg->{expose_show_id}
                my $id = sprintf "%0${id_len}d", 10 ** ($id_len - 1) + keys %callbacks;
                my $id_str = "[$id]"; # should be string to avoid {0} === {"0"}
                $callbacks{$id_str} = $cb if $cfg->{expose_show_id};

                # Create thumbnail
                my $ebox = _create_thumbnail($scale, $win, $win->title(), $id_str, sub ($obj, $e) {
                    return unless $e->button == 1;
                    $cb->();
                });

                $x++, $y = 0 if $y >= $rownum;
                $grid->attach($ebox, $x, $y++, 1, 1);
            }
        }
    }

    return $last_cb->() if $total_windows == 1;

    # Append simple keyboard handlers
    $win_expose->signal_connect('key-press-event', sub ($obj, $e) {
        if ($e->keyval() == 0xff1b) { # XK_Escape from <X11/keysymdef.h>
            $win_expose->destroy();
            $win_expose = undef;
        } elsif ($e->keyval() == 0xff08) { # XK_Backspace
            $shortcut_str = substr $shortcut_str, 0, -1;
            $shortcut->txt($shortcut_str);
        } elsif ($e->keyval() >= 0x30 and $e->keyval() <= 0x39) {
            $shortcut_str .= chr($e->keyval());
            $shortcut->txt($shortcut_str);
            $callbacks{"[$shortcut_str]"}->() if $callbacks{"[$shortcut_str]"};
        } elsif ($e->keyval() == 0x20 or $e->keyval() == 0xff0d) { # XK_Space or XK_Return
            $shortcut_str = "";
            $shortcut->txt($shortcut_str);
        }
    });

    # Compose window elements
    if ($cfg->{expose_show_id}) {
        # Add shortcut label
        my $vbox = Gtk3::Box->new(vertical => 0);
        $vbox->pack_start($shortcut, 0, 0, $cfg->{expose_spacing});
        $vbox->set_center_widget($grid);
        $win_expose->add($vbox);
    } else {
        $win_expose->add($grid);
    }

    # Map the window
    $win_expose->show_all();

    # Grab keyboard
    my $grab_status;
    my $grab_tries = 2**10;
    do {
        $grab_status = $display->get_default_seat()->grab($win_expose->get_window(), "keyboard", 0, (undef) x 4);
    } while ($grab_tries-- and $grab_status eq 'already-grabbed');
}

# TODO consider adding this right into Window.pm (if Expose will work good)
# Inverse approach is used in order to simplify Expose deletion / re-implementation
BEGIN {
    # Insert some pixbuf-specific methods 
    sub X11::korgwm::Window::_get_pixbuf($self) {
        # If the window was not mapped, draw it in black
        return Gtk3::GdkPixbuf::Pixbuf->new_from_xpm_data(['1 1 1 1', 'a c #262729', 'a'])
            unless $self->{real_w} and $self->{real_h};

        # This routine gets RGBA 24TT image but Gtk3 cat convert it only to 8-bit Pixbuf :(
        my $pixmap = $X->generate_id();
        $X->composite_name_window_pixmap($self->{id}, $pixmap);
        my $image = $X->get_image(IMAGE_FORMAT_Z_PIXMAP, $pixmap, 0, 0, $self->{real_w}, $self->{real_h}, -1);
        $image = $X->get_image_data_rgba($image->{sequence});

        return Gtk3::GdkPixbuf::Pixbuf->new_from_bytes(
            Glib::Bytes->new($image->{data}),   # data
            "rgb",                              # colorspace = RGB
            1,                                  # has alpha
            8,                                  # ASSertion bits_per_sample == 8 are you kidding?
            $self->{real_w},                    # width
            $self->{real_h},                    # height
            $self->{real_w} * 4,                # distance in bytes between rows aka rowstride
        );
    }
}

sub init {
    # Set up extension
    Glib::Object::Introspection->setup(basename => "GdkX11", version  => "3.0", package  => "Gtk3::Gdk");
    Glib::Object::Introspection->setup(basename => "GdkPixbuf", version  => "2.0", package  => "Gtk3::GdkPixbuf");
    $display = Gtk3::Gdk::Display::get_default();
    $font = Pango::FontDescription::from_string($cfg->{font});
    $color_fg = sprintf "#%x", $cfg->{color_fg};
    $color_bg = sprintf "#%x", $cfg->{color_bg};
    $color_expose = sprintf "#%x", $cfg->{color_expose};
    $color_gdk_fg = Gtk3::Gdk::RGBA::parse($color_fg);
    $color_gdk_bg = Gtk3::Gdk::RGBA::parse($color_bg);
    $color_gdk_expose = Gtk3::Gdk::RGBA::parse($color_expose);
}

push @X11::korgwm::extensions, \&init;

1;
