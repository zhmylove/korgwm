#!/usr/bin/perl
# made by: KorG
# vim: cc=119 et sw=4 ts=4 :
package X11::korgwm::Expose;
use strict;
use warnings;
use feature 'signatures';
use open ':std', ':encoding(UTF-8)';
use utf8;
use Carp;
use X11::XCB ':all';

use Data::Dumper;
$Data::Dumper::Sortkeys = 1;

use Glib::Object::Introspection;
use Gtk3 -init;

our ($X, $cfg, $windows, %screens);
*X = *X11::korgwm::X;
*cfg = *X11::korgwm::cfg;
*windows = *X11::korgwm::windows;
*screens = *X11::korgwm::screens;

my $display;
my $win_expose;
my $font;
my ($color_fg, $color_bg, $color_expose);
my ($color_gdk_fg, $color_gdk_bg, $color_gdk_expose);

sub _create_thumbnail($scale, $pixbuf, $title, $cb) {
    my $vbox = Gtk3::Box->new(vertical => 0);
    my $vbox_inner = Gtk3::Box->new(vertical => 0);

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

    # Place elements
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

    # Update pixbufs for all visible windows
    $_->_update_pixbuf() for map { $_->current_tag()->windows() } values %screens;

    # Select current screen
    my $screen_curr = $X11::korgwm::focus->{screen};

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
    my $windows = keys %{ $windows }; # TODO it is incorrect as one window could belong to several tags
    return unless $windows;
    my $rownum = _get_rownum($windows, @{ $screen_curr }{qw( w h )});
    my $scale = 0.9 * $screen_curr->{h} / $rownum;

    # Draw the windows
    for my $screen (values %screens) {
        for my $tag (@{ $screen->{tags} }) {
            for my $win ($tag->windows()) {
                my $ebox = _create_thumbnail($scale, $win->{pixbuf}, $win->title(), sub ($obj, $e) {
                    return unless $e->button == 1;
                    $screen->tag_set_active($tag->{idx}, 0);
                    $screen->set_active($win);
                    $win_expose->destroy();
                    $win_expose = undef;
                    $screen->refresh();
                });

                $x++, $y = 0 if $y >= $rownum;
                $grid->attach($ebox, $x, $y++, 1, 1);
            }
        }
    }

    # Map the window
    $win_expose->add($grid);
    $win_expose->show_all();
    $display->get_default_seat()->grab($win_expose->get_window(), "keyboard", 0, undef, undef, undef, undef);
}

# TODO consider adding this right into Window.pm
# Inverse approach is used in order to simplify Expose deletion / re-implementation
BEGIN {
    # Insert some pixbuf-specific methods 
    sub X11::korgwm::Window::_update_pixbuf($self) {
        my $win = Gtk3::Gdk::X11Window->foreign_new_for_display($display, $self->{id});
        $self->{pixbuf} = Gtk3::Gdk::pixbuf_get_from_window($win, 0, 0, @{ $self }{qw( real_w real_h )});
    }

    # Register hide hook
    push @X11::korgwm::Window::hooks_hide, sub($self) { $self->_update_pixbuf(); };
}

sub init {
    # Set up extension
    Glib::Object::Introspection->setup(basename => "GdkX11", version  => "3.0", package  => "Gtk3::Gdk");
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
