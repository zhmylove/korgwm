#!/usr/bin/perl
# vim: cc=119 et sw=4 ts=4 :
package X11::korgwm::Layout;
use strict;
use warnings;
use feature 'signatures';
use open ':std', ':encoding(UTF-8)';
use utf8;
use Carp;
use POSIX qw( ceil floor round );
use Storable qw( dclone );

use Data::Dumper;
$Data::Dumper::Sortkeys = 1;

=head1 DESCRIPTION

The idea behind this module lays in arranging the windows in a proper order.
There is a kind of "default" layout for any tag.
Each time user starts using a tag (i.e. creates first window on it), the layout
for this tag is being copied from the default one to a "working" one.
Then user can either close all windows on a tag resulting in this working
layout disposal, or change the layout sizes in several ways.

Working layout depends on the number of tiled windows in it: layout for a
single window differs with layout for many of them.

Based on number of windows, we need to get a "layout object", which could be
either altered in edge sizes, or handle a list of windows, configuring them one
by one to match the selected scheme.

Layout relies on grid division of the screen.  Firstly it divides the screen
into number of rows, then into columns.  "default" layout for 5 windows looks
like: 

    {
        'cols' => [
            '0.5',
            '0.5'
        ],
        'ncols' => 2,
        'nrows' => 3,
        'rows' => [
            '0.333333333333333',
            '0.333333333333333',
            '0.333333333333333'
        ]
    };

Then it's being translated into a grid, first element of each array is column's
weight.  Other elements -- rows weights inside this column.  For 5 windows the
grid will look like:

    [
        [
            '0.5',
            '0.5',
            '0.5'
        ],
        [
            '0.5',
            '0.333333333333333',
            '0.333333333333333',
            '0.333333333333333'
        ]
    ];

User *maybe* will be able to change weights in their local copy of grid and
everything will work in the same way.

=cut

sub _ncols($windows) {
    return 0 if $windows <= 0;
    return 2 if $windows == 5; # the only reasonable correction.
    ceil(sqrt($windows));
}

sub _nrows($windows) {
    return 0 if $windows <= 0;
    ceil($windows / _ncols($windows));
}

sub _new_layout($windows) {
    croak "Cannot create a layout for imaginary windows" if $windows <= 0;
    my $nrows = _nrows($windows);
    my $ncols = _ncols($windows);
    my $layout = {
        nrows => $nrows,
        ncols => $ncols,
        rows => [ map { 1 / $nrows } 1..$nrows ],
        cols => [ map { 1 / $ncols } 1..$ncols ],
    };
    my $grid = [ map { [ $_, @{ $layout->{rows} } ] } @{ $layout->{cols} } ];
    return $grid if $ncols == 1;

    # Compact first elements of the grid, firstly get extra elements:
    my $extra = $nrows * $ncols - $windows;

    # ... they're always in leftmost column:
    pop @{ $grid->[0] } for 1..$extra;

    # Maybe we should rebalance two first columns
    push @{ $grid->[0] }, pop @{ $grid->[1] } if @{ $grid->[1] } - @{ $grid->[0] } > 1;

    # Normalize elements in first two columns
    for my $arr (@{ $grid }[0, 1]) {
        @{ $arr } = (shift @{ $arr }, map { 1 / @$arr } 1..@{ $arr });
    }

    return $grid;
}

sub arrange_windows($self, $windows, $dpy_width, $dpy_height, $y_offset=0) {
    croak "Cannot arrange non-windows" unless ref $windows eq "ARRAY";
    croak "Cannot arrange imaginary windows" if @{ $windows } < 1;
    croak "Trying to use non-initialized layout" unless defined $self->{grid};
    my $nwindows = @{ $windows };
    my ($dpy_width_orig, $dpy_height_orig) = ($dpy_width, $dpy_height);
    my $grid = dclone($self->{grid}->[$nwindows - 1] //= _new_layout($nwindows));
    my @cols = reverse @{ $grid };
    my @windows = reverse @{ $windows };
    for my $col (@cols) {
        my $col_w = shift @{ $col };
        my $width = floor($dpy_width_orig * $col_w);
        my $x = $dpy_width - $width;
        $x--, $width++ if $x == 1;

        for my $row_w (@{ $col }) {
            my $height = floor($dpy_height_orig * $row_w);
            my $y = $dpy_height - $height;
            $y--, $height++ if $y == 1;
            $y += $y_offset; # reserved for panel

            my $win = shift @windows;
            croak "Window cannot be undef" unless defined $win;
            warn "win:$win x = $x, y = $y, width = $width, height = $height";

            $dpy_height = $y;
        }

        $dpy_height = $dpy_height_orig;
        $dpy_width = $x;
    }
}

sub new($self) {
    bless { grid => [] }, $self;
}

1;
