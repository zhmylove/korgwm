#!/usr/bin/perl
# made by: KorG
# vim: cc=119 et sw=4 ts=4 :
package X11::korgwm::Layout;
use strict;
use warnings;
use feature 'signatures';

use POSIX qw( ceil floor round );
use Storable qw( dclone );
use X11::korgwm::Common;
use X11::korgwm::Window;

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
            '0.5', <-- weight (column ratio, 0..1)
            '0.5', <-- vertical (row) ratio; 0.5 to split screen evenly
            '0.5'  <-- vertical (row) ratio for second window
        ],
        [
            '0.5', <-- this column has the same width as the first one
            '0.333333333333333', <-- all three windows have the same row ratio
            '0.333333333333333',
            '0.333333333333333'
        ]
    ];

User *maybe* will be able to change weights in their local copy of grid and
everything will work in the same way.

Layout also defines display order for tiled windows.  Default order depends
on the layout type: reverse order for grid, forward order for columns.
See API on how to change it dynamically.

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

# Implement dynamic grid
# +-----+-----+
# |     |     |
# +-----+-----+
# |     |     |
# +-----+-----+
sub _new_grid_layout($windows) {
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

# Implement simple columns layout
# +--+--+--+--+
# |  |  |  |  |
# |  |  |  |  |
# |  |  |  |  |
# +--+--+--+--+
sub _new_columns_layout($windows) {
    # Use default "grid" mode when there are a lot of windows
    return _new_grid_layout($windows) if $windows <= 2 or $windows > 7;

    # I don't want to make any algorithm to calculate these values, so just hardcode them
    return [ [0.34, 1], [0.33, 1       ], [0.33, 1       ]                   ] if $windows == 3;
    return [ [0.25, 1], [0.25, 1       ], [0.25, 1       ], [0.25, 1       ] ] if $windows == 4;
    return [ [0.25, 1], [0.25, 1       ], [0.25, 1       ], [0.25, 0.5, 0.5] ] if $windows == 5;
    return [ [0.25, 1], [0.25, 1       ], [0.25, 0.5, 0.5], [0.25, 0.5, 0.5] ] if $windows == 6;
    return [ [0.25, 1], [0.25, 0.5, 0.5], [0.25, 0.5, 0.5], [0.25, 0.5, 0.5] ] if $windows == 7;
}

# Implement very simple narrow layout for 1 or 2 windows
# +--+-----+--+
# |--|     |--|
# |--+-----+--|
# |--|     |--|
# +--+-----+--+
sub _new_narrow_layout($windows) {
    my $padding = 0.20;
    return [ [$padding], [1 - (2 * $padding), 1       ], [$padding] ] if $windows == 1;
    return [ [$padding], [1 - (2 * $padding), 0.5, 0.5], [$padding] ] if $windows == 2;

    # Fallback to a grid layout
    return _new_grid_layout($windows);
}

our %layouts = (
    grid => { func => \&_new_grid_layout, reverse_windows => 1 },
    columns => { func => \&_new_columns_layout, reverse_windows => 0 },
    narrow => { func => \&_new_narrow_layout, reverse_windows => 0 },
);

sub arrange_windows($self, $windows, $dpy_width, $dpy_height, $x_offset=0, $y_offset=0) {
    # Validate parameters
    croak "Cannot arrange non-windows" unless ref $windows eq "ARRAY";
    return if @{ $windows } < 1;
    croak "Trying to use non-initialized layout" unless defined $self->{grid};

    # dpy_* means display_
    my $nwindows = @{ $windows };
    my ($dpy_width_orig, $dpy_height_orig) = ($dpy_width, $dpy_height);

    # Create layout if needed
    my $grid = dclone($self->{grid}->[$nwindows - 1] //= $self->{func}->($nwindows));

    # Prepare windows and grid to zip them
    my @cols = reverse @{ $grid };
    my @windows = $self->{reverse_windows} ? reverse @{ $windows } : @{ $windows };
    my $hide_border = (1 == @windows and 1 == @screens);

    # Prepare $i, $j to save actual position
    my ($i, $j) = 0 + @cols;
    for my $col (@cols) {
        $i--;
        $j = @{ $col } - 1;
        my $col_w = shift @{ $col };
        my $width = floor($dpy_width_orig * $col_w);
        my $x = $dpy_width - $width;
        $x--, $width++ if $x == 1;

        for my $row_w (reverse @{ $col }) {
            $j--;
            my $height = floor($dpy_height_orig * $row_w);
            my $y = $dpy_height - $height;
            $y--, $height++ if $y == 1;

            # Extract next window
            my $win = shift @windows;
            croak "Window cannot be undef" unless defined $win;
            $win->resize_and_move($x + $x_offset, $y + $y_offset, $width, $height, $hide_border ? 0 : ());

            # Save real layout position in the window
            $win->{real_i} = $i;
            $win->{real_j} = $j;

            $dpy_height = $y;
        }

        $dpy_height = $dpy_height_orig;
        $dpy_width = $x;
    }
    $X->flush();
}

sub resize($self, $nwindows, $i, $j, $delta_x, $delta_y) {
    return if $i < 0 or $j < 0 or $nwindows < 0;

    my $grid = $self->{grid}->[$nwindows - 1];
    return unless defined $grid and @{ $grid } > $i + ($delta_x ? 1 : 0);

    my $col = $grid->[$i];
    return unless defined $col and @{ $col } > $j + ($delta_y ? 2 : 1);

    # left/right: just change col's weight
    if ($delta_x) {
        # Ignore change if columns are already too small
        next unless ($delta_x > 0 ? $grid->[$i + 1] : $grid->[$i])->[0] >= 0.2;

        $grid->[$i]->[0] += $delta_x;
        $grid->[$i + 1]->[0] -= $delta_x;
    }

    # up/down: change weight for all similar cols
    if ($delta_y) {
        my $col_size = @{ $col };

        for my $col (grep { $col_size == @{ $_ } } @{ $grid }) {
            next unless ($delta_y > 0 ? $col->[$j + 2] : $col->[$j + 1]) >= 0.2;

            $col->[$j + 1] += $delta_y;
            $col->[$j + 2] -= $delta_y;
        }
    }
}

sub new($self, %params) {
    my $layout = $layouts{ $params{func} // "grid" } or croak "Unknown layout: $params{func}";

    my $reverse_windows = $params{reverse_windows} // $layout->{reverse_windows};

    bless { grid => [], func => $layout->{func}, reverse_windows => $reverse_windows }, $self;
}

1;
